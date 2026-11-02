/// Fixed, public labels for original lab-send refusal; no raw SDK/UI data.
const Set<String> labSendFailurePhases = <String>{
  'admission',
  'profile',
  'profile_owner',
  'profile_apis',
  'profile_transports',
  'profile_paths',
  'profile_members',
  'profile_layout',
  'profile_wallet',
  'profile_terms',
  'journal',
  'transfer',
  'form',
  'transport',
  'sender',
  'token',
  'recipient',
  'amount',
  'review_open',
  'review',
  'preflight',
  'accept',
  'confirmation',
  'receipt',
};

/// Only source-defined original-send reasons can cross the CI boundary.
const Set<String> labSendFailureReasons = <String>{
  'advancing-momentum-required',
  'ambiguous-original-publication',
  'earlier-original-unresolved',
  'earlier-seed-attempt-held',
  'exact-chain-321-lab-required',
  'exact-confirmation-or-effect-pending',
  'exact-confirmation-pending',
  'exact-original-lab-transports-required',
  'exact-original-receipt-mismatch',
  'explicit-lab-origins-required',
  'external-lab-counterparty-required',
  'fixed-original-lab-send-required',
  'funded-index-one-required',
  'funded-selected-index-required',
  'invalid-lab-frontier',
  'invalid-original-hash',
  'isolated-unlocked-profile-required',
  'lab-endpoints-disagree',
  'lab-frontier-regressed',
  'lab-http-frontier-incomplete',
  'lab-http-response-refused',
  'lab-http-response-too-large',
  'lab-http-rpc-refused',
  'original-attempt-held',
  'original-context-changed',
  'original-hash-changed',
  'original-lab-control-changed',
  'original-lab-control-unsettled',
  'original-lab-send-context-changed',
  'original-lab-send-transport-required',
  'original-lab-send-ui-or-read-failed',
  'original-lab-sender-choice-required',
  'original-lab-sender-choice-ambiguous',
  'original-lab-sender-choice-missing',
  'original-lab-sender-choice-unsettled',
  'original-lab-sender-form-choice-missing',
  'original-lab-sender-menu-missing',
  'original-lab-sender-menu-choice-missing',
  'original-outcome-unknown',
  'original-publication-replaced',
  'original-send-form-changed',
  'original-send-form-required',
  'original-send-review-already-captured',
  'original-send-review-changed',
  'original-send-review-center-changed',
  'original-send-review-button-changed',
  'original-send-review-dialog-changed',
  'original-send-review-intent-changed',
  'original-send-review-draft-changed',
  'original-send-review-required',
  'original-transfer-attempt-held',
  'original-transfer-review-mismatch',
  'original-transfer-review-required',
  'original-transfer-witness-required',
  'original-ui-control-changed',
  'owned-isolated-profile-required',
  'receipt-shape-refused',
  'recipe-prerequisite-missing',
  'seed-journal-held',
  'unknown-recipe',
  'unlocked-wallet-required',
};

/// Passive original-request facts, without any publication or receipt claim.
const Set<String> labSendFailureOriginalStates = <String>{
  'not_started',
  'pending',
  'sender_failed',
  'witness_invalid',
  'owner_revoked',
  'detached',
  'result_observed',
};

/// The already-retained display error, never a raw error or original cause.
const Set<String> labSendFailureDisplayErrors = <String>{
  'node_not_synced',
  'generic_failure',
  'other',
};

/// Closed results of completed reads, without a positive confirmation.
const Set<String> labSendFailureConfirmationStates = <String>{
  'absent',
  'unconfirmed',
};

/// Numeric fields are finite original lab observations, never private input.
const Set<String> labSendFailureFrontierNumbers = <String>{
  'ws_first_height',
  'ws_last_height',
  'ws_first_timestamp',
  'ws_last_timestamp',
  'http_first_height',
  'http_last_height',
  'http_first_timestamp',
  'http_last_timestamp',
};

