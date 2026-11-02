import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

const Cubic _spring = Cubic(0.2, 0.8, 0.2, 1);

LocalKey _key(String id) => ValueKey<String>(id);
Key _contentKey(String id) => ValueKey<String>('content_$id');

Widget _row(String id, {Widget? child}) => ListEntranceItem(
  key: _key(id),
  child: SizedBox(
    key: _contentKey(id),
    width: 240,
    height: 40,
    child: child ?? Text(id),
  ),
);

Widget _host(
  List<String> ids, {
  List<String>? mounted,
  Widget? body,
  Key? scopeKey,
  bool light = false,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 160,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: ListEntrance(
          key: scopeKey,
          itemKeys: ids.map(_key).toList(),
          child:
              body ??
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final String id in mounted ?? ids) _row(id),
                ],
              ),
        ),
      ),
    ),
  ),
);

Finder _within(String id, Type type) => find.descendant(
  of: find.byKey(_key(id)),
  matching: find.byType(type),
);

double _opacity(WidgetTester tester, String id) =>
    tester.widget<Opacity>(_within(id, Opacity).first).opacity;

double _rise(WidgetTester tester, String id) => tester
    .widget<Transform>(_within(id, Transform).first)
    .transform
    .storage[13];

void _expectProgress(WidgetTester tester, String id, int elapsed) {
  final double t = elapsed <= 0
      ? 0
      : elapsed >= 320
      ? 1
      : elapsed / 320;
  final double progress = _spring.transform(t);
  expect(_opacity(tester, id), closeTo(progress, 0.001), reason: id);
  expect(_rise(tester, id), closeTo(6 * (1 - progress), 0.01), reason: id);
}

