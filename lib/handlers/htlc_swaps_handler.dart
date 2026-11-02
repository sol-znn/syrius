import 'dart:async';

import 'package:collection/collection.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_worker_origin.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_creation_proof.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Owns one five-second timer and every original-cycle operation.
class HtlcSwapsHandler {
  /// Binds one timer to captured wallet capabilities and a finite scan budget.
  HtlcSwapsHandler({
    HtlcWorkerOrigin? Function()? captureOrigin,
    AutoUnlockHtlcWorker? unlockWorker,
    this.maxBlocksPerCycle = 1000,
  }) : _originSource = captureOrigin,
       _injectedWorker = unlockWorker {
    _work = HtlcOwnedWork(this);
  }

  /// Returns the legacy singleton without reviving a terminally paused owner.
  factory HtlcSwapsHandler.shared() => _instance ??= HtlcSwapsHandler();
  static HtlcSwapsHandler? _instance;
  static HtlcSwapsHandler? _wakeOwner;
  final HtlcWorkerOrigin? Function()? _originSource;
  final AutoUnlockHtlcWorker? _injectedWorker;

  /// Maximum contiguous confirmed blocks committed by a single cycle.
  final int maxBlocksPerCycle;
  late final HtlcOwnedWork _work;
  final List<HtlcOperationReceipt> _operations = <HtlcOperationReceipt>[];
  Timer? _timer;
  bool _started = false;
  bool _hasActiveIncoming = true;
  HtlcWorkerOrigin? _wakeOrigin;
  Future<void>? _cycle;
  Future<HtlcDrainReceipt>? _pause;
  Object? _startReservation;
  bool Function()? _reservedAdmission;

  /// Whether further timer and explicit-cycle admission is terminally closed.
  bool get isPaused => !_work.accepting;

  /// Whether this owner consumed its once-only startup admission.
  bool get hasStarted => _started;
  bool get _pristine =>
      !_started &&
      _work.accepting &&
      _startReservation == null &&
      _cycle == null &&
      _timer == null &&
      _wakeOrigin == null &&
      _work.operations.isEmpty &&
      _operations.isEmpty;

  /// Reserves startup admission without ticking, opening or capturing globals.
  HtlcHandlerStart? reserveStart({required bool Function() isCurrent}) {
    if (!_pristine) return null;
    final Object token = Object();
    final HtlcHandlerStart reservation = HtlcHandlerStart._(
      this,
      token,
      isCurrent,
    );
    if (!reservation._sourceCurrent() || !_pristine) return null;
    _startReservation = token;
    return reservation;
  }

  /// Unknown source state keeps the existing lock protection in place.
  bool get hasActiveIncomingSwaps => _hasActiveIncoming;

  /// Original cycles, chain reads, writes and wake-lock lifecycle receipts.
  List<HtlcOperationReceipt> get operations =>
      List<HtlcOperationReceipt>.unmodifiable(<HtlcOperationReceipt>[
        ..._work.operations,
        ..._operations,
      ]);

  /// Starts the compatibility timer once; deferred initialization uses
  /// [reserveStart] so committed globals can be published before its first RPC.
  void start() {
    if (_started || !_work.accepting) return;
    _started = true;
    _tick();
  }

  void _tick() {
    if (!_work.accepting || !(_reservedAdmission?.call() ?? true)) return;
    unawaited(_beginTick());
  }

  Future<void> _beginTick() {
    final Future<void> original = runOnce();
    void next() {
      if (_work.accepting) _timer = Timer(const Duration(seconds: 5), _tick);
    }

    unawaited(
      original.then<void>(
        (_) => next(),
        onError: (Object _, StackTrace _) => next(),
      ),
    );
    return original;
  }

  Future<T> _observe<T>(String name, Future<T> Function() call) {
    final HtlcOperationReceipt operation = HtlcOperationReceipt(name);
    _operations.add(operation);
    return operation.run<T>(call);
  }

