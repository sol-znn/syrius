import 'dart:async';

/// A successful pop does not establish route or fixture disposal.
enum FixtureCleanupStatus {
  /// The original operation has not settled.
  pending,

  /// The original operation completed without an error.
  succeeded,

  /// The original operation or ownership check failed.
  failed,
}

/// Retains one original cleanup operation, including its unchanged failure.
final class FixtureCleanupReceipt {
  FixtureCleanupReceipt._(this.step);

  /// The cleanup boundary, without owner or wallet details.
  final String step;

  Future<void>? _original;
  FixtureCleanupStatus _status = FixtureCleanupStatus.pending;
  Object? _error;
  StackTrace? _stackTrace;

  /// The exact original Future, absent for a synchronous operation or throw.
  Future<void>? get original => _original;

  /// Pending operations never become successful through elapsed time.
  FixtureCleanupStatus get status => _status;

  /// The original failure, retained privately after the command returns.
  Object? get error => _error;

  /// The exact trace received with the original failure.
  StackTrace? get stackTrace => _stackTrace;

  void _follow(Future<void> original) {
    _original = original;
    unawaited(
      original.then<void>(
        _succeeded,
        onError: _fail,
      ),
    );
  }

  void _succeeded(void _) => _status = FixtureCleanupStatus.succeeded;

  void _fail(Object error, StackTrace trace) {
    _error = error;
    _stackTrace = trace;
    _status = FixtureCleanupStatus.failed;
  }
}

/// Holds fixture admission until the original route and owner are cleaned up.
/// This receipt establishes no restoration of the underlying wallet owner.
final class FixtureCleanup {
  /// Reserves admission before invoking Navigator.push or mounting a fixture.
  FixtureCleanup({required this.name});

  /// The read-only fixture kind, never a wallet identifier.
  final String name;

  final List<FixtureCleanupReceipt> _receipts = <FixtureCleanupReceipt>[];
  Object? _owner;
  bool _opened = false;
  bool _pushReturned = false;
  bool _disposed = false;
  bool _disposeReturned = false;

  /// Keeps inactive, pending, failed and unobserved fixtures admitted.
  String? get heldName =>
      _opened &&
          _pushReturned &&
          _owner != null &&
          _disposed &&
          _disposeReturned &&
          _receipts.every(
            (FixtureCleanupReceipt receipt) =>
                receipt.status == FixtureCleanupStatus.succeeded,
          )
      ? null
      : name;

  /// Original operations remain inspectable without replacing their Futures.
  List<FixtureCleanupReceipt> get receipts =>
      List<FixtureCleanupReceipt>.unmodifiable(_receipts);

  /// Watches transition completion separately from Navigator.push's pop result.
  /// A synchronous push failure retains and rethrows its original trace.
  void open({
    required Future<void> routeCompleted,
    required Future<void> Function() push,
  }) {
    if (_opened) {
      _refuse('Fixture route was already opened');
    }
    _opened = true;
    _record('route-completed')._follow(routeCompleted);
    final FixtureCleanupReceipt popped = _record('route-popped');
    try {
      popped._follow(push());
      _pushReturned = true;
    } on Object catch (error, trace) {
      popped._fail(error, trace);
      Error.throwWithStackTrace(error, trace);
    }
  }

  /// Captures the first actual State before it creates any fixture resources.
  void attach(Object owner) {
    if (_owner != null || _disposed) {
      _refuse('Fixture owner was already attached');
    }
    _owner = owner;
  }

  /// Invokes every captured original cleanup once, even if a sibling fails.
  /// Missing or unsuccessful State.dispose keeps admission held permanently.
  void dispose({
    required Object owner,
    required List<void Function()> dispose,
    required List<Future<void> Function()> close,
    required void Function() stateDisposed,
  }) {
    if (!identical(_owner, owner) || _disposed) {
      _record('disposal-ownership')._fail(
        StateError('Fixture disposal owner changed or was already disposed'),
        StackTrace.current,
      );
      return;
    }
    _disposed = true;
    for (final void Function() original in dispose) {
      _synchronous('resource-disposed', original);
    }
    for (final Future<void> Function() original in close) {
      final FixtureCleanupReceipt receipt = _record('resource-closed');
      try {
        receipt._follow(original());
      } on Object catch (error, trace) {
        receipt._fail(error, trace);
      }
    }
    _synchronous('state-disposed', stateDisposed);
    _disposeReturned = true;
  }

  FixtureCleanupReceipt _record(String step) {
    final FixtureCleanupReceipt receipt = FixtureCleanupReceipt._(step);
    _receipts.add(receipt);
    return receipt;
  }

  void _synchronous(String step, void Function() original) {
    final FixtureCleanupReceipt receipt = _record(step);
    try {
      original();
      receipt._status = FixtureCleanupStatus.succeeded;
    } on Object catch (error, trace) {
      receipt._fail(error, trace);
    }
  }

  Never _refuse(String reason) {
    final StateError error = StateError(reason);
    final StackTrace trace = StackTrace.current;
    _record('ownership-refused')._fail(error, trace);
    Error.throwWithStackTrace(error, trace);
  }
}
