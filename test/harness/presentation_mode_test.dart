import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/presentation_close.dart';
import '../../harness/app/presentation_host.dart';
import '../../harness/app/presentation_mode.dart';

Future<T> _drive<T>(WidgetTester tester, Future<T> original) async {
  bool settled = false;
  T? result;
  Object? failure;
  StackTrace? trace;
  unawaited(
    original.then<void>(
      (T value) {
        result = value;
        settled = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        settled = true;
      },
    ),
  );
  for (int frame = 0; frame < 80 && !settled; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(settled, isTrue, reason: 'The original command must settle');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result as T;
}

Future<HarnessError> _refusedCommand(
  WidgetTester tester,
  Future<Map<String, Object?>> original,
) async {
  try {
    await _drive(tester, original);
  } on HarnessError catch (error) {
    return error;
  }
  fail('The original command must refuse');
}

void main() {
  test(
    'launcher replaces inherited profiles and never inherits preview mode',
    () {
      expect(
        harnessPresentationSurfaces,
        HarnessPresentationController.surfaces.toSet(),
      );
      final Map<String, String> parent = <String, String>{
        'Path': 'fixture-tools',
        'AppData': 'parent-profile',
        'home': 'parent-home',
        'SYRIUS_HARNESS_PRESENTATION': 'wallet-ready',
        'syrius_harness_token': 'parent-control',
      };
      Map<String, String> environment({String? presentation}) =>
          harnessLaunchEnvironment(
            parent,
            profileHome: 'isolated-home',
            appData: 'isolated-roaming',
            localAppData: 'isolated-local',
            temporary: 'isolated-temp',
            port: 12345,
            token: 'fixture-control',
            presentation: presentation,
          );

      final Map<String, String> wallet = environment();
      expect(wallet.containsKey(harnessPresentationEnvironment), isFalse);
      expect(wallet.containsKey('AppData'), isFalse);
      expect(wallet.containsKey('home'), isFalse);
      expect(wallet.containsKey('syrius_harness_token'), isFalse);
      expect(wallet['APPDATA'], 'isolated-roaming');
      expect(wallet['HOME'], 'isolated-home');
      expect(wallet['TEMP'], 'isolated-temp');
      expect(wallet['SYRIUS_HARNESS_TOKEN'], 'fixture-control');
      expect(wallet['Path'], 'fixture-tools');
      expect(parent['AppData'], 'parent-profile');
      expect(parent[harnessPresentationEnvironment], 'wallet-ready');
      expect(
        environment(presentation: 'welcome')[harnessPresentationEnvironment],
        'welcome',
      );
      expect(
        () => environment(presentation: 'wallet-ready'),
        throwsArgumentError,
      );
    },
  );

  test('launcher cannot reuse another mode or component', () {
    final Map<String, dynamic> wallet = <String, dynamic>{
      'harnessMode': 'wallet',
    };
    final Map<String, dynamic> preview = <String, dynamic>{
      'harnessMode': 'presentation',
      'presentationScreen': 'welcome',
      'pid': 44,
    };
    expect(harnessLaunchMatches(wallet), isTrue);
    expect(harnessLaunchMatches(preview), isFalse);
    expect(harnessLaunchMatches(wallet, presentation: 'welcome'), isFalse);
    expect(harnessLaunchMatches(preview, presentation: 'welcome'), isTrue);
    expect(harnessLaunchMatches(preview, presentation: 'import'), isFalse);
    expect(
      harnessLaunchMatches(preview, presentation: 'welcome', expectedPid: 45),
      isFalse,
    );
    expect(
      harnessLaunchMatches(preview, presentation: 'welcome', expectedPid: 44),
      isTrue,
    );
    expect(harnessLaunchMatches(<String, dynamic>{}), isFalse);
  });

  test(
    'preview cannot drive input, wallet services or shot evidence',
    () async {
      final HarnessPresentationController controller =
          HarnessPresentationController();
      addTearDown(controller.dispose);
      final HarnessAgent agent = HarnessAgent.forTest();
      int probes = 0;
      int changes = 0;
      controller.addListener(() => changes++);
      agent.usePresentation(
        controller: controller,
        isCurrent: () {
          probes++;
          return true;
        },
        context: () => null,
      );
      for (final String command in <String>[
        'tap',
        'hover',
        'type',
        'key',
        'scroll',
        'drag',
        'drop',
        'seed',
        'clipboard',
        'shot',
        'screens',
        'import',
        'unlock',
        'chain',
      ]) {
        await expectLater(
          agent.commandForTest(<String, dynamic>{'cmd': command}),
          throwsA(isA<HarnessError>()),
          reason: command,
        );
      }
      expect(probes, 0);
      expect(changes, 0);
      await expectLater(
        agent.commandForTest(<String, dynamic>{'cmd': 'state'}),
        throwsA(isA<HarnessError>()),
      );
      expect(probes, 1);
    },
  );

  test('a reserved wallet host cannot switch to presentation later', () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    final HarnessPresentationController controller =
        HarnessPresentationController();
    addTearDown(controller.dispose);
    expect(
      (await agent.commandForTest(<String, dynamic>{
        'cmd': 'ping',
      }))['harnessMode'],
      'wallet',
    );
    expect(
      () => agent.usePresentation(
        controller: controller,
        isCurrent: () => true,
        context: () => null,
      ),
      throwsA(isA<HarnessError>()),
    );
  });

  testWidgets('an unseen replacement cannot reuse the original host', (
    WidgetTester tester,
  ) async {
    final HarnessPresentationController controller =
        HarnessPresentationController();
    final GlobalKey host = GlobalKey();
    final HarnessAgent agent = HarnessAgent.forTest()
      ..usePresentation(
        controller: controller,
        isCurrent: () => host.currentContext?.mounted ?? false,
        context: () => host.currentContext,
      )
      ..booted = true;
    final HarnessPresentationHost view = HarnessPresentationHost(
      key: host,
      controller: controller,
      background: const SizedBox.expand(),
      welcomeGlobe: const SizedBox.expand(),
    );
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    try {
      await tester.pumpWidget(view);
      final BuildContext original = host.currentContext!;
      await agent.commandForTest(<String, dynamic>{'cmd': 'state'});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(view);
      expect(original.mounted, isFalse);
      expect(host.currentContext, isNot(same(original)));
      for (final String command in <String>['state', 'ping', 'theme']) {
        await expectLater(
          agent.commandForTest(<String, dynamic>{'cmd': command}),
          throwsA(isA<HarnessError>()),
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.reset();
    }
  });

  for (final bool retireBeforeClose in <bool>[true, false]) {
    testWidgets('quit retains its original close, retired $retireBeforeClose', (
      WidgetTester tester,
    ) async {
      final Completer<void> delay = Completer<void>();
      final Completer<void> originalClose = Completer<void>();
      final HarnessPresentationController controller =
          HarnessPresentationController();
      final GlobalKey host = GlobalKey();
      int closes = 0;
      final HarnessAgent agent =
          HarnessAgent.forTest(
            waitForPresentationClose: () => delay.future,
            closePresentation: () {
              closes++;
              return originalClose.future;
            },
          )..usePresentation(
            controller: controller,
            isCurrent: () => host.currentContext?.mounted ?? false,
            context: () => host.currentContext,
          );
      try {
        await tester.pumpWidget(
          KeyedSubtree(
            key: host,
            child: const MaterialApp(home: Text('Original close host')),
          ),
        );
        final Map<String, Object?> acknowledgement = await agent.commandForTest(
          <String, dynamic>{'cmd': 'quit'},
        );
        final PresentationCloseAttempt attempt =
            agent.presentationCloseForTest!;
        expect(acknowledgement['close'], attempt.snapshot());
        expect(attempt.status, PresentationCloseStatus.queued);
        expect(attempt.originalAdmission, same(delay.future));
        expect(attempt.originalClose, isNull);
        expect(attempt.snapshot()['exitProved'], isFalse);
        expect(closes, 0);
        await agent.commandForTest(<String, dynamic>{'cmd': 'quit'});
        expect(agent.presentationCloseForTest, same(attempt));
        await expectLater(
          agent.commandForTest(<String, dynamic>{
            'cmd': 'theme',
            'mode': 'light',
          }),
          throwsA(isA<HarnessError>()),
        );
        if (retireBeforeClose) {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        delay.complete();
        await attempt.admission;
        if (retireBeforeClose) {
          final PresentationCloseOutcome outcome = await attempt.completion;
          expect(outcome.status, PresentationCloseStatus.refused);
          expect(outcome.error, isA<HarnessError>());
          expect(attempt.originalClose, isNull);
          expect(closes, 0);
        } else {
          expect(attempt.status, PresentationCloseStatus.admitted);
          expect(attempt.originalClose, same(originalClose.future));
          expect(closes, 1);
          final Object failure = StateError('Synthetic native close failed');
          final StackTrace trace = StackTrace.current;
          originalClose.completeError(failure, trace);
          final PresentationCloseOutcome outcome = await attempt.completion;
          expect(outcome.status, PresentationCloseStatus.failed);
          expect(outcome.error, same(failure));
          expect(outcome.stackTrace.toString(), trace.toString());
          final Map<String, Object?> again = await agent.commandForTest(
            <String, dynamic>{'cmd': 'quit'},
          );
          expect(again['close'], attempt.snapshot());
          expect(agent.presentationCloseForTest, same(attempt));
          expect(closes, 1);
          final Map<String, Object?> state = await agent.commandForTest(
            <String, dynamic>{'cmd': 'state'},
          );
          expect(state['close'], attempt.snapshot());
          expect(attempt.snapshot().containsKey('error'), isFalse);
          expect(attempt.snapshot()['exitProved'], isFalse);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });
  }

  for (final String theme in <String>['dark', 'light']) {
    for (final String surface in <String>['welcome', 'import']) {
      testWidgets(
        'actual $surface assertions retain the $theme input barrier',
        (
          WidgetTester tester,
        ) async {
          final HarnessPresentationController controller =
              HarnessPresentationController(surface: surface, theme: theme);
          final GlobalKey host = GlobalKey();
          final HarnessAgent agent = HarnessAgent.forTest()
            ..usePresentation(
              controller: controller,
              isCurrent: () => host.currentContext?.mounted ?? false,
              context: () => host.currentContext,
            );
          bool covered = false;
          bool hidden = false;
          late StateSetter update;
          tester.view.physicalSize = const Size(1280, 780);
          tester.view.devicePixelRatio = 1;
          try {
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                    update = setState;
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Opacity(
                          opacity: hidden ? 0 : 1,
                          child: HarnessPresentationHost(
                            key: host,
                            controller: controller,
                            background: const SizedBox.expand(),
                            welcomeGlobe: const SizedBox.expand(),
                          ),
                        ),
                        if (covered)
                          const Positioned.fill(
                            child: ColoredBox(color: Colors.black),
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 700));
            final String target = surface == 'welcome'
                ? 'welcome_create'
                : 'import_seed_field';
            Future<Map<String, Object?>> assertion(String key) =>
                agent.commandForTest(<String, dynamic>{
                  'cmd': 'assert',
                  'key': key,
                });
            final Map<String, Object?> shown = await assertion(target);
            expect(shown['asserted'], isTrue);
            expect(shown['presentationOnly'], isTrue);
            expect(shown['actualCapture'], isFalse);
            expect(
              (await assertion('harness_presentation_banner'))['asserted'],
              isTrue,
            );
            final Map<String, Object?> state = await agent.commandForTest(
              <String, dynamic>{'cmd': 'state'},
            );
            expect(state['harnessMode'], 'presentation');
            expect(state['walletUnlocked'], isFalse);
            expect(state['walletInitCompleted'], isFalse);
            expect(state.keys, isNot(contains('walletPath')));
            expect(state.keys, isNot(contains('address')));
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            for (final EditableText field in tester.widgetList<EditableText>(
              find.byType(EditableText),
            )) {
              expect(field.focusNode.hasFocus, isFalse);
            }
            await expectLater(
              agent.commandForTest(<String, dynamic>{
                'cmd': 'tap',
                'key': target,
              }),
              throwsA(isA<HarnessError>()),
            );
            expect(
              tester
                  .widget<AbsorbPointer>(
                    find.byKey(const Key('harness_presentation_input_barrier')),
                  )
                  .absorbing,
              isTrue,
            );
            update(() => covered = true);
            await tester.pump();
            await expectLater(assertion(target), throwsA(isA<HarnessError>()));
            update(() {
              covered = false;
              hidden = true;
            });
            await tester.pump();
            await expectLater(assertion(target), throwsA(isA<HarnessError>()));
            update(() => hidden = false);
            await tester.pump();
            expect((await assertion(target))['asserted'], isTrue);
            expect(controller.surface, surface);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            tester.view.reset();
          }
        },
      );
    }
  }

  test(
    'a nested observed retirement cannot be restored by the outer proof',
    () async {
      final HarnessAgent agent = HarnessAgent.forTest();
      final HarnessPresentationController controller =
          HarnessPresentationController();
      addTearDown(controller.dispose);
      bool active = true;
      bool inside = false;
      Future<void>? nested;
      Object? nestedError;
      agent.usePresentation(
        controller: controller,
        context: () => null,
        isCurrent: () {
          if (!inside) {
            inside = true;
            active = false;
            nested = agent
                .commandForTest(<String, dynamic>{'cmd': 'state'})
                .then<void>(
                  (_) => fail('Retired source was admitted'),
                  onError: (Object error, StackTrace _) {
                    nestedError = error;
                  },
                );
            active = true;
            inside = false;
          }
          return active;
        },
      );
      await expectLater(
        agent.commandForTest(<String, dynamic>{'cmd': 'state'}),
        throwsA(isA<HarnessError>()),
      );
      await nested;
      expect(active, isTrue);
      expect(nestedError, isA<HarnessError>());
      await expectLater(
        agent.commandForTest(<String, dynamic>{'cmd': 'state'}),
        throwsA(isA<HarnessError>()),
      );
    },
  );

  testWidgets('a listener cannot replace then restore the requested preview', (
    WidgetTester tester,
  ) async {
    final HarnessPresentationController controller =
        HarnessPresentationController();
    final GlobalKey host = GlobalKey();
    final HarnessAgent agent = HarnessAgent.forTest()
      ..usePresentation(
        controller: controller,
        isCurrent: () => host.currentContext?.mounted ?? false,
        context: () => host.currentContext,
      );
    bool changed = false;
    controller.addListener(() {
      if (!changed) {
        changed = true;
        controller
          ..show('seed-quiz')
          ..show('import');
      }
    });
    await tester.pumpWidget(
      KeyedSubtree(
        key: host,
        child: MaterialApp(
          theme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: const Text('Preview marker'),
        ),
      ),
    );
    try {
      final HarnessError failure = await _refusedCommand(
        tester,
        agent.commandForTest(<String, dynamic>{
          'cmd': 'presentation',
          'surface': 'import',
        }),
      );
      expect(
        failure.message,
        'the presentation changed during this command',
      );
      expect(changed, isTrue);
      expect(controller.surface, 'import');
      await expectLater(
        agent.commandForTest(<String, dynamic>{'cmd': 'state'}),
        throwsA(isA<HarnessError>()),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  for (final bool followTheme in <bool>[true, false]) {
    testWidgets('preview verifies the attached theme, follows $followTheme', (
      WidgetTester tester,
    ) async {
      final HarnessPresentationController controller =
          HarnessPresentationController();
      final GlobalKey host = GlobalKey();
      final HarnessAgent agent = HarnessAgent.forTest()
        ..usePresentation(
          controller: controller,
          isCurrent: () => host.currentContext?.mounted ?? false,
          context: () => host.currentContext,
        );
      await tester.pumpWidget(
        KeyedSubtree(
          key: host,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, _) => MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: followTheme ? controller.themeMode : ThemeMode.dark,
              home: const Scaffold(body: Text('Presentation theme')),
            ),
          ),
        ),
      );
      try {
        final Future<Map<String, Object?>> original = agent.commandForTest(
          <String, dynamic>{'cmd': 'theme', 'mode': 'light'},
        );
        if (followTheme) {
          final Map<String, Object?> result = await _drive(tester, original);
          expect(result['mode'], 'light');
          expect(result['brightness'], 'light');
          expect(result['readOnly'], isTrue);
          expect(
            Theme.of(
              tester.element(find.text('Presentation theme')),
            ).brightness,
            Brightness.light,
          );
        } else {
          final HarnessError failure = await _refusedCommand(tester, original);
          expect(
            failure.message,
            'the presentation theme was not observed',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await expectLater(
          agent.commandForTest(<String, dynamic>{'cmd': 'state'}),
          throwsA(isA<HarnessError>()),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });
  }
}
