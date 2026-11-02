import 'dart:async';
import 'dart:convert';

import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_block.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_error.dart';

/// How an approval ended.
enum DappBridgeAnswer {
  /// The person pressed the approving button.
  approved,

  /// The person pressed Decline.
  declined,

  /// Nobody answered: the wallet locked and took the approval down, or it
  /// could not be shown at all. It is not a decline, so the origin is not
  /// held back for it.
  dismissed,
}

/// What the service needs from the wallet. The app implements it with its
/// dialogs and its signer; the tests with a fake, so the rules in
/// [DappBridgeService] are checked without a window.
abstract class DappBridgeWallet {
  /// The selected address, or null while the wallet is locked.
  String? get selectedAddress;

  /// The chain identifier the wallet signs with.
  int get chainId;

  /// The node the wallet is connected to, as configured.
  String? get nodeUrl;

  /// Brings the wallet forward and completes once it is unlocked. Throws a
  /// [DappBridgeError] when that does not happen in time.
  Future<void> waitUnlocked();

  /// Asks the person whether [origin] may see [address] and ask it to sign.
  /// Throws [DappBridgeError.expired] when nobody answers in time.
  Future<DappBridgeAnswer> approveConnect(String origin, String address);

  /// Asks the person whether to sign [message] for [origin]. Throws
  /// [DappBridgeError.expired] when nobody answers in time.
  Future<DappBridgeAnswer> approveSign(
    String origin,
    String address,
    String message,
  );

  /// Signs the UTF-8 bytes of [message] with [address]. Returns the public
  /// key and the signature, hex.
  Future<({String publicKey, String signature})> sign(
    String address,
    String message,
  );

  /// Shows [block] to the person in full and asks whether to send it from
  /// [address] for [origin]. Throws [DappBridgeError.expired] when nobody
  /// answers in time.
  Future<DappBridgeAnswer> approveSend(
    String origin,
    String address,
    DappBridgeBlock block,
  );

  /// Publishes [block] from [address]. Returns `{hash, block}`.
  ///
  /// Approving and sending are two calls so that the service, not each
  /// wallet, checks between them that the request still stands.
  Future<Map<String, Object?>> send(
    String origin,
    String address,
    DappBridgeBlock block,
  );
}

/// Which origins the person has connected, per address. Switching to an
/// address an origin was never shown does not carry the consent over.
abstract class DappBridgeConsent {
  /// Whether [origin] is connected to [address].
  bool has(String origin, String address);

  /// Whether [origin] is connected to any address. It can be answered while
  /// the wallet is locked, so an origin nobody connected is refused without
  /// the wallet being raised for it.
  bool hasAny(String origin);

  /// Records the connection.
  Future<void> grant(String origin, String address);

  /// Withdraws [origin] from every address.
  Future<void> revoke(String origin);
}

/// A production store can bind a decision to one original grant incarnation.
abstract interface class DappBridgeCapturedConsent {
  /// Reads the current address grant without prompting or mutating consent.
  bool has(String origin, String address);

  /// Captures the original preferences Box and requester grant incarnation.
  DappBridgeConsentReceipt captureConsent(String origin);
}

/// Queued decisions never recapture another wallet's preferences or grant.
abstract interface class DappBridgeConsentReceipt {
  /// Whether the original Box and predecision grant incarnation remain current.
  bool get isCurrent;

  /// Whether the committed outcome still belongs to that original requester.
  bool get outcomeIsCurrent;

  /// Grants one approved address only to this captured requester generation.
  Future<void> grant(String address);

  /// Persists this exact revocation before any disconnect notification.
  Future<void> revoke({bool Function()? isCurrent});
}

/// Sends a notification to the sockets of an origin.
typedef DappBridgeEmit =
    void Function(
      String event,
      Object? params, {
      String? origin,
    });

/// Approvals that may wait on the person at once: the extension's number.
const int kDappBridgeMaxPending = 16;

/// How long an origin waits after the person declines before it may raise
/// another approval. The extension's number.
///
/// Without it a page answers every decline with the same request, and the
/// person never gets the wallet back: the approval is modal.
const Duration kDappBridgeDeclineCooldown = Duration(seconds: 30);

/// The longest message `znn_sign` takes, in UTF-16 code units.
const int kDappBridgeMaxSignMessage = 8192;

