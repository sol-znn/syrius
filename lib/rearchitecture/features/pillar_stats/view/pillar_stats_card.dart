import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/pillar_owner_card.dart';

/// Legacy entry points share the same owner proof and publication controls.
class PillarStatsCard extends StatelessWidget {
  /// Keeps the existing owner-panel entry point.
  const PillarStatsCard({
    required this._onStepperNotificationSeeMorePressed,
    super.key,
  });

  final VoidCallback _onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) => PillarOwnerCard(
    onClose: () => Navigator.of(context).maybePop(),
    onStepperNotificationSeeMorePressed: _onStepperNotificationSeeMorePressed,
  );
}
