import 'dart:async';

class _ReceiveListener {
  _ReceiveListener(this._subscription);

  final StreamSubscription<Map<String, dynamic>?> _subscription;

  Future<void> cancel() => _subscription.cancel();
}

class _ReceiveCancellation {
  final Completer<void> _settled = Completer<void>();
  late final Future<void> _original;
  Object? _error;
  late StackTrace _trace;

  void cancel(_ReceiveListener listener) {
    try {
      _original = listener.cancel();
      unawaited(
        _original.then<void>(
          (_) => _settled.complete(),
          onError: (Object error, StackTrace trace) {
            _error = error;
            _trace = trace;
            _settled.complete();
          },
        ),
      );
    } on Object catch (error, trace) {
      _error = error;
      _trace = trace;
      _settled.complete();
    }
  }

  Future<void> result() async {
    await _settled.future;
    if (_error != null) Error.throwWithStackTrace(_error!, _trace);
  }
}

/// Subscription admission belongs to a connection, not an unlocked page.
/// Failed or uncertain admission is retained until a new broadcaster arrives.
class ReceiveFeedConnection {
  /// Freezes one original broadcaster and its subscription transport.
  ReceiveFeedConnection({
    required this.messages,
    required this.isCurrent,
    required this.subscribeMomentums,
    required this.subscribeAccountBlocks,
  });

  /// Messages from the exact connection that created these subscriptions.
  final Stream<Map<String, dynamic>?> messages;

  /// Refuses an old socket URL or replaced API transport.
  final bool Function() isCurrent;

  /// Subscription calls use independently bound original APIs.
  final Future<String?> Function() subscribeMomentums;

  /// Retains the account-block subscription from that same original connection.
  final Future<String?> Function() subscribeAccountBlocks;
  Future<String?>? _momentums;
  Future<String?>? _blocks;
  String? _momentumId;
  String? _blocksId;
  int _height = 0;

  Future<void> _admit() async {
    if (!isCurrent()) return;
    // Both futures are reserved synchronously before the first transport await.
    _momentums ??= Future<String?>.sync(subscribeMomentums);
    _blocks ??= Future<String?>.sync(subscribeAccountBlocks);
    // Attach both error handlers immediately, including a synchronous refusal.
    final List<String?> ids = await Future.wait<String?>(<Future<String?>>[
      _momentums!.onError<Object>((Object _, StackTrace _) => null),
      _blocks!.onError<Object>((Object _, StackTrace _) => null),
    ]);
    if (!isCurrent()) return;
    _momentumId = ids[0];
    _blocksId = ids[1];
  }
}

/// Owns one visible receive feed while retaining connection-level admission.
/// [T] is an immutable origin, captured before each asynchronous operation.
class ReceiveFeed<T extends Object> {
  /// Supplies transport-free lifecycle and message validation for the wallet.
  ReceiveFeed({
    required this.prepare,
    required this.isOriginCurrent,
    required this.ownsAddress,
    required this.scan,
    required this.enqueue,
    required this.drain,
    required this.hasPending,
    required this.notifySyncing,
    this.noticeDelay = const Duration(seconds: 30),
  });

  /// Captures its read authority synchronously before its first await.
  final Future<T?> Function(bool Function() isCurrent) prepare;

  /// Includes the original wallet, transport and selection generation.
  final bool Function(T) isOriginCurrent;

  /// Membership comes from the original immutable account snapshot.
  final bool Function(T, String) ownsAddress;

  /// Discovers unreceived blocks using that same origin.
  final Future<void> Function(T) scan;

  /// Enqueues one exact inbound hash and captured destination.
  final Future<void> Function(T, String, String) enqueue;

  /// Starts the original worker only while its origin remains current.
  final Future<void> Function(T) drain;

  /// Queued automatic work, separate from retained admitted outcomes.
  final bool Function() hasPending;

  /// The delayed notice also retains its original stats and display owner.
  final Future<void> Function(T) notifySyncing;

  /// The existing initial synchronization notice delay.
  final Duration noticeDelay;
  ReceiveFeedConnection? _connection;
  _ReceiveListener? _listener;
  final List<_ReceiveCancellation> _cancellations = <_ReceiveCancellation>[];
  Future<void>? _closing;
  Timer? _notice;
  int _generation = 0;
  bool _closed = false;