/// The methods of the page-to-desktop channel, with the same names, params,
/// results and refusals as the Syrius extension's `window.zenon` and the
/// Android app's `syrius://request`, so a page speaks to all three alike.
class DappBridgeService {
  /// Creates the service over [_wallet] and [_consent].
  DappBridgeService({
    required this._wallet,
    required this._consent,
    this._now = DateTime.now,
  });

  final DappBridgeWallet _wallet;
  final DappBridgeConsent _consent;
  final DateTime Function() _now;
  final Set<String> _pending = <String>{};
  final Map<String, DateTime> _declined = <String, DateTime>{};
  final Map<String, List<String>> _seenAccounts = <String, List<String>>{};
  bool _seenWallet = false;
  int? _seenChainId;
  String? _seenNodeUrl;

  /// Set by whoever owns the server, so events reach the pages.
  DappBridgeEmit? emit;

  /// Answers one request. The signature is a `DappBridgeHandler`.
  Future<Object?> handle(String origin, String method, Object? params) async {
    switch (method) {
      case 'znn_accounts':
        return _accounts(origin);
      case 'znn_chainId':
        return _connected(origin) ? _wallet.chainId : null;
      case 'znn_nodeUrl':
        return _connected(origin) ? publicNodeUrl(_wallet.nodeUrl) : null;
      case 'znn_connect':
        return _prompted(origin, () => _connect(origin));
      case 'znn_disconnect':
        await revoke(origin);
        return true;
      case 'znn_sign':
        return _prompted(origin, () => _sign(origin, params));
      case 'znn_sendTransaction':
        return _prompted(origin, () => _sendTransaction(origin, params));
      case 'znn_signAndSendBlock':
        return _prompted(origin, () => _sendBlock(origin, params));
      default:
        throw const DappBridgeError.unknownMethod();
    }
  }

  /// Withdraws [origin] and tells its pages they see no account. Called for
  /// a page's own `znn_disconnect` and for Disconnect in the wallet.
  Future<void> revoke(String origin) async {
    final DappBridgeConsent consent = _consent;
    final DappBridgeConsentReceipt? receipt =
        consent is DappBridgeCapturedConsent
        ? (consent as DappBridgeCapturedConsent).captureConsent(origin)
        : null;
    if (receipt != null) {
      return revokeReceipt(origin, receipt);
    }
    await consent.revoke(origin);
    _seenAccounts[origin] = <String>[];
    emit?.call('accountsChanged', <String>[], origin: origin);
  }

  /// The row's original receipt is captured before any queued persistence.
  Future<void> revokeReceipt(
    String origin,
    DappBridgeConsentReceipt receipt, {
    bool Function()? isCurrent,
  }) async {
    await receipt.revoke(isCurrent: isCurrent);
    if (!receipt.outcomeIsCurrent) return;
    _seenAccounts[origin] = <String>[];
    emit?.call('accountsChanged', <String>[], origin: origin);
  }

  /// Tells the pages of [origins] what changed in what they may see: the
  /// account after a lock, an unlock or another address, and the chain and
  /// the node after the person changes them.
  ///
  /// Only a change is sent. The first sight of an origin, or of the wallet,
  /// is recorded and not announced: a page reads its starting state.
  void walletChanged(Iterable<String> origins) {
    final int chainId = _wallet.chainId;
    final String? nodeUrl = publicNodeUrl(_wallet.nodeUrl);
    final bool chainChanged = _seenWallet && chainId != _seenChainId;
    final bool nodeChanged = _seenWallet && nodeUrl != _seenNodeUrl;
    _seenWallet = true;
    _seenChainId = chainId;
    _seenNodeUrl = nodeUrl;

    final Set<String> open = origins.toSet();
    _seenAccounts.removeWhere((String origin, _) => !open.contains(origin));
    for (final String origin in open) {
      final List<String> accounts = _accounts(origin);
      final List<String>? before = _seenAccounts[origin];
      _seenAccounts[origin] = accounts;
      if (before != null && before.join() != accounts.join()) {
        emit?.call('accountsChanged', accounts, origin: origin);
      }
      // An origin that sees no account is told nothing about the wallet.
      if (accounts.isEmpty) {
        continue;
      }
      if (chainChanged) {
        emit?.call('chainChanged', chainId, origin: origin);
      }
      if (nodeChanged) {
        emit?.call('nodeChanged', nodeUrl, origin: origin);
      }
    }
  }

