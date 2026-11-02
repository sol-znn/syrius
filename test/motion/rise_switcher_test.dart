import 'dart:ui' show SemanticsAction;

import 'package:animations/animations.dart';
import 'package:flutter/semantics.dart' show SemanticsNode, SemanticsOwner;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

int _built = 0;
int _disposed = 0;

class _Page extends StatefulWidget {
  const _Page(this.name, {super.key});

  final String name;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _built++;
  }

  @override
  void dispose() {
    _disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(key: ValueKey<String>('page_${widget.name}'));
}

Widget _host(
  int index, {
  Widget? page,
  Duration? duration,
  Duration? reverseDuration,
  double? rise,
  bool disableAnimations = false,
}) {
  final Widget destination =
      page ?? KeyedSubtree(key: ValueKey<int>(index), child: _Page('$index'));
  final RiseSwitcher switcher =
      duration == null && reverseDuration == null && rise == null
      ? RiseSwitcher(child: destination)
      : RiseSwitcher(
          duration: duration ?? const Duration(milliseconds: 320),
          reverseDuration: reverseDuration ?? const Duration(milliseconds: 320),
          rise: rise ?? 6,
          child: destination,
        );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Material(
        child: switcher,
      ),
    ),
  );
}

Finder _page(Object index) => find.byKey(ValueKey<String>('page_$index'));

double _rise(WidgetTester tester, Finder page) => tester
    .widget<Transform>(
      find.ancestor(of: page, matching: find.byType(Transform)).last,
    )
    .transform
    .storage[13];

double _opacity(WidgetTester tester, Finder page) => tester
    .widgetList<FadeTransition>(
      find.ancestor(of: page, matching: find.byType(FadeTransition)),
    )
    .fold<double>(
      1,
      (double value, FadeTransition fade) => value * fade.opacity.value,
    );

