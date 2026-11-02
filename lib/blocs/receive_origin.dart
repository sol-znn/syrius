import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A known refusal before a receive has entered the shared sender.
class ReceiveRefused implements Exception {
  /// Refuses without exposing the wallet or transport that lost authority.
  const ReceiveRefused();
}

/// An original SDK response that cannot establish this exact receive.
class ReceiveUnknownResult implements Exception {
  /// Keeps the actual SDK answer for recovery without authorizing a retry.
  const ReceiveUnknownResult(this.result);

  /// The identical original result, including its unmodified SDK block.
  final SendRequestResult result;
}

/// Original receive authority and independently bound read transports.
class ReceiveOrigin {
  /// Explicit sources support finite fixtures without wallets or RPC services.
  ReceiveOrigin({
    required this.sender,
    required this.ledger,
    required this.stats,
    required this.chainId,
    required this.nodeChainId,
    required this.selectedAddress,
    required Iterable<String> addresses,
    required this._isCurrent,
    this._readInbound,
    this._readSync,
  }) : addresses = List<String>.unmodifiable(addresses);

  /// WalletActionContext retains file, path, selection, node and revision.
  factory ReceiveOrigin.wallet({
    required WalletActionContext action,
    required SendTransactionBloc sender,
    required int chainId,
    required int nodeChainId,
    required Iterable<String> addresses,
    required bool Function() isCurrent,
  }) {
    final LedgerApi ledger = action.client.ledger;
    final StatsApi stats = action.client.stats;
    return ReceiveOrigin.boundApis(
      sender: sender,
      ledgerSource: ledger,
      statsSource: stats,
      chainId: chainId,
      nodeChainId: nodeChainId,
      selectedAddress: action.ownerAddress,
      addresses: addresses,
      isCurrent: () =>
          action.isCurrent &&
          identical(action.client.ledger, ledger) &&
          identical(action.client.stats, stats) &&
          isCurrent(),
    );
  }

  /// Rebinding shared API objects cannot redirect a deferred original read.
  factory ReceiveOrigin.boundApis({
    required SendTransactionBloc sender,
    required LedgerApi ledgerSource,
    required StatsApi statsSource,
    required int chainId,
    required int nodeChainId,
    required String selectedAddress,
    required Iterable<String> addresses,
    required bool Function() isCurrent,
  }) {
    final Client ledgerClient = ledgerSource.client;
    final Client statsClient = statsSource.client;
    final String? ledgerUrl = ledgerClient is WsClient
        ? ledgerClient.url
        : null;
    final String? statsUrl = statsClient is WsClient ? statsClient.url : null;
    final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
    final StatsApi stats = StatsApi()..setClient(statsClient);
    return ReceiveOrigin(
      sender: sender,
      ledger: ledger,
      stats: stats,
      chainId: chainId,
      nodeChainId: nodeChainId,
      selectedAddress: selectedAddress,
      addresses: addresses,
      isCurrent: () =>
          isCurrent() &&
          identical(ledgerSource.client, ledgerClient) &&
          identical(statsSource.client, statsClient) &&
          identical(ledger.client, ledgerClient) &&
          identical(stats.client, statsClient) &&
          (ledgerClient is! WsClient || ledgerClient.url == ledgerUrl) &&
          (statsClient is! WsClient || statsClient.url == statsUrl),
    );
  }

  /// The original shared sender attachment.
  final SendTransactionBloc sender;

  /// Independently bound original account-block reader.
  final LedgerApi ledger;

  /// Independently bound original synchronization reader.
  final StatsApi stats;

  /// The captured signing chain, never inferred from a missing node reply.
  final int chainId;

  /// The positively observed node chain that must match the signer.
  final int nodeChainId;

  /// The account selected when this receive origin was captured.
  final String selectedAddress;

  /// Immutable original membership used to authorize inbound destinations.
  final List<String> addresses;
  final bool Function() _isCurrent;
  final Future<AccountBlock?> Function(Hash)? _readInbound;
  final Future<SyncInfo> Function()? _readSync;
  bool _revoked = false;

  /// Once observed revoked, returning to old global values cannot restore it.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final bool lost =
          chainId <= 0 ||
          chainId != nodeChainId ||
          !addresses.contains(selectedAddress) ||
          addresses.toSet().length != addresses.length ||
          addresses.any(
            (String value) => Address.parse(value).toString() != value,
          ) ||
          !_isCurrent();
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Rechecks original authority before the next read or publication step.
  void requireCurrent() {
    if (!isCurrent) throw const ReceiveRefused();
  }

  /// Reads the exact inbound through the captured original ledger transport.
  Future<AccountBlock?> readInbound(Hash hash) {
    requireCurrent();
    return _readInbound?.call(hash) ?? ledger.getAccountBlockByHash(hash);
  }

  /// Reads synchronization through the captured original stats transport.
  Future<SyncInfo> readSync() {
    requireCurrent();
    return _readSync?.call() ?? stats.syncInfo();
  }

  /// Constructor defaults cannot substitute a later global signing chain.
  AccountBlockTemplate receiveBlock(Hash inboundHash) {
    requireCurrent();
    return AccountBlockTemplate.receive(Hash.parse(inboundHash.toString()))
      ..chainIdentifier = chainId;
  }
}
