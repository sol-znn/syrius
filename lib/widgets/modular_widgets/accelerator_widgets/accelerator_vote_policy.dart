import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Missing ownership or source facts never become permission to vote.
enum AcceleratorVoteEligibility {
  /// Original source, owner or exact phase-membership proof is incomplete.
  unknown,

  /// Complete original facts do not satisfy the interface's vote policy.
  ineligible,

  /// Complete original facts satisfy the interface policy, pending fresh send.
  eligible,
}

/// A copied exact target from one complete project response.
final class AcceleratorVoteTarget {
  /// Freezes one exact target and its original project-membership facts.
  AcceleratorVoteTarget({
    required this.projectId,
    required this.targetId,
    required this.projectStatus,
    required this.status,
    required this.creationTimestamp,
    required this.isPhase,
    required this.exactPhaseMembership,
    required this.isLatestPhase,
  });

  /// Validates a phase against the complete original project's ordered hashes.
  factory AcceleratorVoteTarget.fromProject(Project project, {Phase? phase}) {
    final String projectId = project.id.toString();
    final List<String> phaseIds = project.phaseIds
        .map((Hash id) => id.toString())
        .toList();
    final List<String> loadedIds = project.phases
        .map((Phase value) => value.id.toString())
        .toList();
    Phase? capturedPhase;
    if (phase != null) {
      for (final Phase value in project.phases) {
        if (value.id.toString() == phase.id.toString()) capturedPhase = value;
      }
    }
    final bool completeMembership =
        phaseIds.length == phaseIds.toSet().length &&
        loadedIds.length == loadedIds.toSet().length &&
        phaseIds.length == loadedIds.length &&
        phaseIds.every(loadedIds.contains);
    return AcceleratorVoteTarget(
      projectId: projectId,
      targetId: phase?.id.toString() ?? projectId,
      projectStatus: project.status,
      status: capturedPhase?.status ?? phase?.status ?? project.status,
      creationTimestamp:
          capturedPhase?.creationTimestamp ??
          phase?.creationTimestamp ??
          project.creationTimestamp,
      isPhase: phase != null,
      exactPhaseMembership:
          phase == null ||
          completeMembership &&
              capturedPhase != null &&
              capturedPhase.projectId.toString() == projectId &&
              phase.projectId.toString() == projectId &&
              phaseIds.contains(phase.id.toString()),
      isLatestPhase:
          phase == null ||
          phaseIds.isNotEmpty && phaseIds.last == phase.id.toString(),
    );
  }

  /// Exact original parent project hash.
  final String projectId;

  /// Exact original project or phase hash selected for the vote.
  final String targetId;

  /// Parent status copied from the original project response.
  final AcceleratorProjectStatus projectStatus;

  /// Status of the exact original target.
  final AcceleratorProjectStatus status;

  /// Original target creation time in Unix seconds.
  final int creationTimestamp;

  /// Whether this target identifies a phase rather than its parent project.
  final bool isPhase;

  /// Whether complete original hashes and loaded phases prove membership.
  final bool exactPhaseMembership;

  /// Whether this phase is last in the original ordered phase-hash list.
  final bool isLatestPhase;
}

/// The existing UI's status gate, with exact fresh ownership and membership.
/// Node ref 590f43ca7a24dccd8e883bc8903a0cb02e54528a binds these facts.
/// VoteByName checks votable-hash existence and active Pillar ownership,
/// not status, age or previous-vote absence. This UI policy
/// does not guarantee contract admission. A sender must refresh the exact hash.
/// RPC Pillar totals are not a proven active MomentumStore denominator.
abstract final class AcceleratorVotePolicy {
  /// Existing project-list display window; never a contract-admission proof.
  static const int projectVotingSeconds = 14 * 24 * 60 * 60;

  /// Applies interface policy only after exact source and ownership checks.
  static AcceleratorVoteEligibility eligibility({
    required AcceleratorVoteTarget target,
    required bool capturedContextCurrent,
    required bool ownerLookupComplete,
    required String? exactOwnerPillarName,
    required int nowTimestamp,
  }) {
    if (!capturedContextCurrent || !ownerLookupComplete) {
      return AcceleratorVoteEligibility.unknown;
    }
    if (exactOwnerPillarName == null) {
      return AcceleratorVoteEligibility.ineligible;
    }
    if (exactOwnerPillarName.isEmpty ||
        target.projectId.isEmpty ||
        target.targetId.isEmpty ||
        target.creationTimestamp < 0 ||
        nowTimestamp < 0 ||
        target.isPhase && !target.exactPhaseMembership) {
      return AcceleratorVoteEligibility.unknown;
    }
    return (target.isPhase &&
                target.status == AcceleratorProjectStatus.active ||
            target.status == AcceleratorProjectStatus.voting)
        ? AcceleratorVoteEligibility.eligible
        : AcceleratorVoteEligibility.ineligible;
  }

  /// Selects targets for display using original status and Unix-second time.
  /// Phase rows do not invent an age expiry absent from this policy.
  static bool hasVotingWindow(
    AcceleratorVoteTarget target, {
    required int nowTimestamp,
  }) {
    // List timing is a UI fact, not VoteByName's contract admission rule.
    // The project remains within the window at the exact deadline. No phase
    // expiry is established by the pinned contract, including change-votes.
    if (target.isPhase) {
      return target.exactPhaseMembership &&
          (target.status == AcceleratorProjectStatus.voting ||
              target.status == AcceleratorProjectStatus.active);
    }
    return target.status == AcceleratorProjectStatus.voting &&
        nowTimestamp <= target.creationTimestamp + projectVotingSeconds;
  }
}
