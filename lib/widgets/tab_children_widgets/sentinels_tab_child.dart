import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';

/// Sentinels: the address's rewards (what it can collect, over what it
/// earned) and its own sentinel on top; every sentinel filling the rest.
///
/// The amounts to collect are the head of the rewards card instead of a
/// card of their own.
class SentinelsTabChild extends StatelessWidget {
  /// Creates a Sentinels tab child.
  const SentinelsTabChild({
    required this.onStepperNotificationSeeMorePressed,
    this.embedded = false,
    super.key,
  });

  /// Called when the stepper notification asks to show more details.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Draws just the list under the shared Nodes strip and segment.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (embedded) return const SentinelsCard();
    return PageGrid(
      rows: <PageRow>[
        PageRow.fixed(300, <PageCell>[
          const PageCell(SentinelRewardsCard(), flex: 2),
          PageCell(
            SentinelStatsCard(
              onStepperNotificationSeeMorePressed:
                  onStepperNotificationSeeMorePressed,
            ),
          ),
        ]),
        const PageRow.fill(<PageCell>[PageCell(SentinelsCard())]),
      ],
    );
  }
}
