import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:logging/logging.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/base_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/receive_origin.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/bloc/latest_transactions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pending_transactions/bloc/pending_transactions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

export 'receive_origin.dart';

part 'receive_drain.dart';

/// One admitted receive, retained for the lifetime of its worker.
class ReceiveRecord {
  ReceiveRecord._({
    required this.chainId,
    required this.inboundHash,
    required this.toAddress,
    required this.future,
  });

  /// Durable metadata contains no wallet file or live origin capability.
  final int chainId;

  /// Exact original inbound hash, never a replacement-history match.
  final String inboundHash;

  /// The captured wallet member authorized to receive this inbound.
  final String toAddress;

  /// The original caller result remains shared across later attachments.
  final Future<AccountBlockTemplate?> future;

  /// Distinguishes this admission from another request for the same inbound.
  final Object requestId = Object();
  SendRequestHandle? _handle;
  SendRequestResult? _result;
  Object? _error;

  /// The sender's original publication handle, if admission reached it.
  SendRequestHandle? get handle => _handle;

  /// Its immutable terminal result remains available after the view leaves.
  SendRequestResult? get result => _result;

  /// Original refusal or SDK failure, with no retry implied by settlement.
  Object? get error => _result?.error ?? _error;
}

typedef _ReceiveKey = (int, String, String);

class _ReceiveAuthority {
  _ReceiveAuthority(this.lease, this.current, this.observers);
  final Object lease;
  final bool Function() current;
  final _ReceiveObservers observers;
  bool revoked = false;

  bool get isCurrent {
    if (revoked) return false;
    try {
      return !(revoked = !current());
    } on Object {
      revoked = true;
      return false;
    }
  }
}

class _ReceiveObservers {
  _ReceiveObservers()
    : balances = app.sl.isRegistered<MultipleBalanceBloc>()
          ? app.sl<MultipleBalanceBloc>()
          : null,
      latest = app.sl.isRegistered<LatestTransactionsBloc>()
          ? app.sl<LatestTransactionsBloc>()
          : null,
      pending = app.sl.isRegistered<PendingTransactionsBloc>()
          ? app.sl<PendingTransactionsBloc>()
          : null;

  final MultipleBalanceBloc? balances;
  final LatestTransactionsBloc? latest;
  final PendingTransactionsBloc? pending;

  bool get isCurrent =>
      (balances == null ||
          (app.sl.isRegistered<MultipleBalanceBloc>() &&
              identical(balances, app.sl<MultipleBalanceBloc>()))) &&
      (latest == null ||
          (app.sl.isRegistered<LatestTransactionsBloc>() &&
              identical(latest, app.sl<LatestTransactionsBloc>()))) &&
      (pending == null ||
          (app.sl.isRegistered<PendingTransactionsBloc>() &&
              identical(pending, app.sl<PendingTransactionsBloc>())));
}

