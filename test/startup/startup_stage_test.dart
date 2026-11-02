import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_tab_child.dart';

const String _asset = 'test/launch_film/fixtures/film.webp';
const MethodChannel _window = MethodChannel('window_manager');

class _FilmBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

class _PendingBundle extends CachingAssetBundle {
  final Completer<ByteData> _bytes = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => _bytes.future;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.session, super.key});

  final StartupStageSession session;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _inShell = false;
  final ValueNotifier<int> _replay = ValueNotifier<int>(0);
  final List<String> unlocks = <String>[];
  int initialized = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.show(context);
    });
  }

  void adopt() {
    expect(
      widget.session.claim(
        afterUnlock: (String password) async => unlocks.add(password),
        afterInit: () => initialized++,
        replay: _replay,
      ),
      isTrue,
    );
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.session.moveAuthToShell();
      setState(() => _inShell = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.session.settle();
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Expanded(
          child: _inShell
              ? widget.session.buildAuth()
              : const SizedBox.expand(),
        ),
        const SizedBox(height: 40),
      ],
    ),
  );

  @override
  void dispose() {
    widget.session.dispose();
    _replay.dispose();
    super.dispose();
  }
}

StartupStageSession _session(VoidCallback done, {AssetBundle? bundle}) =>
    StartupStageSession(
      asset: _asset,
      wellAsset: _asset,
      bundle: bundle ?? _FilmBundle(),
      onDone: done,
      authBuilder: (_, StartupStageSession session) => LockTabChild(
        session.unlock,
        session.initialized,
        replay: session.replay,
        startup: session,
      ),
    );

Future<GlobalKey<_HarnessState>> _show(
  WidgetTester tester,
  StartupStageSession session, {
  bool light = false,
  bool reduced = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 780);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  final GlobalKey<_HarnessState> key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: _Harness(key: key, session: session),
    ),
  );
  await tester.pump();
  return key;
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration by = const Duration(milliseconds: 20),
}) async {
  for (int turn = 0; turn < 150 && !done(); turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(
        const Duration(milliseconds: 10),
      ),
    );
    await tester.pump(by);
  }
  expect(done(), isTrue, reason: 'The original movie did not complete');
}

