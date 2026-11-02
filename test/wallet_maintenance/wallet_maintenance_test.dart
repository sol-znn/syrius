import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';

import 'support.dart';

void main() {
  for (final bool scaled in <bool>[false, true]) {
    testWidgets('owned question and original film gate reset, scaled $scaled', (
      WidgetTester tester,
    ) async {
      final MaintenanceFixture source = MaintenanceFixture();
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          source.host(
            light: scaled,
            rtl: scaled,
            scale: scaled ? 1.5 : 1,
          ),
        );
        final VoidCallback saved = await confirmMaintenance(tester, source);
        saved();
        expect(source.disposals, 1);
        expect(source.drainCalls, 0);
        expect(source.firstCalls, 0);
        await tester.tap(
          find.byKey(const Key('maintenance_original_film_done')),
        );
        await maintenanceUntil(tester, () => source.drainCalls == 1);
        final WalletMaintenanceRequest original = source.request!;
        final Future<WalletMaintenanceOutcome> settlement = original.settlement;
        expect(source.filmFuture, same(settlement));
        expect(
          original.filmDone(
            ModalRoute.of(
              tester.element(
                find.byKey(const Key('maintenance_original_film_done')),
              ),
            ),
          ),
          same(settlement),
        );
        source.writer.complete(true);
        await maintenanceUntil(tester, () => source.firstCalls == 1);
        final Object first = Object();
        source.first.complete(first);
        await maintenanceUntil(tester, () => source.secondCalls == 1);
        final Object second = Object();
        source.second.complete(second);
        bool settled = false;
        unawaited(settlement.then<void>((_) => settled = true));
        await maintenanceUntil(tester, () => settled);
        final WalletMaintenanceOutcome outcome = await settlement;
        expect(outcome.status, WalletMaintenanceStatus.completed);
        expect(
          outcome.receipts.map(
            (WalletMaintenanceReceipt receipt) => receipt.future,
          ),
          <Future<dynamic>>[
            source.writer.future,
            source.first.future,
            source.second.future,
            source.clearedFuture,
          ],
        );
        expect(outcome.receipts[1].result, same(first));
        expect(outcome.receipts[2].result, same(second));
        expect(outcome.receipts.clear, throwsUnsupportedError);
        expect(source.transition!.held, isFalse);
        expect(source.revision, 10);
        final Route<dynamic> route = ModalRoute.of(
          tester.element(
            find.byKey(const Key('maintenance_original_film_done')),
          ),
        )!;
        final WalletMaintenanceStartupReceipt receipt = original
            .takeStartupReceipt(route)!;
        expect(receipt.route, same(route));
        expect(receipt.claim(), isTrue);
        expect(receipt.claim(), isFalse);
        expect(original.takeStartupReceipt(route), isNull);
        saved();
        expect(source.firstCalls, 1);
        expect(source.secondCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 400));
        tester.view.reset();
      }
    });
  }

  testWidgets('unavailable original drain refuses before handoff and lease', (
    WidgetTester tester,
  ) async {
    final MaintenanceFixture source = MaintenanceFixture()..available = false;
    await tester.pumpWidget(source.host());
    await tester.tap(find.byKey(const Key('maintenance_open')));
    await maintenanceUntil(
      tester,
      () => find
          .byKey(const Key('reset_wallet_confirm'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('reset_wallet_confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(source.transition, isNull);
    expect(source.disposed, isFalse);
    expect(source.drainCalls, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // Cancel receives initial keyboard focus and never admits cleanup.
    await maintenanceUntil(
      tester,
      () => find
          .byKey(const Key('maintenance_open'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    expect(source.transition, isNull);
    expect(source.disposed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('original drain failure holds quarantine and retains identity', (
    WidgetTester tester,
  ) async {
    final MaintenanceFixture source = MaintenanceFixture();
    await tester.pumpWidget(source.host());
    final VoidCallback saved = await confirmMaintenance(tester, source);
    await tester.tap(find.byKey(const Key('maintenance_original_film_done')));
    await maintenanceUntil(tester, () => source.drainCalls == 1);
    final StateError failure = StateError('Original writer did not drain');
    source.writer.completeError(failure);
    bool settled = false;
    unawaited(source.request!.settlement.then<void>((_) => settled = true));
    await maintenanceUntil(tester, () => settled);
    final WalletMaintenanceOutcome outcome = await source.request!.settlement;
    expect(outcome.status, WalletMaintenanceStatus.unknown);
    expect(outcome.error, same(failure));
    expect(outcome.receipts.single.future, same(source.writer.future));
    expect(outcome.receipts.single.error, same(failure));
    expect(source.transition!.held, isTrue);
    expect(
      WalletMaintenanceOwner.retainedUncertainty,
      contains(same(source.request)),
    );
    expect(source.firstCalls, 0);
    saved();
    expect(source.drainCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final int resource in <int>[0, 1, 2, 3, 4]) {
    testWidgets('replacement $resource holds after original admitted result', (
      WidgetTester tester,
    ) async {
      final MaintenanceFixture source = MaintenanceFixture();
      await tester.pumpWidget(source.host());
      await confirmMaintenance(tester, source);
      await tester.tap(find.byKey(const Key('maintenance_original_film_done')));
      await maintenanceUntil(tester, () => source.drainCalls == 1);
      source.writer.complete(true);
      await maintenanceUntil(tester, () => source.firstCalls == 1);
      final Object? originalOwner = source.identities[resource];
      source.identities[resource] = Object();
      expect(source.ownsResources, isFalse);
      source.identities[resource] = originalOwner;
      final Object original = Object();
      source.first.complete(original);
      bool settled = false;
      unawaited(source.request!.settlement.then<void>((_) => settled = true));
      await maintenanceUntil(tester, () => settled);
      final WalletMaintenanceOutcome outcome = await source.request!.settlement;
      expect(outcome.status, WalletMaintenanceStatus.unknown);
      expect(outcome.receipts.last.future, same(source.first.future));
      expect(outcome.receipts.last.result, same(original));
      expect(source.secondCalls, 0);
      expect(source.transition!.held, isTrue);
      expect(source.request!.canNavigate, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('unrelated question coverage cannot revive a saved confirm', (
    WidgetTester tester,
  ) async {
    final MaintenanceFixture source = MaintenanceFixture();
    await tester.pumpWidget(source.host());
    await tester.tap(find.byKey(const Key('maintenance_open')));
    await maintenanceUntil(
      tester,
      () => find
          .byKey(const Key('reset_wallet_confirm'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    final VoidCallback old = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('reset_wallet_confirm')),
        )
        .onPressed!;
    final MaterialPageRoute<void> unrelated = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Unrelated route')),
    );
    source.navigator.currentState!.push<void>(unrelated);
    await tester.pump();
    source.navigator.currentState!.pop();
    bool removed = false;
    unawaited(unrelated.completed.then<void>((_) => removed = true));
    await maintenanceUntil(tester, () => removed);
    await tester.pump();
    old();
    expect(source.transition, isNull);
    expect(source.disposed, isFalse);
    expect(source.drainCalls, 0);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('reset_wallet_confirm')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the original installation pair cannot cover Splash later', (
    WidgetTester tester,
  ) async {
    final MaintenanceFixture source = MaintenanceFixture();
    await tester.pumpWidget(source.host());
    await confirmMaintenance(tester, source);
    final WalletMaintenanceRequest original = source.request!;
    final Route<dynamic> splash = ModalRoute.of(
      tester.element(find.byKey(const Key('maintenance_original_film_done'))),
    )!;
    final Route<dynamic> question = original.questionRoute!;
    bool repeated = false;
    expect(
      original.installReservedSplash(splash, () => repeated = true),
      isFalse,
    );
    expect(repeated, isFalse);
    expect(original.sourceCompletion, same(original.sourceRoute.completed));
    original.routeCovered(splash, question);
    bool settled = false;
    unawaited(original.settlement.then<void>((_) => settled = true));
    await maintenanceUntil(tester, () => settled);
    await tester.tap(find.byKey(const Key('maintenance_original_film_done')));
    await tester.pump();
    final WalletMaintenanceOutcome outcome = await original.settlement;
    expect(outcome.status, WalletMaintenanceStatus.unknown);
    expect(original.canNavigate, isFalse);
    expect(source.transition!.held, isTrue);
    expect(source.drainCalls, 0);
    expect(source.firstCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unrelated Splash coverage cannot revive cleanup after return', (
    WidgetTester tester,
  ) async {
    final MaintenanceFixture source = MaintenanceFixture();
    await tester.pumpWidget(source.host());
    await confirmMaintenance(tester, source);
    final WalletMaintenanceRequest original = source.request!;
    final MaterialPageRoute<void> unrelated = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Unrelated route')),
    );
    source.navigator.currentState!.push<void>(unrelated);
    await tester.pump();
    source.navigator.currentState!.pop();
    bool removed = false;
    unawaited(unrelated.completed.then<void>((_) => removed = true));
    await maintenanceUntil(tester, () => removed);
    await tester.pump();
    await tester.tap(find.byKey(const Key('maintenance_original_film_done')));
    bool settled = false;
    unawaited(original.settlement.then<void>((_) => settled = true));
    await maintenanceUntil(tester, () => settled);
    final WalletMaintenanceOutcome outcome = await original.settlement;
    expect(outcome.status, WalletMaintenanceStatus.unknown);
    expect(original.sourceCompletion, same(original.sourceRoute.completed));
    expect(original.canNavigate, isFalse);
    expect(source.transition!.held, isTrue);
    expect(source.drainCalls, 0);
    expect(source.firstCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('film cannot substitute for positive exact Main acknowledgment', (
    WidgetTester tester,
  ) async {
    final MaintenanceFixture source = MaintenanceFixture()..acknowledge = false;
    await tester.pumpWidget(source.host());
    await confirmMaintenance(tester, source);
    await tester.tap(find.byKey(const Key('maintenance_original_film_done')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(source.drainCalls, 0);
    expect(source.firstCalls, 0);
    source.request!.revoke();
    final WalletMaintenanceOutcome outcome = await source.request!.settlement;
    expect(outcome.status, WalletMaintenanceStatus.unknown);
    expect(source.transition!.held, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
