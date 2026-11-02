import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/harness.dart' as cli;

Map<String, dynamic> _layoutFixture() {
  const List<String> keys = <String>[
    'window-caption',
    'window-body',
    'home_hero',
    'home_send',
    'nodes_tab_pillars',
    'nodes_tab_sentinels',
    'staking_stake_button',
    'plasma_open_fuse',
    'tokens_filter_held',
    'p2p_start_swap',
    'node_settings_add',
    'apps_settings_web_switch',
    'transfer_card',
    'accelerator_strip',
    'bell_panel',
  ];
  List<Map<String, Object?>> snapshot() => <Map<String, Object?>>[
    for (final String key in keys)
      <String, Object?>{'key': key, 'status': 'MISSING'},
  ];
  return <String, dynamic>{
    'schema': 1, 'scope': 'readonly_shot_layout_observation',
    'boundaries': <String>['before_raster', 'after_encoding'],
    'before': snapshot(), 'after': snapshot(), 'unchanged': true,
  };
}

class _TourInstance extends cli.Instance {
  _TourInstance({this.inspection = false}) : super('synthetic-tour');

  final bool inspection;
  bool walletProof = true;
  String tab = 'dashboard';
  String section = 'addresses';
  bool bellOpen = false;
  String? unavailable;
  bool widgetError = false;
  bool severe = false;
  int chain = 321;
  List<String> tabs = <String>[
    ...cli.walletTourPages, 'generation', 'sync', 'lock',
  ];
  final List<String> sections = <String>[];
  final List<String> captured = <String>[];
  final Map<String, String> capturedTabs = <String, String>{};
  final Map<String, String> capturedSections = <String, String>{};
  final Map<String, bool> capturedBells = <String, bool>{};
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
  Map<String, Object?>? outcome;

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    commands.add(Map<String, Object?>.of(command));
    switch (command['cmd']) {
      case 'state':
        return <String, dynamic>{
          'ok': true,
          'harnessMode': inspection ? 'readonly-native' : 'wallet',
          'booted': true,
          if (inspection) ...<String, dynamic>{
            'pid': 44, 'readOnly': true,
            'readonlyAdmission': <String, dynamic>{
              'schema': 1, 'scope': 'readonly_native_sdk_admission',
              'status': 'CURRENT', 'publicationAdmissionPaused': true,
              'automaticReceiveDisabled': true,
            },
            if (walletProof) 'readonlyWallet': <String, dynamic>{
              'schema': 1, 'scope': 'readonly_native_wallet_admission',
              'status': 'CURRENT', 'chain': 321, 'selectedIndex': 1,
              'nativeFrameObserved': true,
            },
          },
          'walletUnlocked': true,
          'walletInitCompleted': true, 'tab': tab, 'tabs': tabs,
          'address': 'synthetic-address', 'walletPath': 'synthetic-profile',
          'node': 'ws://127.0.0.1:45998', 'chainId': chain,
          'signingChainId': 321, 'savedSigningChainId': 321,
        };
      case 'tap':
        final Object? at = command['at'];
        if (at is List && at.length == 2 && at[0] == 0 && at[1] == 779) {
          if (!inspection || tab != 'settings' || section != 'node') {
            throw StateError('unexpected origin tap outside readonly Node');
          }
          if (unavailable == 'nodeRestingTap') {
            return <String, dynamic>{
              'ok': false, 'error': 'synthetic-unavailable',
            };
          }
        }
        if (unavailable != null &&
            (command['tab'] == unavailable || command['key'] == unavailable)) {
          return <String, dynamic>{
            'ok': false, 'error': 'synthetic-unavailable',
          };
        }
        if (command['tab'] case final String value) {
          if (bellOpen) {
            return <String, dynamic>{
              'ok': false, 'error': 'synthetic-covered-navigation',
            };
          }
          if (value == 'notifications') {
            bellOpen = true;
          } else {
            tab = value;
          }
        }
        if (command['key'] case final String key) {
          if (key == 'bell_close') {
            if (!bellOpen) {
              return <String, dynamic>{
                'ok': false, 'error': 'synthetic-bell-not-open',
              };
            }
            bellOpen = false;
          }
          if (key == 'settings_node') section = 'node';
          if (key == 'settings_apps') section = 'apps';
          sections.add(key);
        }
        return <String, dynamic>{'ok': true};
      case 'hover':
        if (!inspection) throw StateError('unexpected ordinary hover');
        if (unavailable == 'hover') {
          return <String, dynamic>{
            'ok': false, 'error': 'synthetic-unavailable',
          };
        }
        return <String, dynamic>{'ok': true};
      case 'wait':
        if (command['key'] == 'bell_panel' &&
            bellOpen == (command['gone'] == true)) {
          return <String, dynamic>{
            'ok': false, 'error': 'synthetic-bell-state-unavailable',
          };
        }
        return <String, dynamic>{'ok': true};
      case 'logs':
        return <String, dynamic>{
          'ok': true, 'seq': 1,
          'logs': <Object?>[
            if (severe && command.containsKey('since'))
              <String, Object?>{'message': 'synthetic private diagnostic'},
          ],
        };
      case 'tree':
        return <String, dynamic>{
          'ok': true,
          'nodes': <Object?>[
            <String, Object?>{
              'kind': widgetError ? 'error' : 'text',
              'label': 'synthetic private widget detail',
            },
          ],
        };
      case 'shot':
        return <String, dynamic>{
          'ok': true, 'png': 'synthetic-frame',
          if (inspection && unavailable != 'layout')
            'layoutObservation': _layoutFixture(),
        };
      default:
        throw StateError('unexpected synthetic command');
    }
  }

  Future<void> run({
    bool changeContext = false,
    bool loseWalletProof = false,
    int? readonlyNativePid,
  }) => cli.tour(
    this,
    cli.Args(<String>[]),
    settle: (_) async {},
    capture: (String page, _) async {
      captured.add(page);
      capturedTabs[page] = tab;
      capturedSections[page] = section;
      capturedBells[page] = bellOpen;
      if (changeContext) chain = 322;
      if (loseWalletProof) walletProof = false;
    },
    publish: (Map<String, Object?> value) => outcome = value,
    readonlyNativePid: readonlyNativePid,
  );
}

