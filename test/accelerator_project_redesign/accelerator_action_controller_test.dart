import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/services/accelerator_project_cache.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  late AcceleratorActionController controller;
  late ActionSource source;
  setUp(() {
    controller = AcceleratorActionController();
    source = ActionSource();
  });

  test(
    'draft units never round, use floating point or accept an extra decimal',
    () {
      expect(
        acceleratorDraftUnits('9007199254740993.00000001'),
        BigInt.parse('900719925474099300000001'),
      );
      expect(acceleratorDraftUnits('0'), BigInt.zero);
      expect(acceleratorDraftUnits('1.000000001'), isNull);
      expect(acceleratorDraftUnits('-1'), isNull);
      expect(acceleratorDraftUnits('NaN'), isNull);
    },
  );

  test(
    'fresh exact phase and exact owned Pillar admit a legitimate change-vote',
    () async {
      source
        ..project = actionProject(
          phases: <int>[2],
          phaseStatus: AcceleratorProjectStatus.active,
          status: AcceleratorProjectStatus.completed,
        )
        ..voteReader = (String _, List<String> _) async => <PillarVote?>[
          listVote(2, vote: AcceleratorProjectVote.no.index),
        ];
      final AcceleratorActionOutcome result = await controller.submit(
        source,
        voteRequest(phase: 2),
      );
      expect(result.state, AcceleratorActionState.submitted);
      expect(source.projectReads, <String>[listHash(1)]);
      expect(source.ownerReads, 1);
      expect(source.publications, 1);
      expect(source.builders.single.vote, AcceleratorProjectVote.yes);
      expect(source.builders.single.phaseId, listHash(2));
    },
  );

  test(
    'zero, multiple, mismatched and renamed Pillars never choose a sender',
    () async {
      for (final List<PillarInfo> pillars in <List<PillarInfo>>[
        <PillarInfo>[],
        <PillarInfo>[listPillar(), listPillar(name: 'second')],
        <PillarInfo>[listPillar(owner: pillarAddress)],
        <PillarInfo>[listPillar(name: 'replacement')],
      ]) {
        source = ActionSource()
          ..project = actionProject(status: AcceleratorProjectStatus.voting)
          ..pillars = pillars;
        final AcceleratorActionOutcome result = await controller.submit(
          source,
          voteRequest(),
        );
        expect(result.state, AcceleratorActionState.refused);
        expect(source.publications, 0);
      }
    },
  );

  test('a replaced phase hash cannot vote on the replacement', () async {
    source.project = actionProject(phases: <int>[3]);
    final AcceleratorActionOutcome result = await controller.submit(
      source,
      voteRequest(phase: 2),
    );
    expect(result.state, AcceleratorActionState.refused);
    expect(source.publications, 0);
    expect(source.projectReads.single, listHash(1));
  });

  test(
    'choice and target are copied before an owned-Pillar suspension',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      final Completer<List<PillarInfo>> owned = Completer<List<PillarInfo>>();
      final Completer<void> asked = Completer<void>();
      source.ownerReader = () {
        asked.complete();
        return owned.future;
      };
      AcceleratorProjectVote choice = AcceleratorProjectVote.yes;
      final AcceleratorActionRequest request = voteRequest(choice: choice);
      final Future<AcceleratorActionOutcome> original = controller.submit(
        source,
        request,
      );
      await asked.future;
      choice = AcceleratorProjectVote.no;
      owned.complete(<PillarInfo>[listPillar()]);
      final AcceleratorActionOutcome result = await original;
      expect(choice, AcceleratorProjectVote.no);
      expect(source.builders.single.vote, AcceleratorProjectVote.yes);
      expect(result.state, AcceleratorActionState.submitted);
    },
  );

  test(
    'revocation during target read refuses before ownership or publication',
    () async {
      final Completer<Project> project = Completer<Project>();
      source.projectReader = (_) => project.future;
      final Future<AcceleratorActionOutcome> original = controller.submit(
        source,
        voteRequest(),
      );
      source.current = false;
      project.complete(actionProject(status: AcceleratorProjectStatus.voting));
      final AcceleratorActionOutcome result = await original;
      expect(result.state, AcceleratorActionState.refused);
      expect(source.ownerReads, 0);
      expect(source.publications, 0);
    },
  );

  test(
    'an accepted original result survives a later context change unchanged',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      final Completer<void> entered = Completer<void>();
      source.sender = (_, _) {
        entered.complete();
        return sent.future;
      };
      final AcceleratorActionRequest request = voteRequest();
      final Future<AcceleratorActionOutcome> original = controller.submit(
        source,
        request,
      );
      await entered.future;
      source.current = false;
      final AccountBlockTemplate accepted = actionBlock(444);
      sent.complete(accepted);
      final AcceleratorActionOutcome result = await original;
      expect(result.state, AcceleratorActionState.submitted);
      expect(identical(result.blocks.single, accepted), isTrue);
      expect(result.hashes, <String>[listHash(444)]);
      expect(identical(controller.retained(source, request), result), isTrue);
    },
  );

  test(
    'concurrent duplicate intents share the exact original Future',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      final Completer<void> entered = Completer<void>();
      source.sender = (_, _) {
        entered.complete();
        return sent.future;
      };
      final AcceleratorActionRequest request = voteRequest();
      final Future<AcceleratorActionOutcome> first = controller.submit(
        source,
        request,
      );
      await entered.future;
      final Future<AcceleratorActionOutcome> second = controller.submit(
        source,
        voteRequest(),
      );
      expect(identical(first, second), isTrue);
      sent.complete(actionBlock(444));
      await first;
      await second;
      expect(source.publications, 1);
    },
  );

  test(
    'sender errors retain their identity and hold the original action lane',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      final StateError failure = StateError('synthetic transport outcome');
      source.sender = (_, _) async => throw failure;
      final AcceleratorActionRequest request = voteRequest();
      final AcceleratorActionOutcome original = await controller.submit(
        source,
        request,
      );
      expect(original.state, AcceleratorActionState.uncertain);
      expect(identical(original.error, failure), isTrue);
      final ActionSource reopened = ActionSource()..project = source.project;
      final AcceleratorActionOutcome refused = await controller.submit(
        reopened,
        voteRequest(choice: AcceleratorProjectVote.no),
      );
      expect(refused.state, AcceleratorActionState.held);
      expect(reopened.publications, 0);
      expect(await controller.rearm(reopened, request), isFalse);
      expect(
        identical(controller.retained(reopened, request), original),
        isTrue,
      );
    },
  );

  test(
    'new allocations include paid phases and refuse changed membership',
    () async {
      source.project = actionProject(
        phases: <int>[2],
        phaseStatus: AcceleratorProjectStatus.paid,
        budget: BigInt.from(150000000),
      );
      final AcceleratorActionOutcome over = await controller.submit(
        source,
        phaseRequest(phases: <int>[2]),
      );
      expect(over.state, AcceleratorActionState.refused);
      expect(source.publications, 0);
      final AcceleratorActionOutcome stale = await controller.submit(
        source,
        phaseRequest(phases: <int>[], znn: 1),
      );
      expect(stale.state, AcceleratorActionState.refused);
      expect(source.publications, 0);
    },
  );

  test(
    'a next phase retains original membership despite caller list changes',
    () async {
      final Completer<Project> project = Completer<Project>();
      source.projectReader = (_) => project.future;
      final List<String> originalIds = <String>[listHash(2)];
      final AcceleratorActionRequest request = AcceleratorActionRequest(
        kind: AcceleratorActionKind.createPhase,
        projectId: listHash(1),
        phaseIds: originalIds,
        name: 'New phase',
        description: 'Proof',
        url: 'https://example.test',
        znn: BigInt.from(100000000),
      );
      final Future<AcceleratorActionOutcome> outcome = controller.submit(
        source,
        request,
      );
      originalIds
        ..clear()
        ..add(listHash(9));
      project.complete(
        actionProject(
          phases: <int>[2],
          phaseStatus: AcceleratorProjectStatus.paid,
        ),
      );
      final AcceleratorActionOutcome result = await outcome;
      expect(result.state, AcceleratorActionState.submitted);
      expect(source.builders.single.phaseIds, <String>[listHash(2)]);
      expect(source.publications, 1);
    },
  );

  test(
    'latest voting phase updates replace allocation without parent-active gate',
    () async {
      source.project = actionProject(
        phases: <int>[2],
        status: AcceleratorProjectStatus.completed,
        budget: BigInt.from(100000000),
      );
      final AcceleratorActionOutcome result = await controller.submit(
        source,
        phaseRequest(update: true, phases: <int>[2], phase: 2),
      );
      expect(result.state, AcceleratorActionState.submitted);
      expect(source.publications, 1);
    },
  );

  test(
    'older phases and foreign owners cannot update the current phase',
    () async {
      source.project = actionProject(phases: <int>[2, 3]);
      final AcceleratorActionOutcome older = await controller.submit(
        source,
        phaseRequest(update: true, phases: <int>[2, 3], phase: 2),
      );
      expect(older.state, AcceleratorActionState.refused);
      source.project = actionProject(
        phases: <int>[2],
        owner: pillarAddress.toString(),
      );
      final AcceleratorActionOutcome foreign = await controller.submit(
        source,
        phaseRequest(update: true, phases: <int>[2], phase: 2),
      );
      expect(foreign.state, AcceleratorActionState.refused);
      expect(source.publications, 0);
    },
  );

  test(
    'reopening a fresh phase form releases only an exact accepted phase effect',
    () async {
      for (final bool update in <bool>[false, true]) {
        controller = AcceleratorActionController();
        source = ActionSource()
          ..project = actionProject(
            phases: <int>[2],
            phaseStatus: update
                ? AcceleratorProjectStatus.voting
                : AcceleratorProjectStatus.paid,
          );
        final AcceleratorActionRequest original = phaseRequest(
          update: update,
          phases: <int>[2],
          phase: update ? 2 : null,
        );
        final AcceleratorActionOutcome accepted = await controller.submit(
          source,
          original,
        );
        source.confirmed = true;
        final AcceleratorActionRequest reopened = phaseRequest(
          update: update,
          phases: update ? <int>[901] : <int>[2, 901],
          phase: update ? 901 : null,
        );
        expect(await controller.rearm(source, reopened), isFalse);
        final Map<String, dynamic> json = AcceleratorProjectCache.projectToJson(
          actionProject(phases: update ? <int>[901] : <int>[2, 901]),
        );
        final List<dynamic> phases = json['phases'] as List<dynamic>;
        final Map<String, dynamic> wrapped =
            phases.last as Map<String, dynamic>;
        final Map<String, dynamic> effect =
            wrapped['phase'] as Map<String, dynamic>;
        effect['name'] = original.name;
        effect['description'] = original.description;
        effect['url'] = original.url;
        effect['znnFundsNeeded'] = original.znn.toString();
        effect['qsrFundsNeeded'] = original.qsr.toString();
        source.project = Project.fromJson(json);
        expect(await controller.rearm(source, reopened), isTrue);
        expect(controller.holds(source, reopened), isFalse);
        expect(controller.history, contains(same(accepted)));
        expect(source.publications, 1);
      }
    },
  );

  test(
    'partial donation retains its raw original and cannot complete the pair',
    () async {
      final AccountBlockTemplate accepted = actionBlock(222);
      final StateError failure = StateError('second synthetic outcome');
      source.sender = (_, _) async {
        if (source.publications == 1) return accepted;
        throw failure;
      };
      int balances = 0;
      source.balanceReader = () async => ++balances == 1
          ? AcceleratorActionBalance(BigInt.one, BigInt.one)
          : AcceleratorActionBalance(BigInt.zero, BigInt.one);
      final AcceleratorActionRequest request = AcceleratorActionRequest(
        kind: AcceleratorActionKind.donate,
        znn: BigInt.one,
        qsr: BigInt.one,
      );
      final AcceleratorActionOutcome result = await controller.submit(
        source,
        request,
      );
      expect(source.publications, 2);
      expect(result.state, AcceleratorActionState.uncertain);
      expect(identical(result.blocks.single, accepted), isTrue);
      expect(result.hashes, <String>[listHash(222)]);
      expect(identical(result.error, failure), isTrue);
      expect(await controller.rearm(source, request), isFalse);
    },
  );

  test(
    'revocation after the first donation does not start the other coin',
    () async {
      source.sender = (_, _) async {
        source.current = false;
        return actionBlock(222);
      };
      final AcceleratorActionOutcome result = await controller.submit(
        source,
        AcceleratorActionRequest(
          kind: AcceleratorActionKind.donate,
          znn: BigInt.one,
          qsr: BigInt.one,
        ),
      );
      expect(source.publications, 1);
      expect(result.state, AcceleratorActionState.uncertain);
      expect(result.hashes, <String>[listHash(222)]);
    },
  );

  test(
    'accepted send confirmation alone cannot claim a project was created',
    () async {
      final AcceleratorActionRequest request = AcceleratorActionRequest(
        kind: AcceleratorActionKind.createProject,
        name: 'New project',
        description: 'New proof',
        url: 'https://example.test',
        znn: BigInt.one,
      );
      final AcceleratorActionOutcome result = await controller.submit(
        source,
        request,
      );
      source.confirmed = true;
      expect(result.state, AcceleratorActionState.submitted);
      expect(await controller.rearm(source, request), isFalse);
      expect(source.confirmedReads, result.hashes);
      expect(controller.holds(source, request), isTrue);
    },
  );

  test(
    'exact confirmed vote and source choice permit an explicit change',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      final AcceleratorActionRequest original = voteRequest();
      final AcceleratorActionOutcome first = await controller.submit(
        source,
        original,
      );
      source
        ..confirmed = true
        ..voteReader = (String name, List<String> ids) async => <PillarVote?>[
          listVote(1, name: name, vote: AcceleratorProjectVote.yes.index),
        ];
      expect(await controller.rearm(source, original), isTrue);
      final AcceleratorActionOutcome changed = await controller.submit(
        source,
        voteRequest(choice: AcceleratorProjectVote.no),
      );
      expect(changed.state, AcceleratorActionState.submitted);
      expect(source.publications, 2);
      expect(controller.history, contains(same(first)));
      expect(source.confirmedReads.single, first.hashes.single);
    },
  );
}
