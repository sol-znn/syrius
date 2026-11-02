part of 'htlc_swaps_service.dart';

/// An atomic chain-scoped cursor. Legacy cursor entries remain untouched.
class HtlcCursor {
  /// Pairs the last independently proven height and hash in one stored value.
  const HtlcCursor(this.height, this.hash);

  /// Last contiguous proven height, or zero for an absent new cursor.
  final int height;

  /// Exact hash at [height], with the empty hash only at zero.
  final String hash;
}

/// An encrypted history reference, revalidated against its exact chain event.
class HtlcWithdrawalReference {
  /// Identifies an original contract event without treating storage as proof.
  const HtlcWithdrawalReference(
    this.deposit,
    this.height,
    this.hash,
    this.method,
  );

  /// Exact initial or counterdeposit consumed by the observed effect.
  final String deposit;

  /// Confirmed contract-account event height, bounded by the committed cursor.
  final int height;

  /// Exact event hash used for subsequent ledger revalidation.
  final String hash;

  /// Observed ABI withdrawal method, either Unlock or Reclaim.
  final String method;
}

/// The public API holds exact resources; encoded records remain private.
class HtlcStoreCapture {
  HtlcStoreCapture._(this._service, this._swaps, this._cursor, this.chainId);
  final HtlcSwapsService _service;
  final Box<dynamic> _swaps;
  final Box<dynamic> _cursor;

  /// Positive chain scope fixed when the original backends were captured.
  final int chainId;
  static const String _privatePrefix = '_htlc-private:v1:';
  bool _revoked = false;
  bool _selectionRevoked = false;

  /// Exact original encrypted catalogue Box identity.
  Object get identity => _swaps;

  /// Exact original chain-cursor Box identity.
  Object get cursorIdentity => _cursor;

  /// Original service and backend operation receipts, including reservations.
  List<HtlcOperationReceipt> get operations => _service.operations;

