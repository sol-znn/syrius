import 'dart:async';

/// Queued admission and an actual close result are separate facts.
enum PresentationCloseStatus {
  /// The original admission delay has not settled.
  queued,

  /// Ownership passed and the original native close was invoked once.
  admitted,

  /// The original close Future completed, without proving process exit.
  completed,

  /// Ownership refused before the native callback was invoked.
  refused,

  /// The original wait or close failed, without a retry.
  failed,
}

/// A terminal original result retained independently of an HTTP connection.
final class PresentationCloseOutcome {
  PresentationCloseOutcome._(this.status, this.error, this.stackTrace);

  /// Completion never synthesizes queued or admitted as a close result.
  final PresentationCloseStatus status;

  /// The unchanged original error, absent after successful completion.
  final Object? error;

  /// The exact trace received with the original failure.
  final StackTrace? stackTrace;
}

/// Owns one delayed native admission, with no launcher, window or retry logic.
final class PresentationCloseAttempt {
  /// Reserves receipts before invoking the captured original wait callback.
  PresentationCloseAttempt({
    required void Function() requireCurrent,
    required Future<void> Function() close,
    Future<void> Function()? waitUntilAdmission,
  }) {
    try {
      final Future<void> original = (waitUntilAdmission ?? _wait)();
      _originalAdmission = original;
      unawaited(
        original.then<void>(
          (_) => _admit(requireCurrent, close),
          onError: (Object error, StackTrace trace) {
            if (_decided) {
              return;
            }
            _decided = true;
            _finish(PresentationCloseStatus.failed, error, trace);
          },
        ),
      );
    } on Object catch (error, trace) {
      _decided = true;
      _finish(PresentationCloseStatus.failed, error, trace);
    }
  }

  final Completer<void> _admission = Completer<void>();
  final Completer<PresentationCloseOutcome> _completion =
      Completer<PresentationCloseOutcome>();
  Future<void>? _originalAdmission;
  Future<void>? _originalClose;
  PresentationCloseStatus _status = PresentationCloseStatus.queued;
  bool _decided = false;
  bool _admitted = false;

  static Future<void> _wait() =>
      Future<void>.delayed(const Duration(milliseconds: 100));

  /// The read-only current phase, which can remain admitted while closing.
  PresentationCloseStatus get status => _status;

  /// Reserved at construction; settles after the actual admission decision.
  /// Consult [status]: settlement alone does not mean close was admitted.
  Future<void> get admission => _admission.future;

  /// The exact wait Future, absent only if its callback threw synchronously.
  Future<void>? get originalAdmission => _originalAdmission;

  /// The exact close Future, absent before invocation or a synchronous throw.
  Future<void>? get originalClose => _originalClose;

  /// Retains the actual terminal outcome without a timeout or unhandled error.
  Future<PresentationCloseOutcome> get completion => _completion.future;

  /// Anonymous acknowledgement; queued never proves close or process exit.
  Map<String, Object?> snapshot() => Map<String, Object?>.unmodifiable(
    <String, Object?>{
      'status': _status.name,
      'queued': _status == PresentationCloseStatus.queued,
      'admitted': _admitted,
      'completed': _status == PresentationCloseStatus.completed,
      'exitProved': false,
    },
  );

  void _admit(
    void Function() requireCurrent,
    Future<void> Function() close,
  ) {
    if (_decided) {
      return;
    }
    _decided = true;
    try {
      requireCurrent();
    } on Object catch (error, trace) {
      _finish(PresentationCloseStatus.refused, error, trace);
      return;
    }
    _admitted = true;
    _status = PresentationCloseStatus.admitted;
    try {
      final Future<void> original = close();
      _originalClose = original;
      _admission.complete();
      unawaited(
        original.then<void>(
          (_) => _finish(PresentationCloseStatus.completed),
          onError: (Object error, StackTrace trace) =>
              _finish(PresentationCloseStatus.failed, error, trace),
        ),
      );
    } on Object catch (error, trace) {
      _finish(PresentationCloseStatus.failed, error, trace);
    }
  }

  void _finish(
    PresentationCloseStatus status, [
    Object? error,
    StackTrace? trace,
  ]) {
    if (_completion.isCompleted) {
      return;
    }
    _status = status;
    if (!_admission.isCompleted) {
      _admission.complete();
    }
    _completion.complete(PresentationCloseOutcome._(status, error, trace));
  }
}
