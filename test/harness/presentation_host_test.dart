import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_wallet_picker.dart';

import '../../harness/app/capture_protocol.dart';
import '../../harness/app/presentation_host.dart';

Future<void> _host(
  WidgetTester tester,
  HarnessPresentationController controller,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  try {
    await tester.pumpWidget(
      HarnessPresentationHost(
        controller: controller,
        background: const SizedBox.expand(),
        welcomeGlobe: const SizedBox.expand(),
      ),
    );
    await tester.pump();
    await body();
  } finally {
    // Dispose while widget-test frame pumping still belongs to the body.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    tester.view.reset();
  }
}

Matcher _refused(String code) => throwsA(
  isA<CaptureRefused>().having(
    (CaptureRefused refusal) => refusal.code,
    'code',
    code,
  ),
);

void main() {
  testWidgets('disposing the host removes only its keyboard interception', (
    WidgetTester tester,
  ) async {
    final HarnessPresentationController controller =
        HarnessPresentationController();
    await _host(tester, controller, () async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(controller.surface, 'welcome');
      expect(tester.takeException(), isNull);
    });
    int events = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              events++;
              return KeyEventResult.handled;
            },
            child: const Text('Independent keyboard owner'),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(events, greaterThan(0));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('scene and theme state are anonymous, explicit and memory-only', () {
    final HarnessPresentationController controller =
        HarnessPresentationController();
    try {
      int changes = 0;
      controller.addListener(() => changes++);
      expect(controller.surface, 'welcome');
      expect(controller.theme, 'dark');
      for (final String surface in HarnessPresentationController.surfaces) {
        controller.show(surface);
        expect(controller.snapshot(), <String, Object?>{
          'presentation': true,
          'readOnly': true,
          'surface': surface,
          'theme': 'dark',
          'actualCapture': false,
          'walletOwnerMounted': false,
        });
      }
      expect(changes, HarnessPresentationController.surfaces.length - 1);
      controller.setTheme('light');
      expect(controller.themeMode, ThemeMode.light);
      expect(controller.theme, 'light');
      expect(changes, HarnessPresentationController.surfaces.length);
      expect(
        () => controller.snapshot()['actualCapture'] = true,
        throwsUnsupportedError,
      );
    } finally {
      controller.dispose();
    }
  });

  test('unsupported readiness and frame requests do not mutate', () {
    final HarnessPresentationController controller =
        HarnessPresentationController();
    try {
      int changes = 0;
      controller.addListener(() => changes++);
      for (final String surface in <String>[
        'wallet-ready',
        'launch',
        'launch-settle',
        'frame-17',
        'sentinels',
        'aged-fuse',
        'home-rest',
      ]) {
        expect(
          () => controller.show(surface),
          _refused('presentation-surface-unavailable'),
        );
      }
      expect(
        () => controller.setTheme('system'),
        _refused('presentation-theme-unavailable'),
      );
      expect(changes, 0);
      expect(controller.surface, 'welcome');
      expect(controller.theme, 'dark');
    } finally {
      controller.dispose();
    }
  });

  test('a disposed presentation owner cannot select another scene', () {
    final HarnessPresentationController controller =
        HarnessPresentationController()..dispose();
    expect(
      () => controller.show('import'),
      _refused('presentation-owner-closed'),
    );
    expect(
      () => controller.setTheme('light'),
      _refused('presentation-owner-closed'),
    );
    expect(controller.surface, 'welcome');
    expect(controller.theme, 'dark');
  });

  for (final String theme in <String>['dark', 'light']) {
    testWidgets(
      'welcome is labelled and refuses pointer and direct $theme',
      (WidgetTester tester) async {
        final HarnessPresentationController controller =
            HarnessPresentationController(theme: theme);
        await _host(tester, controller, () async {
          expect(
            find.text('Synthetic presentation. Read only.'),
            findsOneWidget,
          );
          final AbsorbPointer barrier = tester.widget<AbsorbPointer>(
            find.byKey(const Key('harness_presentation_input_barrier')),
          );
          expect(barrier.absorbing, isTrue);
          final BuildContext banner = tester.element(
            find.byKey(const Key('harness_presentation_banner')),
          );
          expect(
            Theme.of(banner).brightness,
            theme == 'dark' ? Brightness.dark : Brightness.light,
          );
          final WelcomeSurface view = tester.widget<WelcomeSurface>(
            find.byType(WelcomeSurface),
          );
          expect(
            () => view.onSelected(WelcomeDestination.createWallet),
            _refused('presentation-action-refused'),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tapAt(
            tester.getCenter(find.byKey(const Key('welcome_create'))),
          );
          await tester.pump();
          expect(controller.surface, 'welcome');
          expect(find.byType(WelcomeSurface), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }

  testWidgets(
    'import has empty private input and no picker or continuation',
    (WidgetTester tester) async {
      final HarnessPresentationController controller =
          HarnessPresentationController(surface: 'import');
      await _host(tester, controller, () async {
        final ImportSurface view = tester.widget<ImportSurface>(
          find.byType(ImportSurface),
        );
        expect(view.seedController.text, isEmpty);
        expect(view.draft.valid, isFalse);
        expect(view.onContinue, isNull);
        expect(view.wrapDrop, isNull);
        expect(view.onBrowse, _refused('presentation-action-refused'));
        expect(
          () => view.onSeedChanged('synthetic input'),
          _refused('presentation-action-refused'),
        );
        expect(view.seedController.text, isEmpty);
        expect(view.draft.words, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'quiz words cannot become a wallet and callbacks cannot advance',
    (WidgetTester tester) async {
      final HarnessPresentationController controller =
          HarnessPresentationController(surface: 'seed-quiz');
      await _host(tester, controller, () async {
        final SeedQuizSurface view = tester.widget<SeedQuizSurface>(
          find.byType(SeedQuizSurface),
        );
        expect(view.quiz, isNotNull);
        expect(view.quiz!.seedWords, everyElement(startsWith('fixture-word-')));
        expect(view.quiz!.correct, 0);
        expect(view.onContinue, isNull);
        expect(
          () => view.onSelected(0, view.quiz!.questions.first.answer),
          _refused('presentation-action-refused'),
        );
        expect(view.quiz!.correct, 0);
        expect(view.quiz!.complete, isFalse);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'wallet-picker is an inert component without account facts',
    (WidgetTester tester) async {
      final HarnessPresentationController controller =
          HarnessPresentationController(surface: 'wallet-picker');
      await _host(tester, controller, () async {
        final LockWalletPicker view = tester.widget<LockWalletPicker>(
          find.byType(LockWalletPicker),
        );
        expect(view.expanded, isTrue);
        expect(view.entries, hasLength(2));
        expect(view.entries.first, same(view.current));
        expect(
          view.entries.map((LockWalletDisplayEntry entry) => entry.address),
          everyElement(isNull),
        );
        expect(controller.snapshot()['actualCapture'], isFalse);
        expect(tester.takeException(), isNull);
      });
    },
  );
}
