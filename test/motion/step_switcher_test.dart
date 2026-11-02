import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';

/// The height of each step, by index.
const List<double> _heights = <double>[100, 240, 60];

const double _width = 400;

int _built = 0;
int _disposed = 0;

class _Step extends StatefulWidget {
  const _Step(this.index, {this.height});

  final int index;
  final double? height;

  @override
  State<_Step> createState() => _StepState();
}

class _StepState extends State<_Step> {
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
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey<String>('step_${widget.index}'),
    width: double.infinity,
    height: widget.height ?? _heights[widget.index],
  );
}

class _TickingStep extends StatefulWidget {
  const _TickingStep(this.index, this.onTick);

  final int index;
  final ValueChanged<int> onTick;

  @override
  State<_TickingStep> createState() => _TickingStepState();
}

class _TickingStepState extends State<_TickingStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
    animationBehavior: AnimationBehavior.preserve,
  )..addListener(() => widget.onTick(widget.index));

  @override
  void initState() {
    super.initState();
    _clock.repeat();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 100);

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }
}

/// A switcher 400 wide at the top left of the window, free to be any height.
Widget _host(
  int step, {
  TextDirection direction = TextDirection.ltr,
  Color? fill,
  double? height,
  Widget? child,
}) {
  final Widget content = child ?? _Step(step, height: height);
  return Directionality(
    textDirection: direction,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _width,
        child: fill == null
            ? StepSwitcher(step: step, child: content)
            : StepSwitcher(step: step, fillColor: fill, child: content),
      ),
    ),
  );
}

Finder _step(int index) => find.byKey(ValueKey<String>('step_$index'));

double _left(WidgetTester tester, int index) =>
    tester.getTopLeft(_step(index)).dx;

double _switcherHeight(WidgetTester tester) =>
    tester.getSize(find.byType(StepSwitcher)).height;

Widget _retainedHost(
  int step, {
  TextDirection direction = TextDirection.ltr,
  bool showContent = true,
  List<Widget>? children,
  Key? flowKey,
  RetainedStepLayoutBuilder? layoutBuilder,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: _width,
      child: StepSwitcher.retained(
        key: flowKey,
        step: step,
        showContent: showContent,
        layoutBuilder: layoutBuilder,
        children:
            children ??
            <Widget>[
              for (int i = 0; i < _heights.length; i++) _Step(i),
            ],
      ),
    ),
  ),
);

