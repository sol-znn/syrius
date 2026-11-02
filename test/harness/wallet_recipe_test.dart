import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

import '../../harness/app/agent.dart';
import '../../harness/bin/harness.dart' as cli;
import '../../harness/bin/wallet_recipe.dart';

const String _node = 'ws://127.0.0.1:45998';
const String _password = 'synthetic password input';

// Deliberately invalid mnemonic words: this transport actor owns no SDK,
// signer, socket, process, storage directory or real wallet material.
String _seed(int count) => List<String>.filled(count, 'synthetic').join(' ');

class _WalletUi {
  String phase = 'welcome';
  String? entryPhase;
  String? filmState;
  bool naturalStartup = false;
  bool startupObserved = false;
  int unsettledStartupObservations = 0;
  bool retainUnsettledControls = false;
  String? selectedNode;
  int signing = 1;
  int saved = 1;
  int owner = 1;
  int revision = 40;
  bool initialized = false;
  bool pending = false;
  bool catalogued = true;
  bool nodeForm = false;
  bool nodeSection = false;
  bool chainOpen = false;
  bool hasError = false;
  bool readyOriginal = true;
  String? duplicate;
  String? disabled;
  String? failKey;
  String? stallKey;
  String? commitFault;
  String? missingReceipt;
  final Completer<void> stalled = Completer<void>();
  final Map<String, String> typed = <String, String>{};
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
  Duration elapsed = Duration.zero;
  int opens = 0;
  int consents = 0;

  WalletRecipe driver({Duration timeout = const Duration(seconds: 1)}) =>
      WalletRecipe(
        send: send,
        commandTimeout: timeout,
        elapsed: () => elapsed,
        wait: (Duration time) async {
          elapsed += time;
        },
      );

  List<String> get taps => commands
      .where((Map<String, Object?> command) => command['action'] == 'tap')
      .map((Map<String, Object?> command) => command['key']! as String)
      .toList();

  Map<String, dynamic> observation() {
    final List<String> keys = switch (phase) {
      'startup' => <String>['launch_skip_hint'],
      'welcome' => <String>['welcome_import'],
      'seed' => <String>[
        'import_words_12',
        'import_words_24',
        'import_seed_field',
        'import_continue',
      ],
      'password' => <String>[
        'import_new_password',
        'import_confirm_password',
        'import_password_continue',
      ],
      'node' => <String>[
        'node_settings_add',
        if (catalogued) 'node_settings_select_$_node',
        if (selectedNode == _node) 'node_onboarding_continue',
        if (nodeForm) ...<String>[
          'node_settings_endpoint',
          'node_settings_endpoint_save',
        ],
      ],
      'question' => <String>['node_settings_question_accept'],
      'ready' => <String>['wallet_ready_open'],
      'home' => <String>['nav_settings', 'nav_dashboard'],
      'settings' => <String>[
        'nav_dashboard',
        'settings_node',
        if (nodeSection) 'node_settings_chain_toggle',
        if (nodeSection && chainOpen) ...<String>[
          'node_settings_client_chain',
          'node_settings_chain_save',
        ],
      ],
      _ => <String>[],
    };
    return <String, dynamic>{
      'ok': true,
      'entryPhase': entryPhase ??
          (phase == 'startup' ? 'startup-before-initialization' : phase),
      'startupFilmState': ?filmState,
      'harnessMode': 'wallet',
      'booted': true,
      'owner': owner,
      'revision': revision,
      'walletPresent': initialized,
      'walletInitCompleted': initialized,
      'node': selectedNode,
      'chainId': selectedNode == null ? null : 321,
      'nodeConnected': selectedNode != null,
      'nodeSelectionSaved': selectedNode != null,
      'signingChainId': signing,
      'savedSigningChainId': saved,
      'signingPolicyReady': true,
      'transitionPending': pending,
      'tab': phase == 'home' ? 'dashboard' : phase,
      'nodePicker': phase == 'node' || phase == 'settings' && nodeSection,
      'nodeBusy': pending,
      'nodeCatalog': <String>[if (catalogued) _node],
      'readyOriginal': phase == 'ready' && readyOriginal,
      'question': phase == 'question' ? 7 : null,
      'hasError': hasError,
      'controls': <Map<String, dynamic>>[
        for (final String key in <String>[
          ...keys,
          if (keys.contains(duplicate)) duplicate!,
        ])
          <String, dynamic>{
            'key': key,
            'enabled': key != disabled,
            if (key == 'node_settings_chain_toggle') 'expanded': chainOpen,
          },
      ],
    };
  }