  /// Monotonic ownership of both original backends, independent of selection.
  bool get ownsStore {
    if (_revoked) return false;
    try {
      final bool lost = !_service._owns(_swaps) || !_service._owns(_cursor);
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Whether this service still selects the owned original backends.
  bool get isCurrent {
    if (_selectionRevoked) return false;
    final bool lost =
        !ownsStore ||
        !identical(_service._swaps, _swaps) ||
        !identical(_service._cursor, _cursor);
    _selectionRevoked = _selectionRevoked || lost;
    return !_selectionRevoked;
  }

  void _require() {
    if (!ownsStore) throw const HtlcOwnershipRefused('original-store-unowned');
  }

  /// The complete Box remains guarded; typed private metadata is never a row.
  bool isHistoryEntry(String key, Object? encoded) {
    _require();
    if (!key.startsWith(_privatePrefix)) return true;
    if (encoded is! String) {
      throw const HtlcOwnershipRefused('private-metadata-incomplete');
    }
    final dynamic marker = jsonDecode(encoded);
    if (marker is Map && marker['kind'] == 'observed-withdrawal') {
      if (marker['chain'] is! int ||
          (marker['chain'] as int) <= 0 ||
          marker['owner'] is! String ||
          Address.parse(marker['owner'] as String).toString() !=
              marker['owner'] ||
          marker['deposit'] is! String ||
          Hash.parse(marker['deposit'] as String) == emptyHash ||
          Hash.parse(marker['deposit'] as String).toString() !=
              marker['deposit'] ||
          marker['height'] is! int ||
          (marker['height'] as int) <= 0 ||
          marker['hash'] is! String ||
          Hash.parse(marker['hash'] as String) == emptyHash ||
          Hash.parse(marker['hash'] as String).toString() != marker['hash'] ||
          !<String>['Unlock', 'Reclaim'].contains(marker['method']) ||
          key !=
              '${_privatePrefix}observed-withdrawal:v1:${marker['chain']}:'
                  '${marker['deposit']}:${marker['owner']}') {
        throw const HtlcOwnershipRefused('private-withdrawal-incomplete');
      }
      return false;
    }
    if (marker is! Map ||
        marker['chain'] is! int ||
        (marker['chain'] as int) <= 0 ||
        marker['owner'] is! String ||
        Address.parse(marker['owner'] as String).toString() !=
            marker['owner'] ||
        marker['claim'] is! String ||
        !<String>['publishing', 'accepted'].contains(marker['status']) ||
        (marker['status'] == 'accepted' &&
            (marker['hash'] is! String ||
                Hash.parse(marker['hash'] as String) == emptyHash ||
                Hash.parse(marker['hash'] as String).toString() !=
                    marker['hash']))) {
      throw const HtlcOwnershipRefused('private-metadata-incomplete');
    }
    if (marker['deposit'] is String) {
      if (Hash.parse(marker['deposit'] as String) == emptyHash ||
          Hash.parse(marker['deposit'] as String).toString() !=
              marker['deposit'] ||
          key !=
              '${_privatePrefix}unlock:v1:${marker['chain']}:'
                  '${marker['deposit']}:${marker['owner']}') {
        throw const HtlcOwnershipRefused('private-unlock-identity-mismatch');
      }
    } else if (!<String>[
          'start',
          'join',
          'complete',
          'reclaim',
          'recover',
        ].contains(marker['kind']) ||
        marker['target'] is! String ||
        (marker['kind'] == 'start'
            ? marker['target'] != 'new' || marker['recovery'] is! Map
            : Hash.parse(marker['target'] as String) == emptyHash ||
                  Hash.parse(marker['target'] as String).toString() !=
                      marker['target']) ||
        key !=
            '${_privatePrefix}action:v1:${marker['chain']}:${marker['kind']}:'
                '${marker['target']}:${marker['owner']}') {
      throw const HtlcOwnershipRefused('private-action-identity-mismatch');
    }
    return false;
  }

  dynamic _readMarker(String key) {
    if (!_swaps.containsKey(key)) return null;
    final dynamic encoded = _swaps.get(key);
    if (isHistoryEntry(key, encoded)) {
      throw const HtlcOwnershipRefused('private-marker-key-mismatch');
    }
    return jsonDecode(encoded as String);
  }

  bool _matchesMarker(String key, Map<String, dynamic>? expected) =>
      expected != null && _swaps.get(key) == jsonEncode(expected);
  Future<void> _putMarker(String key, Map<String, dynamic> marker) =>
      _swaps.put(key, jsonEncode(marker));

  /// Reads a complete unchanged original catalogue, validating private metadata
  /// before excluding it and refusing partial or replaced history.
  List<HtlcSwap> readAll() {
    _require();
    final Map<dynamic, dynamic> original = Map<dynamic, dynamic>.of(
      _swaps.toMap(),
    );
    final List<HtlcSwap> result = <HtlcSwap>[];
    for (final MapEntry<dynamic, dynamic> entry in original.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const HtlcOwnershipRefused('record-incomplete');
      }
      if (!isHistoryEntry(entry.key as String, entry.value)) continue;
      final dynamic decoded = jsonDecode(entry.value as String);
      if (decoded is! Map<String, dynamic>) {
        throw const HtlcOwnershipRefused('record-incomplete');
      }
      final HtlcSwap swap = HtlcSwap.fromJson(decoded);
      if (swap.id != entry.key) {
        throw const HtlcOwnershipRefused('record-key-mismatch');
      }
      if (swap.chainId == chainId) result.add(swap);
    }
    _require();
    if (_swaps.length != original.length ||
        original.entries.any(
          (MapEntry<dynamic, dynamic> entry) =>
              !_swaps.containsKey(entry.key) ||
              _swaps.get(entry.key) != entry.value,
        )) {
      throw const HtlcOwnershipRefused('catalogue-changed');
    }
    return result;
  }

  /// Finds a unique exact catalogue key in the complete captured chain history.
  HtlcSwap? getSwapById(String id) =>
      readAll().singleWhereOrNull((HtlcSwap value) => value.id == id);

  /// Finds a unique record by exact initial or counterdeposit identifier.
  HtlcSwap? getSwapByHtlcId(String id) => readAll().singleWhereOrNull(
    (HtlcSwap value) => value.initialHtlcId == id || value.counterHtlcId == id,
  );

  /// Finds a unique recorded hash lock, without inferring current live state.
  HtlcSwap? getSwapByHashLock(String hash) =>
      readAll().singleWhereOrNull((HtlcSwap value) => value.hashLock == hash);

  String _withdrawalKey(String deposit, String owner) =>
      '${_privatePrefix}observed-withdrawal:v1:$chainId:$deposit:$owner';

  /// Returns a validated encrypted event reference that still requires exact
  /// ledger proof before it can replace a current live-deposit read.
  HtlcWithdrawalReference? readObservedWithdrawal(
    String deposit,
    String owner,
  ) {
    _require();
    final Map<dynamic, dynamic>? marker =
        _readMarker(_withdrawalKey(deposit, owner)) as Map<dynamic, dynamic>?;
    if (marker == null) return null;
    return HtlcWithdrawalReference(
      marker['deposit'] as String,
      marker['height'] as int,
      marker['hash'] as String,
      marker['method'] as String,
    );
  }

  /// The caller proves the original confirmed effect before committing this
  /// reference. Reading it alone never establishes a spent deposit.
  Future<void> storeObservedWithdrawal(
    HtlcSwap original, {
    required String deposit,
    required int height,
    required String hash,
    required String method,
  }) {
    _require();
    if (original.chainId != chainId ||
        (deposit != original.initialHtlcId &&
            deposit != original.counterHtlcId) ||
        height <= 0 ||
        Hash.parse(hash) == emptyHash ||
        Hash.parse(hash).toString() != hash ||
        !<String>['Unlock', 'Reclaim'].contains(method)) {
      return Future<void>.error(
        const HtlcOwnershipRefused('observed-withdrawal-identity-unproven'),
      );
    }
    final String originalId = original.id;
    final String owner = original.selfAddress;
    final String expected = jsonEncode(original.toJson());
    final String key = _withdrawalKey(deposit, owner);
    final Map<String, dynamic> marker = <String, dynamic>{
      'kind': 'observed-withdrawal',
      'chain': chainId,
      'deposit': deposit,
      'owner': owner,
      'height': height,
      'hash': hash,
      'method': method,
    };
    final String encoded = jsonEncode(marker);
    final HtlcOperationReceipt reservation = _service._work.reserve(
      'observed-withdrawal-write',
    );
    final HtlcSerialTurn turn = _service._lane(_swaps).reserve();
    return reservation.run<void>(() async {
      try {
        await turn.ready;
        _require();
        if (_swaps.get(originalId) != expected ||
            (_swaps.containsKey(key) && _swaps.get(key) != encoded)) {
          throw const HtlcOwnershipRefused('observed-withdrawal-replaced');
        }
        await _service._observe<void>(
          'put-observed-withdrawal',
          () => _swaps.put(key, encoded),
        );
        _require();
        await _service._observe<void>(
          'flush-observed-withdrawal',
          _swaps.flush,
        );
      } finally {
        turn.release();
      }
    });
  }

  String get _cursorKey => '$kLastCheckedHtlcBlockKey:v2:$chainId';

  /// Reads the atomic chain cursor without resetting malformed legacy values.
  HtlcCursor readCursor() {
    _require();
    if (!_cursor.containsKey(_cursorKey)) {
      _require();
      if (_cursor.containsKey(_cursorKey)) {
        throw const HtlcOwnershipRefused('cursor-changed');
      }
      return HtlcCursor(0, emptyHash.toString());
    }
    final dynamic value = _cursor.get(_cursorKey);
    if (value is! Map ||
        value['chain'] != chainId ||
        value['height'] is! int ||
        (value['height'] as int) <= 0 ||
        value['hash'] is! String ||
        Hash.parse(value['hash'] as String) == emptyHash ||
        Hash.parse(value['hash'] as String).toString() != value['hash']) {
      throw const HtlcOwnershipRefused('cursor-incomplete');
    }
    final int height = value['height'] as int;
    final String hash = value['hash'] as String;
    _require();
    if (!const DeepCollectionEquality().equals(
      _cursor.get(_cursorKey),
      <String, dynamic>{'chain': chainId, 'height': height, 'hash': hash},
    )) {
      throw const HtlcOwnershipRefused('cursor-changed');
    }
    return HtlcCursor(height, hash);
  }

  /// Reserves persistence against the complete original catalogue before RPC.
  HtlcStoreWriteRequest reserveWrite() {
    _require();
    readAll();
    final Map<dynamic, dynamic> originals = Map<dynamic, dynamic>.of(
      _swaps.toMap(),
    );
    _require();
    return HtlcStoreWriteRequest._(
      this,
      originals,
      _service._work.reserve('reserved-swap-write'),
    );
  }

  /// Reserves and persists one record through its exact original Box lane.
  Future<void> storeSwap(HtlcSwap swap) => reserveWrite().storeSwap(swap);

  Future<void> _persist(
    String id,
    String encoded, {
    String? expected,
    bool expectAbsent = false,
  }) async {
    final HtlcSerialTurn turn = _service._lane(_swaps).reserve();
    try {
      await turn.ready;
      _require();
      if ((expected != null && _swaps.get(id) != expected) ||
          (expectAbsent && _swaps.containsKey(id))) {
        throw const HtlcOwnershipRefused('record-replaced');
      }
      await _service._observe<void>('put-swap', () => _swaps.put(id, encoded));
      _require();
      await _service._observe<void>('flush-swap', _swaps.flush);
    } finally {
      turn.release();
    }
  }

  /// Updates require the exact original record, including its private fields.
  Future<void> replaceSwap(HtlcSwap before, HtlcSwap after) {
    _require();
    if (before.id != after.id ||
        before.chainId != chainId ||
        after.chainId != chainId) {
      return Future<void>.error(
        const HtlcOwnershipRefused('replacement-identity-mismatch'),
      );
    }
    final String expected = jsonEncode(before.toJson());
    final String encoded = jsonEncode(after.toJson());
    return _service._work.admit<void>(
      'replace-swap',
      () => _persist(after.id, encoded, expected: expected),
    );
  }

  /// Commits one next contiguous height and exact hash together, with a flush.
  Future<void> storeCursor(int height, String hash) {
    _require();
    if (height <= 0 ||
        Hash.parse(hash) == emptyHash ||
        Hash.parse(hash).toString() != hash) {
      return Future<void>.error(
        const HtlcOwnershipRefused('cursor-proof-incomplete'),
      );
    }
    final Map<String, dynamic> value = <String, dynamic>{
      'chain': chainId,
      'height': height,
      'hash': hash,
    };
    final HtlcOperationReceipt reservation = _service._work.reserve(
      'cursor-write',
    );
    final HtlcSerialTurn turn = _service._lane(_cursor).reserve();
    return reservation.run<void>(() async {
      try {
        await turn.ready;
        _require();
        final HtlcCursor before = readCursor();
        if (height != before.height + 1) {
          throw const HtlcOwnershipRefused('cursor-not-contiguous');
        }
        await _service._observe<void>(
          'put-cursor',
          () => _cursor.put(_cursorKey, value),
        );
        _require();
        await _service._observe<void>('flush-cursor', _cursor.flush);
      } finally {
        turn.release();
      }
    });
  }

  /// Deletes only exact inactive rows after rechecking original records and
  /// durable recovery anchors on their original serial Box lane.
  Future<void> deleteIds(List<String> ids) {
    _require();
    if (ids.isEmpty) return Future<void>.value();
    final Map<String, String> originals = <String, String>{};
    final List<HtlcSwap> records = <HtlcSwap>[];
    for (final String id in ids) {
      final HtlcSwap? value = getSwapById(id);
      if (value == null || !_inactive(value)) {
        throw const HtlcOwnershipRefused('delete-record-unowned');
      }
      if (_startAnchorHeld(value)) {
        throw const HtlcOwnershipRefused('delete-recovery-anchor-held');
      }
      records.add(value);
      originals[id] = _swaps.get(id) as String;
    }
    final HtlcOperationReceipt reservation = _service._work.reserve(
      'delete-inactive',
    );
    final HtlcSerialTurn turn = _service._lane(_swaps).reserve();
    return reservation.run<void>(() async {
      try {
        await turn.ready;
        _require();
        if (originals.entries.any(
          (MapEntry<String, String> entry) =>
              _swaps.get(entry.key) != entry.value,
        )) {
          throw const HtlcOwnershipRefused('delete-record-replaced');
        }
        if (records.any(_startAnchorHeld)) {
          throw const HtlcOwnershipRefused('delete-recovery-anchor-held');
        }
        await _service._observe<void>(
          'delete-inactive',
          () => _swaps.deleteAll(originals.keys),
        );
        _require();
        await _service._observe<void>('flush-delete', _swaps.flush);
      } finally {
        turn.release();
      }
    });
  }

  bool _startAnchorHeld(HtlcSwap record) {
    _require();
    final String key = _actionKey('start', 'new', record.selfAddress);
    if (!_swaps.containsKey(key)) return false;
    final dynamic marker = _readMarker(key);
    if (marker is! Map ||
        marker['chain'] != chainId ||
        marker['owner'] != record.selfAddress ||
        marker['kind'] != 'start' ||
        marker['target'] != 'new' ||
        !<String>['publishing', 'accepted'].contains(marker['status']) ||
        marker['recovery'] is! Map) {
      throw const HtlcOwnershipRefused('recovery-anchor-incomplete');
    }
    return marker['hash'] == record.initialHtlcId ||
        (marker['recovery'] as Map<dynamic, dynamic>)['hashLock'] ==
            record.hashLock;
  }

  String _unlockKey(String id, String owner) =>
      '${_privatePrefix}unlock:v1:$chainId:$id:$owner';
  bool _hasWithdrawalHold(String id, String owner) {
    if (hasUnlockHold(id, owner)) return true;
    for (final String kind in <String>['complete', 'recover', 'reclaim']) {
      final String key = _actionKey(kind, id, owner);
      if (_swaps.containsKey(key)) {
        _readMarker(key);
        return true;
      }
    }
    return false;
  }

  /// Validates a durable automatic-withdrawal hold for this deposit and signer.
  bool hasUnlockHold(String id, String owner) {
    _require();
    final String key = _unlockKey(id, owner);
    if (!_swaps.containsKey(key)) return false;
    final dynamic value = _readMarker(key);
    if (value is! Map ||
        value['chain'] != chainId ||
        value['deposit'] != id ||
        value['owner'] != owner ||
        !<String>['publishing', 'accepted'].contains(value['status'])) {
      throw const HtlcOwnershipRefused('unlock-hold-incomplete');
    }
    return true;
  }

  /// Reserves the original unlock journal before any automatic-claim RPC.
  HtlcUnlockWriteRequest reserveUnlock(String id, String owner) {
    _require();
    if (Hash.parse(id) == emptyHash ||
        Hash.parse(id).toString() != id ||
        Address.parse(owner).toString() != owner) {
      throw const HtlcOwnershipRefused('unlock-identity-incomplete');
    }
    return HtlcUnlockWriteRequest._(
      this,
      id,
      owner,
      _service._work.reserve('reserved-unlock-journal'),
    );
  }

  static int _nextAction = 0;
  String _actionKey(String kind, String target, String owner) =>
      '${_privatePrefix}action:v1:$chainId:$kind:$target:$owner';

  /// Reserves one original durable action lifecycle before any action RPC.
  HtlcActionWriteRequest reserveAction({
    required String kind,
    required String targetId,
    required String owner,
  }) {
    _require();
    if (!<String>[
          'start',
          'join',
          'complete',
          'reclaim',
          'recover',
        ].contains(kind) ||
        (kind == 'start'
            ? targetId != 'new'
            : Hash.parse(targetId) == emptyHash ||
                  Hash.parse(targetId).toString() != targetId) ||
        Address.parse(owner).toString() != owner) {
      throw const HtlcOwnershipRefused('action-identity-incomplete');
    }
    return HtlcActionWriteRequest._(
      this,
      kind,
      targetId,
      owner,
      '${identityHashCode(_service._owner)}:${_nextAction++}',
      _service._work.reserve('reserved-durable-action'),
    );
  }

  /// Only explicit New deposit may release a positively accepted Start.
  Future<bool> rearmStart({
    required String owner,
    required AccountBlock creation,
    HtlcInfo? deposit,
  }) {
    _require();
    final String key = _actionKey('start', 'new', owner);
    final dynamic marker = _readMarker(key);
    final dynamic original = _swaps.get(key);
    if (!_swaps.containsKey(key) ||
        marker is! Map ||
        marker['status'] != 'accepted' ||
        marker['chain'] != chainId ||
        marker['kind'] != 'start' ||
        marker['target'] != 'new' ||
        marker['owner'] != owner ||
        marker['hash'] != creation.hash.toString() ||
        creation.hash == emptyHash ||
        creation.chainIdentifier != chainId ||
        creation.address.toString() != owner ||
        creation.toAddress != htlcAddress ||
        creation.blockType != BlockTypeEnum.userSend.index ||
        creation.confirmationDetail == null ||
        creation.confirmationDetail!.momentumTimestamp <= 0 ||
        marker['recovery'] is! Map) {
      return Future<bool>.value(false);
    }
    final Map<dynamic, dynamic> recovery =
        marker['recovery'] as Map<dynamic, dynamic>;
    final HtlcSwap? record = getSwapById(creation.hash.toString());
    if (record == null ||
        record.direction != P2pSwapDirection.outgoing ||
        record.id != record.initialHtlcId ||
        record.selfAddress != owner ||
        recovery['chainId'] != chainId ||
        recovery['selfAddress'] != owner ||
        recovery['recipient'] != record.counterpartyAddress ||
        recovery['amount'] != record.fromAmount.toString() ||
        recovery['tokenStandard'] != record.fromTokenStandard ||
        recovery['expirationTime'] != record.initialHtlcExpirationTime ||
        recovery['hashLock'] != record.hashLock ||
        recovery['hashType'] != record.hashType ||
        recovery['preimage'] is! String ||
        recovery['preimage'] != record.preimage ||
        recovery['startTime'] != record.startTime ||
        recovery['fromDecimals'] != record.fromDecimals ||
        recovery['fromSymbol'] != record.fromSymbol ||
        !htlcCreationMatches(record, creation, initial: true)) {
      return Future<bool>.value(false);
    }
    final String recordValue = _swaps.get(record.id) as String;
    final BlockData? data = AccountBlockUtils.getDecodedBlockData(
      Definitions.htlc,
      creation.data,
    );
    if (data == null ||
        data.function != 'Create' ||
        data.params['hashLock'] is! List<int> ||
        htlcProofInteger(data.params['keyMaxSize']) != recovery['keyMaxSize'] ||
        creation.confirmationDetail!.momentumTimestamp < record.startTime ||
        creation.confirmationDetail!.momentumTimestamp >=
            record.initialHtlcExpirationTime) {
      return Future<bool>.value(false);
    }
    if (deposit != null &&
        (deposit.id != creation.hash ||
            deposit.timeLocked.toString() != owner ||
            deposit.hashLocked.toString() != record.counterpartyAddress ||
            deposit.amount != creation.amount ||
            deposit.tokenStandard != creation.tokenStandard ||
            deposit.hashType != record.hashType ||
            deposit.expirationTime != record.initialHtlcExpirationTime ||
            deposit.keyMaxSize != recovery['keyMaxSize'] ||
            FormatUtils.encodeHexString(deposit.hashLock) != record.hashLock)) {
      return Future<bool>.value(false);
    }
    final List<int> preimage = List<int>.unmodifiable(
      FormatUtils.decodeHexString(recovery['preimage'] as String),
    );
    if (preimage.isEmpty || preimage.length > (recovery['keyMaxSize'] as int)) {
      return Future<bool>.value(false);
    }
    final HtlcOperationReceipt reservation = _service._work.reserve(
      'new-deposit-rearm',
    );
    final HtlcSerialTurn turn = _service._lane(_swaps).reserve();
    return reservation.run<bool>(() async {
      try {
        await turn.ready;
        _require();
        if (_swaps.get(record.id) != recordValue ||
            _swaps.get(key) != original) {
          throw const HtlcOwnershipRefused('new-deposit-rearm-marker-changed');
        }
        if (!await htlcPreimageMatches(
          record.hashType,
          record.hashLock,
          preimage,
        )) {
          throw const HtlcOwnershipRefused('new-deposit-recovery-unproven');
        }
        _require();
        if (_swaps.get(record.id) != recordValue ||
            _swaps.get(key) != original) {
          throw const HtlcOwnershipRefused('new-deposit-rearm-marker-changed');
        }
        await _service._observe<void>(
          'clear-confirmed-start',
          () => _swaps.delete(key),
        );
        _require();
        await _service._observe<void>('flush-start-rearm', _swaps.flush);
        return true;
      } finally {
        turn.release();
      }
    });
  }
}

/// A pre-RPC reservation prevents cleanup from passing a deferred publication.
class HtlcStoreWriteRequest {
  HtlcStoreWriteRequest._(this._store, this._originals, this._reservation);
  final HtlcStoreCapture _store;
  final Map<dynamic, dynamic> _originals;
  final HtlcOperationReceipt _reservation;
  Future<void>? _write;

