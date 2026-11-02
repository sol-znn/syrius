import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

const Key _toggle = ValueKey<String>('rail_toggle');
const Key _pill = Key('rail_pill');
const Key _page = Key('page');
const Key _dot = ValueKey<String>('rail_unseen_dot');
const EdgeInsets _shellPadding = EdgeInsets.fromLTRB(10, 14, 18, 18);

Key _nav(Tabs tab) => ValueKey<String>('nav_${tab.name}');
Key _icon(Tabs tab) => ValueKey<String>('rail_icon_${tab.name}');
Key _label(Tabs tab) => ValueKey<String>('rail_label_${tab.name}');

Finder _semantic(String name) => find.byWidgetPredicate(
  (Widget widget) => widget is Semantics && widget.properties.label == name,
);

String? _tooltipMessage(Tooltip tooltip) =>
    tooltip.message ?? (tooltip.richMessage as TextSpan?)?.semanticsLabel;

Finder _tooltip(String name, [String? shortcut]) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Tooltip &&
      _tooltipMessage(widget) != null &&
      (_tooltipMessage(widget) == name ||
          _tooltipMessage(widget)!.startsWith('$name  ')) &&
      (shortcut == null || _tooltipMessage(widget)!.contains(shortcut)),
);

Finder _shownTooltip(String name) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is RichText &&
      widget.text
          .toPlainText(includeSemanticsLabels: false)
          .startsWith('$name\uFFFC'),
);

Widget _host({
  required RailCollapse collapse,
  Tabs selected = Tabs.dashboard,
  bool locked = false,
  bool light = false,
  bool hasUnseen = false,
  TextDirection direction = TextDirection.ltr,
  ValueChanged<Tabs>? onSelected,
  VoidCallback? onNotifications,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Padding(
        padding: _shellPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ShellRail(
              collapse: collapse,
              selected: selected,
              locked: locked,
              onSelected: onSelected ?? (Tabs _) {},
              onNotifications: onNotifications,
              hasUnseen: hasUnseen,
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.expand(key: _page)),
          ],
        ),
      ),
    ),
  ),
);

Rect _rail(WidgetTester tester) => tester.getRect(find.byType(ShellRail));

Finder _labels() =>
    find.descendant(of: find.byType(ShellRail), matching: find.byType(Text));

