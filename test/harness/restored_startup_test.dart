import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/ci_wallet_reopen.dart' as entry;
import '../../harness/bin/harness.dart' as cli;
import '../../harness/bin/wallet_recipe.dart';
import '../../harness/lock_view_observation.dart';

class _Unformattable implements Exception {
  @override
  String toString() => throw StateError('The error must not be formatted');
}

class _UnlockInstance extends cli.Instance {
  _UnlockInstance(this.refusal, {this.lockView})
      : super('synthetic-restored-unlock');

  final Object? lockView;

  final String? refusal;
  final List<String> commands = <String>[];
  int observations = 0;

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final String name = command['cmd']! as String;
    commands.add(name);
    bool refused = false;
    if (name == 'lock-view') {
      final Object? original = lockView;
      if (original is! Map<String, dynamic>) throw _Unformattable();
      expect(command['action'], anyOf('bind', 'observe'));
      expect(command.containsKey('value'), isFalse);
      return Map<String, dynamic>.from(original);
    }
    if (name == 'state') {
      observations++;
      refused = observations == 1
          ? refusal == 'UNLOCK_STATE_REFUSED'
          : refusal == 'UNLOCK_WAIT_REFUSED' ||
              refusal == 'UNLOCK_FAILURE_TREE_REFUSED';
      if (!refused) {
        return <String, dynamic>{
          'ok': true,
          'tab': refusal == 'UNLOCK_LOCK_REQUIRED'
              ? 'startup' : observations == 1 ? 'lock' : 'dashboard',
          'walletUnlocked': observations > 1,
        };
      }
    } else if (name == 'wait') {
      expect(command['key'], 'wallet_password_field');
      expect(command['kind'], 'field');
      expect(command['ready'], isTrue);
      expect(command['timeoutMs'], 5000);
      expect(command.containsKey('value'), isFalse);
      refused = refusal == 'UNLOCK_FIELD_READY_REFUSED';
    } else if (name == 'type') {
      expect(command['key'], 'wallet_password_field');
      expect(command['value'], 'synthetic-private-password');
      refused = refusal == 'UNLOCK_TYPE_REFUSED';
    } else if (name == 'tap') {
      expect(command['key'], 'wallet_unlock_button');
      refused = refusal == 'UNLOCK_TAP_REFUSED';
    } else if (name == 'tree') {
      expect(command['kind'], 'text');
      refused = refusal == 'UNLOCK_FAILURE_TREE_REFUSED';
      if (!refused) return <String, dynamic>{'ok': true, 'nodes': <Object>[]};
    } else {
      throw StateError('Unexpected original unlock operation');
    }
    return <String, dynamic>{
      'ok': !refused,
      if (refused) 'error': 'synthetic-private-error',
      if (refused) 'detail': <String, String>{'path': 'synthetic-private-path'},
      if (refused) 'stack': 'synthetic-private-stack',
    };
  }
}

Object _typeError() {
  final Object value = Object();
  try {
    return value as int;
  } on Object catch (error) {
    return error;
  }
}

Future<Map<String, Object?>> _failure(
  Future<void> Function() action,
  String phase,
) async {
  try {
    await action();
  } on Object catch (error) {
    final Map<String, Object?>? result = entry.restoredChildFailure(
      phase,
      error,
    );
    expect(result, isNotNull);
    return result!;
  }
  throw StateError('The original operation did not refuse');
}

Map<String, dynamic> _view({
  String tab = 'lock', String phase = 'unknown', String? film,
  bool hint = false,
}) => <String, dynamic>{
  'ok': true, 'harnessMode': 'wallet', 'booted': true,
  'owner': 1, 'revision': 1, 'hasError': false,
  'tab': tab, 'entryPhase': phase,
  'startupFilmState': ?film,
  'controls': <Map<String, Object>>[
    if (hint) <String, Object>{'key': 'launch_skip_hint', 'enabled': true},
  ],
};

