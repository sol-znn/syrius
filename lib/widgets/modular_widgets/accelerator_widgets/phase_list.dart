import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/screens/stepper_screen.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_list.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/phase_creation_stepper.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Compatibility phase panel. A supplied original source owns its actions.
class PhaseList extends StatelessWidget {
  /// Displays copied phase facts and actions bound to the supplied source.
  const PhaseList(
    this.pillarInfo,
    this.project,
    this.onRefreshButtonPressed, {
    required this.onStepperNotificationSeeMorePressed,
    this.source,
    super.key,
  });

  /// Legacy caller's Pillar context; never substitutes for fresh ownership.
  final PillarInfo? pillarInfo;

  /// The original project whose phase membership this panel displays.
  final Project project;

  /// Legacy refresh callback retained for compatible callers.
  final VoidCallback onRefreshButtonPressed;

  /// The original notification-details navigation callback.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// The captured action capability, absent when creation cannot be admitted.
  final AcceleratorActionSource? source;

  @override
  Widget build(BuildContext context) {
    final AcceleratorActionSource? origin = source;
    final List<String> ids = project.phaseIds
        .map((Hash id) => id.toString())
        .toList();
    Phase? latest;
    for (final Phase phase in project.phases) {
      if (ids.isNotEmpty && phase.id.toString() == ids.last) latest = phase;
    }
    final bool canCreate =
        origin != null &&
        origin.isCurrent &&
        project.owner.toString() == origin.ownerAddress &&
        project.status == AcceleratorProjectStatus.active &&
        ids.length == project.phases.length &&
        ids.toSet().length == ids.length &&
        (ids.isEmpty || latest?.status == AcceleratorProjectStatus.paid);
    return Panel(
      title: context.l10n.acceleratorPhases,
      actions: <Widget>[
        OutlinedButton(
          key: const Key('acc_create_phase'),
          style: accCompactQuietStyle(context),
          onPressed: canCreate
              ? () {
                  if (!origin.isCurrent ||
                      !(ModalRoute.of(context)?.isCurrent ?? true) ||
                      !TickerMode.valuesOf(context).enabled) {
                    return;
                  }
                  final Project copy = AcceleratorListProject.fromProject(
                    project,
                  ).toProject();
                  final Widget stepper = PhaseCreationStepper(
                    copy,
                    source: origin,
                  );
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => StepperScreen(
                        stepper: stepper,
                        onStepperNotificationSeeMorePressed:
                            onStepperNotificationSeeMorePressed,
                      ),
                    ),
                  );
                }
              : null,
          child: Text(context.l10n.acceleratorCreatePhase),
        ),
      ],
      child: AcceleratorProjectList(
        null,
        project.phases,
        projects: project,
        onStepperNotificationSeeMorePressed:
            onStepperNotificationSeeMorePressed,
      ),
    );
  }
}