  /// Original encrypted Box identity reserved before the action's first RPC.
  Object get identity => _store.identity;

  /// Whether the exact captured backends remain owned for this write.
  bool get ownsStore => _store.ownsStore;

  /// Reserved lifecycle, including known refusal or retained failure.
  HtlcOperationReceipt get receipt => _reservation;

  /// Terminal settlement without replacing the original write failure.
  Future<void> get settled => _reservation.settled;

  /// Persists once against the originally captured record or absence.
  Future<void> storeSwap(HtlcSwap swap) {
    final Future<void>? existing = _write;
    if (existing != null) return existing;
    final String id = swap.id;
    final int chain = swap.chainId;
    final String encoded = jsonEncode(swap.toJson());
    final Future<void> operation = _reservation.run<void>(() {
      if (chain != _store.chainId) {
        throw const HtlcOwnershipRefused('write-chain-mismatch');
      }
      return _store._persist(
        id,
        encoded,
        expected: _originals[id] as String?,
        expectAbsent: !_originals.containsKey(id),
      );
    });
    _write = operation;
    return operation;
  }

  /// Settles known refusal before any backend invocation.
  void refuse() => _reservation.refuse();

  /// Settles uncertainty negatively without erasing the original action hold.
  void retainUnknown(Object error, StackTrace stackTrace) =>
      _reservation.retainUnknown(error, stackTrace);
}

/// A durable write-ahead hold contains identifiers and the accepted hash only.
class HtlcUnlockWriteRequest {
  HtlcUnlockWriteRequest._(
    this._store,
    this._id,
    this._owner,
    this._reservation,
  );
  final HtlcStoreCapture _store;
  final String _id;
  final String _owner;
  final HtlcOperationReceipt _reservation;
  bool _claimed = false;
  bool _claimAttempted = false;
  bool _claimSettled = false;
  bool _claimFailed = false;
  Map<String, dynamic>? _marker;
  Future<bool>? _claim;
  Future<void>? _completion;

