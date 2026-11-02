import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/accelerator_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Compatibility observer for one exact project or phase vote intent.
class VoteProjectBloc extends AcceleratorActionBloc {
  /// Retains the original injected or captured action capabilities.
  VoteProjectBloc({super.source, super.controller});

  /// Submits the chosen target, Pillar and vote without choosing replacements.
  Future<AcceleratorActionOutcome> voteProject(
    Hash id,
    AcceleratorProjectVote vote, {
    Hash? projectId,
    String? pillarName,
  }) => run(
    // No owner lookup may silently choose a Pillar or reinterpret a phase hash.
    AcceleratorActionRequest(
      kind: AcceleratorActionKind.vote,
      projectId: (projectId ?? id).toString(),
      phaseId: projectId == null || projectId == id ? null : id.toString(),
      pillarName: pillarName,
      vote: vote,
    ),
  );
}
