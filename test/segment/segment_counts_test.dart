import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

enum _Node { pillars, sentinels }

const String _prefix = 'counted_nodes';

Finder _cell(_Node node) => find.byKey(Segment.keyOf(_prefix, node));

final Finder _thumb = find.byType(SegmentThumb);

Widget _control({
  int? pillars,
  int? sentinels,
  _Node selected = _Node.pillars,
  ValueChanged<_Node>? onChanged,
  bool icons = false,
}) => Segment<_Node>(
  keyPrefix: _prefix,
  items: <SegmentItem<_Node>>[
    SegmentItem<_Node>(
      value: _Node.pillars,
      label: 'Pillars',
      count: pillars,
      icon: icons ? Icons.account_tree : null,
    ),
    SegmentItem<_Node>(
      value: _Node.sentinels,
      label: 'Sentinels',
      count: sentinels,
      icon: icons ? Icons.storage : null,
    ),
  ],
  selected: selected,
  onChanged: onChanged ?? (_Node _) {},
);

Widget _app(
  Widget child, {
  bool light = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Align(alignment: AlignmentDirectional.topStart, child: child),
    ),
  ),
);

Text _label(WidgetTester tester, _Node node) => tester.widget<Text>(
  find.descendant(of: _cell(node), matching: find.byType(Text)),
);

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'zero is mono and unknown is absent in ${light ? 'light' : 'dark'}',
      (WidgetTester tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_app(_control(pillars: 0), light: light));
          final Text label = _label(tester, _Node.pillars);
          final TextSpan paragraph = label.textSpan! as TextSpan;
          final TextSpan count = paragraph.children!.last as TextSpan;
          final AppTokens tokens = AppTokens.of(
            tester.element(_cell(_Node.pillars)),
          );
          expect(paragraph.toPlainText(), 'Pillars 0');
          expect(count.style!.fontFamily, tokens.dataText.fontFamily);
          expect(count.style!.fontFeatures, tokens.dataText.fontFeatures);
          expect(count.style!.fontSize, label.style!.fontSize);
          expect(count.style!.color, label.style!.color);
          expect(_label(tester, _Node.sentinels).data, 'Sentinels');
          expect(
            tester.getSemantics(_cell(_Node.pillars)),
            isSemantics(
              label: 'Pillars, 0',
              isButton: true,
              hasSelectedState: true,
              isSelected: true,
              isInMutuallyExclusiveGroup: true,
              hasTapAction: true,
            ),
          );
          expect(
            tester.getSemantics(_cell(_Node.sentinels)),
            isSemantics(label: 'Sentinels', isButton: true),
          );
        } finally {
          handle.dispose();
        }
      },
    );
  }

  testWidgets(
    'changed and removed counts resize the selected thumb immediately',
    (WidgetTester tester) async {
      await tester.pumpWidget(_app(_control(pillars: 7, sentinels: 12)));
      final Rect first = tester.getRect(_cell(_Node.pillars));
      expect(tester.getRect(_thumb), first);
      final Element thumb = tester.element(_thumb);

      await tester.pumpWidget(_app(_control(pillars: 1000000, sentinels: 12)));
      final Rect wider = tester.getRect(_cell(_Node.pillars));
      expect(wider.width, greaterThan(first.width));
      expect(tester.getRect(_thumb), wider);
      expect(tester.element(_thumb), same(thumb));

      await tester.pumpWidget(_app(_control(sentinels: 12)));
      final Rect absent = tester.getRect(_cell(_Node.pillars));
      expect(absent.width, lessThan(first.width));
      expect(tester.getRect(_thumb), absent);
      expect(tester.element(_thumb), same(thumb));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('counts take part in the actual intrinsic paragraph layout', (
    WidgetTester tester,
  ) async {
    Widget build(int? count) => _app(
      IntrinsicWidth(child: _control(pillars: count, sentinels: 12)),
    );
    await tester.pumpWidget(build(null));
    final double initial = tester.getSize(find.byType(Segment<_Node>)).width;
    await tester.pumpWidget(build(123456));
    expect(
      tester.getSize(find.byType(Segment<_Node>)).width,
      greaterThan(initial),
    );
    expect(tester.getRect(_thumb), tester.getRect(_cell(_Node.pillars)));
    expect(tester.takeException(), isNull);
  });

  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      testWidgets(
        'counts and icons fit narrow keyboard tabs in '
        '${light ? 'light' : 'dark'} ${direction.name}',
        (WidgetTester tester) async {
          _Node selected = _Node.pillars;
          await tester.pumpWidget(
            _app(
              SizedBox(
                width: 120,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) =>
                      _control(
                        pillars: 97000,
                        sentinels: 12000,
                        icons: true,
                        selected: selected,
                        onChanged: (_Node value) =>
                            setState(() => selected = value),
                      ),
                ),
              ),
              light: light,
              direction: direction,
            ),
          );
          expect(tester.takeException(), isNull);
          final Rect whole = tester.getRect(find.byType(Segment<_Node>));
          expect(whole.width, lessThanOrEqualTo(120));
          for (final _Node node in _Node.values) {
            final Rect cell = tester.getRect(_cell(node));
            expect(cell.left, greaterThanOrEqualTo(whole.left));
            expect(cell.right, lessThanOrEqualTo(whole.right));
          }
          expect(find.byIcon(Icons.account_tree), findsOneWidget);
          expect(find.byIcon(Icons.storage), findsOneWidget);
          expect(
            tester.getRect(_cell(_Node.pillars)).left,
            direction == TextDirection.ltr
                ? lessThan(tester.getRect(_cell(_Node.sentinels)).left)
                : greaterThan(tester.getRect(_cell(_Node.sentinels)).left),
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(
            direction == TextDirection.ltr
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft,
          );
          await tester.pumpAndSettle();
          expect(selected, _Node.sentinels);
          expect(
            tester.getRect(_thumb),
            tester.getRect(_cell(_Node.sentinels)),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
