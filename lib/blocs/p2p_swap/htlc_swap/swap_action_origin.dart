import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_binding.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A fixed refusal is safe for display; original errors stay in the journal.
class SwapActionRefused implements Exception {
  /// Names a source fact, never a wallet path, secret or native diagnostic.
  const SwapActionRefused(this.reason);

  /// Fixed source-fact code, suitable for mapping to localized interface text.
  final String reason;
}

/// The original SDK publication, captured before an action's first read.
typedef SwapPublisher =
    Future<AccountBlockTemplate> Function(
      AccountBlockTemplate block,
      String purpose,
    );

/// A reserved original store write, independent of the action view's lifetime.
abstract interface class SwapPersistenceReservation {
  /// Returns the actual original backend write Future.
  Future<void> store(HtlcSwap swap);

  /// Releases a positively known refusal before publication was invoked.
  void refuse();

  /// Keeps unknown publication or persistence held without a timer or retry.
  void retainUnknown(Object error, StackTrace trace);
}

/// A durable original publication hold in the encrypted recovery backend.
abstract interface class SwapPublicationReservation {
  /// Writes and flushes a private original hold before any signer invocation.
  Future<void> prepare({Map<String, dynamic>? recovery});

  /// Retains the exact accepted hash in that original durable hold.
  Future<void> accepted(String exactHash);

  /// Settles known prepublication refusal; uncertain writes remain failures.
  Future<void> refuseBeforePublication();

  /// Settles the terminal receipt negatively while retaining possible effects.
  void retainUnknown(Object error, StackTrace trace);
}

class _PublicationReservation implements SwapPublicationReservation {
  _PublicationReservation(this.original);
  final HtlcActionWriteRequest original;

  @override
  Future<void> prepare({Map<String, dynamic>? recovery}) =>
      original.prepare(recovery: recovery);
  @override
  Future<void> accepted(String exactHash) => original.accepted(exactHash);
  @override
  Future<void> refuseBeforePublication() => original.refuseBeforePublication();
  @override
  void retainUnknown(Object error, StackTrace trace) =>
      original.retainUnknown(error, trace);
}

class _StoreReservation implements SwapPersistenceReservation {
  _StoreReservation(this.original);
  final HtlcStoreWriteRequest original;

  @override
  Future<void> store(HtlcSwap swap) => original.storeSwap(swap);

  @override
  void refuse() => original.refuse();

  @override
  void retainUnknown(Object error, StackTrace trace) =>
      original.retainUnknown(error, trace);
}

/// All reads, signer admission and persistence belong to one original wallet.
/// Injected origins have no filesystem, network or real signer.
class SwapActionOrigin {
  /// Freezes membership and the original operation capabilities.
  SwapActionOrigin({
    required this.identity,
    required this.chainId,
    required this.ownerAddress,
    required Iterable<String> members,
    required this._isCurrent,
    required this.readHtlc,
    required this.readBlock,
    required this._readChainTime,
    required this.readAccount,
    required this.readToken,
    required this.readHistory,
    required this.readContractBlocks,
    required this.reserveStore,
    required this.reservePublication,
    required this.rearmStart,
    required this.capturePublisher,
    required this.create,
    required this.unlock,
    required this.reclaim,
  }) : members = Set<String>.unmodifiable(members);

  /// Captures actual APIs and independently bound clients before any await.
  static SwapActionOrigin? capture({bool Function()? sourceIsCurrent}) {
    try {
      return _capture(sourceIsCurrent: sourceIsCurrent);
    } on Object {
      return null;
    }
  }

