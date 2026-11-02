import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

enum _Node { pillars, sentinels }

const String _prefix = 'heading_nodes';

Finder _cell(_Node node) => find.byKey(Segment.keyOf(_prefix, node));

final Finder _thumb = find.byType(SegmentThumb);

Widget _control({
  SegmentAppearance appearance = SegmentAppearance.heading,
  int? pillars,
  int? sentinels,
  String pillarLabel = 'Pillars',
  _Node selected = _Node.pillars,
  ValueChanged<_Node>? onChanged,
  bool icons = false,
}) => Segment<_Node>(
  appearance: appearance,
  keyPrefix: _prefix,
  items: <SegmentItem<_Node>>[
    SegmentItem<_Node>(
      value: _Node.pillars,
      label: pillarLabel,
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
  double textScale = 1,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
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

Decoration _thumbDecoration(WidgetTester tester) => tester
    .widget<DecoratedBox>(
      find.descendant(of: _thumb, matching: find.byType(DecoratedBox)),
    )
    .decoration;

void main() {
  testWidgets('omitted appearance retains the original pill geometry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Segment<_Node>(
          keyPrefix: _prefix,
          items: const <SegmentItem<_Node>>[
            SegmentItem<_Node>(value: _Node.pillars, label: 'Pillars'),
            SegmentItem<_Node>(value: _Node.sentinels, label: 'Sentinels'),
          ],
          selected: _Node.pillars,
          onChanged: (_Node _) {},
        ),
      ),
    );
    expect(
      tester.widget<Segment<_Node>>(find.byType(Segment<_Node>)).appearance,
      SegmentAppearance.pill,
    );
    expect(
      tester.widget<SegmentThumb>(_thumb).appearance,
      SegmentAppearance.pill,
    );
    final Rect original = tester.getRect(find.byType(Segment<_Node>));
    final Rect cell = tester.getRect(_cell(_Node.pillars));
    final Rect thumb = tester.getRect(_thumb);
    expect(cell.left - original.left, 4);
    expect(tester.getRect(_cell(_Node.sentinels)).left, cell.right);
    expect(thumb, cell);
    expect(_thumbDecoration(tester), isA<ShapeDecoration>());

    await tester.pumpWidget(_app(_control(appearance: SegmentAppearance.pill)));
    expect(tester.getRect(find.byType(Segment<_Node>)), original);
    expect(tester.getRect(_cell(_Node.pillars)), cell);
    expect(tester.getRect(_thumb), thumb);
    expect(tester.takeException(), isNull);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'flat heading and factual counts use ${light ? 'light' : 'dark'} tokens',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_app(_control(pillars: 0), light: light));
          final AppTokens tokens = AppTokens.of(
            tester.element(_cell(_Node.pillars)),
          );
          final Text label = _label(tester, _Node.pillars);
          final TextSpan paragraph = label.textSpan! as TextSpan;
          final TextSpan count = paragraph.children!.whereType<TextSpan>().last;
          final BoxDecoration underline =
              _thumbDecoration(tester) as BoxDecoration;
          expect(label.style!.fontSize, 14);
          expect(label.style!.fontWeight, FontWeight.w500);
          expect(label.style!.color, tokens.foreground);
          expect(_label(tester, _Node.sentinels).style!.color, tokens.dim);
          expect(paragraph.toPlainText(includePlaceholders: false), 'Pillars0');
          expect(count.style!.fontSize, 11);
          expect(count.style!.fontFamily, tokens.monoFontFamily);
          expect(count.style!.fontFeatures, tokens.dataText.fontFeatures);
          expect(count.style!.color, tokens.faint);
          expect(_label(tester, _Node.sentinels).data, 'Sentinels');
          expect(underline.color, isNull);
          expect(underline.borderRadius, isNull);
          expect(
            (underline.border! as Border).bottom,
            BorderSide(color: tokens.znn, width: tokens.tabUnderlineThickness),
          );
          expect(
            tester
                .widgetList<DecoratedBox>(
                  find.descendant(
                    of: find.byType(Segment<_Node>),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .any((DecoratedBox box) => box.decoration is ShapeDecoration),
            isFalse,
          );
          final Rect whole = tester.getRect(find.byType(Segment<_Node>));
          final Rect first = tester.getRect(_cell(_Node.pillars));
          expect(first.topLeft, whole.topLeft);
          expect(first.height, tokens.panelHeaderHeight);
          expect(
            tester.getRect(_cell(_Node.sentinels)).left - first.right,
            tokens.tabGap,
          );
          expect(tester.getRect(_thumb), first);
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
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('counts and translated labels resize the same measured thumb', (
    WidgetTester tester,
  ) async {
    Widget build({int? count, String label = 'Pillars'}) => _app(
      IntrinsicWidth(
        child: IntrinsicHeight(
          child: _control(pillars: count, pillarLabel: label),
        ),
      ),
    );
    await tester.pumpWidget(build(count: 7));
    final Element thumb = tester.element(_thumb);
    final Rect first = tester.getRect(_cell(_Node.pillars));
    final double initial = tester.getSize(find.byType(Segment<_Node>)).width;
    await tester.pumpWidget(build(count: 1000000, label: 'Network pillars'));
    final Rect wider = tester.getRect(_cell(_Node.pillars));
    expect(wider.width, greaterThan(first.width));
    expect(
      tester.getSize(find.byType(Segment<_Node>)).width,
      greaterThan(initial),
    );
    expect(tester.getRect(_thumb), wider);
    expect(tester.element(_thumb), same(thumb));

    await tester.pumpWidget(build());
    expect(tester.getRect(_cell(_Node.pillars)).width, lessThan(first.width));
    expect(_label(tester, _Node.pillars).data, 'Pillars');
    expect(tester.getRect(_thumb), tester.getRect(_cell(_Node.pillars)));
    expect(tester.element(_thumb), same(thumb));
    expect(tester.takeException(), isNull);
  });

  testWidgets('heading keeps one 360 ms underline and label fade', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _Node selected = _Node.pillars;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => _control(
            selected: selected,
            pillars: 0,
            sentinels: 12,
            onChanged: (_Node value) => setState(() => selected = value),
          ),
        ),
      ),
    );
    final Element thumb = tester.element(_thumb);
    final Rect from = tester.getRect(_cell(_Node.pillars));
    final Rect to = tester.getRect(_cell(_Node.sentinels));
    await tester.tap(_cell(_Node.sentinels));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester.getRect(_thumb).left,
      moreOrLessEquals((from.left + to.left) / 2),
    );
    expect(
      tester.getRect(_thumb).width,
      moreOrLessEquals((from.width + to.width) / 2),
    );
    expect(
      _label(tester, _Node.pillars).style!.color,
      _label(tester, _Node.sentinels).style!.color,
    );
    expect(tester.element(_thumb), same(thumb));
    await tester.pump(const Duration(milliseconds: 170));
    expect(tester.getRect(_thumb), isNot(to));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.getRect(_thumb), to);
    expect(tester.element(_thumb), same(thumb));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      testWidgets(
        'scaled narrow heading keeps geometry and keyboard in '
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
              textScale: 2,
            ),
          );
          expect(tester.takeException(), isNull);
          final Rect whole = tester.getRect(find.byType(Segment<_Node>));
          expect(whole.width, lessThanOrEqualTo(120));
          expect(whole.height, greaterThan(AppTokens.dark.panelHeaderHeight));
          for (final _Node node in _Node.values) {
            final Rect cell = tester.getRect(_cell(node));
            expect(cell.left, greaterThanOrEqualTo(whole.left - 0.001));
            expect(cell.right, lessThanOrEqualTo(whole.right + 0.001));
            expect(cell.height, whole.height);
          }
          expect(
            tester.getRect(_cell(_Node.pillars)).left,
            direction == TextDirection.ltr
                ? lessThan(tester.getRect(_cell(_Node.sentinels)).left)
                : greaterThan(tester.getRect(_cell(_Node.sentinels)).left),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            Focus.of(tester.element(_cell(_Node.pillars))).hasPrimaryFocus,
            isTrue,
          );
          final AppTokens tokens = AppTokens.of(
            tester.element(_cell(_Node.pillars)),
          );
          expect(
            tester
                .widgetList<DecoratedBox>(
                  find.descendant(
                    of: find.byType(Segment<_Node>),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .any((DecoratedBox box) {
                  final Decoration decoration = box.decoration;
                  return box.position == DecorationPosition.foreground &&
                      decoration is BoxDecoration &&
                      decoration.border ==
                          Border.all(color: tokens.focusRing, width: 2);
                }),
            isTrue,
          );
          expect(tester.getRect(find.byType(Segment<_Node>)), whole);
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
          expect(tester.getRect(find.byType(Segment<_Node>)), whole);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a real search field shares the measured heading row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 600,
          child: Panel(
            heading: _control(pillars: 97, sentinels: 12),
            actions: const <Widget>[
              SizedBox(
                width: 200,
                height: 30,
                child: TextField(
                  key: Key('heading_search'),
                  decoration: InputDecoration(isDense: true),
                ),
              ),
            ],
            shrinkWrap: true,
            child: const SizedBox(height: 20),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final Finder search = find.byKey(const Key('heading_search'));
    await tester.enterText(search, 'exact rows');
    await tester.pump();
    expect(find.text('exact rows'), findsOneWidget);
    expect(
      tester.getRect(search).center.dy,
      tester.getRect(_cell(_Node.pillars)).center.dy,
    );
    expect(tester.takeException(), isNull);
  });

  for (final TextDirection direction in TextDirection.values) {
    testWidgets(
      'Panel aligns its measured heading and actions ${direction.name}',
      (WidgetTester tester) async {
        Widget build(double scale) => _app(
          SizedBox(
            width: 500,
            child: Panel(
              key: const Key('heading_panel'),
              heading: _control(pillars: 97, sentinels: 12),
              actions: const <Widget>[
                SizedBox(key: Key('heading_action'), width: 40, height: 30),
              ],
              shrinkWrap: true,
              child: const SizedBox(height: 20),
            ),
          ),
          direction: direction,
          textScale: scale,
        );
        await tester.pumpWidget(build(1));
        final double initial = tester
            .getSize(find.byKey(const Key('heading_panel')))
            .height;
        for (final double scale in <double>[1, 2]) {
          await tester.pumpWidget(build(scale));
          final Rect panel = tester.getRect(
            find.byKey(const Key('heading_panel')),
          );
          final Rect first = tester.getRect(_cell(_Node.pillars));
          final Rect action = tester.getRect(
            find.byKey(const Key('heading_action')),
          );
          final AppTokens tokens = AppTokens.of(
            tester.element(_cell(_Node.pillars)),
          );
          expect(
            direction == TextDirection.ltr
                ? first.left - panel.left
                : panel.right - first.right,
            tokens.tabHeaderPadding.start,
          );
          expect(
            tester.getRect(_thumb).bottom,
            tester.getRect(find.byType(Divider)).top,
          );
          expect(action.height, 30);
          expect(action.center.dy, first.center.dy);
          expect(tester.takeException(), isNull);
        }
        expect(
          tester.getSize(find.byKey(const Key('heading_panel'))).height,
          greaterThan(initial),
        );
      },
    );
  }
}
