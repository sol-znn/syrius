import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_creation_proof.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'htlc_store_capture.dart';

/// Owns the original encrypted backends and their admitted serial operations.
class HtlcSwapsService {
  /// Owns exact backends returned by [openBox] and verified by [ownsBox].
  HtlcSwapsService({
    Future<Box<dynamic>> Function(String, List<int>)? openBox,
    bool Function(Box<dynamic>)? ownsBox,
  }) : _openBox = openBox ?? _openHiveBox,
       _ownsBox = ownsBox ?? _hiveOwns {
    _work = HtlcOwnedWork(this, ownsResources: _ownsCapturedBackends);
  }

  /// Returns the compatibility singleton without reviving terminal admission.
  factory HtlcSwapsService.shared() => _instance ??= HtlcSwapsService();

  /// Injects finite backends without opening or discovering a Box by name.
  HtlcSwapsService.bound({
    required Box<dynamic> swaps,
    required Box<dynamic> cursor,
    required this._ownsBox,
  }) : _openBox = _openHiveBox,
       _swaps = swaps,
       _cursor = cursor {
    _claims[swaps] = _owner;
    _claims[cursor] = _owner;
    _work = HtlcOwnedWork(this, ownsResources: _ownsCapturedBackends);
  }

  static HtlcSwapsService? _instance;
  static final Expando<Object> _claims = Expando<Object>();
  static final Expando<HtlcSerialLane> _lanes = Expando<HtlcSerialLane>();
  static final Map<String, HtlcSerialLane> _openLanes =
      <String, HtlcSerialLane>{};
  final Object _owner = Object();
  final Future<Box<dynamic>> Function(String, List<int>) _openBox;
  final bool Function(Box<dynamic>) _ownsBox;
  late final HtlcOwnedWork _work;
  final HtlcSerialLane _lifecycle = HtlcSerialLane();
  final List<HtlcOperationReceipt> _backendOperations =
      <HtlcOperationReceipt>[];
  Box<dynamic>? _swaps;
  Box<dynamic>? _cursor;
  Future<void>? _opening;
  Future<void>? _closing;
  Future<HtlcDrainReceipt>? _pause;
  _OpeningBackends? _openingBackends;
  bool _uncertain = false;

  /// Whether this original service has closed admission permanently.
  bool get isPaused => !_work.accepting;

  static Future<Box<dynamic>> _openHiveBox(String name, List<int> key) async {
    final HtlcSerialTurn turn = (_openLanes[name] ??= HtlcSerialLane())
        .reserve();
    try {
      await turn.ready;
      if (name == kLastCheckedHtlcBlockBox) {
        return await Hive.openBox<dynamic>(name);
      }
      if (Hive.isBoxOpen(name)) {
        throw const HtlcOwnershipRefused(
          'preopened-encrypted-backend-unproven',
        );
      }
      return await Hive.openBox<dynamic>(
        name,
        encryptionCipher: HiveAesCipher(key),
      );
    } finally {
      turn.release();
    }
  }

  static bool _hiveOwns(Box<dynamic> box) =>
      box.isOpen &&
      Hive.isBoxOpen(box.name) &&
      identical(Hive.box<dynamic>(box.name), box);

  bool _owns(Box<dynamic> box) =>
      !_uncertain &&
      identical(_claims[box], _owner) &&
      box.isOpen &&
      _ownsBox(box);
  bool _ownsCapturedBackends() =>
      _swaps != null && _cursor != null && _owns(_swaps!) && _owns(_cursor!);
  HtlcSerialLane _lane(Box<dynamic> box) => _lanes[box] ??= HtlcSerialLane();

  /// Original lifecycle, reserved write and actual backend operation receipts.
  List<HtlcOperationReceipt> get operations =>
      List<HtlcOperationReceipt>.unmodifiable(<HtlcOperationReceipt>[
        ..._work.operations,
        ..._backendOperations,
      ]);

  Future<T> _observe<T>(String name, Future<T> Function() call) async {
    final HtlcOperationReceipt operation = HtlcOperationReceipt(name);
    _backendOperations.add(operation);
    try {
      return await operation.run<T>(call);
    } on Object {
      _uncertain = true;
      rethrow;
    }
  }

  /// Frozen W01 API: the actual original open backend, without a name lookup.
  Box<dynamic>? captureSwapsBox() {
    final Box<dynamic>? original = _swaps;
    return original != null && ownsSwapsBox(original) ? original : null;
  }

