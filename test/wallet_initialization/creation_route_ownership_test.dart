import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_step_route.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';

import '../import_redesign/support.dart';

// This view mounts only the entry boundary and inert controls. The original
// creation, import, password, node and hardware owners are never mounted.
class _RouteFixture {
  final Object identity = Object();
  final Object file = Object();
  final Object connection = Object();
  final Completer<Object> creation = Completer<Object>();
  final List<Object> opened = <Object>[];
  Completer<void>? persist;
  Completer<void>? connect;
  WalletInitializationRun? run;
  bool persistEntered = false;
  bool connectEntered = false;
  bool readyTaken = false;
  int factories = 0;

  void begin(EntryActionLease lease) {
    if (run != null || !lease.isCurrent) return;
    final WalletInitializationBinding binding = WalletInitializationBinding(
      identity: identity,
      connectionOwner: connection,
      isCurrent: () => lease.isCurrent,
      begin: () {},
      prepare: (_, _) async => WalletInitializationData(
        path: 'fixture-source',
        members: <String>['member-a'],
        labels: <String, String>{},
        selected: 'member-a',
        chainId: 1,
      ),
      persist: (_, _, _, _) async {
        persistEntered = true;
        if (persist != null) await persist!.future;
      },
      connect: (_) async {
        connectEntered = true;
        if (connect != null) await connect!.future;
        return WalletInitializationConnection(
          owner: connection,
          connected: true,
          chainId: 1,
          state: WalletInitializationNetworkState.compatible,
        );
      },
      admitLocal: (_) => true,
      activate: () => true,
      publish: (_, _) => true,
    );
    run = binding.start(
      create: () {
        factories++;
        return creation.future;
      },
      cipherKey: const <int>[],
    );
  }

  Widget view(Object source) => EntryActionBoundary(
    source: source,
    builder: (_, EntryActionLease lease) => Scaffold(
      body: Column(
        children: <Widget>[
          OutlinedButton(
            key: const Key('fixture_setup'),
            onPressed: lease.guard(() => begin(lease)),
            child: const Text('Fixture setup'),
          ),
          OutlinedButton(
            key: const Key('fixture_ready'),
            onPressed: lease.guard(() {
              final WalletInitializationOutcome? outcome = run?.outcome;
              final Object? original = outcome?.file;
              if (readyTaken ||
                  outcome?.published != true ||
                  !identical(original, file)) {
                return;
              }
              readyTaken = true;
              opened.add(original!);
            }),
            child: const Text('Fixture ready'),
          ),
        ],
      ),
    ),
  );
}

VoidCallback _saved(WidgetTester tester, String key) =>
    tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed!;