  List<String> _accounts(String origin) {
    final String? address = _wallet.selectedAddress;
    return address != null && _consent.has(origin, address)
        ? <String>[address]
        : <String>[];
  }

  bool _connected(String origin) => _accounts(origin).isNotEmpty;

  /// One approval per origin at a time: a second would stack a dialog the
  /// person has not asked for on top of the one they are reading.
  Future<Object?> _prompted(
    String origin,
    Future<Object?> Function() run,
  ) async {
    if (_pending.contains(origin) || _pending.length >= kDappBridgeMaxPending) {
      throw const DappBridgeError.busy();
    }
    _pending.add(origin);
    try {
      return await run();
    } finally {
      _pending.remove(origin);
    }
  }

  /// Refuses an approval for [origin] while its last decline is recent.
  void _checkCooldown(String origin) {
    final DateTime? declined = _declined[origin];
    if (declined == null) {
      return;
    }
    if (_now().difference(declined) < kDappBridgeDeclineCooldown) {
      throw const DappBridgeError.busy('Declined a moment ago. Try later');
    }
    _declined.remove(origin);
  }

  void _noteDecline(String origin) {
    // Bounded: an entry is dropped once its cooldown is over.
    final DateTime now = _now();
    _declined
      ..removeWhere(
        (_, DateTime at) => now.difference(at) >= kDappBridgeDeclineCooldown,
      )
      ..[origin] = now;
  }

  /// Ends the request unless the person approved it. Only a decline they
  /// made starts the cooldown: an approval the lock took down is answered as
  /// a locked wallet is, and the page may ask again at once.
  void _approved(String origin, DappBridgeAnswer answer) {
    switch (answer) {
      case DappBridgeAnswer.approved:
        return;
      case DappBridgeAnswer.declined:
        _noteDecline(origin);
        throw const DappBridgeError.declined();
      case DappBridgeAnswer.dismissed:
        throw const DappBridgeError.locked();
    }
  }

  Future<String> _unlockedAddress() async {
    await _wallet.waitUnlocked();
    final String? address = _wallet.selectedAddress;
    if (address == null) {
      throw const DappBridgeError.locked();
    }
    return address;
  }

  /// The address [origin] is connected to. A request from an origin that is
  /// not connected is refused before the wallet is raised or any prompt is
  /// shown.
  Future<String> _connectedAddress(String origin) async {
    if (!_consent.hasAny(origin)) {
      throw const DappBridgeError.notConnected();
    }
    final String address = await _unlockedAddress();
    _stillConnected(origin, address);
    return address;
  }

  void _stillConnected(String origin, String address) {
    if (!_consent.has(origin, address)) {
      throw const DappBridgeError.notConnected();
    }
  }

  /// What the person approved was [address] acting for [origin]. Run after
  /// every approval and before the key is used: the page may have
  /// disconnected, the wallet may have locked, or another address may have
  /// been selected while the approval was up, and signing then is not what
  /// was approved.
  void _stillApproved(String origin, String address) {
    _stillConnected(origin, address);
    if (_wallet.selectedAddress != address) {
      throw const DappBridgeError.locked('The account changed. Ask again');
    }
  }

  Future<Object?> _connect(String origin) async {
    if (!_consent.hasAny(origin)) {
      // Before the wallet is raised: a page that was just declined does not
      // get to bring the window forward again either.
      _checkCooldown(origin);
    }
    final String address = await _unlockedAddress();
    final int chain = _wallet.chainId;
    final String? node = _wallet.nodeUrl;
    final DappBridgeConsent consent = _consent;
    final DappBridgeConsentReceipt? receipt =
        consent is DappBridgeCapturedConsent
        ? (consent as DappBridgeCapturedConsent).captureConsent(origin)
        : null;
    if (!_consent.has(origin, address)) {
      _checkCooldown(origin);
      _approved(origin, await _wallet.approveConnect(origin, address));
      // The selection may have changed while the dialog was up. What was
      // approved is the address that was shown.
      if (_wallet.selectedAddress != address ||
          _wallet.chainId != chain ||
          _wallet.nodeUrl != node ||
          (receipt != null && !receipt.isCurrent)) {
        throw const DappBridgeError.locked('The account changed. Ask again');
      }
      await (receipt?.grant(address) ?? consent.grant(origin, address));
      if (receipt != null && !receipt.outcomeIsCurrent) {
        throw const DappBridgeError.notConnected();
      }
    }
    final List<String> accounts = _accounts(origin);
    _seenAccounts[origin] = accounts;
    emit?.call('accountsChanged', accounts, origin: origin);
    return accounts;
  }

