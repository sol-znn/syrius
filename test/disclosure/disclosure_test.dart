import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

const Key _disclosure = Key('disclosure');
const Key _body = Key('body');
const Key _rest = Key('rest');
const Key _toggle = ValueKey<String>('stake_toggle');

/// Where a disclosure's state is stored, written out and not read from the
/// widget's file: a profile holds entries under this prefix, so a change to
/// it loses every reader's choices and should fail a test.
const String _prefix = 'disclosure_open_';

const double _header = 44;
const double _bodyHeight = 60;

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SizedBox(width: 400, height: 600, child: child),
        ),
      ),
    );

/// A disclosure above whatever takes the height it leaves, as a form sits
/// above a list on a page.
Widget _stacked(Widget disclosure, {Widget? after}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[
    disclosure,
    ?after,
    const Expanded(child: SizedBox.expand(key: _rest)),
  ],
);

Disclosure _plain({
  bool initiallyOpen = false,
  bool keepAlive = false,
  String title = 'New stake',
  String? storeKey,
  int? count,
  String? summary,
  DisclosureController? controller,
  ValueChanged<bool>? onChanged,
  Widget child = const SizedBox(key: _body, height: _bodyHeight),
}) => Disclosure(
  key: _disclosure,
  title: title,
  count: count,
  summary: summary,
  storeKey: storeKey,
  initiallyOpen: initiallyOpen,
  keepAlive: keepAlive,
  controller: controller,
  onChanged: onChanged,
  keyPrefix: 'stake',
  child: child,
);

Finder _chevron() => find.byIcon(Icons.expand_more);

double _height(WidgetTester tester, Key key) =>
    tester.getSize(find.byKey(key)).height;

/// How far the chevron is turned, in turns.
double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find
          .ancestor(of: _chevron(), matching: find.byType(RotationTransition))
          .first,
    )
    .turns
    .value;

/// The clip round the body, which is on only while it moves.
Clip _clip(WidgetTester tester) => tester
    .widget<ClipRect>(
      find
          .ancestor(of: find.byKey(_body), matching: find.byType(ClipRect))
          .first,
    )
    .clipBehavior;

