import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/view/sentinel_values.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_refresh.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The selected address's proven ownership beside root-owned rewards/actions.
///
/// The caller supplies a read bound to its captured address, node and chain.
/// This view also requires an exact owner match; another address's cached
/// record cannot supply a label, object or owner action. An inactive matching
/// record remains owned, because that address cannot register again.
class SentinelStrip extends StatelessWidget {
  /// Creates presentation without fetching, signing or creating action blocs.
  const SentinelStrip({
    required this.selectedAddress,
    required this.ownerState,
    required this.rewards,
    required this.collectAction,
    this.onOpenOwner,
    this.onOpenRewards,
    this.onRefreshOwner,
    super.key,
  });

  /// The address captured by the caller's current read scope.
  final String selectedAddress;

  /// Proven ownership for that scope; an unbound read must be initial.
  final FetchState<List<SentinelInfo>> ownerState;

  /// The ready value, including exact coin amounts and any dollar estimate.
  ///
  /// The caller renders unknown rewards as unknown and owns the price
  /// listener. The view additionally hides this whole value with balances.
  final Widget rewards;

  /// Collection with the caller's captured admission and retained outcome.
  final Widget collectAction;

  /// Opens the existing owner workflow after the caller's own context checks.
  final VoidCallback? onOpenOwner;

  /// Opens the existing rewards history for the caller's captured scope.
  final VoidCallback? onOpenRewards;

  /// Reads ownership again, including when a known revocation window ends.
  final VoidCallback? onRefreshOwner;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final FetchState<List<SentinelInfo>> state = ownerState;
    final SentinelInfo? sentinel = state is FetchPopulated<List<SentinelInfo>>
        ? state.data
              .where(
                (SentinelInfo item) => item.owner.toString() == selectedAddress,
              )
              .firstOrNull
        : null;
    final bool empty =
        state is FetchPopulated<List<SentinelInfo>> && state.data.isEmpty;
    final bool available = sentinel != null || empty;
    final Widget owner;
    if (sentinel != null) {
      owner = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SentinelOwnerText(
            key: const Key('nodes_sentinel_owner_address'),
            address: sentinel.owner.toString(),
            style: tokens.dataText.copyWith(
              fontSize: tokens.pillarOwnerNameText.fontSize,
            ),
          ),
          SizedBox(width: tokens.inlineGap),
          SentinelStatusChip(
            key: Key(
              sentinel.active
                  ? 'nodes_sentinel_active'
                  : 'nodes_sentinel_revoked',
            ),
            active: sentinel.active,
            compact: true,
          ),
        ],
      );
    } else if (empty) {
      owner = Text(context.l10n.nodesNoneYet, style: tokens.compactText);
    } else if (state is FetchFailure<List<SentinelInfo>>) {
      owner = Text(context.l10n.nodesUnavailable, style: tokens.compactText);
    } else {
      owner = const Skeleton(width: 120);
    }

    final Widget strip = PageStrip(
      key: const Key('nodes_sentinels_strip'),
      lead: sentinel == null
          ? null
          : NodeObject.sentinel(
              key: ValueKey<(String, int)>((
                sentinel.owner.toString(),
                sentinel.registrationTimestamp,
              )),
              size: kStripLeadSize,
            ),
      figures: <StripFigure>[
        StripFigure(
          label: context.l10n.nodesYourSentinel,
          value: owner,
        ),
        StripFigure(
          label: context.l10n.nodesToCollect,
          value: HiddenAmount(child: rewards),
          trailing: collectAction,
        ),
        if (!empty)
          StripFigure(
            label: context.l10n.nodesRevocable,
            value: sentinel == null
                ? state is FetchFailure<List<SentinelInfo>>
                      ? Text(
                          context.l10n.nodesUnavailable,
                          style: tokens.compactText,
                        )
                      : const Skeleton(width: 80)
                : SentinelRevocationTime(
                    key: ValueKey<String>(sentinel.owner.toString()),
                    sentinel: sentinel,
                    chip: true,
                    onRefresh: onRefreshOwner,
                  ),
          ),
      ],
      actions: <Widget>[
        TextButton.icon(
          key: const Key('nodes_sentinel_rewards'),
          style: quietButtonStyle(context).copyWith(
            minimumSize: WidgetStatePropertyAll<Size>(
              Size(0, tokens.compactButtonHeight),
            ),
            padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsetsDirectional.symmetric(horizontal: tokens.cardGap),
            ),
            textStyle: WidgetStatePropertyAll<TextStyle>(tokens.compactText),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onOpenRewards,
          icon: Icon(Icons.bar_chart_rounded, size: tokens.settingsIconSize),
          label: Text(context.l10n.nodesRewards),
        ),
        IconButton(
          key: const Key('nodes_sentinel_owner'),
          tooltip: context.l10n.nodesYourSentinel,
          onPressed: available ? onOpenOwner : null,
          icon: Icon(Icons.more_horiz, size: tokens.railIconSize),
        ),
      ],
    );
    final VoidCallback? refresh = onRefreshOwner;
    return refresh == null
        ? strip
        : PageRefreshAction(onRefresh: refresh, child: strip);
  }
}