Map<String, Object>? _frontierObservation(Object? value) {
  if (value is! Map || value.length != 11 ||
      !value.keys.toSet().containsAll(<String>{
        ...labSendFailureFrontierNumbers,
        'polls', 'ws_hash_changed', 'http_hash_changed',
      }) || value['polls'] is! int || value['polls'] != 6 ||
      value['ws_hash_changed'] is! bool ||
      value['http_hash_changed'] is! bool ||
      labSendFailureFrontierNumbers.any((String key) =>
          value[key] is! int || (value[key] as int) <= 0 ||
          (value[key] as int) > 9007199254740991)) {
    return null;
  }
  bool advances(String endpoint) =>
      (value['${endpoint}_last_height'] as int) >
          (value['${endpoint}_first_height'] as int) &&
      (value['${endpoint}_last_timestamp'] as int) >
          (value['${endpoint}_first_timestamp'] as int) &&
      value['${endpoint}_hash_changed'] == true;
  for (final String endpoint in <String>['ws', 'http']) {
    final int firstHeight = value['${endpoint}_first_height'] as int;
    final int lastHeight = value['${endpoint}_last_height'] as int;
    if (lastHeight < firstHeight || lastHeight == firstHeight &&
        (value['${endpoint}_last_timestamp'] !=
            value['${endpoint}_first_timestamp'] ||
         value['${endpoint}_hash_changed'] != false)) {
      return null;
    }
  }
  if (advances('ws') && advances('http')) return null;
  return Map<String, Object>.unmodifiable(<String, Object>{
    'polls': 6,
    for (final String key in labSendFailureFrontierNumbers)
      key: value[key] as int,
    'ws_hash_changed': value['ws_hash_changed'] as bool,
    'http_hash_changed': value['http_hash_changed'] as bool,
  });
}

Map<String, Object>? _confirmationObservation(Object? value) {
  if (value is! Map || value.length != 4 ||
      !value.keys.toSet().containsAll(<String>{
        'polls', 'absent', 'unconfirmed', 'last',
      }) || value['polls'] is! int || value['polls'] != 18 ||
      value['absent'] is! int || value['unconfirmed'] is! int ||
      value['last'] is! String ||
      !labSendFailureConfirmationStates.contains(value['last'])) {
    return null;
  }
  final int absent = value['absent'] as int;
  final int unconfirmed = value['unconfirmed'] as int;
  final String last = value['last'] as String;
  if (absent < 0 || absent > 18 || unconfirmed < 0 || unconfirmed > 18 ||
      absent + unconfirmed != 18 ||
      (last == 'absent' ? absent : unconfirmed) == 0) {
    return null;
  }
  return Map<String, Object>.unmodifiable(<String, Object>{
    'polls': 18, 'absent': absent, 'unconfirmed': unconfirmed, 'last': last,
  });
}

/// Returns an independent immutable projection, or refuses the whole payload.
Map<String, Object>? labSendPublicDiagnostic(Object? value) {
  if (value is! Map || value.length < 2 || value.length > 4 ||
      !value.keys.toSet().containsAll(<String>{'phase', 'reason'}) ||
      !labSendFailurePhases.contains(value['phase']) ||
      !labSendFailureReasons.contains(value['reason'])) {
    return null;
  }
  final bool frontier = value.containsKey('frontier');
  final Map<String, Object>? observation = frontier
      ? _frontierObservation(value['frontier']) : null;
  if (frontier && (value.length != 3 || value['phase'] != 'preflight' ||
      value['reason'] != 'advancing-momentum-required' ||
      observation == null)) {
    return null;
  }
  final bool confirmation = value.containsKey('confirmation');
  final Map<String, Object>? confirmationObservation = confirmation
      ? _confirmationObservation(value['confirmation']) : null;
  if (confirmation && (value.length != 3 ||
      value['phase'] != 'confirmation' ||
      value['reason'] != 'exact-confirmation-pending' ||
      confirmationObservation == null)) {
    return null;
  }
  final bool original = value.containsKey('original');
  if (original && (value['phase'] != 'confirmation' ||
      value['reason'] != 'original-outcome-unknown' ||
      value['original'] is! String ||
      !labSendFailureOriginalStates.contains(value['original']))) {
    return null;
  }
  final bool displayError = value.containsKey('display_error');
  if (displayError && (!original || value.length != 4 ||
      value['original'] != 'sender_failed' ||
      value['display_error'] is! String ||
      !labSendFailureDisplayErrors.contains(value['display_error']))) {
    return null;
  }
  if (value.length != 2 + (original ? 1 : 0) + (frontier ? 1 : 0) +
      (confirmation ? 1 : 0) + (displayError ? 1 : 0)) {
    return null;
  }
  return Map<String, Object>.unmodifiable(<String, Object>{
    'phase': value['phase'] as String, 'reason': value['reason'] as String,
    if (original) 'original': value['original'] as String,
    if (displayError) 'display_error': value['display_error'] as String,
    if (frontier) 'frontier': observation!,
    if (confirmation) 'confirmation': confirmationObservation!,
  });
}

/// Carries only the finite diagnostic through the private controller boundary.
final class LabSendDiagnosticFailure implements Exception {
  /// Discards any malformed or private response rather than exporting it.
  LabSendDiagnosticFailure(Object? value)
    : diagnostic = labSendPublicDiagnostic(value);

  /// A copied, validated label pair; never the original HTTP response.
  final Map<String, Object>? diagnostic;

  @override
  String toString() => 'Original lab send refused';
}
