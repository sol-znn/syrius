import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/base_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_worker_origin.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/notification_type.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_creation_proof.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

typedef _UnlockKey = (int, String, String);

class _UnlockRequest {
  _UnlockRequest(this.origin, this.swap, this.reservation);
  final HtlcWorkerOrigin origin;
  final HtlcSwap swap;
  final HtlcUnlockWriteRequest reservation;
  _UnlockKey get key => (origin.chainId, swap.initialHtlcId, swap.selfAddress);
  bool invokingSender = false;
  bool accepted = false;
  AccountBlockTemplate? originalResponse;
  Object? originalError;
  StackTrace? originalStack;
}

/// Only exact owned recipients can use the existing signer. No timer retries.
class AutoUnlockHtlcWorker extends BaseBloc<WalletNotification> {
  /// Uses finite injected capabilities or captures the registered wallet owner.
  AutoUnlockHtlcWorker({HtlcWorkerOrigin? Function()? captureOrigin})
    : _originSource = captureOrigin {
    _work = HtlcOwnedWork(this);
  }

  /// Returns the compatibility singleton; terminally paused owners stay paused.
  factory AutoUnlockHtlcWorker.shared() => _instance ??= AutoUnlockHtlcWorker();
  static AutoUnlockHtlcWorker? _instance;
  static final Map<_UnlockKey, _UnlockRequest> _journal =
      <_UnlockKey, _UnlockRequest>{};
  final HtlcWorkerOrigin? Function()? _originSource;
  late final HtlcOwnedWork _work;
  final Queue<_UnlockRequest> _queue = Queue<_UnlockRequest>();
  final List<HtlcOperationReceipt> _operations = <HtlcOperationReceipt>[];
  Future<void>? _drain;
  Future<HtlcDrainReceipt>? _pause;

  /// Whether the original admitted queue drain still owns its Future.
  bool get running => _drain != null;

  /// Whether terminal pause has synchronously closed further admission.
  bool get isPaused => !_work.accepting;

  /// Snapshot of queued initial deposit identifiers, excluding active work.
  Queue<Hash> get pool => Queue<Hash>.of(
    _queue.map((_UnlockRequest value) => Hash.parse(value.swap.initialHtlcId)),
  );

  /// Retained admission keys, including unknown outcomes rather than only
  /// confirmed withdrawals. This view is never proof of chain completion.
  HashSet<Hash> get processedHashes => HashSet<Hash>.of(
    _journal.keys.map((_UnlockKey key) => Hash.parse(key.$2)),
  );

  /// Original queue, RPC, publication, persistence and notification receipts.
  List<HtlcOperationReceipt> get operations =>
      List<HtlcOperationReceipt>.unmodifiable(<HtlcOperationReceipt>[
        ..._work.operations,
        ..._operations,
      ]);

  HtlcWorkerOrigin? _capture() => _originSource != null
      ? _originSource()
      : captureHtlcWorkerOrigin(
          ownerIsCurrent: () =>
              app.sl.isRegistered<AutoUnlockHtlcWorker>() &&
              identical(app.sl<AutoUnlockHtlcWorker>(), this),
        );

  Future<T> _observe<T>(String name, Future<T> Function() call) {
    final HtlcOperationReceipt operation = HtlcOperationReceipt(name);
    _operations.add(operation);
    return operation.run<T>(call);
  }

  /// Captures exact record, store reservation and recipient before sync RPC.
  Future<void> addHash(Hash hash, {HtlcWorkerOrigin? origin}) {
    if (!_work.accepting) {
      return Future<void>.error(
        const HtlcOwnershipRefused('unlock-worker-paused'),
      );
    }
    final HtlcWorkerOrigin? original = origin ?? _capture();
    if (original == null ||
        !original.isCurrent ||
        !original.canNotify ||
        hash == emptyHash) {
      return Future<void>.error(
        const HtlcOwnershipRefused('unlock-origin-unproven'),
      );
    }
    final HtlcSwap? found = original.store.getSwapByHtlcId(hash.toString());
    if (found == null ||
        found.direction != P2pSwapDirection.incoming ||
        found.initialHtlcId != hash.toString() ||
        found.preimage == null ||
        !original.members.contains(found.selfAddress) ||
        found.counterHtlcId == null ||
        !<P2pSwapState>[
          P2pSwapState.active,
          P2pSwapState.reclaimable,
        ].contains(found.state)) {
      return Future<void>.error(
        const HtlcOwnershipRefused('unlock-record-unproven'),
      );
    }
    final _UnlockKey key = (
      original.chainId,
      found.initialHtlcId,
      found.selfAddress,
    );
    if (_journal.containsKey(key) ||
        original.store.hasUnlockHold(found.initialHtlcId, found.selfAddress)) {
      return Future<void>.value();
    }
    final HtlcSwap swap = HtlcSwap.fromJson(found.toJson());
    final _UnlockRequest request = _UnlockRequest(
      original,
      swap,
      original.store.reserveUnlock(swap.initialHtlcId, swap.selfAddress),
    );
    _journal[key] = request;
    return _work.admit<void>('enqueue-unlock', () async {
      try {
        final SyncInfo sync = await _observe<SyncInfo>(
          'unlock-sync',
          original.readSync,
        );
        original.requireCurrent();
        if (!_work.accepting) {
          request.reservation.refuse();
          _journal.remove(key);
          return;
        }
        if (!(sync.state == SyncState.syncDone ||
            (sync.targetHeight > 0 &&
                sync.currentHeight > 0 &&
                sync.targetHeight >= sync.currentHeight &&
                sync.targetHeight - sync.currentHeight < 3))) {
          throw const HtlcOwnershipRefused('unlock-sync-unproven');
        }
        _queue.add(request);
      } on Object {
        if (!request.reservation.receipt.completed) {
          request.reservation.refuse();
        }
        if (identical(_journal[key], request)) _journal.remove(key);
        rethrow;
      }
    });
  }

