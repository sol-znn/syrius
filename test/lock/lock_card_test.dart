import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_card.dart';

const MethodChannel _window = MethodChannel('window_manager');
const String _address = 'z1qq9n7fpaqd8lpcljandzmx4xtku9w4ftwyg0mq';
const Key _password = ValueKey<String>('wallet_password_field');
const Key _unlock = ValueKey<String>('wallet_unlock_button');

/// Layout and field tests do not need to decode art. Their read may remain
/// pending when the film is disposed, without a timer or any wallet I/O.
class _PendingFilmBundle extends CachingAssetBundle {
  final Completer<ByteData> _bytes = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => _bytes.future;
}

/// Playback tests decode the already committed well asset. Nothing is
/// generated, and the presentation has no path from here to wallet files.
class _WellBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    expect(key, 'assets/images/launch_well.webp');
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

Widget _host({
  required TextEditingController password,
  required AssetBundle bundle,
  VoidCallback? onUnlock,
  String name = 'Qualification wallet',
  String? address = _address,
  bool light = false,
  bool busy = false,
  bool canUnlock = true,
  bool opening = false,
  bool incorrect = false,
  bool reduced = false,
  int failures = 0,
  int failedAttempts = 0,
  int? attemptsRemaining,
  String? error,
  ValueListenable<int>? replay,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) => MaterialApp(
  locale: const Locale('en'),
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: DefaultAssetBundle(
        bundle: bundle,
        child: LockCard(
          walletName: name,
          address: address,
          passwordController: password,
          onUnlock: onUnlock ?? () {},
          busy: busy,
          canUnlock: canUnlock,
          opening: opening,
          incorrectPassword: incorrect,
          passwordFailures: failures,
          failedAttempts: failedAttempts,
          attemptsRemaining: attemptsRemaining,
          errorMessage: error,
          replay: replay,
        ),
      ),
    ),
  ),
);

Future<void> _show(
  WidgetTester tester,
  Widget host, {
  Size size = const Size(1280, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(host);
  await tester.pump();
}

double _shakeX(WidgetTester tester) => tester
    .widget<Transform>(
      find.byKey(const ValueKey<String>('lock_password_shake')),
    )
    .transform
    .storage[12];

LaunchFilmController _film(WidgetTester tester) =>
    tester.widget<LaunchFilm>(find.byType(LaunchFilm)).controller!;

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration by = Duration.zero,
}) async {
  for (int tries = 0; tries < 200 && !done(); tries += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(by);
  }
  expect(done(), isTrue, reason: 'the well did not reach its expected frame');
}