  /// Explicit finite cycles let fixtures exercise the exact ordinary pipeline.
  Future<void> runOnce() {
    if (_cycle != null) return _cycle!;
    if (!_work.accepting) {
      return Future<void>.error(const HtlcOwnershipRefused('handler-paused'));
    }
    if (!(_reservedAdmission?.call() ?? true)) {
      return Future<void>.error(
        const HtlcOwnershipRefused('reserved-handler-source-unavailable'),
      );
    }
    final AutoUnlockHtlcWorker? worker = _originSource != null
        ? _injectedWorker
        : app.sl.isRegistered<AutoUnlockHtlcWorker>()
        ? app.sl<AutoUnlockHtlcWorker>()
        : null;
    final HtlcWorkerOrigin? origin = _originSource != null
        ? _originSource()
        : captureHtlcWorkerOrigin(
            ownerIsCurrent: () =>
                app.sl.isRegistered<HtlcSwapsHandler>() &&
                identical(app.sl<HtlcSwapsHandler>(), this) &&
                (worker == null ||
                    (app.sl.isRegistered<AutoUnlockHtlcWorker>() &&
                        identical(app.sl<AutoUnlockHtlcWorker>(), worker))),
          );
    if (origin == null) {
      // Capture is synchronous and has admitted no RPC, write or publication.
      // Ready/locked/offline sources stay protected until a later real cycle.
      _hasActiveIncoming = true;
      _work.reserve('handler-origin-unavailable-no-admission').refuse();
      return Future<void>.value();
    }
    final Future<void> original = _work.admit<void>('handler-cycle', () async {
      if (!origin.isCurrent || maxBlocksPerCycle <= 0) {
        throw const HtlcOwnershipRefused('handler-origin-unproven');
      }
      final List<HtlcSwap> source = origin.store.readAll();
      final Map<String, HtlcSwap> records = <String, HtlcSwap>{};
      final Set<String> hashLocks = <String>{};
      for (final HtlcSwap swap in source) {
        if (swap.chainId != origin.chainId ||
            !origin.members.contains(swap.selfAddress) ||
            records.containsKey(swap.id) ||
            !hashLocks.add(swap.hashLock)) {
          throw const HtlcOwnershipRefused('handler-catalogue-incomplete');
        }
        records[swap.id] = HtlcSwap.fromJson(swap.toJson());
      }
      _hasActiveIncoming = source.any(
        (HtlcSwap swap) =>
            swap.direction == P2pSwapDirection.incoming &&
            <P2pSwapState>[
              P2pSwapState.pending,
              P2pSwapState.active,
              P2pSwapState.reclaimable,
            ].contains(swap.state),
      );
      if (_hasActiveIncoming && _wakeOrigin == null) {
        if (_wakeOwner != null && !identical(_wakeOwner, this)) {
          throw const HtlcOwnershipRefused('wake-lock-owner-changed');
        }
        _wakeOwner = this;
        _wakeOrigin = origin;
        await _observe<void>('wake-lock-enable', origin.enableWakeLock);
        origin.requireCurrent();
      }
      final List<HtlcSwap> unresolved = source
          .where(
            (HtlcSwap swap) => <P2pSwapState>[
              P2pSwapState.pending,
              P2pSwapState.active,
              P2pSwapState.reclaimable,
            ].contains(swap.state),
          )
          .toList();
      if (unresolved.isEmpty) return;
      final SyncInfo sync = await _observe<SyncInfo>(
        'handler-sync',
        origin.readSync,
      );
      origin.requireCurrent();
      if (!(sync.state == SyncState.syncDone ||
          (sync.targetHeight > 0 &&
              sync.currentHeight > 0 &&
              sync.targetHeight >= sync.currentHeight &&
              sync.targetHeight - sync.currentHeight < 3))) {
        throw const HtlcOwnershipRefused('handler-sync-unproven');
      }
      if (!await _scan(origin, records)) return;
      final int chainTime = await _observe<int>(
        'handler-chain-time',
        origin.readChainTime,
      );
      origin.requireCurrent();
      if (chainTime <= 0) {
        throw const HtlcOwnershipRefused('handler-chain-time-unproven');
      }
      for (final HtlcSwap record in List<HtlcSwap>.of(records.values)) {
        if (!<P2pSwapState>[
          P2pSwapState.pending,
          P2pSwapState.active,
        ].contains(record.state)) {
          continue;
        }
        final String? own = record.direction == P2pSwapDirection.outgoing
            ? record.initialHtlcId
            : record.counterHtlcId;
        if (own == null) {
          throw const HtlcOwnershipRefused('own-deposit-unproven');
        }
        if (await _observedWithdrawal(origin, record, own)) continue;
        final HtlcInfo live = await _observe<HtlcInfo>(
          'handler-live-deposit',
          () => origin.readLive(own),
        );
        origin.requireCurrent();
        if (!_liveMatches(record, live, own)) {
          throw const HtlcOwnershipRefused('handler-live-deposit-mismatch');
        }
        if (live.expirationTime <= chainTime) {
          final HtlcSwap changed = HtlcSwap.fromJson(record.toJson())
            ..state = P2pSwapState.reclaimable;
          await _observe<void>(
            'handler-expiry-write',
            () => origin.store.replaceSwap(record, changed),
          );
          records[record.id] = changed;
          origin.requireCurrent();
        }
      }
      for (final HtlcSwap record in records.values) {
        if (record.direction == P2pSwapDirection.incoming &&
            record.preimage != null &&
            <P2pSwapState>[
              P2pSwapState.active,
              P2pSwapState.reclaimable,
            ].contains(record.state)) {
          if (worker == null) {
            throw const HtlcOwnershipRefused('unlock-worker-absent');
          }
          await _observe<void>(
            'handler-enqueue-unlock',
            () => worker.addHash(
              Hash.parse(record.initialHtlcId),
              origin: origin,
            ),
          );
          origin.requireCurrent();
        }
      }
      if (worker != null) {
        await _observe<void>('handler-unlock-drain', worker.autoUnlock);
      }
    });
    _cycle = original;
    unawaited(
      original.then<void>(
        (_) {
          if (identical(_cycle, original)) _cycle = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_cycle, original)) _cycle = null;
        },
      ),
    );
    return original;
  }

  Future<bool> _scan(
    HtlcWorkerOrigin origin,
    Map<String, HtlcSwap> records,
  ) async {
    final HtlcCursor cursor = origin.store.readCursor();
    final AccountBlock? rawHead = await _observe<AccountBlock?>(
      'htlc-frontier',
      origin.readFrontier,
    );
    final AccountBlock? head = rawHead == null
        ? null
        : AccountBlock.fromJson(rawHead.toJson());
    origin.requireCurrent();
    if (head == null ||
        !_ownedBlock(head, origin.chainId, head.height) ||
        head.height < cursor.height) {
      throw const HtlcOwnershipRefused('htlc-frontier-unproven');
    }
    String previous = cursor.hash;
    int previousTime = 0;
    if (cursor.height > 0) {
      final List<AccountBlock>? anchor = await _observe<List<AccountBlock>?>(
        'htlc-cursor-anchor',
        () => origin.readBlocks(cursor.height, 1),
      );
      origin.requireCurrent();
      if (anchor == null ||
          anchor.length != 1 ||
          !_ownedBlock(anchor.single, origin.chainId, cursor.height) ||
          anchor.single.hash.toString() != cursor.hash) {
        throw const HtlcOwnershipRefused('htlc-cursor-anchor-mismatch');
      }
      previousTime = anchor.single.confirmationDetail!.momentumTimestamp;
    }
    int next = cursor.height + 1;
    int scanned = 0;
    final Set<String> hashes = <String>{};
    while (next <= head.height && scanned < maxBlocksPerCycle) {
      final int remaining = head.height - next + 1;
      final int budget = maxBlocksPerCycle - scanned;
      final int count = remaining < 100 ? remaining : 100;
      final int size = count < budget ? count : budget;
      final List<AccountBlock>? rawPage = await _observe<List<AccountBlock>?>(
        'htlc-contiguous-page',
        () => origin.readBlocks(next, size),
      );
      origin.requireCurrent();
      if (rawPage == null || rawPage.length != size) {
        throw const HtlcOwnershipRefused('htlc-page-incomplete');
      }
      final List<AccountBlock> page = List<AccountBlock>.unmodifiable(
        rawPage.map(
          (AccountBlock value) => AccountBlock.fromJson(value.toJson()),
        ),
      );
      for (int index = 0; index < page.length; index++) {
        final AccountBlock block = page[index];
        if (!_ownedBlock(block, origin.chainId, next + index) ||
            block.previousHash.toString() != previous ||
            block.confirmationDetail!.momentumTimestamp < previousTime ||
            !hashes.add(block.hash.toString()) ||
            (block.height == head.height && block.hash != head.hash)) {
          throw const HtlcOwnershipRefused('htlc-page-not-contiguous');
        }
        await _apply(origin, records, block);
        origin.requireCurrent();
        await _observe<void>(
          'htlc-cursor-write',
          () => origin.store.storeCursor(block.height, block.hash.toString()),
        );
        previous = block.hash.toString();
        previousTime = block.confirmationDetail!.momentumTimestamp;
        scanned++;
      }
      next += size;
    }
    if (next <= head.height) return false;
    if (previous != head.hash.toString()) {
      throw const HtlcOwnershipRefused('htlc-frontier-not-reached');
    }
    final AccountBlock? after = await _observe<AccountBlock?>(
      'htlc-frontier-recheck',
      origin.readFrontier,
    );
    origin.requireCurrent();
    if (after == null ||
        !_ownedBlock(after, origin.chainId, after.height) ||
        after.height < head.height ||
        (after.height == head.height && after.hash != head.hash)) {
      throw const HtlcOwnershipRefused('htlc-frontier-changed');
    }
    return after.height == head.height && after.hash == head.hash;
  }

  Future<void> _apply(
    HtlcWorkerOrigin origin,
    Map<String, HtlcSwap> records,
    AccountBlock block,
  ) async {
    if (block.blockType != BlockTypeEnum.contractReceive.index) return;
    final BlockData data = _contractCall(origin, block);
    if (<String>[
      'DenyProxyUnlock',
      'AllowProxyUnlock',
    ].contains(data.function)) {
      return;
    }
    final String? id = data.params['id']?.toString();
    final String? lock = data.params['hashLock'] is List<int>
        ? FormatUtils.encodeHexString(data.params['hashLock'] as List<int>)
        : null;
    final List<HtlcSwap> matching = records.values
        .where(
          (HtlcSwap swap) =>
              (id != null &&
                  (swap.initialHtlcId == id || swap.counterHtlcId == id)) ||
              (lock != null && swap.hashLock == lock),
        )
        .toList();
    if (matching.isEmpty) return;
    if (matching.length != 1) {
      throw const HtlcOwnershipRefused('htlc-record-ambiguous');
    }
    final HtlcSwap before = matching.single;
    final HtlcSwap after = HtlcSwap.fromJson(before.toJson());
    if (data.function == 'Create') {
      final AccountBlock paired = block.pairedAccountBlock!;
      final String created = paired.hash.toString();
      // The successful confirmed effect remains proof after the live entry
      // disappears. A refund output cannot activate or discover a deposit.
      if (block.descendantBlocks.isNotEmpty) {
        throw const HtlcOwnershipRefused('htlc-create-effect-unproven');
      }
      if (before.state == P2pSwapState.pending &&
          created == before.initialHtlcId) {
        if (!htlcCreationMatches(before, paired, initial: true)) {
          throw const HtlcOwnershipRefused('htlc-initial-create-unproven');
        }
        after.state = P2pSwapState.active;
      } else if (before.direction == P2pSwapDirection.outgoing &&
          before.counterHtlcId == null &&
          created != before.initialHtlcId) {
        final int? expiration = htlcProofInteger(data.params['expirationTime']);
        if (expiration == null ||
            expiration <= block.confirmationDetail!.momentumTimestamp ||
            paired.amount <= BigInt.zero ||
            paired.token == null ||
            paired.token!.tokenStandard != paired.tokenStandard) {
          throw const HtlcOwnershipRefused('htlc-counter-deposit-mismatch');
        }
        after
          ..counterHtlcId = created
          ..counterHtlcExpirationTime = expiration
          ..toAmount = paired.amount
          ..toTokenStandard = paired.tokenStandard.toString()
          ..toDecimals = paired.token!.decimals
          ..toSymbol = paired.token!.symbol;
        if (!htlcCreationMatches(after, paired, initial: false)) {
          throw const HtlcOwnershipRefused('htlc-counter-create-unproven');
        }
      } else {
        if ((created == before.initialHtlcId ||
                created == before.counterHtlcId) &&
            !htlcCreationMatches(
              before,
              paired,
              initial: created == before.initialHtlcId,
            )) {
          throw const HtlcOwnershipRefused('htlc-historical-create-unproven');
        }
        return;
      }
    } else {
      final _HtlcWithdrawalProof? proof = await _proveWithdrawal(
        origin,
        before,
        block,
      );
      if (proof == null) return;
      await _observe<void>(
        'htlc-observed-withdrawal-write',
        () => origin.store.storeObservedWithdrawal(
          before,
          deposit: proof.deposit,
          height: block.height,
          hash: block.hash.toString(),
          method: proof.method,
        ),
      );
      origin.requireCurrent();
      if (proof.method == 'Unlock') {
        after.preimage ??= proof.preimage;
        if ((before.direction == P2pSwapDirection.incoming &&
                proof.deposit == before.initialHtlcId) ||
            (before.direction == P2pSwapDirection.outgoing &&
                proof.deposit == before.counterHtlcId)) {
          after.state = P2pSwapState.completed;
        }
      } else if ((before.direction == P2pSwapDirection.outgoing &&
              proof.deposit == before.initialHtlcId) ||
          (before.direction == P2pSwapDirection.incoming &&
              proof.deposit == before.counterHtlcId)) {
        after.state = P2pSwapState.unsuccessful;
      }
    }
    origin.requireCurrent();
    if (!const DeepCollectionEquality().equals(
      before.toJson(),
      after.toJson(),
    )) {
      await _observe<void>(
        'htlc-observed-record-write',
        () => origin.store.replaceSwap(before, after),
      );
      records[after.id] = after;
    }
  }

  BlockData _contractCall(HtlcWorkerOrigin origin, AccountBlock block) {
    final AccountBlock? paired = block.pairedAccountBlock;
    if (paired == null ||
        paired.chainIdentifier != origin.chainId ||
        paired.toAddress != htlcAddress ||
        paired.blockType != BlockTypeEnum.userSend.index ||
        paired.hash == emptyHash ||
        block.fromBlockHash != paired.hash) {
      throw const HtlcOwnershipRefused('htlc-paired-block-unproven');
    }
    final BlockData? data = AccountBlockUtils.getDecodedBlockData(
      Definitions.htlc,
      paired.data,
    );
    if (data == null ||
        !<String>[
          'Create',
          'Unlock',
          'Reclaim',
          'DenyProxyUnlock',
          'AllowProxyUnlock',
        ].contains(data.function)) {
      throw const HtlcOwnershipRefused('htlc-function-unproven');
    }
    return data;
  }

  Future<_HtlcWithdrawalProof?> _proveWithdrawal(
    HtlcWorkerOrigin origin,
    HtlcSwap record,
    AccountBlock block,
  ) async {
    if (!_ownedBlock(block, origin.chainId, block.height) ||
        block.blockType != BlockTypeEnum.contractReceive.index) {
      throw const HtlcOwnershipRefused('htlc-withdrawal-event-unproven');
    }
    final BlockData data = _contractCall(origin, block);
    final String? id = data.params['id']?.toString();
    if (!<String>['Unlock', 'Reclaim'].contains(data.function) ||
        id == null ||
        (id != record.initialHtlcId && id != record.counterHtlcId)) {
      throw const HtlcOwnershipRefused('htlc-withdrawal-id-unproven');
    }
    if (block.descendantBlocks.isEmpty) return null;
    final AccountBlock? rawCreation = await _observe<AccountBlock?>(
      'htlc-terminal-create-proof',
      () => origin.readBlock(id),
    );
    origin.requireCurrent();
    final AccountBlock? creation = rawCreation == null
        ? null
        : AccountBlock.fromJson(rawCreation.toJson());
    if (!htlcCreationMatches(
      record,
      creation,
      initial: id == record.initialHtlcId,
    )) {
      throw const HtlcOwnershipRefused('htlc-terminal-deposit-unproven');
    }
    final BlockData? original = AccountBlockUtils.getDecodedBlockData(
      Definitions.htlc,
      creation!.data,
    );
    if (original == null ||
        original.function != 'Create' ||
        original.params['hashLock'] is! List<int> ||
        FormatUtils.encodeHexString(original.params['hashLock'] as List<int>) !=
            record.hashLock) {
      throw const HtlcOwnershipRefused('htlc-terminal-lock-mismatch');
    }
    final String recipient = data.function == 'Unlock'
        ? original.params['hashLocked'].toString()
        : creation.address.toString();
    if (!block.descendantBlocks.any(
      (AccountBlock output) =>
          output.address == htlcAddress &&
          output.chainIdentifier == origin.chainId &&
          output.blockType == BlockTypeEnum.contractSend.index &&
          output.toAddress.toString() == recipient &&
          output.amount == creation.amount &&
          output.tokenStandard == creation.tokenStandard,
    )) {
      throw const HtlcOwnershipRefused('htlc-terminal-output-unproven');
    }
    String? preimage;
    if (data.function == 'Unlock') {
      final dynamic value = data.params['preimage'];
      final int? keySize = htlcProofInteger(original.params['keyMaxSize']);
      if (value is! List<int> ||
          keySize == null ||
          value.length > keySize ||
          !await _observe<bool>(
            'htlc-observed-key-proof',
            () => htlcPreimageMatches(record.hashType, record.hashLock, value),
          )) {
        throw const HtlcOwnershipRefused('htlc-observed-key-mismatch');
      }
      preimage = FormatUtils.encodeHexString(value);
    }
    origin.requireCurrent();
    return _HtlcWithdrawalProof(id, data.function, preimage);
  }

  Future<bool> _observedWithdrawal(
    HtlcWorkerOrigin origin,
    HtlcSwap record,
    String own,
  ) async {
    final HtlcWithdrawalReference? reference = origin.store
        .readObservedWithdrawal(
          own,
          record.selfAddress,
        );
    if (reference == null) return false;
    final HtlcCursor cursor = origin.store.readCursor();
    final AccountBlock? raw = await _observe<AccountBlock?>(
      'htlc-observed-withdrawal-proof',
      () => origin.readBlock(reference.hash),
    );
    origin.requireCurrent();
    final AccountBlock? block = raw == null
        ? null
        : AccountBlock.fromJson(raw.toJson());
    if (block == null ||
        block.hash.toString() != reference.hash ||
        block.height != reference.height ||
        block.height > cursor.height) {
      throw const HtlcOwnershipRefused('htlc-observed-withdrawal-unproven');
    }
    final _HtlcWithdrawalProof? proof = await _proveWithdrawal(
      origin,
      record,
      block,
    );
    if (proof == null ||
        proof.deposit != own ||
        proof.method != reference.method) {
      throw const HtlcOwnershipRefused('htlc-observed-withdrawal-mismatch');
    }
    origin.requireCurrent();
    return true;
  }

  /// Cancels this timer and awaits original work and wake-lock release after
  /// closing admission. Failure stays attached to the exact paused owner.
  Future<HtlcDrainReceipt> pauseAndDrain() {
    if (_pause != null) return _pause!;
    _timer?.cancel();
    _timer = null;
    final Future<HtlcDrainReceipt> original = _work.pauseAndDrain();
    final HtlcWorkerOrigin? wake = _wakeOrigin;
    final Future<HtlcDrainReceipt> result = () async {
      final HtlcDrainReceipt receipt = await original;
      Object? error = receipt.error;
      StackTrace? trace = receipt.stackTrace;
      if (wake != null) {
        try {
          if (!identical(_wakeOwner, this)) {
            throw const HtlcOwnershipRefused('wake-lock-owner-changed');
          }
          await _observe<void>('wake-lock-disable', wake.disableWakeLock);
          _wakeOwner = null;
          _wakeOrigin = null;
        } on Object catch (value, stack) {
          error ??= value;
          trace ??= stack;
        }
      }
      final List<HtlcOperationReceipt> children = List<HtlcOperationReceipt>.of(
        _operations,
      );
      for (final HtlcOperationReceipt child in children) {
        await child.settled;
      }
      final HtlcOperationReceipt? failed = children.firstWhereOrNull(
        (HtlcOperationReceipt value) => value.error != null,
      );
      return HtlcDrainReceipt(
        owner: this,
        completed: receipt.completed && error == null && failed == null,
        operations: <HtlcOperationReceipt>[...receipt.operations, ...children],
        error: error ?? failed?.error,
        stackTrace: trace ?? failed?.stackTrace,
      );
    }();
    _pause = result;
    return result;
  }
}

