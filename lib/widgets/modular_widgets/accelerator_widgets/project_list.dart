import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/accelerator_tab_child.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Retained for source compatibility with ProjectListBloc's old cache filters.
/// The redesigned list uses one AcceleratorListFilter over complete sources.
enum AccProjectsFilterTag {
  /// Projects owned by a member of the original wallet.
  myProjects,

  /// Projects whose cached status is active.
  onlyAccepted,

  /// Voting projects or phases without a vote in the original Pillar lookup.
  needsVoting,

  /// Voting projects or phases present in the original Pillar vote lookup.
  alreadyVoted,
}

/// Compatibility entry point. The page captures current ownership itself.
class AccProjectList extends StatelessWidget {
  /// Mounts the page that independently captures its current original source.
  const AccProjectList({
    required this.onStepperNotificationSeeMorePressed,
    required this.pillarInfo,
    super.key,
  });

  /// Original notification-details navigation callback.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Legacy Pillar context, never a substitute for the page's fresh lookup.
  final PillarInfo? pillarInfo;

  @override
  Widget build(BuildContext context) => AcceleratorTabChild(
    onStepperNotificationSeeMorePressed: onStepperNotificationSeeMorePressed,
  );
}
