import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/toast_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/event_toast.dart';

Widget _app(
  WidgetBuilder body, {
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (BuildContext context, Widget? child) =>
      Directionality(textDirection: direction, child: child!),
  home: Scaffold(body: Builder(builder: body)),
);

Future<void> _showFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a new event replaces both pending and mounted entries', (
    WidgetTester tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _app((BuildContext value) {
        context = value;
        return const SizedBox.expand();
      }),
    );
    ToastUtils.showToast(context, 'First');
    ToastUtils.showToast(context, 'Second');
    await _showFrame(tester);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byType(EventToast), findsOneWidget);
    ToastUtils.showToast(context, 'Third');
    await _showFrame(tester);
    expect(find.text('Second'), findsNothing);
    expect(find.text('Third'), findsOneWidget);
    expect(find.byType(EventToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.byType(EventToast), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final bool beforeFrame in <bool>[false, true]) {
    testWidgets(
      'owner destruction releases the entry, beforeFrame $beforeFrame',
      (
        WidgetTester tester,
      ) async {
        late BuildContext context;
        Widget page() => _app((BuildContext value) {
          context = value;
          return const SizedBox.expand();
        });
        await tester.pumpWidget(page());
        ToastUtils.showToast(context, 'Old owner');
        if (!beforeFrame) await _showFrame(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(page());
        ToastUtils.showToast(context, 'New owner');
        await _showFrame(tester);
        expect(find.text('Old owner'), findsNothing);
        expect(find.text('New owner'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(EventToast), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('late clipboard completion ignores an unmounted context', (
    WidgetTester tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _app((BuildContext value) {
        context = value;
        return const SizedBox.expand();
      }),
    );
    await tester.pumpWidget(const SizedBox());
    ToastUtils.showToast(context, 'Copied');
    await tester.pump();
    expect(find.byType(EventToast), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final TextDirection direction in TextDirection.values) {
    testWidgets(
      'the ${direction.name} card leaves the page outside it reachable',
      (
        WidgetTester tester,
      ) async {
        late BuildContext context;
        int presses = 0;
        await tester.pumpWidget(
          _app((BuildContext value) {
            context = value;
            return Stack(
              children: <Widget>[
                PositionedDirectional(
                  top: 44,
                  start: 0,
                  child: TextButton(
                    key: const Key('same_row'),
                    onPressed: () => presses++,
                    child: const Text('Page'),
                  ),
                ),
                PositionedDirectional(
                  bottom: 0,
                  start: 0,
                  child: TextButton(
                    key: const Key('below'),
                    onPressed: () => presses++,
                    child: const Text('Below'),
                  ),
                ),
              ],
            );
          }, direction: direction),
        );
        const Color accent = Color(0xFF123456);
        ToastUtils.showToast(context, 'Copied', color: accent);
        await _showFrame(tester);
        final Rect toast = tester.getRect(find.byType(EventToast));
        expect(toast.top, 44);
        expect(toast.width, 300);
        expect(
          direction == TextDirection.ltr ? toast.right : toast.left,
          direction == TextDirection.ltr ? 776 : 24,
        );
        expect(
          tester.widget<EventToast>(find.byType(EventToast)).accent,
          accent,
        );
        await tester.tap(find.byKey(const Key('same_row')));
        await tester.tap(find.byKey(const Key('below')));
        expect(presses, 2);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
