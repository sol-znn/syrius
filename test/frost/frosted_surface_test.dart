import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

Widget _app(Widget child, {bool light = false}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  home: Scaffold(body: Center(child: child)),
);

Finder _filters(Finder surface) => find.descendant(
  of: surface,
  matching: find.byType(BackdropFilter),
);

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets('dialog glass follows the ${light ? 'light' : 'dark'} tokens', (
      WidgetTester tester,
    ) async {
      final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
      await tester.pumpWidget(
        _app(
          const DialogCard(title: 'Send', body: Text('Send 1 ZNN?')),
          light: light,
        ),
      );
      await tester.pumpAndSettle();
      final Finder surface = find.byType(FrostedSurface);
      final Finder filter = _filters(surface);
      expect(filter, findsOneWidget);
      expect(
        tester.widget<BackdropFilter>(filter).filter,
        ImageFilter.blur(sigmaX: tokens.dialogBlur, sigmaY: tokens.dialogBlur),
      );
      final ClipRRect clip = tester.widget<ClipRRect>(
        find.descendant(of: surface, matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, BorderRadius.circular(tokens.dialogRadius));
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: surface, matching: find.byType(ColoredBox)),
            )
            .color,
        tokens.glass,
      );
      expect(
        tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
        Colors.transparent,
      );
      final Iterable<BoxDecoration> decorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((DecoratedBox box) => box.decoration)
          .whereType<BoxDecoration>();
      expect(
        decorations.any(
          (BoxDecoration value) =>
              value.boxShadow?.contains(tokens.dialogShadow) ?? false,
        ),
        isTrue,
      );
      expect(
        decorations.any(
          (BoxDecoration value) =>
              value.border == Border.all(color: tokens.line),
        ),
        isTrue,
      );
      expect(
        decorations.any(
          (BoxDecoration value) =>
              value.border == Border(top: tokens.glassTopEdge),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disjoint surfaces share one backdrop only when requested', (
    WidgetTester tester,
  ) async {
    const Key left = Key('left');
    const Key right = Key('right');
    const Key independent = Key('independent');
    await tester.pumpWidget(
      _app(
        BackdropGroup(
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FrostedSurface(
                key: left,
                grouped: true,
                child: SizedBox(width: 80, height: 80),
              ),
              SizedBox(width: 20),
              FrostedSurface(
                key: right,
                grouped: true,
                child: SizedBox(width: 80, height: 80),
              ),
              FrostedSurface(
                key: independent,
                child: SizedBox(width: 80, height: 80),
              ),
            ],
          ),
        ),
      ),
    );
    RenderBackdropFilter render(Key key) =>
        tester.renderObject<RenderBackdropFilter>(
          _filters(find.byKey(key)),
        );
    expect(render(left).backdropKey, isNotNull);
    expect(render(right).backdropKey, same(render(left).backdropKey));
    // The default stays independent even inside a group. This is what an
    // overlapping dialog and its full-window barrier require.
    expect(render(independent).backdropKey, isNull);
    expect(tester.getSize(find.byKey(left)), const Size(80, 80));
  });

  testWidgets('a zero blur remains clipped and preserves child input', (
    WidgetTester tester,
  ) async {
    int presses = 0;
    await tester.pumpWidget(
      _app(
        FrostedSurface(
          sigma: 0,
          borderRadius: BorderRadius.circular(24),
          child: TextButton(
            onPressed: () => presses++,
            child: const Text('Continue'),
          ),
        ),
      ),
    );
    final Finder surface = find.byType(FrostedSurface);
    expect(tester.widget<BackdropFilter>(_filters(surface)).enabled, isFalse);
    expect(
      tester
          .widget<ClipRRect>(
            find.descendant(of: surface, matching: find.byType(ClipRRect)),
          )
          .borderRadius,
      BorderRadius.circular(24),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(presses, 1);
  });
}