  void connected() {
    selectedNode = _node;
    pending = false;
    revision += 2;
    phase = 'ready';
  }

  Future<Map<String, dynamic>> send(
    Map<String, Object?> command,
    Duration timeout,
  ) async {
    commands.add(Map<String, Object?>.of(command));
    final Object? key = command['key'];
    if (command['action'] == 'observe') {
      if (phase == 'startup' && naturalStartup) {
        if (startupObserved) phase = 'welcome';
        startupObserved = true;
      }
      if (unsettledStartupObservations > 0) {
        unsettledStartupObservations--;
        return <String, dynamic>{
          ...observation(),
          'entryPhase': 'unknown',
          if (!retainUnsettledControls) 'controls': <Map<String, dynamic>>[],
        };
      }
      // The agent authenticates the current dialog's actual facts before the
      // CLI receives them.
      if (phase == 'question' &&
          (command['expectedNode'] != _node ||
              command['expectedNodeChain'] != 321 ||
              command['originalSigningChain'] != signing)) {
        return <String, dynamic>{'ok': false};
      }
      return observation();
    }
    if (stallKey != null && key == stallKey) await stalled.future;
    if (failKey != null && key == failKey) {
      return <String, dynamic>{
        'ok': false,
        'error': '${_seed(12)} $_password private diagnostic',
      };
    }
    if (command['action'] == 'type') {
      typed[key! as String] = command['value']! as String;
      return <String, dynamic>{'ok': true, 'acted': true};
    }
    switch (key) {
      case 'launch_skip_hint':
        phase = 'welcome';
      case 'welcome_import':
        phase = 'seed';
      case 'import_continue':
        phase = 'password';
      case 'import_password_continue':
        initialized = true;
        owner++;
        phase = 'node';
      case 'node_settings_add':
        nodeForm = true;
      case 'node_settings_endpoint_save':
        catalogued = true;
        nodeForm = false;
      case 'node_onboarding_continue':
      case 'node_settings_select_$_node':
        revision++;
        pending = true;
        if (signing == 321) {
          connected();
        } else {
          phase = 'question';
        }
      case 'node_settings_question_accept':
        consents++;
        connected();
      case 'wallet_ready_open':
        opens++;
        phase = 'home';
      case 'nav_settings':
        phase = 'settings';
      case 'settings_node':
        nodeSection = true;
      case 'node_settings_chain_toggle':
        chainOpen = !chainOpen;
      case 'node_settings_chain_save':
        final int value = int.parse(typed['node_settings_client_chain']!);
        if (commitFault != 'runtime') signing = value;
        if (commitFault != 'saved') saved = value;
        if (commitFault == 'owner') owner++;
        if (commitFault == 'node') selectedNode = 'ws://127.0.0.1:55998';
        if (commitFault == 'pending') pending = true;
        if (commitFault == 'error') hasError = true;
      case 'nav_dashboard':
        phase = 'home';
    }
    return <String, dynamic>{
      'ok': true,
      if (missingReceipt == null || key != missingReceipt) 'acted': true,
    };
  }
}

Future<void> _import(
  WalletRecipe driver, {
  int words = 24,
  String? chain = '321',
}) => driver.importWallet(
  chain: chain,
  mnemonic: _seed(words),
  password: _password,
  node: _node,
);

