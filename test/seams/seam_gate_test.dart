import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';

const Key _surface = Key('seam_surface');
const Key _control = Key('seam_control');

Widget _app(
  Widget child, {
  bool dark = false,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  theme: dark ? ThemeData.dark() : ThemeData.light(),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(key: _surface, child: child),
    ),
  ),
);

Future<Uint8List> _pixels(WidgetTester tester) async {
  final RenderRepaintBoundary surface = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_surface));
  final ByteData? data = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await surface.toImage();
    try {
      return await image.toByteData();
    } finally {
      image.dispose();
    }
  });
  return data!.buffer.asUint8List();
}

void main() {
  for (final bool dark in <bool>[false, true]) {
    testWidgets('keeps paint and geometry in ${dark ? 'dark' : 'light'}', (
      WidgetTester tester,
    ) async {
      final Widget control = SizedBox(
        key: _control,
        width: 180,
        height: 56,
        child: ElevatedButton(onPressed: () {}, child: const Text('Zap')),
      );
      await tester.pumpWidget(_app(control, dark: dark));
      await tester.pumpAndSettle();
      final Rect before = tester.getRect(find.byKey(_control));
      final Size size = tester.getSize(find.byKey(_surface));
      final Uint8List paint = await _pixels(tester);

      await tester.pumpWidget(
        _app(
          SeamGate(seam: Seam.zapSend, child: control),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_control)), before);
      expect(tester.getSize(find.byKey(_surface)), size);
      expect(await _pixels(tester), orderedEquals(paint));
    });
  }

  testWidgets('denies taps, double taps and long presses', (
    WidgetTester tester,
  ) async {
    int activated = 0;
    await tester.pumpWidget(
      _app(
        SeamGate(
          seam: Seam.zapSend,
          child: GestureDetector(
            onTap: () => activated++,
            onDoubleTap: () => activated++,
            onLongPress: () => activated++,
            child: const SizedBox(key: _control, width: 180, height: 56),
          ),
        ),
      ),
    );
    final Offset at = tester.getCenter(find.byKey(_control));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.longPressAt(at);
    await tester.pumpAndSettle();
    expect(activated, 0);
  });

  testWidgets('skips focus and cannot activate with Enter or Space', (
    WidgetTester tester,
  ) async {
    final FocusNode before = FocusNode();
    final FocusNode gated = FocusNode();
    final FocusNode after = FocusNode();
    addTearDown(before.dispose);
    addTearDown(gated.dispose);
    addTearDown(after.dispose);
    int activated = 0;
    await tester.pumpWidget(
      _app(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton(
              focusNode: before,
              onPressed: () {},
              child: const Text('Before'),
            ),
            SeamGate(
              seam: Seam.zapSend,
              child: TextButton(
                focusNode: gated,
                onPressed: () => activated++,
                child: const Text('Zap'),
              ),
            ),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After'),
            ),
          ],
        ),
      ),
    );
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(after.hasFocus, isTrue);
    expect(gated.canRequestFocus, isFalse);
    gated.requestFocus();
    await tester.pump();
    expect(gated.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(activated, 0);
  });

  testWidgets('removes semantic actions and exposes a disabled node', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      int activated = 0;
      await tester.pumpWidget(
        _app(
          SeamGate(
            seam: Seam.walletPicker,
            child: Semantics(
              label: 'Money action',
              onTap: () => activated++,
              onLongPress: () => activated++,
              onSetText: (String value) => activated++,
              child: const SizedBox(width: 180, height: 56),
            ),
          ),
        ),
      );
      final SemanticsNode node = tester.getSemantics(find.byType(SeamGate));
      expect(
        node,
        isSemantics(label: 'Not yet', hasEnabledState: true, isEnabled: false),
      );
      expect(find.semantics.byLabel('Money action'), findsNothing);
      for (final ui.SemanticsAction action in <ui.SemanticsAction>[
        ui.SemanticsAction.tap,
        ui.SemanticsAction.longPress,
        ui.SemanticsAction.focus,
        ui.SemanticsAction.setText,
      ]) {
        expect(node.getSemanticsData().hasAction(action), isFalse);
        node.owner!.performAction(node.id, action, 'injected');
      }
      await tester.pump();
      expect(activated, 0);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('takes focus away when an active control becomes gated', (
    WidgetTester tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    int activated = 0;
    final Widget control = TextButton(
      focusNode: focus,
      onPressed: () => activated++,
      child: const Text('Zap'),
    );
    await tester.pumpWidget(_app(control));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.pumpWidget(
      _app(SeamGate(seam: Seam.zapSend, child: control)),
    );
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activated, 0);
  });

  testWidgets('clears a focused control reparented into an existing gate', (
    WidgetTester tester,
  ) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    final Widget control = TextButton(
      key: GlobalKey(),
      focusNode: focus,
      onPressed: () {},
      child: const Text('Zap'),
    );
    const Key gate = Key('existing_gate');
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            control,
            const SeamGate(
              key: gate,
              seam: Seam.zapSend,
              child: SizedBox(width: 180, height: 56),
            ),
          ],
        ),
      ),
    );
    final State<SeamGate> existing = tester.state<State<SeamGate>>(
      find.byKey(gate),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(width: 180, height: 56),
            SeamGate(key: gate, seam: Seam.zapSend, child: control),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.state<State<SeamGate>>(find.byKey(gate)), same(existing));
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
  });

  testWidgets('keeps the basic cursor and shows the localized tooltip', (
    WidgetTester tester,
  ) async {
    int hovered = 0;
    await tester.pumpWidget(
      _app(
        SeamGate(
          seam: Seam.zapSend,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => hovered++,
            child: const SizedBox(key: _control, width: 180, height: 56),
          ),
        ),
        locale: const Locale('ar'),
      ),
    );
    final String message = lookupAppLocalizations(const Locale('ar')).notYet;
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(_control)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(hovered, 0);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, message);
    expect(find.text(message), findsOneWidget);
  });

  test('indirect callbacks refuse every seam before invoking the action', () {
    int invoked = 0;
    for (final Seam seam in Seam.values) {
      expect(runUnlessSeamed(seam: seam, action: () => invoked++), isFalse);
    }
    expect(invoked, 0);
    expect(runUnlessSeamed(seam: null, action: () => invoked++), isTrue);
    expect(invoked, 1);
  });

  testWidgets('a guarded global shortcut cannot invoke the missing action', (
    WidgetTester tester,
  ) async {
    bool? accepted;
    int invoked = 0;
    await tester.pumpWidget(
      _app(
        CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
              accepted = runUnlessSeamed(
                seam: Seam.zapSend,
                action: () => invoked++,
              );
            },
          },
          child: const Focus(autofocus: true, child: Text('Shortcut host')),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(accepted, isFalse);
    expect(invoked, 0);
  });

  testWidgets('a guarded palette callback leaves the current route in place', (
    WidgetTester tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () {
              accepted = runUnlessSeamed(
                seam: Seam.walletPicker,
                action: () => Navigator.of(context).pop(),
              );
            },
            child: const Text('Choose wallet'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose wallet'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    expect(find.text('Choose wallet'), findsOneWidget);
  });
}
