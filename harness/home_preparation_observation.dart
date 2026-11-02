/// Original Home preparation boundaries; these labels perform no operation.
enum HomePreparationStep {
  initialState, initialReadiness, resolveTarget,
  gotoState, gotoTarget, gotoTap, gotoWait,
  railState, railReadiness, railTogglePresence, railLabelPresence,
  railToggle, railWait, finalState, finalReadiness,
}

/// Closed labels from the already returned original Home tap reply.
enum HomeTapReply {
  targetMissing, targetDisabled, targetCovered, viewAmbiguous, unknown,
}

/// Classifies only four literal original messages; private text is not copied.
HomeTapReply classifyHomeTapReply(Object? value) => switch (value) {
  'nothing matches' => HomeTapReply.targetMissing,
  'disabled' => HomeTapReply.targetDisabled,
  'covered by something else' => HomeTapReply.targetCovered,
  'expected one owned Flutter view' => HomeTapReply.viewAmbiguous,
  _ => HomeTapReply.unknown,
};

/// Receives only an already entered original boundary and original state reply.
/// It is optional and never changes the original caller's command or wait.
typedef HomePreparationObserver = void Function(HomePreparationStep step, {
  Map<String, dynamic>? state, String? target,
});

const Set<String> _stateSteps = <String>{
  'initialReadiness', 'gotoTarget', 'gotoWait',
  'railReadiness', 'finalReadiness',
};
const Set<String> _flags = <String>{'yes', 'no', 'unknown'};
const Set<String> _tabs = <String>{
  'home', 'dashboard', 'lock', 'other', 'unknown',
};

String _flag(Object? value) => value is bool
    ? (value ? 'yes' : 'no') : 'unknown';

String _tab(Object? value) => switch (value) {
  'home' => 'home', 'dashboard' => 'dashboard', 'lock' => 'lock',
  String() => 'other', _ => 'unknown',
};

/// An immutable closed projection, without private state or action authority.
Map<String, Object>? homePreparationProjection(Object? value) {
  const Set<String> fields = <String>{'stage', 'state', 'target', 'reply'};
  if (value is! Map || !value.containsKey('stage') || value.keys.any(
    (Object? key) => key is! String || !fields.contains(key),
  )) {
    return null;
  }
  final List<String> stages = HomePreparationStep.values.map(
    (HomePreparationStep step) => step.name,
  ).toList(growable: false);
  final Object? stage = value['stage'];
  final Object? target = value['target'];
  if (stage is! String || !stages.contains(stage) ||
      value.containsKey('target') &&
          (target is! String ||
              !<String>{'home', 'dashboard'}.contains(target) ||
              stages.indexOf(stage) <
                  stages.indexOf(HomePreparationStep.resolveTarget.name))) {
    return null;
  }
  Map<String, Object>? state;
  if (value.containsKey('state')) {
    final Object? raw = value['state'];
    const Set<String> stateFields = <String>{
      'at', 'booted', 'unlocked', 'initialized', 'tab',
    };
    if (raw is! Map || raw.length != stateFields.length ||
        stateFields.any((String key) => !raw.containsKey(key))) {
      return null;
    }
    final Object? at = raw['at'];
    if (at is! String || !_stateSteps.contains(at) ||
        stages.indexOf(at) > stages.indexOf(stage) ||
        <String>['booted', 'unlocked', 'initialized'].any(
          (String key) => raw[key] is! String || !_flags.contains(raw[key]),
        ) || raw['tab'] is! String || !_tabs.contains(raw['tab'])) {
      return null;
    }
    state = Map<String, Object>.unmodifiable(<String, Object>{
      for (final String key in stateFields) key: raw[key] as String,
    });
  }
  final Object? reply = value['reply'];
  if (value.containsKey('reply') &&
      (stage != HomePreparationStep.gotoTap.name || target == null ||
          state == null || state['at'] != HomePreparationStep.gotoTarget.name ||
          reply is! String || !HomeTapReply.values.any(
            (HomeTapReply code) => code.name == reply,
          ))) {
    return null;
  }
  return Map<String, Object>.unmodifiable(<String, Object>{
    'stage': stage,
    if (target != null) 'target': target as String,
    'state': ?state,
    if (reply != null) 'reply': reply as String,
  });
}

/// Passive finite state only; owns no I/O, callback, timer or operation.
final class HomePreparationTrace {
  /// Starts without an observation, independently of private input data.
  HomePreparationTrace();

  HomePreparationStep? _stage;
  String? _target;
  Map<String, Object>? _state;

  /// Clears the previous original boundary without acting on it.
  void clear() {
    _stage = null;
    _target = null;
    _state = null;
  }

  /// Copies only finite flags from an already completed original state read.
  void observe(HomePreparationStep step, {
    Map<String, dynamic>? state, String? target,
  }) {
    _stage = step;
    if (target != null) {
      _target = target == 'home' || target == 'dashboard' ? target : null;
    }
    if (state != null) {
      _state = Map<String, Object>.unmodifiable(<String, Object>{
        'at': step.name, 'booted': _flag(state['booted']),
        'unlocked': _flag(state['walletUnlocked']),
        'initialized': _flag(state['walletInitCompleted']),
        'tab': _tab(state['tab']),
      });
    }
  }

  /// Adds only an already received original reply at the known tap boundary.
  /// It does not query, dispatch, retry or change the stored observation.
  Map<String, Object>? failureSnapshot(HomeTapReply? reply) {
    final Map<String, Object>? original = snapshot;
    if (original == null || reply == null ||
        _stage != HomePreparationStep.gotoTap) {
      return original;
    }
    return homePreparationProjection(<String, Object>{
      ...original, 'reply': reply.name,
    }) ?? original;
  }

  /// Freezes the current original observation; it does not establish Home.
  Map<String, Object>? get snapshot {
    final HomePreparationStep? stage = _stage;
    if (stage == null) return null;
    return homePreparationProjection(<String, Object>{
      'stage': stage.name,
      'target': ?_target,
      'state': ?_state,
    });
  }
}
