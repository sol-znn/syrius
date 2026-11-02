import 'dart:async';

/// The source boundary a preparation would need to cross.
enum CaptureMode {
  /// Navigation inside an already owned working session.
  navigation,

  /// An independent read-only view, never actual-wallet evidence.
  presentation,

  /// Authentication or onboarding with an original entry owner.
  entry,

  /// A positively committed original initialization.
  ready,

  /// Original native startup and its renderer handoff.
  coldStart,

  /// A route that would cover an existing working owner.
  coveredShell,
}

/// One immutable request for an original renderer's observed state.
final class CaptureFrameSpec {
  /// Static views omit film fields; moving views need an actual frame lease.
  const CaptureFrameSpec({
    required this.renderer,
    this.asset,
    this.decodedIndex,
    this.phase,
  });

  /// The exact original renderer or view-generation identity.
  final Object renderer;

  /// The captured original asset identity, when a film is requested.
  final Object? asset;

  /// A decoded original frame, never an estimate from elapsed time.
  final int? decodedIndex;

  /// A pinned original transition value, not a requested animation duration.
  final double? phase;

  bool get _valid {
    final int? index = decodedIndex;
    final double? progress = phase;
    return (index == null || (index >= 0 && asset != null)) &&
        (progress == null ||
            (progress.isFinite && progress >= 0 && progress <= 1));
  }

  bool _matches(CaptureFrameSpec other) =>
      identical(renderer, other.renderer) &&
      identical(asset, other.asset) &&
      decodedIndex == other.decodedIndex &&
      phase == other.phase;
}

/// The screen, theme and original frame cannot change during a run.
final class CapturePlan {
  /// Creates a request; admission validates it before calling a source.
  const CapturePlan({
    required this.screen,
    required this.theme,
    required this.mode,
    required this.frame,
  });

  /// An anonymous catalog or presentation identifier.
  final String screen;

  /// Exactly dark or light; no preference is written by this protocol.
  final String theme;

  /// Presentation output cannot qualify an actual-wallet capture.
  final CaptureMode mode;

  /// The immutable original frame to observe before and after the shot.
  final CaptureFrameSpec frame;

  bool get _valid =>
      RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(screen) &&
      (theme == 'dark' || theme == 'light') &&
      frame._valid;
}

/// A refusal code contains no wallet path, credential or transport payload.
class CaptureRefused implements Exception {
  /// Names the missing proof without attempting a fallback.
  const CaptureRefused(this.code);

  /// The anonymous boundary that could not admit the request.
  final String code;

  @override
  String toString() => 'CaptureRefused($code)';
}

/// Unforgeable within this protocol; a new theme receives another token.
final class CaptureToken {
  CaptureToken._(this.plan);

  /// The identical immutable request reserved before any source callback.
  final CapturePlan plan;
}

/// Positive preparation evidence from the originally captured source.
final class CapturePrepared {
  /// A provider supplies this only after its original preparation settles.
  const CapturePrepared({
    required this.token,
    required this.source,
    required this.route,
  });

  /// The exact run that requested the original preparation.
  final CaptureToken token;

  /// The exact captured source, rather than a replacement with equal values.
  final Object source;

  /// The actual route or independent presentation root prepared by the owner.
  final Object route;
}

/// An actual observation, separate from the desired frame in the plan.
final class CaptureObservedFrame {
  /// Renderer adapters must read their original state, never echo the plan.
  const CaptureObservedFrame({
    required this.token,
    required this.source,
    required this.route,
    required this.frame,
  });

  /// The original run whose frame was observed.
  final CaptureToken token;

  /// The original captured source that owns the observation.
  final Object source;

  /// The identical positively prepared route or presentation root.
  final Object route;

  /// The renderer, asset, decoded frame and transition value actually read.
  final CaptureFrameSpec frame;
}

