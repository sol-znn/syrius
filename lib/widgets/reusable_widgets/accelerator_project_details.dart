import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Copied owner, exact hash and creation time. No mutable wallet label lookup.
class AcceleratorProjectDetails extends StatelessWidget {
  /// Displays supplied original facts without a wallet or asynchronous lookup.
  const AcceleratorProjectDetails({
    this.owner,
    this.hash,
    this.creationTimestamp,
    this.acceleratorProjectStatus,
    this.isPhase = false,
    super.key,
  });

  /// Original canonical owner address, with the full identifier in its tooltip.
  final Address? owner;

  /// Exact original project or phase hash, with its full tooltip value.
  final Hash? hash;

  /// Original creation time in Unix seconds, absent when unknown.
  final int? creationTimestamp;

  /// Original status used by the project-only display countdown.
  final AcceleratorProjectStatus? acceleratorProjectStatus;

  /// Whether the original target is a phase, which has no invented age expiry.
  final bool isPhase;
  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    String createdLabel() {
      final String label = context.l10n.acceleratorCreated;
      final String date = FormatUtils.formatDate(creationTimestamp! * 1000);
      return '$label $date';
    }

    final List<String> parts = <String>[
      if (owner != null)
        '${context.l10n.acceleratorOwner} ${owner!.toShortString()}',
      if (hash != null) hash!.toShortString(),
      if (creationTimestamp != null) createdLabel(),
    ];
    if (!isPhase &&
        creationTimestamp != null &&
        acceleratorProjectStatus == AcceleratorProjectStatus.voting) {
      final int remaining =
          creationTimestamp! +
          AcceleratorVotePolicy.projectVotingSeconds -
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (remaining >= 0) {
        parts.add(
          context.l10n.acceleratorClosesIn(
            FormatUtils.formatDurationCoarse(
              context.l10n,
              Duration(seconds: remaining),
            ),
          ),
        );
      }
    }
    return Tooltip(
      message: <String>[
        if (owner != null) owner.toString(),
        if (hash != null) hash.toString(),
      ].join('\n'),
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tokens.dataText.copyWith(fontSize: 12, color: tokens.dim),
      ),
    );
  }
}
