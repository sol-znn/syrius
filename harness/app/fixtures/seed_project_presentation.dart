import 'dart:async';

import 'seed_policy.dart';

/// One captured original Project presentation, independent of publication.
/// Only its exact confirmed original hash may request its original exit.
final class SeedProjectPresentation {
  /// Retains the original owner, exit and completed-route Future.
  SeedProjectPresentation({
    required this._originalCurrent,
    required this._submittedCurrent,
    required this._tapOriginalExit,
    required this._originalRouteCompleted,
    Duration closeTimeout = const Duration(seconds: 5),
  }) : _closeTimeout = closeTimeout {
    if (closeTimeout <= Duration.zero ||
        closeTimeout > const Duration(seconds: 5)) {
      throw ArgumentError('A bounded presentation close is required');
    }
  }

  final bool Function() _originalCurrent;
  final bool Function(String) _submittedCurrent;
  final Future<void> Function(void Function()) _tapOriginalExit;
  final Future<Object?> _originalRouteCompleted;
  final Duration _closeTimeout;
  bool _held = false;
  bool _attempted = false;
  bool _closed = false;
  String? _acceptedHash;

  /// A positively observed original route completion remains an event.
  bool get closed => _closed;

  void _require(bool Function() condition) {
    bool current = false;
    try {
      current = !_held && condition();
    } on Object {
      current = false;
    }
    if (!current) {
      _held = true;
      throw const SeedRefused('original-project-presentation-changed');
    }
  }

  void _requireOwner(void Function() requireOwner) {
    try {
      requireOwner();
    } on Object {
      _held = true;
      rethrow;
    }
  }

  /// Rechecks only the captured view owner at original publication boundaries.
  void requireCaptured() {
    if (_attempted) {
      throw const SeedRefused('original-project-presentation-held');
    }
    _require(_originalCurrent);
  }

  /// Does not publish, sign, replace a receipt, poll a chain or admit a retry.
  Future<void> close(String hash, void Function() requireOwner) async {
    if (!seedHash(hash)) {
      throw const SeedRefused('confirmed-project-presentation-required');
    }
    _requireOwner(requireOwner);
    if (_closed && hash == _acceptedHash) return;
    if (_attempted || _acceptedHash != null && hash != _acceptedHash) {
      throw const SeedRefused('original-project-presentation-held');
    }
    void current() {
      _requireOwner(requireOwner);
      _require(() => _originalCurrent() && _submittedCurrent(hash));
    }
    current();
    _acceptedHash = hash;
    _attempted = true;
    await _tapOriginalExit(current);
    try {
      await _originalRouteCompleted.timeout(_closeTimeout);
    } on TimeoutException {
      throw const SeedRefused('original-project-presentation-close-pending');
    }
    _requireOwner(requireOwner);
    _closed = true;
  }
}
