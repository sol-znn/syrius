import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/shortcuts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool extraAlt = false,
}) async {
  final LogicalKeyboardKey modifier =
      defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (extraAlt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
  await tester.sendKeyEvent(key);
  if (extraAlt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Widget _app({
  required List<Intent> received,
  bool locked = false,
  Widget child = const SizedBox.shrink(),
}) {
  Action<T> record<T extends Intent>() => CallbackAction<T>(
    onInvoke: (T intent) {
      received.add(intent);
      return null;
    },
  );
  return MaterialApp(
    home: Scaffold(
      body: Shortcuts(
        shortcuts: locked ? kLockedShellShortcuts : kShellShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            OpenPageIntent: record<OpenPageIntent>(),
            OpenGoToIntent: record<OpenGoToIntent>(),
            ToggleRailIntent: record<ToggleRailIntent>(),
            RefreshPageIntent: record<RefreshPageIntent>(),
            ToggleBalancesIntent: record<ToggleBalancesIntent>(),
            ReplayLockIntent: record<ReplayLockIntent>(),
            DismissIntent: record<DismissIntent>(),
          },
          child: FocusScope(autofocus: true, child: child),
        ),
      ),
    ),
  );
}

void main() {
  const TargetPlatformVariant desktop = TargetPlatformVariant(
    <TargetPlatform>{
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    },
  );

  testWidgets('eight numbered destinations and numpad use the platform chord', (
    WidgetTester tester,
  ) async {
    final List<Intent> received = <Intent>[];
    await tester.pumpWidget(_app(received: received));
    await tester.pump();
    expect(
      kChordName,
      defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Ctrl',
    );
    const List<LogicalKeyboardKey> digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
    ];
    const List<LogicalKeyboardKey> pad = <LogicalKeyboardKey>[
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
    ];
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      ...digits,
      ...pad,
    ]) {
      await _chord(tester, key);
    }
    expect(
      received.whereType<OpenPageIntent>().map((OpenPageIntent i) => i.tab),
      <Tabs>[
        ...kRailPages.map((RailEntry e) => e.tab),
        ...kRailPages.map((RailEntry e) => e.tab),
      ],
    );
    received.clear();
    await _chord(tester, LogicalKeyboardKey.digit9);
    await _chord(tester, LogicalKeyboardKey.numpad9);
    expect(received, isEmpty);
  }, variant: desktop);

  testWidgets('shell commands retain text focus and reject AltGr modifiers', (
    WidgetTester tester,
  ) async {
    final List<Intent> received = <Intent>[];
    final TextEditingController field = TextEditingController(text: 'draft');
    addTearDown(field.dispose);
    await tester.pumpWidget(
      _app(
        received: received,
        child: TextField(controller: field, autofocus: true),
      ),
    );
    await tester.pump();
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.comma,
      LogicalKeyboardKey.keyL,
    ]) {
      await _chord(tester, key);
    }
    expect(received.map((Intent i) => i.runtimeType), <Type>[
      OpenGoToIntent,
      ToggleRailIntent,
      RefreshPageIntent,
      ToggleBalancesIntent,
      OpenPageIntent,
      OpenPageIntent,
    ]);
    expect((received[4] as OpenPageIntent).tab, Tabs.settings);
    expect((received[5] as OpenPageIntent).tab, Tabs.lock);
    expect(field.text, 'draft');
    received.clear();
    await _chord(tester, LogicalKeyboardKey.keyR, extraAlt: true);
    await _chord(tester, LogicalKeyboardKey.digit1, extraAlt: true);
    expect(received, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);

  testWidgets(
    'locked replay reaches its owner while password editing keeps focus',
    (WidgetTester tester) async {
      final List<Intent> received = <Intent>[];
      final TextEditingController field = TextEditingController(
        text: 'local fixture',
      );
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _app(
          received: received,
          locked: true,
          child: TextField(
            controller: field,
            autofocus: true,
            obscureText: true,
          ),
        ),
      );
      await tester.pump();
      final FocusNode? before = FocusManager.instance.primaryFocus;
      await _chord(tester, LogicalKeyboardKey.keyL);
      expect(received.single, isA<ReplayLockIntent>());
      expect(field.text, 'local fixture');
      expect(FocusManager.instance.primaryFocus, same(before));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'ordinary typing stays in the field and Escape reaches dismissal',
    (
      WidgetTester tester,
    ) async {
      final List<Intent> received = <Intent>[];
      await tester.pumpWidget(
        _app(received: received, child: const TextField(autofocus: true)),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'untouched recipient');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(received, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(received, hasLength(1));
      expect(received.single, isA<DismissIntent>());
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'locked shell exposes replay only and a modal owns its own keys',
    (
      WidgetTester tester,
    ) async {
      final List<Intent> received = <Intent>[];
      await tester.pumpWidget(_app(received: received, locked: true));
      await tester.pump();
      for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.comma,
      ]) {
        await _chord(tester, key);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(received, isEmpty);
      await _chord(tester, LogicalKeyboardKey.keyL);
      expect(received.single, isA<ReplayLockIntent>());
      received.clear();
      await tester.pumpWidget(
        _app(
          received: received,
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Owned modal')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await _chord(tester, LogicalKeyboardKey.keyR);
      expect(received, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Owned modal'), findsNothing);
      await _chord(tester, LogicalKeyboardKey.keyR);
      expect(received.single, isA<RefreshPageIntent>());
    },
    variant: desktop,
  );
}
