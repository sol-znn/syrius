import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_step_route.dart';

import 'support.dart';

Widget _boundary(Object source, VoidCallback action) => EntryActionBoundary(
  source: source,
  builder: (_, EntryActionLease lease) => Scaffold(
    body: OutlinedButton(
      key: const Key('fixture_action'),
      onPressed: lease.guard(action),
      child: const Text('Fixture action'),
    ),
  ),
);

VoidCallback _saved(WidgetTester tester) => tester
    .widget<OutlinedButton>(find.byKey(const Key('fixture_action')))
    .onPressed!;

void main() {
  testWidgets(
    'source replacement and disposal permanently revoke saved actions',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      int calls = 0;
      await tester.pumpWidget(entryHost(_boundary(Object(), () => calls++)));
      final VoidCallback first = _saved(tester);
      await tester.pumpWidget(entryHost(_boundary(Object(), () => calls++)));
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

  testWidgets('a dialog cover revokes the route generation across return', (
    WidgetTester tester,
  ) async {
    prepareEntryViewport(tester);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    int calls = 0;
    await tester.pumpWidget(
      entryHost(_boundary(Object(), () => calls++), navigator: navigator),
    );
    final VoidCallback saved = _saved(tester);
    final Future<void> dismissed = showDialog<void>(
      context: tester.element(find.byKey(const Key('fixture_action'))),
      builder: (_) => const AlertDialog(content: Text('Fixture cover')),
    );
    saved();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await dismissed;
    saved();
    expect(calls, 0);
    _saved(tester)();
    expect(calls, 1);
  });

  testWidgets(
    'hidden branches deny keyboard and retained callbacks on return',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final Object source = Object();
      int calls = 0;
      Widget host({required bool enabled}) =>
          entryHost(_boundary(source, () => calls++), enabled: enabled);
      await tester.pumpWidget(host(enabled: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final VoidCallback saved = _saved(tester);
      await tester.pumpWidget(host(enabled: false));
      saved();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpWidget(host(enabled: true));
      saved();
      expect(calls, 0);
      _saved(tester)();
      expect(calls, 1);
    },
  );

  testWidgets('foreground loss revokes the captured generation after resume', (
    WidgetTester tester,
  ) async {
    prepareEntryViewport(tester);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    int calls = 0;
    await tester.pumpWidget(entryHost(_boundary(Object(), () => calls++)));
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

  testWidgets(
    'the real onboarding route uses a preserving 300 ms shared axis',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        entryHost(
          const Scaffold(body: Text('Fixture origin')),
          navigator: navigator,
        ),
      );
      final OnboardingStepRoute<void> route = OnboardingStepRoute<void>(
        builder: (_) => const Scaffold(body: Text('Fixture next')),
      );
      navigator.currentState!.push<void>(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(route.animation!.value, closeTo(.5, .01));
      expect(find.byType(SharedAxisTransition), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 151));
      expect(route.animation!.value, 1);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(route.animation!.value, closeTo(.5, .01));
      await tester.pump(const Duration(milliseconds: 151));
      expect(find.text('Fixture origin'), findsOneWidget);
    },
  );

  testWidgets(
    'the actual shared-axis entrance refuses input until its endpoint',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      int calls = 0;
      await tester.pumpWidget(
        entryHost(
          const Scaffold(body: Text('Fixture origin')),
          navigator: navigator,
        ),
      );
      navigator.currentState!.push<void>(
        OnboardingStepRoute<void>(
          builder: (_) => _boundary(Object(), () => calls++),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final VoidCallback early = _saved(tester);
      early();
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 151));
      early();
      expect(calls, 0);
      _saved(tester)();
      expect(calls, 1);
    },
  );
}
