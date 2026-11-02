/// An opened wallet no longer has the original inspection resources.
class ReadonlyWalletAdmissionRefused implements Exception {
  /// No replacement wallet, transport or native frame is admitted.
  const ReadonlyWalletAdmissionRefused();
}

/// Retains one original frame observation and the opened wallet's owners.
/// The native adapter supplies actual resources; tests supply isolated actors.
class ReadonlyWalletAdmission {
  ReadonlyWalletAdmission._(this._ownersCurrent);

  final bool Function() _ownersCurrent;
  Future<void>? _originalFrame;
  Object? _frameError;
  StackTrace? _frameTrace;
  bool _ready = false;
  bool _held = false;
  bool _checking = false;

  /// The original observation stays retained after a refusal or late outcome.
  Future<void>? get originalFrame => _originalFrame;

  /// Captures once, checks both sides of the original await and never retries.
  static Future<ReadonlyWalletAdmission> seal({
    required bool Function() ownersCurrent,
    required Future<void> Function() observeFrame,
  }) async {
    final ReadonlyWalletAdmission admission =
        ReadonlyWalletAdmission._(ownersCurrent);
    try {
      admission._requireOwners();
      final Future<void> original = observeFrame();
      admission._originalFrame = original;
      // Observe settlement even if the synchronous owner check below refuses.
      // The unchanged original failure still propagates from this seal call.
      final Future<void> settled = original.then<void>(
        (_) {},
        onError: (Object error, StackTrace trace) {
          admission
            .._frameError = error
            .._frameTrace = trace;
        },
      );
      admission._requireOwners();
      await settled;
      final Object? error = admission._frameError;
      if (error != null) {
        Error.throwWithStackTrace(error, admission._frameTrace!);
      }
      admission
        .._requireOwners()
        .._ready = true
        ..requireCurrent();
      return admission;
    } on Object {
      admission._held = true;
      rethrow;
    }
  }

  /// Restoring an observed lost owner cannot revive this inspection session.
  void requireCurrent() {
    if (!_ready) _refuse();
    _requireOwners();
  }

  void _requireOwners() {
    if (_held || _checking) _refuse();
    _checking = true;
    try {
      if (!_ownersCurrent() || _held) _refuse();
    } on Object {
      _held = true;
      rethrow;
    } finally {
      _checking = false;
    }
  }

  Never _refuse() {
    _held = true;
    throw const ReadonlyWalletAdmissionRefused();
  }
}
