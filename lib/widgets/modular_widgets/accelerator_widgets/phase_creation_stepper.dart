import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Legacy positions for the original new-phase form.
enum PhaseCreationStep {
  /// Enter the original phase metadata and exact funding amounts.
  phaseDetails,

  /// Explicitly submit the captured draft after fresh original checks.
  submitPhase,
}

/// Fresh admission checks the captured owner and exact latest phase membership.
class PhaseCreationStepper extends StatelessWidget {
  /// Opens a new-phase form for the exact originally supplied project.
  const PhaseCreationStepper(this.project, {this.source, super.key});

  /// Original project and ordered phase membership used by fresh preflight.
  final Project project;

  /// Original action source; absence cannot authorize publication.
  final AcceleratorActionSource? source;
  @override
  Widget build(BuildContext context) => AcceleratorActionStepper(
    kind: AcceleratorActionKind.createPhase,
    project: project,
    source: source,
  );
}
