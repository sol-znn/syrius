import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_list_item.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Legacy phase display. Current project browsing uses AcceleratorListView.
enum AcceleratorProjectsFilterTag {
  /// Legacy selection of projects owned by wallet members.
  myProjects,

  /// Legacy selection of accepted projects.
  onlyAccepted,

  /// Legacy selection of projects with voting open.
  votingOpened,
}

/// Already supplied phases are displayed without starting legacy vote senders.
class AcceleratorProjectList extends StatelessWidget {
  /// Displays already supplied project or phase facts without a vote sender.
  const AcceleratorProjectList(
    this.pillarInfo,
    this.acceleratorProjects, {
    required this.onStepperNotificationSeeMorePressed,
    this.projects,
    super.key,
  });

  /// Legacy caller Pillar context, never fresh action permission.
  final PillarInfo? pillarInfo;

  /// Exact original rows supplied by the parent, without an implicit RPC read.
  final List<AcceleratorProject> acceleratorProjects;

  /// Original parent project when the supplied rows are phases.
  final Project? projects;

  /// Original notification-details navigation callback.
  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) {
    if (acceleratorProjects.isEmpty) {
      return EmptyNote(text: context.l10n.acceleratorNoneYet);
    }
    return ListView.separated(
      itemCount: acceleratorProjects.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) =>
          AcceleratorProjectListItem(
            key: ValueKey<String>(acceleratorProjects[index].id.toString()),
            acceleratorProject: acceleratorProjects[index],
            project: projects,
            onStepperNotificationSeeMorePressed:
                onStepperNotificationSeeMorePressed,
          ),
    );
  }
}