  /// Original reserved unlock lifecycle, which cleanup must wait to settle.
  HtlcOperationReceipt get receipt => _reservation;

  /// Writes and flushes one hold only when neither manual nor automatic
  /// withdrawal already owns this exact deposit and signer.
  Future<bool> claim() {
    if (_claimAttempted || _reservation.completed) {
      throw const HtlcOwnershipRefused('unlock-claim-reused');
    }
    _claimAttempted = true;
    final HtlcSerialTurn turn = _store._service._lane(_store._swaps).reserve();
    final Future<bool> operation = () async {
      try {
        await turn.ready;
        _store._require();
        if (_store._hasWithdrawalHold(_id, _owner)) return false;
        final Map<String, dynamic> marker = <String, dynamic>{
          'chain': _store.chainId,
          'deposit': _id,
          'owner': _owner,
          'claim':
              '${identityHashCode(this)}:${HtlcStoreCapture._nextAction++}',
          'status': 'publishing',
        };
        _marker = Map<String, dynamic>.from(marker);
        await _store._service._observe<void>(
          'claim-unlock',
          () => _store._putMarker(_store._unlockKey(_id, _owner), marker),
        );
        _store._require();
        await _store._service._observe<void>(
          'flush-unlock-claim',
          _store._swaps.flush,
        );
        _store._require();
        if (!_store._matchesMarker(_store._unlockKey(_id, _owner), _marker)) {
          throw const HtlcOwnershipRefused('unlock-claim-replaced');
        }
        _claimed = true;
        return true;
      } on Object {
        _claimFailed = true;
        rethrow;
      } finally {
        _claimSettled = true;
        turn.release();
      }
    }();
    _claim = operation;
    return operation;
  }

