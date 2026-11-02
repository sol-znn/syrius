import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';

import 'support.dart';

Widget _action(Object source, VoidCallback callback) => SwapActionBoundary(
  source: source,
  builder: (_, SwapViewLease lease) => OutlinedButton(
    key: const Key('fixture_action'),
    onPressed: lease.guard(callback),
    child: const Text('Fixture action'),
  ),
);
VoidCallback _saved(WidgetTester tester) => tester
    .widget<OutlinedButton>(find.byKey(const Key('fixture_action')))
    .onPressed!;

void main() {
  testWidgets(
    'replacement and disposal permanently revoke the original callback',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      int calls = 0;
      await tester.pumpWidget(swapHost(_action(Object(), () => calls++)));
      final VoidCallback first = _saved(tester);
      await tester.pumpWidget(swapHost(_action(Object(), () => calls++)));
      first();
      expect(calls, 0);
      final VoidCallback second = _saved(tester);
      second();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      second();
      expect(calls, 1);
    },
  );

  testWidgets(
    'route coverage revokes saved actions even after the route returns',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      int calls = 0;
      await tester.pumpWidget(
        swapHost(_action(Object(), () => calls++), navigator: navigator),
      );
      final VoidCallback saved = _saved(tester);
      final Future<void> dialog = showDialog<void>(
        context: tester.element(find.byKey(const Key('fixture_action'))),
        builder: (_) => const AlertDialog(content: Text('Fixture cover')),
      );
      saved();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await dialog;
      saved();
      expect(calls, 0);
      _saved(tester)();
      expect(calls, 1);
    },
  );

  testWidgets(
    'hidden branches block keyboard and refuse retained actions after return',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final Object source = Object();
      int calls = 0;
      Widget host({required bool enabled}) =>
          swapHost(_action(source, () => calls++), enabled: enabled);
      await tester.pumpWidget(host(enabled: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final VoidCallback saved = _saved(tester);
      await tester.pumpWidget(host(enabled: false));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      saved();
      await tester.pumpWidget(host(enabled: true));
      saved();
      expect(calls, 0);
      _saved(tester)();
      expect(calls, 1);
    },
  );

  testWidgets('foreground loss revokes the generation across resume', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    int calls = 0;
    await tester.pumpWidget(swapHost(_action(Object(), () => calls++)));
    final VoidCallback saved = _saved(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    saved();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    saved();
    expect(calls, 0);
    _saved(tester)();
    expect(calls, 1);
  });

  testWidgets('an entering route accepts no action until its actual endpoint', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    int calls = 0;
    await tester.pumpWidget(
      swapHost(const Text('Fixture origin'), navigator: navigator),
    );
    final PageRouteBuilder<void> route = PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) =>
          Scaffold(body: _action(Object(), () => calls++)),
    );
    navigator.currentState!.push<void>(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final VoidCallback early = _saved(tester);
    early();
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 121));
    early();
    expect(calls, 0);
    _saved(tester)();
    expect(calls, 1);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });
}
