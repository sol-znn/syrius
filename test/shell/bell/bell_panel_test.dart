import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/event_toast.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/bell_panel.dart';

import 'support.dart';

Widget _app(
  BellController controller, {
  bool dark = true,
  bool rtl = false,
  FocusNode? field,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Directionality(
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                TextField(focusNode: field, key: const Key('underlying_field')),
                TextButton(
                  key: const Key('open_bell'),
                  onPressed: () => unawaited(
                    showBellPanel(context: context, controller: controller),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.topLeft,
              child: BellToast(controller: controller),
            ),
          ],
        ),
      ),
    ),
  ),
);

void _bellTest(
  String description,
  Future<void> Function(
    WidgetTester tester,
    MemoryBellHistory history,
    BellController controller,
  )
  body,
) {
  testWidgets(description, (WidgetTester tester) async {
    // Futures created by widget frames must finish before fake time stops.
    final MemoryBellHistory history = MemoryBellHistory();
    final BellController controller = bell(history)..setPrivate(value: false);
    try {
      await body(tester, history, controller);
    } finally {
      await _closeBell(tester, controller, history);
    }
  });
}

Future<void> _closeBell(
  WidgetTester tester,
  BellController controller,
  MemoryBellHistory history,
) async {
  try {
    await tester.pumpWidget(const SizedBox.shrink());
  } finally {
    try {
      await _finishOwnedFuture(tester, controller.close());
    } finally {
      await history.close();
    }
  }
}