  /// Retains the exact sender-accepted hash in the owned durable claim.
  Future<void> accept(String hash) {
    if (_completion != null) return _completion!;
    final Future<void> operation = _reservation.run<void>(() async {
      if (!_claimed ||
          Hash.parse(hash) == emptyHash ||
          Hash.parse(hash).toString() != hash) {
        throw const HtlcOwnershipRefused('accepted-unlock-hash-unproven');
      }
      final HtlcSerialTurn turn = _store._service
          ._lane(_store._swaps)
          .reserve();
      try {
        await turn.ready;
        _store._require();
        if (!_store.hasUnlockHold(_id, _owner) ||
            !_store._matchesMarker(_store._unlockKey(_id, _owner), _marker)) {
          throw const HtlcOwnershipRefused('unlock-claim-missing');
        }
        final Map<String, dynamic> marker = <String, dynamic>{
          ..._marker!,
          'status': 'accepted',
          'hash': hash,
        };
        await _store._service._observe<void>(
          'accept-unlock',
          () => _store._putMarker(_store._unlockKey(_id, _owner), marker),
        );
        _store._require();
        await _store._service._observe<void>(
          'flush-accepted-unlock',
          _store._swaps.flush,
        );
      } finally {
        turn.release();
      }
    });
    _completion = operation;
    return operation;
  }

