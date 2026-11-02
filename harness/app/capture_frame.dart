import 'dart:async';

/// Frame completion and permission to read pixels are separate facts.
enum CaptureFrameStatus {
  /// The original frame has not settled or passed its admission deadline.
  pending,

  /// The original frame completed before its admission deadline.
  ready,

  /// Missing, failed or late frame proof permanently holds this scope.
  held,
}

/// The actual original frame result, including after admission was refused.
final class CaptureFrameOutcome {
  CaptureFrameOutcome._(this.completed, this.error, this.stackTrace);

  /// True only when the original frame Future completed without an error.
  final bool completed;

  /// The unchanged original failure, absent after successful completion.
  final Object? error;

  /// The exact trace received with the original frame failure.
  final StackTrace? stackTrace;
}

/// Anonymous refusal; the original diagnostic stays in its retained receipt.
final class CaptureFrameRefused implements Exception {
  /// Refuses pending admission, a held scope or another capture in progress.
  const CaptureFrameRefused();

  @override
  String toString() => 'The original capture frame is unavailable';
}

/// One original frame Future, with a separate once-only admission decision.
final class CaptureFrameReceipt {
  CaptureFrameReceipt._();

  final Completer<bool> _admission = Completer<bool>();
  final Completer<CaptureFrameOutcome> _completion =
      Completer<CaptureFrameOutcome>();
  Future<void>? _original;
  CaptureFrameOutcome? _outcome;
  CaptureFrameStatus _status = CaptureFrameStatus.pending;
  bool _timedOut = false;
  Object? _admissionError;
  StackTrace? _admissionTrace;

  /// A late original success cannot change held admission back to ready.
  CaptureFrameStatus get status => _status;

  /// The identical returned frame Future, absent after a synchronous throw.
  Future<void>? get original => _original;

  /// Settles once with permission or refusal, never with a fake frame result.
  Future<bool> get admission => _admission.future;

  /// Settles only with the original frame's actual success or failure.
  Future<CaptureFrameOutcome> get completion => _completion.future;

  /// The actual result, absent while the original frame remains pending.
  CaptureFrameOutcome? get outcome => _outcome;

  /// A deadline refusal is not completion of the pending original frame.
  bool get timedOut => _timedOut;

  /// An unchanged observation or clock failure, separate from the frame result.
  Object? get admissionError => _admissionError;

  /// The exact trace received if admission could not observe a timely frame.
  StackTrace? get admissionStackTrace => _admissionTrace;

  void _start(
    Future<void> Function() waitForFrame,
    Future<void> Function() waitUntilDeadline,
  ) {
    final Future<void> original;
    try {
      original = waitForFrame();
      _original = original;
    } on Object catch (error, trace) {
      _settleOriginal(error, trace);
      return;
    }
    try {
      unawaited(
        original.then<void>(
          _frameCompleted,
          onError: _settleOriginal,
        ),
      );
    } on Object catch (error, trace) {
      // Failed observation cannot settle an otherwise unknown original.
      _hold(error: error, trace: trace);
    }
    if (_status != CaptureFrameStatus.pending) {
      return;
    }
    try {
      unawaited(
        waitUntilDeadline().then<void>(
          (_) => _hold(timedOut: true),
          onError: (Object error, StackTrace trace) =>
              _hold(error: error, trace: trace),
        ),
      );
    } on Object catch (error, trace) {
      _hold(error: error, trace: trace);
    }
  }

  void _hold({bool timedOut = false, Object? error, StackTrace? trace}) {
    if (_status != CaptureFrameStatus.pending) {
      return;
    }
    _timedOut = timedOut;
    _admissionError = error;
    _admissionTrace = trace;
    _status = CaptureFrameStatus.held;
    _admission.complete(false);
  }

  void _frameCompleted(void _) => _settleOriginal();

  void _settleOriginal([Object? error, StackTrace? trace]) {
    if (_completion.isCompleted) {
      return;
    }
    final CaptureFrameOutcome outcome = CaptureFrameOutcome._(
      error == null,
      error,
      trace,
    );
    _outcome = outcome;
    if (_status == CaptureFrameStatus.pending) {
      _status = error == null
          ? CaptureFrameStatus.ready
          : CaptureFrameStatus.held;
      _admission.complete(error == null);
    }
    _completion.complete(outcome);
  }
}

/// Serial frame admission, without native renderer or restoration proof.
/// Retain this owner: replacing it must not clear a held original frame.
final class CaptureFrameGate {
  /// Reserves before either callback can synchronously reenter the caller.
  CaptureFrameGate({
    required this._waitForFrame,
    Future<void> Function()? waitUntilDeadline,
  }) : _waitUntilDeadline = waitUntilDeadline ?? _deadline;

  final Future<void> Function() _waitForFrame;
  final Future<void> Function() _waitUntilDeadline;
  CaptureFrameReceipt? _receipt;
  bool _busy = false;
  bool _held = false;

  static Future<void> _deadline() =>
      Future<void>.delayed(const Duration(milliseconds: 250));

  /// At most one receipt is retained; a held receipt is never replaced.
  /// A finished positive receipt remains available until the next admission.
  CaptureFrameReceipt? get receipt => _receipt;

  /// A timeout or original failure remains held after any late settlement.
  bool get heldUnknown => _held || _receipt?.status == CaptureFrameStatus.held;

  /// Call before theme effects as well as before starting another readback.
  void requireIdle() {
    if (_busy || heldUnknown) {
      throw const CaptureFrameRefused();
    }
  }

  /// Runs readback only after positive original frame completion.
  /// Admission remains busy until the original readback callback settles.
  Future<T> capture<T>(Future<T> Function() readback) async {
    requireIdle();
    final CaptureFrameReceipt original = CaptureFrameReceipt._();
    _receipt = original;
    _busy = true;
    original._start(_waitForFrame, _waitUntilDeadline);
    try {
      final bool admitted = await original.admission;
      if (!admitted ||
          original.status != CaptureFrameStatus.ready ||
          !identical(_receipt, original) ||
          heldUnknown) {
        _held = true;
        throw const CaptureFrameRefused();
      }
      return await readback();
    } finally {
      if (original.status == CaptureFrameStatus.held) {
        _held = true;
      }
      if (!heldUnknown && identical(_receipt, original)) {
        _busy = false;
      }
    }
  }
}
