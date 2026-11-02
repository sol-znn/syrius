import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

Widget _host({
  bool light = false,
  TextDirection direction = TextDirection.ltr,
  bool mediaQuery = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: mediaQuery),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => TextButton(
        onPressed: () => showGoToPalette<int>(
          context: context,
          entries: <GoToEntry<int>>[
            GoToEntry<int>(
              id: 'page',
              value: 1,
              label: 'Delegation',
              detail: 'Nodes',
              shortcut: 'Ctrl 4',
              icon: Icons.home,
              iconBuilder: (BuildContext context, Color color) => Icon(
                Icons.layers_outlined,
                key: const Key('original_mark'),
                color: color,
              ),
            ),
            const GoToEntry<int>(
              id: 'contact',
              value: 2,
              label: 'Sample contact',
              identifier: 'z1same00000000000000000000000000000000tail',
              detail: 'Send to',
              category: GoToCategory.addresses,
            ),
          ],
        ),
        child: const Text('Open'),
      ),
    ),
  ),
);

Finder _filter(Finder owner) => find.descendant(
  of: owner,
  matching: find.byType(BackdropFilter),
);

double _rise(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(of: find.byType(RiseIn), matching: find.byType(Transform))
          .first,
    )
    .transform
    .storage[13];

Color _rowColor(WidgetTester tester, String id) =>
    (tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byKey(ValueKey<Object?>(id)),
                    matching: find.byWidgetPredicate(
                      (Widget widget) =>
                          widget is DecoratedBox &&
                          widget.decoration is BoxDecoration &&
                          (widget.decoration as BoxDecoration).color != null,
                    ),
                  ),
                )
                .decoration
            as BoxDecoration)
        .color!;

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      testWidgets(
        'bounded glass and exact layout, light $light, ${direction.name}',
        (WidgetTester tester) async {
          tester.view
            ..physicalSize = const Size(1200, 600)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(_host(light: light, direction: direction));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
          final Rect palette = tester.getRect(
            find.byKey(const Key('go_to_palette')),
          );
          expect(palette.width, 560);
          expect(palette.top, 120);
          expect(palette.bottom, lessThanOrEqualTo(600 - tokens.goToEdgeInset));
          expect(find.byType(BackdropFilter), findsNWidgets(2));
          final Finder surface = find.byType(FrostedSurface);
          final Finder barrier = find.byType(FrostedBarrier);
          expect(
            tester.widget<BackdropFilter>(_filter(surface)).filter,
            ImageFilter.blur(
              sigmaX: tokens.dialogBlur,
              sigmaY: tokens.dialogBlur,
            ),
          );
          expect(
            tester.widget<BackdropFilter>(_filter(barrier)).filter,
            ImageFilter.blur(sigmaX: kFrostSigma, sigmaY: kFrostSigma),
          );
          expect(
            tester
                .renderObject<RenderBackdropFilter>(_filter(surface))
                .backdropKey,
            isNull,
          );
          expect(
            tester
                .renderObject<RenderBackdropFilter>(_filter(barrier))
                .backdropKey,
            isNull,
          );
          expect(
            tester
                .widget<ClipRRect>(
                  find.descendant(
                    of: surface,
                    matching: find.byType(ClipRRect),
                  ),
                )
                .borderRadius,
            BorderRadius.circular(tokens.dialogRadius),
          );
          expect(
            tester
                .widget<ColoredBox>(
                  find
                      .descendant(
                        of: surface,
                        matching: find.byType(ColoredBox),
                      )
                      .first,
                )
                .color,
            tokens.glass,
          );
          final RichText identifier = tester.widget<RichText>(
            find.descendant(
              of: find.byKey(const ValueKey<Object?>('contact')),
              matching: find.byWidgetPredicate(
                (Widget widget) =>
                    widget is RichText &&
                    widget.text.toPlainText(includeSemanticsLabels: false) ==
                        'z1same…tail',
              ),
            ),
          );
          expect(
            identifier.text.toPlainText(includeSemanticsLabels: false),
            'z1same…tail',
          );
          expect(identifier.textDirection, TextDirection.ltr);
          expect(identifier.text.style!.fontFamily, tokens.monoFontFamily);
          expect(find.byKey(const Key('original_mark')), findsOneWidget);
          expect(find.byIcon(Icons.home), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final bool platform in <bool>[false, true]) {
    for (final bool mediaQuery in <bool>[false, true]) {
      testWidgets(
        'rise keeps 240 ms and 6 px, '
        'platform $platform, MediaQuery $mediaQuery',
        (WidgetTester tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: platform);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await tester.pumpWidget(_host(mediaQuery: mediaQuery));
          await tester.tap(find.text('Open'));
          await tester.pump();
          expect(_rise(tester), 6);
          await tester.pump(const Duration(milliseconds: 75));
          expect(
            _rise(tester),
            closeTo(6 * (1 - AppTokens.dark.spring.transform(75 / 240)), 1e-6),
          );
          await tester.pump(const Duration(milliseconds: 164));
          expect(_rise(tester), greaterThan(0));
          await tester.pump(const Duration(milliseconds: 1));
          expect(_rise(tester), 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(FrostHold.count.value, 0);
        },
      );
    }
  }

  testWidgets(
    'selection keeps its 150 ms colour clock with both OS flags set',
    (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(_host(mediaQuery: true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(_rowColor(tester, 'contact').a, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_rowColor(tester, 'contact').a, 0);
      await tester.pump(const Duration(milliseconds: 75));
      expect(_rowColor(tester, 'contact').a, greaterThan(0));
      expect(_rowColor(tester, 'contact').a, lessThan(1));
      await tester.pump(const Duration(milliseconds: 75));
      expect(_rowColor(tester, 'contact'), AppTokens.dark.card3);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    },
  );
}