class _ReceiveRequest {
  _ReceiveRequest({
    required this.hash,
    required this.origin,
    required this.automatic,
    required this.epoch,
    this.toAddress,
    this.automaticCurrent,
  }) {
    // Automatic work has no external caller to observe its projection.
    if (automatic) {
      unawaited(
        future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  final String hash;
  final ReceiveOrigin origin;
  final bool automatic;
  final int epoch;
  final String? toAddress;
  final bool Function()? automaticCurrent;
  final Completer<AccountBlockTemplate?> completion =
      Completer<AccountBlockTemplate?>();
  final Object reservation = Object();
  late final Future<AccountBlockTemplate?> future = completion.future;
  ReceiveRecord? record;
  bool revoked = false;

  _ReceiveKey? get key =>
      toAddress == null ? null : (origin.chainId, toAddress!, hash);
}

/// Serial receive admission through the shell's existing transaction sender.
class AutoReceiveTxWorker extends BaseBloc<WalletNotification> {
  /// Injects finite ports; the default defers resource capture until admission.
  AutoReceiveTxWorker({
    this._originSource,
    this._automaticEnabled,
    this._otherWorkerBusy,
    this._onSuccess,
    this._onQueued,
    this._onFailure,
  });

  /// The process-owned production worker; injected owners remain independent.
  factory AutoReceiveTxWorker.shared() => _instance ??= AutoReceiveTxWorker();

  static AutoReceiveTxWorker? _instance;

  final ReceiveOrigin? Function(SendTransactionBloc, bool Function())?
  _originSource;
  final bool Function()? _automaticEnabled;
  final bool Function()? _otherWorkerBusy;
  final void Function(ReceiveOrigin, AccountBlockTemplate, String)? _onSuccess;
  final void Function(ReceiveOrigin)? _onQueued;
  final void Function(Object)? _onFailure;
  final Expando<_ReceiveAuthority> _origins = Expando<_ReceiveAuthority>(
    'Original receive authority',
  );
  final Queue<_ReceiveRequest> _queue = Queue<_ReceiveRequest>();
  final Map<_ReceiveKey, Object> _pendingAdds = <_ReceiveKey, Object>{};
  final Map<_ReceiveKey, _ReceiveRequest> _automatic =
      <_ReceiveKey, _ReceiveRequest>{};
  final Map<_ReceiveKey, ReceiveRecord> _journal =
      <_ReceiveKey, ReceiveRecord>{};
  final List<ReceiveRecord> _originals = <ReceiveRecord>[];
  final Set<_ReceiveRequest> _marked = <_ReceiveRequest>{};
  SendTransactionBloc? _sender;
  Object? _senderLease;
  Future<void>? _drain;
  _ReceiveRequest? _active;
  int _automaticEpoch = 0;
  bool _closed = false;
  bool _paused = false;
  final List<ReceiveReadReceipt<dynamic>> _readOperations =
      <ReceiveReadReceipt<dynamic>>[];
  Future<ReceiveDrainReceipt>? _pausing;

  /// Admitted hashes stay held, including unknown original outcomes.
  final ValueNotifier<Set<Hash>> inFlight = ValueNotifier<Set<Hash>>(
    const <Hash>{},
  );

  /// True while the actual serial drain has not yet settled.
  bool get running => _drain != null;

  /// A terminal pause cannot be reused by a later wallet initialization.
  bool get isPaused => _paused;

  /// Includes deferred automatic reads and automatic queue entries.
  bool get hasPending => _pendingAdds.isNotEmpty || _automatic.isNotEmpty;

  /// The list never substitutes an original result after a later attachment.
  List<ReceiveRecord> get originals => List<ReceiveRecord>.unmodifiable(
    _originals,
  );

  /// Installs an opaque attachment without transferring old result records.
  Object attachSender(SendTransactionBloc sender) {
    if (_paused || _closed || sender.isClosed) throw const ReceiveRefused();
    clearAutomatic();
    final Object lease = Object();
    _sender = sender;
    _senderLease = lease;
    return lease;
  }

  /// Detaching an old shell cannot detach its replacement.
  void detachSender(Object lease) {
    if (!identical(_senderLease, lease)) return;
    _senderLease = null;
    _sender = null;
    clearAutomatic();
  }

  /// Checks the exact attachment without capturing any replacement resource.
  bool ownsSender(Object lease) =>
      !_closed &&
      identical(_senderLease, lease) &&
      _sender != null &&
      !_sender!.isClosed;

  /// Captures all authority synchronously, before callers read preferences.
  ReceiveOrigin? captureOrigin({bool Function()? sourceIsCurrent}) {
    if (_paused || _closed) return null;
    final SendTransactionBloc? sender = _sender;
    final Object? lease = _senderLease;
    if (sender == null || lease == null || !ownsSender(lease)) return null;
    final ReceiveOrigin? Function(SendTransactionBloc, bool Function())?
    source = _originSource;
    try {
      final _ReceiveAuthority authority = _ReceiveAuthority(
        lease,
        () =>
            ownsSender(lease) &&
            (source != null ||
                (app.sl.isRegistered<AutoReceiveTxWorker>() &&
                    identical(app.sl<AutoReceiveTxWorker>(), this))) &&
            (sourceIsCurrent?.call() ?? true),
        _ReceiveObservers(),
      );
      if (!authority.isCurrent) return null;
      final ReceiveOrigin? origin;
      if (source != null) {
        origin = source(sender, () => authority.isCurrent);
      } else {
        final String? selected = kSelectedAddress;
        final int? nodeChain = kNodeChainId;
        final int chain = getChainIdentifier();
        if (selected == null ||
            nodeChain == null ||
            nodeChain <= 0 ||
            nodeChain != chain ||
            kDefaultAddressList.any((String? value) => value == null)) {
          return null;
        }
        final WalletActionContext? action = WalletActionContext.capture(
          selected,
        );
        if (action == null) return null;
        origin = ReceiveOrigin.wallet(
          action: action,
          sender: sender,
          chainId: chain,
          nodeChainId: nodeChain,
          addresses: kDefaultAddressList.cast<String>(),
          isCurrent: () => authority.isCurrent,
        );
      }
      if (_paused ||
          _closed ||
          origin == null ||
          !identical(origin.sender, sender) ||
          !authority.isCurrent ||
          !origin.isCurrent) {
        return null;
      }
      if (_paused ||
          _closed ||
          !ownsSender(lease) ||
          !identical(_sender, sender)) {
        return null;
      }
      _origins[origin] = authority;
      return origin;
    } on Object {
      return null;
    }
  }

  bool _ownsOrigin(ReceiveOrigin origin) {
    final _ReceiveAuthority? authority = _origins[origin];
    return authority != null &&
        ownsSender(authority.lease) &&
        authority.isCurrent &&
        identical(origin.sender, _sender) &&
        origin.isCurrent;
  }

  bool Function() _captureAutomaticAuthority() {
    final bool Function()? source = _automaticEnabled;
    if (source != null) return () => !_closed && source();
    final Object? preferences = app.sharedPrefsService;
    if (preferences == null || !Hive.isBoxOpen(kSharedPrefsBox)) {
      return () => false;
    }
    final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
    return () =>
        !_closed &&
        identical(preferences, app.sharedPrefsService) &&
        box.isOpen &&
        Hive.isBoxOpen(kSharedPrefsBox) &&
        identical(box, Hive.box<dynamic>(kSharedPrefsBox)) &&
        box.get(
              kAutoReceiveKey,
              defaultValue: kAutoReceiveDefaultValue,
            ) ==
            true;
  }

  /// A deferred sync reply cannot refill a cleared or replaced queue.
  Future<void> addHash(
    Hash hash, {
    required ReceiveOrigin origin,
    required String toAddress,
  }) async {
    if (_paused || _closed) return;
    final int epoch = _automaticEpoch;
    final String inbound = hash.toString();
    final _ReceiveKey key = (origin.chainId, toAddress, inbound);
    final bool Function() enabled = _captureAutomaticAuthority();
    bool current() {
      if (_paused || _closed || epoch != _automaticEpoch) return false;
      final bool owns = _ownsOrigin(origin);
      if (!owns || _paused || _closed || epoch != _automaticEpoch) return false;
      final bool automatic = enabled();
      // Source and preference callbacks may synchronously close admission.
      return automatic && !_paused && !_closed && epoch == _automaticEpoch;
    }

    if (!current() ||
        inbound == emptyHash.toString() ||
        !origin.addresses.contains(toAddress) ||
        _journal.containsKey(key) ||
        _automatic.containsKey(key) ||
        _pendingAdds.containsKey(key)) {
      return;
    }
    final Object addition = Object();
    _pendingAdds[key] = addition;
    try {
      final ReceiveReadReceipt<SyncInfo> receipt =
          ReceiveReadReceipt<SyncInfo>._('sync');
      _readOperations.add(receipt);
      final SyncInfo sync = await receipt._read(origin.readSync);
      if (!current() ||
          !identical(_pendingAdds[key], addition) ||
          _journal.containsKey(key) ||
          !_synced(sync)) {
        return;
      }
      final _ReceiveRequest request = _ReceiveRequest(
        hash: inbound,
        origin: origin,
        automatic: true,
        epoch: epoch,
        toAddress: toAddress,
        automaticCurrent: enabled,
      );
      _automatic[key] = request;
      _queue.add(request);
      _effect(() {
        if (current()) (_onQueued ?? _refreshPending)(origin);
      });
    } on Object catch (error, trace) {
      _report(error, trace);
    } finally {
      if (identical(_pendingAdds[key], addition)) _pendingAdds.remove(key);
    }
  }

  static bool _synced(SyncInfo sync) =>
      sync.state == SyncState.syncDone ||
      (sync.targetHeight > 0 &&
          sync.currentHeight > 0 &&
          sync.targetHeight >= sync.currentHeight &&
          sync.targetHeight - sync.currentHeight < 3);

  /// Manual work ignores the automatic preference and captures only once.
  /// Returning the stored Future preserves the original projection's identity.
  Future<AccountBlockTemplate?> autoReceiveTransactionHash(
    Hash hash, {
    ReceiveOrigin? origin,
    bool Function()? sourceIsCurrent,
  }) {
    if (_paused || _closed) {
      return Future<AccountBlockTemplate?>.error(const ReceiveRefused());
    }
    final String inbound = hash.toString();
    final ReceiveOrigin? captured =
        origin ?? captureOrigin(sourceIsCurrent: sourceIsCurrent);
    if (_paused || _closed) {
      return Future<AccountBlockTemplate?>.error(const ReceiveRefused());
    }
    if (captured == null) {
      // Preserve the visible mark/fail/unmark contract without a node.
      _setHolds(<Hash>{...inFlight.value, Hash.parse(inbound)});
      _refreshHolds();
      return Future<AccountBlockTemplate?>.error(const ReceiveRefused());
    }
    final ReceiveRecord? original = _held(captured, inbound);
    if (original != null) return original.future;
    for (final _ReceiveRequest pending in <_ReceiveRequest>[
      ?_active,
      ..._queue,
    ]) {
      if (pending.hash == inbound &&
          !pending.automatic &&
          pending.origin.chainId == captured.chainId &&
          pending.origin.selectedAddress == captured.selectedAddress &&
          listEquals(pending.origin.addresses, captured.addresses)) {
        return pending.future;
      }
    }
    final _ReceiveRequest request = _ReceiveRequest(
      hash: inbound,
      origin: captured,
      automatic: false,
      epoch: _automaticEpoch,
      automaticCurrent: sourceIsCurrent,
    );
    _queue.addFirst(request);
    unawaited(_startDrain());
    return request.future;
  }

  ReceiveRecord? _held(ReceiveOrigin origin, String inbound) =>
      _journal[(origin.chainId, origin.selectedAddress, inbound)];

  bool _allowed(_ReceiveRequest request) {
    if (request.revoked) return false;
    try {
      return !(request.revoked =
          !_ownsOrigin(request.origin) ||
          (request.automatic && request.epoch != _automaticEpoch) ||
          !(request.automaticCurrent?.call() ?? !request.automatic));
    } on Object {
      request.revoked = true;
      return false;
    }
  }

  /// Clears only exact automatic entries, never admitted original records.
  void clearAutomatic() {
    _automaticEpoch++;
    _pendingAdds.clear();
    final List<_ReceiveRequest> queued = _queue
        .where((_ReceiveRequest request) => request.automatic)
        .toList();
    for (final _ReceiveRequest request in queued) {
      _queue.remove(request);
      _removeAutomatic(request);
      _refuse(request, const ReceiveRefused(), StackTrace.current);
    }
    _automatic.clear();
  }

  /// Drains queued automatic work through the already captured shared sender.
  Future<void> autoReceive() {
    if (_paused || _closed) return _drain ?? Future<void>.value();
    try {
      if (!_captureAutomaticAuthority()()) clearAutomatic();
    } on Object catch (error, trace) {
      clearAutomatic();
      _report(error, trace);
    }
    return _startDrain();
  }

  Future<void> _startDrain() {
    final Future<void>? existing = _drain;
    if (existing != null) return existing;
    if (_paused || _closed || _queue.isEmpty) return Future<void>.value();
    final Completer<void> completion = Completer<void>();
    final Future<void> drain = completion.future;
    _drain = drain;
    unawaited(() async {
      try {
        await _drainQueue();
      } on Object catch (error, trace) {
        _report(error, trace);
      } finally {
        if (identical(_drain, drain)) _drain = null;
        completion.complete();
        if (_queue.any((_ReceiveRequest request) => !request.automatic)) {
          unawaited(_startDrain());
        }
      }
    }());
    return drain;
  }

  Future<void> _drainQueue() async {
    while (!_paused && !_closed && _queue.isNotEmpty) {
      final _ReceiveRequest request = _queue.firstWhere(
        (_ReceiveRequest entry) => !entry.automatic,
        orElse: () => _queue.first,
      );
      if (request.automatic &&
          (_otherWorkerBusy?.call() ??
              (app.sl.isRegistered<AutoUnlockHtlcWorker>() &&
                  app.sl<AutoUnlockHtlcWorker>().running))) {
        return;
      }
      if (_paused || _closed || !_queue.contains(request)) return;
      _queue.remove(request);
      _active = request;
      final bool processed = await _receive(request);
      if (identical(_active, request)) _active = null;
      if (!processed) {
        if (_allowed(request)) {
          _queue.addFirst(request);
        } else {
          _removeAutomatic(request);
          _refuse(request, const ReceiveRefused(), StackTrace.current);
        }
        return;
      }
      _removeAutomatic(request);
    }
  }

  Future<bool> _receive(_ReceiveRequest request) async {
    final ReceiveOrigin origin = request.origin;
    final SendTransactionBloc sender = origin.sender;
    bool reserved = false;
    bool deferred = false;
    _marked.add(request);
    _refreshHolds();
    try {
      if (!_allowed(request) || request.hash == emptyHash.toString()) {
        throw const ReceiveRefused();
      }
      reserved = sender.tryReserve(request.reservation);
      if (!reserved) {
        if (request.automatic && _allowed(request)) {
          deferred = true;
          return false;
        }
        throw const ReceiveRefused();
      }
      if (!_allowed(request)) throw const ReceiveRefused();
      // This exact fresh proof is inside the shared sender's reservation.
      final ReceiveReadReceipt<AccountBlock?> receipt =
          ReceiveReadReceipt<AccountBlock?>._('inbound');
      _readOperations.add(receipt);
      final AccountBlock? inbound = await receipt._read(
        () => origin.readInbound(Hash.parse(request.hash)),
      );
      if (!_allowed(request) ||
          inbound == null ||
          inbound.hash.toString() != request.hash ||
          inbound.chainIdentifier != origin.chainId ||
          !BlockUtils.isSendBlock(inbound.blockType)) {
        throw const ReceiveRefused();
      }
      final String destination = inbound.toAddress.toString();
      if (!origin.addresses.contains(destination) ||
          (request.toAddress ?? origin.selectedAddress) != destination) {
        throw const ReceiveRefused();
      }
      final _ReceiveKey key = (origin.chainId, destination, request.hash);
      final ReceiveRecord? held = _journal[key];
      if (held != null) {
        sender.releaseReservation(request.reservation);
        reserved = false;
        _forward(held.future, request);
        return true;
      }
      final AccountBlockTemplate block = origin.receiveBlock(
        Hash.parse(request.hash),
      );
      final ReceiveRecord record = ReceiveRecord._(
        chainId: origin.chainId,
        inboundHash: request.hash,
        toAddress: destination,
        future: request.future,
      );
      request.record = record;
      // Install before sender callbacks can synchronously reenter this worker.
      _journal[key] = record;
      final SendRequestHandle? handle = sender.trySubmitOwned(
        owner: request.reservation,
        requestId: record.requestId,
        block: block,
        fromAddress: destination,
        reasonForGeneratingPlasma: PlasmaPurpose.receiveTransaction.message,
        origin: SendTransactionOrigin.contract,
        canStart: () => _allowed(request),
        canPublish: () => _allowed(request),
      );
      if (handle == null) {
        if (identical(_journal[key], record)) _journal.remove(key);
        request.record = null;
        throw const ReceiveRefused();
      }
      record._handle = handle;
      _originals.add(record);
      final SendRequestResult result = await handle.result;
      // Retain originals before consulting presentation or its observers.
      record._result = result;
      final Object? error = result.error;
      if (error != null) {
        record._error = error;
        request.completion.completeError(error);
        _failureEffect(request, error);
      } else if (_accepted(record, result.block)) {
        request.completion.complete(result.block);
        _effect(() {
          if (_allowed(request)) {
            (_onSuccess ?? _refreshReceived)(
              origin,
              result.block!,
              destination,
            );
          }
        });
      } else {
        final ReceiveUnknownResult unknown = ReceiveUnknownResult(result);
        record._error = unknown;
        request.completion.completeError(unknown);
        _failureEffect(request, unknown);
      }
      return true;
    } on Object catch (error, trace) {
      _refuse(request, error, trace);
      _failureEffect(request, error);
      return true;
    } finally {
      if (reserved) sender.releaseReservation(request.reservation);
      if (request.record?.handle == null) {
        final ReceiveRecord? record = request.record;
        if (record != null) {
          final _ReceiveKey key = (
            record.chainId,
            record.toAddress,
            record.inboundHash,
          );
          if (identical(_journal[key], record)) _journal.remove(key);
          request.record = null;
        }
      }
      _marked.remove(request);
      _refreshHolds();
      if (!deferred) _removeAutomatic(request);
    }
  }

  static bool _accepted(ReceiveRecord record, AccountBlockTemplate? block) =>
      block != null &&
      block.hash != emptyHash &&
      block.chainIdentifier == record.chainId &&
      block.address.toString() == record.toAddress &&
      block.blockType == BlockTypeEnum.userReceive.index &&
      block.fromBlockHash.toString() == record.inboundHash;

  void _forward(
    Future<AccountBlockTemplate?> original,
    _ReceiveRequest request,
  ) {
    unawaited(
      original.then<void>(
        request.completion.complete,
        onError: request.completion.completeError,
      ),
    );
  }

  void _refuse(_ReceiveRequest request, Object error, StackTrace trace) {
    if (!request.completion.isCompleted) {
      request.completion.completeError(error, trace);
    }
  }

  void _removeAutomatic(_ReceiveRequest request) {
    final _ReceiveKey? key = request.key;
    if (key != null && identical(_automatic[key], request)) {
      _automatic.remove(key);
    }
  }

  void _refreshHolds() => _setHolds(<Hash>{
    for (final _ReceiveRequest request in _marked) Hash.parse(request.hash),
    for (final ReceiveRecord record in _journal.values)
      if (record.handle != null) Hash.parse(record.inboundHash),
  });

  void _setHolds(Set<Hash> value) {
    if (_closed) return;
    _effect(() => inFlight.value = Set<Hash>.unmodifiable(value));
  }

  void _failureEffect(_ReceiveRequest request, Object error) => _effect(() {
    if (_allowed(request)) (_onFailure ?? _sendErrorNotification)(error);
  });

  void _effect(VoidCallback callback) {
    try {
      callback();
    } on Object catch (error, trace) {
      _report(error, trace);
    }
  }

  void _report(Object error, StackTrace trace) {
    try {
      Logger('AutoReceiveTxWorker').log(Level.WARNING, 'receive', error, trace);
    } on Object {
      // Diagnostic observers cannot replace an original publication outcome.
    }
  }

  void _refreshPending(ReceiveOrigin origin) {
    final _ReceiveObservers? observers = _origins[origin]?.observers;
    final PendingTransactionsBloc? pending = observers?.pending;
    if (_ownsOrigin(origin) &&
        observers != null &&
        observers.isCurrent &&
        pending != null) {
      pending.add(
        InfiniteListRefreshRequested(
          address: Address.parse(origin.selectedAddress),
        ),
      );
    }
  }

  void _refreshReceived(
    ReceiveOrigin origin,
    AccountBlockTemplate block,
    String toAddress,
  ) {
    final _ReceiveObservers? observers = _origins[origin]?.observers;
    if (!_ownsOrigin(origin) || observers == null || !observers.isCurrent) {
      return;
    }
    final MultipleBalanceBloc? balances = observers.balances;
    if (balances != null) {
      balances.add(
        MultipleBalanceFetch(addresses: origin.addresses),
      );
    }
    if (!_ownsOrigin(origin) || !observers.isCurrent) return;
    final Address selected = Address.parse(origin.selectedAddress);
    final LatestTransactionsBloc? latest = observers.latest;
    if (latest != null) {
      latest.add(
        InfiniteListRefreshRequested(address: selected),
      );
    }
    if (!_ownsOrigin(origin) || !observers.isCurrent) return;
    _refreshPending(origin);
    if (!_ownsOrigin(origin) || !observers.isCurrent) return;
    addEvent(
      WalletNotification(
        title: currentL10n.transactionReceivedNotificationTitle(
          ZenonAddressUtils.getLabel(toAddress),
        ),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: currentL10n.transactionReceivedNotificationDetails(
          '${block.hash}',
        ),
        type: NotificationType.paymentReceived,
      ),
    );
  }

  void _sendErrorNotification(Object error) {
    addEvent(
      WalletNotification(
        title: currentL10n.autoReceiveFailedNotificationTitle,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: currentL10n.receiveOperationFailed,
        type: NotificationType.error,
      ),
    );
  }

  @override
  void dispose() {
    if (_closed) return;
    clearAutomatic();
    _closed = true;
    _senderLease = null;
    _sender = null;
    for (final _ReceiveRequest request in _queue) {
      _refuse(request, const ReceiveRefused(), StackTrace.current);
    }
    _queue.clear();
    inFlight.dispose();
    super.dispose();
  }
}
