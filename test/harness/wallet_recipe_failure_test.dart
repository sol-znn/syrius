import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/node_library.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_update/node_update.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart'
    show Panel;
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_frame.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';

import '../../harness/app/agent.dart';
import '../../harness/bin/wallet_recipe.dart';
import '../../harness/wallet_recipe_failure.dart';
import '../node_update/support.dart' as node_fixture;
import '../welcome/support.dart';

class _HeldNodeLibrary extends node_fixture.FakeNodeLibrary {
  final Completer<NodeLibraryStatus> answer = Completer<NodeLibraryStatus>();
  int statusCalls = 0;

  @override
  Future<NodeLibraryStatus> status() {
    statusCalls++;
    return answer.future;
  }
}

Future<Map<String, Object?>> _chainControl(HarnessAgent agent) async {
  final Map<String, Object?> view = await agent.commandForTest(
    <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
  );
  final List<Map<String, Object?>> controls =
      view['controls']! as List<Map<String, Object?>>;
  return controls.singleWhere((Map<String, Object?> row) =>
      row['key'] == 'node_settings_chain_toggle');
}

Future<bool> _chainReady(HarnessAgent agent) async =>
    (await _chainControl(agent))['enabled']! as bool;

Future<Map<String, Object?>> _importControl(HarnessAgent agent) async {
  final Map<String, Object?> view = await agent.commandForTest(
    <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
  );
  final List<Map<String, Object?>> controls =
      view['controls']! as List<Map<String, Object?>>;
  return controls.singleWhere(
    (Map<String, Object?> row) => row['key'] == 'welcome_import',
  );
}

