import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/accelerator_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';

/// Compatibility observer for one original Accelerator project-creation intent.
class CreateProjectBloc extends AcceleratorActionBloc {
  /// Retains the original injected or captured action capabilities.
  CreateProjectBloc({super.source, super.controller});

  /// Submits copied metadata and exact native funding units for the project.
  Future<AcceleratorActionOutcome> createProject(
    String name,
    String description,
    String url,
    BigInt znnFundsNeeded,
    BigInt qsrFundsNeeded,
  ) => run(
    AcceleratorActionRequest(
      kind: AcceleratorActionKind.createProject,
      name: name,
      description: description,
      url: url,
      znn: znnFundsNeeded,
      qsr: qsrFundsNeeded,
    ),
  );
}
