import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// The two existing positive policies. Zero never means an enabled policy.
enum SecurityPreference {
  /// Minutes until the existing inactivity lock.
  lockMinutes,

  /// Wrong passwords before the existing removal policy.
  wrongPasswords,
}

/// Absence uses the established default; malformed stored data stays unknown.
int? securityPositivePreference(
  Object? value, {
  required bool exists,
  required int fallback,
}) {
  if (!exists) {
    return fallback > 0 ? fallback : null;
  }
  return value is num && value.isFinite && value > 0 && value == value.toInt()
      ? value.toInt()
      : null;
}

/// Refuses an original action without displaying a library diagnostic.
class SecuritySettingsRefused implements Exception {
  /// The original action no longer owns its target.
  const SecuritySettingsRefused();
}

/// One captured preference box and its original policy effects.
abstract interface class SecurityPolicySession {
  /// Shared by every view writing this exact box.
  Object get store;

  /// Includes the original visible section and wallet generation.
  bool get isCurrent;

  /// Resource ownership survives section disposal after a put was admitted.
  bool get ownsStore;

  /// Awaits the original box's write, with no global effect beforehand.
  Future<void> persist(SecurityPreference preference, int value);

  /// Requires the exact saved value before changing the application policy.
  void apply(SecurityPreference preference, int value);

  /// Awaits the original timer callback, including a synchronous callback.
  Future<void> effect(SecurityPreference preference);

  /// Called only while the original surface still owns presentation.
  Future<void> notify(SecurityPreference preference);
}

/// The immutable result of signing an explicitly captured message or file.
class SecuritySignature {
  /// Contains data from the original signing operation only.
  const SecuritySignature({required this.signature, required this.publicKey});

  /// The encoded signature, not a transaction hash.
  final String signature;

  /// The original signing account's encoded public key.
  final String publicKey;
}

/// Signing, verification and external input captured before suspension.
abstract interface class SecurityCryptoSession {
  /// Staleness is monotonic for this original operation.
  bool get isCurrent;

  /// Signs UTF-8 text, retaining the 32-byte message refusal.
  Future<SecuritySignature> signText(String message);

  /// Signs the existing digest of the exact selected file.
  Future<SecuritySignature> signFile(String path);

  /// Verifies the original immutable triple.
  Future<bool> verifyText(String message, String signature, String publicKey);

  /// Verifies the digest of the exact originally selected file.
  Future<bool> verifyFile(String path, String signature, String publicKey);

  /// Native input is an explicit action, never a presentation default.
  Future<String?> pickFile();

  /// A late paste cannot target a replacement field.
  Future<String?> paste();

  /// Copies only from the original visible field or result.
  Future<void> copy(String value);
}

/// Pure state. Mounting a view does not write preferences.
class SecuritySettingsState {
  /// Keeps saved custom positive values even when absent from the presets.
  const SecuritySettingsState({
    required this.lockMinutes,
    required this.wrongPasswords,
    this.busy = false,
    this.failed = false,
  });

  /// The persisted existing inactivity duration.
  final int? lockMinutes;

  /// The persisted existing exhaustion limit.
  final int? wrongPasswords;

  /// Prevents duplicate policy admission in this presenter.
  final bool busy;

  /// A generic failure, never raw storage text.
  final bool failed;
}

/// Applies positive policies over a shared original-box/key lane.
class SecuritySettingsPresenter extends Cubit<SecuritySettingsState> {
  /// No capture or write occurs until an explicit choice.
  SecuritySettingsPresenter({
    required SecuritySettingsState initial,
    required this._capture,
  }) : super(initial);

  static final Expando<Map<SecurityPreference, Future<void>>> _lanes =
      Expando<Map<SecurityPreference, Future<void>>>();

  final SecurityPolicySession? Function() _capture;
  int _epoch = 0;
  bool _visible = true;
  Object? _error;
  Object? _observationError;
  Object? _pending;

  /// Saved callbacks bind this generation, including unobserved round trips.
  int get epoch => _epoch;

  /// Retains the original error for diagnostics outside the product UI.
  Object? get error => _error;

  /// Optional observers cannot replace the original persistence result.
  Object? get observationError => _observationError;