double _labelOpacity(WidgetTester tester, Tabs tab) => tester
    .widget<Opacity>(
      find
          .ancestor(of: find.byKey(_label(tab)), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

RailCollapse _choice({bool open = false}) {
  final RailCollapse collapse = RailCollapse();
  addTearDown(collapse.dispose);
  if (open) collapse.setCollapsed(collapsed: false);
  return collapse;
}

Future<void> _preferencesInMemory() async {
  await Hive.openBox<dynamic>(kSharedPrefsBox, bytes: Uint8List(0));
  sharedPrefsService = await SharedPrefsService.getInstance();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('syrius_rail_');
    Hive.init(dir.path);
    sharedPrefsService = null;
  });

  tearDown(() async {
    await Hive.close();
    sharedPrefsService = null;
    dir.deleteSync(recursive: true);
  });

  group('the stored choice', () {
    test('works in memory before preferences exist', () {
      final RailCollapse collapse = _choice();
      expect(collapse.value, isTrue);
      collapse.setCollapsed(collapsed: false);
      expect(collapse.value, isFalse);
      collapse.toggle();
      expect(collapse.value, isTrue);
    });

    test('the explicit setter notifies only when the choice changes', () {
      int notifications = 0;
      final RailCollapse collapse = _choice()
        ..addListener(() => notifications++)
        ..setCollapsed(collapsed: false)
        ..setCollapsed(collapsed: false);
      expect(collapse.value, isFalse);
      expect(notifications, 1);
    });

    test('the default does not create a stored choice', () async {
      sharedPrefsService = await SharedPrefsService.getInstance();
      expect(_choice().value, isTrue);
      expect(sharedPrefsService!.get(kRailCollapsedKey), isNull);
    });

    test('the choice survives closing and reopening its profile box', () async {
      sharedPrefsService = await SharedPrefsService.getInstance();
      final RailCollapse collapse = _choice()..setCollapsed(collapsed: false);
      await sharedPrefsService!.close();
      await sharedPrefsService!.checkIfBoxIsOpen();
      expect(sharedPrefsService!.get(kRailCollapsedKey), isFalse);
      expect(_choice().value, isFalse);
      collapse.setCollapsed(collapsed: true);
      await sharedPrefsService!.close();
      await sharedPrefsService!.checkIfBoxIsOpen();
      expect(_choice().value, isTrue);
    });

    test('a damaged entry uses the default', () async {
      await _preferencesInMemory();
      await sharedPrefsService!.put(kRailCollapsedKey, 'open');
      expect(_choice().value, isTrue);
    });

    test('a closed preferences box cannot break navigation', () async {
      sharedPrefsService = await SharedPrefsService.getInstance();
      await sharedPrefsService!.close();
      final RailCollapse collapse = _choice()..toggle();
      await Future<void>.delayed(Duration.zero);
      expect(collapse.value, isFalse);
    });
  });

  group('the rail', () {
    setUp(_preferencesInMemory);

    test('has exactly eight pages and three footer destinations', () {
      expect(
        kRailPages.map((RailEntry entry) => entry.tab),
        <Tabs>[
          Tabs.dashboard,
          Tabs.transfer,
          Tabs.staking,
          Tabs.pillars,
          Tabs.plasma,
          Tabs.tokens,
          Tabs.p2pSwap,
          Tabs.accelerator,
        ],
      );
      expect(
        railWalletEntries(onLock: false).map((RailEntry entry) => entry.tab),
        <Tabs>[Tabs.notifications, Tabs.settings, Tabs.lock],
      );
    });

    testWidgets('starts as a 56 px strip of twelve exact glyphs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(collapse: _choice()));
      final Rect rail = _rail(tester);
      expect(rail.width, 56);
      expect(rail.left, _shellPadding.left);
      expect(_labels(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ShellRail),
          matching: find.byType(SvgPicture),
        ),
        findsNWidgets(12),
      );
      for (final RailEntry entry in <RailEntry>[
        ...kRailPages,
        ...railWalletEntries(onLock: false),
      ]) {
        expect(
          tester.getCenter(find.byKey(_icon(entry.tab))).dx,
          rail.center.dx,
        );
        expect(tester.getSize(find.byKey(_nav(entry.tab))).width, 40);
      }
      expect(
        tester.getSize(find.byKey(_page)).width,
        800 - _shellPadding.horizontal - 56 - 8,
      );
      expect(find.byKey(_nav(Tabs.sentinels)), findsNothing);
      expect(find.byKey(_nav(Tabs.walletConnect)), findsNothing);
    });

    testWidgets('a stored open choice is fully visible on the first frame', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(collapse: _choice(open: true)));
      expect(_rail(tester).width, 200);
      expect(find.text('Home'), findsOneWidget);
      expect(_labelOpacity(tester, Tabs.dashboard), 1);
      expect(_tooltip('Collapse', 'Ctrl B'), findsOneWidget);
      expect(tester.getSize(find.byKey(_pill)).width, 184);
    });

    testWidgets(
      'tooltips name the eight numbered shortcuts and footer chords',
      (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(_host(collapse: _choice()));
        for (int i = 0; i < kRailPages.length; i++) {
          expect(
            _tooltip(kRailPages[i].label, 'Ctrl ${i + 1}'),
            findsOneWidget,
          );
        }
        expect(_tooltip('Expand', 'Ctrl B'), findsOneWidget);
        expect(_tooltip('Settings', 'Ctrl ,'), findsOneWidget);
        expect(_tooltip('Lock', 'Ctrl L'), findsOneWidget);
        expect(_tooltip('Notifications'), findsOneWidget);
      },
    );

    testWidgets('macOS tooltip chords use Cmd', (WidgetTester tester) async {
      await tester.pumpWidget(_host(collapse: _choice()));
      expect(_tooltip('Transfer', 'Cmd 2'), findsOneWidget);
      expect(_tooltip('Settings', 'Cmd ,'), findsOneWidget);
      expect(_tooltip('Transfer', 'Ctrl 2'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('collapsed tooltips sit beside the row towards the page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(collapse: _choice()));
      final TestGesture mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(700, 500));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_nav(Tabs.transfer))));
      await tester.pumpAndSettle();
      final Rect tip = tester.getRect(_shownTooltip('Transfer'));
      expect(tip.left, greaterThan(_rail(tester).right));
      expect(
        tip.center.dy,
        closeTo(tester.getCenter(find.byKey(_nav(Tabs.transfer))).dy, 1),
      );
    });

    testWidgets('open labels suppress duplicate floating tooltips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(collapse: _choice(open: true)));
      final TestGesture mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(700, 500));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_nav(Tabs.transfer))));
      await tester.pumpAndSettle();
      expect(find.text('Transfer'), findsOneWidget);
      expect(_shownTooltip('Transfer'), findsNothing);
    });

    testWidgets('width uses the 200 ms spring, then labels fade for 150 ms', (
      WidgetTester tester,
    ) async {
      final RailCollapse collapse = _choice();
      await tester.pumpWidget(_host(collapse: collapse));
      final double pageCollapsed = tester.getSize(find.byKey(_page)).width;
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(sharedPrefsService!.get(kRailCollapsedKey), isFalse);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _rail(tester).width,
        closeTo(56 + 144 * AppTokens.dark.spring.transform(0.25), 0.01),
      );
      expect(_labels(), findsNothing);
      await tester.pump(const Duration(milliseconds: 149));
      expect(_rail(tester).width, lessThan(200));
      expect(_labels(), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_rail(tester).width, 200);
      await tester.pump(const Duration(microseconds: 1));
      expect(_labelOpacity(tester, Tabs.dashboard), 0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(_rail(tester).width, 200);
      expect(
        _labelOpacity(tester, Tabs.dashboard),
        closeTo(AppTokens.dark.ease.transform(0.5), 0.001),
      );
      await tester.pump(const Duration(microseconds: 75001));
      expect(_labelOpacity(tester, Tabs.dashboard), 1);
      expect(tester.getSize(find.byKey(_page)).width, pageCollapsed - 144);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing hides text before the 200 ms spring narrows its box', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(collapse: _choice(open: true)));
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(_labels(), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _rail(tester).width,
        closeTo(200 - 144 * AppTokens.dark.spring.transform(0.25), 0.01),
      );
      expect(_labels(), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      expect(_rail(tester).width, 56);
      expect(_tooltip('Expand', 'Ctrl B'), findsOneWidget);
    });

    testWidgets('rapid reversal cannot leave visible labels in a narrow rail', (
      WidgetTester tester,
    ) async {
      final RailCollapse collapse = _choice();
      await tester.pumpWidget(_host(collapse: collapse));
      collapse.toggle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final double interruptedWidth = _rail(tester).width;
      collapse.toggle();
      await tester.pump();
      expect(_rail(tester).width, interruptedWidth);
      expect(_labels(), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_rail(tester).width, lessThan(interruptedWidth));
      collapse.setCollapsed(collapsed: false);
      await tester.pump();
      expect(_labels(), findsNothing);
      await tester.pumpAndSettle();
      expect(_rail(tester).width, 200);
      expect(_labelOpacity(tester, Tabs.dashboard), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('follows the Display setter and a replacement notifier', (
      WidgetTester tester,
    ) async {
      final RailCollapse first = _choice();
      await tester.pumpWidget(_host(collapse: first));
      first.setCollapsed(collapsed: false);
      await tester.pumpAndSettle();
      expect(_rail(tester).width, 200);
      final RailCollapse next = _choice()..setCollapsed(collapsed: true);
      await tester.pumpWidget(_host(collapse: next));
      await tester.pumpAndSettle();
      expect(_rail(tester).width, 56);
      first.toggle();
      await tester.pumpAndSettle();
      expect(_rail(tester).width, 56);
    });

    testWidgets('keeps both full clocks when the system disables animations', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(_host(collapse: _choice()));
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _rail(tester).width,
        closeTo(56 + 144 * AppTokens.dark.spring.transform(0.25), 0.01),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(microseconds: 1));
      expect(_labelOpacity(tester, Tabs.dashboard), 0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(_labelOpacity(tester, Tabs.dashboard), greaterThan(0));
      expect(_labelOpacity(tester, Tabs.dashboard), lessThan(1));
      await tester.pumpAndSettle();
      expect(_labelOpacity(tester, Tabs.dashboard), 1);
    });

    testWidgets('inset pills and row middles retain their hit targets', (
      WidgetTester tester,
    ) async {
      final List<Tabs> opened = <Tabs>[];
      final RailCollapse collapse = _choice();
      await tester.pumpWidget(
        _host(
          collapse: collapse,
          selected: Tabs.transfer,
          onSelected: opened.add,
        ),
      );
      expect(
        tester.getRect(find.byKey(_pill)),
        tester.getRect(find.byKey(_nav(Tabs.transfer))),
      );
      expect(tester.getSize(find.byKey(_pill)).width, 40);
      await tester.tap(find.byKey(_nav(Tabs.staking)));
      collapse.toggle();
      await tester.pumpAndSettle();
      final Rect settings = tester.getRect(find.byKey(_nav(Tabs.settings)));
      await tester.tapAt(Offset(settings.right - 2, settings.center.dy));
      expect(opened, <Tabs>[Tabs.staking, Tabs.settings]);
      expect(tester.getSize(find.byKey(_pill)).width, 184);
      expect(
        tester.getCenter(find.byKey(_icon(Tabs.transfer))).dx,
        _rail(tester).left + 28,
      );
    });

    testWidgets('legacy Sentinels navigation highlights Nodes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(collapse: _choice(), selected: Tabs.sentinels),
      );
      expect(
        tester.getRect(find.byKey(_pill)),
        tester.getRect(find.byKey(_nav(Tabs.pillars))),
      );
    });

    testWidgets('the bell defaults to navigation and can open its panel', (
      WidgetTester tester,
    ) async {
      final List<Tabs> opened = <Tabs>[];
      final RailCollapse collapse = _choice();
      await tester.pumpWidget(
        _host(collapse: collapse, onSelected: opened.add),
      );
      await tester.tap(find.byKey(_nav(Tabs.notifications)));
      expect(opened, <Tabs>[Tabs.notifications]);
      int panels = 0;
      await tester.pumpWidget(
        _host(
          collapse: collapse,
          onSelected: opened.add,
          onNotifications: () => panels++,
        ),
      );
      await tester.tap(find.byKey(_nav(Tabs.notifications)));
      expect(panels, 1);
      expect(opened, <Tabs>[Tabs.notifications]);
    });

    testWidgets('the unseen dot has source geometry and an accessible status', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        final RailCollapse collapse = _choice();
        await tester.pumpWidget(_host(collapse: collapse, hasUnseen: true));
        final Rect bell = tester.getRect(find.byKey(_nav(Tabs.notifications)));
        final Rect dot = tester.getRect(find.byKey(_dot));
        expect(dot.size, const Size(7, 7));
        expect(dot.left, bell.left + 24);
        expect(dot.top, bell.top + 10);
        expect(
          tester
              .getSemantics(_semantic('Notifications'))
              .getSemanticsData()
              .value,
          'Unseen',
        );
        await tester.pumpWidget(_host(collapse: collapse));
        expect(find.byKey(_dot), findsNothing);
        expect(
          tester
              .getSemantics(_semantic('Notifications'))
              .getSemanticsData()
              .value,
          isEmpty,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('each destination has one named semantic action', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        final List<Tabs> opened = <Tabs>[];
        await tester.pumpWidget(
          _host(collapse: _choice(), onSelected: opened.add),
        );
        expect(find.semantics.byLabel('Home'), findsOneWidget);
        final SemanticsNode transfer = tester.getSemantics(
          _semantic('Transfer'),
        );
        expect(
          transfer.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        transfer.owner!.performAction(transfer.id, ui.SemanticsAction.tap);
        expect(opened, <Tabs>[Tabs.transfer]);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('Tab focus survives expanding and Enter opens the next page', (
      WidgetTester tester,
    ) async {
      final List<Tabs> opened = <Tabs>[];
      await tester.pumpWidget(
        _host(collapse: _choice(), onSelected: opened.add),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final FocusNode? toggleFocus = primaryFocus;
      final BoxDecoration decoration =
          tester.widget<DecoratedBox>(find.descendant(
            of: find.byKey(_toggle), matching: find.byType(DecoratedBox),
          ).first).decoration
              as BoxDecoration;
      expect(
        decoration.border,
        Border.all(color: AppTokens.dark.focusRing, width: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_rail(tester).width, 200);
      expect(primaryFocus, same(toggleFocus));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened, <Tabs>[Tabs.dashboard]);
    });

    testWidgets(
      'locked navigation refuses pointer, keys and semantic actions',
      (
        WidgetTester tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          final RailCollapse collapse = _choice();
          final List<Tabs> opened = <Tabs>[];
          int panels = 0;
          await tester.pumpWidget(
            _host(
              collapse: collapse,
              selected: Tabs.lock,
              locked: true,
              onSelected: opened.add,
              onNotifications: () => panels++,
            ),
          );
          await tester.tap(find.byKey(_toggle), warnIfMissed: false);
          await tester.tap(
            find.byKey(_nav(Tabs.dashboard)),
            warnIfMissed: false,
          );
          await tester.tap(
            find.byKey(_nav(Tabs.notifications)),
            warnIfMissed: false,
          );
          for (int i = 0; i < 14; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            bool inRail = false;
            primaryFocus?.context?.visitAncestorElements((Element ancestor) {
              inRail = ancestor.widget is ShellRail;
              return !inRail;
            });
            expect(inRail, isFalse);
          }
          expect(find.semantics.byLabel('Home'), findsNothing);
          expect(find.semantics.byLabel('Notifications'), findsNothing);
          expect(collapse.value, isTrue);
          expect(opened, isEmpty);
          expect(panels, 0);
          expect(sharedPrefsService!.get(kRailCollapsedKey), isNull);
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('locking removes focus that was already inside the rail', (
      WidgetTester tester,
    ) async {
      final RailCollapse collapse = _choice(open: true);
      final List<Tabs> opened = <Tabs>[];
      await tester.pumpWidget(
        _host(collapse: collapse, onSelected: opened.add),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final FocusNode? previouslyFocused = primaryFocus;
      await tester.pumpWidget(
        _host(
          collapse: collapse,
          locked: true,
          selected: Tabs.lock,
          onSelected: opened.add,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(primaryFocus, isNot(same(previouslyFocused)));
      expect(opened, isEmpty);
      expect(collapse.value, isFalse);
    });

    testWidgets(
      'RTL mirrors the rail, fixed icon inset, labels and unseen dot',
      (
        WidgetTester tester,
      ) async {
        final RailCollapse collapse = _choice();
        await tester.pumpWidget(
          _host(
            collapse: collapse,
            direction: TextDirection.rtl,
            hasUnseen: true,
          ),
        );
        expect(_rail(tester).right, 800 - _shellPadding.right);
        expect(
          tester.getCenter(find.byKey(_icon(Tabs.dashboard))).dx,
          _rail(tester).center.dx,
        );
        final Rect bell = tester.getRect(find.byKey(_nav(Tabs.notifications)));
        expect(tester.getRect(find.byKey(_dot)).right, bell.right - 24);
        collapse.toggle();
        await tester.pumpAndSettle();
        final Rect icon = tester.getRect(find.byKey(_icon(Tabs.dashboard)));
        final Rect label = tester.getRect(find.byKey(_label(Tabs.dashboard)));
        expect(icon.center.dx, _rail(tester).right - 28);
        expect(label.right, icon.left - 12);
        expect(tester.takeException(), isNull);
      },
    );

    for (final bool light in <bool>[false, true]) {
      testWidgets(
        'fits 1200 by 600 in ${light ? 'light' : 'dark'} with either choice',
        (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = const Size(1200, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final RailCollapse collapse = _choice();
          await tester.pumpWidget(_host(collapse: collapse, light: light));
          for (final double width in <double>[56, 200]) {
            final Rect rail = _rail(tester);
            expect(rail.width, width);
            expect(tester.getRect(find.byKey(_toggle)).top, rail.top + 4);
            expect(tester.getRect(find.byKey(_toggle)).height, 32);
            expect(
              tester.getRect(find.byKey(_nav(Tabs.lock))).bottom,
              rail.bottom - 12,
            );
            Rect? previous;
            for (final RailEntry entry in <RailEntry>[
              ...kRailPages,
              ...railWalletEntries(onLock: false),
            ]) {
              final Rect row = tester.getRect(find.byKey(_nav(entry.tab)));
              expect(row.height, 40);
              if (previous != null) {
                expect(row.top - previous.bottom, greaterThanOrEqualTo(2));
              }
              previous = row;
            }
            expect(tester.takeException(), isNull);
            collapse.toggle();
            await tester.pumpAndSettle();
          }
          final BoxDecoration selected =
              tester.widget<DecoratedBox>(find.byKey(_pill)).decoration
                  as BoxDecoration;
          expect(
            selected.color,
            light ? AppTokens.light.card : AppTokens.dark.card,
          );
        },
      );
    }
  });
}