void main() {
  testWidgets('the first cohort fades and rises 6 px, 40 ms apart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a', 'b', 'c']));
    for (final String id in <String>['a', 'b', 'c']) {
      _expectProgress(tester, id, 0);
      expect(tester.getSize(find.byKey(_key(id))), const Size(240, 40));
    }

    await tester.pump(const Duration(milliseconds: 20));
    _expectProgress(tester, 'a', 20);
    _expectProgress(tester, 'b', 0);
    _expectProgress(tester, 'c', 0);

    await tester.pump(const Duration(milliseconds: 40));
    _expectProgress(tester, 'a', 60);
    _expectProgress(tester, 'b', 20);
    _expectProgress(tester, 'c', 0);

    await tester.pump(const Duration(milliseconds: 260));
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 280);
    _expectProgress(tester, 'c', 240);
    await tester.pump(const Duration(milliseconds: 40));
    _expectProgress(tester, 'b', 320);
    _expectProgress(tester, 'c', 280);
    await tester.pump(const Duration(milliseconds: 40));
    _expectProgress(tester, 'c', 320);
    // The endpoint is visible at the deadline; the SDK retires its ticker
    // only once elapsed time is strictly greater than the duration.
    await tester.pump(const Duration(microseconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('an empty snapshot waits for the first populated cohort', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>[]));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host(<String>['a', 'b']));
    await tester.pump(const Duration(milliseconds: 20));
    _expectProgress(tester, 'a', 20);
    _expectProgress(tester, 'b', 0);
    await tester.pumpAndSettle();
  });

  testWidgets('rebuilds and sorting do not restart an active entrance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a', 'b', 'c']));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(_host(<String>['c', 'a', 'b']));
    _expectProgress(tester, 'a', 120);
    _expectProgress(tester, 'b', 80);
    _expectProgress(tester, 'c', 40);
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(<String>['b', 'c', 'a'], light: true));
    for (final String id in <String>['a', 'b', 'c']) {
      _expectProgress(tester, id, 320);
    }
  });

  testWidgets('later new rows enter once without delaying each other', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(<String>['a', 'b', 'c']));
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 0);
    _expectProgress(tester, 'c', 0);

    await tester.pump(const Duration(milliseconds: 160));
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 160);
    _expectProgress(tester, 'c', 160);
    await tester.pump(const Duration(milliseconds: 160));
    _expectProgress(tester, 'b', 320);
    _expectProgress(tester, 'c', 320);
  });

  testWidgets('a snapshot updated in place still admits its new identity', (
    WidgetTester tester,
  ) async {
    final List<LocalKey> keys = <LocalKey>[_key('a')];
    Widget page(List<String> ids) => MaterialApp(
      home: Scaffold(
        body: ListEntrance(
          itemKeys: keys,
          child: Column(
            children: <Widget>[for (final String id in ids) _row(id)],
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(<String>['a']));
    await tester.pumpAndSettle();
    keys.add(_key('b'));
    await tester.pumpWidget(page(<String>['a', 'b']));
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 0);
    await tester.pump(const Duration(milliseconds: 160));
    _expectProgress(tester, 'b', 160);
    await tester.pumpAndSettle();
  });

  testWidgets('removing and reinserting an identity does not replay it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a', 'b']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(<String>['b']));
    expect(find.byKey(_key('a')), findsNothing);

    await tester.pumpWidget(_host(<String>['b', 'a']));
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 320);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('an initial identity first mounted later is already settled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(<String>['a', 'b'], mounted: <String>['a']),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(<String>['a', 'b'], mounted: <String>['b']),
    );
    _expectProgress(tester, 'b', 320);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a later offscreen arrival does not animate when scrolled in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a']));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(<String>['a', 'b'], mounted: <String>['a']),
    );
    await tester.pumpWidget(
      _host(<String>['a', 'b'], mounted: <String>['a', 'b']),
    );
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 320);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('lazy disposal and a return to the viewport never replay rows', (
    WidgetTester tester,
  ) async {
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);
    final List<String> ids = List<String>.generate(
      100,
      (int index) => '$index',
    );
    await tester.pumpWidget(
      _host(
        ids,
        body: ListView.builder(
          controller: scroll,
          itemExtent: 40,
          itemCount: ids.length,
          itemBuilder: (BuildContext context, int index) => _row(ids[index]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    scroll.jumpTo(3000);
    await tester.pump();
    expect(find.byKey(_key('0')), findsNothing);
    _expectProgress(tester, '75', 320);

    scroll.jumpTo(0);
    await tester.pump();
    _expectProgress(tester, '0', 320);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a recreated unfinished row does not start its entrance again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a', 'b']));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(
      _host(<String>['a', 'b'], mounted: <String>['a']),
    );
    await tester.pumpWidget(_host(<String>['a', 'b']));
    _expectProgress(tester, 'b', 320);
    _expectProgress(tester, 'a', 20);
    await tester.pumpAndSettle();
  });

  testWidgets('replacing the view scope starts a fresh entrance history', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(<String>['a'], scopeKey: const ValueKey<String>('first')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(<String>['a'], scopeKey: const ValueKey<String>('second')),
    );
    _expectProgress(tester, 'a', 0);
    await tester.pump(const Duration(milliseconds: 160));
    _expectProgress(tester, 'a', 160);
    await tester.pumpAndSettle();
  });

  testWidgets('invisible rows take no pointer, focus or semantic action', (
    WidgetTester tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      int activated = 0;
      const Key button = ValueKey<String>('button_b');
      await tester.pumpWidget(
        _host(
          <String>['a', 'b'],
          body: Column(
            children: <Widget>[
              _row('a'),
              _row(
                'b',
                child: TextButton(
                  key: button,
                  focusNode: focus,
                  autofocus: true,
                  onPressed: () => activated++,
                  child: const Text('Run B'),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(_opacity(tester, 'b'), 0);
      expect(
        tester
            .widget<IgnorePointer>(_within('b', IgnorePointer).first)
            .ignoring,
        isTrue,
      );
      expect(
        tester.widget<Focus>(_within('b', Focus).first).descendantsAreFocusable,
        isFalse,
      );
      expect(find.bySemanticsLabel('Run B'), findsNothing);
      await tester.tap(find.byKey(button), warnIfMissed: false);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(activated, 0);

      await tester.pump(const Duration(milliseconds: 40));
      expect(_opacity(tester, 'b'), greaterThan(0));
      expect(find.bySemanticsLabel('Run B'), findsOneWidget);
      await tester.tap(find.byKey(button));
      expect(activated, 1);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activated, 2);
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('both OS and MediaQuery animation flags keep the full clock', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(
      _host(<String>['a', 'b'], disableAnimations: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    _expectProgress(tester, 'a', 100);
    _expectProgress(tester, 'b', 60);
    await tester.pump(const Duration(milliseconds: 220));
    _expectProgress(tester, 'a', 320);
    _expectProgress(tester, 'b', 280);
    await tester.pump(const Duration(milliseconds: 40));
    _expectProgress(tester, 'b', 320);
    // Keep the deadline assertion above; ticker retirement needs the next tick.
    await tester.pump(const Duration(microseconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the clock moves the wrapper without rebuilding its child', (
    WidgetTester tester,
  ) async {
    int builds = 0;
    await tester.pumpWidget(
      _host(
        <String>['a'],
        body: _row(
          'a',
          child: Builder(
            builder: (BuildContext context) {
              builds++;
              return const Text('12.5 ZNN');
            },
          ),
        ),
      ),
    );
    final int before = builds;
    for (int frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, before);
    expect(find.text('12.5 ZNN'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('disposing active and delayed rows releases all tickers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(<String>['a', 'b', 'c']));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('duplicate logical keys are rejected by the scope', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(<String>['a', 'a'], mounted: <String>['a']),
    );
    expect(
      tester.takeException().toString(),
      contains('ListEntrance.itemKeys must contain each logical key once.'),
    );
  });

  testWidgets('an item key must belong to its logical snapshot', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(<String>['a'], mounted: <String>['b']),
    );
    expect(
      tester.takeException().toString(),
      contains('A ListEntranceItem key must occur in ListEntrance.itemKeys.'),
    );
  });

  testWidgets('an item requires an entrance scope', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _row('a')));
    expect(
      tester.takeException().toString(),
      contains('ListEntranceItem requires a ListEntrance ancestor.'),
    );
  });
}
