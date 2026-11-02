import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  late AcceleratorActionController actions;
  late AcceleratorProjectPresenter presenter;
  late ActionSource source;
  bool disposed = false;
  setUp(() {
    disposed = false;
    actions = AcceleratorActionController();
    source = ActionSource();
    presenter = AcceleratorProjectPresenter(
      projectId: listHash(1),
      actions: actions,
    );
  });
  tearDown(() {
    if (!disposed) presenter.dispose();
  });

  test(
    'details selects the exact phase and keeps existing votes changeable',
    () async {
      source
        ..project = actionProject(
          phases: <int>[2],
          phaseStatus: AcceleratorProjectStatus.active,
        )
        ..voteReader = (String name, List<String> ids) async => <PillarVote?>[
          null,
          listVote(2, name: name, vote: AcceleratorProjectVote.no.index),
        ];
      await presenter.load(source);
      expect(presenter.snapshot.selectedId, listHash(2));
      expect(presenter.snapshot.canVote, isTrue);
      expect(presenter.snapshot.needsVote, isFalse);
      expect(
        presenter.snapshot.votes[listHash(2)],
        AcceleratorProjectVote.no.index,
      );
    },
  );

  test(
    'zero, foreign and ambiguous Pillars retain exact eligibility states',
    () async {
      source
        ..project = actionProject(status: AcceleratorProjectStatus.voting)
        ..pillars = <PillarInfo>[];
      await presenter.load(source);
      expect(
        presenter.snapshot.eligibility,
        AcceleratorVoteEligibility.ineligible,
      );
      source.pillars = <PillarInfo>[listPillar(owner: pillarAddress)];
      await presenter.load(source);
      expect(
        presenter.snapshot.eligibility,
        AcceleratorVoteEligibility.unknown,
      );
      source.pillars = <PillarInfo>[listPillar(), listPillar(name: 'other')];
      await presenter.load(source);
      expect(
        presenter.snapshot.eligibility,
        AcceleratorVoteEligibility.unknown,
      );
      expect(presenter.snapshot.canVote, isFalse);
    },
  );

  test(
    'a short or foreign vote response cannot label the target Your vote',
    () async {
      source
        ..project = actionProject(status: AcceleratorProjectStatus.voting)
        ..voteReader = (_, _) async => <PillarVote?>[];
      await presenter.load(source);
      expect(presenter.snapshot.votesComplete, isFalse);
      expect(presenter.snapshot.needsVote, isFalse);
      expect(
        presenter.snapshot.canVote,
        isTrue,
        reason: 'absence is not a change-vote prerequisite',
      );
      source.voteReader = (_, _) async => <PillarVote?>[listVote(2)];
      await presenter.load(source);
      expect(presenter.snapshot.votesComplete, isFalse);
      expect(presenter.snapshot.needsVote, isFalse);
    },
  );

  test(
    'a phase selection does not strand an in-flight original ownership read',
    () async {
      source.project = actionProject(phases: <int>[2]);
      final Completer<List<PillarInfo>> owner = Completer<List<PillarInfo>>();
      final Completer<void> projectShown = Completer<void>();
      source.ownerReader = () => owner.future;
      presenter.addListener(() {
        if (presenter.snapshot.project != null && !projectShown.isCompleted) {
          projectShown.complete();
        }
      });
      final Future<void> loading = presenter.load(source);
      await projectShown.future;
      presenter.select(listHash(2), presenter.snapshot.authority);
      owner.complete(<PillarInfo>[listPillar()]);
      await loading;
      expect(presenter.snapshot.selectedId, listHash(2));
      expect(presenter.snapshot.ownerComplete, isTrue);
      expect(presenter.snapshot.votesComplete, isTrue);
      expect(presenter.snapshot.canVote, isTrue);
    },
  );

  test(
    'a retained old selection callback cannot redirect a fresh target',
    () async {
      source.project = actionProject(phases: <int>[2, 3]);
      await presenter.load(source);
      final Object old = presenter.snapshot.authority;
      presenter
        ..select(listHash(2), old)
        ..select(listHash(3), old);
      expect(presenter.snapshot.selectedId, listHash(2));
      expect(presenter.owns(old), isFalse);
    },
  );

  test(
    'fresh admission refuses a displayed phase replaced during the view',
    () async {
      source.project = actionProject(phases: <int>[2]);
      await presenter.load(source);
      final Object authority = presenter.snapshot.authority;
      source.project = actionProject(phases: <int>[3]);
      final AcceleratorActionOutcome outcome = await presenter.vote(
        AcceleratorProjectVote.yes,
        authority: authority,
        canContinue: () => true,
      );
      expect(outcome.state, AcceleratorActionState.refused);
      expect(source.publications, 0);
    },
  );

  test(
    'a superseded original project response cannot paint another read',
    () async {
      final Completer<Project> first = Completer<Project>();
      source.projectReader = (_) => first.future;
      final Future<void> original = presenter.load(source);
      final ActionSource replacement = ActionSource()
        ..project = actionProject(name: 'Fresh project');
      await presenter.load(replacement);
      first.complete(actionProject(name: 'Late original'));
      await original;
      expect(presenter.snapshot.project!.name, 'Fresh project');
      expect(identical(presenter.snapshot.source, replacement), isTrue);
    },
  );

  test(
    'disposal suppresses UI publication and retains the accepted original',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      await presenter.load(source);
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      final Completer<void> entered = Completer<void>();
      source.sender = (_, _) {
        entered.complete();
        return sent.future;
      };
      final Future<AcceleratorActionOutcome> original = presenter.vote(
        AcceleratorProjectVote.yes,
        authority: presenter.snapshot.authority,
        canContinue: () => true,
      );
      await entered.future;
      presenter.dispose();
      disposed = true;
      final AccountBlockTemplate block = actionBlock(777);
      sent.complete(block);
      final AcceleratorActionOutcome result = await original;
      expect(result.state, AcceleratorActionState.submitted);
      expect(identical(result.blocks.single, block), isTrue);
      expect(
        identical(actions.retained(source, voteRequest()), result),
        isTrue,
      );
    },
  );

  test(
    'refresh after reopening can reconcile a retained exact original vote',
    () async {
      source.project = actionProject(status: AcceleratorProjectStatus.voting);
      await actions.submit(source, voteRequest());
      await presenter.load(source);
      expect(presenter.snapshot.held, isTrue);
      expect(presenter.snapshot.canVote, isFalse);
      source
        ..confirmed = true
        ..voteReader = (String name, List<String> ids) async => <PillarVote?>[
          listVote(1, name: name, vote: AcceleratorProjectVote.yes.index),
        ];
      await presenter.refresh(source);
      expect(presenter.snapshot.held, isFalse);
      expect(presenter.snapshot.canVote, isTrue);
      expect(source.confirmedReads, <String>[listHash(901)]);
    },
  );
}
