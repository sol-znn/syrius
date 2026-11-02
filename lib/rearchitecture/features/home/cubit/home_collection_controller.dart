import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The existing reward contracts, each collected once per explicit batch.
enum HomeRewardSource {
  /// Pillar and delegation rewards share this contract.
  pillar,

  /// Sentinel rewards.
  sentinel,

  /// Staking rewards.
  stake,
}

/// Captures the current context before the first collection can be admitted.
class HomeCollectionSession {
  /// Uses existing SDK template builders and a captured context guard.
  HomeCollectionSession({
    required this.address,
    required this.chainId,
    required this.isCurrent,
    required this.buildBlock,
  });

  /// The exact source address for every request in this batch.
  final String address;

  /// The original chain, never inferred from a later global selection.
  final int chainId;

  /// Checks the original file, client, chain, node and address.
  final bool Function() isCurrent;

  /// Builds the same existing collectReward template as the source page.
  final AccountBlockTemplate Function(HomeRewardSource source) buildBlock;
}

/// A read's eligibility is captured before its RPCs start.
class HomeCollectionRead {
  HomeCollectionRead._(this.owner, this.epoch, this.canRearm);

  /// The exact session owner that started this read.
  final HomeCollectionController owner;

  /// The collection epoch observed before the RPCs started.
  final int epoch;

  /// Whether all original hashes were confirmed before this read.
  final bool canRearm;
}

/// Retains one original admitted attempt whose final result is unavailable.
class HomeCollectionAttempt {
  /// Keeps the exact request and any returned template for later inspection.
  const HomeCollectionAttempt({
    required this.requestId,
    required this.source,
    this.error,
    this.block,
  });

  /// The original request identity; a fresh read never replaces it.
  final Object requestId;

  /// The original reward contract.
  final HomeRewardSource source;

  /// The original failure, which does not establish non-publication.
  final Object? error;

  /// The original returned response, if available.
  final AccountBlockTemplate? block;
}

/// One session-owned collection coordinator; leaving Home does not replace it.
class HomeCollectionController extends ChangeNotifier {
  /// Shares the existing sender and exact wallet-and-chain flight registry.
  HomeCollectionController({
    required this.sender,
    required this.flight,
    required this.address,
    required this.chainId,
  }) {
    sender.busy.addListener(_changed);
    flight.addListener(_changed);
  }

  /// The wallet's existing publication owner, never a nested sender.
  final SendTransactionBloc sender;

  /// The same exact-hash tracker used by the wallet's status strip.
  final InFlightBlocks flight;

  /// The selected address this shell-owned coordinator was created for.
  final String address;

  /// The original chain for this coordinator and its exact-hash tracker.
  final int chainId;
  final List<AccountBlockTemplate> _accepted = <AccountBlockTemplate>[];
  final List<Hash> _confirmationBarrier = <Hash>[];
  HomeCollectionAttempt? _unresolved;
  HomeSnapshot? _consumedSnapshot;
  HomeSnapshot? _rearmedSnapshot;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;

  /// Whether this original batch is still awaiting a request outcome.
  bool get busy => _busy;

  /// Exact original responses, including partial batches after a failure.
  List<AccountBlockTemplate> get accepted =>
      List<AccountBlockTemplate>.unmodifiable(_accepted);

  /// A retained uncertain attempt prevents automatic or implicit resubmission.
  HomeCollectionAttempt? get unresolved => _unresolved;

  /// Only a displayed unconsumed snapshot can start an explicit new batch.
  bool canCollect(HomeSnapshot? snapshot) =>
      !_disposed &&
      !_busy &&
      !sender.busy.value &&
      _unresolved == null &&
      _confirmationBarrier.isEmpty &&
      snapshot != null &&
      !identical(snapshot, _consumedSnapshot) &&
      (_consumedSnapshot == null || identical(snapshot, _rearmedSnapshot)) &&
      snapshot.rewardsDue.isNotEmpty;