/// A positive restoration receipt is independent of visible Home or theme.
final class CaptureRestored {
  /// The owner supplies this after all original cleanup Futures settle.
  const CaptureRestored({
    required this.token,
    required this.source,
    required this.originalRoute,
  });

  /// The exact original preparation being restored.
  final CaptureToken token;

  /// The original resource owner, never a newly captured service set.
  final Object source;

  /// The original route identity captured before preparation.
  final Object originalRoute;
}

/// Captured callbacks cannot discover replacement files, SDKs or services.
class CaptureSource<T> {
  /// All proofs and operations must retain their original native owners.
  /// Current proof includes an original frame lease throughout PNG encoding;
  /// two matching observations cannot create that missing renderer guarantee.
  CaptureSource({
    required this.identity,
    required this.originalRoute,
    required this._isCurrent,
    required this._prepare,
    required this._observe,
    required this._shot,
    required this._restore,
    required this._isRestored,
  });

  /// The original profile/view/resource scope retained by every callback.
  final Object identity;

  /// Captured before preparation can cover or replace a route.
  final Object originalRoute;
  final bool Function() _isCurrent;
  final Future<CapturePrepared?> Function(CaptureToken) _prepare;
  final Future<CaptureObservedFrame?> Function(CaptureToken) _observe;
  final Future<T> Function(CaptureToken) _shot;
  final Future<CaptureRestored?> Function(CaptureToken) _restore;
  final bool Function(CaptureRestored) _isRestored;
}

/// Evidence is reserved before invoking an original asynchronous callback.
class CaptureOperation {
  CaptureOperation._(this.name);

  /// One of the finite prepare, observation, shot or restoration steps.
  final String name;
  final Completer<void> _settled = Completer<void>();
  Future<Object?>? _original;
  Object? _value;
  Object? _error;
  StackTrace? _trace;

  /// The identical returned Future; null only for a synchronous throw.
  Future<Object?>? get original => _original;

  /// Completes only when the original returned or failed, with no timeout.
  Future<void> get settled => _settled.future;

  /// Whether an actual original outcome has been observed.
  bool get isSettled => _settled.isCompleted;

  /// The original value, including a value from a subsequently stale run.
  Object? get value => _value;

  /// The exact original failure, retained independently of UI lifetime.
  Object? get error => _error;

  /// The exact trace delivered with [error].
  StackTrace? get stackTrace => _trace;

  void _start(Future<Object?> Function() call) {
    try {
      final Future<Object?> original = call();
      _original = original;
      unawaited(
        original.then<void>(
          (Object? value) => _finish(value: value),
          onError: (Object error, StackTrace trace) =>
              _finish(error: error, trace: trace),
        ),
      );
    } on Object catch (error, trace) {
      _finish(error: error, trace: trace);
    }
  }

  void _finish({Object? value, Object? error, StackTrace? trace}) {
    if (_settled.isCompleted) {
      return;
    }
    _value = value;
    _error = error;
    _trace = trace;
    _settled.complete();
  }
}

/// Qualification and restoration are separate facts about the same run.
enum CaptureStatus {
  /// Both frame observations and original restoration were proved.
  captured,

  /// No preparation effect was admitted.
  refused,

  /// An original failed, but its exact restoration was positively proved.
  failed,

  /// Source or restoration uncertainty permanently prevents another run.
  heldUnknown,
}

/// The original outcomes remain available even when capture was refused.
class CaptureOutcome<T> {
  CaptureOutcome._({
    required this.plan,
    required this.status,
    required this.result,
    required this.error,
    required this.stackTrace,
    required this.restorationVerified,
  });

  /// The immutable original request, including its evidence mode.
  final CapturePlan plan;

  /// Only [CaptureStatus.captured] qualifies the requested frame.
  final CaptureStatus status;

  /// The original shot result, which may remain unqualified after refusal.
  final T? result;

  /// The first unchanged failure observed by this run.
  final Object? error;

  /// The original trace for [error].
  final StackTrace? stackTrace;

