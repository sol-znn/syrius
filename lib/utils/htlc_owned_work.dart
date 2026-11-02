import 'dart:async';

/// A fixed refusal carries no wallet material or backend diagnostics.
class HtlcOwnershipRefused implements Exception {
  /// Records a fixed ownership fact without embedding backend diagnostics.
  const HtlcOwnershipRefused(this.reason);

  /// Stable reason code for source inspection and localized error mapping.
  final String reason;
}

/// One admitted original Future and its unchanged terminal completion.
class HtlcOperationReceipt {
  /// Reserves an observable operation before its original backend is invoked.
  HtlcOperationReceipt(this.name);

  /// Fixed operation label, containing no wallet material.
  final String name;

  /// Actual original backend Future, absent for known pre-invocation refusal.
  Future<dynamic>? original;

  /// Original successful value, if the admitted Future completed positively.
  Object? result;

  /// Unchanged failure or explicitly retained uncertainty.
  Object? error;

  /// Original trace associated with [error].
  StackTrace? stackTrace;

  /// Whether the reservation reached a positive or negative terminal outcome.
  bool completed = false;
  final Completer<void> _settled = Completer<void>();

  /// Completes on terminal settlement without concealing [error].
  Future<void> get settled => _settled.future;

  /// Invokes once, retains the actual backend Future and forwards its unchanged
  /// result or failure while settling this reservation in all terminal paths.
  Future<T> run<T>(Future<T> Function() call) async {
    if (original != null || completed) {
      throw const HtlcOwnershipRefused('operation-reused');
    }
    try {
      final Future<T> operation = call();
      original = operation;
      final T value = await operation;
      result = value;
      return value;
    } on Object catch (value, trace) {
      error = value;
      stackTrace = trace;
      rethrow;
    } finally {
      completed = true;
      _settled.complete();
    }
  }

  /// A known refusal before any backend invocation is still a positive finish.
  void refuse() {
    if (original != null || completed) {
      throw const HtlcOwnershipRefused('operation-reused');
    }
    completed = true;
    _settled.complete();
  }

  /// An uncertain publication never becomes a positive drain through absence.
  void retainUnknown(Object value, StackTrace trace) {
    if (original != null || completed) {
      throw const HtlcOwnershipRefused('operation-reused');
    }
    error = value;
    stackTrace = trace;
    completed = true;
    _settled.complete();
  }
}

/// A positive terminal receipt belongs to the exact paused owner.
class HtlcDrainReceipt {
  /// Freezes the original owner's terminal operations and first failure.
  HtlcDrainReceipt({
    required this.owner,
    required this.completed,
    required Iterable<HtlcOperationReceipt> operations,
    this.error,
    this.stackTrace,
  }) : operations = List<HtlcOperationReceipt>.unmodifiable(operations);

  /// Exact paused owner; another owner's receipt cannot authorize cleanup.
  final Object owner;

  /// Positive only when every original operation and ownership check succeeded.
  final bool completed;

  /// Complete immutable set of reservations included in this drain.
  final List<HtlcOperationReceipt> operations;

  /// First original operation or resource-ownership failure.
  final Object? error;

  /// Original trace associated with [error].
  final StackTrace? stackTrace;
}

/// Admission closes synchronously. Pending originals have no synthetic timeout.
class HtlcOwnedWork {
  /// Tracks one owner and its optional final exact-resource ownership check.
  HtlcOwnedWork(this.owner, {bool Function()? ownsResources})
    : _ownsResources = ownsResources ?? (() => true);

  /// Identity to which every terminal drain belongs.
  final Object owner;
  final bool Function() _ownsResources;
  bool _paused = false;
  final List<HtlcOperationReceipt> _operations = <HtlcOperationReceipt>[];
  Future<HtlcDrainReceipt>? _drain;

  /// Whether new work may still reserve admission.
  bool get accepting => !_paused;

  /// Immutable snapshot including uninvoked and unsettled reservations.
  List<HtlcOperationReceipt> get operations =>
      List<HtlcOperationReceipt>.unmodifiable(_operations);

  /// Reserves before RPC or writes; callers must run, refuse or retain unknown.
  HtlcOperationReceipt reserve(String name) {
    if (_paused) throw const HtlcOwnershipRefused('owner-paused');
    final HtlcOperationReceipt operation = HtlcOperationReceipt(name);
    _operations.add(operation);
    return operation;
  }

  /// Reserves and immediately invokes one original operation.
  Future<T> admit<T>(String name, Future<T> Function() call) =>
      reserve(name).run<T>(call);

  /// Closes admission synchronously, then awaits every reserved original.
  /// Unsettled work has no timeout, and negative outcomes stay negative.
  Future<HtlcDrainReceipt> pauseAndDrain() {
    final Future<HtlcDrainReceipt>? existing = _drain;
    if (existing != null) return existing;
    _paused = true;
    final Completer<HtlcDrainReceipt> completion =
        Completer<HtlcDrainReceipt>();
    _drain = completion.future;
    final List<HtlcOperationReceipt> originals = List<HtlcOperationReceipt>.of(
      _operations,
    );
    unawaited(() async {
      for (final HtlcOperationReceipt original in originals) {
        await original.settled;
      }
      Object? error;
      StackTrace? trace;
      for (final HtlcOperationReceipt original in originals) {
        if (original.error != null) {
          error ??= original.error;
          trace ??= original.stackTrace;
        }
      }
      try {
        if (!_ownsResources()) {
          throw const HtlcOwnershipRefused('original-owner-changed');
        }
      } on Object catch (value, stack) {
        error ??= value;
        trace ??= stack;
      }
      completion.complete(
        HtlcDrainReceipt(
          owner: owner,
          completed:
              error == null &&
              originals.every((HtlcOperationReceipt value) => value.completed),
          operations: originals,
          error: error,
          stackTrace: trace,
        ),
      );
    }());
    return completion.future;
  }
}

/// Each turn reserves its predecessor before invoking an original backend.
class HtlcSerialLane {
  Future<void> _tail = Future<void>.value();

  /// Reserves a turn synchronously behind the exact prior turn's release.
  HtlcSerialTurn reserve() {
    final HtlcSerialTurn turn = HtlcSerialTurn(_tail);
    _tail = turn._released.future;
    return turn;
  }

  /// Original current tail, including turns not yet ready to invoke a backend.
  Future<void> get pending => _tail;
}

/// A single original lane turn whose release never discovers another owner.
class HtlcSerialTurn {
  /// Waits on the predecessor captured by its owning lane.
  HtlcSerialTurn(this.ready);

  /// Completes when that exact predecessor releases its turn.
  final Future<void> ready;
  final Completer<void> _released = Completer<void>();

  /// Idempotently releases only this turn, normally from its owner's finally.
  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}
