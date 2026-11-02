import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

const String _prefix = 'security_choice';

Finder _cell(int value) => find.byKey(Segment.keyOf(_prefix, value));

Widget _app(
  Widget child, {
  bool light = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(body: Align(child: child)),
  ),
);

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(Segment.slideDuration);
}

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      testWidgets('available choices in light=$light and $direction', (
        WidgetTester tester,
      ) async {
        int selected = 0;
        final List<int> reported = <int>[];
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _app(
              StatefulBuilder(
                builder: (BuildContext context, StateSetter update) {
                  final TextStyle numeric = AppTokens.of(context).dataText;
                  return Segment<int>(
                    keyPrefix: _prefix,
                    selected: selected,
                    items: <SegmentItem<int>>[
                      SegmentItem<int>(
                        value: 0,
                        label: '5 min',
                        labelStyle: numeric,
                      ),
                      const SegmentItem<int>(
                        value: 1,
                        label: 'On close',
                        seam: Seam.autoLockOnClose,
                      ),
                      const SegmentItem<int>(
                        value: 2,
                        label: '1 h',
                        enabled: false,
                      ),
                      SegmentItem<int>(
                        value: 3,
                        label: '15 min',
                        labelStyle: numeric,
                      ),
                    ],
                    onChanged: (int value) => update(() {
                      selected = value;
                      reported.add(value);
                    }),
                  );
                },
              ),
              light: light,
              direction: direction,
            ),
          );
          await tester.pump();
          final Rect seamed = tester.getRect(_cell(1));
          await tester.tapAt(seamed.center);
          await tester.tap(_cell(2), warnIfMissed: false);
          await tester.pump();
          expect(reported, isEmpty);
          expect(
            tester.widget<Text>(find.text('5 min')).style!.fontFamily,
            AppTokens.dark.monoFontFamily,
          );
          expect(
            tester.getSemantics(_cell(2)),
            isSemantics(isEnabled: false, hasTapAction: false),
          );
          final Finder gate = find.ancestor(
            of: _cell(1),
            matching: find.byType(SeamGate),
          );
          expect(gate, findsOneWidget);
          expect(
            tester.getSemantics(gate),
            isSemantics(isEnabled: false, hasTapAction: false),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _key(
            tester,
            direction == TextDirection.ltr
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft,
          );
          expect(selected, 3);
          expect(reported, <int>[3]);
          await _key(tester, LogicalKeyboardKey.home);
          expect(selected, 0);
          await _key(tester, LogicalKeyboardKey.end);
          expect(selected, 3);
          expect(reported, <int>[3, 0, 3]);
          expect(tester.getRect(_cell(1)), seamed);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('a saved callback rechecks the current choice and disposal', (
    WidgetTester tester,
  ) async {
    late StateSetter rebuild;
    bool gated = false;
    int activated = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter update) {
            rebuild = update;
            return Segment<int>(
              keyPrefix: _prefix,
              selected: 0,
              items: <SegmentItem<int>>[
                const SegmentItem<int>(value: 0, label: '3'),
                SegmentItem<int>(
                  value: 1,
                  label: 'Off',
                  seam: gated ? Seam.wrongPasswordLimitOff : null,
                ),
              ],
              onChanged: (_) => activated++,
            );
          },
        ),
      ),
    );
    final VoidCallback saved = tester
        .widget<GestureDetector>(
          find
              .descendant(of: _cell(1), matching: find.byType(GestureDetector))
              .first,
        )
        .onTap!;
    rebuild(() => gated = true);
    await tester.pump();
    saved();
    expect(activated, 0);
    await tester.pumpWidget(const SizedBox());
    saved();
    expect(activated, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrows and edges refuse when every choice is unavailable', (
    WidgetTester tester,
  ) async {
    int activated = 0;
    await tester.pumpWidget(
      _app(
        Segment<int>(
          keyPrefix: _prefix,
          selected: null,
          items: const <SegmentItem<int>>[
            SegmentItem<int>(value: 0, label: 'Off', enabled: false),
            SegmentItem<int>(
              value: 1,
              label: 'On close',
              seam: Seam.autoLockOnClose,
            ),
          ],
          onChanged: (_) => activated++,
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    ]) {
      await _key(tester, key);
    }
    expect(activated, 0);
    expect(tester.getSize(find.byType(SegmentThumb)).width, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
