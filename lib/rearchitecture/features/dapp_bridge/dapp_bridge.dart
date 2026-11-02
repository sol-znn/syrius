import 'dart:async';

import 'package:hex/hex.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_block.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_channel.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_consent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_error.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_link.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_origin.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_service.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/view/dapp_bridge_approval.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart'
    show kSharedPrefsBox;
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/functions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/main_app_container.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

export 'cubit/connected_sites_cubit.dart';
export 'cubit/dapp_bridge_switch_cubit.dart';
export 'server/dapp_bridge_block.dart';
export 'server/dapp_bridge_channel.dart';
export 'server/dapp_bridge_consent.dart';
export 'server/dapp_bridge_error.dart';
export 'server/dapp_bridge_link.dart';
export 'server/dapp_bridge_origin.dart';
export 'server/dapp_bridge_server.dart';
export 'server/dapp_bridge_service.dart';
export 'view/connected_sites.dart';
export 'view/dapp_bridge_approval.dart';
export 'view/dapp_bridge_switch.dart';

/// Where the first build kept consent. Nothing was released with it; it is
/// deleted so no consent outlives the move into the settings box.
const String _kLegacyConsentBox = 'dapp_bridge_consent_box';

/// How long a request waits for the person to unlock the wallet.
const Duration _kUnlockWait = Duration(minutes: 5);

/// How long the approval waits for the node to name a token before it shows
/// the raw amount and the token standard instead.
const Duration _kTokenLookup = Duration(seconds: 5);

/// The page-to-desktop channel as the app runs it: a [DappBridgeChannel]
/// wired to this wallet's dialogs, signer and settings box.
/// See `docs/research/webapp-to-syrius.md` for why it is a loopback socket,
/// and `docs/webapp-integration.md` for what a page sends it.
class DappBridge implements DappBridgeControl, DappBridgeOwnedControl {
  DappBridge._() {
    DappBridgeControl.app = this;
  }

  /// The one channel of this process.
  static final DappBridge instance = DappBridge._();

  final Logger _logger = Logger('DappBridge');

  late final DappBridgeChannel _channel = DappBridgeChannel(
    wallet: _AppWallet(),
    store: _SettingsStore(),
    open: (Uri url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('not opened');
      }
    },
  );

  @override
  bool get enabled => _channel.enabled;

  @override
  int? get port => _channel.port;

  @override
  List<DappBridgeSite> get sites => _channel.sites;

  @override
  Stream<void> get changes => _channel.changes;

  @override
  Future<void> setEnabled({required bool enabled}) =>
      _channel.setEnabled(enabled: enabled);

  @override
  Future<void> disconnect(String requester) => _channel.disconnect(requester);

  @override
  DappBridgeActions captureActions() => _channel.captureActions();

  /// Starts listening, unless the person has turned the channel off.
  Future<void> start() async {
    try {
      if (await Hive.boxExists(_kLegacyConsentBox)) {
        await Hive.deleteBoxFromDisk(_kLegacyConsentBox);
      }
    } on Object catch (e, s) {
      _logger.warning('old consent box not deleted', e, s);
    }
    await _channel.start();
  }

  /// Stops listening and closes every page's socket.
  Future<void> stop() => _channel.stop();

  /// To be called when the selected address changes or the page changes, so
  /// connected pages learn which account they now see.
  void selectionChanged() => _channel.walletChanged();

  /// Takes [link] when it is a `syrius://request`, and answers it in the
  /// background. Returns whether it was one, so the caller can stop there.
  bool handleLink(Uri link) {
    if (!isDappBridgeLink(link)) {
      return false;
    }
    unawaited(_channel.handleLink(link));
    return true;
  }
}

bool get _unlocked =>
    kWalletFile != null &&
    kSelectedAddress != null &&
    kCurrentPage != null &&
    kCurrentPage != Tabs.lock;

/// The wallet's settings box. A wallet reset deletes it, and with it every
/// site's consent.
class _SettingsStore implements DappBridgeCapturedStore {
  @override
  Object get identity => this;

  @override
  bool get isCurrent => true;

  @override
  Object? read(String key) => sharedPrefsService?.get(key);

  @override
  Future<void> write(String key, Object? value) => capture().write(key, value);

  @override
  DappBridgeStore capture() {
    final SharedPrefsService prefs =
        sharedPrefsService ?? (throw StateError('settings are not open'));
    if (!Hive.isBoxOpen(kSharedPrefsBox)) {
      throw StateError('settings are not open');
    }
    final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
    final Object? wallet = kWalletFile;
    final int revision = WalletContextRevision.value;
    return _CapturedSettingsStore(
      box,
      () =>
          identical(prefs, sharedPrefsService) &&
          identical(wallet, kWalletFile) &&
          revision == WalletContextRevision.value &&
          Hive.isBoxOpen(kSharedPrefsBox) &&
          identical(box, Hive.box<dynamic>(kSharedPrefsBox)),
    );
  }
}

/// A queued write never reopens or looks up a replacement preferences box.
class _CapturedSettingsStore implements DappBridgeCapturedStore {
  _CapturedSettingsStore(this.box, this._owns);
  final Box<dynamic> box;
  final bool Function() _owns;
  bool _revoked = false;

  @override
  DappBridgeStore capture() => this;

  @override
  Object get identity => box;

