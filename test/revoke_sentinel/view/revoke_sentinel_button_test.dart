import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/revoke_sentinel/view/revoke_sentinel_button.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../sentinel_stats/sentinel_owner_fixture.dart';

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(emptyAddress);
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(() => true);
  });

  late SentinelOwnerFixture fixture;
  late SentinelInfo sentinel;
  late ValueNotifier<bool> visible;
  late GlobalKey<NavigatorState> navigator;
  late int refreshed;

  setUp(() {
    sentinel = sentinelOwnerRecord();
    visible = ValueNotifier<bool>(true);
    navigator = GlobalKey<NavigatorState>();
    refreshed = 0;
  });

  void checkWidgets(String description, WidgetTesterCallback body) {
    testWidgets(description, (WidgetTester tester) async {
      fixture = SentinelOwnerFixture();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        try {
          await fixture.dispose(tester);
        } finally {
          visible.dispose();
        }
      }
    });
  }

  Future<void> show(WidgetTester tester, {bool light = false}) async {
    await fixture.load(tester, sentinel);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: const <Locale>[Locale('en')],
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, bool enabled, _) => TickerMode(
              enabled: enabled,
              child: Center(
                child: RevokeSentinelButton(
                  sentinel: sentinel,
                  ownerReader: fixture.reader,
                  sender: fixture.sender,
                  onRevoked: () => refreshed++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ModalRoute<bool> questionRoute(WidgetTester tester, String key) =>
      ModalRoute.of<bool>(tester.element(find.byKey(Key(key)).last))!;

  Future<void> finishQuestionTransition(
    WidgetTester tester,
    String key,
  ) async {
    await tester.pump();
    final ModalRoute<bool> route = questionRoute(tester, key);
    final RiseIn rise = tester.widget<RiseIn>(
      find.descendant(
        of: find.byKey(Key(key)).last,
        matching: find.byType(RiseIn),
      ),
    );
    await tester.pump(
      route.transitionDuration > rise.duration
          ? route.transitionDuration
          : rise.duration,
    );
    await tester.pump();
  }

  Future<void> finishQuestionDismissal(
    WidgetTester tester,
    ModalRoute<bool> route,
  ) async {
    await tester.pump();
    await tester.pump(route.reverseTransitionDuration);
    await tester.pump();
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sentinel_owner_revoke')));
    await finishQuestionTransition(
      tester,
      'sentinel_owner_revoke_first_dialog',
    );
  }

  VoidCallback accept(WidgetTester tester) => tester
      .widget<OutlinedButton>(
        find.byKey(const Key('sentinel_owner_revoke_accept')).last,
      )
      .onPressed!;

  Future<void> confirmBoth(WidgetTester tester) async {
    await ask(tester);
    accept(tester)();
    await finishQuestionTransition(
      tester,
      'sentinel_owner_revoke_final_dialog',
    );
    final ModalRoute<bool> route = questionRoute(
      tester,
      'sentinel_owner_revoke_final_dialog',
    );
    accept(tester)();
    await finishQuestionDismissal(tester, route);
  }

  for (final bool light in <bool>[false, true]) {
    checkWidgets(
      'two questions publish once from the exact owner, light=$light',
      (
        WidgetTester tester,
      ) async {
        await show(tester, light: light);
        await ask(tester);
        expect(fixture.publications, 0);
        expect(
          find.text('Disassemble the sentinel of $emptyAddress?'),
          findsOneWidget,
        );
        final VoidCallback first = accept(tester);
        first();
        first();
        await finishQuestionTransition(
          tester,
          'sentinel_owner_revoke_final_dialog',
        );
        expect(
          find.byKey(const Key('sentinel_owner_revoke_final_dialog')),
          findsOneWidget,
        );
        first();
        expect(
          find.byKey(const Key('sentinel_owner_revoke_final_dialog')),
          findsOneWidget,
        );
        final VoidCallback finalAnswer = accept(tester);
        final ModalRoute<bool> route = questionRoute(
          tester,
          'sentinel_owner_revoke_final_dialog',
        );
        finalAnswer();
        finalAnswer();
        await finishQuestionDismissal(tester, route);
        await pumpSentinelUntil(
          tester,
          () => refreshed == 1,
          reason: 'The original accepted revoke must finish and refresh once',
        );
        expect(fixture.ownershipReads, 2);
        expect(fixture.publications, 1);
        expect(fixture.publishedFrom, emptyAddress.toString());
        expect(fixture.requestedOwners, everyElement(emptyAddress.toString()));
        expect(refreshed, 1);
        expect(fixture.sender.state.origin, SendTransactionOrigin.contract);
        finalAnswer();
        await tester.pump();
        expect(fixture.publications, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  checkWidgets('cancelling the final question performs no fresh read or send', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await ask(tester);
    accept(tester)();
    await finishQuestionTransition(
      tester,
      'sentinel_owner_revoke_final_dialog',
    );
    final ModalRoute<bool> route = questionRoute(
      tester,
      'sentinel_owner_revoke_final_dialog',
    );
    await tester.tap(
      find.byKey(const Key('sentinel_owner_revoke_cancel')).last,
    );
    await finishQuestionDismissal(tester, route);
    expect(fixture.ownershipReads, 1);
    expect(fixture.publications, 0);
    expect(refreshed, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final Map<String, SentinelInfo? Function()> refusedProofs =
      <String, SentinelInfo? Function()>{
        'missing': () => null,
        'foreign': () => sentinelOwnerRecord(owner: kZnnCoin.owner),
        'inactive': () => sentinelOwnerRecord(active: false),
        'closed window': () => sentinelOwnerRecord(revocable: false),
      };
  for (final MapEntry<String, SentinelInfo? Function()> proof
      in refusedProofs.entries) {
    checkWidgets('fresh ${proof.key} ownership refuses publication', (
      WidgetTester tester,
    ) async {
      await show(tester);
      fixture.read = () async => proof.value();
      await confirmBoth(tester);
      await pumpSentinelUntil(
        tester,
        () => fixture.ownershipReads == 2 && !fixture.sender.busy.value,
        reason: 'The refused fresh proof must release the original reservation',
      );
      expect(fixture.ownershipReads, 2);
      expect(fixture.publications, 0);
      expect(fixture.sender.busy.value, isFalse);
      expect(refreshed, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  checkWidgets('context ABA between questions cannot authorize a new owner', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await ask(tester);
    final VoidCallback saved = accept(tester);
    final ModalRoute<bool> route = questionRoute(
      tester,
      'sentinel_owner_revoke_first_dialog',
    );
    kSelectedAddress = kZnnCoin.owner.toString();
    WalletContextRevision.invalidate();
    kSelectedAddress = emptyAddress.toString();
    saved();
    await finishQuestionDismissal(tester, route);
    expect(
      find.byKey(const Key('sentinel_owner_revoke_final_dialog')),
      findsNothing,
    );
    expect(fixture.ownershipReads, 1);
    expect(fixture.publications, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  checkWidgets(
    'a replaced read ticket refuses a saved initial button callback',
    (
      WidgetTester tester,
    ) async {
      await show(tester);
      final VoidCallback saved = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('sentinel_owner_revoke')),
          )
          .onPressed!;
      await fixture.load(tester, sentinel);
      saved();
      await tester.pump();
      expect(
        find.byKey(const Key('sentinel_owner_revoke_first_dialog')),
        findsNothing,
      );
      expect(fixture.publications, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  checkWidgets('hiding during fresh verification revokes preparation', (
    WidgetTester tester,
  ) async {
    await show(tester);
    final Completer<SentinelInfo?> proof = Completer<SentinelInfo?>();
    fixture.read = () => proof.future;
    await confirmBoth(tester);
    await pumpSentinelUntil(
      tester,
      () => fixture.ownershipReads == 2,
      reason: 'The original revoke must reach its pending fresh proof',
    );
    expect(fixture.sender.busy.value, isTrue);
    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pump();
    proof.complete(sentinelOwnerRecord());
    await pumpSentinelUntil(
      tester,
      () => !fixture.sender.busy.value,
      reason: 'The hidden owner action must settle its original reservation',
    );
    expect(fixture.publications, 0);
    expect(fixture.sender.busy.value, isFalse);
    expect(refreshed, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  checkWidgets(
    'saved answers cannot pop another route or a disposed navigator',
    (
      WidgetTester tester,
    ) async {
      await show(tester);
      await ask(tester);
      final VoidCallback saved = accept(tester);
      final MaterialPageRoute<void> route = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route')),
      );
      navigator.currentState!.push<void>(route);
      await tester.pump();
      await tester.pump(route.transitionDuration);
      await tester.pump();
      saved();
      await tester.pump();
      expect(find.text('Other route'), findsOneWidget);
      expect(fixture.publications, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      saved();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  checkWidgets(
    'an accepted original result survives hiding without UI refresh',
    (
      WidgetTester tester,
    ) async {
      await show(tester);
      final Completer<AccountBlockTemplate> reply =
          Completer<AccountBlockTemplate>();
      fixture.addCleanup(() {
        if (!reply.isCompleted && fixture.publications > 0) {
          reply.completeError(StateError('Fixture publication interrupted'));
        }
      });
      fixture.publish = (_) => reply.future;
      await confirmBoth(tester);
      await pumpSentinelUntil(
        tester,
        () => fixture.publications == 1,
        reason: 'The original publication must start before hiding its owner',
      );
      expect(fixture.publications, 1);
      expect(fixture.sender.busy.value, isTrue);
      visible.value = false;
      await tester.pump();
      final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1)
        ..hash = Hash.parse('7' * 64);
      reply.complete(accepted);
      await pumpSentinelUntil(
        tester,
        () => !fixture.sender.busy.value,
        reason: 'The original accepted response must settle while hidden',
      );
      expect(fixture.sender.state.data, same(accepted));
      expect(fixture.sender.state.data!.hash, accepted.hash);
      expect(fixture.publications, 1);
      expect(refreshed, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