void _retainedTestWidgets(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (WidgetTester tester) async {
    try {
      await body(tester);
    } finally {
      // A failed assertion must still release this test's retained bodies
      // before the next test resets its mount and disposal counters.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

List<bool> _inputGates(WidgetTester tester) => tester
    .widgetList<StepInteraction>(
      find.byType(StepInteraction, skipOffstage: false),
    )
    .map((StepInteraction scope) => scope.interactive)
    .toList();

void main() {
  setUp(() {
    _built = 0;
    _disposed = 0;
  });

  group('StepSwitcher', () {
    testWidgets('the first step appears in place, without motion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      expect(tester.getTopLeft(_step(0)), Offset.zero);
      expect(_switcherHeight(tester), 100);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the new step replaces the old', (WidgetTester tester) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pumpAndSettle();
      expect(find.byType(_Step), findsOneWidget);
      expect(_step(1), findsOneWidget);
      expect(_step(0), findsNothing);
      expect(_built, 2);
      expect(_disposed, 1);
      expect(tester.getTopLeft(_step(1)), Offset.zero);
    });

    testWidgets('mid-transition both steps are in the tree', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_step(0), findsOneWidget);
      expect(_step(1), findsOneWidget);
      expect(_disposed, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('a rebuild with the same step keeps the step', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(0));
      expect(_built, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a higher step enters from the end, a lower from the start', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      // Left to right the end is the right: the new step starts 30 px out.
      expect(_left(tester, 1), 30);
      expect(_left(tester, 0), 0);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_left(tester, 1), inExclusiveRange(0, 30));
      expect(_left(tester, 0), lessThan(0));

      await tester.pumpAndSettle();
      expect(_left(tester, 1), 0);

      await tester.pumpWidget(_host(0));
      expect(_left(tester, 0), -30);
      expect(_left(tester, 1), 0);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_left(tester, 0), inExclusiveRange(-30, 0));
      expect(_left(tester, 1), greaterThan(0));

      await tester.pumpAndSettle();
      expect(_left(tester, 0), 0);
    });

    testWidgets('right to left the sides swap', (WidgetTester tester) async {
      const TextDirection rtl = TextDirection.rtl;
      await tester.pumpWidget(_host(0, direction: rtl));
      await tester.pumpWidget(_host(1, direction: rtl));
      // The end is the left now.
      expect(_left(tester, 1), -30);
      expect(_left(tester, 0), 0);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_left(tester, 1), inExclusiveRange(-30, 0));
      expect(_left(tester, 0), greaterThan(0));

      await tester.pumpAndSettle();
      expect(_left(tester, 1), 0);

      await tester.pumpWidget(_host(0, direction: rtl));
      expect(_left(tester, 0), 30);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_left(tester, 0), inExclusiveRange(0, 30));
      expect(_left(tester, 1), lessThan(0));

      await tester.pumpAndSettle();
      expect(_left(tester, 0), 0);
    });

    testWidgets('the height travels from one step to the next', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));

      // To a taller step: no jump on the frame of the change.
      await tester.pumpWidget(_host(1));
      expect(_switcherHeight(tester), 100);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_switcherHeight(tester), inExclusiveRange(100, 240));
      // Neither step is squeezed into the height shown.
      expect(tester.getSize(_step(0)), const Size(_width, 100));
      expect(tester.getSize(_step(1)), const Size(_width, 240));
      await tester.pumpAndSettle();
      expect(_switcherHeight(tester), 240);

      // To a shorter one: the old step is not cut to the new height at once.
      await tester.pumpWidget(_host(2));
      expect(_switcherHeight(tester), 240);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_switcherHeight(tester), inExclusiveRange(60, 240));
      expect(tester.getSize(_step(1)), const Size(_width, 240));
      expect(tester.getSize(_step(2)), const Size(_width, 60));
      await tester.pumpAndSettle();
      expect(_switcherHeight(tester), 60);
    });

    testWidgets('a taller step is cut at the height shown, only in motion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      expect(tester.layers.whereType<ClipRectLayer>(), isEmpty);

      await tester.pumpWidget(_host(1));
      await tester.pump(const Duration(milliseconds: 100));
      final Rect clip = tester.layers
          .whereType<ClipRectLayer>()
          .single
          .clipRect!;
      expect(clip.height, _switcherHeight(tester));
      // Room at the sides for the step's travel.
      expect(clip.width, greaterThan(_width));

      await tester.pumpAndSettle();
      expect(tester.layers.whereType<ClipRectLayer>(), isEmpty);
    });

    testWidgets('a step that grows by itself is followed at once', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(0, height: 150));
      expect(_switcherHeight(tester), 150);
      expect(_built, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a switcher of a fixed height keeps both steps that tall', (
      WidgetTester tester,
    ) async {
      Widget host(int step) => Directionality(
        textDirection: TextDirection.ltr,
        child: StepSwitcher(
          step: step,
          child: Column(
            key: ValueKey<String>('step_$step'),
            children: const <Widget>[Spacer(), SizedBox(height: 10)],
          ),
        ),
      );
      await tester.pumpWidget(host(0));
      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(_step(0)), const Size(800, 600));
      expect(tester.getSize(_step(1)), const Size(800, 600));
      await tester.pumpAndSettle();
    });

    testWidgets('the leaving step takes no input', (WidgetTester tester) async {
      int taps = 0;
      Widget host(int step) => _host(
        step,
        child: step == 0
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: double.infinity, height: 100),
              )
            : const SizedBox(width: double.infinity, height: 100),
      );
      await tester.pumpWidget(host(0));
      await tester.tapAt(const Offset(100, 50));
      expect(taps, 1);
      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tapAt(const Offset(100, 50));
      expect(taps, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('the fill is never the theme canvas', (
      WidgetTester tester,
    ) async {
      const Color canvas = Color(0xFFFF0000);
      const Color card = Color(0xFF101010);
      // Every fill the package has in the tree while two steps swap.
      Set<Color> fills() => tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(StepSwitcher),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((ColoredBox box) => box.color)
          .toSet();
      Widget host(int step, {Color? fill}) => Theme(
        data: ThemeData(canvasColor: canvas),
        child: _host(step, fill: fill),
      );

      await tester.pumpWidget(host(0));
      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(milliseconds: 30));
      expect(fills(), <Color>{Colors.transparent});
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(1, fill: card));
      await tester.pumpWidget(host(2, fill: card));
      await tester.pump(const Duration(milliseconds: 30));
      expect(fills(), <Color>{card});
      await tester.pumpAndSettle();
    });

    testWidgets('MediaQuery.disableAnimations does not shorten the swap', (
      WidgetTester tester,
    ) async {
      Widget host(int step) => MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(step),
      );
      await tester.pumpWidget(host(0));
      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_left(tester, 1), inExclusiveRange(0, 30));
      expect(_switcherHeight(tester), inExclusiveRange(100, 240));

      // 300 ms in all: the old step is there to the end and gone after it.
      await tester.pump(const Duration(milliseconds: 140));
      expect(_step(0), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(_step(0), findsNothing);
      expect(_switcherHeight(tester), 240);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    // The platform's own flag is another matter. The package builds its two
    // controllers without `AnimationBehavior.preserve` and takes no
    // controller from outside, so under the flag its swap runs in a
    // twentieth of the time whatever this widget does; that is put right
    // once for the whole app, in the binding. What the widget owns is the
    // height, and the height keeps its duration.
    testWidgets('the height keeps its duration when the platform asks for '
        'less motion', (WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pump(const Duration(milliseconds: 150));
      // The flag is in force: the package's swap, 15 ms now, is long over.
      expect(_step(0), findsNothing);
      expect(_switcherHeight(tester), inExclusiveRange(100, 240));
      await tester.pump(const Duration(milliseconds: 140));
      expect(_switcherHeight(tester), lessThan(240));
      await tester.pump(const Duration(milliseconds: 20));
      expect(_switcherHeight(tester), 240);
      await tester.pumpAndSettle();
    });
  });

  group('retained StepSwitcher', () {
    _retainedTestWidgets('every retained body mounts and tears down once', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_retainedHost(0));
      expect(_built, 3);
      expect(_disposed, 0);
      expect(_switcherHeight(tester), 100);
      final _StepState first = tester.state(find.byType(_Step).first);

      await tester.pumpWidget(_retainedHost(1));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(_retainedHost(0));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(_retainedHost(2));
      await tester.pumpAndSettle();
      expect(_built, 3);
      expect(_disposed, 0);
      expect(
        tester.state(find.byType(_Step, skipOffstage: false).first),
        same(first),
      );
      expect(_switcherHeight(tester), 60);

      await tester.pumpWidget(_retainedHost(2, showContent: false));
      await tester.pumpAndSettle();
      expect(_switcherHeight(tester), 0);
      expect(_disposed, 0);
      expect(find.byType(_Step, skipOffstage: false), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(_disposed, 3);
      expect(tester.takeException(), isNull);
    });

    _retainedTestWidgets('same-step data updates without restarting motion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_retainedHost(0));
      await tester.pumpWidget(
        _retainedHost(
          0,
          children: const <Widget>[
            _Step(0, height: 150),
            _Step(1),
            _Step(2),
          ],
        ),
      );
      expect(_switcherHeight(tester), 150);
      expect(_built, 3);
      expect(_disposed, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    _retainedTestWidgets('only the settled body owns a running ticker', (
      WidgetTester tester,
    ) async {
      final List<int> ticks = <int>[0, 0, 0];
      Widget host(int step) => _retainedHost(
        step,
        children: <Widget>[
          for (int i = 0; i < ticks.length; i++)
            _TickingStep(i, (int index) => ticks[index]++),
        ],
      );
      await tester.pumpWidget(host(0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(ticks[0], greaterThan(0));
      expect(ticks[1], 0);
      expect(ticks[2], 0);
      await tester.pumpWidget(host(1));
      final int departed = ticks[0];
      await tester.pump(const Duration(milliseconds: 150));
      expect(ticks[0], departed);
      expect(ticks[1], 0);
      await tester.pump(const Duration(milliseconds: 150));
      // The child's resumed ticker gets its first frame at the same clock
      // value as the completed transition, before observing later ticks.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(ticks[0], departed);
      expect(
        ticks[1],
        greaterThan(0),
        reason: 'Current input gates: ${_inputGates(tester)}',
      );
      expect(ticks[2], 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    _retainedTestWidgets('a new flow key releases each old body once', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _retainedHost(0, flowKey: const ValueKey<int>(0)),
      );
      await tester.pumpWidget(
        _retainedHost(0, flowKey: const ValueKey<int>(1)),
      );
      expect(_built, 6);
      expect(_disposed, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(_disposed, 6);
    });

    for (final TextDirection direction in TextDirection.values) {
      _retainedTestWidgets('shared axis follows $direction in both ways', (
        WidgetTester tester,
      ) async {
        final double side = direction == TextDirection.ltr ? 1 : -1;
        await tester.pumpWidget(_retainedHost(0, direction: direction));
        await tester.pumpWidget(_retainedHost(1, direction: direction));
        expect(_left(tester, 1), 30 * side);
        await tester.pump(const Duration(milliseconds: 150));
        expect(_left(tester, 1) * side, inExclusiveRange(0, 30));
        expect(_left(tester, 0) * side, lessThan(0));
        expect(_switcherHeight(tester), inExclusiveRange(100, 240));
        await tester.pumpAndSettle();
        await tester.pumpWidget(_retainedHost(0, direction: direction));
        expect(_left(tester, 0), -30 * side);
        await tester.pump(const Duration(milliseconds: 150));
        expect(_left(tester, 0) * side, inExclusiveRange(-30, 0));
        await tester.pumpAndSettle();
        expect(_left(tester, 0), 0);
        expect(_built, 3);
        expect(_disposed, 0);
      });
    }

    for (final bool platformFlag in <bool>[false, true]) {
      _retainedTestWidgets(
        'the full retained clock survives motion flags $platformFlag',
        (
          WidgetTester tester,
        ) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: platformFlag);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          Widget host(int index) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: _retainedHost(index),
          );
          await tester.pumpWidget(host(0));
          await tester.pumpWidget(host(1));
          await tester.pump(const Duration(milliseconds: 150));
          expect(_left(tester, 1), inExclusiveRange(0, 30));
          expect(_left(tester, 0), lessThan(0));
          expect(_switcherHeight(tester), inExclusiveRange(100, 240));
          await tester.pump(const Duration(milliseconds: 140));
          expect(_left(tester, 1), greaterThan(0));
          await tester.pump(const Duration(milliseconds: 9));
          expect(_inputGates(tester), <bool>[false, false, false]);
          await tester.pump(const Duration(milliseconds: 1));
          expect(_inputGates(tester), <bool>[false, true, false]);
          await tester.pump();
          expect(_left(tester, 1), 0);
          expect(_switcherHeight(tester), 240);
          expect(_disposed, 0);
          expect(tester.binding.hasScheduledFrame, isFalse);
        },
      );
    }

    _retainedTestWidgets('interleaved entries retain state as height closes', (
      WidgetTester tester,
    ) async {
      Widget layout(BuildContext context, List<Widget> entries) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < entries.length; i++) ...<Widget>[
            Text('Header $i', textDirection: TextDirection.ltr),
            entries[i],
          ],
        ],
      );
      await tester.pumpWidget(_retainedHost(0, layoutBuilder: layout));
      await tester.pumpWidget(_retainedHost(1, layoutBuilder: layout));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_step(0), findsOneWidget);
      expect(_step(1), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_step(0), findsNothing);
      expect(_step(1), findsOneWidget);
      expect(_built, 3);
      expect(_disposed, 0);
      await tester.pumpWidget(_retainedHost(0, layoutBuilder: layout));
      await tester.pumpAndSettle();
      expect(_built, 3);
      expect(_disposed, 0);
    });

    _retainedTestWidgets('departed and incoming refuse focus and semantics', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final FocusNode oldFocus = FocusNode();
      final FocusNode newFocus = FocusNode();
      addTearDown(oldFocus.dispose);
      addTearDown(newFocus.dispose);
      int oldPresses = 0;
      int newPresses = 0;
      try {
        Widget host(int index) => MaterialApp(
          home: Scaffold(
            body: _retainedHost(
              index,
              children: <Widget>[
                TextButton(
                  focusNode: oldFocus,
                  onPressed: () => oldPresses++,
                  child: const Text('Old action'),
                ),
                TextButton(
                  focusNode: newFocus,
                  onPressed: () => newPresses++,
                  child: const Text('New action'),
                ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(host(0));
        oldFocus.requestFocus();
        await tester.pump();
        final SemanticsNode old = tester.getSemantics(find.text('Old action'));
        final SemanticsOwner owner = old.owner!;
        await tester.pumpWidget(host(1));
        await tester.pump();
        expect(oldFocus.hasFocus, isFalse);
        expect(oldFocus.canRequestFocus, isFalse);
        expect(newFocus.canRequestFocus, isFalse);
        oldFocus.requestFocus();
        newFocus.requestFocus();
        await tester.pump();
        expect(oldFocus.hasFocus || newFocus.hasFocus, isFalse);
        expect(find.semantics.byLabel('Old action'), findsNothing);
        expect(find.semantics.byLabel('New action'), findsNothing);
        owner.performAction(old.id, SemanticsAction.tap);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.tapAt(const Offset(100, 20));
        expect(oldPresses, 0);
        expect(newPresses, 0);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          newFocus.canRequestFocus,
          isTrue,
          reason: 'Current input gates: ${_inputGates(tester)}',
        );
        expect(find.semantics.byLabel('New action'), findsOneWidget);
        await tester.tap(find.text('New action'));
        expect(newPresses, 1);
        expect(oldPresses, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  });
}