  /// Replacing a connection immediately revokes every old callback.
  void connect(ReceiveFeedConnection connection) {
    if (_closed) return;
    if (!identical(connection, _connection)) {
      _revoke();
      _connection = connection;
    }
    rearm();
  }

  /// Lock, selection or transition changes revoke before any deferred work.
  void revoke() => _revoke();

  void _revoke() {
    _generation++;
    final _ReceiveListener? original = _listener;
    _listener = null;
    _notice?.cancel();
    _notice = null;
    if (original != null) _cancel(original);
  }

  void _cancel(_ReceiveListener original) {
    // Reserve before cancellation can synchronously reenter close.
    final _ReceiveCancellation cancellation = _ReceiveCancellation();
    _cancellations.add(cancellation);
    cancellation.cancel(original);
  }

  /// Reuses original subscription receipts after an explicit unlocked rearm.
  void rearm() {
    if (_closed) return;
    _revoke();
    final ReceiveFeedConnection? connection = _connection;
    if (connection == null || !connection.isCurrent()) return;
    final int generation = _generation;
    bool sourceCurrent() =>
        !_closed &&
        generation == _generation &&
        identical(connection, _connection) &&
        connection.isCurrent();
    unawaited(
      _start(connection, sourceCurrent).onError<Object>(
        (Object _, StackTrace _) {},
      ),
    );
  }

  Future<void> _start(
    ReceiveFeedConnection connection,
    bool Function() sourceCurrent,
  ) async {
    final T? origin = await prepare(sourceCurrent);
    if (origin == null) return;
    bool current() => sourceCurrent() && isOriginCurrent(origin);
    if (!current()) return;
    await connection._admit();
    if (!current()) return;
    final _ReceiveListener listener = _ReceiveListener(
      connection.messages.listen((Map<String, dynamic>? event) {
        if (current()) _onMessage(connection, origin, event, current);
      }, onError: (Object _, StackTrace _) {}),
    );
    if (!current()) {
      _cancel(listener);
      return;
    }
    _listener = listener;
    _notice = Timer(noticeDelay, () {
      if (current()) {
        unawaited(
          notifySyncing(origin).onError<Object>(
            (Object _, StackTrace _) {},
          ),
        );
      }
    });
    await scan(origin);
    if (current()) await drain(origin);
  }

  void _onMessage(
    ReceiveFeedConnection connection,
    T origin,
    Map<String, dynamic>? event,
    bool Function() current,
  ) {
    if (event?['method'] != 'ledger.subscription') return;
    final Object? params = event?['params'];
    if (params is! Map) return;
    final Object? id = params['subscription'];
    final Object? result = params['result'];
    if (id is! String || result is! List || result.isEmpty) return;
    if (id == connection._blocksId) {
      for (final Object? item in result) {
        if (!current()) return;
        if (item is! Map) continue;
        final Object? address = item['toAddress'];
        final Object? hash = item['hash'];
        if (address is! String ||
            hash is! String ||
            !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash) ||
            !ownsAddress(origin, address)) {
          continue;
        }
        unawaited(
          enqueue(origin, hash, address).onError<Object>(
            (Object _, StackTrace _) {},
          ),
        );
      }
    } else if (id == connection._momentumId) {
      for (final Object? item in result) {
        if (item is! Map || item.containsKey('blockType')) continue;
        final Object? height = item['height'];
        if (height is! int || height <= connection._height) continue;
        connection._height = height;
        if (current() && hasPending()) {
          unawaited(
            drain(origin).onError<Object>(
              (Object _, StackTrace _) {},
            ),
          );
        }
      }
    }
  }

  /// Cancels only this owner's listener and timer; SDK callbacks stay passive.
  Future<void> close() {
    final Future<void>? existing = _closing;
    if (existing != null) return existing;
    final Completer<void> completion = Completer<void>();
    _closing = completion.future;
    _closed = true;
    _revoke();
    _connection = null;
    completion.complete(
      Future.wait<void>(
        _cancellations.map(
          (_ReceiveCancellation cancellation) => cancellation.result(),
        ),
      ).then<void>((_) {}),
    );
    return completion.future;
  }
}
