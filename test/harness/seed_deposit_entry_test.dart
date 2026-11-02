import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/p2p_swap_warning_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/start_native_swap_modal.dart';

import '../../harness/app/fixtures/seed_deposit_entry.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../../harness/app/seed_deposit_entry_binding.dart';
import '../swap_actions_redesign/support.dart';

Matcher _refused(String code) => throwsA(
  isA<SeedRefused>().having((SeedRefused error) => error.code, 'code', code),
);

Future<void> _frames(WidgetTester tester) async {
  await swapFrames(tester);
  await tester.pump(const Duration(milliseconds: 300));
  await swapFrames(tester);
}

SeedDepositEntry _capture(
  WidgetTester tester,
  SwapUiFixture source, {
  required Future<void> Function(Element, VoidCallback) tap,
}) => captureSeedDepositEntry(
  find.byWidgetPredicate(
    (Widget widget) => widget is P2PSwapWarningModal ||
        widget is StartNativeSwapModal,
  ).evaluate(),
  expectedOwner: source.owner,
  tapOriginal: tap,
);

Future<void> _pointer(
  WidgetTester tester, Element element, VoidCallback admission,
) async {
  final Finder exact = find.byElementPredicate(
    (Element value) => identical(value, element),
  );
  expect(exact.hitTestable(), findsOneWidget);
  admission();
  final TestGesture pointer = await tester.startGesture(
    tester.getCenter(exact), kind: PointerDeviceKind.mouse,
  );
  admission();
  await pointer.up();
}

