import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Legacy positions for replacement of one exact original latest phase.
enum UpdatePhaseStep {
  /// Edit metadata and funding amounts from the original selected phase.
  phaseDetails,

  /// Explicitly submit that replacement after fresh original checks.
  updatePhase,
}

/// An update replaces the captured exact latest phase, never a later one.
class UpdatePhaseStepper extends StatelessWidget {
  /// Opens an update bound to the original phase and its parent project.
  const UpdatePhaseStepper(this.phase, this.project, {this.source, super.key});

  /// The exact original phase to replace, never a later selected phase.
  final Phase phase;

  /// Original parent project and phase membership required by preflight.
  final Project project;

  /// Original action source; absence cannot authorize publication.
  final AcceleratorActionSource? source;
  @override
  Widget build(BuildContext context) => AcceleratorActionStepper(
    kind: AcceleratorActionKind.updatePhase,
    project: project,
    phase: phase,
    source: source,
  );
}