  /// Equal values or a visible prior route never imply this fact.
  final bool restorationVerified;
}

/// Retains finite original receipts independently of the presenting widget.
class CaptureRun<T> {
  CaptureRun._(this.plan) : token = CaptureToken._(plan);

  /// The immutable original screen/theme/frame request.
  final CapturePlan plan;

  /// Reserved before the source capture callback can reenter the protocol.
  final CaptureToken token;
  final Completer<CaptureOutcome<T>> _completion =
      Completer<CaptureOutcome<T>>();
  final List<CaptureOperation> _operations = <CaptureOperation>[];
  Object? _error;
  StackTrace? _trace;
  bool _held = false;

  /// Never completes merely because the UI disappears or a deadline passes.
  Future<CaptureOutcome<T>> get completion => _completion.future;

  /// At most five original steps; no retries or replacement shots are added.
  List<CaptureOperation> get operations =>
      List<CaptureOperation>.unmodifiable(_operations);

  /// Monotonic loss of original source or restoration proof.
  bool get heldUnknown => _held;

  void _remember(Object error, StackTrace trace) {
    _error ??= error;
    _trace ??= trace;
  }
}

/// A bounded protocol, not a native owner-transfer or startup implementation.
/// The owner must retain this instance; replacing it cannot clear a held scope.
class CaptureProtocol<T> {
  /// Captures one source synchronously before its first asynchronous effect.
  CaptureProtocol({required this._capture});

  /// Production has no native entry, renderer-pin or restoration adapter yet.
  /// Refusal is explicit instead of constructing a successful fake binding.
  CaptureProtocol.unavailable() : _capture = ((CapturePlan _) => null);

  /// A protocol instance retains a small fixed number of admitted runs.
  /// This bound does not claim one instance can capture the entire catalog.
  static const int maxRuns = 16;

  final CaptureSource<T>? Function(CapturePlan) _capture;
  final List<CaptureRun<T>> _runs = <CaptureRun<T>>[];
  CaptureRun<T>? _active;
  bool _held = false;

  /// Source loss or uncertain restoration cannot be cleared by another plan.
  bool get heldUnknown => _held;

  /// Original admitted runs, including failures and unfinished operations.
  List<CaptureRun<T>> get runs => List<CaptureRun<T>>.unmodifiable(_runs);

  /// Reserves the exact run before any source proof or callback can reenter.
  CaptureRun<T> start(CapturePlan plan) {
    final CaptureRun<T> run = CaptureRun<T>._(plan);
    if (_held || _active != null || _runs.length >= maxRuns || !plan._valid) {
      _finish(run, CaptureStatus.refused, restored: false);
      return run;
    }
    _active = run;
    _runs.add(run);
    unawaited(_execute(run));
    return run;
  }

  /// Retires this scope while original Futures continue to report outcomes.
  void revoke() {
    _held = true;
    _active?._held = true;
  }

  void _hold(CaptureRun<T> run) {
    _held = true;
    run._held = true;
  }

  bool _current(CaptureRun<T> run, CaptureSource<T> source) {
    if (_held || run._held || !identical(_active, run)) {
      return false;
    }
    bool valid;
    try {
      valid = source._isCurrent();
    } on Object catch (error, trace) {
      run._remember(error, trace);
      valid = false;
    }
    if (!valid || _held || run._held || !identical(_active, run)) {
      _hold(run);
      return false;
    }
    return true;
  }

  Future<Object?> _observe(
    CaptureRun<T> run,
    CaptureSource<T> source,
    String name,
    Future<Object?> Function() call,
  ) async {
    if (!_current(run, source)) {
      throw const CaptureRefused('original-source-unavailable');
    }
    final CaptureOperation operation = CaptureOperation._(name);
    run._operations.add(operation);
    operation._start(call);
    final bool afterCallback = _current(run, source);
    await operation.settled;
    final bool afterAwait = _current(run, source);
    final Object? failure = operation.error;
    if (failure != null) {
      run._remember(failure, operation.stackTrace!);
      Error.throwWithStackTrace(failure, operation.stackTrace!);
    }
    if (!afterCallback || !afterAwait) {
      throw const CaptureRefused('original-source-unavailable');
    }
    return operation.value;
  }

