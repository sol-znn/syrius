import 'package:flutter_test/flutter_test.dart';

import '../../harness/lab_send_failure.dart';

class _PrivateValue {
  @override
  String toString() => throw StateError('Private values must not be formatted');
}

Map<String, Object> _labels() => <String, Object>{
  'phase': 'profile', 'reason': 'owned-isolated-profile-required',
};

Map<String, Object> _frontier() => <String, Object>{
  'polls': 6,
  'ws_first_height': 10, 'ws_last_height': 17,
  'ws_first_timestamp': 100, 'ws_last_timestamp': 107,
  'ws_hash_changed': true,
  'http_first_height': 10, 'http_last_height': 10,
  'http_first_timestamp': 100, 'http_last_timestamp': 100,
  'http_hash_changed': false,
};

Map<String, Object> _stalled(Map<String, Object> frontier) => <String, Object>{
  'phase': 'preflight', 'reason': 'advancing-momentum-required',
  'frontier': frontier,
};

void main() {
  Map<String, Object> pending(Map<String, Object> counts) =>
      <String, Object>{
        'phase': 'confirmation', 'reason': 'exact-confirmation-pending',
        'confirmation': counts,
      };
  Map<String, Object> counts() => <String, Object>{
    'polls': 18, 'absent': 7, 'unconfirmed': 11, 'last': 'unconfirmed',
  };

  test('completed confirmation counts are independently immutable', () {
    for (final int absent in <int>[0, 7, 18]) {
      final Map<String, Object> input = counts()
        ..['absent'] = absent
        ..['unconfirmed'] = 18 - absent
        ..['last'] = absent == 18 ? 'absent' : 'unconfirmed';
      final Map<String, Object> expected = Map<String, Object>.of(input);
      final Map<String, Object> result =
          labSendPublicDiagnostic(pending(input))!;
      final Map<String, Object> observed =
          result['confirmation']! as Map<String, Object>;
      input['polls'] = 0;
      expect(observed, expected);
      expect(() => observed['polls'] = 0, throwsUnsupportedError);
      expect(() => result['confirmation'] = counts(), throwsUnsupportedError);
      expect(LabSendDiagnosticFailure(result).diagnostic, result);
    }
  });

  test('confirmation counts reject private coercion and impossible totals', () {
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'polls': true},
      <String, Object?>{'polls': 17},
      <String, Object?>{'absent': 7.0},
      <String, Object?>{'absent': -1},
      <String, Object?>{'unconfirmed': 19},
      <String, Object?>{'absent': 8},
      <String, Object?>{'last': _PrivateValue()},
      <String, Object?>{'last': 'confirmed'},
      <String, Object?>{'last': 'absent\n'},
      <String, Object?>{'hash': 'private'},
      <String, Object?>{'absent': 18, 'unconfirmed': 0},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object?>{
        ...pending(counts()), 'confirmation': <String, Object?>{
          ...counts(), ...change,
        },
      }), isNull);
    }
    for (final String key in counts().keys) {
      expect(labSendPublicDiagnostic(pending(counts()..remove(key))), isNull);
    }
  });

  test('confirmation exhaustion is scoped and legacy absence stays absent',
      () {
    for (final Map<String, Object> change in <Map<String, Object>>[
      <String, Object>{'phase': 'preflight'},
      <String, Object>{'reason': 'original-outcome-unknown'},
      <String, Object>{'original': 'result_observed'},
      <String, Object>{'frontier': _frontier()},
      <String, Object>{'confirmed': true},
      <String, Object>{'retry': true},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object>{
        ...pending(counts()), ...change,
      }), isNull);
    }
    final Map<String, Object> legacy = <String, Object>{
      'phase': 'confirmation', 'reason': 'exact-confirmation-pending',
    };
    expect(labSendPublicDiagnostic(legacy), legacy);
    expect(labSendPublicDiagnostic(legacy)!.containsKey('confirmation'),
        isFalse);
  });

  test('stalled frontier facts are independent immutable original read values',
      () {
    final Map<String, Object> input = _frontier();
    final Map<String, Object> value = _stalled(input);
    final Map<String, Object> result = labSendPublicDiagnostic(value)!;
    final Map<String, Object> facts =
        result['frontier']! as Map<String, Object>;
    input['http_last_height'] = 50;
    expect(facts, _frontier());
    expect(() => facts['polls'] = 0, throwsUnsupportedError);
    expect(() => result['phase'] = 'accept', throwsUnsupportedError);
    expect(LabSendDiagnosticFailure(result).diagnostic, result);
  });

  test(
      'frontier facts reject coercion private extras and impossible exhaustion',
      () {
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'polls': true},
      <String, Object?>{'polls': 5},
      <String, Object?>{'ws_last_height': 0},
      <String, Object?>{'ws_last_height': 9007199254740992},
      <String, Object?>{'ws_last_height': 17.0},
      <String, Object?>{'http_hash_changed': 0},
      <String, Object?>{'ws_first_timestamp': _PrivateValue()},
      <String, Object?>{'hash': 'private'},
      <String, Object?>{'http_last_height': 9},
      <String, Object?>{'http_last_timestamp': 101},
      <String, Object?>{'http_hash_changed': true},
      <String, Object?>{'http_last_height': 17,
        'http_last_timestamp': 107, 'http_hash_changed': true},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object?>{
        ..._stalled(_frontier()), 'frontier': <String, Object?>{
          ..._frontier(), ...change,
        },
      }), isNull);
    }
    final Map<String, Object> missing = _frontier()..remove('polls');
    expect(labSendPublicDiagnostic(_stalled(missing)), isNull);
  });

  test('frontier facts belong only to the exhausted original preflight', () {
    for (final Map<String, Object> change in <Map<String, Object>>[
      <String, Object>{'phase': 'confirmation'},
      <String, Object>{'reason': 'original-outcome-unknown'},
      <String, Object>{'original': 'pending'},
      <String, Object>{'confirmed': true},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object>{
        ..._stalled(_frontier()), ...change,
      }), isNull);
    }
    expect(labSendPublicDiagnostic(<String, Object>{
      'phase': 'preflight', 'reason': 'advancing-momentum-required',
    }), isNotNull);
  });
  test('review refusals expose only the fixed failed binding label', () {
    for (final String part in <String>[
      'center', 'button', 'dialog', 'intent', 'draft',
    ]) {
      final Map<String, Object> value = <String, Object>{
        'phase': 'preflight', 'reason': 'original-send-review-$part-changed',
      };
      expect(labSendPublicDiagnostic(value), value);
      expect(labSendPublicDiagnostic(<String, Object>{
        ...value, part: 'private',
      }), isNull);
    }
  });

  test('every fixed phase preserves the exact source-defined reason', () {
    for (final String phase in labSendFailurePhases) {
      final Map<String, Object> value = _labels()..['phase'] = phase;
      expect(labSendPublicDiagnostic(value), value);
    }
  });

  test('unknown labels and nonstring values are never projected', () {
    for (final Map<String, Object> change in <Map<String, Object>>[
      <String, Object>{'phase': 'private-path'},
      <String, Object>{'reason': 'private-server-message'},
      <String, Object>{'phase': 1},
      <String, Object>{'reason': false},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object>{..._labels(), ...change}),
        isNull);
    }
  });

  test('extra identity values or success claims refuse the whole payload', () {
    for (final String key in <String>[
      'hash', 'address', 'walletPath', 'requestId', 'confirmed', 'retry',
    ]) {
      expect(labSendPublicDiagnostic(<String, Object>{
        ..._labels(), key: 'private',
      }), isNull);
    }
    expect(labSendPublicDiagnostic(<String, Object>{'phase': 'profile'}),
      isNull);
  });

  test('the returned diagnostic is independent and immutable', () {
    final Map<String, Object> input = _labels();
    final Map<String, Object> result = labSendPublicDiagnostic(input)!;
    input['phase'] = 'private';
    expect(result, _labels());
    expect(() => result['phase'] = 'confirmation', throwsUnsupportedError);
  });

  test('the controller failure retains only its validated copied labels', () {
    final Map<String, Object> input = _labels();
    final LabSendDiagnosticFailure failure = LabSendDiagnosticFailure(input);
    input['reason'] = 'private';
    expect(failure.diagnostic, _labels());
    expect(failure.toString(), 'Original lab send refused');
    expect(failure.toString(), isNot(contains('private')));
  });

  test('opaque errors are discarded without calling their formatter', () {
    final _PrivateValue private = _PrivateValue();
    expect(labSendPublicDiagnostic(private), isNull);
    expect(labSendPublicDiagnostic(<String, Object>{
      'phase': private, 'reason': private,
    }), isNull);
    final LabSendDiagnosticFailure failure = LabSendDiagnosticFailure(private);
    expect(failure.diagnostic, isNull);
    expect(failure.toString(), 'Original lab send refused');
  });

  test('original state is optional, copied and scoped to unknown confirmation',
      () {
    for (final String state in labSendFailureOriginalStates) {
      final Map<String, Object> input = <String, Object>{
        'phase': 'confirmation', 'reason': 'original-outcome-unknown',
        'original': state,
      };
      final Map<String, Object> result = labSendPublicDiagnostic(input)!;
      input['original'] = 'private';
      expect(result['original'], state);
      expect(() => result['original'] = 'pending', throwsUnsupportedError);
      final LabSendDiagnosticFailure failure = LabSendDiagnosticFailure(result);
      expect(failure.diagnostic, result);
      expect(failure.toString(), 'Original lab send refused');
    }
    expect(labSendPublicDiagnostic(_labels()), _labels());
  });

  test('unknown, private or misplaced original state refuses the whole payload',
      () {
    final Map<String, Object?> value = <String, Object?>{
      'phase': 'confirmation', 'reason': 'original-outcome-unknown',
      'original': 'not_started',
    };
    for (final Object? state in <Object?>[
      null, true, 1, '', 'private-path', 'pending\n', _PrivateValue(),
    ]) {
      expect(labSendPublicDiagnostic(<String, Object?>{
        ...value, 'original': state,
      }), isNull);
    }
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'phase': 'admission'},
      <String, Object?>{'reason': 'exact-confirmation-pending'},
      <String, Object?>{'hash': 'private'},
      <String, Object?>{'confirmed': true},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object?>{
        ...value, ...change,
      }), isNull);
    }
  });

  test('display labels are copied only for the same failed original scope', () {
    for (final String kind in labSendFailureDisplayErrors) {
      final Map<String, Object> input = <String, Object>{
        'phase': 'confirmation', 'reason': 'original-outcome-unknown',
        'original': 'sender_failed', 'display_error': kind,
      };
      final Map<String, Object> result = labSendPublicDiagnostic(input)!;
      input['display_error'] = 'private';
      expect(result['display_error'], kind);
      expect(result['original'], 'sender_failed');
      expect(() => result['display_error'] = 'other', throwsUnsupportedError);
      expect(LabSendDiagnosticFailure(result).diagnostic, result);
    }
  });

  test('private display errors or misplaced labels refuse the whole payload',
      () {
    final Map<String, Object?> input = <String, Object?>{
      'phase': 'confirmation', 'reason': 'original-outcome-unknown',
      'original': 'sender_failed', 'display_error': 'node_not_synced',
    };
    for (final Object? value in <Object?>[
      null, true, 1, '', 'private', 'node_not_synced\n', _PrivateValue(),
    ]) {
      expect(labSendPublicDiagnostic(<String, Object?>{
        ...input, 'display_error': value,
      }), isNull);
    }
    for (final String state in labSendFailureOriginalStates) {
      if (state == 'sender_failed') continue;
      expect(labSendPublicDiagnostic(<String, Object?>{
        ...input, 'original': state,
      }), isNull);
    }
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'phase': 'accept'},
      <String, Object?>{'reason': 'exact-confirmation-pending'},
      <String, Object?>{'hash': 'private'},
      <String, Object?>{'confirmed': true},
    ]) {
      expect(labSendPublicDiagnostic(<String, Object?>{
        ...input, ...change,
      }), isNull);
    }
    input.remove('original');
    expect(labSendPublicDiagnostic(input), isNull);
  });
}