  static SwapActionOrigin? _capture({bool Function()? sourceIsCurrent}) {
    final String? selected = kSelectedAddress;
    final int? chain = kNodeChainId;
    if (selected == null ||
        chain == null ||
        chain <= 0 ||
        chain != getChainIdentifier()) {
      return null;
    }
    final WalletActionContext? scope = WalletActionContext.capture(selected);
    final HtlcSwapsService? service = app.htlcSwapsService;
    final Object? wallet = kWalletFile;
    if (scope == null || service == null || wallet == null) return null;
    final HtlcStoreCapture? store = service.captureStore(chainId: chain);
    if (store == null) return null;
    final Zenon sdk = scope.client;
    final HtlcApi htlcSource = sdk.embedded.htlc;
    final TokenApi tokenSource = sdk.embedded.token;
    final LedgerApi ledgerSource = sdk.ledger;
    final Client htlcTransport = htlcSource.client;
    final Client tokenTransport = tokenSource.client;
    final Client ledgerTransport = ledgerSource.client;
    final HtlcApi htlc = HtlcApi()..setClient(htlcTransport);
    final TokenApi token = TokenApi()..setClient(tokenTransport);
    final LedgerApi ledger = LedgerApi()..setClient(ledgerTransport);
    final List<String> members = kDefaultAddressList
        .whereType<String>()
        .toList();
    if (members.length != kDefaultAddressList.length ||
        members.toSet().length != members.length) {
      return null;
    }
    final SwapListResources resources = SwapListResources(
      identities: () => <Object?>[
        app.htlcSwapsService,
        sdk.embedded.htlc,
        sdk.embedded.token,
        sdk.ledger,
        htlcSource.client,
        tokenSource.client,
        ledgerSource.client,
        htlc.client,
        token.client,
        ledger.client,
      ],
      values: () => <Object?>[
        if (htlcTransport is WsClient) htlcTransport.url else null,
        if (tokenTransport is WsClient) tokenTransport.url else null,
        if (ledgerTransport is WsClient) ledgerTransport.url else null,
      ],
      ready: () =>
          scope.isCurrent &&
          store.isCurrent &&
          (sourceIsCurrent?.call() ?? true),
    );
    late final SwapActionOrigin origin;
    origin = SwapActionOrigin(
      identity: store.identity,
      chainId: chain,
      ownerAddress: selected,
      members: members,
      isCurrent: () => resources.isCurrent,
      readHtlc: (String id) => htlc.getById(Hash.parse(id)),
      readBlock: (String id) => ledger.getAccountBlockByHash(Hash.parse(id)),
      readChainTime: () async {
        final Momentum frontier = await ledger.getFrontierMomentum();
        if (frontier.chainIdentifier != chain || frontier.timestamp <= 0) {
          throw const SwapActionRefused('chain-time');
        }
        return frontier.timestamp;
      },
      readAccount: (String address) =>
          ledger.getAccountInfoByAddress(Address.parse(address)),
      readToken: (String standard) =>
          token.getByZts(TokenStandard.parse(standard)),
      readHistory: store.readAll,
      readContractBlocks: (int after) =>
          AccountBlockUtils.getAccountBlocksAfterTime(
            htlcAddress,
            after,
            ledger: ledger,
            canRead: () => origin.isCurrent,
          ),
      reserveStore: () => _StoreReservation(store.reserveWrite()),
      reservePublication: (String kind, String target, String owner) =>
          _PublicationReservation(
            store.reserveAction(kind: kind, targetId: target, owner: owner),
          ),
      rearmStart: (String owner, AccountBlock creation) =>
          store.rearmStart(owner: owner, creation: creation),
      capturePublisher: (String address) {
        origin.requireCurrent();
        if (!origin.members.contains(address)) {
          throw const SwapActionRefused('signer');
        }
        final AccountBlockUtils sender = AccountBlockUtils.capture(
          address: Address.parse(address),
          canPublish: () => origin.isCurrent,
        );
        return (AccountBlockTemplate block, String purpose) =>
            sender.createAccountBlock(
              block,
              purpose,
              address: Address.parse(address),
              waitForRequiredPlasma: true,
              canPublish: () => origin.isCurrent,
            );
      },
      create: htlc.create,
      unlock: htlc.unlock,
      reclaim: htlc.reclaim,
    );
    return origin.isCurrent ? origin : null;
  }

  /// An opaque original encrypted backend identity, never a path.
  final Object identity;

  /// Positive chain shared by every captured reader, builder and publication.
  final int chainId;

  /// Selection at capture; a different member signer must still be owned.
  final String ownerAddress;

  /// Complete immutable member set used for original signer admission.
  final Set<String> members;
  final bool Function() _isCurrent;

  /// Live deposit lookup on the original HTLC transport.
  final Future<HtlcInfo> Function(String id) readHtlc;

  /// Exact original ledger hash lookup for confirmed Create proofs.
  final Future<AccountBlock?> Function(String id) readBlock;
  final Future<int> Function() _readChainTime;
  int? _lastChainTime;

  /// Every later proof uses a positive time at least as recent as this origin.
  Future<int> readChainTime() async {
    requireCurrent();
    final int time = await _readChainTime();
    requireCurrent();
    final int? previous = _lastChainTime;
    if (time <= 0 || (previous != null && time < previous)) {
      throw const SwapActionRefused('chain-time');
    }
    _lastChainTime = time;
    return time;
  }

  /// Original account read used to establish complete funding facts.
  final Future<AccountInfo> Function(String address) readAccount;

  /// Original token metadata lookup; null never supplies invented metadata.
  final Future<Token?> Function(String standard) readToken;

  /// Complete original encrypted catalogue and retained recovery anchors.
  final List<HtlcSwap> Function() readHistory;

  /// Bounded complete original contract history after an exact chain timestamp.
  final Future<List<AccountBlock>> Function(int after) readContractBlocks;

  /// Reserves the original recovery write before the action's first RPC.
  final SwapPersistenceReservation Function() reserveStore;

  /// Reserves a durable original action hold before the first RPC.
  final SwapPublicationReservation Function(
    String kind,
    String target,
    String owner,
  )
  reservePublication;

  /// Releases only a positively proven original Start for explicit New deposit.
  final Future<bool> Function(String owner, AccountBlock creation) rearmStart;

  /// Captures a specific original member signer before asynchronous reads.
  final SwapPublisher Function(String address) capturePublisher;

  /// Pure SDK Create builder; publication remains separately owned.
  final AccountBlockTemplate Function(
    Token token,
    BigInt amount,
    Address recipient,
    int expiry,
    int hashType,
    int keyMaxSize,
    List<int> hashLock,
  )
  create;

  /// Pure SDK Unlock builder for one exact deposit and preimage.
  final AccountBlockTemplate Function(Hash id, List<int> preimage) unlock;

  /// Pure SDK Reclaim builder for one exact deposit.
  final AccountBlockTemplate Function(Hash id) reclaim;
  bool _revoked = false;

  /// Every observed departure is terminal for this original action source.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final bool lost = !_isCurrent();
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Refuses after original source change without recapturing replacements.
  void requireCurrent() {
    if (!isCurrent) throw const SwapActionRefused('source');
  }
}