void main() {
  Map<String, dynamic> ready() => <String, dynamic>{
    'walletUnlocked': true, 'walletInitCompleted': true,
    'embeddedNode': false, 'ws': 'running',
    'node': 'ws://127.0.0.1:45998', 'nodeSelectionSaved': true,
    'nodeTransitionPending': false, 'chainId': 321,
    'signingChainId': 321, 'savedSigningChainId': 321,
  };

  test('restored readiness needs initialized transport and saved lab policy',
      () {
    expect(entry.restoredWalletReady(ready()), isTrue);
    for (final String key in ready().keys) {
      final Map<String, dynamic> value = ready()..remove(key);
      expect(entry.restoredWalletReady(value), isFalse, reason: key);
    }
  });

  test('unlocked state cannot hide pending or foreign restored policy', () {
    for (final Map<String, Object> change in <Map<String, Object>>[
      <String, Object>{'chainId': 321.0},
      <String, Object>{'signingChainId': 1},
      <String, Object>{'savedSigningChainId': 321.0},
      <String, Object>{'ws': 'uninitialized'},
      <String, Object>{'nodeSelectionSaved': false},
      <String, Object>{'nodeTransitionPending': true},
    ]) {
      expect(entry.restoredWalletReady(ready()..addAll(change)), isFalse);
    }
  });

  test('a settled restored lock uses no input', () async {
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
    final WalletRecipe driver = WalletRecipe(
      send: (Map<String, Object?> command, Duration _) async {
        commands.add(command);
        return _view();
      },
    );
    await driver.settleRestoredStartup();
    expect(commands, hasLength(1));
    expect(commands.single['action'], 'observe');
  });

  test('the original startup hint gets one ordinary key before lock', () async {
    bool skipped = false;
    final List<Map<String, Object?>> inputs = <Map<String, Object?>>[];
    final WalletRecipe driver = WalletRecipe(
      send: (Map<String, Object?> command, Duration _) async {
        if (command['action'] == 'observe') {
          return skipped ? _view() : _view(
            phase: 'startup-before-initialization', film: 'opening',
            hint: true);
        }
        inputs.add(command);
        skipped = true;
        return <String, dynamic>{'ok': true, 'acted': true};
      },
      wait: (Duration _) async {},
    );
    await driver.settleRestoredStartup();
    expect(inputs, hasLength(1));
    expect(inputs.single['action'], 'key');
    expect(inputs.single['key'], 'launch_skip_hint');
    expect(inputs.single.containsKey('value'), isFalse);
  });

  test('natural initialization reaches lock without any key', () async {
    int observations = 0;
    final List<Map<String, Object?>> inputs = <Map<String, Object?>>[];
    final WalletRecipe driver = WalletRecipe(
      send: (Map<String, Object?> command, Duration _) async {
        if (command['action'] != 'observe') inputs.add(command);
        return observations++ < 2 ? _view(
          phase: 'startup-initialization-started', film: 'ended') : _view();
      },
      wait: (Duration _) async {},
    );
    await driver.settleRestoredStartup();
    expect(inputs, isEmpty);
    expect(observations, 3);
  });

  test('a natural lock racing the hint observation does not receive a key',
      () async {
    int observations = 0;
    final List<Map<String, Object?>> inputs = <Map<String, Object?>>[];
    final WalletRecipe driver = WalletRecipe(
      send: (Map<String, Object?> command, Duration _) async {
        if (command['action'] != 'observe') inputs.add(command);
        return observations++ == 0 ? _view(
          phase: 'startup-before-initialization', film: 'opening', hint: true)
          : _view();
      },
      wait: (Duration _) async {},
    );
    await driver.settleRestoredStartup();
    expect(inputs, isEmpty);
  });

  test('Welcome or a failed initialization refuses before private input',
      () async {
    for (final String phase in <String>[
      'welcome', 'import', 'ready', 'startup-hive-error',
    ]) {
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final WalletRecipe driver = WalletRecipe(
        send: (Map<String, Object?> command, Duration _) async {
          commands.add(command);
          return _view(tab: 'entry', phase: phase);
        },
      );
      await expectLater(driver.settleRestoredStartup(),
        throwsA(isA<WalletRecipeRefused>()));
      expect(commands.every((Map<String, Object?> command) =>
        command['action'] == 'observe'), isTrue);
    }
  });

  test('restored startup requires one acknowledged visible target client',
      () async {
    Map<String, dynamic> window() => <String, dynamic>{
      'ok': true, 'clientMatched': true, 'client': <num>[1280, 780.0],
      'minimized': false, 'maximized': false,
    };
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
    await entry.showRestoredStartupWindow((Map<String, Object?> command) async {
      commands.add(command);
      return window();
    });
    expect(commands, <Map<String, Object?>>[
      <String, Object?>{
        'cmd': 'window', 'do': 'show', 'width': 1280, 'height': 780,
      },
    ]);
    final Map<String, List<Map<String, dynamic>>> invalid =
        <String, List<Map<String, dynamic>>>{
      'WINDOW_RESPONSE_REFUSED': <Map<String, dynamic>>[
        <String, dynamic>{'ok': false}, <String, dynamic>{'ok': 'true'},
      ],
      'WINDOW_CLIENT_REFUSED': <Map<String, dynamic>>[
        <String, dynamic>{'clientMatched': false},
        <String, dynamic>{'client': null},
        <String, dynamic>{'client': <num>[1280]},
        <String, dynamic>{'client': <Object>[true, 780]},
        <String, dynamic>{'client': <num>[double.nan, 780]},
        <String, dynamic>{'client': <num>[1279, 780]},
      ],
      'WINDOW_STATE_REFUSED': <Map<String, dynamic>>[
        <String, dynamic>{'minimized': true},
        <String, dynamic>{'maximized': true},
        <String, dynamic>{'minimized': null},
      ],
    };
    for (final MapEntry<String, List<Map<String, dynamic>>> group
        in invalid.entries) {
      for (final Map<String, dynamic> change in group.value) {
        int requests = 0;
        final Map<String, Object?> failed = await _failure(
          () => entry.showRestoredStartupWindow((_) async {
            requests++;
            return window()..addAll(change);
          }),
          'startup_window',
        );
        expect(requests, 1);
        expect(failed['kind'], 'WINDOW_REFUSED');
        expect(failed['code'], group.key);
        expect(failed['recipe'], isNull);
      }
    }
  });

  test('child failures export fixed types and validated recipe labels only',
      () async {
    final Map<String, String> diagnostic = <String, String>{
      'action': 'observe', 'control': 'none',
      'reason': 'wallet-recipe-refused',
      'entry': 'startup-before-initialization',
      'startup': 'key-confirmed', 'film': 'skip-middle-frame-pending',
    };
    final Map<String, Object?> original = entry.restoredChildFailure(
      'startup',
      WalletRecipeRefused('wallet-recipe-restored-lock-required',
        diagnostic: diagnostic),
    )!;
    expect(original['code'], 'wallet-recipe-restored-lock-required');
    expect(original['recipe'], diagnostic);
    final Map<String, Object?> unknown = entry.restoredChildFailure(
      'startup', WalletRecipeRefused('private',
        diagnostic: <String, String>{...diagnostic, 'private': 'private'}),
    )!;
    expect(unknown['code'], isNull);
    expect(unknown['recipe'], isNull);
    final Map<String, Object> errors = <String, Object>{
      'HARNESS_REFUSED': cli.Fail('private'),
      'FORMAT_ERROR': const FormatException('private'),
      'STATE_ERROR': StateError('private'),
      'OS_ERROR': const FileSystemException('private', 'private'),
      'TYPE_ERROR': _typeError(),
      'OTHER_ERROR': _Unformattable(),
    };
    for (final MapEntry<String, Object> value in errors.entries) {
      final Map<String, Object?> failure =
          entry.restoredChildFailure('startup', value.value)!;
      expect(failure['kind'], value.key);
      expect(failure['code'], isNull);
      expect(failure['recipe'], isNull);
      expect(jsonEncode(failure), isNot(contains('private')));
    }
    expect(entry.restoredChildFailure('private', _Unformattable()), isNull);
    final Map<String, List<String>> expected = <String, List<String>>{
      'UNLOCK_STATE_REFUSED': <String>['state'],
      'UNLOCK_LOCK_REQUIRED': <String>['state'],
      'UNLOCK_FIELD_READY_REFUSED': <String>['state', 'wait'],
      'UNLOCK_TYPE_REFUSED': <String>['state', 'wait', 'type'],
      'UNLOCK_TAP_REFUSED': <String>['state', 'wait', 'type', 'tap'],
      'UNLOCK_WAIT_REFUSED': <String>[
        'state', 'wait', 'type', 'tap', 'state', 'tree',
      ],
      'UNLOCK_FAILURE_TREE_REFUSED': <String>[
        'state', 'wait', 'type', 'tap', 'state', 'tree',
      ],
    };
    expect(expected.keys.toSet(), entry.restoredUnlockFailureCodes);
    for (final MapEntry<String, List<String>> item in expected.entries) {
      final _UnlockInstance instance = _UnlockInstance(item.key);
      final Map<String, Object?> failure = await _failure(
        () => entry.unlockRestoredWallet(
          instance,
          'synthetic-private-password',
        ),
        'unlock',
      );
      expect(instance.commands, item.value);
      expect(failure['kind'], 'HARNESS_REFUSED');
      expect(failure['code'], item.key);
      expect(failure['recipe'], isNull);
      expect(jsonEncode(failure), isNot(contains('private')));
    }
    final _UnlockInstance positive = _UnlockInstance(null);
    await entry.unlockRestoredWallet(positive, 'synthetic-private-password');
    expect(positive.commands, <String>[
      'state', 'wait', 'type', 'tap', 'state',
    ]);
  });

  test('closed lock observations reject private fields and invalid values', () {
    final Map<String, Object?> view = <String, Object?>{
      for (final String key in lockViewBooleanFields) key: false,
      'password_failures': 0, 'lifecycle': 'unknown',
    };
    final Map<String, Object?> value = <String, Object?>{
      'schema': 1, 'status': 'observed', 'owner_same': true, 'view': view,
    };
    expect(projectLockView(value), value);
    expect(projectLockView(<String, Object?>{...value, 'ok': true}), value);
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'private': 'private'},
      <String, Object?>{'schema': true},
      <String, Object?>{'status': 'private'},
      <String, Object?>{'owner_same': false},
      <String, Object?>{'ok': false},
      <String, Object?>{'view': null},
      for (final Map<String, Object?> invalid in <Map<String, Object?>>[
        <String, Object?>{'private': 'private'},
        <String, Object?>{'busy': 1},
        <String, Object?>{'password_failures': true},
        <String, Object?>{'password_failures': -1},
        <String, Object?>{'password_failures': 256},
        <String, Object?>{'lifecycle': 'private'},
      ]) <String, Object?>{'view': <String, Object?>{...view, ...invalid}},
    ]) {
      expect(projectLockView(<String, Object?>{...value, ...change}), isNull);
    }
    for (final String status in lockViewStatuses.difference(
      <String>{'observed'},
    )) {
      expect(projectLockView(<String, Object?>{
        'schema': 1, 'status': status, 'owner_same': false, 'view': null,
      }), isNotNull);
    }
  });

  test('passive lock diagnostics cannot retry or replace an unlock refusal',
      () async {
    for (final Object? view in <Object?>[
      null,
      <String, Object?>{'ok': true, 'private': 'private'},
      <String, Object?>{
        'ok': true, 'schema': 1, 'status': 'observed', 'owner_same': true,
        'view': <String, Object?>{
          for (final String key in lockViewBooleanFields) key: false,
          'password_failures': 0, 'lifecycle': 'inactive',
        },
      },
    ]) {
      final _UnlockInstance instance = _UnlockInstance(
        'UNLOCK_WAIT_REFUSED', lockView: view,
      );
      final Map<String, Object?> failure = await _failure(
        () => entry.unlockRestoredWallet(
          instance, 'synthetic-private-password', observeView: true,
        ), 'unlock',
      );
      expect(instance.commands, <String>[
        'lock-view', 'state', 'wait', 'type', 'tap', 'state', 'tree',
        'lock-view',
      ]);
      expect(failure['code'], 'UNLOCK_WAIT_REFUSED');
      expect(failure['kind'], 'HARNESS_REFUSED');
      expect(jsonEncode(failure), isNot(contains('private')));
      final Map<String, Object?>? projected = projectLockView(view);
      expect(failure['lock_view'], projected);
    }
  });

  test('failed restored wait retains its last labels and cannot adopt lock',
      () async {
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
    bool laterLock = false;
    final WalletRecipe driver = WalletRecipe(
      send: (Map<String, Object?> command, Duration _) async {
        commands.add(command);
        if (command['action'] != 'observe') {
          return <String, dynamic>{'ok': true, 'acted': true};
        }
        return laterLock ? _view() : _view(
          phase: 'startup-before-initialization',
          film: 'skip-middle-frame-pending', hint: true);
      },
      wait: (Duration _) async {},
    );
    final Map<String, Object?> failed = await _failure(
      driver.settleRestoredStartup, 'startup');
    expect(failed['code'], 'wallet-recipe-restored-lock-required');
    final Map<String, String> labels = failed['recipe']! as Map<String, String>;
    expect(labels['entry'], 'startup-before-initialization');
    expect(labels['film'], 'skip-middle-frame-pending');
    expect(labels['startup'], 'key-confirmed');
    expect(commands.where((Map<String, Object?> c) =>
      c['action'] != 'observe').map((Map<String, Object?> c) => c['key']),
      <String>['launch_skip_hint']);
    final int originalRequests = commands.length;
    laterLock = true;
    expect((await _failure(driver.settleRestoredStartup, 'startup'))['code'],
      'wallet-recipe-retired');
    expect(commands.length, originalRequests);
  });
}
