import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/event_toast.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

Widget _app(
  Widget toast, {
  bool light = false,
  bool? disableAnimations,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topCenter, child: toast),
  ),
);

Finder get _bar => find.descendant(
  of: find.byType(EventToast),
  matching: find.byType(FractionallySizedBox),
);

double _remaining(WidgetTester tester) =>
    tester.widget<FractionallySizedBox>(_bar).widthFactor!;

double _rise(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(EventToast),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[13];

void main() {
  for (final bool platform in <bool>[false, true]) {
    for (final bool mediaQuery in <bool>[false, true]) {
      testWidgets('300 ms rise and five-second drain, platform $platform, '
          'MediaQuery $mediaQuery', (WidgetTester tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: platform);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        int dismissed = 0;
        await tester.pumpWidget(
          _app(
            EventToast(message: 'Copied', onDismiss: () => dismissed++),
            disableAnimations: mediaQuery,
          ),
        );
        expect(_rise(tester), 6);
        expect(_remaining(tester), 1);
        await tester.pump(const Duration(milliseconds: 150));
        expect(
          _rise(tester),
          closeTo(6 * (1 - AppTokens.dark.spring.transform(0.5)), 1e-6),
        );
        expect(_remaining(tester), closeTo(0.97, 1e-9));
        await tester.pump(const Duration(milliseconds: 149));
        expect(_rise(tester), greaterThan(0));
        await tester.pump(const Duration(milliseconds: 1));
        expect(_rise(tester), 0);
        await tester.pump(const Duration(milliseconds: 2200));
        expect(_remaining(tester), closeTo(0.5, 1e-9));
        await tester.pump(const Duration(milliseconds: 2499));
        expect(find.text('Copied'), findsOneWidget);
        expect(_remaining(tester), greaterThan(0));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        expect(find.text('Copied'), findsNothing);
        expect(dismissed, 1);
        await tester.pump(const Duration(seconds: 6));
        expect(dismissed, 1);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets('hover and focus preserve only the remaining time', (
    WidgetTester tester,
  ) async {
    int dismissed = 0;
    await tester.pumpWidget(
      _app(EventToast(message: 'Copied', onDismiss: () => dismissed++)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(_remaining(tester), closeTo(0.6, 1e-9));
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(5, 500));
    await mouse.moveTo(tester.getCenter(find.byType(EventToast)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    expect(_remaining(tester), closeTo(0.6, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await mouse.moveTo(const Offset(5, 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    expect(_remaining(tester), closeTo(0.6, 1e-9));
    tester.binding.focusManager.primaryFocus!.unfocus();
    await tester.pump();
    // Focus changes settle after the frame. Stamp the resumed clock before
    // advancing fake time, as a real next frame does.
    await tester.pump();
    expect(_remaining(tester), closeTo(0.6, 1e-9));
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(microseconds: 1));
    expect(find.text('Copied'), findsNothing);
    expect(dismissed, 1);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape hides the focused toast and a new message restarts it', (
    WidgetTester tester,
  ) async {
    int dismissed = 0;
    EventToast toast(String message) =>
        EventToast(message: message, onDismiss: () => dismissed++);
    await tester.pumpWidget(_app(toast('First')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(dismissed, 1);
    await tester.pumpWidget(_app(toast('Second')));
    await tester.pump(const Duration(milliseconds: 4999));
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(microseconds: 1));
    expect(find.text('Second'), findsNothing);
    expect(dismissed, 2);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('the themed card drains from the reading start, light $light', (
      WidgetTester tester,
    ) async {
      final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
      final TextDirection direction = light
          ? TextDirection.rtl
          : TextDirection.ltr;
      int dismissed = 0;
      await tester.pumpWidget(
        _app(
          EventToast(
            message: 'Incoming',
            detail: 'Address 2',
            onDismiss: () => dismissed++,
          ),
          light: light,
          direction: direction,
        ),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      expect(tester.getSize(find.byType(EventToast)).width, 300);
      expect(
        tester.widget<Text>(find.text('Incoming')).style!.color,
        tokens.foreground,
      );
      final Finder surface = find.byType(FrostedSurface);
      expect(tester.widget<FrostedSurface>(surface).sigma, tokens.panelBlur);
      expect(
        tester
            .widget<ColoredBox>(
              find
                  .descendant(of: surface, matching: find.byType(ColoredBox))
                  .first,
            )
            .color,
        tokens.glass,
      );
      final Rect bar = tester.getRect(_bar);
      final Rect fill = tester.getRect(
        find.descendant(of: _bar, matching: find.byType(ColoredBox)),
      );
      expect(fill.width, closeTo(bar.width / 2, 1e-6));
      expect(light ? fill.right : fill.left, light ? bar.right : bar.left);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(find.text('Incoming'), findsNothing);
      expect(dismissed, 1);
      await tester.pump(const Duration(seconds: 6));
      expect(dismissed, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