Future<void> _begin(
  WidgetTester tester,
  GlobalKey<_HarnessState> host,
) async {
  host.currentState!.adopt();
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Rect _stageRect(WidgetTester tester) => tester.getRect(
  find.byKey(const ValueKey<String>('startup_stage_rect')),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (_) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'mounts the real auth owner before the first movie frame '
      'in ${light ? 'light' : 'dark'}',
      (
        WidgetTester tester,
      ) async {
        int done = 0;
        final StartupStageSession session = _session(() => done++);
        await _show(tester, session, light: light);
        expect(find.byType(LockTabChild), findsOneWidget);
        expect(find.byType(LaunchFilm), findsOneWidget);
        expect(
          tester.widget<LaunchFilm>(find.byType(LaunchFilm)).fit,
          BoxFit.cover,
        );
        expect(session.film.frame, -1);
        expect(find.text('Click or press a key to skip'), findsOneWidget);
        expect(
          tester
              .getRect(find.byKey(const ValueKey<String>('launch_skip_hint')))
              .bottom,
          754,
        );
        final LockCard card = tester.widget<LockCard>(find.byType(LockCard));
        expect(card.canUnlock, isFalse);
        card.passwordController.text = 'Synthetic input';
        card.onUnlock();
        await session.unlock('Synthetic input');
        session.initialized();
        await tester.pump();
        expect(card.passwordController.text, 'Synthetic input');
        expect(session.interactive, isFalse);
        expect(done, 0);
        expect(_stageRect(tester), const Rect.fromLTWH(0, 0, 1280, 780));
      },
    );
  }

  testWidgets('pointer skip holds the original final frame and starts once', (
    WidgetTester tester,
  ) async {
    int done = 0;
    late StartupStageSession session;
    session = _session(() {
      done++;
      session.wait();
    });
    await _show(tester, session);
    await tester.tapAt(const Offset(100, 100));
    await _until(tester, () => session.film.isDone);
    expect(session.film.frame, 7);
    expect(done, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Click or press a key to skip'), findsNothing);
    await tester.tapAt(const Offset(100, 100));
    await tester.pump(const Duration(seconds: 1));
    expect(done, 1);
    expect(session.interactive, isFalse);
  });

  testWidgets('any key skips without handing input to the password', (
    WidgetTester tester,
  ) async {
    int done = 0;
    final StartupStageSession session = _session(() => done++);
    await _show(tester, session);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await _until(tester, () => session.film.isDone);
    expect(done, 1);
    expect(session.film.frame, 7);
    expect(
      tester.widget<LockCard>(find.byType(LockCard)).passwordController.text,
      isEmpty,
    );
  });

  for (final bool reduced in <bool>[false, true]) {
    testWidgets(
      'retains both original States through the exact 400ms handoff '
      'with motion flag $reduced',
      (
        WidgetTester tester,
      ) async {
        int done = 0;
        final StartupStageSession session = _session(() => done++);
        final GlobalKey<_HarnessState> host = await _show(
          tester,
          session,
          reduced: reduced,
        );
        final State<StatefulWidget> auth = tester.state(
          find.byType(LockTabChild),
        );
        final State<StatefulWidget> film = tester.state(
          find.byType(LaunchFilm),
        );
        await _until(tester, () => session.film.isDone);
        final Rect full = _stageRect(tester);
        await _begin(tester, host);
        expect(
          identical(tester.state(find.byType(LockTabChild)), auth),
          isTrue,
        );
        expect(identical(tester.state(find.byType(LaunchFilm)), film), isTrue);
        await tester.pump(const Duration(milliseconds: 200));
        expect(_stageRect(tester).width, lessThan(full.width));
        expect(_stageRect(tester).width, greaterThan(418));
        expect(session.interactive, isFalse);
        await tester.pump(const Duration(milliseconds: 199));
        expect(session.interactive, isFalse);
        await tester.pump(const Duration(milliseconds: 1));
        expect(session.interactive, isTrue);
        expect(session.filmInWell, isTrue);
        expect(
          tester.widget<LaunchFilm>(find.byType(LaunchFilm)).fit,
          BoxFit.contain,
        );
        expect(
          find.byKey(const ValueKey<String>('startup_stage_rect')),
          findsNothing,
        );
        expect(find.byType(LockTabChild), findsOneWidget);
        expect(find.byType(LaunchFilm), findsOneWidget);
        expect(
          identical(tester.state(find.byType(LockTabChild)), auth),
          isTrue,
        );
        expect(identical(tester.state(find.byType(LaunchFilm)), film), isTrue);
        expect(session.film.frame, 7);
        await session.unlock('Synthetic input');
        session.initialized();
        expect(host.currentState!.unlocks, <String>['Synthetic input']);
        expect(host.currentState!.initialized, 1);
        expect(done, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a resize retargets the real well without restarting400ms', (
    WidgetTester tester,
  ) async {
    final StartupStageSession session = _session(() {});
    final GlobalKey<_HarnessState> host = await _show(tester, session);
    await _until(tester, () => session.film.isDone);
    await _begin(tester, host);
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.physicalSize = const Size(1200, 600);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(session.interactive, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(session.interactive, isTrue);
    expect(tester.getSize(find.byKey(session.wellKey)).height, 118);
    expect(find.byType(LaunchFilm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second claimant cannot replace the original callbacks', (
    WidgetTester tester,
  ) async {
    final StartupStageSession session = _session(() {});
    final GlobalKey<_HarnessState> host = await _show(tester, session);
    await _until(tester, () => session.film.isDone);
    await _begin(tester, host);
    final ValueNotifier<int> replay = ValueNotifier<int>(0);
    expect(
      session.claim(
        afterUnlock: (_) async => fail('Replaced original unlock'),
        afterInit: () => fail('Replaced original init'),
        replay: replay,
      ),
      isFalse,
    );
    replay.dispose();
    await tester.pump(const Duration(milliseconds: 400));
    await session.unlock('Original callback');
    expect(host.currentState!.unlocks, <String>['Original callback']);
  });

  testWidgets('disposing a decoding stage removes only its own overlay', (
    WidgetTester tester,
  ) async {
    final StartupStageSession session = _session(
      () => fail('Disposed startup'),
      bundle: _PendingBundle(),
    );
    await _show(tester, session);
    final OverlayState overlay = Overlay.of(
      tester.element(find.byType(_Harness)),
    );
    final OverlayEntry other = OverlayEntry(
      builder: (_) => const Positioned(
        left: 0,
        top: 0,
        child: SizedBox(
          key: ValueKey<String>('independent_overlay'),
          width: 1,
          height: 1,
        ),
      ),
    );
    overlay.insert(other);
    await tester.pump();
    session.dispose();
    await tester.pump();
    expect(find.byType(LaunchFilm), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('independent_overlay')),
      findsOneWidget,
    );
    await session.unlock('Refused');
    other
      ..remove()
      ..dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing midway leaves no film and never exposes auth', (
    WidgetTester tester,
  ) async {
    final StartupStageSession session = _session(() {});
    final GlobalKey<_HarnessState> host = await _show(tester, session);
    await _until(tester, () => session.film.isDone);
    await _begin(tester, host);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(session.interactive, isFalse);
    expect(session.isClosed, isTrue);
    expect(find.byType(LaunchFilm), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
