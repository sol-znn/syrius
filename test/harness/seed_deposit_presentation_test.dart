import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/start_native_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';

import '../../harness/app/fixtures/seed_deposit_presentation.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../../harness/app/seed_deposit_presentation_binding.dart';
import '../swap_actions/support.dart';
import '../swap_actions_redesign/support.dart' show
    fixtureDollars, prepareSwapViewport, swapFrames, swapHost;

Matcher _refused() => throwsA(isA<SeedRefused>());

Future<void> _frames(WidgetTester tester) async {
  await swapFrames(tester);
  await tester.pump(const Duration(milliseconds: 300));
  await swapFrames(tester);
}

Future<void> _close(WidgetTester tester, Future<void> original) async {
  bool done = false;
  Object? error;
  StackTrace? trace;
  unawaited(original.then((_) { done = true; },
    onError: (Object value, StackTrace stack) {
      error = value;
      trace = stack;
      done = true;
    },
  ));
  for (int frame = 0; frame < 120 && !done; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue);
  if (error != null) Error.throwWithStackTrace(error!, trace!);
}

SeedDepositPresentation _presentation({
  required Future<Object?> route,
  required Future<void> Function(VoidCallback) tap,
  bool Function()? current,
  bool Function(String)? submitted,
  Duration timeout = const Duration(seconds: 5),
}) => SeedDepositPresentation(
  originalCurrent: current ?? () => true,
  submittedCurrent: submitted ?? (String hash) => hash == actionHash(1),
  tapOriginalExit: tap,
  originalRouteCompleted: route,
  closeTimeout: timeout,
);

class _DepositRoute {
  final ActionFixture source = ActionFixture();
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  late final SwapActionOrigin origin = source.origin();
  late StateSetter redraw;
  int revision = 0;
  int exits = 0;

  CapturedSwapModal<StartNativeSwapModal> state(WidgetTester tester) =>
      tester.state(find.byType(StartNativeSwapModal))
          as CapturedSwapModal<StartNativeSwapModal>;

  Future<SeedDepositPresentation> submit(
    WidgetTester tester, {
    bool light = false,
  }) async {
    await tester.pumpWidget(swapHost(Builder(
      builder: (BuildContext context) => OutlinedButton(
        key: const Key('fixture_home'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (_, StateSetter update) {
              redraw = update;
              return StartNativeSwapModal(
                key: ValueKey<int>(revision),
                onSwapStarted: (_) {}, source: origin,
                sourceIsCurrent: () => source.current,
                dollars: fixtureDollars,
              );
            },
          ),
        ),
        child: const Text('Home'),
      ),
    ), navigator: navigator, light: light));
    await tester.tap(find.byKey(const Key('fixture_home')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('swap_amount_input')).first,
        '1');
    await tester.enterText(find.byKey(const Key('swap_counterparty_input')),
        source.counterparty);
    await tester.tap(find.byKey(const Key('swap_action_details_toggle')));
    await _frames(tester);
    final Finder button = find.byKey(const Key('swap_create_deposit'));
    await tester.ensureVisible(button);
    await _frames(tester);
    final SeedDepositPresentation captured = captureSeedDepositPresentation(
      tester.element(button), expectedOwner: source.owner,
      tapOriginal: (Element element, VoidCallback admission) async {
        final Finder exact = find.byElementPredicate(
          (Element value) => identical(value, element),
        );
        expect(exact.hitTestable(), findsOneWidget);
        admission();
        final TestGesture pointer = await tester.startGesture(
          tester.getCenter(exact), kind: PointerDeviceKind.mouse,
        );
        admission();
        exits++;
        await pointer.up();
      },
    )..requireCaptured();
    await tester.tap(button);
    await _frames(tester);
    expect(source.publications, 1);
    return captured;
  }
}

