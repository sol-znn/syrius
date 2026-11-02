import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_owner_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinel_stats/view/sentinel_stats_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/fetch_bloc/fetch_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'sentinel_owner_fixture.dart';

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(emptyAddress);
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(() => true);
  });

  late SentinelOwnerFixture fixture;
  late GlobalKey<NavigatorState> navigator;
  NodeOwnerPublisher? publisher;
  Zenon? originalClient;
  late int stepperBuilds;

  setUp(() {
    navigator = GlobalKey<NavigatorState>();
    publisher = null;
    originalClient = null;
    stepperBuilds = 0;
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
          AppLottie.debugClear();
        }
      }
    });
  }

  Future<void> show(WidgetTester tester, {bool light = false}) async {
    await tester.pump();
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: const <Locale>[Locale('en')],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              child: SentinelStatsCard(
                ownerReader: fixture.reader,
                sender: fixture.sender,
                onStepperNotificationSeeMorePressed: () {},
                stepperBuilderForTesting:
                    (
                      AccountBlockUtils ownerPublisher,
                      Zenon client,
                    ) {
                      publisher = ownerPublisher as NodeOwnerPublisher;
                      originalClient = client;
                      stepperBuilds++;
                      return const Scaffold(body: Text('Existing stepper'));
                    },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finishSpawnTransition(WidgetTester tester) async {
    final Finder entering = find.text('Existing stepper', skipOffstage: false);
    await pumpSentinelUntil(
      tester,
      () => entering.evaluate().isNotEmpty,
      reason: 'The pushed stepper must be laid out before its enter transition',
    );
    final ModalRoute<void> route = ModalRoute.of<void>(
      tester.element(entering),
    )!;
    await tester.pump(route.transitionDuration);
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump();
    expect(find.text('Existing stepper'), findsOneWidget);
  }

  Future<void> openSpawn(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sentinel_owner_spawn')));
    await finishSpawnTransition(tester);
  }

  Future<AccountBlockTemplate> publish() => publisher!.createAccountBlock(
    AccountBlockTemplate(blockType: 1),
    'Isolated owner action',
    address: emptyAddress,
    waitForRequiredPlasma: true,
  );

  Future<void> refuses(
    WidgetTester tester,
    PendingSentinelPublication pending,
  ) async {
    await pumpSentinelUntil(
      tester,
      () => pending.outcome.settled,
      reason: 'The original refusal must settle before assertions',
    );
    expect(pending.outcome.error, isA<FailureException>());
    expect(pending.outcome.result, isNull);
  }

  for (final bool light in <bool>[false, true]) {
    checkWidgets(
      'inactive sentinel remains owned with the original at132px, light=$light',
      (
        WidgetTester tester,
      ) async {
        await fixture.load(tester, sentinelOwnerRecord(active: false));
        await show(tester, light: light);
        expect(tester.widget<NodeObject>(find.byType(NodeObject)).size, 132);
        final AppLottie animation = tester.widget<AppLottie>(
          find.byType(AppLottie),
        );
        expect(animation.asset, AppLottieAsset.sentinel);
        expect(animation.repeat, isFalse);
        expect(find.byTooltip(emptyAddress.toString()), findsOneWidget);
        expect(find.text('Revoked'), findsOneWidget);
        expect(find.text('None yet'), findsNothing);
        expect(find.text('Spawn'), findsNothing);
        expect(find.byKey(const Key('sentinel_owner_revoke')), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  checkWidgets(
    'active ownership shows exact facts and the guarded existing action',
    (
      WidgetTester tester,
    ) async {
      await fixture.load(tester, sentinelOwnerRecord());
      await show(tester);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Registered'), findsOneWidget);
      expect(find.text('Revocable'), findsOneWidget);
      expect(find.byKey(const Key('sentinel_owner_revoke')), findsOneWidget);
      expect(find.byKey(const Key('sentinel_owner_spawn')), findsNothing);
      expect(fixture.publications, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  checkWidgets('waiting and failed reads cannot become a Spawn proof', (
    WidgetTester tester,
  ) async {
    final Completer<SentinelInfo?> reply = Completer<SentinelInfo?>();
    fixture.read = () => reply.future;
    fixture.reader.add(FetchRequestData(address: emptyAddress));
    await show(tester);
    expect(find.byKey(const Key('sentinel_owner_spawn')), findsNothing);
    expect(find.text('None yet'), findsNothing);
    reply.completeError(StateError('Owner lookup unavailable'));
    await pumpSentinelUntil(
      tester,
      () => fixture.reader.state is FetchFailure<List<SentinelInfo>>,
      reason: 'The failed displayed read must complete on the widget clock',
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.byKey(const Key('sentinel_owner_spawn')), findsNothing);
    expect(fixture.publications, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  checkWidgets(
    'Spawn injects original client and fresh empty proof '
    'into the shared sender',
    (
      WidgetTester tester,
    ) async {
      await fixture.load(tester, null);
      await show(tester);
      final VoidCallback saved = tester
          .widget<OutlinedButton>(find.byKey(const Key('sentinel_owner_spawn')))
          .onPressed!;
      saved();
      saved();
      await finishSpawnTransition(tester);
      expect(stepperBuilds, 1);
      expect(originalClient, same(fixture.client));
      final PendingSentinelPublication original = PendingSentinelPublication(
        publish(),
      );
      final AccountBlockTemplate accepted = await original.settle(tester);
      expect(publisher!.lastResult!.block, same(accepted));
      expect(fixture.ownershipReads, 2);
      expect(fixture.publications, 1);
      expect(fixture.publishedFrom, emptyAddress.toString());
      saved();
      expect(fixture.publications, 1);
      final ModalRoute<void> route = ModalRoute.of<void>(
        tester.element(find.text('Existing stepper')),
      )!;
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(route.reverseTransitionDuration);
      await tester.pump();
      await refuses(tester, PendingSentinelPublication(publish()));
      expect(fixture.publications, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final bool active in <bool>[false, true]) {
    checkWidgets(
      'fresh ${active ? 'active' : 'inactive'} ownership '
      'refuses Spawn publication',
      (
        WidgetTester tester,
      ) async {
        await fixture.load(tester, null);
        await show(tester);
        await openSpawn(tester);
        fixture.read = () async => sentinelOwnerRecord(active: active);
        await refuses(tester, PendingSentinelPublication(publish()));
        expect(fixture.ownershipReads, 2);
        expect(fixture.publications, 0);
        expect(fixture.sender.busy.value, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  checkWidgets(
    'a replacement empty read cannot revive the original Spawn proof',
    (
      WidgetTester tester,
    ) async {
      await fixture.load(tester, null);
      await show(tester);
      await openSpawn(tester);
      await fixture.load(tester, null);
      final int reads = fixture.ownershipReads;
      await refuses(tester, PendingSentinelPublication(publish()));
      expect(fixture.ownershipReads, reads);
      expect(fixture.publications, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  checkWidgets('context ABA revokes a fresh empty proof while it waits', (
    WidgetTester tester,
  ) async {
    await fixture.load(tester, null);
    await show(tester);
    await openSpawn(tester);
    final Completer<SentinelInfo?> reply = Completer<SentinelInfo?>();
    fixture.read = () => reply.future;
    final PendingSentinelPublication original = PendingSentinelPublication(
      publish(),
    );
    await pumpSentinelUntil(
      tester,
      () => fixture.ownershipReads == 2,
      reason: 'The original action must reach its fresh owner read',
    );
    expect(fixture.sender.busy.value, isTrue);
    expect(original.outcome.settled, isFalse);
    WalletContextRevision.invalidate();
    reply.complete(null);
    await refuses(tester, original);
    expect(fixture.publications, 0);
    expect(fixture.sender.busy.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  checkWidgets(
    'the original accepted Spawn action survives owner view disposal',
    (
      WidgetTester tester,
    ) async {
      await fixture.load(tester, null);
      await show(tester);
      await openSpawn(tester);
      final Completer<AccountBlockTemplate> reply =
          Completer<AccountBlockTemplate>();
      fixture.addCleanup(() {
        if (!reply.isCompleted && fixture.publications > 0) {
          reply.completeError(StateError('Fixture publication interrupted'));
        }
      });
      fixture.publish = (_) => reply.future;
      final PendingSentinelPublication original = PendingSentinelPublication(
        publish(),
      );
      await pumpSentinelUntil(
        tester,
        () => fixture.publications == 1,
        reason: 'The original publication must start before view disposal',
      );
      expect(fixture.publications, 1);
      expect(original.outcome.settled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1)
        ..hash = Hash.parse('7' * 64);
      reply.complete(accepted);
      expect(await original.settle(tester), same(accepted));
      expect(publisher!.lastResult!.block, same(accepted));
      expect(publisher!.lastResult!.block!.hash, accepted.hash);
      expect(fixture.publications, 1);
    },
  );
}