WalletRecipe _inspection(
  _WalletUi ui, {
  Map<String, dynamic> Function(
    Map<String, Object?> command,
    Map<String, dynamic> reply,
  )? transform,
}) => WalletRecipe.inspection(
  expectedPid: 42,
  elapsed: () => ui.elapsed,
  wait: (Duration time) async {
    ui.elapsed += time;
  },
  send: (Map<String, Object?> command, Duration timeout) async {
    expect(command['cmd'], 'readonly-entry');
    final Map<String, dynamic> original = await ui.send(command, timeout);
    // This isolated actor has no SDK or native process. Production responses
    // come from the admitted agent, never from this synthetic projection.
    final Map<String, dynamic> reply = <String, dynamic>{
      ...original,
      'pid': 42,
      'booted': true,
      'harnessMode': 'readonly-native',
      'readOnly': true,
      'readonlyAdmission': <String, dynamic>{
        'schema': 1,
        'scope': 'readonly_native_sdk_admission',
        'status': 'CURRENT',
        'publicationAdmissionPaused': true,
        'automaticReceiveDisabled': true,
      },
    };
    return transform?.call(command, reply) ?? reply;
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('inspection imports through its own namespace with owned replies',
      () async {
    final _WalletUi ui = _WalletUi();
    await _import(_inspection(ui));
    expect(ui.phase, 'home');
    expect(ui.opens, 1);
    expect(ui.signing, 321);
    expect(ui.saved, 321);
    expect(ui.commands.every((Map<String, Object?> command) =>
        command['cmd'] == 'readonly-entry'), isTrue);
  });

  test('inspection refuses foreign mode PID and SDK receipts before input',
      () async {
    for (final String fault in <String>[
      'mode', 'pid', 'paused', 'pending', 'expanded', 'automatic',
    ]) {
      final _WalletUi ui = _WalletUi();
      final WalletRecipe driver = _inspection(ui, transform: (
        Map<String, Object?> _, Map<String, dynamic> reply,
      ) {
        final Map<String, dynamic> sdk =
            reply['readonlyAdmission'] as Map<String, dynamic>;
        switch (fault) {
          case 'mode': reply['harnessMode'] = 'wallet';
          case 'pid': reply['pid'] = 43;
          case 'paused': sdk['publicationAdmissionPaused'] = false;
          case 'pending': sdk['status'] = 'PENDING';
          case 'expanded': sdk['extra'] = true;
          case 'automatic': sdk['automaticReceiveDisabled'] = false;
        }
        return reply;
      });
      await expectLater(_import(driver),
          throwsA(isA<WalletRecipeRefused>()));
      expect(ui.commands.length, 1);
      expect(ui.typed, isEmpty);
      await expectLater(_import(driver),
          throwsA(isA<WalletRecipeRefused>()));
      expect(ui.commands.length, 1);
    }
  });

  test('an inspection action reply cannot borrow a different process',
      () async {
    final _WalletUi ui = _WalletUi();
    final WalletRecipe driver = _inspection(ui, transform: (
      Map<String, Object?> command, Map<String, dynamic> reply,
    ) {
      if (command['action'] == 'type') reply['pid'] = 43;
      return reply;
    });
    await expectLater(_import(driver),
        throwsA(isA<WalletRecipeRefused>()));
    final int commands = ui.commands.length;
    expect(ui.typed.keys, <String>['import_seed_field']);
    expect(ui.opens, 0);
    await expectLater(_import(driver),
        throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands.length, commands);
  });

  test('inspection admits only explicit owned chain-321 import inputs',
      () async {
    for (final (String, String?) input in <(String, String?)>[
      ('1', _node), ('321', null),
      ('321', 'wss://example.invalid:443'),
    ]) {
      final _WalletUi ui = _WalletUi();
      await expectLater(_inspection(ui).importWallet(
        chain: input.$1, node: input.$2,
        mnemonic: _seed(24), password: _password,
      ), throwsA(isA<WalletRecipeRefused>()));
      expect(ui.commands, isEmpty);
    }
  });

  test('inspection needs an actual PID and cannot adopt restored startup',
      () async {
    final _WalletUi ui = _WalletUi();
    expect(() => WalletRecipe.inspection(send: ui.send, expectedPid: 0),
        throwsA(isA<WalletRecipeRefused>()));
    await expectLater(_inspection(ui).settleRestoredStartup(),
        throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands, isEmpty);
  });
  test('startup uses one fixed key before Welcome import', () async {
    final _WalletUi ui = _WalletUi()..phase = 'startup';
    await _import(ui.driver());
    final List<Map<String, Object?>> skips = ui.commands.where(
      (Map<String, Object?> row) => row['key'] == 'launch_skip_hint',
    ).toList();
    expect(skips, hasLength(1));
    expect(skips.single['action'], 'key');
    expect(skips.single.containsKey('value'), isFalse);
    expect(ui.taps.first, 'welcome_import');
    expect(ui.opens, 1);
    final _WalletUi natural = _WalletUi()
      ..phase = 'startup'
      ..naturalStartup = true;
    await _import(natural.driver());
    expect(natural.commands.any(
      (Map<String, Object?> row) => row['action'] == 'key',
    ), isFalse);
    expect(natural.opens, 1);
    final _WalletUi stalledWelcome = _WalletUi()
      ..phase = 'startup'
      ..failKey = 'welcome_import';
    await expectLater(_import(stalledWelcome.driver()), throwsA(
      isA<WalletRecipeRefused>().having(
        (WalletRecipeRefused value) => value.diagnostic?['startup'],
        'original startup decision', 'key-confirmed',
      ),
    ));
  });

  test('startup failures retain only valid film labels', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'startup'
      ..entryPhase = 'startup-before-initialization'
      ..filmState = 'first-frame-pending'
      ..failKey = 'welcome_import';
    await expectLater(_import(ui.driver()), throwsA(
      isA<WalletRecipeRefused>().having(
        (WalletRecipeRefused value) => value.diagnostic?['film'],
        'original film observation', 'first-frame-pending',
      ),
    ));
    final _WalletUi invalid = _WalletUi()
      ..phase = 'startup'
      ..filmState = 'synthetic private asset';
    await expectLater(_import(invalid.driver()), throwsA(
      isA<WalletRecipeRefused>().having(
        (WalletRecipeRefused value) => value.code,
        'unknown film state', 'wallet-recipe-observation-refused',
      ),
    ));
    expect(invalid.commands, hasLength(1));
  });

  for (final bool retainControls in <bool>[false, true]) {
    test('first unsettled entry waits for startup $retainControls', () async {
      final _WalletUi ui = _WalletUi()
        ..phase = 'startup'
        ..unsettledStartupObservations = 2
        ..retainUnsettledControls = retainControls;
      await _import(ui.driver());
      final List<Map<String, Object?>> skips = ui.commands.where(
        (Map<String, Object?> row) => row['key'] == 'launch_skip_hint',
      ).toList();
      expect(skips, hasLength(1));
      expect(skips.single['action'], 'key');
      expect(ui.commands.take(3).every(
        (Map<String, Object?> row) => row['action'] == 'observe',
      ), isTrue);
      expect(ui.taps.first, 'welcome_import');
      expect(ui.opens, 1);
    });
  }

  test('an unsettled entry can hand off naturally without a key', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'startup'
      ..unsettledStartupObservations = 2
      ..naturalStartup = true;
    await _import(ui.driver());
    expect(ui.commands.any(
      (Map<String, Object?> row) => row['action'] == 'key',
    ), isFalse);
    expect(ui.taps.first, 'welcome_import');
    expect(ui.opens, 1);
  });

  test('an entry that never settles retires without input', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'startup'
      ..unsettledStartupObservations = 300;
    final WalletRecipe driver = ui.driver();
    await expectLater(_import(driver), throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands.every(
      (Map<String, Object?> row) => row['action'] == 'observe',
    ), isTrue);
    expect(ui.taps, isEmpty);
    expect(ui.typed, isEmpty);
    final int original = ui.commands.length;
    await expectLater(_import(driver), throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands, hasLength(original));
  });

  for (final bool disabled in <bool>[false, true]) {
    test('an unavailable startup hint retires the recipe $disabled', () async {
      final _WalletUi ui = _WalletUi()
        ..phase = 'startup'
        ..disabled = disabled ? 'launch_skip_hint' : null;
      if (!disabled) ui.phase = 'unavailable';
      ui.entryPhase = 'startup-before-initialization';
      final WalletRecipe driver = ui.driver();
      await expectLater(_import(driver), throwsA(isA<WalletRecipeRefused>()));
      expect(ui.taps, isEmpty);
      expect(ui.typed, isEmpty);
      expect(ui.commands.every(
        (Map<String, Object?> row) => row['action'] == 'observe',
      ), isTrue);
      final int original = ui.commands.length;
      await expectLater(_import(driver), throwsA(isA<WalletRecipeRefused>()));
      expect(ui.commands, hasLength(original));
    });
  }

  test('initialization already in progress cannot receive a skip', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'startup'
      ..entryPhase = 'startup-initialization-started';
    await expectLater(
      _import(ui.driver()), throwsA(isA<WalletRecipeRefused>()),
    );
    expect(ui.commands.any(
      (Map<String, Object?> row) => row['action'] == 'key',
    ), isFalse);
  });

  for (final String? chain in <String?>[null, '', 'true', '0', '-1', '0x141']) {
    test(
      'invalid explicit chain $chain sends no command or private input',
      () async {
        final _WalletUi ui = _WalletUi();
        await expectLater(
          _import(ui.driver(), chain: chain),
          throwsA(isA<WalletRecipeRefused>()),
        );
        expect(ui.commands, isEmpty);
      },
    );
  }

  test('duplicate chain options refuse before a recipe can start', () {
    expect(
      () => cli.Args(<String>['--chain', '1', '--chain=321']),
      throwsA(isA<cli.Fail>()),
    );
  });

  for (final int words in <int>[12, 24]) {
    test(
      '$words words complete through real-consent and signing observations',
      () async {
        final _WalletUi ui = _WalletUi()..catalogued = words == 24;
        await _import(ui.driver(), words: words);
        expect(ui.typed['import_seed_field'], _seed(words));
        expect(ui.typed['import_new_password'], _password);
        expect(ui.typed['import_confirm_password'], _password);
        expect(ui.taps, contains('import_words_$words'));
        expect(ui.consents, 1);
        expect(ui.opens, 1);
        expect(ui.taps, isNot(contains('node_onboarding_continue')));
        expect(ui.signing, 321);
        expect(ui.saved, 321);
        expect(ui.phase, 'home');
        expect(
          ui.taps.indexOf('node_settings_question_accept'),
          lessThan(ui.taps.indexOf('wallet_ready_open')),
        );
        expect(
          ui.taps.indexOf('wallet_ready_open'),
          lessThan(ui.taps.indexOf('node_settings_chain_save')),
        );
        expect(
          ui.commands.every(
            (Map<String, Object?> c) =>
                c['cmd'] == 'wallet-recipe' &&
                !c.containsKey('nth') &&
                !c.containsKey('force') &&
                !c.containsKey('text'),
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'saved selected node requires one explicit onboarding confirmation',
    () async {
      final _WalletUi ui = _WalletUi()..selectedNode = _node;
      await _import(ui.driver());
      expect(
        ui.taps.where((String key) => key == 'node_onboarding_continue'),
        hasLength(1),
      );
      expect(ui.taps, isNot(contains('node_settings_select_$_node')));
      expect(ui.opens, 1);
    },
  );

  test(
    'compatible signing policy needs neither consent nor another Save',
    () async {
      final _WalletUi ui = _WalletUi()
        ..signing = 321
        ..saved = 321;
      await _import(ui.driver());
      expect(ui.consents, 0);
      expect(ui.opens, 1);
      expect(ui.taps, isNot(contains('node_settings_chain_save')));
    },
  );

  test(
    'a standalone node command cannot consent to a signing mismatch',
    () async {
      final _WalletUi ui = _WalletUi()
        ..phase = 'node'
        ..initialized = true;
      await expectLater(
        ui.driver().selectNode(_node),
        throwsA(isA<WalletRecipeRefused>()),
      );
      expect(ui.consents, 0);
      expect(ui.opens, 0);
    },
  );

  test(
    'the actual node chain must match the explicitly requested chain',
    () async {
      final _WalletUi ui = _WalletUi();
      await expectLater(
        _import(ui.driver(), chain: '322'),
        throwsA(isA<WalletRecipeRefused>()),
      );
      expect(ui.consents, 0);
      expect(ui.opens, 0);
    },
  );

  test(
    'an unowned Ready cannot be opened or replaced with another attempt',
    () async {
      final _WalletUi ui = _WalletUi()..readyOriginal = false;
      await expectLater(
        _import(ui.driver()),
        throwsA(isA<WalletRecipeRefused>()),
      );
      expect(ui.consents, 1);
      expect(ui.opens, 0);
      expect(ui.taps, isNot(contains('wallet_ready_open')));
    },
  );

  test('an already selected node must satisfy an explicit chain', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'node'
      ..initialized = true
      ..selectedNode = _node;
    final WalletRecipe driver = ui.driver();
    await expectLater(
      driver.selectNode(_node, expectedChain: 322),
      throwsA(isA<WalletRecipeRefused>()),
    );
    expect(ui.taps, isEmpty);
    expect(ui.consents, 0);
    expect(ui.opens, 0);
    final int commands = ui.commands.length;
    await expectLater(
      driver.selectNode(_node, expectedChain: 321),
      throwsA(isA<WalletRecipeRefused>()),
    );
    expect(ui.commands, hasLength(commands));
  });

  test('an already verified node needs no repeated selection', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'node'
      ..initialized = true
      ..selectedNode = _node;
    await ui.driver().selectNode(_node, expectedChain: 321);
    expect(ui.taps, isEmpty);
    expect(ui.consents, 0);
    expect(ui.opens, 0);
  });

  test('matching node chain never substitutes for signing policy', () async {
    final _WalletUi ui = _WalletUi()
      ..phase = 'home'
      ..selectedNode = _node
      ..initialized = true;
    await ui.driver().changeClientChain(321);
    expect(ui.taps, contains('node_settings_chain_save'));
    expect(ui.signing, 321);
    expect(ui.saved, 321);
  });

  test(
    'an already verified signing policy requires no additional Save',
    () async {
      final _WalletUi ui = _WalletUi()
        ..phase = 'home'
        ..selectedNode = _node
        ..initialized = true
        ..signing = 321
        ..saved = 321;
      await ui.driver().changeClientChain(321);
      expect(ui.taps, isEmpty);
    },
  );

  for (final String fault in <String>[
    'runtime',
    'saved',
    'owner',
    'node',
    'pending',
    'error',
  ]) {
    test('a $fault commit failure cannot report a completed import', () async {
      final _WalletUi ui = _WalletUi()..commitFault = fault;
      await expectLater(
        _import(ui.driver()),
        throwsA(isA<WalletRecipeRefused>()),
      );
      expect(
        ui.taps.where((String key) => key == 'node_settings_chain_save'),
        hasLength(1),
      );
      expect(ui.opens, 1);
      expect(ui.taps, isNot(contains('nav_dashboard')));
    });
  }

  for (final bool ambiguous in <bool>[true, false]) {
    test(
      'an ${ambiguous ? 'ambiguous' : 'disabled'} Welcome cannot be tapped',
      () async {
        final _WalletUi ui = _WalletUi();
        if (ambiguous) {
          ui.duplicate = 'welcome_import';
        } else {
          ui.disabled = 'welcome_import';
        }
        await expectLater(
          _import(ui.driver()),
          throwsA(isA<WalletRecipeRefused>()),
        );
        expect(ui.taps, isEmpty);
        expect(ui.typed, isEmpty);
      },
    );
  }

  test('transport diagnostics cannot expose private input', () async {
    final _WalletUi ui = _WalletUi()..failKey = 'import_password_continue';
    Object? refusal;
    try {
      await _import(ui.driver());
    } on WalletRecipeRefused catch (error) {
      refusal = error;
    }
    expect(refusal, isA<WalletRecipeRefused>());
    expect('$refusal', isNot(contains(_seed(12))));
    expect('$refusal', isNot(contains(_password)));
    expect(ui.consents, 0);
    expect(ui.opens, 0);
  });

  test(
    'an action without its receipt cannot authorize follow-up changes',
    () async {
      final _WalletUi ui = _WalletUi()..missingReceipt = 'wallet_ready_open';
      await expectLater(
        _import(ui.driver()),
        throwsA(isA<WalletRecipeRefused>()),
      );
      expect(ui.opens, 1);
      expect(ui.taps, isNot(contains('node_settings_chain_save')));
      expect(ui.saved, 1);
    },
  );

  for (final String key in <String>[
    'node_settings_question_accept',
    'wallet_ready_open',
    'node_settings_chain_save',
  ]) {
    test('late $key settles only its original action after refusal', () async {
      final _WalletUi ui = _WalletUi()..stallKey = key;
      final WalletRecipe driver = ui.driver(
        timeout: const Duration(milliseconds: 5),
      );
      await expectLater(_import(driver), throwsA(isA<WalletRecipeRefused>()));
      final int commands = ui.commands.length;
      ui.stalled.complete();
      await Future<void>.delayed(Duration.zero);
      expect(ui.commands, hasLength(commands));
      expect(ui.taps.where((String value) => value == key), hasLength(1));
      expect(ui.opens, key == 'node_settings_question_accept' ? 0 : 1);
      await expectLater(
        driver.changeClientChain(321),
        throwsA(isA<WalletRecipeRefused>()),
      );
      expect(ui.commands, hasLength(commands));
    });
  }

  testWidgets('recipe observations omit private field values', (
    WidgetTester tester,
  ) async {
    final TextEditingController input = TextEditingController(text: _seed(12));
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const Key('import_seed_field'),
              controller: input,
            ),
          ),
        ),
      );
      final Map<String, Object?> view = await agent.commandForTest(
        <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
      );
      expect(jsonEncode(view), isNot(contains(_seed(12))));
      expect(view.containsKey('walletPath'), isFalse);
      expect(view.containsKey('addresses'), isFalse);
      expect(view['signingPolicyReady'], isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    }
  });

  testWidgets(
    'the observation retains duplicate actionable keys as ambiguous',
    (
      WidgetTester tester,
    ) async {
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                for (int index = 0; index < 2; index++)
                  KeyedSubtree(
                    key: ValueKey<String>('welcome_import_parent_$index'),
                    child: TextButton(
                      key: const Key('welcome_import'),
                      onPressed: () {},
                      child: const Text('Import'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final Map<String, Object?> view = await agent.commandForTest(
        <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
      );
      final List<Map<String, Object?>> controls =
          view['controls']! as List<Map<String, Object?>>;
      expect(
        controls.where(
          (Map<String, Object?> value) => value['key'] == 'welcome_import',
        ),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a lookalike mismatch has no original selection authority', (
    WidgetTester tester,
  ) async {
    int accepted = 0;
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogCard(
            title: 'Node mismatch',
            body: const Text('Unowned question'),
            actions: <Widget>[
              TextButton(
                key: const Key('node_settings_question_accept'),
                onPressed: () => accepted++,
                child: const Text('Proceed'),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'wallet-recipe',
        'action': 'observe',
        'expectedNode': _node,
        'expectedNodeChain': 321,
        'originalSigningChain': 1,
      }),
      throwsA(isA<HarnessError>()),
    );
    expect(accepted, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