class _HtlcWithdrawalProof {
  const _HtlcWithdrawalProof(this.deposit, this.method, this.preimage);
  final String deposit;
  final String method;
  final String? preimage;
}

/// One-use synchronous admission with separately observed deferred startup.
class HtlcHandlerStart {
  HtlcHandlerStart._(this._owner, this._token, this._isCurrent);
  final HtlcSwapsHandler _owner;
  final Object _token;
  final bool Function() _isCurrent;
  bool _consumed = false;
  bool _revoked = false;
  bool _invoked = false;
  HtlcOperationReceipt? _startup;
  Object? _sourceError;
  StackTrace? _sourceTrace;

  /// Handler that owns the reserved startup token.
  Object get identity => _owner;

  /// Whether the deferred first cycle has actually been invoked.
  bool get invoked => _invoked;

  /// First-cycle receipt, absent until the deferred callback admits it.
  HtlcOperationReceipt? get startup => _startup;

  /// Unchanged first-cycle or source-guard failure.
  Object? get error => _startup?.error ?? _sourceError;

  /// Original trace associated with [error].
  StackTrace? get stackTrace => _startup?.stackTrace ?? _sourceTrace;

  bool _sourceCurrent() {
    if (_revoked) return false;
    try {
      final bool lost = !_isCurrent();
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object catch (error, trace) {
      _sourceError = error;
      _sourceTrace = trace;
      _revoked = true;
      return false;
    }
  }

  bool _eligibleState({required bool consumed}) =>
      _consumed == consumed &&
      identical(_owner._startReservation, _token) &&
      !_owner._started &&
      _owner._work.accepting &&
      _owner._cycle == null &&
      _owner._work.operations.isEmpty &&
      _owner._operations.isEmpty;

  bool _eligible({required bool consumed}) =>
      _eligibleState(consumed: consumed) &&
      _sourceCurrent() &&
      _eligibleState(consumed: consumed);

  /// Whether the exact unused token and original source still admit startup.
  bool get canActivate => _eligible(consumed: false);

  /// The caller publishes its exact committed globals synchronously after this
  /// returns. No RPC or source capture can run before that same stack unwinds.
  bool activate() {
    if (_consumed) return false;
    _consumed = true;
    if (!_eligible(consumed: true)) return false;
    _invoked = true;
    _owner._reservedAdmission = _sourceCurrent;
    _owner._started = true;
    final HtlcOperationReceipt receipt = HtlcOperationReceipt(
      'reserved-handler-startup',
    );
    _startup = receipt;
    _owner._operations.add(receipt);
    scheduleMicrotask(() {
      final Future<void> original = receipt.run<void>(() {
        if (!_sourceCurrent() ||
            _owner.isPaused ||
            !_owner.hasStarted ||
            !identical(_owner._startReservation, _token)) {
          if (_sourceError != null) {
            Error.throwWithStackTrace(_sourceError!, _sourceTrace!);
          }
          throw const HtlcOwnershipRefused('reserved-start-source-unavailable');
        }
        return _owner._beginTick();
      });
      unawaited(
        original.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    });
    return true;
  }
}

bool _ownedBlock(AccountBlock block, int chain, int height) =>
    height > 0 &&
    block.height == height &&
    block.address == htlcAddress &&
    block.chainIdentifier == chain &&
    block.hash != emptyHash &&
    block.confirmationDetail != null &&
    block.confirmationDetail!.numConfirmations > 0 &&
    block.confirmationDetail!.momentumTimestamp > 0;

bool _liveMatches(HtlcSwap record, HtlcInfo live, String id) {
  final bool initial = id == record.initialHtlcId;
  final bool own = initial == (record.direction == P2pSwapDirection.outgoing);
  return live.id.toString() == id &&
      live.timeLocked.toString() ==
          (own ? record.selfAddress : record.counterpartyAddress) &&
      live.hashLocked.toString() ==
          (own ? record.counterpartyAddress : record.selfAddress) &&
      live.amount == (own ? record.fromAmount : record.toAmount) &&
      live.tokenStandard.toString() ==
          (own ? record.fromTokenStandard : record.toTokenStandard) &&
      live.hashType == record.hashType &&
      FormatUtils.encodeHexString(live.hashLock) == record.hashLock &&
      live.expirationTime ==
          (initial
              ? record.initialHtlcExpirationTime
              : record.counterHtlcExpirationTime);
}