  @override
  void onChange(Change<SecuritySettingsState> change) {
    try {
      super.onChange(change);
    } on Object catch (error, trace) {
      // Returning normally preserves Cubit's actual state and stream delivery.
      _observationError = error;
      _report(error, trace);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    try {
      super.onError(error, stackTrace);
    } on Object {
      // A diagnostic observer cannot substitute its own error.
    }
  }

  void _report(Object error, StackTrace trace) {
    try {
      addError(error, trace);
    } on Object {
      // Diagnostics do not alter the owned operation or its original result.
    }
  }

  void _publish(SecuritySettingsState next) {
    if (!isClosed) {
      try {
        emit(next);
      } on Object catch (error, trace) {
        // Reentrant close may end delivery, but cannot skip a committed effect.
        _report(error, trace);
      }
    }
  }

  /// Revokes queued work and paint; an admitted put retains its completion.
  void setVisible({required bool visible}) {
    if (isClosed || _visible == visible) {
      return;
    }
    _visible = visible;
    if (!visible) {
      _epoch++;
    }
  }

  bool _current(SecurityPolicySession session, int epoch) =>
      !isClosed && _visible && epoch == _epoch && session.isCurrent;

  /// Persists, applies and observes the original action in that order.
  Future<bool> choose(
    SecurityPreference preference,
    int value, {
    required int epoch,
  }) async {
    if (isClosed ||
        !_visible ||
        _pending != null ||
        state.busy ||
        epoch != _epoch ||
        value <= 0) {
      return false;
    }
    final int? previous = preference == SecurityPreference.lockMinutes
        ? state.lockMinutes
        : state.wrongPasswords;
    if (previous == value) {
      return false;
    }
    final Object operation = Object();
    _pending = operation;
    SecurityPolicySession? session;
    Map<SecurityPreference, Future<void>>? lanes;
    Completer<void>? released;
    bool applied = false;
    try {
      session = _capture();
      if (session == null || !session.isCurrent || !session.ownsStore) {
        return false;
      }
      lanes = _lanes[session.store] ??= <SecurityPreference, Future<void>>{};
      final Future<void> previousWrite =
          lanes[preference] ?? Future<void>.value();
      released = Completer<void>();
      lanes[preference] = released.future;
      // Both reservations precede all synchronous Cubit observers.
      _publish(
        SecuritySettingsState(
          lockMinutes: state.lockMinutes,
          wrongPasswords: state.wrongPasswords,
          busy: true,
        ),
      );
      await previousWrite;
      if (!_current(session, epoch) || !session.ownsStore) {
        throw const SecuritySettingsRefused();
      }
      await session.persist(preference, value);
      if (!session.ownsStore) {
        throw const SecuritySettingsRefused();
      }
      session.apply(preference, value);
      applied = true;
      await session.effect(preference);
      _publish(
        SecuritySettingsState(
          lockMinutes: preference == SecurityPreference.lockMinutes
              ? value
              : state.lockMinutes,
          wrongPasswords: preference == SecurityPreference.wrongPasswords
              ? value
              : state.wrongPasswords,
          busy: true,
        ),
      );
      if (_current(session, epoch)) {
        await session.notify(preference);
      }
      return true;
    } on Object catch (error) {
      _error = error;
      if (applied || (session != null && _current(session, epoch))) {
        _publish(
          SecuritySettingsState(
            lockMinutes: applied && preference == SecurityPreference.lockMinutes
                ? value
                : state.lockMinutes,
            wrongPasswords:
                applied && preference == SecurityPreference.wrongPasswords
                ? value
                : state.wrongPasswords,
            busy: true,
            failed: !applied,
          ),
        );
      }
      return applied;
    } finally {
      released?.complete();
      if (released != null && identical(lanes?[preference], released.future)) {
        unawaited(lanes?.remove(preference));
      }
      if (identical(_pending, operation)) {
        _pending = null;
      }
      _publish(
        SecuritySettingsState(
          lockMinutes: state.lockMinutes,
          wrongPasswords: state.wrongPasswords,
          failed: state.failed,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _visible = false;
    _epoch++;
    return super.close();
  }
}
