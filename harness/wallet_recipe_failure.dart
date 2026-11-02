/// Only fixed recipe labels may leave the private command exchange.
const Set<String> walletRecipeActions = <String>{
  'observe', 'tap', 'type', 'scroll', 'key', 'unknown',
};

/// Dynamic node-selection keys collapse to one label without an endpoint.
const Set<String> walletRecipeControls = <String>{
  'none', 'unknown', 'launch_skip_hint', 'welcome_import',
  'import_words_12', 'import_words_24',
  'import_seed_field', 'import_continue', 'import_new_password',
  'import_confirm_password', 'import_password_continue', 'node_settings_add',
  'node_settings_endpoint', 'node_settings_endpoint_save',
  'node_settings_select', 'node_onboarding_continue',
  'node_settings_question_accept', 'node_settings_chain_toggle',
  'node_settings_client_chain', 'node_settings_chain_save', 'wallet_ready_open',
  'nav_settings', 'nav_dashboard', 'settings_node', 'settings_addresses',
  'settings_add_address', 'addresses_select',
};

/// Fixed server and observation refusals carry no exception text or payload.
const Set<String> walletRecipeFailureCodes = <String>{
  'wallet-recipe-action-refused', 'wallet-recipe-control-refused',
  'wallet-recipe-input-refused', 'wallet-recipe-node-view-ambiguous',
  'wallet-recipe-original-control-changed',
  'wallet-recipe-original-control-replaced',
  'wallet-recipe-original-control-moved',
  'wallet-recipe-original-control-moved-subpixel',
  'wallet-recipe-original-control-resized',
  'wallet-recipe-original-owner-changed',
  'wallet-recipe-original-address-context-changed',
  'wallet-recipe-original-question-changed',
  'wallet-recipe-original-ready-changed',
  'wallet-recipe-original-ready-unavailable',
  'wallet-recipe-private-input-refused',
  'wallet-recipe-question-already-used', 'wallet-recipe-question-facts-refused',
  'wallet-recipe-question-replaced', 'wallet-recipe-question-unowned',
  'wallet-recipe-refused', 'wallet-recipe-scroll-refused',
  'wallet-recipe-selection-origin-refused', 'wallet-recipe-transition-held',
  'wallet-recipe-visible-error',
  'wallet-recipe-stage-unsettled',
  'wallet-recipe-control-absent',
  'wallet-recipe-control-disabled',
  'wallet-recipe-control-widget-disabled',
  'wallet-recipe-address-backend-blocked',
  'wallet-recipe-address-mounted-blocked',
  'wallet-recipe-address-hidden-blocked',
  'wallet-recipe-address-window-blocked',
  'wallet-recipe-address-section-blocked',
  'wallet-recipe-address-focus-blocked',
  'wallet-recipe-address-route-blocked',
  'wallet-recipe-address-ticker-blocked',
  'wallet-recipe-address-busy-blocked',
  'wallet-recipe-control-entrance-pending',
  'wallet-recipe-control-layout-pending',
  'wallet-recipe-control-not-reachable',
  'wallet-recipe-startup-key-unconfirmed',
};

/// Only an observed original guard can select a more specific fixed refusal.
String walletRecipeControlFailure(Object? gate) => switch (gate) {
  'widget' => 'wallet-recipe-control-widget-disabled',
  'entrance' => 'wallet-recipe-control-entrance-pending',
  'layout' => 'wallet-recipe-control-layout-pending',
  'hit_test' => 'wallet-recipe-control-not-reachable',
  _ => 'wallet-recipe-control-disabled',
};

/// Only the disabled Add address control may use its cached original predicate.
String walletRecipeAddressFailure(Object? gate) => switch (gate) {
  'backend' => 'wallet-recipe-address-backend-blocked',
  'mounted' => 'wallet-recipe-address-mounted-blocked',
  'hidden' => 'wallet-recipe-address-hidden-blocked',
  'window' => 'wallet-recipe-address-window-blocked',
  'section' => 'wallet-recipe-address-section-blocked',
  'focus' => 'wallet-recipe-address-focus-blocked',
  'route' => 'wallet-recipe-address-route-blocked',
  'ticker' => 'wallet-recipe-address-ticker-blocked',
  'busy' => 'wallet-recipe-address-busy-blocked',
  _ => 'wallet-recipe-control-widget-disabled',
};