void main() {
  group('a disclosure, with no preferences open', () {
    testWidgets('is closed by default: its header, and no body in the tree', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_stacked(_plain())));

      expect(tester.takeException(), isNull);
      expect(find.byKey(_body, skipOffstage: false), findsNothing);
      expect(_height(tester, _disclosure), _header);
      expect(_height(tester, _rest), 600 - _header);
      // Sideways, pointing the way the text runs on.
      expect(_turns(tester), -0.25);
      expect(tester.getRect(find.text('New stake')).left, 16);
      expect(tester.getRect(_chevron()).right, 400 - 12);
      // It starts where it is: nothing moves as the page is shown.
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('starts open with initiallyOpen, unclipped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_stacked(_plain(initiallyOpen: true))));

      expect(find.byKey(_body), findsOneWidget);
      expect(_height(tester, _disclosure), _header + _bodyHeight);
      expect(_turns(tester), 0);
      expect(_clip(tester), Clip.none);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a tap opens it, mid-height half way, and another closes it', (
      WidgetTester tester,
    ) async {
      final List<bool> changes = <bool>[];
      await tester.pumpWidget(
        _host(_stacked(_plain(onChanged: changes.add))),
      );

      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(changes, <bool>[true]);
      await tester.pump(const Duration(milliseconds: 120));

      // On the way: between the two heights, the body at its full height
      // under the clip, so nothing overflows, and above its place.
      final double mid = _height(tester, _disclosure);
      expect(mid, greaterThan(_header));
      expect(mid, lessThan(_header + _bodyHeight));
      expect(_height(tester, _rest), 600 - mid);
      expect(_height(tester, _body), _bodyHeight);
      expect(_clip(tester), Clip.hardEdge);
      final double top = tester.getRect(find.byKey(_body)).top;
      expect(top, lessThan(_header));
      expect(top, greaterThan(_header - 8));
      final double opacity = tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(_body),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));
      // The chevron is on its way too, and ahead of the body.
      expect(_turns(tester), greaterThan(-0.25));
      expect(_turns(tester), lessThan(0));
      expect(tester.takeException(), isNull);

      // The chevron is there 20 ms before the height is.
      await tester.pump(const Duration(milliseconds: 105));
      expect(_turns(tester), 0);
      expect(_clip(tester), Clip.hardEdge);

      await tester.pumpAndSettle();
      expect(_height(tester, _disclosure), _header + _bodyHeight);
      expect(tester.getRect(find.byKey(_body)).top, _header);
      expect(_clip(tester), Clip.none);
      expect(tester.binding.transientCallbackCount, 0);

      // Anywhere on the row, not only on the title or the chevron.
      await tester.tapAt(const Offset(200, _header / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_height(tester, _disclosure), greaterThan(_header));
      expect(_height(tester, _disclosure), lessThan(_header + _bodyHeight));
      expect(_clip(tester), Clip.hardEdge);
      await tester.pumpAndSettle();

      expect(changes, <bool>[true, false]);
      expect(find.byKey(_body, skipOffstage: false), findsNothing);
      expect(_height(tester, _disclosure), _header);
      expect(_turns(tester), -0.25);
    });

    testWidgets('a close turned back before it ends leaves the body in place', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_stacked(_plain(initiallyOpen: true))));

      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();

      expect(find.byKey(_body), findsOneWidget);
      expect(_height(tester, _disclosure), _header + _bodyHeight);
      expect(_clip(tester), Clip.none);
    });

    testWidgets('moves at full length when the system asks for less motion', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(_host(_stacked(_plain())));

      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      // A controller left to the system's setting would be done in 12 ms.
      await tester.pump(const Duration(milliseconds: 100));
      expect(_height(tester, _disclosure), greaterThan(_header));
      expect(_height(tester, _disclosure), lessThan(_header + _bodyHeight));
      expect(_turns(tester), lessThan(0));
      await tester.pumpAndSettle();
      expect(_height(tester, _disclosure), _header + _bodyHeight);
    });

    testWidgets('Enter and Space toggle it when the header has the focus', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_stacked(_plain())));

      // Not focused: the keys are not the header's.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsOneWidget);

      // The header is still there to be pressed, and still has the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsOneWidget);
    });

    testWidgets('the header is a button, for the pointer and a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(_stacked(_plain())));

      expect(
        tester.getSemantics(find.byKey(_toggle)),
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(200, 400));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      // Anywhere on the row, the empty middle included.
      await mouse.moveTo(const Offset(250, _header / 2));
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(_toggle)),
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the count follows the title and the summary keeps the end', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(_stacked(_plain(count: 12, summary: 'Sporks mode'))),
      );

      final Rect title = tester.getRect(find.text('New stake'));
      final Rect count = tester.getRect(find.text('12'));
      final Rect summary = tester.getRect(find.text('Sporks mode'));
      final Rect chevron = tester.getRect(_chevron());
      expect(count.left, title.right + AppTokens.dark.cardGap);
      // A short title's slack goes between the two, not after the chevron.
      expect(chevron.right, 400 - 12);
      expect(summary.right, chevron.left - 8);
      expect(summary.left, greaterThan(count.right));
      expect(
        tester.widget<Text>(find.text('12')).style!.color,
        AppTokens.dark.faint,
      );
      expect(_height(tester, _disclosure), _header);
    });

    testWidgets(
      'right to left, the chevron keeps the end of the row, which is the '
      'left, and turns from the other side',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _host(
            _stacked(_plain(count: 3, summary: 'Later')),
            direction: TextDirection.rtl,
          ),
        );

        final Rect title = tester.getRect(find.text('New stake'));
        final Rect count = tester.getRect(find.text('3'));
        final Rect summary = tester.getRect(find.text('Later'));
        final Rect chevron = tester.getRect(_chevron());
        expect(title.right, 400 - 16);
        expect(count.right, title.left - AppTokens.dark.cardGap);
        expect(chevron.left, 12);
        expect(summary.left, chevron.right + 8);
        expect(_turns(tester), 0.25);

        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(_turns(tester), 0);
        expect(tester.getRect(_chevron()).left, 12);
        // The body is as wide as the header, from the same edge.
        expect(
          tester.getRect(find.byKey(_body)),
          const Rect.fromLTWH(0, _header, 400, _bodyHeight),
        );
      },
    );
  });

  group('keepAlive', () {
    testWidgets('keeps what was typed across a close, out of reach while '
        'closed', (WidgetTester tester) async {
      final FocusNode field = FocusNode();
      final FocusNode next = FocusNode();
      addTearDown(field.dispose);
      addTearDown(next.dispose);
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          _stacked(
            _plain(
              keepAlive: true,
              child: TextField(key: _body, focusNode: field),
            ),
            after: TextButton(
              focusNode: next,
              onPressed: () {},
              child: const Text('Next'),
            ),
          ),
        ),
      );

      // Mounted from the start, and neither seen nor reachable.
      expect(find.byKey(_body), findsNothing);
      expect(find.byKey(_body, skipOffstage: false), findsOneWidget);
      expect(_height(tester, _disclosure), _header);
      expect(field.canRequestFocus, isFalse);
      expect(find.bySemanticsLabel('Next'), findsOneWidget);
      expect(find.semantics.byFlag(SemanticsFlag.isTextField), findsNothing);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsOneWidget);
      expect(field.canRequestFocus, isTrue);
      expect(find.semantics.byFlag(SemanticsFlag.isTextField), findsOne);
      final State<StatefulWidget> state = tester.state(find.byKey(_body));

      await tester.enterText(find.byKey(_body), 'half typed');
      await tester.pump();
      expect(field.hasFocus, isTrue);

      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      // The focus leaves as the close begins, not when it ends.
      expect(field.hasFocus, isFalse);
      await tester.pumpAndSettle();

      expect(find.byKey(_body), findsNothing);
      expect(find.text('half typed', skipOffstage: false), findsOneWidget);
      expect(_height(tester, _disclosure), _header);
      expect(find.semantics.byFlag(SemanticsFlag.isTextField), findsNothing);
      // A closed form runs no ticker of its own, a cursor's included.
      expect(tester.binding.transientCallbackCount, 0);

      // Tab goes from the header past the hidden field.
      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(field.hasFocus, isFalse);
      expect(next.hasFocus, isTrue);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.text('half typed'), findsOneWidget);
      expect(tester.state(find.byKey(_body)), same(state));
      expect(field.canRequestFocus, isTrue);
      semantics.dispose();
    });

    testWidgets('left off, a closed body is gone and what it held with it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _stacked(
            _plain(initiallyOpen: true, child: const TextField(key: _body)),
          ),
        ),
      );
      await tester.enterText(find.byKey(_body), 'half typed');
      await tester.pump();

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(_body, skipOffstage: false), findsNothing);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsOneWidget);
      expect(find.text('half typed'), findsNothing);
    });
  });

  group('a controller', () {
    for (final bool keepAlive in <bool>[false, true]) {
      testWidgets(
        'a closing body rejects input and semantics immediately, '
        'keepAlive $keepAlive',
        (WidgetTester tester) async {
          final DisclosureController controller = DisclosureController(
            open: true,
          );
          final FocusNode action = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(action.dispose);
          final SemanticsHandle semantics = tester.ensureSemantics();
          try {
            int presses = 0;
            await tester.pumpWidget(
              _host(
                _stacked(
                  Disclosure.bare(
                    key: _disclosure,
                    controller: controller,
                    keepAlive: keepAlive,
                    child: SizedBox(
                      key: _body,
                      height: _bodyHeight,
                      child: TextButton(
                        focusNode: action,
                        onPressed: () => presses++,
                        child: const Text('Confirm stake'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            action.requestFocus();
            await tester.pump();
            expect(action.hasFocus, isTrue);
            expect(find.semantics.byLabel('Confirm stake'), findsOne);

            controller.close();
            await tester.pump();
            // No time has passed: the whole button is still painted, but the
            // closing state must not accept another financial action.
            expect(_height(tester, _disclosure), _bodyHeight);
            expect(find.byKey(_body), findsOneWidget);
            expect(action.hasFocus, isFalse);
            expect(action.canRequestFocus, isFalse);
            expect(find.semantics.byLabel('Confirm stake'), findsNothing);
            await tester.tapAt(tester.getCenter(find.byKey(_body)));
            await tester.pump(const Duration(milliseconds: 120));
            expect(_height(tester, _disclosure), greaterThan(0));
            expect(_height(tester, _disclosure), lessThan(_bodyHeight));
            expect(find.semantics.byLabel('Confirm stake'), findsNothing);
            await tester.tapAt(tester.getCenter(find.byKey(_body)));
            await tester.pump();
            expect(presses, 0);

            controller.open();
            await tester.pumpAndSettle();
            expect(action.canRequestFocus, isTrue);
            expect(find.semantics.byLabel('Confirm stake'), findsOne);
            await tester.tap(find.text('Confirm stake'));
            await tester.pumpAndSettle();
            expect(presses, 1);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets('opens and closes a bare disclosure, which has no header', (
      WidgetTester tester,
    ) async {
      final DisclosureController controller = DisclosureController();
      addTearDown(controller.dispose);
      final List<bool> changes = <bool>[];
      await tester.pumpWidget(
        _host(
          _stacked(
            Disclosure.bare(
              key: _disclosure,
              controller: controller,
              onChanged: changes.add,
              child: const SizedBox(key: _body, height: _bodyHeight),
            ),
          ),
        ),
      );

      expect(_height(tester, _disclosure), 0);
      expect(find.byKey(_body, skipOffstage: false), findsNothing);
      expect(_chevron(), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(controller.isOpen, isFalse);

      controller.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_height(tester, _disclosure), greaterThan(0));
      expect(_height(tester, _disclosure), lessThan(_bodyHeight));
      await tester.pumpAndSettle();
      expect(_height(tester, _disclosure), _bodyHeight);
      expect(controller.isOpen, isTrue);

      // Asked for what it already is, it does nothing.
      controller.open();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      controller.toggle();
      await tester.pumpAndSettle();
      expect(find.byKey(_body, skipOffstage: false), findsNothing);
      expect(_height(tester, _rest), 600);
      expect(changes, <bool>[true, false]);
    });

    testWidgets('follows the header, and tells its listeners', (
      WidgetTester tester,
    ) async {
      final DisclosureController controller = DisclosureController();
      addTearDown(controller.dispose);
      int told = 0;
      controller.addListener(() => told++);
      await tester.pumpWidget(
        _host(_stacked(_plain(controller: controller))),
      );
      expect(told, 0);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);
      expect(told, 1);

      controller.close();
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsNothing);
      expect(_turns(tester), -0.25);
      expect(told, 2);
    });

    testWidgets('told to open before the disclosure exists, opens it', (
      WidgetTester tester,
    ) async {
      final DisclosureController controller = DisclosureController()..open();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(_stacked(_plain(controller: controller))),
      );

      expect(find.byKey(_body), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);

      // Gone with its page, it no longer listens.
      await tester.pumpWidget(_host(const SizedBox()));
      controller.close();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the stored state', () {
    late Directory dir;
    late Box<dynamic> preferences;

    // Kept in memory: a toggle stores as it is pressed, under the test's
    // fake clock, and a write to a file begun there never finishes.
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('syrius_disclosure_');
      Hive.init(dir.path);
      preferences = await Hive.openBox<dynamic>(
        kSharedPrefsBox,
        bytes: Uint8List(0),
      );
    });

    tearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('is written under the key at each toggle, by whoever toggles', (
      WidgetTester tester,
    ) async {
      final DisclosureController controller = DisclosureController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          _stacked(_plain(storeKey: 'test.stake', controller: controller)),
        ),
      );
      // Showing it stores nothing: it stays "never chosen".
      expect(preferences.keys, isEmpty);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(preferences.get('${_prefix}test.stake'), isTrue);
      expect(preferences.keys, <String>['${_prefix}test.stake']);

      controller.close();
      await tester.pumpAndSettle();
      expect(preferences.get('${_prefix}test.stake'), isFalse);
    });

    testWidgets('is read back the next time it is built, open at once', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(_stacked(_plain(storeKey: 'test.stake'))),
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();

      // Another page, then this one again, in another language: a new
      // disclosure, the same key.
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpWidget(
        _host(_stacked(_plain(storeKey: 'test.stake', title: 'Neuer Stake'))),
      );
      expect(find.byKey(_body), findsOneWidget);
      expect(_height(tester, _disclosure), _header + _bodyHeight);
      // It does not open again in front of them.
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('closed wins over initiallyOpen, and over an open controller', (
      WidgetTester tester,
    ) async {
      await preferences.put('${_prefix}test.stake', false);
      final DisclosureController controller = DisclosureController(open: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          _stacked(
            _plain(
              storeKey: 'test.stake',
              initiallyOpen: true,
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byKey(_body), findsNothing);
      // The controller says where the disclosure is, not where it was told
      // to be.
      expect(controller.isOpen, isFalse);
    });

    testWidgets("is one disclosure's, and nothing is stored without a key", (
      WidgetTester tester,
    ) async {
      await preferences.put('${_prefix}test.stake', true);
      await tester.pumpWidget(_host(_stacked(_plain(storeKey: 'test.fuse'))));
      expect(find.byKey(_body), findsNothing);

      // The same widget given another key reads that key's state.
      await tester.pumpWidget(
        _host(_stacked(_plain(storeKey: 'test.stake'))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsOneWidget);

      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pumpWidget(_host(_stacked(_plain())));
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(preferences.keys, <String>['${_prefix}test.stake']);
    });

    testWidgets('a damaged entry reads as never chosen', (
      WidgetTester tester,
    ) async {
      await preferences.put('${_prefix}test.stake', 'open');
      await tester.pumpWidget(
        _host(_stacked(_plain(storeKey: 'test.stake'))),
      );
      expect(find.byKey(_body), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