Future<void> _finishOwnedFuture(
  WidgetTester tester,
  Future<void> operation,
) async {
  bool finished = false;
  final Future<void> observed = operation.whenComplete(() => finished = true);
  // Subscription cancellation may finish on the real event loop. Start the
  // operation in fake time, then let both queues progress before awaiting it.
  for (int turn = 0; turn < 20 && !finished; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(finished, isTrue, reason: 'Owned asynchronous cleanup must finish');
  await observed;
}

void main() {
  for (final bool dark in <bool>[true, false]) {
    _bellTest(
      'a 380 px frosted panel opens over $dark theme and clears unseen',
      (
        WidgetTester tester,
        MemoryBellHistory history,
        BellController controller,
      ) async {
        history.put(1, event(timestamp: DateTime.now().millisecondsSinceEpoch));
        expect(controller.hasUnseen.value, isTrue);
        await tester.pumpWidget(_app(controller, dark: dark));
        expect(find.byType(EventToast), findsNothing);
        await tester.tap(find.byKey(const Key('open_bell')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('bell_panel')), findsOneWidget);
        expect(tester.getSize(find.byKey(const Key('bell_panel'))).width, 380);
        expect(find.text('Stored event'), findsOneWidget);
        expect(find.byType(FrostedSurface), findsOneWidget);
        expect(controller.hasUnseen.value, isFalse);
        await tester.tap(find.byKey(const Key('bell_close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('bell_panel')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  _bellTest('full 240 ms motion remains under the OS animation flag', (
    WidgetTester tester,
    MemoryBellHistory history,
    BellController controller,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(_app(controller));
    await tester.tap(find.byKey(const Key('open_bell')));
    await tester.pump();
    final BuildContext panel = tester.element(
      find.byKey(const Key('bell_panel')),
    );
    final ModalRoute<dynamic> route = ModalRoute.of(panel)!;
    expect(route.transitionDuration, const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 120));
    expect(route.animation!.value, greaterThan(0));
    expect(route.animation!.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 120));
    expect(route.animation!.value, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _bellTest('RTL panel uses the reading end and Escape restores focus', (
    WidgetTester tester,
    MemoryBellHistory history,
    BellController controller,
  ) async {
    final FocusNode field = FocusNode();
    await tester.pumpWidget(_app(controller, rtl: true, field: field));
    field.requestFocus();
    await tester.pump();
    // A shell shortcut opens the panel without moving focus to its opener.
    final BuildContext context = tester.element(
      find.byKey(const Key('open_bell')),
    );
    final Future<void> closed = showBellPanel(
      context: context,
      controller: controller,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('bell_panel'))).dx, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _finishOwnedFuture(tester, closed);
    expect(find.byKey(const Key('bell_panel')), findsNothing);
    expect(field.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    field.dispose();
  });

  _bellTest('privacy removes this panel while preserving a newer route', (
    WidgetTester tester,
    MemoryBellHistory history,
    BellController controller,
  ) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(controller, navigator: navigator));
    await tester.tap(find.byKey(const Key('open_bell')));
    await tester.pumpAndSettle();
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unrelated route')),
      ),
    );
    await tester.pumpAndSettle();
    controller.setPrivate(value: true);
    await tester.pumpAndSettle();
    expect(find.text('Unrelated route'), findsOneWidget);
    expect(
      find.byKey(const Key('bell_panel'), skipOffstage: false),
      findsNothing,
    );
    expect(FrostHold.count.value, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _bellTest(
    'new events use the five-second toast without replay or seen marks',
    (
      WidgetTester tester,
      MemoryBellHistory history,
      BellController controller,
    ) async {
      history.items[0] = event(title: 'Old');
      controller.refresh();
      await tester.pumpWidget(_app(controller));
      expect(find.byType(EventToast), findsNothing);
      history.put(1, event(title: 'Fresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Fresh'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(EventToast), findsNothing);
      expect(controller.hasUnseen.value, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('real pending scope leads history and Clear never decides', (
    WidgetTester tester,
  ) async {
    final FakeApprovalClient client = FakeApprovalClient()..add(1);
    final MemoryBellHistory history = MemoryBellHistory();
    final BellController controller = bell(
      history,
      approvals: client.controller,
    )..setPrivate(value: false);
    try {
      history.put(1, event());
      await tester.pumpWidget(_app(controller));
      await tester.tap(find.byKey(const Key('open_bell')));
      await tester.pumpAndSettle();
      expect(find.text('NEEDS YOU'), findsOneWidget);
      expect(find.text('app.example'), findsOneWidget);
      expect(find.text('zenon:1:address-a'), findsOneWidget);
      expect(find.text('zenon:1:address-b'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byKey(const Key('bell_clear')));
      await tester.pump();
      expect(client.approveCalls + client.declineCalls, 0);
      expect(client.controller.value, hasLength(1));
      expect(history.items, isEmpty);
    } finally {
      try {
        await _closeBell(tester, controller, history);
      } finally {
        client.controller.dispose();
      }
    }
  });

  testWidgets('widget teardown awaits seen writes and owned stream closure', (
    WidgetTester tester,
  ) async {
    final MemoryBellHistory history = MemoryBellHistory();
    final Completer<void> writing = Completer<void>();
    final Completer<void> finishWrite = Completer<void>();
    final List<List<String>> persisted = <List<String>>[];
    final BellController controller = BellController(
      history: history,
      scope: testScope,
      readSeen: (String scope) => <String>[],
      writeSeen: (String scope, List<String> identities) async {
        if (!writing.isCompleted) writing.complete();
        await finishWrite.future;
        persisted.add(identities);
      },
    )..setPrivate(value: false);
    final Future<void> toastsClosed = controller.toasts.drain<void>();
    final Future<void> statesClosed = controller.stream.drain<void>();
    try {
      history.put(1, event());
      await tester.pumpWidget(_app(controller));
      await tester.tap(find.byKey(const Key('open_bell')));
      await tester.pumpAndSettle();
      expect(writing.isCompleted, isTrue);
      expect(controller.hasUnseen.value, isFalse);
      final Set<String> acknowledged = controller.state.identities;
      await tester.pumpWidget(const SizedBox.shrink());
      bool closed = false;
      final Future<void> firstClose = controller.close().then<void>((_) {
        closed = true;
      });
      final Future<void> secondClose = controller.close();
      await tester.pump();
      expect(controller.state.private, isTrue);
      expect(closed, isFalse);
      expect(persisted, isEmpty);
      finishWrite.complete();
      await _finishOwnedFuture(tester, firstClose);
      await secondClose;
      await toastsClosed;
      await statesClosed;
      expect(closed, isTrue);
      expect(controller.isClosed, isTrue);
      expect(persisted, hasLength(1));
      expect(persisted.single, unorderedEquals(acknowledged));
      await controller.close();
    } finally {
      if (!finishWrite.isCompleted) finishWrite.complete();
      await _closeBell(tester, controller, history);
      await toastsClosed;
      await statesClosed;
    }
  });
}
