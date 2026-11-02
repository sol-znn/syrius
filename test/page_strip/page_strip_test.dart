import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

const Key _strip = Key('strip');
const Key _lead = Key('lead');
const Key _action = Key('action');
const Key _note = Key('note');

/// The one file the no-data mark has, whatever size it is drawn at.
final String _noData = AppLottieAsset.noData.path(kEmptyNoteMarkSize, 1);

Widget _host(
  Widget child, {
  double width = 1100,
  double height = 300,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  ),
);

/// A strip above the list it heads, as on a page.
Widget _page(PageStrip strip) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[strip, const Spacer()],
);

Widget _button(String label) => SizedBox(
  key: _action,
  width: 110,
  height: 38,
  child: Center(child: Text(label)),
);

PageStrip _three({VoidCallback? onTap}) => PageStrip(
  key: _strip,
  lead: const SizedBox.expand(key: _lead),
  figures: <StripFigure>[
    StripFigure(label: 'Your pillar', value: const Text('dev1'), onTap: onTap),
    const StripFigure(
      label: 'To collect',
      value: Text('3.214 ZNN'),
      trailing: Text(r'$1.99'),
    ),
  ],
  actions: <Widget>[_button('Stake')],
);

TextStyle _paintedStyle(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    )
    .text
    .style!;