  bool _frameMatches(
    CaptureRun<T> run,
    CaptureSource<T> source,
    CapturePrepared prepared,
    Object? observed,
  ) =>
      observed is CaptureObservedFrame &&
      identical(observed.token, run.token) &&
      identical(observed.source, source.identity) &&
      identical(observed.route, prepared.route) &&
      run.plan.frame._matches(observed.frame);

  Future<void> _execute(CaptureRun<T> run) async {
    CaptureSource<T>? source;
    bool restored = false;
    bool shotVerified = false;
    try {
      source = _capture(run.plan);
      if (source == null) {
        run._remember(
          const CaptureRefused('native-capture-proof-unavailable'),
          StackTrace.current,
        );
        return;
      }
      final CaptureSource<T> captured = source;
      final Object? prepared = await _observe(
        run,
        captured,
        'prepare',
        () => captured._prepare(run.token),
      );
      if (prepared is! CapturePrepared ||
          !identical(prepared.token, run.token) ||
          !identical(prepared.source, captured.identity)) {
        throw const CaptureRefused('original-preparation-unproven');
      }
      final Object? before = await _observe(
        run,
        captured,
        'frame-before',
        () => captured._observe(run.token),
      );
      if (!_frameMatches(run, captured, prepared, before)) {
        throw const CaptureRefused('original-frame-unproven');
      }
      await _observe(run, captured, 'shot', () => captured._shot(run.token));
      final Object? after = await _observe(
        run,
        captured,
        'frame-after',
        () => captured._observe(run.token),
      );
      if (!_frameMatches(run, captured, prepared, after)) {
        throw const CaptureRefused('original-frame-changed');
      }
      shotVerified = true;
    } on Object catch (error, trace) {
      run._remember(error, trace);
      if (source == null) {
        _hold(run);
      }
    } finally {
      final CaptureSource<T>? original = source;
      if (original != null &&
          run._operations.isNotEmpty &&
          _current(run, original)) {
        try {
          final Object? receipt = await _observe(
            run,
            original,
            'restore',
            () => original._restore(run.token),
          );
          if (receipt is! CaptureRestored ||
              !identical(receipt.token, run.token) ||
              !identical(receipt.source, original.identity) ||
              !identical(receipt.originalRoute, original.originalRoute)) {
            throw const CaptureRefused('original-restoration-unproven');
          }
          if (!_current(run, original)) {
            throw const CaptureRefused('original-source-unavailable');
          }
          final bool valid = original._isRestored(receipt);
          if (!valid || !_current(run, original)) {
            throw const CaptureRefused('original-restoration-unproven');
          }
          restored = true;
        } on Object catch (error, trace) {
          run._remember(error, trace);
          _hold(run);
        }
      }
      if (original != null && !restored) {
        _hold(run);
      }
      _finish(
        run,
        run._held
            ? CaptureStatus.heldUnknown
            : original == null
            ? CaptureStatus.refused
            : shotVerified && run._error == null
            ? CaptureStatus.captured
            : CaptureStatus.failed,
        restored: restored,
      );
    }
  }

  void _finish(
    CaptureRun<T> run,
    CaptureStatus status, {
    required bool restored,
  }) {
    final Iterable<CaptureOperation> shots = run._operations.where(
      (CaptureOperation operation) => operation.name == 'shot',
    );
    run._completion.complete(
      CaptureOutcome<T>._(
        plan: run.plan,
        status: status,
        result: shots.isEmpty ? null : shots.single.value as T?,
        error: run._error,
        stackTrace: run._trace,
        restorationVerified: restored,
      ),
    );
    if (!run._held && identical(_active, run)) {
      _active = null;
    }
  }
}