  /// Drains already admitted requests once, retaining shared durable holds and
  /// exact accepted results; no timer or failure path retries publication.
  Future<void> autoUnlock() {
    final Future<void>? existing = _drain;
    if (existing != null) return existing;
    if (!_work.accepting || _queue.isEmpty) return Future<void>.value();
    final Future<void> original = _work.admit<void>('unlock-queue', () async {
      while (_work.accepting && _queue.isNotEmpty) {
        final _UnlockRequest request = _queue.removeFirst();
        await _unlock(request);
      }
    });
    _drain = original;
    unawaited(
      original.then<void>(
        (_) {
          if (identical(_drain, original)) _drain = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_drain, original)) _drain = null;
        },
      ),
    );
    return original;
  }

  Future<void> _unlock(_UnlockRequest request) async {
    final HtlcWorkerOrigin origin = request.origin;
    final HtlcSwap swap = request.swap;
    try {
      origin.requireCurrent();
      final HtlcSwap? current = origin.store.getSwapById(swap.id);
      if (current == null ||
          !const DeepCollectionEquality().equals(
            current.toJson(),
            swap.toJson(),
          )) {
        throw const HtlcOwnershipRefused('unlock-record-replaced');
      }
      final HtlcInfo rawLive = await _observe<HtlcInfo>(
        'unlock-live-deposit',
        () => origin.readLive(swap.initialHtlcId),
      );
      final HtlcInfo live = HtlcInfo.fromJson(rawLive.toJson());
      origin.requireCurrent();
      final AccountBlock? rawCreation = await _observe<AccountBlock?>(
        'unlock-initial-create',
        () => origin.readBlock(swap.initialHtlcId),
      );
      final AccountBlock? creation = rawCreation == null
          ? null
          : AccountBlock.fromJson(rawCreation.toJson());
      origin.requireCurrent();
      final AccountBlock? rawCounter = await _observe<AccountBlock?>(
        'unlock-counter-create',
        () => origin.readBlock(swap.counterHtlcId!),
      );
      final AccountBlock? counter = rawCounter == null
          ? null
          : AccountBlock.fromJson(rawCounter.toJson());
      origin.requireCurrent();
      final int chainTime = await _observe<int>(
        'unlock-chain-time',
        origin.readChainTime,
      );
      origin.requireCurrent();
      if (!htlcCreationMatches(swap, creation, initial: true) ||
          !htlcCreationMatches(swap, counter, initial: false) ||
          live.id.toString() != swap.initialHtlcId ||
          live.hashLocked.toString() != swap.selfAddress ||
          live.timeLocked.toString() != swap.counterpartyAddress ||
          live.amount != creation!.amount ||
          live.tokenStandard != creation.tokenStandard ||
          live.expirationTime != swap.initialHtlcExpirationTime ||
          live.hashType != swap.hashType ||
          FormatUtils.encodeHexString(live.hashLock) != swap.hashLock ||
          chainTime <= 0 ||
          live.expirationTime <= chainTime ||
          live.keyMaxSize !=
              htlcProofInteger(
                AccountBlockUtils.getDecodedBlockData(
                  Definitions.htlc,
                  creation.data,
                )?.params['keyMaxSize'],
              )) {
        throw const HtlcOwnershipRefused('unlock-fresh-proof-mismatch');
      }
      final List<int> value = List<int>.unmodifiable(
        FormatUtils.decodeHexString(swap.preimage!),
      );
      if (value.isEmpty ||
          value.length > live.keyMaxSize ||
          value.length > htlcPreimageMaxLength ||
          !await _observe<bool>(
            'unlock-key-proof',
            () => htlcPreimageMatches(swap.hashType, swap.hashLock, value),
          )) {
        throw const HtlcOwnershipRefused('unlock-key-proof-mismatch');
      }
      origin.requireCurrent();
      _requireOriginalRecord(request);
      if (!await _observe<bool>(
        'unlock-durable-claim',
        request.reservation.claim,
      )) {
        request.reservation.refuse();
        return;
      }
      origin.requireCurrent();
      _requireOriginalRecord(request);
      final AccountBlockTemplate block = origin.buildUnlock(
        swap.initialHtlcId,
        value,
      );
      final List<int> intent = List<int>.of(block.data);
      final BlockData? decoded = AccountBlockUtils.getDecodedBlockData(
        Definitions.htlc,
        intent,
      );
      if (block.toAddress != htlcAddress ||
          block.chainIdentifier != origin.chainId ||
          block.blockType != BlockTypeEnum.userSend.index ||
          block.amount != BigInt.zero ||
          decoded == null ||
          decoded.function != 'Unlock' ||
          decoded.params['id'].toString() != swap.initialHtlcId ||
          decoded.params['preimage'] is! List<int> ||
          !const ListEquality<int>().equals(
            decoded.params['preimage'] as List<int>,
            value,
          )) {
        throw const HtlcOwnershipRefused('unlock-template-mismatch');
      }
      final BigInt intendedAmount = block.amount;
      final TokenStandard intendedStandard = block.tokenStandard;
      request.invokingSender = true;
      final AccountBlockTemplate response =
          await _observe<AccountBlockTemplate>(
            'unlock-publication',
            () => origin.publish(block, swap.selfAddress),
          );
      request.originalResponse = response;
      final String acceptedHash = response.hash.toString();
      if (response.hash == emptyHash ||
          response.chainIdentifier != origin.chainId ||
          response.address.toString() != swap.selfAddress ||
          response.toAddress != htlcAddress ||
          response.blockType != BlockTypeEnum.userSend.index ||
          response.amount != intendedAmount ||
          response.tokenStandard != intendedStandard ||
          !const ListEquality<int>().equals(response.data, intent)) {
        throw const HtlcOwnershipRefused('unlock-publication-unknown');
      }
      request.accepted = true;
      // Acceptance retains the exact hash. Completion awaits the chain scanner.
      await _observe<void>(
        'unlock-accepted-journal',
        () => request.reservation.accept(acceptedHash),
      );
      await _observe<void>(
        'unlock-notification',
        () => origin.notify(
          WalletNotification(
            title: currentL10n.accountBlockPublishedNotificationTitle,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            details: currentL10n.transactionReceivedNotificationDetails(
              acceptedHash,
            ),
            type: NotificationType.paymentReceived,
            chainId: origin.chainId,
            transactionHash: acceptedHash,
          ),
        ),
      );
    } on Object catch (error, trace) {
      request
        ..originalError = error
        ..originalStack = trace;
      if (request.invokingSender ||
          request.reservation.receipt.original != null) {
        request.reservation.retainUnknown(error, trace);
      } else {
        try {
          request.reservation.refuse();
          if (identical(_journal[request.key], request)) {
            _journal.remove(request.key);
          }
        } on Object {
          // A durable publishing hold is retained even before a failed handoff.
          request.reservation.retainUnknown(error, trace);
        }
      }
      rethrow;
    }
  }

  void _requireOriginalRecord(_UnlockRequest request) {
    final HtlcSwap? value = request.origin.store.getSwapById(request.swap.id);
    if (value == null ||
        !const DeepCollectionEquality().equals(
          value.toJson(),
          request.swap.toJson(),
        )) {
      throw const HtlcOwnershipRefused('unlock-record-replaced');
    }
  }

  /// Closes admission and waits for all original request and backend outcomes.
  /// An uncertain publication produces a negative receipt without erasing it.
  Future<HtlcDrainReceipt> pauseAndDrain() {
    if (_pause != null) return _pause!;
    final Future<HtlcDrainReceipt> original = _work.pauseAndDrain();
    while (_queue.isNotEmpty) {
      final _UnlockRequest queued = _queue.removeFirst();
      queued.reservation.refuse();
      if (identical(_journal[queued.key], queued)) _journal.remove(queued.key);
    }
    final Future<HtlcDrainReceipt> result = () async {
      final HtlcDrainReceipt receipt = await original;
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
        completed: receipt.completed && failed == null,
        operations: <HtlcOperationReceipt>[...receipt.operations, ...children],
        error: receipt.error ?? failed?.error,
        stackTrace: receipt.stackTrace ?? failed?.stackTrace,
      );
    }();
    _pause = result;
    return result;
  }

  @override
  void dispose() {
    unawaited(pauseAndDrain());
    super.dispose();
  }
}
