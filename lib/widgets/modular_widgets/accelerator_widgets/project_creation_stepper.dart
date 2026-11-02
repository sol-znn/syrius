import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart';

/// Legacy positions retained for the original project-creation flow.
enum ProjectCreationStep {
  /// Review project-creation funding and the original account balance.
  projectCreation,

  /// Enter the original project metadata and exact requested allocation.
  projectDetails,

  /// Explicitly submit the original draft after fresh source checks.
  submitProject,
}

/// The existing project creation flow, with one captured original action scope.
class ProjectCreationStepper extends StatelessWidget {
  /// Opens creation under one originally captured action scope.
  const ProjectCreationStepper({this.source, super.key});

  /// Original action source; absence cannot authorize publication.
  final AcceleratorActionSource? source;
  @override
  Widget build(BuildContext context) => AcceleratorActionStepper(
    kind: AcceleratorActionKind.createProject,
    source: source,
  );
}
