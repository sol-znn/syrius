import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/model/pillar_owner_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/view/pillar_owner_panel.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import '../publication_session/support.dart';
import 'owner_card_support.dart';

const Key _amount = Key('pillar_owner_qsr_amount');
const Key _confirm = Key('pillar_owner_qsr_confirm');

PillarOwnerPanel _panel(WidgetTester tester) =>
    tester.widget<PillarOwnerPanel>(find.byType(PillarOwnerPanel));

Future<FrostedDialogRoute<String>> _openDeposit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pillar_owner_depositQsr')));
  await pumpUntilOwner(
    tester,
    () => find.byKey(_amount).evaluate().isNotEmpty,
    reason: 'The admitted deposit action must open its owned dialog',
  );
  final FrostedDialogRoute<String> route =
      ModalRoute.of<String>(tester.element(find.byKey(_amount)))!
          as FrostedDialogRoute<String>;
  await tester.pump(route.transitionDuration);
  return route;
}

Future<void> _finishDialog<T>(
  WidgetTester tester,
  FrostedDialogRoute<T> route,
) async {
  await tester.pump();
  await tester.pump(route.reverseTransitionDuration);
  // The pinned interpolation completes strictly after its duration.
  await tester.pump(const Duration(microseconds: 1));
  await finishOwnerBoundary(tester, route.completed.then<void>((_) {}));
}

Future<void> _confirmDeposit(WidgetTester tester, String amount) async {
  await tester.enterText(find.byKey(_amount), amount);
  await tester.pump();
  expect(tester.widget<TextButton>(find.byKey(_confirm)).onPressed, isNotNull);
  await tester.tap(find.byKey(_confirm));
}