void main() {
  testWidgets('recipe keeps disabled callback and occluded center distinct', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    bool enabled = false;
    bool covered = false;
    int actions = 0;
    Widget host() => welcomeHost(Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(child: TextButton(
          key: const Key('settings_add_address'),
          onPressed: enabled ? () => actions++ : null,
          child: const Text('Synthetic action'),
        )),
        if (covered) const Positioned.fill(
          child: ColoredBox(color: Color(0xff000000)),
        ),
      ],
    ));
    Future<Map<String, Object?>> control() async {
      final Map<String, Object?> view = await agent.commandForTest(
        <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
      );
      final List<Map<String, Object?>> controls =
          view['controls']! as List<Map<String, Object?>>;
      return controls.singleWhere((Map<String, Object?> row) =>
          row['key'] == 'settings_add_address');
    }
    await tester.pumpWidget(host());
    final Finder button = find.byKey(const Key('settings_add_address'));
    final Element original = tester.element(button);
    expect((await control())['enabled'], isFalse);
    expect((await control())['blockedBy'], 'widget');
    enabled = true;
    await tester.pumpWidget(host());
    expect(tester.element(button), same(original));
    expect((await control())['enabled'], isTrue);
    expect((await control()).containsKey('blockedBy'), isFalse);
    covered = true;
    await tester.pumpWidget(host());
    expect(tester.element(button), same(original));
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect((await control())['enabled'], isFalse);
    expect((await control())['blockedBy'], 'hit_test');
    covered = false;
    await tester.pumpWidget(host());
    expect(tester.element(button), same(original));
    expect((await control())['enabled'], isTrue);
    expect(actions, 0);
  });


  for (final (bool disableAnimations, bool failLoad) in <(bool, bool)>[
    (false, false), (true, false), (false, true), (true, true),
  ]) {
    testWidgets('chain recipe waits for updater $failLoad $disableAnimations', (
      WidgetTester tester,
    ) async {
      const Size viewport = Size(1280, 1600);
      prepareWelcomeViewport(tester, size: viewport);
      final _HeldNodeLibrary library = _HeldNodeLibrary();
      final node_fixture.FakeNodeUpdater updater =
          node_fixture.FakeNodeUpdater(library);
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      int factories = 0;
      int saved = 0;
      int picked = 0;
      int toggled = 0;
      addTearDown(() {
        if (!library.answer.isCompleted) {
          library.answer.complete(library.current);
        }
      });
      await tester.pumpWidget(welcomeHost(
        SettingsFrame(
          selected: SettingsSectionId.node,
          onSelected: (SettingsSectionId _) {},
          child: SettingsSection(children: <Widget>[
            NodeUpdateCard(
              library: library,
              repository: node_fixture.kRepo,
              updaterFor: (_) {
                factories++;
                return updater;
              },
              saveRepository: (String _) async {
                saved++;
              },
              pickFile: () async {
                picked++;
                return null;
              },
            ),
            Disclosure(
              title: 'Client chain',
              keyPrefix: 'node_settings_chain',
              onChanged: (bool _) => toggled++,
              child: const SizedBox(height: 60),
            ),
          ]),
        ),
        size: viewport,
        disableAnimations: disableAnimations,
      ));
      await tester.pump();
      final Finder toggle = find.byKey(
        const Key('node_settings_chain_toggle'),
      );
      final Element original = tester.element(toggle);
      final Offset loadingCenter = tester.getCenter(toggle);
      expect(find.byKey(const Key('node_update_loading')), findsOneWidget);
      expect(toggle.hitTestable(), findsOneWidget);
      expect(library.statusCalls, 1);
      expect(await _chainReady(agent), isFalse);
      for (int frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect((await _chainControl(agent))['blockedBy'], 'layout');
      // Ordinary input stays available while the sibling reads its source.
      await tester.tap(toggle);
      expect(toggled, 1);
      if (failLoad) {
        library.answer.completeError(Exception('Synthetic disk read failure'));
      } else {
        library.answer.complete(library.current);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await _chainReady(agent), isFalse);
      for (int frame = 0; frame < 80; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byKey(Key(failLoad
          ? 'node_update_failed' : 'node_update_ready')), findsOneWidget);
      expect(tester.element(toggle), same(original));
      expect(tester.getCenter(toggle), isNot(loadingCenter));
      expect(await _chainReady(agent), isTrue);
      expect(toggled, 1);
      expect(library.statusCalls, 1);
      expect(library.calls, isEmpty);
      expect(updater.calls, isEmpty);
      expect(<int>[factories, saved, picked], <int>[0, 0, 0]);
    });
  }

  for (final bool disableAnimations in <bool>[false, true]) {
    testWidgets('chain recipe waits for its own scroll $disableAnimations', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      int toggled = 0;
      await tester.pumpWidget(welcomeHost(
        SettingsFrame(
          selected: SettingsSectionId.node,
          onSelected: (SettingsSectionId _) {},
          child: SettingsSection(children: <Widget>[
            const SizedBox(height: 240),
            Disclosure(
              title: 'Client chain',
              keyPrefix: 'node_settings_chain',
              onChanged: (bool _) => toggled++,
              child: const SizedBox(height: 60),
            ),
            const SizedBox(height: 1800),
          ]),
        ),
        disableAnimations: disableAnimations,
      ));
      final Finder toggle = find.byKey(
        const Key('node_settings_chain_toggle'),
      );
      final Element original = tester.element(toggle);
      final Offset originalCenter = tester.getCenter(toggle);
      final ScrollableState scroll = Scrollable.of(original);
      final Future<void> moving = scroll.position.animateTo(
        120, duration: const Duration(milliseconds: 200), curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      expect(toggle, findsOneWidget);
      expect(await _chainReady(agent), isFalse);
      for (int frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await moving;
      expect(tester.element(toggle), same(original));
      expect(tester.getCenter(toggle), isNot(originalCenter));
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      expect(await _chainReady(agent), isTrue);
      expect(toggle.hitTestable(), findsOneWidget);
      expect(toggled, 0);
      await tester.tap(toggle);
      expect(toggled, 1);
    });
  }

  for (final bool disableAnimations in <bool>[false, true]) {
    testWidgets('chain field waits for its reveal $disableAnimations', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      final TextEditingController input = TextEditingController(text: '1');
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      try {
        await tester.pumpWidget(welcomeHost(
          SettingsFrame(
            selected: SettingsSectionId.node,
            onSelected: (SettingsSectionId _) {},
            child: SettingsSection(children: <Widget>[
              Panel(
                child: Disclosure(
                  title: 'Client chain',
                  keyPrefix: 'node_settings_chain',
                  child: TextField(
                    key: const Key('node_settings_client_chain'),
                    controller: input,
                  ),
                ),
              ),
            ]),
          ),
          disableAnimations: disableAnimations,
        ));
        await tester.tap(find.byKey(const Key('node_settings_chain_toggle')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final Finder field = find.byKey(
          const Key('node_settings_client_chain'),
        );
        final Element original = tester.element(field);
        final Offset movingCenter = tester.getCenter(field);
        Future<bool> ready() async {
          final Map<String, Object?> view = await agent.commandForTest(
            <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
          );
          final List<Map<String, Object?>> controls =
              view['controls']! as List<Map<String, Object?>>;
          return controls.singleWhere((Map<String, Object?> row) =>
              row['key'] == 'node_settings_client_chain')['enabled']! as bool;
        }
        expect(field.hitTestable(), findsOneWidget);
        expect(await ready(), isFalse);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.element(field), same(original));
        expect(tester.getCenter(field), isNot(movingCenter));
        expect(await ready(), isTrue);
        expect(input.text, '1');
        await tester.enterText(field, '321');
        expect(input.text, '321');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        input.dispose();
      }
    });
  }

  test('control change labels stay private and retire the original driver',
      () async {
    for (final String reason in <String>[
      'wallet-recipe-original-control-replaced',
      'wallet-recipe-original-control-moved',
      'wallet-recipe-original-control-moved-subpixel',
      'wallet-recipe-original-control-resized',
    ]) {
      int calls = 0;
      final WalletRecipe recipe = WalletRecipe(
        send: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          return <String, dynamic>{
            'ok': false, 'error': reason,
            'detail': 'synthetic private geometry',
          };
        },
      );
      Future<void> run() => recipe.importWallet(
        chain: '321', mnemonic: List<String>.filled(12, 'synthetic').join(' '),
        password: 'Synthetic fixture A1!',
      );
      WalletRecipeRefused? failure;
      try {
        await run();
      } on WalletRecipeRefused catch (error) {
        failure = error;
      }
      expect(failure?.diagnostic?['reason'], reason);
      expect(walletRecipePublicDiagnostic(failure?.diagnostic),
          failure?.diagnostic);
      expect(jsonEncode(failure?.diagnostic),
          isNot(contains('synthetic private')));
      await expectLater(run(), throwsA(isA<WalletRecipeRefused>()));
      expect(calls, 1);
    }
  });

  for (final bool disableAnimations in <bool>[false, true]) {
    testWidgets('chain recipe waits for Settings motion $disableAnimations', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      int toggled = 0;
      Widget frame(SettingsSectionId selected) => welcomeHost(
        SettingsFrame(
          selected: selected,
          onSelected: (SettingsSectionId _) {},
          child: selected == SettingsSectionId.addresses
              ? const SizedBox.expand()
              : SettingsSection(children: <Widget>[
                  Disclosure(
                    title: 'Client chain',
                    keyPrefix: 'node_settings_chain',
                    onChanged: (bool _) => toggled++,
                    child: const SizedBox(height: 60),
                  ),
                ]),
        ),
        disableAnimations: disableAnimations,
      );
      Future<Map<String, Object?>> control() async {
        final Map<String, Object?> view = await agent.commandForTest(
          <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
        );
        final List<Map<String, Object?>> controls =
            view['controls']! as List<Map<String, Object?>>;
        return controls.singleWhere((Map<String, Object?> row) =>
            row['key'] == 'node_settings_chain_toggle');
      }
      await tester.pumpWidget(frame(SettingsSectionId.addresses));
      await tester.pumpWidget(frame(SettingsSectionId.node));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final Finder toggle = find.byKey(
        const Key('node_settings_chain_toggle'),
      );
      final Element original = tester.element(toggle);
      final Offset movingCenter = tester.getCenter(toggle);
      expect(toggle.hitTestable(), findsOneWidget);
      expect((await control())['enabled'], isFalse);
      // Ordinary input keeps the transition's original interactive boundary.
      await tester.tap(toggle);
      expect(toggled, 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.element(toggle), same(original));
      expect(tester.getCenter(toggle), isNot(movingCenter));
      expect((await control())['enabled'], isTrue);
      expect(toggled, 1);
    });
  }

  for (final bool disableAnimations in <bool>[false, true]) {
    testWidgets('Welcome recipe waits for its entrance $disableAnimations', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      int selected = 0;
      await tester.pumpWidget(welcomeHost(
        welcomeFixture(
          source: Object(), onSelected: (WelcomeDestination _) => selected++,
        ),
        disableAnimations: disableAnimations,
      ));
      await tester.pump(const Duration(milliseconds: 150));
      final Finder importControl = find.byKey(const Key('welcome_import'));
      final Element original = tester.element(importControl);
      final Offset movingCenter = tester.getCenter(importControl);
      expect(importControl.hitTestable(), findsOneWidget);
      expect((await _importControl(agent))['enabled'], isFalse);
      expect(selected, 0);

      await finishWelcomeEntrance(tester);
      expect(tester.element(importControl), same(original));
      expect(tester.getCenter(importControl), isNot(movingCenter));
      expect((await _importControl(agent))['enabled'], isTrue);
      expect(selected, 0);
    });
  }

  testWidgets('ordinary Welcome input remains available during entrance', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    final List<WelcomeDestination> selected = <WelcomeDestination>[];
    await tester.pumpWidget(welcomeHost(welcomeFixture(
      source: Object(), onSelected: selected.add,
    )));
    await tester.pump(const Duration(milliseconds: 150));
    expect((await _importControl(agent))['enabled'], isFalse);
    expect((await _importControl(agent))['blockedBy'], 'entrance');
    await tester.tap(find.byKey(const Key('welcome_import')));
    expect(selected, <WelcomeDestination>[WelcomeDestination.importWallet]);
    await finishWelcomeEntrance(tester);
    expect((await _importControl(agent))['enabled'], isTrue);
    expect(selected, <WelcomeDestination>[WelcomeDestination.importWallet]);
  });

  testWidgets('the actual Welcome view exposes its original import control', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    int selected = 0;
    await tester.pumpWidget(welcomeHost(welcomeFixture(
      source: Object(), onSelected: (WelcomeDestination _) => selected++,
    )));
    await finishWelcomeEntrance(tester);
    final Map<String, Object?> view = await agent.commandForTest(
      <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
    );
    expect(view['entryPhase'], 'welcome');
    final List<Map<String, Object?>> controls =
        view['controls']! as List<Map<String, Object?>>;
    final List<Map<String, Object?>> imports = controls.where(
      (Map<String, Object?> row) => row['key'] == 'welcome_import',
    ).toList();
    expect(imports, hasLength(1));
    expect(imports.single['enabled'], isTrue);
    expect(selected, 0);
  });

  test('entry labels reject raw text and keep only known view families', () {
    final Map<String, String> value = walletRecipeDiagnostic(
      <String, Object?>{'action': 'observe', 'key': 'welcome_import'},
      'wallet-recipe-control-absent', entryPhase: 'startup-platform-error',
    );
    expect(value['entry'], 'startup-platform-error');
    expect(walletRecipePublicDiagnostic(value), value);
    expect(walletRecipePublicDiagnostic(<String, String>{
      ...value, 'entry': 'synthetic private exception text',
    }), isNull);
    expect(walletRecipeDiagnostic(<String, Object?>{'action': 'observe'},
      'wallet-recipe-control-absent', entryPhase: 'synthetic private data',
    ).containsKey('entry'), isFalse);
    for (final String handoff in walletRecipeStartupHandoffs) {
      final Map<String, String> traced = <String, String>{
        ...value, 'startup': handoff,
      };
      expect(walletRecipePublicDiagnostic(traced), traced);
    }
    expect(walletRecipePublicDiagnostic(<String, String>{
      ...value, 'startup': 'synthetic private input',
    }), isNull);
    for (final String film in walletRecipeStartupFilmStates) {
      final Map<String, String> traced = <String, String>{
        ...value, 'startup': 'key-confirmed', 'film': film,
      };
      expect(walletRecipePublicDiagnostic(traced), traced);
    }
    for (final Object? film in <Object?>[
      'synthetic private asset', 1, true, null,
    ]) {
      expect(walletRecipePublicDiagnostic(<String, Object?>{
        ...value, 'film': film,
      }), isNull);
    }
  });

  for (final bool disabled in <bool>[false, true]) {
    test('wait labels identify the unavailable control $disabled', () async {
      int calls = 0;
      bool acted = false;
      final WalletRecipe recipe = WalletRecipe(
        wait: (Duration _) async {},
        send: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          acted |= command['action'] != 'observe';
          return <String, dynamic>{
            'ok': true, 'harnessMode': 'wallet', 'booted': true,
            'owner': 1, 'revision': 1, 'hasError': false,
            'walletPresent': false, 'transitionPending': false,
            'entryPhase': 'welcome',
            'signingPolicyReady': true,
            'signingChainId': 1, 'savedSigningChainId': 1,
            'controls': <Map<String, dynamic>>[
              if (disabled)
                <String, dynamic>{'key': 'welcome_import', 'enabled': false},
            ],
          };
        },
      );
      Future<void> run() => recipe.importWallet(
        chain: '321', mnemonic: List<String>.filled(12, 'synthetic').join(' '),
        password: 'Synthetic fixture A1!',
      );
      WalletRecipeRefused? failure;
      try {
        await run();
      } on WalletRecipeRefused catch (error) {
        failure = error;
      }
      expect(failure?.code, 'wallet-recipe-stage-unsettled');
      expect(failure?.diagnostic, <String, String>{
        'action': 'observe', 'control': 'welcome_import',
        'entry': 'welcome',
        'startup': 'natural-welcome',
        'reason': disabled
            ? 'wallet-recipe-control-disabled'
            : 'wallet-recipe-control-absent',
      });
      expect(acted, isFalse);
      final int originalCalls = calls;
      await expectLater(run(), throwsA(isA<WalletRecipeRefused>()));
      expect(calls, originalCalls);
    });
  }

  test('a refused field retains fixed labels without its value or reply', () {
    final Map<String, String> value = walletRecipeDiagnostic(
      <String, Object?>{
        'action': 'type', 'key': 'import_seed_field',
        'value': 'synthetic private input',
        'endpoint': 'synthetic private node',
      },
      'wallet-recipe-private-input-refused',
    );
    expect(value, <String, String>{
      'action': 'type', 'control': 'import_seed_field',
      'reason': 'wallet-recipe-private-input-refused',
    });
    expect(jsonEncode(value), isNot(contains('synthetic private')));
    expect(() => value['control'] = 'changed', throwsUnsupportedError);
    expect(walletRecipePublicDiagnostic(value), value);
  });

  test('dynamic controls and unknown errors cannot disclose their text', () {
    final Map<String, String> value = walletRecipeDiagnostic(
      <String, Object?>{
        'action': 'tap',
        'key': 'node_settings_select_wss://synthetic-private.invalid:321',
      },
      'synthetic private transport detail',
    );
    expect(value['control'], 'node_settings_select');
    expect(value['reason'], 'wallet-recipe-refused');
    expect(jsonEncode(value), isNot(contains('synthetic')));
    expect(walletRecipePublicDiagnostic(<String, String>{
      ...value, 'detail': 'synthetic private data',
    }), isNull);
    expect(walletRecipePublicDiagnostic(<String, String>{
      ...value, 'reason': 'synthetic private data',
    }), isNull);
  });

  test('failure labels keep the refusal and retire its driver', () async {
    int calls = 0;
    final WalletRecipe recipe = WalletRecipe(
      send: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        return <String, dynamic>{
          'ok': false, 'error': 'wallet-recipe-original-owner-changed',
          'detail': 'synthetic private reply',
        };
      },
    );
    Future<void> run() => recipe.importWallet(
      chain: '321', mnemonic: List<String>.filled(12, 'synthetic').join(' '),
      password: 'Synthetic fixture A1!',
    );
    WalletRecipeRefused? failure;
    try {
      await run();
    } on WalletRecipeRefused catch (error) {
      failure = error;
    }
    expect(failure?.code, 'wallet-recipe-command-refused');
    expect(failure?.diagnostic, <String, String>{
      'action': 'observe', 'control': 'none',
      'reason': 'wallet-recipe-original-owner-changed',
    });
    expect('$failure', isNot(contains('synthetic private')));
    await expectLater(run(), throwsA(isA<WalletRecipeRefused>()));
    expect(calls, 1);
  });

  testWidgets('the server preserves a fixed owner refusal without acting', (
    WidgetTester tester,
  ) async {
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'wallet-recipe', 'action': 'tap', 'key': 'welcome_import',
        'owner': 0, 'revision': 0,
      }),
      throwsA(isA<HarnessError>().having(
        (HarnessError value) => value.message,
        'message', 'wallet-recipe-original-owner-changed',
      )),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