/// Entry types and failure families disclose no displayed text or error detail.
const Set<String> walletRecipeEntryPhases = <String>{
  'startup', 'welcome', 'import', 'ready', 'node', 'error', 'unknown',
  'startup-before-initialization', 'startup-initialization-started',
  'startup-initialization-refused', 'startup-filesystem-error',
  'startup-platform-error', 'startup-hive-error', 'startup-other-error',
};

/// This records only the original startup decision, never a key or payload.
const Set<String> walletRecipeStartupHandoffs = <String>{
  'observing', 'key-sent', 'key-confirmed',
  'natural-welcome', 'natural-initialization',
};

/// Read-only states of the original film disclose no asset or frame payload.
const Set<String> walletRecipeStartupFilmStates = <String>{
  'opening', 'first-frame-pending', 'frame-visible', 'last-frame', 'ended',
  'frames-suspended', 'ticker-muted',
  'skip-ticker-stopped', 'skip-display-pending', 'skip-next-pending',
  'skip-previous-pending', 'skip-asset-pending', 'skip-codec-pending',
  'skip-frame-pending', 'skip-resize-pending',
  'skip-first-frame-pending', 'skip-middle-frame-pending',
  'skip-last-frame-pending',
  'skip-display-wait-pending', 'skip-dispose-pending',
};

/// Values, endpoints, exception text and reply details are never projected.
Map<String, String> walletRecipeDiagnostic(
  Map<String, Object?> command,
  Object? reason, {
  Object? entryPhase,
}) {
  final Object? action = command['action'];
  final Object? key = command['key'];
  String control = 'unknown';
  if (key == null) {
    control = 'none';
  } else if (key is String) {
    if (walletRecipeControls.contains(key)) {
      control = key;
    } else if (key.startsWith('node_settings_select_')) {
      control = 'node_settings_select';
    } else if (key.startsWith('addresses_select_')) {
      control = 'addresses_select';
    }
  }
  return Map<String, String>.unmodifiable(<String, String>{
    'action': action is String && walletRecipeActions.contains(action)
        ? action
        : 'unknown',
    'control': control,
    'reason': reason is String && walletRecipeFailureCodes.contains(reason)
        ? reason
        : 'wallet-recipe-refused',
    if (entryPhase is String && walletRecipeEntryPhases.contains(entryPhase))
      'entry': entryPhase,
  });
}

/// Recheck even a typed exception before adding its labels to a CI marker.
Map<String, String>? walletRecipePublicDiagnostic(Object? value) {
  const Set<String> fields = <String>{
    'action', 'control', 'reason', 'entry', 'startup', 'film',
  };
  if (value is! Map<Object?, Object?> ||
      value.length < 3 || value.length > 6 ||
      value.keys.any((Object? key) => !fields.contains(key))) {
    return null;
  }
  final Object? action = value['action'];
  final Object? control = value['control'];
  final Object? reason = value['reason'];
  final Object? entry = value['entry'];
  final Object? startup = value['startup'];
  final Object? film = value['film'];
  if (action is! String ||
      control is! String ||
      reason is! String ||
      !walletRecipeActions.contains(action) ||
      !walletRecipeControls.contains(control) ||
      !walletRecipeFailureCodes.contains(reason)) {
    return null;
  }
  if (value.containsKey('entry') &&
      (entry is! String || !walletRecipeEntryPhases.contains(entry))) {
    return null;
  }
  if (value.containsKey('startup') &&
      (startup is! String || !walletRecipeStartupHandoffs.contains(startup))) {
    return null;
  }
  if (value.containsKey('film') &&
      (film is! String || !walletRecipeStartupFilmStates.contains(film))) {
    return null;
  }
  final String? phase = entry is String ? entry : null;
  final String? handoff = startup is String ? startup : null;
  final String? filmState = film is String ? film : null;
  return Map<String, String>.unmodifiable(<String, String>{
    'action': action, 'control': control, 'reason': reason,
    'entry': ?phase,
    'startup': ?handoff,
    'film': ?filmState,
  });
}