void main() {
  testWidgets(
    'disposal retains an original factory answer and forbids publication',
    (WidgetTester tester) async {
      prepareEntryViewport(tester);
      final _RouteFixture fixture = _RouteFixture();
      await tester.pumpWidget(entryHost(fixture.view(Object())));
      final VoidCallback oldReady = _saved(tester, 'fixture_ready');
      _saved(tester, 'fixture_setup')();
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.creation.complete(fixture.file);
      final WalletInitializationOutcome outcome = await fixture.run!.completion;
      oldReady();
      expect(outcome.file, same(fixture.file));
      expect(outcome.published, isFalse);
      expect(fixture.opened, isEmpty);
      expect(fixture.factories, 1);
    },
  );

  testWidgets('replaced route source cannot recover an old creation callback', (
    WidgetTester tester,
  ) async {
    prepareEntryViewport(tester);
    final _RouteFixture fixture = _RouteFixture();
    final Object originalSource = Object();
    await tester.pumpWidget(entryHost(fixture.view(originalSource)));
    final VoidCallback oldSetup = _saved(tester, 'fixture_setup');
    oldSetup();
    await tester.pumpWidget(entryHost(fixture.view(Object())));
    await tester.pumpWidget(entryHost(fixture.view(originalSource)));
    oldSetup();
    fixture.creation.complete(fixture.file);
    expect((await fixture.run!.completion).published, isFalse);
    expect(fixture.factories, 1);
    expect(fixture.opened, isEmpty);
  });

  testWidgets(
    'dialog coverage during persistence revokes completion and saved Ready',
    (WidgetTester tester) async {
      prepareEntryViewport(tester);
      final _RouteFixture fixture = _RouteFixture()
        ..persist = Completer<void>();
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        entryHost(fixture.view(Object()), navigator: navigator),
      );
      final VoidCallback oldReady = _saved(tester, 'fixture_ready');
      _saved(tester, 'fixture_setup')();
      fixture.creation.complete(fixture.file);
      await tester.pump();
      expect(fixture.persistEntered, isTrue);
      final Future<void> dismissed = showDialog<void>(
        context: tester.element(find.byKey(const Key('fixture_setup'))),
        builder: (_) => const AlertDialog(content: Text('Fixture cover')),
      );
      await tester.pump();
      fixture.persist!.complete();
      expect((await fixture.run!.completion).published, isFalse);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await dismissed;
      oldReady();
      expect(fixture.opened, isEmpty);
      expect(fixture.factories, 1);
    },
  );

  testWidgets(
    'foreground departure during connection remains revoked after resume',
    (WidgetTester tester) async {
      prepareEntryViewport(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final _RouteFixture fixture = _RouteFixture()
        ..connect = Completer<void>();
      await tester.pumpWidget(entryHost(fixture.view(Object())));
      _saved(tester, 'fixture_setup')();
      fixture.creation.complete(fixture.file);
      await tester.pump();
      expect(fixture.connectEntered, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      fixture.connect!.complete();
      final WalletInitializationOutcome outcome = await fixture.run!.completion;
      expect(outcome.published, isFalse);
      expect(outcome.file, same(fixture.file));
      expect(fixture.factories, 1);
    },
  );

  testWidgets('hidden ticker branch rejects stale completion after returning', (
    WidgetTester tester,
  ) async {
    prepareEntryViewport(tester);
    final _RouteFixture fixture = _RouteFixture()..persist = Completer<void>();
    final Object source = Object();
    await tester.pumpWidget(entryHost(fixture.view(source)));
    _saved(tester, 'fixture_setup')();
    fixture.creation.complete(fixture.file);
    await tester.pump();
    expect(fixture.persistEntered, isTrue);
    await tester.pumpWidget(entryHost(fixture.view(source), enabled: false));
    await tester.pumpWidget(entryHost(fixture.view(source)));
    fixture.persist!.complete();
    expect((await fixture.run!.completion).published, isFalse);
    expect(fixture.opened, isEmpty);
  });

  testWidgets(
    'shared-axis entry admits once and Ready uses the exact injected file',
    (WidgetTester tester) async {
      prepareEntryViewport(tester);
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      final _RouteFixture fixture = _RouteFixture();
      await tester.pumpWidget(
        entryHost(
          const Scaffold(body: Text('Fixture origin')),
          navigator: navigator,
        ),
      );
      navigator.currentState!.push<void>(
        OnboardingStepRoute<void>(builder: (_) => fixture.view(Object())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final VoidCallback early = _saved(tester, 'fixture_setup');
      early();
      expect(fixture.factories, 0);
      await tester.pump(const Duration(milliseconds: 151));
      early();
      expect(fixture.factories, 0);
      _saved(tester, 'fixture_setup')();
      _saved(tester, 'fixture_setup')();
      fixture.creation.complete(fixture.file);
      expect((await fixture.run!.completion).published, isTrue);
      _saved(tester, 'fixture_ready')();
      _saved(tester, 'fixture_ready')();
      expect(fixture.opened, hasLength(1));
      expect(fixture.opened.single, same(fixture.file));
      expect(fixture.factories, 1);
    },
  );
}