  /// Called before a Home read, so an older in-flight read cannot rearm it.
  HomeCollectionRead beginRead() => HomeCollectionRead._(
    this,
    _epoch,
    !_busy &&
        _unresolved == null &&
        _confirmationBarrier.every(flight.hasConfirmed),
  );

  /// Rearms only after exact confirmation followed by a fresh context read.
  void completeRead(
    HomeCollectionRead read, {
    required bool isCurrent,
    required HomeSnapshot snapshot,
  }) {
    if (_disposed ||
        !identical(read.owner, this) ||
        read.epoch != _epoch ||
        !read.canRearm ||
        !isCurrent ||
        _busy ||
        _unresolved != null) {
      return;
    }
    if (_confirmationBarrier.isNotEmpty || _consumedSnapshot != null) {
      _confirmationBarrier.clear();
      _rearmedSnapshot = snapshot;
      _changed();
    }
  }

  /// Revokes remaining batch dispatch without cancelling an original request.
  void invalidate() {
    if (_disposed) return;
    _epoch++;
    _rearmedSnapshot = null;
    flight.invalidateEvidence();
    for (final AccountBlockTemplate block in _accepted) {
      if (_confirmationBarrier.contains(block.hash)) {
        flight.sent(hash: block.hash, amount: block.amount);
      }
    }
    _changed();
  }

  /// Runs each existing collection once, stopping at the first unknown result.
  Future<void> collect({
    required HomeSnapshot snapshot,
    required HomeCollectionSession session,
  }) async {
    if (!canCollect(snapshot) ||
        session.address != address ||
        session.chainId != chainId ||
        !session.isCurrent()) {
      return;
    }
    final List<HomeRewardSource> jobs = <HomeRewardSource>[
      if (snapshot.rewardsDue.containsKey('Delegation'))
        HomeRewardSource.pillar,
      if (snapshot.rewardsDue.containsKey('Sentinel'))
        HomeRewardSource.sentinel,
      if (snapshot.rewardsDue.containsKey('Staking')) HomeRewardSource.stake,
    ];
    if (jobs.isEmpty) return;
    final Object owner = Object();
    if (!sender.tryReserve(owner)) return;
    final int epoch = ++_epoch;
    _busy = true;
    _consumedSnapshot = snapshot;
    _rearmedSnapshot = null;
    _changed();
    try {
      for (final HomeRewardSource source in jobs) {
        if (_disposed || epoch != _epoch || !session.isCurrent()) break;
        final Object requestId = Object();
        final SendRequestHandle? handle = sender.trySubmitOwned(
          owner: owner,
          requestId: requestId,
          block: session.buildBlock(source),
          fromAddress: session.address,
          reasonForGeneratingPlasma: switch (source) {
            HomeRewardSource.pillar =>
              PlasmaPurpose.collectPillarRewards.message,
            HomeRewardSource.sentinel =>
              PlasmaPurpose.collectSentinelRewards.message,
            HomeRewardSource.stake =>
              PlasmaPurpose.collectStakingRewards.message,
          },
        );
        if (handle == null) break;
        final SendRequestResult result = await handle.result;
        final AccountBlockTemplate? block = result.block;
        if (!result.accepted ||
            block == null ||
            block.hash == emptyHash ||
            block.address.toString() != session.address ||
            block.chainIdentifier != session.chainId) {
          _unresolved = HomeCollectionAttempt(
            requestId: requestId,
            source: source,
            error: result.error,
            block: block,
          );
          break;
        }
        _accepted.add(block);
        _confirmationBarrier.add(block.hash);
        // Observing an exact returned hash neither republishes nor settles it.
        flight.sent(hash: block.hash, amount: block.amount);
      }
    } on Object catch (error, trace) {
      // Template preparation can fail before admission. It never authorizes a
      // substitute operation, and a fresh read is needed before another try.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: trace,
          library: 'Home collection',
        ),
      );
    } finally {
      _busy = false;
      sender.releaseReservation(owner);
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    sender.busy.removeListener(_changed);
    flight.removeListener(_changed);
    super.dispose();
  }
}
