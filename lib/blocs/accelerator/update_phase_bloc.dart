import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/accelerator_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Compatibility observer for replacing the exact original latest phase.
class UpdatePhaseBloc extends AcceleratorActionBloc {
  /// Retains the original injected or captured action capabilities.
  UpdatePhaseBloc({super.source, super.controller});

  /// Requires the original phase hash and membership before admitting a draft.
  Future<AcceleratorActionOutcome> updatePhase(
    Hash id,
    String name,
    String description,
    String url,
    BigInt znnFundsNeeded,
    BigInt qsrFundsNeeded, {
    String? phaseId,
    List<String> phaseIds = const <String>[],
  }) => run(
    // The old signature did not identify a phase. Such a call now refuses;
    // a fresh UI must carry the exact original latest phase and membership.
    AcceleratorActionRequest(
      kind: AcceleratorActionKind.updatePhase,
      projectId: id.toString(),
      phaseId: phaseId,
      phaseIds: phaseIds,
      name: name,
      description: description,
      url: url,
      znn: znnFundsNeeded,
      qsr: qsrFundsNeeded,
    ),
  );
}
