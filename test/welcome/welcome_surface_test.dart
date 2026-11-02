import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/hero_field.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

import 'support.dart';

const List<String> _actions = <String>['create', 'import', 'hardware'];

Finder _action(String name) => find.byKey(Key('welcome_$name'));

Finder _icon(String name) => find.descendant(
  of: _action(name),
  matching: find.byWidgetPredicate(
    (Widget widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
  ),
);

Finder _rowMotion(String name, Type type) => find.descendant(
  of: find.byKey(ValueKey<String>('welcome_${name}_entrance')),
  matching: find.byType(type),
);

double _opacity(WidgetTester tester, String name) =>
    tester.widget<Opacity>(_rowMotion(name, Opacity).first).opacity;

double _rise(WidgetTester tester, String name) => tester
    .widget<Transform>(_rowMotion(name, Transform).first)
    .transform
    .storage[13];

void _expectProgress(WidgetTester tester, String name, int elapsed) {
  final double time = (elapsed / 320).clamp(0.0, 1.0);
  final double progress = const Cubic(0.2, 0.8, 0.2, 1).transform(time);
  expect(_opacity(tester, name), closeTo(progress, 0.001));
  expect(_rise(tester, name), closeTo(6 * (1 - progress), 0.01));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final FontLoader fonts = FontLoader(kSansFontFamily);
    for (final String asset in const <String>[
      'assets/fonts/SpaceGrotesk-Regular.ttf',
      'assets/fonts/SpaceGrotesk-Medium.ttf',
      'assets/fonts/SpaceGrotesk-SemiBold.ttf',
      'assets/fonts/SpaceGrotesk-Bold.ttf',
    ]) {
      fonts.addFont(rootBundle.load(asset));
    }
    await fonts.load();
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'the ${light ? 'light' : 'dark'} layout keeps the original crop',
      (
        WidgetTester tester,
      ) async {
        prepareWelcomeViewport(tester);
        final List<WelcomeDestination> calls = <WelcomeDestination>[];
        await tester.pumpWidget(
          welcomeHost(
            welcomeFixture(source: Object(), onSelected: calls.add),
            light: light,
          ),
        );
        await finishWelcomeEntrance(tester);

        final Rect globe = tester.getRect(
          find.byKey(const Key('welcome_globe_viewport')),
        );
        final Rect composition = tester.getRect(
          find.byKey(const Key('welcome_globe_composition')),
        );
        final Rect column = tester.getRect(
          find.byKey(const Key('welcome_action_column')),
        );
        expect(globe.size, const Size(470, 470));
        expect(composition.size, const Size(836, 470));
        expect(composition.center, globe.center);
        expect(column.width, 400);
        expect(column.left - globe.right, 36);
        expect(column.center.dy, globe.center.dy);
        expect(find.byKey(const Key('welcome_wide_layout')), findsOneWidget);

        for (final String name in _actions) {
          expect(tester.getSize(_action(name)), const Size(400, 70));
          expect(tester.getSize(_icon(name)), const Size(40, 40));
        }
        expect(
          tester.getTopLeft(_action('import')).dy -
              tester.getBottomLeft(_action('create')).dy,
          12,
        );
        expect(
          find.text('A seed, or a wallet file dropped here'),
          findsOneWidget,
        );
        expect(find.byType(AppLottie), findsNothing);
        expect(find.byType(HeroField), findsNothing);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the ${light ? 'light' : 'dark'} rows keep one plasma fill', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      await tester.pumpWidget(
        welcomeHost(
          welcomeFixture(source: Object(), onSelected: (_) {}),
          light: light,
        ),
      );
      await finishWelcomeEntrance(tester);
      final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
      final List<BoxDecoration> marks = <BoxDecoration>[
        for (final String name in _actions)
          tester.widget<Container>(_icon(name)).decoration! as BoxDecoration,
      ];
      expect(
        marks.where((BoxDecoration mark) => mark.gradient != null),
        hasLength(1),
      );
      expect(marks[0].gradient, tokens.plasma);
      expect(marks[1].color, tokens.card2);
      expect(marks[2].color, tokens.card2);
      final InkWell row = tester.widget<InkWell>(_action('create'));
      expect(row.hoverColor, tokens.hover);
      expect(row.mouseCursor, SystemMouseCursors.click);
    });
  }

  testWidgets('only the selected destination is requested by each row', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: calls.add)),
    );
    await finishWelcomeEntrance(tester);
    for (final String name in _actions) {
      await tester.tap(_action(name));
      await tester.pump();
    }
    expect(calls, WelcomeDestination.values);
    expect(find.byType(AppLottie), findsNothing);
    expect(find.byType(HeroField), findsNothing);
  });

  testWidgets('Tab, Enter and Space select the three entry requests', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: calls.add)),
    );
    await finishWelcomeEntrance(tester);
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    expect(calls, WelcomeDestination.values);
  });

  testWidgets('keyboard focus paints its ring without moving the row', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: (_) {})),
    );
    await finishWelcomeEntrance(tester);
    final Rect before = tester.getRect(_action('create'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final AnimatedContainer outline = tester.widget<AnimatedContainer>(
      find.descendant(
        of: _action('create'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final BoxDecoration decoration =
        outline.foregroundDecoration! as BoxDecoration;
    expect(decoration.border!.top.color, AppTokens.dark.focusRing);
    expect(tester.getRect(_action('create')), before);
  });

  testWidgets('rows enter 40 ms apart and keep the 320 ms rise with OS flags', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(source: Object(), onSelected: calls.add),
        disableAnimations: true,
      ),
    );
    for (final String name in _actions) {
      _expectProgress(tester, name, 0);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 20));
    _expectProgress(tester, 'create', 20);
    _expectProgress(tester, 'import', 0);
    _expectProgress(tester, 'hardware', 0);
    await tester.pump(const Duration(milliseconds: 40));
    _expectProgress(tester, 'create', 60);
    _expectProgress(tester, 'import', 20);
    _expectProgress(tester, 'hardware', 0);
    await tester.pump(const Duration(milliseconds: 340));
    for (final String name in _actions) {
      _expectProgress(tester, name, 320);
    }
    await tester.pump(const Duration(microseconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a source replacement revokes every saved destination callback', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    final ValueChanged<WelcomeDestination> selected = calls.add;
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: selected)),
    );
    await finishWelcomeEntrance(tester);
    final List<VoidCallback> saved = <VoidCallback>[
      for (final String name in _actions) savedWelcomeAction(tester, name),
    ];
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: selected)),
    );
    for (final VoidCallback callback in saved) {
      callback();
    }
    expect(calls, isEmpty);
    savedWelcomeAction(tester, 'import')();
    expect(calls, <WelcomeDestination>[WelcomeDestination.importWallet]);
  });

  testWidgets('a callback replacement cannot redirect an earlier press', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final Object source = Object();
    final List<WelcomeDestination> first = <WelcomeDestination>[];
    final List<WelcomeDestination> second = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: source, onSelected: first.add)),
    );
    await finishWelcomeEntrance(tester);
    final VoidCallback saved = savedWelcomeAction(tester, 'hardware');
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: source, onSelected: second.add)),
    );
    saved();
    expect(first, isEmpty);
    expect(second, isEmpty);
    savedWelcomeAction(tester, 'hardware')();
    expect(second, <WelcomeDestination>[WelcomeDestination.hardwareWallet]);
  });

  testWidgets('a route cover revokes callbacks before and after return', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(source: Object(), onSelected: calls.add),
        navigatorKey: navigator,
      ),
    );
    await finishWelcomeEntrance(tester);
    final VoidCallback saved = savedWelcomeAction(tester, 'create');
    final MaterialPageRoute<void> cover = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Fixture cover')),
    );
    navigator.currentState!.push<void>(cover);
    saved();
    expect(calls, isEmpty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    saved();
    expect(calls, isEmpty);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    saved();
    expect(calls, isEmpty);
    savedWelcomeAction(tester, 'create')();
    expect(calls, <WelcomeDestination>[WelcomeDestination.createWallet]);
    for (final String name in _actions) {
      _expectProgress(tester, name, 320);
    }
  });

  testWidgets('a hidden ticker branch revokes callbacks and keeps art paused', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final Object source = Object();
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    final ValueChanged<WelcomeDestination> selected = calls.add;
    Widget host({required bool enabled}) => welcomeHost(
      welcomeFixture(source: source, onSelected: selected),
      enabled: enabled,
    );
    await tester.pumpWidget(host(enabled: true));
    await finishWelcomeEntrance(tester);
    final VoidCallback saved = savedWelcomeAction(tester, 'import');
    await tester.pumpWidget(host(enabled: false));
    saved();
    expect(calls, isEmpty);
    expect(
      TickerMode.valuesOf(
        tester.element(find.byKey(const Key('fixture_globe'))),
      ).enabled,
      isFalse,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpWidget(host(enabled: true));
    saved();
    expect(calls, isEmpty);
    savedWelcomeAction(tester, 'import')();
    expect(calls, <WelcomeDestination>[WelcomeDestination.importWallet]);
  });

  testWidgets('an admitted route request refuses a repeated saved press', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(
          source: Object(),
          onSelected: (WelcomeDestination destination) {
            calls.add(destination);
            navigator.currentState!.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Fixture route')),
              ),
            );
          },
        ),
        navigatorKey: navigator,
      ),
    );
    await finishWelcomeEntrance(tester);
    final VoidCallback saved = savedWelcomeAction(tester, 'create');
    saved();
    saved();
    expect(calls, <WelcomeDestination>[WelcomeDestination.createWallet]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Fixture route'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    saved();
    expect(calls, hasLength(1));
  });

  testWidgets('a dialog cover revokes every earlier row callback on return', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(source: Object(), onSelected: calls.add),
        navigatorKey: navigator,
      ),
    );
    await finishWelcomeEntrance(tester);
    final List<VoidCallback> saved = <VoidCallback>[
      for (final String name in _actions) savedWelcomeAction(tester, name),
    ];
    final Future<void> dismissed = showDialog<void>(
      context: tester.element(find.byKey(const Key('welcome_screen_marker'))),
      builder: (_) => const AlertDialog(content: Text('Fixture dialog')),
    );
    for (final VoidCallback callback in saved) {
      callback();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, isEmpty);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await dismissed;
    for (final VoidCallback callback in saved) {
      callback();
    }
    expect(calls, isEmpty);
    savedWelcomeAction(tester, 'import')();
    expect(calls, <WelcomeDestination>[WelcomeDestination.importWallet]);
  });

  testWidgets('a parent focus barrier refuses saved callbacks and keyboard', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final FocusNode parent = FocusNode(debugLabel: 'Fixture parent');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      parent.dispose();
    });
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(
        Focus(
          focusNode: parent,
          child: welcomeFixture(source: Object(), onSelected: calls.add),
        ),
      ),
    );
    await finishWelcomeEntrance(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final VoidCallback saved = savedWelcomeAction(tester, 'create');
    parent.descendantsAreFocusable = false;
    saved();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, isEmpty);
    parent.descendantsAreFocusable = true;
    await tester.pump();
    saved();
    expect(calls, isEmpty);
    savedWelcomeAction(tester, 'create')();
    expect(calls, <WelcomeDestination>[WelcomeDestination.createWallet]);
  });

  testWidgets('losing foreground ownership permanently revokes saved presses', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: calls.add)),
    );
    await finishWelcomeEntrance(tester);
    final VoidCallback saved = savedWelcomeAction(tester, 'hardware');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    saved();
    expect(calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    saved();
    expect(calls, isEmpty);
    savedWelcomeAction(tester, 'hardware')();
    expect(calls, <WelcomeDestination>[WelcomeDestination.hardwareWallet]);
  });

  testWidgets('disposal revokes callbacks without opening a destination', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: Object(), onSelected: calls.add)),
    );
    await finishWelcomeEntrance(tester);
    final List<VoidCallback> saved = <VoidCallback>[
      for (final String name in _actions) savedWelcomeAction(tester, name),
    ];
    await tester.pumpWidget(const SizedBox.shrink());
    for (final VoidCallback callback in saved) {
      callback();
    }
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('text grows in a narrow short window and every action scrolls', (
    WidgetTester tester,
  ) async {
    const Size size = Size(600, 380);
    prepareWelcomeViewport(tester, size: size);
    final List<WelcomeDestination> calls = <WelcomeDestination>[];
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(source: Object(), onSelected: calls.add),
        size: size,
        scale: 2.5,
      ),
    );
    await finishWelcomeEntrance(tester);
    expect(find.byKey(const Key('welcome_stacked_layout')), findsOneWidget);
    for (final String name in _actions) {
      expect(tester.getSize(_action(name)).height, greaterThan(70));
      await tester.ensureVisible(_action(name));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_action(name));
    }
    expect(calls, WelcomeDestination.values);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL mirrors the entry columns and keeps all action text', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(source: Object(), onSelected: (_) {}),
        rtl: true,
      ),
    );
    await finishWelcomeEntrance(tester);
    final Rect globe = tester.getRect(
      find.byKey(const Key('welcome_globe_viewport')),
    );
    final Rect column = tester.getRect(
      find.byKey(const Key('welcome_action_column')),
    );
    expect(globe.left - column.right, 36);
    for (final String name in _actions) {
      expect(tester.getSize(_action(name)), const Size(400, 70));
    }
    expect(find.text('A seed, or a wallet file dropped here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resize and theme rebuild do not replay the list entrance', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final Object source = Object();
    void selected(WelcomeDestination _) {}
    await tester.pumpWidget(
      welcomeHost(welcomeFixture(source: source, onSelected: selected)),
    );
    await finishWelcomeEntrance(tester);
    const Size smaller = Size(800, 600);
    tester.view.physicalSize = smaller;
    await tester.pumpWidget(
      welcomeHost(
        welcomeFixture(source: source, onSelected: selected),
        light: true,
        size: smaller,
      ),
    );
    for (final String name in _actions) {
      _expectProgress(tester, name, 320);
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });
}