void main() {
  tearDown(AppLottie.debugClear);

  group('PageStrip', () {
    testWidgets('lead, figures and actions run from the start', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_page(_three())));
      final Rect strip = tester.getRect(find.byKey(_strip));
      final Rect lead = tester.getRect(find.byKey(_lead));
      final Rect first = tester.getRect(find.text('YOUR PILLAR'));
      final Rect second = tester.getRect(find.text('TO COLLECT'));
      final Rect action = tester.getRect(find.byKey(_action));

      expect(lead.size, const Size.square(kStripLeadSize));
      expect(lead.left, strip.left + 18);
      expect(lead.top, strip.top + 12);
      expect(lead.right, lessThan(first.left));
      expect(first.right, lessThan(second.left));
      expect(second.right, lessThan(action.left));
      expect(action.right, strip.right - 18);
      // The label over the value, the dollar amount after it.
      final Rect value = tester.getRect(find.text('3.214 ZNN'));
      expect(second.bottom, lessThanOrEqualTo(value.top));
      expect(value.right, lessThan(tester.getRect(find.text(r'$1.99')).left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrors right to left', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(_page(_three(onTap: () {})), direction: TextDirection.rtl),
      );
      final Rect strip = tester.getRect(find.byKey(_strip));
      final Rect lead = tester.getRect(find.byKey(_lead));
      final Rect first = tester.getRect(find.text('YOUR PILLAR'));
      final Rect second = tester.getRect(find.text('TO COLLECT'));
      final Rect action = tester.getRect(find.byKey(_action));

      expect(lead.right, strip.right - 18);
      expect(lead.left, greaterThan(first.right));
      expect(first.left, greaterThan(second.right));
      expect(second.left, greaterThan(action.right));
      expect(action.left, strip.left + 18);
      // The chevron follows the figure and points on, which is leftwards.
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(
        tester.getRect(find.byIcon(Icons.chevron_left)).right,
        lessThanOrEqualTo(first.left),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a strip without a lead is as tall as one with', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_page(_three())));
      final double withLead = tester.getSize(find.byKey(_strip)).height;
      await tester.pumpWidget(
        _host(
          _page(
            const PageStrip(
              key: _strip,
              figures: <StripFigure>[
                StripFigure(label: 'Staked', value: Text('0')),
              ],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(_strip)).height, withLead);
    });

    for (final TextDirection direction in TextDirection.values) {
      testWidgets('four figures and an action fit 700 px, ${direction.name}', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          _host(
            _page(
              PageStrip(
                key: _strip,
                lead: const SizedBox.expand(key: _lead),
                figures: <StripFigure>[
                  StripFigure(
                    label: 'Your sentinel with a long label',
                    value: const Text('Address 3 of the wallet'),
                    onTap: () {},
                  ),
                  const StripFigure(
                    label: 'To collect',
                    value: Text('1,234,567.12345678 ZNN'),
                    trailing: Text(r'$765,431.99'),
                  ),
                  const StripFigure(
                    label: 'Last 7 days',
                    value: Text('+ 41,200.12345678 QSR'),
                    trailing: Text(r'$23,484.07'),
                  ),
                  const StripFigure(
                    label: 'Revocable',
                    value: Text('in 3 d 2 h'),
                  ),
                ],
                actions: <Widget>[_button('Stake')],
              ),
            ),
            width: 700,
            direction: direction,
          ),
        );
        // An overflow is reported as an exception by the row it is in.
        expect(tester.takeException(), isNull);
        final Rect strip = tester.getRect(find.byKey(_strip));
        expect(strip.width, 700);
        for (final String text in <String>[
          '1,234,567.12345678 ZNN',
          r'$765,431.99',
          r'$23,484.07',
          'in 3 d 2 h',
        ]) {
          final Rect rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(strip.left), reason: text);
          expect(rect.right, lessThanOrEqualTo(strip.right), reason: text);
        }
        // The action kept its width: the figures gave way, not the button.
        expect(tester.getSize(find.byKey(_action)).width, 110);
        // The long value was drawn smaller, not cut.
        final RenderParagraph value = tester.renderObject<RenderParagraph>(
          find.text('1,234,567.12345678 ZNN'),
        );
        expect(value.didExceedMaxLines, isFalse);
        expect(
          // As drawn: getSize would give the height before the scaling.
          tester.getRect(find.text('1,234,567.12345678 ZNN')).height,
          lessThan(tester.getRect(find.text('in 3 d 2 h')).height),
        );
      });
    }

    testWidgets('a tappable figure is a button and calls back', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      int taps = 0;
      await tester.pumpWidget(_host(_page(_three(onTap: () => taps++))));

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(
        tester.getSemantics(find.text('YOUR PILLAR')),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      await tester.tap(find.text('dev1'));
      expect(taps, 1);
      // The chevron is part of the button.
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(taps, 2);
      // A figure without onTap is neither.
      await tester.tap(find.text('3.214 ZNN'));
      expect(taps, 2);
      expect(
        tester.getSemantics(find.text('TO COLLECT')),
        isNot(isSemantics(isButton: true)),
      );
      semantics.dispose();
    });

    testWidgets('a figure can be reached and activated from the keyboard', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(_host(_page(_three(onTap: () => taps++))));
      final Rect before = tester.getRect(find.text('YOUR PILLAR'));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final Border ring = Border.all(
        color: AppTokens.dark.focusRing,
        width: 2,
      );
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).border == ring,
        ),
        findsOneWidget,
      );
      expect(tester.getRect(find.text('YOUR PILLAR')), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('actions retain their width and the mockup gap', (
      WidgetTester tester,
    ) async {
      const Key first = Key('first_action');
      const Key second = Key('second_action');
      await tester.pumpWidget(
        _host(
          _page(
            const PageStrip(
              key: _strip,
              figures: <StripFigure>[
                StripFigure(label: 'Active', value: Text('1')),
              ],
              actions: <Widget>[
                SizedBox(key: first, width: 90, height: 38),
                SizedBox(key: second, width: 110, height: 38),
              ],
            ),
          ),
        ),
      );
      final Rect start = tester.getRect(find.byKey(first));
      final Rect end = tester.getRect(find.byKey(second));
      expect(start.width, 90);
      expect(end.width, 110);
      expect(end.left - start.right, 8);
      expect(end.right, tester.getRect(find.byKey(_strip)).right - 18);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an updated amount is exact on its first frame', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<String> amount = ValueNotifier<String>(
        '1,234,567.12345678 ZNN',
      );
      addTearDown(amount.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<String>(
            valueListenable: amount,
            builder: (BuildContext context, String value, Widget? child) =>
                _page(
                  PageStrip(
                    figures: <StripFigure>[
                      StripFigure(label: 'Staked', value: Text(value)),
                    ],
                  ),
                ),
          ),
        ),
      );

      amount.value = '1,234,567.12345679 ZNN';
      await tester.pump();
      expect(find.text('1,234,567.12345678 ZNN'), findsNothing);
      expect(find.text(amount.value), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text(amount.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes the card colour and radius of each theme', (
      WidgetTester tester,
    ) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        await tester.pumpWidget(_host(_page(_three()), theme: theme));
        await tester.pumpAndSettle();
        final Material surface = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(_strip),
                matching: find.byType(Material),
              )
              .first,
        );
        final AppTokens tokens = theme.extension<AppTokens>()!;
        expect(surface.color, tokens.card);
        expect(
          surface.borderRadius,
          BorderRadius.circular(tokens.cardRadius),
        );
        final TextStyle value = _paintedStyle(tester, '3.214 ZNN');
        final TextStyle dollars = _paintedStyle(tester, r'$1.99');
        for (final TextStyle style in <TextStyle>[value, dollars]) {
          expect(style.fontFamily, kMonoFontFamily);
          expect(
            style.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
        }
        expect(value.fontSize, 19);
        expect(value.fontWeight, FontWeight.w400);
        expect(value.color, tokens.foreground);
        expect(dollars.fontSize, 13);
        expect(dollars.color, tokens.faint);
      }
    });
  });

  group('EmptyNote', () {
    testWidgets('list size: the mark at 44 over the text, centred', (
      WidgetTester tester,
    ) async {
      await tester.runAsync(() => AppLottie.debugLoad(_noData));
      await tester.pumpWidget(
        _host(
          EmptyNote(
            key: _note,
            text: 'None yet',
            action: _button('Stake'),
          ),
          width: 600,
        ),
      );
      await tester.pump();
      final Rect note = tester.getRect(find.byKey(_note));
      final Rect mark = tester.getRect(find.byType(Lottie));
      final Rect text = tester.getRect(find.text('None yet'));
      final Rect action = tester.getRect(find.byKey(_action));

      expect(note.size, const Size(600, 300));
      expect(mark.size, const Size.square(kEmptyNoteMarkSize));
      expect(mark.center.dx, note.center.dx);
      expect(text.center.dx, moreOrLessEquals(note.center.dx, epsilon: 0.5));
      expect(text.top - mark.bottom, 12);
      expect(text.bottom, lessThan(action.top));
      // The three as a block sit in the middle of the height.
      expect(
        (mark.top + action.bottom) / 2,
        moreOrLessEquals(note.center.dy, epsilon: 0.5),
      );
      // Once, then held: a mark that loops would never let the test settle.
      expect(tester.widget<Lottie>(find.byType(Lottie)).repeat, isFalse);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final TextDirection direction in TextDirection.values) {
      testWidgets('line size: the mark at 16 before the text, '
          '${direction.name}', (WidgetTester tester) async {
        await tester.runAsync(() => AppLottie.debugLoad(_noData));
        await tester.pumpWidget(
          _host(
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: EmptyNote.line(key: _note, text: 'None yet'),
            ),
            width: 600,
            height: 48,
            direction: direction,
          ),
        );
        await tester.pump();
        final Rect note = tester.getRect(find.byKey(_note));
        final Rect mark = tester.getRect(find.byType(Lottie));
        final Rect text = tester.getRect(find.text('None yet'));

        expect(mark.size, const Size.square(kEmptyNoteLineMarkSize));
        // As wide as the mark, the gap and the text: one line of a card.
        expect(note.width, lessThan(200));
        expect(note.height, lessThan(48));
        expect(mark.center.dy, moreOrLessEquals(text.center.dy, epsilon: 1));
        if (direction == TextDirection.ltr) {
          expect(mark.right, lessThan(text.left));
        } else {
          expect(mark.left, greaterThan(text.right));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('holds its place before the mark has loaded', (
      WidgetTester tester,
    ) async {
      // Nothing was loaded: the widget asks, and an isolate cannot answer
      // inside the test's fake clock, so this is the frame before it does.
      await tester.pumpWidget(
        _host(const EmptyNote(key: _note, text: 'None yet')),
      );
      expect(find.byType(Lottie), findsNothing);
      expect(
        tester.getSize(find.byType(AppLottie)),
        const Size.square(kEmptyNoteMarkSize),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long text in the line size is cut, not overflowed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmptyNote.line(
            key: _note,
            text: 'Nothing has been collected on this address so far',
          ),
          width: 120,
          height: 48,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(_note)).width, 120);
    });

    testWidgets('list and line copy use their own size in both themes', (
      WidgetTester tester,
    ) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        final AppTokens tokens = theme.extension<AppTokens>()!;
        for (final bool line in <bool>[false, true]) {
          await tester.pumpWidget(
            _host(
              line
                  ? const EmptyNote.line(text: 'None yet')
                  : const EmptyNote(text: 'None yet'),
              theme: theme,
            ),
          );
          // ThemeData itself interpolates when this host switches themes.
          await tester.pumpAndSettle();
          final TextStyle style = _paintedStyle(tester, 'None yet');
          expect(style.fontFamily, kSansFontFamily);
          expect(style.fontSize, line ? 13 : 14);
          expect(style.color, tokens.dim);
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