void main() {
  test('confirmed Deposit closure awaits its original route exactly once',
      () async {
    final Completer<Object?> route = Completer<Object?>();
    int exits = 0;
    final SeedDepositPresentation original = _presentation(
      route: route.future,
      tap: (VoidCallback admission) async { admission(); exits++; },
    )..requireCaptured();
    final Future<void> pending = original.close(actionHash(1), () {});
    await Future<void>.value();
    expect(exits, 1);
    expect(original.closed, isFalse);
    route.complete(null);
    await pending;
    await original.close(actionHash(1), () {});
    expect(original.closed, isTrue);
    expect(exits, 1);
    await expectLater(original.close(actionHash(2), () {}), _refused());
    expect(exits, 1);
  });

  test('Deposit source or owner refusal cannot revive before release',
      () async {
    for (final String phase in <String>['before', 'release', 'owner']) {
      bool current = phase != 'before';
      bool owner = phase != 'owner';
      int exits = 0;
      final SeedDepositPresentation original = _presentation(
        route: Future<Object?>.value(), current: () => current,
        tap: (VoidCallback admission) async {
          admission();
          if (phase == 'release') current = false;
          admission();
          exits++;
        },
      );
      void admit() {
        if (!owner) throw const SeedRefused('original-context-changed');
      }
      await expectLater(original.close(actionHash(1), admit), _refused());
      current = owner = true;
      await expectLater(original.close(actionHash(1), admit), _refused());
      expect(exits, 0);
      expect(original.closed, isFalse);
    }
  });

  test('a different or unsubmitted Deposit hash cannot close a presentation',
      () async {
    for (final String hash in <String>[actionHash(2), 'invalid']) {
      int exits = 0;
      final SeedDepositPresentation original = _presentation(
        route: Future<Object?>.value(),
        tap: (_) async { exits++; },
      );
      await expectLater(original.close(hash, () {}), _refused());
      expect(exits, 0);
      expect(original.closed, isFalse);
    }
  });

  test('pending and failed Deposit exits retain their single original attempt',
      () async {
    for (final bool fail in <bool>[false, true]) {
      final Completer<Object?> route = Completer<Object?>();
      int exits = 0;
      final SeedDepositPresentation original = _presentation(
        route: route.future, timeout: const Duration(milliseconds: 1),
        tap: (VoidCallback admission) async {
          admission();
          exits++;
          if (fail) throw StateError('Finite close failure');
        },
      );
      await expectLater(original.close(actionHash(1), () {}),
          throwsA(fail ? isA<StateError>() : isA<SeedRefused>()));
      route.complete(null);
      await Future<void>.value();
      await expectLater(original.close(actionHash(1), () {}), _refused());
      expect(exits, 1);
      expect(original.closed, isFalse);
    }
    for (final Duration timeout in <Duration>[
      Duration.zero, const Duration(seconds: 6),
    ]) {
      expect(() => _presentation(route: Future<Object?>.value(),
        timeout: timeout, tap: (_) async {}), throwsArgumentError);
    }
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('original Deposit Close restores Home, light $light',
        (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final _DepositRoute fixture = _DepositRoute();
      final SeedDepositPresentation original = await fixture.submit(tester,
          light: light);
      expect(find.byKey(const Key('fixture_home')).hitTestable(),
          findsNothing);
      final int reads = fixture.source.timeReads;
      final int accountReads = fixture.source.accountReads.length;
      await _close(tester, original.close(actionHash(1), () {}));
      expect(original.closed, isTrue);
      expect(fixture.exits, 1);
      expect(find.byType(StartNativeSwapModal), findsNothing);
      expect(find.byKey(const Key('fixture_home')).hitTestable(),
          findsOneWidget);
      await original.close(actionHash(1), () {});
      expect(fixture.exits, 1);
      expect(fixture.source.publications, 1);
      expect(fixture.source.timeReads, reads);
      expect(fixture.source.accountReads.length, accountReads);
      expect(fixture.source.rearmCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final String reason in <String>[
    'hash', 'owner', 'state', 'covered', 'result',
  ]) {
    testWidgets('an original Deposit exit stays held after $reason changes',
        (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final _DepositRoute fixture = _DepositRoute();
      final SeedDepositPresentation original = await fixture.submit(tester);
      String hash = actionHash(1);
      final CapturedSwapModal<StartNativeSwapModal> state =
          fixture.state(tester);
      final SwapActionResult? result = state.shownResult;
      switch (reason) {
        case 'hash':
          hash = actionHash(2);
        case 'owner':
          fixture.source.current = false;
        case 'state':
          fixture.redraw(() => fixture.revision++);
          await _frames(tester);
        case 'covered':
          fixture.navigator.currentState!.push<void>(
            MaterialPageRoute<void>(builder: (_) => const Text('Covered')),
          );
          await _frames(tester);
        case 'result':
          state.shownResult = SwapActionResult(
            status: SwapActionStatus.submitted,
            acceptedHash: result?.acceptedHash, swap: result?.swap,
          );
      }
      await expectLater(original.close(hash, () {}), _refused());
      fixture.source.current = true;
      if (reason == 'covered') {
        fixture.navigator.currentState!.pop();
        await _frames(tester);
      }
      state.shownResult = result;
      await expectLater(original.close(actionHash(1), () {}), _refused());
      expect(fixture.exits, 0);
      expect(fixture.source.publications, 1);
      expect(original.closed, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an uncertain real Deposit result cannot grant its Close pointer',
      (WidgetTester tester) async {
    prepareSwapViewport(tester);
    final _DepositRoute fixture = _DepositRoute();
    fixture.source.store.error = StateError('Finite persistence failure');
    final SeedDepositPresentation original = await fixture.submit(tester);
    expect(fixture.state(tester).shownResult?.status, SwapActionStatus.unknown);
    await expectLater(original.close(actionHash(1), () {}), _refused());
    expect(fixture.exits, 0);
    expect(fixture.source.publications, 1);
    expect(original.closed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