void main() {
  setUp(() {
    _built = 0;
    _disposed = 0;
  });

  group('RiseSwitcher', () {
    testWidgets('the first page appears in place, without motion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      expect(tester.getTopLeft(_page(0)), Offset.zero);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the new page rises 6 px; the old one does not move', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      // Native fade-through includes its scale; this is the added translation.
      expect(_rise(tester, _page(1)), 6);
      expect(tester.getTopLeft(_page(0)).dy, 0);

      await tester.pump(const Duration(milliseconds: 50));
      final double rising = _rise(tester, _page(1));
      expect(rising, greaterThan(0));
      expect(rising, lessThan(6));
      expect(
        rising,
        closeTo(6 * (1 - AppTokens.light.spring.transform(50 / 320)), 1e-6),
      );
      expect(tester.getTopLeft(_page(0)).dy, 0);

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_page(1)), Offset.zero);
    });

    testWidgets('the old page is gone before the new one has arrived', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      expect(_page(0), findsOneWidget);
      // Past the 96 ms visible exit, inside the 320 ms arrival.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(_page(0), findsNothing);
      expect(_disposed, 1);
      expect(_rise(tester, _page(1)), greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('only the current page is built once settled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(2));
      await tester.pumpAndSettle();
      expect(_built, 3);
      expect(_disposed, 2);
      expect(find.byType(_Page), findsOneWidget);
      expect(_page(2), findsOneWidget);
    });

    testWidgets('a rebuild with the same key keeps the page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(0));
      expect(_built, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the leaving page takes no input', (WidgetTester tester) async {
      int taps = 0;
      Widget host(int index) => Directionality(
        textDirection: TextDirection.ltr,
        child: RiseSwitcher(
          child: KeyedSubtree(
            key: ValueKey<int>(index),
            child: index == 0
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                  )
                : const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpWidget(host(0));
      await tester.tapAt(const Offset(100, 100));
      expect(taps, 1);
      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tapAt(const Offset(100, 100));
      expect(taps, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('fade-through separates visibility and finishes at 320 ms', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      expect(find.byType(FadeThroughTransition), findsNWidgets(2));
      expect(_opacity(tester, _page(0)), 1);
      expect(_opacity(tester, _page(1)), 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(_opacity(tester, _page(0)), greaterThan(0));
      expect(_opacity(tester, _page(1)), 0);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_opacity(tester, _page(0)), 0);
      expect(_opacity(tester, _page(1)), closeTo(0, 1e-9));
      // The SDK completes a clock on its first tick after the endpoint.
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(_page(0), findsNothing);
      await tester.pump(const Duration(microseconds: 63999));
      expect(_opacity(tester, _page(1)), greaterThan(0));
      expect(_opacity(tester, _page(1)), lessThan(1));
      await tester.pump(const Duration(milliseconds: 160));
      expect(_opacity(tester, _page(1)), 1);
      expect(_rise(tester, _page(1)), 0);
      await tester.pump(const Duration(microseconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a slower exit delays a custom entrance without overlap', (
      WidgetTester tester,
    ) async {
      Widget host(int index) => _host(
        index,
        duration: const Duration(milliseconds: 100),
        reverseDuration: const Duration(milliseconds: 600),
        rise: 12,
      );
      await tester.pumpWidget(host(0));
      await tester.pumpWidget(host(1));
      expect(_rise(tester, _page(1)), 12);
      await tester.pump(const Duration(milliseconds: 179));
      expect(_opacity(tester, _page(0)), greaterThan(0));
      expect(_opacity(tester, _page(1)), 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_opacity(tester, _page(0)), 0);
      expect(_opacity(tester, _page(1)), closeTo(0, 1e-9));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(_page(0), findsNothing);
      await tester.pump(const Duration(microseconds: 34999));
      expect(_opacity(tester, _page(1)), greaterThan(0));
      expect(_rise(tester, _page(1)), greaterThan(0));
      // 150 ms hold plus the caller's 100 ms incoming clock.
      await tester.pump(const Duration(milliseconds: 35));
      expect(_opacity(tester, _page(1)), 1);
      expect(_rise(tester, _page(1)), 0);
      await tester.pump(const Duration(microseconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('rapid A B A reclaims an actual descendant GlobalKey safely', (
      WidgetTester tester,
    ) async {
      final GlobalKey<_PageState> a = GlobalKey<_PageState>();
      Widget pageA() => KeyedSubtree(
        key: const ValueKey<String>('A'),
        child: _Page('A', key: a),
      );
      await tester.pumpWidget(_host(0, page: pageA()));
      final _PageState original = a.currentState!;
      await tester.pumpWidget(_host(1));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(_host(0, page: pageA()));
      expect(tester.takeException(), isNull);
      expect(find.byKey(a), findsOneWidget);
      expect(a.currentState, same(original));
      await tester.pumpAndSettle();
      expect(_page('A'), findsOneWidget);
      expect(find.byType(_Page), findsOneWidget);
      expect(a.currentState, same(original));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('rapid replacements retire every obsolete page and ticker', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      for (int index = 1; index <= 5; index++) {
        await tester.pumpWidget(_host(index));
        await tester.pump(const Duration(milliseconds: 20));
        final int visible = <int>[for (int i = 0; i <= index; i++) i]
            .where(
              (int i) =>
                  _page(i).evaluate().isNotEmpty &&
                  _opacity(tester, _page(i)) > 0,
            )
            .length;
        expect(visible, lessThanOrEqualTo(1));
      }
      await tester.pumpAndSettle();
      expect(find.byType(_Page), findsOneWidget);
      expect(_disposed, _built - 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(_disposed, _built);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clock changes apply to the next replacement', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pump(const Duration(milliseconds: 80));
      final _PageState original = tester.state<_PageState>(
        find.byType(_Page).last,
      );
      await tester.pumpWidget(
        _host(1, duration: const Duration(milliseconds: 50)),
      );
      expect(tester.state<_PageState>(find.byType(_Page).last), same(original));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_opacity(tester, _page(1)), lessThan(1));
      await tester.pump(const Duration(milliseconds: 160));
      expect(_opacity(tester, _page(1)), 1);
      expect(_rise(tester, _page(1)), 0);
      await tester.pump(const Duration(microseconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('outgoing and hidden pages refuse focus and semantic actions', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final FocusNode focus = FocusNode();
      addTearDown(focus.dispose);
      int oldPresses = 0;
      int newPresses = 0;
      try {
        Widget page(int index) => KeyedSubtree(
          key: ValueKey<int>(index),
          child: Center(
            child: TextButton(
              focusNode: index == 0 ? focus : null,
              onPressed: () => index == 0 ? oldPresses++ : newPresses++,
              child: Text(index == 0 ? 'Old action' : 'New action'),
            ),
          ),
        );
        await tester.pumpWidget(_host(0, page: page(0)));
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        final SemanticsNode old = tester.getSemantics(find.text('Old action'));
        final SemanticsOwner owner = old.owner!;
        await tester.pumpWidget(_host(1, page: page(1)));
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        expect(focus.canRequestFocus, isFalse);
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        expect(find.semantics.byLabel('Old action'), findsNothing);
        expect(find.semantics.byLabel('New action'), findsNothing);
        owner.performAction(old.id, SemanticsAction.tap);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.tapAt(tester.getCenter(find.text('Old action')));
        expect(oldPresses, 0);
        expect(newPresses, 0);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(find.text('New action'));
        expect(newPresses, 1);
        expect(oldPresses, 0);
        await tester.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    });

    for (final bool disabled in <bool>[false, true]) {
      testWidgets('keeps the 320 ms clock with OS animations off: $disabled', (
        WidgetTester tester,
      ) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: disabled);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(_host(0, disableAnimations: disabled));
        await tester.pumpWidget(_host(1, disableAnimations: disabled));
        await tester.pump(const Duration(milliseconds: 80));
        expect(_page(0), findsOneWidget);
        expect(_opacity(tester, _page(1)), 0);
        await tester.pump(const Duration(milliseconds: 160));
        expect(_opacity(tester, _page(1)), lessThan(1));
        expect(_rise(tester, _page(1)), greaterThan(0));
        await tester.pump(const Duration(milliseconds: 80));
        expect(_opacity(tester, _page(1)), 1);
        expect(_rise(tester, _page(1)), 0);
        await tester.pump(const Duration(microseconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }

    for (final bool disabled in <bool>[false, true]) {
      testWidgets(
        'a field rebuilt during arrival stays traversable $disabled',
        (
          WidgetTester tester,
        ) async {
          final FocusNode field = FocusNode();
          final FocusNode action = FocusNode();
          final ValueNotifier<int> revision = ValueNotifier<int>(0);
          Widget host(int index) => MaterialApp(
            home: Scaffold(
              body: _host(
                index,
                disableAnimations: disabled,
                page: KeyedSubtree(
                  key: ValueKey<int>(index),
                  child: index == 0
                      ? const SizedBox.expand()
                      : Center(
                          child: SizedBox(
                            width: 240,
                            child: ValueListenableBuilder<int>(
                              valueListenable: revision,
                              builder: (_, int value, _) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  TextField(
                                    focusNode: field,
                                    decoration: InputDecoration(
                                      labelText: 'Recipient $value',
                                    ),
                                  ),
                                  TextButton(
                                    focusNode: action,
                                    onPressed: () {},
                                    child: const Text('Continue'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          );
          try {
            await tester.pumpWidget(host(0));
            await tester.pumpWidget(host(1));
            expect(field.canRequestFocus, isFalse);
            revision.value++;
            await tester.pump(const Duration(milliseconds: 16));
            field.requestFocus();
            await tester.pump();
            expect(field.hasFocus, isFalse);
            await tester.pumpAndSettle();
            expect(field.skipTraversal, isFalse);
            field.requestFocus();
            await tester.pump();
            expect(field.hasFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            expect(action.hasFocus, isTrue);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            revision.dispose();
            field.dispose();
            action.dispose();
          }
        },
      );
    }

    testWidgets('explicit zero clocks switch immediately without a ticker', (
      WidgetTester tester,
    ) async {
      Widget host(int index) => _host(
        index,
        duration: Duration.zero,
        reverseDuration: Duration.zero,
      );
      await tester.pumpWidget(host(0));
      await tester.pumpWidget(host(1));
      expect(_page(0), findsNothing);
      expect(_page(1), findsOneWidget);
      expect(_opacity(tester, _page(1)), 1);
      expect(_rise(tester, _page(1)), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