  /// Settles only when no claim was written or left uncertain.
  void refuse() {
    if (_claimed || _claimFailed || (_claimAttempted && !_claimSettled)) {
      throw const HtlcOwnershipRefused('durable-unlock-hold-retained');
    }
    _reservation.refuse();
  }

  /// Waits for an admitted claim before retaining its unchanged uncertainty.
  void retainUnknown(Object error, StackTrace stackTrace) {
    if (_reservation.original != null || _reservation.completed) return;
    final Future<bool>? claiming = _claim;
    final Future<void> operation = _reservation.run<void>(() async {
      if (claiming != null) {
        try {
          await claiming;
        } on Object {
          /* The original claim receipt retains its error. */
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    _completion = operation;
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
}

/// Recovery payloads stay in the original encrypted backend's private lane.
class HtlcActionWriteRequest {
  HtlcActionWriteRequest._(
    this._store,
    this._kind,
    this._target,
    this._owner,
    this._claimId,
    this._reservation,
  );
  final HtlcStoreCapture _store;
  final String _kind;
  final String _target;
  final String _owner;
  final String _claimId;
  final HtlcOperationReceipt _reservation;
  Map<String, dynamic>? _marker;
  Future<void>? _preparation;
  Future<void>? _completion;
  Object? _prepareError;
  late StackTrace _prepareStack;
  bool _prepared = false;
  bool _accepted = false;
  bool _unknown = false;
  bool _writeInvoked = false;

  /// Exact original encrypted backend that owns this durable action.
  Object get identity => _store.identity;

  /// Whether the original captured backends remain owned.
  bool get ownsStore => _store.ownsStore;

  /// Reserved terminal action receipt, distinct from preparation's Future.
  HtlcOperationReceipt get receipt => _reservation;
  String get _key => _store._actionKey(_kind, _target, _owner);

  /// Serializes and flushes the original publishing hold and private recovery
  /// data before signer invocation, retaining the identical preparation Future.
  Future<void> prepare({Map<String, dynamic>? recovery}) {
    if (_preparation != null) return _preparation!;
    if (_reservation.completed || _reservation.original != null) {
      throw const HtlcOwnershipRefused('action-request-reused');
    }
    final Map<String, dynamic> frozen = recovery == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(jsonEncode(recovery)) as Map<String, dynamic>,
          );
    if (_kind == 'start' && frozen.isEmpty) {
      throw const HtlcOwnershipRefused('start-recovery-required');
    }
    final Map<String, dynamic> marker = <String, dynamic>{
      'chain': _store.chainId,
      'kind': _kind,
      'target': _target,
      'owner': _owner,
      'claim': _claimId,
      'status': 'publishing',
      if (frozen.isNotEmpty) 'recovery': frozen,
    };
    final Map<String, dynamic> expected = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(marker)) as Map<String, dynamic>,
    );
    final HtlcSerialTurn turn = _store._service._lane(_store._swaps).reserve();
    final Future<void> operation = () async {
      try {
        await turn.ready;
        _store._require();
        if (_store._swaps.containsKey(_key)) {
          throw const HtlcOwnershipRefused('durable-action-held');
        }
        if (<String>['complete', 'recover', 'reclaim'].contains(_kind) &&
            _store._hasWithdrawalHold(_target, _owner)) {
          throw const HtlcOwnershipRefused('withdrawal-outcome-held');
        }
        _writeInvoked = true;
        await _store._service._observe<void>(
          'prepare-action',
          () => _store._putMarker(_key, marker),
        );
        _store._require();
        await _store._service._observe<void>(
          'flush-prepared-action',
          _store._swaps.flush,
        );
        _store._require();
        if (!_store._matchesMarker(_key, expected)) {
          throw const HtlcOwnershipRefused('prepared-action-marker-replaced');
        }
        _marker = expected;
        _prepared = true;
      } on Object catch (error, trace) {
        if (_writeInvoked) {
          _prepareError = error;
          _prepareStack = trace;
        }
        rethrow;
      } finally {
        turn.release();
      }
    }();
    _preparation = operation;
    return operation;
  }

  /// Records the exact accepted hash against the original prepared marker.
  Future<void> accepted(String exactHash) {
    if (_completion != null) return _completion!;
    final Future<void> operation = _reservation.run<void>(() async {
      final Future<void>? preparing = _preparation;
      if (preparing == null) {
        throw const HtlcOwnershipRefused('action-not-prepared');
      }
      await preparing;
      if (!_prepared ||
          _unknown ||
          Hash.parse(exactHash) == emptyHash ||
          Hash.parse(exactHash).toString() != exactHash) {
        throw const HtlcOwnershipRefused('accepted-action-unproven');
      }
      _accepted = true;
      final HtlcSerialTurn turn = _store._service
          ._lane(_store._swaps)
          .reserve();
      try {
        await turn.ready;
        _store._require();
        if (!_store._matchesMarker(_key, _marker)) {
          throw const HtlcOwnershipRefused('accepted-action-marker-replaced');
        }
        final Map<String, dynamic> marker = <String, dynamic>{
          ..._marker!,
          'status': 'accepted',
          'hash': exactHash,
        };
        await _store._service._observe<void>(
          'accept-action',
          () => _store._putMarker(_key, marker),
        );
        _store._require();
        await _store._service._observe<void>(
          'flush-accepted-action',
          _store._swaps.flush,
        );
        _marker = marker;
      } finally {
        turn.release();
      }
    });
    _completion = operation;
    return operation;
  }

  /// Settles known pre-write refusal or clears only its own unstarted marker.
  /// A possibly failed write stays a negative terminal result, never rollback.
  Future<void> refuseBeforePublication() {
    if (_completion != null) {
      return Future<void>.error(
        const HtlcOwnershipRefused('action-completion-retained'),
      );
    }
    final Future<void> operation = _reservation.run<void>(() async {
      if (_accepted || _unknown) {
        throw const HtlcOwnershipRefused('action-outcome-held');
      }
      final Future<void>? preparation = _preparation;
      if (preparation != null) {
        try {
          await preparation;
        } on Object {
          if (_prepareError != null) {
            Error.throwWithStackTrace(_prepareError!, _prepareStack);
          }
        }
      }
      if (!_prepared) return;
      final HtlcSerialTurn turn = _store._service
          ._lane(_store._swaps)
          .reserve();
      try {
        await turn.ready;
        _store._require();
        if (!_store._matchesMarker(_key, _marker)) {
          throw const HtlcOwnershipRefused('refused-action-marker-replaced');
        }
        await _store._service._observe<void>(
          'clear-unpublished-action',
          () => _store._swaps.delete(_key),
        );
        _store._require();
        await _store._service._observe<void>(
          'flush-unpublished-action',
          _store._swaps.flush,
        );
      } finally {
        turn.release();
      }
    });
    _completion = operation;
    return operation;
  }

  /// Waits for original preparation, retains possible effects and settles the
  /// reserved action negatively with the original error and stack trace.
  void retainUnknown(Object error, StackTrace trace) {
    _unknown = true;
    if (_reservation.original != null || _reservation.completed) return;
    final Future<void>? preparation = _preparation;
    final Future<void> operation = _reservation.run<void>(() async {
      if (preparation != null) {
        try {
          await preparation;
        } on Object {
          /* Preserve the separately retained backend error. */
        }
      }
      Error.throwWithStackTrace(error, trace);
    });
    _completion = operation;
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
}