  /// Frozen W01 API: exact selected, registered and open backend identity.
  bool ownsSwapsBox(Box<dynamic> original) =>
      identical(_swaps, original) && _owns(original);

  /// Captures the exact backends for independently owned original writes.
  HtlcStoreCapture? captureStore({required int chainId}) {
    final Box<dynamic>? swaps = _swaps;
    final Box<dynamic>? cursor = _cursor;
    if (!_work.accepting ||
        chainId <= 0 ||
        swaps == null ||
        cursor == null ||
        !_owns(swaps) ||
        !_owns(cursor)) {
      return null;
    }
    return HtlcStoreCapture._(this, swaps, cursor, chainId);
  }

  /// Whether complete current-chain history reaches the retained-record limit.
  bool get isMaxSwapsReached =>
      _current().readAll().length >= kMaxP2pSwapsToStore;

  /// A cipher change has no atomic rollback primitive in the existing backend.
  /// Refuses before opening or deleting, retaining original evidence.
  Future<void> openBoxes(
    String suffix,
    List<int> cipherKey, {
    List<int>? newCipherKey,
  }) {
    if (!_work.accepting) {
      return Future<void>.error(const HtlcOwnershipRefused('store-paused'));
    }
    if (_opening != null) {
      return Future<void>.error(
        const HtlcOwnershipRefused('store-open-in-progress'),
      );
    }
    final String name = '${kHtlcSwapsBox}_$suffix';
    final List<int> key = List<int>.unmodifiable(cipherKey);
    final Box<dynamic>? originalSwaps = _swaps;
    final Box<dynamic>? originalCursor = _cursor;
    final _OpeningBackends backends = _OpeningBackends();
    _openingBackends = backends;
    final HtlcSerialTurn turn = _lifecycle.reserve();
    final Future<void> operation = _work.admit<void>('open', () async {
      try {
        await turn.ready;
        if (newCipherKey != null) {
          throw const HtlcOwnershipRefused('cipher-migration-unproven');
        }
        if (originalSwaps != null || originalCursor != null) {
          if (originalSwaps == null ||
              originalCursor == null ||
              originalSwaps.name != name ||
              !_owns(originalSwaps) ||
              !_owns(originalCursor)) {
            throw const HtlcOwnershipRefused('store-open-owner-changed');
          }
          return;
        }
        final Box<dynamic> swaps = await _observe<Box<dynamic>>(
          'open-swaps',
          () => _openBox(name, key),
        );
        if (!swaps.isOpen ||
            !_ownsBox(swaps) ||
            (_claims[swaps] != null && !identical(_claims[swaps], _owner))) {
          throw const HtlcOwnershipRefused('opened-swaps-unowned');
        }
        _claims[swaps] = _owner;
        backends.swaps = swaps;
        _swaps = swaps;
        final Box<dynamic> cursor = await _observe<Box<dynamic>>(
          'open-cursor',
          () => _openBox(kLastCheckedHtlcBlockBox, key),
        );
        if (!cursor.isOpen ||
            !_ownsBox(cursor) ||
            (_claims[cursor] != null && !identical(_claims[cursor], _owner))) {
          throw const HtlcOwnershipRefused('opened-cursor-unowned');
        }
        _claims[cursor] = _owner;
        backends.cursor = cursor;
        _cursor = cursor;
      } finally {
        turn.release();
      }
    });
    _opening = operation;
    // Retire only the owned attempt; this observer never replaces its failure.
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_opening, operation)) _opening = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_opening, operation)) _opening = null;
        },
      ),
    );
    return operation;
  }

  /// Closes admission and waits for every original reserved and backend Future.
  /// Unknown persistence keeps the result negative and prevents cleanup.
  Future<HtlcDrainReceipt> pauseAndDrain() {
    if (_pause != null) return _pause!;
    final Future<HtlcDrainReceipt> original = _work.pauseAndDrain();
    final Future<HtlcDrainReceipt> result = () async {
      final HtlcDrainReceipt receipt = await original;
      final List<HtlcOperationReceipt> children = List<HtlcOperationReceipt>.of(
        _backendOperations,
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

  /// No close starts until every reserved original write has a positive finish.
  Future<void> closeBoxes() {
    final Future<void>? existing = _closing;
    if (existing != null) return existing;
    final Box<dynamic>? swaps = _swaps;
    final Box<dynamic>? cursor = _cursor;
    final Future<void>? opening = _opening;
    final _OpeningBackends? openingBackends = _openingBackends;
    final Future<HtlcDrainReceipt> drain = pauseAndDrain();
    final Future<void> operation = () async {
      if (opening != null) await opening;
      final Box<dynamic>? originalSwaps = swaps ?? openingBackends?.swaps;
      final Box<dynamic>? originalCursor = cursor ?? openingBackends?.cursor;
      final HtlcDrainReceipt receipt = await drain;
      if (!identical(receipt.owner, this) ||
          !receipt.completed ||
          originalSwaps == null ||
          originalCursor == null) {
        Error.throwWithStackTrace(
          receipt.error ?? const HtlcOwnershipRefused('store-drain-unproven'),
          receipt.stackTrace ?? StackTrace.current,
        );
      }
      for (final Box<dynamic> box in <Box<dynamic>>[
        originalSwaps,
        originalCursor,
      ]) {
        final HtlcSerialTurn turn = _lane(box).reserve();
        try {
          await turn.ready;
          if (!_owns(box)) {
            throw const HtlcOwnershipRefused('close-backend-unowned');
          }
          await _observe<void>('flush-before-close', box.flush);
          if (!_owns(box)) {
            throw const HtlcOwnershipRefused('close-backend-replaced');
          }
          await _observe<void>('close', box.close);
          if (box.isOpen) {
            throw const HtlcOwnershipRefused('close-not-confirmed');
          }
          _claims[box] = null;
          if (identical(_swaps, box)) _swaps = null;
          if (identical(_cursor, box)) _cursor = null;
        } finally {
          turn.release();
        }
      }
    }();
    _closing = operation;
    return operation;
  }

  HtlcStoreCapture _current() {
    final int? chain = kNodeChainId;
    final HtlcStoreCapture? captured = chain == null
        ? null
        : captureStore(chainId: chain);
    if (captured == null) {
      throw const HtlcOwnershipRefused('store-not-captured');
    }
    return captured;
  }

  /// Reads complete chain history, excluding validated private metadata.
  List<HtlcSwap> getAllSwaps() => _current().readAll();

  /// Filters a complete current-chain catalogue by recorded state.
  List<HtlcSwap> getSwapsByState(List<P2pSwapState> states) => getAllSwaps()
      .where((HtlcSwap value) => states.contains(value.state))
      .toList();

  /// Finds a unique recorded hash lock without claiming deposit liveness.
  HtlcSwap? getSwapByHashLock(String hash) =>
      _current().getSwapByHashLock(hash);

  /// Finds history by either exact initial or counterdeposit identifier.
  HtlcSwap? getSwapByHtlcId(String id) => _current().getSwapByHtlcId(id);

  /// Finds history by its exact catalogue key.
  HtlcSwap? getSwapById(String id) => _current().getSwapById(id);

  /// Reads the height from a validated atomic height-and-hash cursor.
  int getLastCheckedHtlcBlockHeight() => _current().readCursor().height;

  /// Captures the record's original chain store before reserving persistence.
  Future<void> storeSwap(HtlcSwap swap) {
    final HtlcStoreCapture? original = captureStore(chainId: swap.chainId);
    if (original == null) {
      return Future<void>.error(
        const HtlcOwnershipRefused('store-not-captured'),
      );
    }
    return original.storeSwap(swap);
  }

  /// Refuses a legacy height-only write that cannot prove an anchor hash.
  Future<void> storeLastCheckedHtlcBlockHeight(int height) =>
      Future<void>.error(
        const HtlcOwnershipRefused('cursor-hash-proof-required'),
      );

  /// Deletes only inactive exact history with no retained recovery anchor.
  Future<void> deleteSwap(String id) => _current().deleteIds(<String>[id]);

  /// Captures one complete catalogue before deleting eligible inactive rows.
  Future<void> deleteInactiveSwaps() {
    final HtlcStoreCapture original = _current();
    return original.deleteIds(
      original
          .readAll()
          .where(_inactive)
          .map((HtlcSwap value) => value.id)
          .toList(),
    );
  }
}

class _OpeningBackends {
  Box<dynamic>? swaps;
  Box<dynamic>? cursor;
}

bool _inactive(HtlcSwap swap) =>
    swap.state == P2pSwapState.completed ||
    swap.state == P2pSwapState.unsuccessful;