void main() {
  test('a warning rejects a missing original Continue callback', () {
    expect(() => Function.apply(
      SeedDepositEntry.warning,
      <Object?>[],
      <Symbol, dynamic>{
        #originalCurrent: () => true,
        #tapOriginalContinue: null,
      },
    ), throwsA(anyOf(isA<TypeError>(), isA<NoSuchMethodError>())));
  });

  test(
    'an original warning permits one guarded Continue and no replay',
    () async {
      int pointers = 0;
      int checks = 0;
      final SeedDepositEntry original = SeedDepositEntry.warning(
        originalCurrent: () => true,
        tapOriginalContinue: (VoidCallback admission) async {
          admission();
          pointers++;
          admission();
        },
      );
      await original.prepare(() => checks++);
      expect(pointers, 1);
      expect(checks, greaterThanOrEqualTo(3));
      await expectLater(original.prepare(() {}),
          _refused('original-deposit-entry-held'));
      expect(pointers, 1);
    },
  );

  test(
    'an already-ready entry consumes only its original observation',
    () async {
      int reads = 0;
      final SeedDepositEntry original = SeedDepositEntry.ready(
        originalCurrent: () { reads++; return true; },
      );
      await original.prepare(() {});
      expect(reads, 1);
      await expectLater(original.prepare(() {}),
          _refused('original-deposit-entry-held'));
      expect(reads, 1);
    },
  );

  test(
    'revoked original warning cannot revive before pointer release',
    () async {
      bool current = true;
      int pointers = 0;
      final SeedDepositEntry original = SeedDepositEntry.warning(
        originalCurrent: () => current,
        tapOriginalContinue: (VoidCallback admission) async {
          admission();
          current = false;
          admission();
          pointers++;
        },
      );
      await expectLater(original.prepare(() {}),
          _refused('original-deposit-entry-changed'));
      current = true;
      await expectLater(original.prepare(() {}),
          _refused('original-deposit-entry-held'));
      expect(pointers, 0);
    },
  );

  test(
    'original owner refusal is retained before any Continue pointer',
    () async {
      int pointers = 0;
      final SeedDepositEntry original = SeedDepositEntry.warning(
        originalCurrent: () => true,
        tapOriginalContinue: (_) async { pointers++; },
      );
      await expectLater(original.prepare(() {
        throw const SeedRefused('original-context-changed');
      }), _refused('original-context-changed'));
      await expectLater(original.prepare(() {}),
          _refused('original-deposit-entry-held'));
      expect(pointers, 0);
    },
  );

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'real warning Continue reaches a real Start modal, light $light',
      (WidgetTester tester) async {
        prepareSwapViewport(tester);
        final SwapUiFixture source = SwapUiFixture();
        int accepted = 0;
        int pointers = 0;
        await tester.pumpWidget(swapHost(Builder(
          builder: (BuildContext context) {
            Future<void> open() async {
              final bool? continued = await showDialog<bool>(
                context: context,
                builder: (BuildContext dialog) => P2PSwapWarningModal(
                  onAccepted: () {
                    accepted++;
                    Navigator.of(dialog).pop(true);
                  },
                ),
              );
              if (continued != true || !context.mounted) return;
              await showDialog<void>(context: context,
                builder: (_) => StartNativeSwapModal(
                  onSwapStarted: (_) {}, source: source.origin,
                  sourceIsCurrent: () => source.current,
                  dollars: fixtureDollars,
                ),
              );
            }
            return OutlinedButton(key: const Key('open_warning'),
              onPressed: () => unawaited(open()), child: const Text('Open'));
          },
        ), light: light));
        await tester.tap(find.byKey(const Key('open_warning')));
        await _frames(tester);
        expect(find.byType(P2PSwapWarningModal), findsOneWidget);
        expect(find.byType(StartNativeSwapModal), findsNothing);
        final SeedDepositEntry original = _capture(tester, source,
          tap: (Element element, VoidCallback admission) async {
            pointers++;
            await _pointer(tester, element, admission);
          },
        );
        expect(accepted, 0);
        await original.prepare(() {});
        await _frames(tester);
        expect(accepted, 1);
        expect(pointers, 1);
        expect(find.byType(P2PSwapWarningModal), findsNothing);
        expect(find.byType(StartNativeSwapModal), findsOneWidget);
        expect(find.byKey(const Key('swap_start_screen_marker')),
            findsOneWidget);
        expect(source.mutations, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an already-open real Start is observed without another pointer',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SwapUiFixture source = SwapUiFixture();
      await tester.pumpWidget(swapHost(StartNativeSwapModal(
        onSwapStarted: (_) {}, source: source.origin,
        sourceIsCurrent: () => source.current, dollars: fixtureDollars,
      )));
      await _frames(tester);
      final int reads = source.accountReads.length;
      int pointers = 0;
      final SeedDepositEntry original = _capture(tester, source,
        tap: (_, _) async { pointers++; },
      );
      await original.prepare(() {});
      expect(pointers, 0);
      expect(source.accountReads.length, reads);
      expect(source.mutations, 0);
      expect(find.byKey(const Key('swap_start_screen_marker')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a matching key outside a real warning grants no pointer', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    int pointers = 0;
    await tester.pumpWidget(swapHost(OutlinedButton(
      key: const Key('p2p_warning_continue'), onPressed: () { pointers++; },
      child: const Text('Continue'),
    )));
    expect(() => captureSeedDepositEntry(
      find.byKey(const Key('p2p_warning_continue')).evaluate(),
      expectedOwner: SwapUiFixture().owner,
      tapOriginal: (_, _) async { pointers++; },
    ), _refused('original-deposit-entry-required'));
    expect(pointers, 0);
  });

  testWidgets(
    'replaced warning callback stays held after the old value returns',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SwapUiFixture source = SwapUiFixture();
      late StateSetter redraw;
      bool replaced = false;
      int oldCalls = 0;
      int newCalls = 0;
      void original() { oldCalls++; }
      void replacement() { newCalls++; }
      await tester.pumpWidget(swapHost(StatefulBuilder(
        builder: (_, StateSetter update) {
          redraw = update;
          return P2PSwapWarningModal(
            onAccepted: replaced ? replacement : original,
          );
        },
      )));
      await _frames(tester);
      final SeedDepositEntry retained = _capture(tester, source,
        tap: (Element element, VoidCallback admission) =>
            _pointer(tester, element, admission),
      );
      redraw(() => replaced = true);
      await tester.pump();
      await expectLater(retained.prepare(() {}),
          _refused('original-deposit-entry-changed'));
      redraw(() => replaced = false);
      await tester.pump();
      await expectLater(retained.prepare(() {}),
          _refused('original-deposit-entry-held'));
      expect(oldCalls, 0);
      expect(newCalls, 0);
    },
  );

  testWidgets('covering the original warning revokes its retained entry', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture source = SwapUiFixture();
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    int pointers = 0;
    await tester.pumpWidget(swapHost(P2PSwapWarningModal(onAccepted: () {}),
        navigator: navigator));
    await _frames(tester);
    final SeedDepositEntry original = _capture(tester, source,
      tap: (_, _) async { pointers++; },
    );
    navigator.currentState!.push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Cover')),
    ));
    await _frames(tester);
    await expectLater(original.prepare(() {}),
        _refused('original-deposit-entry-changed'));
    navigator.currentState!.pop();
    await _frames(tester);
    await expectLater(original.prepare(() {}),
        _refused('original-deposit-entry-held'));
    expect(pointers, 0);
  });

  testWidgets('ambiguous real warnings cannot choose a replacement owner', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture source = SwapUiFixture();
    int pointers = 0;
    await tester.pumpWidget(swapHost(SizedBox(width: 700, height: 500,
      child: Stack(children: <Widget>[
        P2PSwapWarningModal(onAccepted: () {}),
        P2PSwapWarningModal(onAccepted: () {}),
      ]),
    )));
    await _frames(tester);
    expect(() => _capture(tester, source, tap: (_, _) async { pointers++; }),
        _refused('original-deposit-entry-required'));
    expect(pointers, 0);
    expect(tester.takeException(), isNull);
  });
}