  Future<Object?> _sign(String origin, Object? params) async {
    // A bare string is taken too, as the extension does.
    final Object? message = params is String
        ? params
        : params is Map
        ? params['message']
        : null;
    if (message is! String ||
        message.isEmpty ||
        message.length > kDappBridgeMaxSignMessage) {
      throw const DappBridgeError.invalidParams('message must be text');
    }
    // 32 bytes is the size of an account block hash. Signing raw bytes of
    // that length would let a page have a transaction signed by calling it a
    // message.
    if (utf8.encode(message).length == 32) {
      throw const DappBridgeError.invalidParams(
        'A 32 byte message is refused. Pad it',
      );
    }
    final String address = await _connectedAddress(origin);
    final DappBridgeConsent consent = _consent;
    final DappBridgeConsentReceipt? receipt =
        consent is DappBridgeCapturedConsent
        ? (consent as DappBridgeCapturedConsent).captureConsent(origin)
        : null;
    final int chain = _wallet.chainId;
    final String? node = _wallet.nodeUrl;
    _checkCooldown(origin);
    _approved(origin, await _wallet.approveSign(origin, address, message));
    _stillApproved(origin, address);
    if ((receipt != null && !receipt.isCurrent) ||
        chain != _wallet.chainId ||
        node != _wallet.nodeUrl) {
      throw const DappBridgeError.notConnected();
    }
    final ({String publicKey, String signature}) signed = await _wallet.sign(
      address,
      message,
    );
    return <String, Object?>{
      'message': message,
      'address': address,
      'publicKey': signed.publicKey,
      'signature': signed.signature,
    };
  }

  Future<Object?> _sendTransaction(String origin, Object? params) {
    final Object? to = params is Map ? params['to'] : null;
    final Object? tokenStandard = params is Map
        ? params['tokenStandard']
        : null;
    final Object? amount = params is Map ? params['amount'] : null;
    // An amount left out is not zero here, as it is in a block: a transfer
    // that names no amount is a mistake in the page.
    if (to is! String ||
        tokenStandard is! String ||
        (amount is! String && amount is! int)) {
      throw const DappBridgeError.invalidParams(
        'to and tokenStandard must be strings, amount a string or an integer',
      );
    }
    return _send(
      origin,
      DappBridgeBlock.parse(<String, Object?>{
        'toAddress': to,
        'tokenStandard': tokenStandard,
        'amount': amount,
      }),
    );
  }

  Future<Object?> _sendBlock(String origin, Object? params) {
    if (params is! Map) {
      throw const DappBridgeError.invalidParams('An account block is expected');
    }
    return _send(origin, DappBridgeBlock.parse(params));
  }

  Future<Object?> _send(String origin, DappBridgeBlock block) async {
    final String address = await _connectedAddress(origin);
    final DappBridgeConsent consent = _consent;
    final DappBridgeConsentReceipt? receipt =
        consent is DappBridgeCapturedConsent
        ? (consent as DappBridgeCapturedConsent).captureConsent(origin)
        : null;
    final int chain = _wallet.chainId;
    final String? node = _wallet.nodeUrl;
    _checkCooldown(origin);
    _approved(origin, await _wallet.approveSend(origin, address, block));
    _stillApproved(origin, address);
    if ((receipt != null && !receipt.isCurrent) ||
        chain != _wallet.chainId ||
        node != _wallet.nodeUrl) {
      throw const DappBridgeError.notConnected();
    }
    return _wallet.send(origin, address, block);
  }
}

/// The node as a page may know it: scheme, host and a port that is not the
/// default. Credentials, path, query and fragment stay in the wallet, since a
/// private endpoint often carries its key there.
String? publicNodeUrl(String? nodeUrl) {
  final Uri? uri = nodeUrl == null ? null : Uri.tryParse(nodeUrl);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  if (uri.scheme != 'ws' && uri.scheme != 'wss') {
    return null;
  }
  final int defaultPort = uri.scheme == 'wss' ? 443 : 80;
  final String port = uri.hasPort && uri.port != defaultPort
      ? ':${uri.port}'
      : '';
  return '${uri.scheme}://${uri.host}$port';
}