  @override
  bool get isCurrent => !_revoked && !(_revoked = !box.isOpen || !_owns());

  @override
  Object? read(String key) => box.isOpen ? box.get(key) : null;

  @override
  Future<void> write(String key, Object? value) {
    if (!isCurrent) throw StateError('settings are not open');
    return box.put(key, value);
  }
}

class _AppWallet implements DappBridgeWallet {
  @override
  String? get selectedAddress => _unlocked ? kSelectedAddress : null;

  @override
  int get chainId => getChainIdentifier();

  @override
  String? get nodeUrl => kCurrentNode;

  @override
  Future<void> waitUnlocked() async {
    await _bringForward();
    final DateTime deadline = DateTime.now().add(_kUnlockWait);
    while (!_unlocked) {
      if (DateTime.now().isAfter(deadline)) {
        throw const DappBridgeError.locked();
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Future<DappBridgeAnswer> approveConnect(String origin, String address) =>
      _ask(
        title: 'Connect this site?',
        origin: origin,
        action: 'Connect',
        rows: <(String, String)>[
          ('Address', address),
          ('It can', 'See this address and ask you to sign'),
        ],
      );

  @override
  Future<DappBridgeAnswer> approveSign(
    String origin,
    String address,
    String message,
  ) => _ask(
    title: 'Sign this message?',
    origin: origin,
    action: 'Sign',
    rows: <(String, String)>[
      ('Address', address),
      ('Message', message),
    ],
  );

  @override
  Future<({String publicKey, String signature})> sign(
    String address,
    String message,
  ) async {
    // The service has checked the selected address and unlocked session.
    // The signer retains that original wallet and account across acquisition
    // and release. This final check keeps a signature inside the wallet
    // unless its key belongs to the address approved by the caller.
    final Signature signed = await walletSignMessage(message);
    final String signer = Address.fromPublicKey(
      HEX.decode(signed.publicKey),
    ).toString();
    if (signer != address) {
      throw const DappBridgeError.locked('The account changed. Ask again');
    }
    return (publicKey: signed.publicKey, signature: signed.signature);
  }

  @override
  Future<DappBridgeAnswer> approveSend(
    String origin,
    String address,
    DappBridgeBlock block,
  ) async {
    String shownAmount = '${block.amount} (smallest unit)';
    String symbol = block.tokenStandard.toString();
    try {
      final Token? token = await zenon!.embedded.token
          .getByZts(block.tokenStandard)
          .timeout(_kTokenLookup);
      if (token != null) {
        shownAmount = block.amount.addDecimals(token.decimals);
        symbol = '${token.symbol} (${block.tokenStandard})';
      }
    } on Object {
      // Shown raw. The person still sees the exact amount and the standard.
    }
    return _ask(
      title: block.data.isEmpty ? 'Send this?' : 'Call this contract?',
      origin: origin,
      action: 'Send',
      rows: <(String, String)>[
        ('From', address),
        ('To', block.toAddress.toString()),
        ('Amount', shownAmount),
        ('Token', symbol),
        if (block.data.isNotEmpty)
          (
            'Data, ${block.data.length} bytes',
            BytesUtils.bytesToHex(block.data),
          ),
      ],
    );
  }

  @override
  Future<Map<String, Object?>> send(
    String origin,
    String address,
    DappBridgeBlock block,
  ) async {
    final SendTransactionBloc bloc = SendTransactionBloc()
      ..add(
        SendTransactionInitiateFromBlock(
          block: AccountBlockTemplate.callContract(
            block.toAddress,
            block.tokenStandard,
            block.amount,
            block.data,
          ),
          fromAddress: address,
          reasonForGeneratingPlasma: plasmaPurposeSendForDapp(
            dappBridgeShownOrigin(origin),
          ),
        ),
      );
    final SendTransactionState result = await bloc.stream.firstWhere(
      (SendTransactionState state) =>
          state.status == SendTransactionStatus.success ||
          state.status == SendTransactionStatus.failure,
    );
    unawaited(bloc.close());
    final AccountBlockTemplate? sent = result.data;
    if (result.status != SendTransactionStatus.success || sent == null) {
      // The wallet's own error can carry the node's URL, key and all, so the
      // page gets a fixed line and the log gets the rest.
      Logger('DappBridge').warning('send for $origin failed', result.error);
      throw const DappBridgeError.locked(
        'Not sent, or the outcome is unknown. Check the account',
      );
    }
    return <String, Object?>{
      'hash': sent.hash.toString(),
      'block': sent.toJson(),
    };
  }

  Future<void> _bringForward() async {
    if (!await windowManager.isFocused() || !await windowManager.isVisible()) {
      await windowManager.show();
    }
  }

  Future<DappBridgeAnswer> _ask({
    required String title,
    required String origin,
    required String action,
    required List<(String, String)> rows,
  }) async {
    await _bringForward();
    final NavigatorState? navigator = globalNavigatorKey.currentState;
    if (navigator == null || !navigator.mounted || !_unlocked) {
      // Never shown, so nobody declined it.
      return DappBridgeAnswer.dismissed;
    }
    return showDappBridgeApproval(
      navigator,
      title: title,
      requester: origin,
      action: action,
      rows: rows,
      // Asked again when its turn comes: the wallet may have locked while
      // another approval was on screen.
      stillWanted: () => _unlocked,
    );
  }
}