List<int> _record(LaunchFilmController film) {
  final List<int> frames = <int>[if (film.frame >= 0) film.frame];
  film.addListener(() {
    if (film.frame >= 0 && (frames.isEmpty || frames.last != film.frame)) {
      frames.add(film.frame);
    }
  });
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TextEditingController password;
  late AssetBundle pendingFilm;

  setUp(() {
    password = TextEditingController();
    pendingFilm = _PendingFilmBundle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (MethodCall call) async => true);
  });

  tearDown(() {
    password.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('lock card follows the ${light ? 'light' : 'dark'} tokens', (
      WidgetTester tester,
    ) async {
      await _show(
        tester,
        _host(password: password, bundle: pendingFilm, light: light),
      );
      final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('lock_card_surface')))
            .width,
        tokens.lockCardWidth,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('lock_film_well')))
            .height,
        tokens.lockWellHeight,
      );
      expect(tester.getSize(find.byKey(_password)).height, tokens.fieldHeight);
      expect(
        tester.getSize(find.byKey(_unlock)).height,
        tokens.lockActionHeight,
      );
      expect(find.text('Qualification wallet'), findsOneWidget);
      expect(find.text('z1qq9n…g0mq'), findsOneWidget);
      expect(find.byType(Ltr), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('lock_attempt_note')),
        findsNothing,
      );
      final FrostedSurface frost = tester.widget<FrostedSurface>(
        find.byType(FrostedSurface),
      );
      expect(frost.sigma, tokens.panelBlur);
      expect(frost.borderRadius, BorderRadius.circular(tokens.dialogRadius));
      final List<BoxDecoration> glassPaint = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FrostedSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map<Decoration>((DecoratedBox box) => box.decoration)
          .whereType<BoxDecoration>()
          .toList();
      final BoxDecoration outline = glassPaint.firstWhere(
        (BoxDecoration paint) =>
            paint.borderRadius == frost.borderRadius && paint.border != null,
      );
      expect(outline.border!.isUniform, isTrue);
      expect((outline.border! as Border).top.color, tokens.line);
      expect(
        glassPaint.any(
          (BoxDecoration paint) =>
              paint.borderRadius == null &&
              paint.border == Border(top: tokens.glassTopEdge),
        ),
        isTrue,
      );
      final DecoratedBox pill = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(PrimaryPill),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((pill.decoration as ShapeDecoration).gradient, tokens.plasma);
      final ColoredBox stage = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('lock_film_well')),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(stage.color, tokens.launchStageBackground);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'wrong password reports the global limit in ${light ? 'light' : 'dark'}',
      (
        WidgetTester tester,
      ) async {
        await _show(
          tester,
          _host(
            password: password,
            bundle: pendingFilm,
            light: light,
            incorrect: true,
            failedAttempts: 1,
            attemptsRemaining: 2,
          ),
        );
        expect(
          find.byKey(const ValueKey<String>('lock_wrong_marker')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('lock_screen_marker')),
          findsNothing,
        );
        expect(
          find.text(
            'Incorrect password. 2 tries left. The wallet resets at the limit.',
          ),
          findsOneWidget,
        );
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Icon warning = tester.widget<Icon>(
          find.byIcon(Icons.warning_amber_outlined),
        );
        expect(warning.color, tokens.error);
        final TextField field = tester.widget<TextField>(find.byKey(_password));
        expect(field.decoration!.enabledBorder!.borderSide.color, tokens.error);
        expect(find.textContaining('removed from this computer'), findsNothing);
        expect(password.text, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a singular remaining try and a disabled limit have no false countdown',
    (
      WidgetTester tester,
    ) async {
      await _show(
        tester,
        _host(
          password: password,
          bundle: pendingFilm,
          incorrect: true,
          failedAttempts: 2,
          attemptsRemaining: 1,
        ),
      );
      expect(
        find.text(
          'Incorrect password. 1 try left. The wallet resets at the limit.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        _host(
          password: password,
          bundle: pendingFilm,
          incorrect: true,
          failedAttempts: 3,
        ),
      );
      expect(find.text('Incorrect password'), findsOneWidget);
      expect(find.textContaining('tries left'), findsNothing);
      expect(find.textContaining('resets'), findsNothing);
    },
  );

  testWidgets('a non-password error does not become a failed-password state', (
    WidgetTester tester,
  ) async {
    await _show(
      tester,
      _host(
        password: password,
        bundle: pendingFilm,
        error: 'Connect the Ledger',
      ),
    );
    expect(find.text('Connect the Ledger'), findsOneWidget);
    expect(find.text('Incorrect password'), findsNothing);
    expect(find.textContaining('tries left'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('lock_wrong_marker')),
      findsNothing,
    );
    expect(_shakeX(tester), 0);
  });

  testWidgets('password entry, submit and reveal remain owned by the caller', (
    WidgetTester tester,
  ) async {
    final List<String> submitted = <String>[];
    await _show(
      tester,
      _host(
        password: password,
        bundle: pendingFilm,
        onUnlock: () => submitted.add(password.text),
      ),
    );
    await tester.tap(find.byKey(_unlock));
    expect(submitted, isEmpty);
    await tester.enterText(find.byKey(_password), 'fixture password');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(_password)).obscureText,
      isFalse,
    );
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.tap(find.byKey(_unlock));
    expect(submitted, <String>['fixture password']);
    expect(password.text, 'fixture password');
    await tester.tap(find.byKey(_password));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, <String>['fixture password', 'fixture password']);
    final TextField field = tester.widget<TextField>(find.byKey(_password));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('busy state refuses submit and re-hides a revealed password', (
    WidgetTester tester,
  ) async {
    int submitted = 0;
    await _show(
      tester,
      _host(
        password: password,
        bundle: pendingFilm,
        onUnlock: () => submitted += 1,
      ),
    );
    await tester.enterText(find.byKey(_password), 'fixture password');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpWidget(
      _host(
        password: password,
        bundle: pendingFilm,
        busy: true,
        opening: true,
        onUnlock: () => submitted += 1,
      ),
    );
    final TextField field = tester.widget<TextField>(find.byKey(_password));
    expect(field.enabled, isFalse);
    expect(field.obscureText, isTrue);
    expect(tester.widget<PrimaryPill>(find.byKey(_unlock)).onPressed, isNull);
    field.onSubmitted!('fixture password');
    expect(submitted, 0);
    expect(find.text('Opening the wallet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('wallet, add and recovery controls refuse all activation', (
    WidgetTester tester,
  ) async {
    await _show(
      tester,
      _host(password: password, bundle: pendingFilm),
    );
    final List<Seam> gates = tester
        .widgetList<SeamGate>(find.byType(SeamGate))
        .map((SeamGate gate) => gate.seam)
        .toList();
    expect(gates, <Seam>[
      Seam.walletPicker,
      Seam.walletPicker,
      Seam.passwordRecovery,
    ]);
    await tester.tap(
      find.byKey(const ValueKey<String>('lock_wallet_display')),
      warnIfMissed: false,
    );
    await tester.tap(find.text('Add a wallet'), warnIfMissed: false);
    await tester.tap(find.text('Forgot the password'), warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(find.byType(LockCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    final TextButton recovery = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Forgot the password'),
    );
    expect(
      recovery.onPressed,
      throwsA(
        isA<SeamNotBuilt>().having(
          (SeamNotBuilt error) => error.seam,
          'seam',
          Seam.passwordRecovery,
        ),
      ),
    );
  });

  testWidgets(
    'an unsaved attempt blocks credentials without claiming a reset',
    (
      WidgetTester tester,
    ) async {
      int submitted = 0;
      password.text = 'fixture password';
      await _show(
        tester,
        _host(
          password: password,
          bundle: pendingFilm,
          canUnlock: false,
          incorrect: true,
          failedAttempts: 1,
          error: 'Unlock state was not saved. Restart Syrius.',
          onUnlock: () => submitted += 1,
        ),
      );
      expect(
        find.text('Unlock state was not saved. Restart Syrius.'),
        findsOneWidget,
      );
      expect(find.textContaining('tries left'), findsNothing);
      expect(find.textContaining('resets'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('lock_wrong_marker')),
        findsOneWidget,
      );
      final TextField field = tester.widget<TextField>(find.byKey(_password));
      expect(field.enabled, isFalse);
      field.onSubmitted!('fixture password');
      expect(submitted, 0);
      expect(tester.widget<PrimaryPill>(find.byKey(_unlock)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'a wrong password shakes twice by 4 px over 200 ms with both flags set',
    (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _show(
        tester,
        _host(password: password, bundle: pendingFilm, reduced: true),
      );
      await tester.pumpWidget(
        _host(
          password: password,
          bundle: pendingFilm,
          reduced: true,
          incorrect: true,
          failures: 1,
          failedAttempts: 1,
          attemptsRemaining: 2,
        ),
      );
      await tester.pump();
      expect(_shakeX(tester), 0);
      for (final (int milliseconds, double x) in <(int, double)>[
        (25, 4),
        (50, -4),
        (50, 4),
        (50, -4),
        (25, 0),
      ]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        expect(_shakeX(tester), closeTo(x, 0.00001));
      }
      await tester.pumpWidget(
        _host(
          password: password,
          bundle: pendingFilm,
          reduced: true,
          incorrect: true,
          failures: 2,
          failedAttempts: 2,
          attemptsRemaining: 1,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(_shakeX(tester), closeTo(4, 0.00001));
    },
  );

  testWidgets('RTL and a short scaled window retain reachable controls', (
    WidgetTester tester,
  ) async {
    await _show(
      tester,
      _host(
        password: password,
        bundle: pendingFilm,
        direction: TextDirection.rtl,
        textScale: 2,
        name: 'A long qualification wallet name',
        incorrect: true,
        failedAttempts: 1,
        attemptsRemaining: 2,
      ),
      size: const Size(480, 420),
    );
    expect(
      Directionality.of(tester.element(find.text('z1qq9n…g0mq'))),
      TextDirection.ltr,
    );
    await tester.ensureVisible(find.byKey(_unlock));
    await tester.pump();
    expect(find.byKey(_unlock).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing display data does not invent a wallet or address', (
    WidgetTester tester,
  ) async {
    await _show(
      tester,
      _host(password: password, bundle: pendingFilm, name: '', address: null),
    );
    expect(find.text('Main'), findsNothing);
    expect(find.text('Qualification wallet'), findsNothing);
    expect(find.byType(Ltr), findsNothing);
    expect(find.byTooltip(_address), findsNothing);
  });

  testWidgets('cold entry decodes only the held ending into view', (
    WidgetTester tester,
  ) async {
    await _show(
      tester,
      _host(password: password, bundle: _WellBundle()),
    );
    final LaunchFilmController film = _film(tester);
    final List<int> frames = _record(film);
    await _until(tester, () => film.isDone);
    expect(film.frameCount, 56);
    expect(frames, <int>[55]);
    expect(film.frame, 55);
    await tester.pump(const Duration(seconds: 2));
    expect(film.frame, 55);
    expect(film.isDone, isTrue);
  });

  testWidgets('manual lock starts at frame 14 and holds frame 55', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> replay = ValueNotifier<int>(1);
    addTearDown(replay.dispose);
    await _show(
      tester,
      _host(password: password, bundle: _WellBundle(), replay: replay),
    );
    final LaunchFilmController film = _film(tester);
    final List<int> frames = _record(film);
    await _until(tester, () => film.frame == 14);
    expect(frames, <int>[14]);
    await _until(
      tester,
      () => film.isDone,
      by: const Duration(milliseconds: 34),
    );
    expect(frames, List<int>.generate(42, (int index) => index + 14));
    expect(film.frame, 55);
  });

  testWidgets(
    'replay requests, repeat failures and hover restart the same segment',
    (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> replay = ValueNotifier<int>(0);
      addTearDown(replay.dispose);
      final AssetBundle bundle = _WellBundle();
      await _show(
        tester,
        _host(password: password, bundle: bundle, replay: replay),
      );
      final LaunchFilmController film = _film(tester);
      await _until(tester, () => film.isDone);
      replay.value += 1;
      await _until(tester, () => film.frame == 14);
      expect(film.isDone, isFalse);
      await _until(
        tester,
        () => film.isDone,
        by: const Duration(milliseconds: 34),
      );
      for (int failure = 1; failure <= 2; failure += 1) {
        await tester.pumpWidget(
          _host(
            password: password,
            bundle: bundle,
            replay: replay,
            incorrect: true,
            failures: failure,
            failedAttempts: failure,
            attemptsRemaining: 3 - failure,
          ),
        );
        await _until(tester, () => film.frame == 14);
        await _until(
          tester,
          () => film.isDone,
          by: const Duration(milliseconds: 34),
        );
      }
      final TestGesture mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey<String>('lock_film_well'))),
      );
      await _until(tester, () => film.frame == 14);
      expect(film.isDone, isFalse);
    },
  );

  testWidgets(
    'replay replacement and disposal release the previous owner',
    (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> old = ValueNotifier<int>(0);
      final ValueNotifier<int> next = ValueNotifier<int>(0);
      addTearDown(old.dispose);
      addTearDown(next.dispose);
      final AssetBundle bundle = _WellBundle();
      await _show(
        tester,
        _host(password: password, bundle: bundle, replay: old),
      );
      final LaunchFilmController film = _film(tester);
      await _until(tester, () => film.isDone);
      await tester.pumpWidget(
        _host(password: password, bundle: bundle, replay: next),
      );
      old.value += 1;
      await tester.pump();
      expect(film.isDone, isTrue);
      next.value += 1;
      await _until(tester, () => film.frame == 14);
      await tester.pumpWidget(const SizedBox.shrink());
      old.value += 1;
      next.value += 1;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
