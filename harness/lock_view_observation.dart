/// Fixed boolean fields contain no input, paths or error text.
const Set<String> lockViewBooleanFields = <String>{
  'mounted', 'current', 'window_active', 'visible', 'route_current',
  'focus_allows_input', 'startup_interactive', 'busy', 'opening',
  'incorrect_password', 'attempt_storage_failed', 'has_error_message',
};

/// Only framework lifecycle labels may leave the child.
const Set<String> lockViewLifecycles = <String>{
  'resumed', 'inactive', 'hidden', 'paused', 'detached', 'unknown',
};

/// Original callback progress contains fixed labels and no input data.
const Set<String> lockViewUnlockPhases = <String>{
  'idle', 'entered', 'preflight_refused',
  'capture_requested',
  'capture_returned',
  'attempt_bound',
  'busy_mark_requested',
  'input_clear_requested',
  'capture_preferences',
  'capture_wallet_context',
  'capture_sdk',
  'capture_notifications',
  'capture_resources',
  'capture_initialization',
  'capture_reset',
  'capture_binding',
  'attempt_unavailable', 'decrypt_requested', 'decrypt_returned',
  'view_revoked', 'reset_requested', 'reset_returned',
  'reset_refused', 'result_guard_refused', 'init_requested',
  'init_returned', 'session_assigned', 'callback_requested',
  'callback_returned', 'password_exception', 'ledger_exception',
  'other_exception', 'authenticated_exception',
};

/// Unavailable owners remain explicit and never become authentication.
const Set<String> lockViewStatuses = <String>{
  'observed', 'unavailable', 'replaced', 'retired',
};

/// Unknown fields or values cannot enter a public child failure marker.
Map<String, Object?>? projectLockView(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  const Set<String> keys = <String>{
    'schema', 'status', 'owner_same', 'view',
  };
  if (!value.keys.toSet().containsAll(keys) ||
      value.keys.any((String key) => !keys.contains(key) && key != 'ok') ||
      (value.containsKey('ok') && value['ok'] != true) ||
      value['schema'] is! int || value['schema'] != 1 ||
      value['status'] is! String ||
      !lockViewStatuses.contains(value['status']) ||
      value['owner_same'] is! bool) {
    return null;
  }
  final Object? raw = value['view'];
  Map<String, Object?>? view;
  if (value['status'] == 'observed') {
    final bool progress = raw is Map<String, dynamic> &&
        raw.containsKey('unlock_phase');
    final Set<String> fields = <String>{
      ...lockViewBooleanFields, 'password_failures', 'lifecycle',
      if (progress) ...<String>{'unlock_phase', 'unlock_requests'},
    };
    if (value['owner_same'] != true || raw is! Map<String, dynamic> ||
        raw.length != fields.length || !raw.keys.toSet().containsAll(fields) ||
        lockViewBooleanFields.any((String key) => raw[key] is! bool) ||
        raw['password_failures'] is! int ||
        (raw['password_failures'] as int) < 0 ||
        (raw['password_failures'] as int) > 255 ||
        raw['lifecycle'] is! String ||
        !lockViewLifecycles.contains(raw['lifecycle']) ||
        (progress && (raw['unlock_phase'] is! String ||
            !lockViewUnlockPhases.contains(raw['unlock_phase']) ||
            raw['unlock_requests'] is! int ||
            (raw['unlock_requests'] as int) < 0 ||
            (raw['unlock_requests'] as int) > 255))) {
      return null;
    }
    view = Map<String, Object?>.from(raw);
  } else if (value['owner_same'] != false || raw != null) {
    return null;
  }
  return <String, Object?>{
    'schema': 1, 'status': value['status'],
    'owner_same': value['owner_same'], 'view': view,
  };
}
