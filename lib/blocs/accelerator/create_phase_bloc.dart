import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/accelerator_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Compatibility observer for adding a phase to one exact original project.
class CreatePhaseBloc extends AcceleratorActionBloc {
  /// Retains the original injected or captured action capabilities.
  CreatePhaseBloc({super.source, super.controller});

  /// Submits the original draft and phase-membership snapshot without retrying.
  Future<AcceleratorActionOutcome> createPhase(
    Hash id,
    String name,
    String description,
    String url,
    BigInt znnFundsNeeded,
    BigInt qsrFundsNeeded, {
    List<String> phaseIds = const <String>[],
  }) => run(
    AcceleratorActionRequest(
      kind: AcceleratorActionKind.createPhase,
      projectId: id.toString(),
      phaseIds: phaseIds,
      name: name,
      description: description,
      url: url,
      znn: znnFundsNeeded,
      qsr: qsrFundsNeeded,
    ),
  );
}
