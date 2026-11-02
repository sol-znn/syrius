import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_frame.dart';

Widget _app({
  bool light = false,
  bool rtl = false,
  bool disableAnimations = false,
  ValueChanged<SettingsSectionId>? onAction,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
  locale: rtl ? const Locale('ar') : const Locale('en'),
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: Scaffold(body: _Demo(onAction: onAction)),
);

class _Demo extends StatefulWidget {
  const _Demo({this.onAction});
  final ValueChanged<SettingsSectionId>? onAction;

  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  SettingsSectionId selected = SettingsSectionId.addresses;

  @override
  Widget build(BuildContext context) => SettingsFrame(
    selected: selected,
    onSelected: (SettingsSectionId value) => setState(() => selected = value),
    child: Center(
      key: const Key('settings_page'),
      child: TextButton(
        key: ValueKey<String>('action_${selected.name}'),
        onPressed: () => widget.onAction?.call(selected),
        child: Text('Page ${selected.name}'),
      ),
    ),
  );
}

Finder _section(SettingsSectionId section) =>
    find.byKey(ValueKey<String>('settings_${section.name}'));

Material _surface(WidgetTester tester, SettingsSectionId section) =>
    tester.widget<Material>(
      find
          .ancestor(of: _section(section), matching: find.byType(Material))
          .first,
    );

void _window(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final bool rtl in <bool>[false, true]) {
      testWidgets(
        'seven sections keep the drawn frame, light $light, RTL $rtl',
        (
          WidgetTester tester,
        ) async {
          _window(tester);
          await tester.pumpWidget(_app(light: light, rtl: rtl));
          await tester.pumpAndSettle();
          final Rect menu = tester.getRect(
            find.byKey(const Key('settings_section_menu')),
          );
          final Rect page = tester.getRect(
            find.byKey(const Key('settings_page')),
          );
          expect(menu.width, 200);
          expect(menu.height, 600);
          expect(rtl ? menu.left - page.right : page.left - menu.right, 12);
          final List<Rect> rows = <Rect>[
            for (final SettingsSectionId section in SettingsSectionId.values)
              tester.getRect(_section(section)),
          ];
          expect(rows.length, 7);
          for (int i = 0; i < rows.length; i++) {
            expect(rows[i].height, 38);
            if (i > 0) expect(rows[i].top, rows[i - 1].bottom);
          }
          expect(find.text('Apps'), findsOneWidget);
          expect(find.textContaining('Confirm'), findsNothing);
          expect(
            _surface(tester, SettingsSectionId.addresses).color,
            light ? AppTokens.light.card2 : AppTokens.dark.card2,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Apps is reachable from the section menu by keyboard', (
    WidgetTester tester,
  ) async {
    _window(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    for (int i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Page apps'), findsOneWidget);
    expect(find.text('Page addresses'), findsNothing);
    expect(
      _surface(tester, SettingsSectionId.apps).color,
      AppTokens.dark.card2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the outgoing section rejects actions during its visible exit', (
    WidgetTester tester,
  ) async {
    _window(tester);
    final List<SettingsSectionId> actions = <SettingsSectionId>[];
    await tester.pumpWidget(_app(onAction: actions.add));
    await tester.pumpAndSettle();
    final Offset oldAction = tester.getCenter(
      find.byKey(const Key('action_addresses')),
    );
    await tester.tap(_section(SettingsSectionId.apps));
    await tester.pump();
    expect(find.text('Page addresses'), findsOneWidget);
    await tester.tapAt(oldAction);
    await tester.pump();
    expect(actions, isEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Page addresses'), findsNothing);
    await tester.tap(find.byKey(const Key('action_apps')));
    expect(actions, <SettingsSectionId>[SettingsSectionId.apps]);
  });

  for (final (bool, bool) flags in <(bool, bool)>[
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
      'selection retains 150 ms with independent motion flags $flags',
      (
        WidgetTester tester,
      ) async {
        _window(tester);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: flags.$1);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(_app(disableAnimations: flags.$2));
        await tester.pumpAndSettle();
        await tester.tap(_section(SettingsSectionId.apps));
        await tester.pump();
        final Color off = AppTokens.dark.card2.withValues(alpha: 0);
        expect(_surface(tester, SettingsSectionId.apps).color, off);
        await tester.pump(const Duration(milliseconds: 75));
        expect(
          _surface(tester, SettingsSectionId.apps).color,
          Color.lerp(
            off,
            AppTokens.dark.card2,
            AppTokens.dark.ease.transform(0.5),
          ),
        );
        await tester.pump(const Duration(milliseconds: 74));
        expect(
          _surface(tester, SettingsSectionId.apps).color,
          isNot(AppTokens.dark.card2),
        );
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          _surface(tester, SettingsSectionId.apps).color,
          AppTokens.dark.card2,
        );
        await tester.pumpAndSettle();
      },
    );
  }
}
