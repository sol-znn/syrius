import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'fixtures.dart';

AcceleratorVoteEligibility eligible(
  AcceleratorVoteTarget target, {
  bool current = true,
  bool ownerComplete = true,
  String? pillar = 'test-pillar',
  int now = listClock,
}) => AcceleratorVotePolicy.eligibility(
  target: target,
  capturedContextCurrent: current,
  ownerLookupComplete: ownerComplete,
  exactOwnerPillarName: pillar,
  nowTimestamp: now,
);

void main() {
  test(
    'missing source and owner facts are distinct from an owner with no Pillar',
    () {
      final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
        listProject(1),
      );
      expect(
        eligible(target, current: false),
        AcceleratorVoteEligibility.unknown,
      );
      expect(
        eligible(target, ownerComplete: false),
        AcceleratorVoteEligibility.unknown,
      );
      expect(
        eligible(target, pillar: null),
        AcceleratorVoteEligibility.ineligible,
      );
      expect(eligible(target), AcceleratorVoteEligibility.eligible);
    },
  );

  test('the project list deadline includes its exact boundary', () {
    final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
      listProject(
        1,
        created: listClock - AcceleratorVotePolicy.projectVotingSeconds,
      ),
    );
    expect(
      AcceleratorVotePolicy.hasVotingWindow(target, nowTimestamp: listClock),
      isTrue,
    );
    expect(
      AcceleratorVotePolicy.hasVotingWindow(
        target,
        nowTimestamp: listClock + 1,
      ),
      isFalse,
    );
    // The contract's hash admission rule is separate from the list clock.
    expect(
      eligible(target, now: listClock + 1),
      AcceleratorVoteEligibility.eligible,
    );
  });

  test(
    'old active phases permit change-votes without a parent-active gate',
    () {
      final Project project = listProject(
        1,
        created: 0,
        status: AcceleratorProjectStatus.completed,
        phases: <int>[2],
        phaseStatus: AcceleratorProjectStatus.active,
      );
      final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
        project,
        phase: project.phases.single,
      );
      expect(eligible(target), AcceleratorVoteEligibility.eligible);
      expect(
        AcceleratorVotePolicy.hasVotingWindow(target, nowTimestamp: listClock),
        isTrue,
      );
    },
  );

  test('a removed or foreign phase hash remains unknown', () {
    final Project original = listProject(1, phases: <int>[2]);
    final Project replacement = listProject(1, phases: <int>[3]);
    final AcceleratorVoteTarget removed = AcceleratorVoteTarget.fromProject(
      replacement,
      phase: original.phases.single,
    );
    expect(eligible(removed), AcceleratorVoteEligibility.unknown);
    expect(
      AcceleratorVotePolicy.hasVotingWindow(removed, nowTimestamp: listClock),
      isFalse,
    );
  });

  test('closed project UI status does not offer a vote', () {
    final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
      listProject(1, status: AcceleratorProjectStatus.closed),
    );
    expect(eligible(target), AcceleratorVoteEligibility.ineligible);
  });

  test(
    'a retained phase object cannot replace current same-hash source facts',
    () {
      final Project original = listProject(1, phases: <int>[2]);
      final Project current = listProject(
        1,
        phases: <int>[2],
        phaseStatus: AcceleratorProjectStatus.paid,
      );
      final AcceleratorVoteTarget target = AcceleratorVoteTarget.fromProject(
        current,
        phase: original.phases.single,
      );
      expect(target.exactPhaseMembership, isTrue);
      expect(target.status, AcceleratorProjectStatus.paid);
      expect(eligible(target), AcceleratorVoteEligibility.ineligible);
    },
  );
}