Future<void> _confirmRevocation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pillar_owner_revokeConfirmed')));
  for (final String step in <String>['first', 'final']) {
    final Finder dialog = find.byKey(Key('pillar_owner_revoke_${step}_dialog'));
    await pumpUntilOwner(
      tester,
      () => dialog.evaluate().isNotEmpty,
      reason: 'The $step revocation question must precede publication',
    );
    final FrostedDialogRoute<bool> route =
        ModalRoute.of<bool>(tester.element(dialog))!
            as FrostedDialogRoute<bool>;
    await tester.pump(route.transitionDuration);
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byKey(const Key('pillar_owner_revoke_accept')),
      ),
    );
    await _finishDialog(tester, route);
  }
}

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(MockPublicationAccount());
    registerFallbackValue(<int>[]);
    registerFallbackValue((PowStatus _) {});
    registerFallbackValue(() => true);
    registerFallbackValue(PowStatus.done);
  });

  void checkWidgets(
    String description,
    Future<void> Function(
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    )
    body, {
    bool revocable = false,
  }) {
    testWidgets(description, (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 780);
      tester.view.devicePixelRatio = 1;
      BalanceVisibility.debugReset();
      final OwnerCardFixture fixture = OwnerCardFixture();
      if (revocable) {
        fixture.rpc.rows = <PillarInfo>[
          ownerCardPillar(revocable: true, cooldown: 60),
        ];
      }
      final GlobalKey<OwnerCardHostState> key = GlobalKey<OwnerCardHostState>();
      try {
        await tester.pumpWidget(
          OwnerCardHost(key: key, fixture: fixture),
        );
        fixture.read();
        await pumpUntilOwner(
          tester,
          () => find.byType(PillarOwnerPanel).evaluate().isNotEmpty,
          reason: 'A completed exact-owner read must reach the adapter',
        );
        await body(tester, fixture, key.currentState!);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          final OwnerCardHostState? host = key.currentState;
          if (host != null) await host.closeRoutes(tester);
        } finally {
          try {
            await fixture.dispose(tester);
          } finally {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  checkWidgets(
    'cost resolves independently without inventing deposit or locked ZNN',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      PillarOwnerSnapshot snapshot = _panel(tester).snapshot;
      expect(snapshot.depositedQsr.state, PillarOwnerFactState.loading);
      expect(snapshot.registrationCostQsr.state, PillarOwnerFactState.loading);
      expect(snapshot.lockedZnn, isNull);
      expect(snapshot.ownerAddress, emptyAddress.toString());
      expect(snapshot.producerAddress, kZnnCoin.owner.toString());
      expect(snapshot.weight, BigInt.parse('900719925474099300000009'));
      expect(snapshot.momentumRewardPercent, 7);
      expect(snapshot.delegateRewardPercent, 83);
      expect(fixture.rpc.depositRequests.single, emptyAddress);

      final BigInt cost = BigInt.parse('15000000000001');
      fixture.rpc.costs.single.complete(cost);
      await pumpUntilOwner(
        tester,
        () => _panel(tester).snapshot.registrationCostQsr.value == cost,
        reason: 'The cost read must update without waiting for deposit',
      );
      snapshot = _panel(tester).snapshot;
      expect(snapshot.depositedQsr.state, PillarOwnerFactState.loading);
      expect(snapshot.lockedZnn, isNull);

      fixture.rpc.deposits.single.completeError(
        StateError('deposit unavailable'),
      );
      await pumpUntilOwner(
        tester,
        () =>
            _panel(tester).snapshot.depositedQsr.state ==
            PillarOwnerFactState.unavailable,
        reason: 'A failed deposit read must remain an unavailable fact',
      );
      snapshot = _panel(tester).snapshot;
      expect(snapshot.depositedQsr.value, isNull);
      expect(snapshot.registrationCostQsr.value, cost);
      expect(snapshot.lockedZnn, isNull);
      expect(
        _panel(tester).enabledActions,
        isNot(contains(PillarOwnerAction.withdrawQsr)),
      );
      expect(fixture.publication.openCalls, 0);
    },
  );

  checkWidgets(
    'actual zero deposit survives an unavailable registration cost',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      fixture.rpc.deposits.single.complete(BigInt.zero);
      fixture.rpc.costs.single.complete(-BigInt.one);
      await pumpUntilOwner(
        tester,
        () =>
            _panel(tester).snapshot.registrationCostQsr.state ==
            PillarOwnerFactState.unavailable,
        reason: 'An invalid cost must settle independently from actual zero',
      );
      final PillarOwnerSnapshot snapshot = _panel(tester).snapshot;
      expect(snapshot.depositedQsr.state, PillarOwnerFactState.available);
      expect(snapshot.depositedQsr.value, BigInt.zero);
      expect(snapshot.registrationCostQsr.value, isNull);
      expect(snapshot.lockedZnn, isNull);
      expect(
        _panel(tester).enabledActions,
        isNot(contains(PillarOwnerAction.withdrawQsr)),
      );
      expect(
        _panel(tester).enabledActions,
        contains(PillarOwnerAction.depositQsr),
      );
    },
  );

  checkWidgets(
    'late facts and saved actions cannot reuse a superseded owner context',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      final PillarOwnerPanel oldPanel = _panel(tester);
      final PillarOwnerSnapshot oldSnapshot = oldPanel.snapshot;
      final Completer<BigInt> oldDeposit = fixture.rpc.deposits.single;
      final Completer<BigInt> oldCost = fixture.rpc.costs.single;
      kCurrentNode = 'replacement-fixture-node';
      WalletContextRevision.invalidate();
      host.rebuild();
      await tester.pump();
      expect(find.byType(PillarOwnerPanel), findsNothing);
      expect(find.byKey(const Key('nodes_spawn_pillar')), findsNothing);
      await oldPanel.onAction(PillarOwnerAction.depositQsr, oldSnapshot);
      expect(find.byKey(_amount), findsNothing);

      fixture.read();
      await pumpUntilOwner(
        tester,
        () => find.byType(PillarOwnerPanel).evaluate().isNotEmpty,
        reason: 'Only the new context may supply an owner panel',
      );
      final Object newAuthority = _panel(tester).snapshot.authority;
      expect(newAuthority, isNot(same(oldSnapshot.authority)));
      fixture.rpc.deposits.last.complete(BigInt.from(5));
      fixture.rpc.costs.last.complete(BigInt.from(503));
      await pumpUntilOwner(
        tester,
        () =>
            _panel(tester).snapshot.registrationCostQsr.value ==
            BigInt.from(503),
        reason: 'The replacement read must own its returned facts',
      );
      oldDeposit.complete(BigInt.from(999));
      oldCost.completeError(StateError('late old cost'));
      await tester.pump();
      final PillarOwnerSnapshot current = _panel(tester).snapshot;
      expect(current.authority, same(newAuthority));
      expect(current.depositedQsr.value, BigInt.from(5));
      expect(current.registrationCostQsr.value, BigInt.from(503));
      expect(fixture.publication.openCalls, 0);
    },
  );

  checkWidgets(
    'invalid deposit amounts and cancelled saved callbacks never publish',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      final FrostedDialogRoute<String> route = await _openDeposit(tester);
      final ValueChanged<String> submitted = tester
          .widget<TextField>(find.byKey(_amount))
          .onSubmitted!;
      for (final String invalid in <String>[
        '0',
        '-1',
        '1e3',
        'NaN',
        '0.000000001',
        ' 2',
      ]) {
        await tester.enterText(find.byKey(_amount), invalid);
        await tester.pump();
        expect(
          tester.widget<TextButton>(find.byKey(_confirm)).onPressed,
          isNull,
        );
        submitted(invalid);
        await tester.pump();
        expect(route.isCurrent, isTrue);
      }
      await tester.enterText(find.byKey(_amount), '2');
      await tester.pump();
      final VoidCallback confirm = tester
          .widget<TextButton>(find.byKey(_confirm))
          .onPressed!;
      await tester.tap(find.text('Cancel'));
      await _finishDialog(tester, route);

      final MaterialPageRoute<void> replacement = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Replacement route')),
      );
      host.navigator.currentState!.push<void>(replacement);
      await tester.pump();
      await tester.pump(replacement.transitionDuration);
      confirm();
      submitted('2');
      await tester.pump();
      expect(replacement.isCurrent, isTrue);
      expect(fixture.rpc.depositActions, isEmpty);
      expect(fixture.publication.sendCalls, 0);
      expect(fixture.publication.openCalls, 0);
    },
  );

  checkWidgets(
    'direct QSR confirmation refuses a context change before rebuilding',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      final FrostedDialogRoute<String> route = await _openDeposit(tester);
      await tester.enterText(find.byKey(_amount), '2.5');
      await tester.pump();
      final VoidCallback confirm = tester
          .widget<TextButton>(find.byKey(_confirm))
          .onPressed!;
      final ValueChanged<String> submitted = tester
          .widget<TextField>(find.byKey(_amount))
          .onSubmitted!;
      kCurrentNode = 'replacement-fixture-node';
      WalletContextRevision.invalidate();
      confirm();
      submitted('2.5');
      await tester.pump();
      expect(route.isCurrent, isTrue);
      expect(fixture.rpc.depositActions, isEmpty);
      expect(fixture.publication.openCalls, 0);
      await tester.tap(find.text('Cancel'));
      await _finishDialog(tester, route);
      expect(fixture.publication.sendCalls, 0);
    },
  );

  for (final bool dispose in <bool>[false, true]) {
    checkWidgets(
      '${dispose ? 'disposed' : 'hidden'} owner dismisses QSR '
      'and refuses saved callbacks',
      (
        WidgetTester tester,
        OwnerCardFixture fixture,
        OwnerCardHostState host,
      ) async {
        final FrostedDialogRoute<String> route = await _openDeposit(tester);
        await tester.enterText(find.byKey(_amount), '3');
        await tester.pump();
        final VoidCallback confirm = tester
            .widget<TextButton>(find.byKey(_confirm))
            .onPressed!;
        final ValueChanged<String> submitted = tester
            .widget<TextField>(find.byKey(_amount))
            .onSubmitted!;
        if (dispose) {
          host.detach();
        } else {
          host.hide();
        }
        await tester.pump();
        confirm();
        submitted('3');
        await _finishDialog(tester, route);
        expect(find.byKey(_confirm), findsNothing);
        expect(fixture.rpc.depositActions, isEmpty);
        expect(fixture.publication.openCalls, 0);
        expect(fixture.publication.sendCalls, 0);
        expect(host.navigator.currentState!.canPop(), isFalse);
      },
    );
  }

  checkWidgets(
    'fresh proof requires both the exact owner and the displayed pillar name',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      final List<List<PillarInfo>> refusals = <List<PillarInfo>>[
        <PillarInfo>[],
        <PillarInfo>[ownerCardPillar(owner: kZnnCoin.owner)],
        <PillarInfo>[ownerCardPillar(name: 'replacement-pillar')],
      ];
      for (final List<PillarInfo> refusal in refusals) {
        final int proofRequest = fixture.rpc.ownerRequests.length + 1;
        final Object originalRead = fixture.reader.readOwner!;
        fixture.rpc.lookupOwner = (_) => Future<List<PillarInfo>>.value(
          fixture.rpc.ownerRequests.length == proofRequest
              ? refusal
              : fixture.rpc.rows,
        );
        final FrostedDialogRoute<String> route = await _openDeposit(tester);
        await _confirmDeposit(tester, '1');
        await _finishDialog(tester, route);
        await pumpUntilOwner(
          tester,
          () =>
              fixture.rpc.ownerRequests.length > proofRequest &&
              find.byType(PillarOwnerPanel).evaluate().isNotEmpty &&
              !_panel(tester).busy &&
              !identical(fixture.reader.readOwner, originalRead),
          reason: 'Refused proof must release its hold and refresh ownership',
        );
        expect(fixture.rpc.ownerRequests[proofRequest - 1], emptyAddress);
        expect(fixture.sender.busy.value, isFalse);
        expect(fixture.publication.openCalls, 0);
        expect(fixture.publication.sendCalls, 0);
      }
      expect(fixture.rpc.depositActions, hasLength(refusals.length));
    },
  );

  for (final String phase in <String>['sync', 'open', 'account', 'plasma']) {
    checkWidgets(
      'revocation expiry during $phase refuses the original prepared send',
      (
        WidgetTester tester,
        OwnerCardFixture fixture,
        OwnerCardHostState host,
      ) async {
        final Completer<SyncInfo> sync = Completer<SyncInfo>();
        final Completer<Wallet> open = Completer<Wallet>();
        final Completer<WalletAccount> account = Completer<WalletAccount>();
        final Completer<bool> plasma = Completer<bool>();
        switch (phase) {
          case 'sync':
            fixture.publication.syncReply = sync.future;
          case 'open':
            fixture.publication.openReply = open.future;
          case 'account':
            fixture.publication.accountReply = account.future;
          case 'plasma':
            fixture.publication.powReply = plasma.future;
        }
        bool waiting() => switch (phase) {
          'sync' => fixture.publication.syncCalls == 1,
          'open' => fixture.publication.openCalls == 1,
          'account' => fixture.publication.accountIndices.isNotEmpty,
          'plasma' => fixture.publication.powCalls == 1,
          _ => false,
        };
        void releasePreparation() {
          if (!sync.isCompleted) sync.complete(fixture.publication.syncInfo);
          if (!open.isCompleted) open.complete(fixture.publication.wallet);
          if (!account.isCompleted) {
            account.complete(fixture.publication.account);
          }
          if (!plasma.isCompleted) plasma.complete(false);
        }

        try {
          await _confirmRevocation(tester);
          await pumpUntilOwner(
            tester,
            waiting,
            reason: 'Both answers must admit the original $phase preparation',
          );
          final PillarOwnerSnapshot snapshot = _panel(tester).snapshot;
          final Object read = fixture.reader.readOwner!;
          final Object request = fixture.sender.state.requestId!;
          expect(fixture.sender.state.status, SendTransactionStatus.loading);
          expect(fixture.rpc.revokeActions, <String>[snapshot.name]);
          expect(
            fixture.rpc.ownerRequests,
            <Address>[emptyAddress, emptyAddress],
          );
          expect(snapshot.revocationBoundaryUtc!.isAfter(fixture.now), isTrue);
          expect(fixture.publication.sendCalls, 0);

          // Only the deadline changes; the same view, read and session remain.
          fixture.now = snapshot.revocationBoundaryUtc!;
          expect(_panel(tester).stillCurrent(snapshot), isTrue);
          expect(fixture.reader.readOwner, same(read));
          releasePreparation();
          await pumpUntilOwner(
            tester,
            () =>
                fixture.sender.state.status == SendTransactionStatus.failure &&
                !fixture.sender.busy.value,
            reason: 'Expiry must settle the original request before SDK send',
          );
          expect(fixture.sender.state.requestId, same(request));
          expect(fixture.sender.state.origin, SendTransactionOrigin.contract);
          expect(fixture.sender.state.data, isNull);
          expect(
            fixture.sender.state.error?.message,
            currentL10n.publicationSessionChanged,
          );
          expect(fixture.publication.sendCalls, 0);
          expect(fixture.publication.records, isEmpty);
          expect(fixture.publication.openCalls, phase == 'sync' ? 0 : 1);
          expect(fixture.publication.closeCalls, phase == 'sync' ? 0 : 1);
          verifyNever(() => fixture.publication.account.sign(any()));
          verifyNever(() => fixture.publication.account.signTx(any()));
        } finally {
          releasePreparation();
        }
      },
      revocable: true,
    );
  }

  checkWidgets(
    'expiry after revocation dispatch preserves its original accepted result',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      await _confirmRevocation(tester);
      await pumpUntilOwner(
        tester,
        () => fixture.publication.sendCalls == 1,
        reason: 'The original revocation must reach SDK send before expiry',
      );
      final PillarOwnerSnapshot snapshot = _panel(tester).snapshot;
      final Object request = fixture.sender.state.requestId!;
      expect(fixture.rpc.revokeActions, <String>[snapshot.name]);
      expect(fixture.publication.accountIndices, <int>[1]);
      expect(
        fixture.publication.sentAccount,
        same(fixture.publication.account),
      );
      expect(fixture.sender.busy.value, isTrue);
      fixture.now = snapshot.revocationBoundaryUtc!;
      host.detach();
      kCurrentNode = 'replacement-fixture-node';
      WalletContextRevision.invalidate();
      await tester.pump();
      final AccountBlockTemplate accepted = fixture.publication.response;
      fixture.transport.complete(accepted);
      await pumpUntilOwner(
        tester,
        () => fixture.publication.records.isNotEmpty,
        reason: 'Expiry cannot replace the original accepted hash or history',
      );
      await tester.pump(const Duration(seconds: 1));
      await pumpUntilOwner(
        tester,
        () =>
            fixture.sender.state.status == SendTransactionStatus.success &&
            !fixture.sender.busy.value,
        reason: 'The original accepted revocation must finish its own delay',
      );
      expect(fixture.sender.state.requestId, same(request));
      expect(fixture.sender.state.origin, SendTransactionOrigin.contract);
      expect(fixture.sender.state.data, same(accepted));
      expect(fixture.sender.state.error, isNull);
      expect(
        fixture.publication.records.single.transactionHash,
        accepted.hash.toString(),
      );
      expect(
        fixture.publication.records.single.chainId,
        PublicationFixture.chain,
      );
      expect(fixture.publication.sendCalls, 1);
      expect(fixture.publication.closeCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
    },
    revocable: true,
  );

  checkWidgets(
    'the exact accepted deposit survives its owner view and context leaving',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      final FrostedDialogRoute<String> route = await _openDeposit(tester);
      await _confirmDeposit(tester, '9007199254740993.00000001');
      await _finishDialog(tester, route);
      await pumpUntilOwner(
        tester,
        () => fixture.publication.sendCalls == 1,
        reason: 'The original SDK send must start before its view leaves',
      );
      expect(fixture.sender.busy.value, isTrue);
      expect(fixture.rpc.ownerRequests, hasLength(2));
      expect(fixture.publication.accountIndices, <int>[1]);
      expect(
        fixture.publication.sentTemplate!.amount,
        BigInt.parse('900719925474099300000001'),
      );
      expect(
        fixture.publication.sentTemplate!.tokenStandard,
        kQsrCoin.tokenStandard,
      );
      host.detach();
      kCurrentNode = 'replacement-fixture-node';
      WalletContextRevision.invalidate();
      await tester.pump();
      final AccountBlockTemplate accepted = fixture.publication.response;
      fixture.transport.complete(accepted);
      await pumpUntilOwner(
        tester,
        () => fixture.publication.records.isNotEmpty,
        reason: 'The original accepted hash must reach its retained history',
      );
      await tester.pump(const Duration(seconds: 1));
      await pumpUntilOwner(
        tester,
        () => fixture.sender.state.status == SendTransactionStatus.success,
        reason: 'The original accepted result must settle after its SDK delay',
      );
      expect(fixture.sender.state.data, same(accepted));
      expect(fixture.sender.state.origin, SendTransactionOrigin.contract);
      expect(fixture.sender.busy.value, isFalse);
      expect(
        fixture.publication.records.single.transactionHash,
        accepted.hash.toString(),
      );
      expect(
        fixture.publication.records.single.chainId,
        PublicationFixture.chain,
      );
      expect(fixture.publication.closeCalls, 1);
      expect(fixture.publication.sendCalls, 1);
      expect(find.byType(PillarOwnerPanel), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  checkWidgets(
    'another shared sender success cannot refresh or complete the owner card',
    (
      WidgetTester tester,
      OwnerCardFixture fixture,
      OwnerCardHostState host,
    ) async {
      final Object read = fixture.reader.readOwner!;
      final Object authority = _panel(tester).snapshot.authority;
      final Object batch = Object();
      expect(fixture.sender.tryReserve(batch), isTrue);
      final SendRequestHandle? request = fixture.sender.trySubmitOwned(
        owner: batch,
        requestId: Object(),
        block: fixture.publication.template,
        fromAddress: emptyAddress.toString(),
        reasonForGeneratingPlasma: 'Independent collection',
      );
      expect(request, isNotNull);
      fixture.sender.releaseReservation(batch);
      await pumpUntilOwner(
        tester,
        () => fixture.publication.sendCalls == 1,
        reason: 'The unrelated shared request must reach its fake SDK boundary',
      );
      fixture.transport.complete(fixture.publication.response);
      await pumpUntilOwner(
        tester,
        () => fixture.publication.records.isNotEmpty,
        reason: 'The unrelated result must reach its own original history',
      );
      await tester.pump(const Duration(seconds: 1));
      await finishOwnerBoundary(tester, request!.result.then<void>((_) {}));
      expect(fixture.sender.state.origin, SendTransactionOrigin.collection);
      expect(fixture.reader.readOwner, same(read));
      expect(_panel(tester).snapshot.authority, same(authority));
      expect(fixture.rpc.ownerRequests, hasLength(1));
      expect(fixture.rpc.depositActions, isEmpty);
      expect(fixture.rpc.withdrawals, 0);
      expect(host.closes, 0);
      expect(_panel(tester).busy, isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(_confirm), findsNothing);
    },
  );
}