class _UnlockStdout extends Fake implements Stdout {
  final List<Object?> lines = <Object?>[];

  @override
  void writeln([Object? object = '']) => lines.add(object);
}

class _UnlockInstance extends cli.Instance {
  _UnlockInstance(this.states) : super('synthetic-unlock');

  final List<Map<String, dynamic>> states;
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
  final _UnlockStdout output = _UnlockStdout();
  final List<cli.UnlockStep> observedSteps = <cli.UnlockStep>[];

  Future<void> runUnlock() => IOOverrides.runZoned<Future<void>>(
    () => cli.unlock(this, 'synthetic-password', observe: observedSteps.add),
    stdout: () => output,
  );

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    commands.add(Map<String, Object?>.of(command));
    if (command['cmd'] == 'state') {
      if (states.isEmpty) throw StateError('synthetic state exhausted');
      return <String, dynamic>{'ok': true, ...states.removeAt(0)};
    }
    if (command['cmd'] == 'wait' || command['cmd'] == 'type' ||
        command['cmd'] == 'tap') {
      return <String, dynamic>{'ok': true};
    }
    throw StateError('unexpected synthetic unlock command');
  }
}

void main() {
  test('ordinary tour cannot adopt an inspection host implicitly', () async {
    final _TourInstance instance = _TourInstance(inspection: true);
    await expectLater(instance.run(), throwsA(isA<cli.Fail>()));
    expect(instance.captured, isEmpty);
    expect(instance.commands.length, 1);
  });

  test('explicit inspection visits every original page with a separate scope',
      () async {
    final _TourInstance instance = _TourInstance(inspection: true);
    await instance.run(readonlyNativePid: 44);
    expect(instance.captured,
        <String>[...cli.walletTourPages, 'walletConnect']);
    expect(instance.outcome!['scope'], 'readonly_native_page_tour');
    expect(instance.outcome!['complete'], isTrue);
    final List<dynamic> visited =
        instance.outcome!['visited']! as List<dynamic>;
    for (final dynamic page in visited) {
      final Map<String, dynamic> layout =
          (page as Map<String, dynamic>)['layout'] as Map<String, dynamic>;
      expect(layout, _layoutFixture());
    }
    final _TourInstance missing = _TourInstance(inspection: true)
      ..unavailable = 'layout';
    await expectLater(missing.run(readonlyNativePid: 44),
        throwsA(isA<cli.WalletTourFailure>()));
    expect(missing.captured, isEmpty);
    final List<dynamic> partial = missing.outcome!['visited']! as List<dynamic>;
    final Map<String, dynamic> incomplete =
        partial.single as Map<String, dynamic>;
    expect(incomplete['captured'], isFalse);
    expect(incomplete['layout'], isNull);
    expect(instance.sections, containsAll(<String>[
      'nodes_tab_pillars', 'nodes_tab_sentinels', 'settings_node',
      'settings_apps', 'bell_close',
    ]));
  });

  test('an explicit inspection cannot borrow ordinary or foreign-PID state',
      () async {
    for (final _TourInstance instance in <_TourInstance>[
      _TourInstance(), _TourInstance(inspection: true),
    ]) {
      await expectLater(instance.run(readonlyNativePid: 45),
          throwsA(isA<cli.Fail>()));
      expect(instance.captured, isEmpty);
      expect(instance.commands.length, 1);
    }
  });

  test('lost wallet scope after one capture prevents further page traversal',
      () async {
    final _TourInstance instance = _TourInstance(inspection: true);
    await expectLater(
        instance.run(readonlyNativePid: 44, loseWalletProof: true),
        throwsA(isA<cli.WalletTourFailure>()));
    expect(instance.captured, <String>['dashboard']);
    expect(instance.outcome!['scope'], 'readonly_native_page_tour');
    expect(instance.outcome!['complete'], isFalse);
  });

  test('unlock refuses unconfirmed non-lock states before password input',
      () async {
    for (final Object? tab in <Object?>[
      'startup', 'welcome', 'dashboard', null,
    ]) {
      for (final Object? unlocked in <Object?>[false, null, 'true', 1]) {
        final _UnlockInstance instance = _UnlockInstance(<Map<String, dynamic>>[
          <String, dynamic>{'tab': tab, 'walletUnlocked': unlocked},
        ]);
        await expectLater(instance.runUnlock(),
          throwsA(isA<cli.Fail>()));
        expect(instance.commands, <Map<String, Object?>>[
          <String, Object?>{'cmd': 'state'},
        ]);
        expect(instance.output.lines, isEmpty);
      }
    }
  });

  test('unlock accepts an already observed unlocked state without input',
      () async {
    final _UnlockInstance instance = _UnlockInstance(<Map<String, dynamic>>[
      <String, dynamic>{'tab': 'dashboard', 'walletUnlocked': true},
    ]);
    await instance.runUnlock();
    expect(instance.commands, <Map<String, Object?>>[
      <String, Object?>{'cmd': 'state'},
    ]);
    expect(instance.output.lines, <Object?>['already unlocked']);
  });

  test('unlock retains the ordinary password field, button and state check',
      () async {
    final _UnlockInstance instance = _UnlockInstance(<Map<String, dynamic>>[
      <String, dynamic>{'tab': 'lock', 'walletUnlocked': false},
      <String, dynamic>{'tab': 'dashboard', 'walletUnlocked': true},
    ]);
    await instance.runUnlock();
    expect(instance.commands, <Map<String, Object?>>[
      <String, Object?>{'cmd': 'state'},
      <String, Object?>{'cmd': 'wait', 'key': 'wallet_password_field',
        'kind': 'field', 'ready': true, 'timeoutMs': 5000},
      <String, Object?>{'cmd': 'type', 'key': 'wallet_password_field',
        'value': 'synthetic-password'},
      <String, Object?>{'cmd': 'tap', 'key': 'wallet_unlock_button'},
      <String, Object?>{'cmd': 'state'},
    ]);
    expect(instance.states, isEmpty);
    expect(instance.output.lines, isEmpty);
    expect(instance.observedSteps, <cli.UnlockStep>[
      cli.UnlockStep.state, cli.UnlockStep.lock, cli.UnlockStep.fieldReady,
      cli.UnlockStep.typePassword,
      cli.UnlockStep.submit, cli.UnlockStep.wait,
    ]);
  });

  test('tour covers every page and reaches merged subpages', () async {
    final _TourInstance instance = _TourInstance();
    await instance.run();
    expect(instance.captured, <String>[
      ...cli.walletTourPages, 'walletConnect',
    ]);
    expect(instance.sections, <String>[
      'nodes_tab_pillars', 'nodes_tab_sentinels', 'bell_close',
      'settings_node', 'settings_apps',
    ]);
    expect(instance.tab, 'dashboard');
    expect(instance.bellOpen, isFalse);
    expect(instance.outcome?['complete'], isTrue);
    final List<Map<String, Object?>> visited =
        instance.outcome!['visited']! as List<Map<String, Object?>>;
    expect(
      visited.every((Map<String, Object?> page) => page['captured'] == true),
      isTrue,
    );
  });

  test('notifications opens the bell while retaining its original page',
      () async {
    final _TourInstance instance = _TourInstance()..tab = 'accelerator';
    await cli.goto(instance, 'notifications');
    expect(instance.tab, 'accelerator');
    expect(instance.bellOpen, isTrue);
    expect(instance.outcome, isNull);
  });

  for (final bool inspection in <bool>[false, true]) {
    test(
        'tour selects capture contexts across retained visits, '
        'inspection $inspection', () async {
      final _TourInstance instance = _TourInstance(inspection: inspection)
        ..tab = 'accelerator'
        ..section = 'apps';
      for (final int visit in <int>[0, 1]) {
        final int before = instance.commands.length;
        await instance.run(readonlyNativePid: inspection ? 44 : null);
        expect(instance.capturedTabs['notifications'], 'dashboard');
        expect(instance.capturedBells['notifications'], isTrue);
        expect(instance.capturedTabs['settings'], 'settings');
        expect(instance.capturedSections['settings'], 'node');
        expect(instance.capturedBells['settings'], isFalse);
        expect(instance.capturedTabs['walletConnect'], 'settings');
        expect(instance.capturedSections['walletConnect'], 'apps');
        expect(instance.tab, 'dashboard');
        expect(instance.section, 'apps');
        expect(instance.outcome?['complete'], isTrue);
        expect(instance.captured.length, (visit + 1) * 12);
        final List<Map<String, Object?>> commands =
            instance.commands.sublist(before);
        expect(commands.where((Map<String, Object?> command) =>
            command['cmd'] == 'tap' &&
            command['key'] == 'settings_node'), hasLength(1));
        final List<Map<String, Object?>> restingTaps = commands.where(
          (Map<String, Object?> command) => command['cmd'] == 'tap' &&
              command['at'] is List,
        ).toList();
        expect(restingTaps, hasLength(inspection ? 1 : 0));
        if (inspection) {
          expect(restingTaps.single, <String, Object?>{
            'cmd': 'tap', 'at': <int>[0, 779], 'settleMs': 0,
          });
          final int at = commands.indexOf(restingTaps.single);
          expect(commands[at - 1]['cmd'], 'hover');
          expect(commands[at + 1]['cmd'], 'tree');
        }
        final List<String> tabs = commands
            .where((Map<String, Object?> command) =>
                command['cmd'] == 'tap' && command['tab'] is String)
            .map((Map<String, Object?> command) => command['tab']! as String)
            .toList();
        final int bell = tabs.indexOf('notifications');
        expect(bell, greaterThan(0));
        expect(tabs[bell - 1], 'dashboard');
        final List<int> hovers = <int>[
          for (int i = 0; i < commands.length; i++)
            if (commands[i]['cmd'] == 'hover') i,
        ];
        final List<int> shots = <int>[
          for (int i = 0; i < commands.length; i++)
            if (commands[i]['cmd'] == 'shot') i,
        ];
        expect(hovers, hasLength(inspection ? shots.length : 0));
        if (inspection) {
          for (int i = 0; i < shots.length; i++) {
            expect(hovers[i], lessThan(shots[i]));
            if (i > 0) expect(hovers[i], greaterThan(shots[i - 1]));
            expect(commands[hovers[i]]['at'], <int>[0, 0]);
            expect(commands[hovers[i]]['settleMs'], 0);
          }
        }
      }
    });
  }

  test('an unavailable page cannot silently become complete', () async {
    final _TourInstance instance = _TourInstance()..unavailable = 'transfer';
    await expectLater(instance.run(), throwsA(isA<cli.Fail>()));
    expect(instance.captured, <String>['dashboard']);
    expect(instance.outcome?['complete'], isFalse);
  });

  test('a missing merged section fails after its rail page opens', () async {
    for (final String key in <String>[
      'nodes_tab_sentinels', 'settings_node',
    ]) {
      final _TourInstance instance = _TourInstance()..unavailable = key;
      await expectLater(instance.run(), throwsA(isA<cli.Fail>()));
      expect(instance.captured,
          key == 'nodes_tab_sentinels'
              ? <String>['dashboard', 'transfer', 'pillars']
              : cli.walletTourPages
                  .takeWhile((String page) => page != 'settings')
                  .toList());
      expect(instance.outcome?['complete'], isFalse);
      expect(instance.commands.where((Map<String, Object?> command) =>
          command['cmd'] == 'tap' && command['key'] == key), hasLength(1));
    }
  });

  test('invalid catalogs are rejected before navigation', () async {
    for (final List<String> tabs in <List<String>>[
      <String>[],
      <String>[...cli.walletTourPages, 'dashboard'],
      <String>[...cli.walletTourPages, 'unknown'],
      cli.walletTourPages.where((String page) => page != 'sentinels').toList(),
    ]) {
      final _TourInstance instance = _TourInstance()..tabs = tabs;
      await expectLater(instance.run(), throwsA(isA<cli.Fail>()));
      expect(instance.captured, isEmpty);
      expect(instance.sections, isEmpty);
    }
  });

  test('widget and severe errors fail without raw diagnostics', () async {
    for (final bool widgetError in <bool>[true, false]) {
      final _TourInstance instance = _TourInstance()
        ..widgetError = widgetError
        ..severe = !widgetError;
      await expectLater(instance.run(), throwsA(isA<cli.Fail>()));
      expect(instance.outcome?['complete'], isFalse);
      expect(instance.outcome.toString(), isNot(contains('private')));
      expect(instance.captured, isEmpty);
    }
  });

  test('wallet context changes stop the tour before the next page', () async {
    final _TourInstance instance = _TourInstance();
    await expectLater(
      instance.run(changeContext: true), throwsA(isA<cli.Fail>()),
    );
    expect(instance.captured, <String>['dashboard']);
    expect(instance.outcome?['complete'], isFalse);
  });

  test('a failed tour tap keeps its original page and operation once',
      () async {
    final _TourInstance instance = _TourInstance()
      ..unavailable = 'nodes_tab_pillars';
    try {
      await instance.run();
      fail('The original unavailable control must refuse');
    } on cli.WalletTourFailure catch (error) {
      expect(error.diagnostic, <String, Object>{
        'schema': 1, 'scope': 'original_wallet_page_tour_failure',
        'page': 'pillars', 'step': 'sectionControlTap', 'kind': 'refused',
      });
    }
    expect(instance.captured, <String>['dashboard', 'transfer']);
    expect(instance.commands.where((Map<String, Object?> command) =>
        command['cmd'] == 'tap' &&
        command['key'] == 'nodes_tab_pillars'), hasLength(1));
    expect(instance.outcome?['complete'], isFalse);
    final _TourInstance blocked = _TourInstance(inspection: true)
      ..unavailable = 'hover';
    try {
      await blocked.run(readonlyNativePid: 44);
      fail('The original unavailable hover must refuse');
    } on cli.WalletTourFailure catch (error) {
      expect(error.diagnostic, <String, Object>{
        'schema': 1, 'scope': 'original_wallet_page_tour_failure',
        'page': 'dashboard', 'step': 'pointerNeutral', 'kind': 'refused',
      });
    }
    expect(blocked.captured, isEmpty);
    expect(blocked.commands.where((Map<String, Object?> command) =>
        command['cmd'] == 'hover'), hasLength(1));
    expect(blocked.outcome?['complete'], isFalse);
    final _TourInstance resting = _TourInstance(inspection: true)
      ..unavailable = 'nodeRestingTap';
    try {
      await resting.run(readonlyNativePid: 44);
      fail('The original unavailable origin tap must refuse');
    } on cli.WalletTourFailure catch (error) {
      expect(error.diagnostic, <String, Object>{
        'schema': 1, 'scope': 'original_wallet_page_tour_failure',
        'page': 'settings', 'step': 'nodeRestingTap', 'kind': 'refused',
      });
    }
    expect(resting.captured, cli.walletTourPages.take(10).toList());
    expect(resting.commands.where((Map<String, Object?> command) =>
        command['cmd'] == 'tap' && command['at'] is List), hasLength(1));
    expect(resting.outcome?['complete'], isFalse);
  });

  test('tour page errors and context changes keep their original guards',
      () async {
    for (final bool contextChange in <bool>[false, true]) {
      final _TourInstance instance = _TourInstance()
        ..severe = !contextChange;
      try {
        await instance.run(changeContext: contextChange);
        fail('The original failed guard must refuse');
      } on cli.WalletTourFailure catch (error) {
        expect(error.diagnostic, <String, Object>{
          'schema': 1, 'scope': 'original_wallet_page_tour_failure',
          'page': 'dashboard',
          'step': contextChange ? 'afterPage' : 'logs', 'kind': 'refused',
        });
        expect(error.toString(), isNot(contains('private')));
      }
      expect(instance.captured,
          contextChange ? <String>['dashboard'] : isEmpty);
      expect(instance.outcome?['complete'], isFalse);
    }
  });

  test('unknown tour input cannot enter diagnostics or replace a good tour',
      () async {
    final cli.WalletTourFailure foreign = cli.WalletTourFailure(
      page: 'synthetic-private-value', step: cli.WalletTourStep.capture,
      kind: cli.WalletTourFailureKind.other,
    );
    expect(foreign.diagnostic['page'], 'unknown');
    expect(foreign.diagnostic.toString(), isNot(contains('private')));
    final _TourInstance instance = _TourInstance();
    await instance.run();
    expect(instance.outcome?['complete'], isTrue);
    expect(instance.captured,
        <String>[...cli.walletTourPages, 'walletConnect']);
  });
}
