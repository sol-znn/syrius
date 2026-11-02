import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';

Widget _app(
  ValueNotifier<bool> choice, {
  bool light = false,
  bool rtl = false,
  bool disableAnimations = false,
  bool enabled = true,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: Directionality(
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      body: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: choice,
          builder: (_, bool value, _) => SettingsSwitch(
            value: value,
            label: 'Example setting',
            onChanged: enabled ? (bool next) => choice.value = next : null,
          ),
        ),
      ),
    ),
  ),
);

Color? _trackColour(WidgetTester tester) =>
    (tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('settings_switch_track')),
                )
                .decoration
            as ShapeDecoration)
        .color;

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final (bool, bool) flags in <(bool, bool)>[
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      testWidgets('switch clocks stay 150/180 ms, light $light, flags $flags', (
        WidgetTester tester,
      ) async {
        final ValueNotifier<bool> choice = ValueNotifier<bool>(false);
        addTearDown(choice.dispose);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: flags.$1);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(
          _app(choice, light: light, disableAnimations: flags.$2),
        );
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Finder thumb = find.byKey(const Key('settings_switch_thumb'));
        final Finder track = find.byKey(const Key('settings_switch_track'));
        final Rect off = tester.getRect(thumb);
        expect(tester.getSize(track), const Size(38, 22));
        expect(off.size, const Size(16, 16));
        expect(_trackColour(tester), tokens.line);
        await tester.tap(find.byType(SettingsSwitch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(
          _trackColour(tester),
          Color.lerp(tokens.line, tokens.znn, tokens.ease.transform(0.5)),
        );
        expect(
          tester.getTopLeft(thumb).dx - off.left,
          closeTo(16 * tokens.spring.transform(75 / 180), 0.001),
        );
        await tester.pump(const Duration(milliseconds: 75));
        expect(_trackColour(tester), tokens.znn);
        expect(tester.getTopLeft(thumb).dx - off.left, lessThan(16));
        await tester.pump(const Duration(milliseconds: 30, microseconds: 1));
        expect(tester.getTopLeft(thumb).dx - off.left, 16);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'keyboard and semantics operate once and disabled input refuses',
    (
      WidgetTester tester,
    ) async {
      final ValueNotifier<bool> choice = ValueNotifier<bool>(false);
      addTearDown(choice.dispose);
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_app(choice));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(choice.value, isTrue);
        expect(find.semantics.byLabel('Example setting'), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(SettingsSwitch)),
          matchesSemantics(
            label: 'Example setting',
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            isFocused: true,
            hasTapAction: true,
          ),
        );
        await tester.pumpWidget(_app(choice, enabled: false));
        await tester.tap(find.byType(SettingsSwitch), warnIfMissed: false);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(choice.value, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('RTL mirrors the thumb and an external change keeps its clock', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<bool> choice = ValueNotifier<bool>(false);
    addTearDown(choice.dispose);
    await tester.pumpWidget(_app(choice, rtl: true));
    final Finder thumb = find.byKey(const Key('settings_switch_thumb'));
    final double start = tester.getTopLeft(thumb).dx;
    choice.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      start - tester.getTopLeft(thumb).dx,
      closeTo(16 * AppTokens.dark.spring.transform(0.5), 0.001),
    );
    choice.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(thumb).dx, start);
  });
}
