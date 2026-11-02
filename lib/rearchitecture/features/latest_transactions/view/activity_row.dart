import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/model/activity_entry.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/value_flash.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/explorer_links.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';

/// One source-bound movement, with no background reads or transaction action.
class ActivityRow extends StatefulWidget {
  /// Draws an exact history entry at [now].
  const ActivityRow({
    required this.entry,
    required this.now,
    this.chainId,
    this.addressLabels = const <String, String>{},
    this.visibility,
    this.onOpenExplorer,
    super.key,
  });

  /// The original block's presentation data.
  final ActivityEntry entry;

  /// The view's shared clock for relative time.
  final DateTime now;

  /// The source chain, never guessed from the currently selected network.
  final int? chainId;

  /// The wallet's current local labels, read without changing them.
  final Map<String, String> addressLabels;

  /// The shared balance choice; defaults to the wallet singleton.
  final BalanceVisibility? visibility;

  /// An isolated opener for widget qualification; normally the wallet opener.
  final ValueChanged<Uri>? onOpenExplorer;

  @override
  State<ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<ActivityRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ActivityEntry entry = widget.entry;
    final Color actionInk = entry.incoming ? tokens.znnInk : tokens.dim;
    return MouseRegion(
      onEnter: (_) => _hover.forward(),
      onExit: (_) => _hover.reverse(),
      child: AnimatedBuilder(
        animation: _hover,
        builder: (BuildContext context, Widget? child) => Container(
          key: ValueKey<String>('activity_row:${entry.hash}'),
          constraints: BoxConstraints(minHeight: tokens.activityRowHeight),
          padding: tokens.activityRowPadding,
          decoration: BoxDecoration(
            color: tokens.hover.withValues(
              alpha: tokens.hover.a * tokens.ease.transform(_hover.value),
            ),
            border: Border(bottom: BorderSide(color: tokens.line)),
          ),
          child: child,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 22,
              child: Row(
                children: <Widget>[
                  Icon(
                    _icon(entry.kind),
                    size: tokens.activityIconSize,
                    color: actionInk,
                  ),
                  SizedBox(width: tokens.homeTokenRowGap),
                  Flexible(
                    child: Text(
                      _label(context, entry.kind),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.bodyText.copyWith(color: actionInk),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: tokens.activityColumnGap),
            Expanded(flex: 31, child: _buildCounterparty(context)),
            SizedBox(width: tokens.activityColumnGap),
            Expanded(flex: 22, child: _buildAmount(context)),
            SizedBox(width: tokens.activityColumnGap),
            Expanded(flex: 12, child: _buildTime(context)),
            SizedBox(width: tokens.activityColumnGap),
            Expanded(flex: 13, child: _buildAction(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterparty(BuildContext context) {
    final ActivityEntry entry = widget.entry;
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle style = tokens.dataText.copyWith(color: tokens.dim);
    if (entry.name case final String name) {
      return Tooltip(
        message: name,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
          textDirection: ltrUnlessRtl(name),
        ),
      );
    }
    if (entry.stakeMonths case final int months) {
      return Text(
        context.l10n.stakeDurationMonths(months),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final String? address = (entry.fuseBeneficiary ?? entry.counterparty)
        ?.toString();
    if (address == null) {
      return Text(context.l10n.homeAmountUnknown, style: style);
    }
    final String short = _short(address);
    final String? label = widget.addressLabels[address];
    final String text = entry.fuseBeneficiary == null
        ? (label ?? short)
        : '${context.l10n.plasma}, ${label ?? short}';
    return Tooltip(
      message: address,
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
              textDirection: ltrUnlessRtl(text),
            ),
          ),
          if (label != null && entry.fuseBeneficiary == null) ...<Widget>[
            SizedBox(width: tokens.heroSymbolGap),
            Flexible(
              child: Text(
                short,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: tokens.faint),
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAmount(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ActivityEntry entry = widget.entry;
    final BigInt? raw = entry.amount;
    final int? decimals = entry.decimals;
    final TextStyle style = tokens.dataText;
    final Widget number = raw == null || decimals == null
        ? Text(context.l10n.activityUnitsUnavailable, style: style)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (raw != BigInt.zero)
                Text(entry.incoming ? '+ ' : '− ', style: style),
              AmountText(raw, decimals: decimals, style: style),
            ],
          );
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: Ltr(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueFlash(
                value: (raw, decimals),
                child: HiddenAmount(
                  key: ValueKey<String>('activity_amount:${entry.hash}'),
                  visibility: widget.visibility,
                  style: style,
                  alignment: AlignmentDirectional.centerEnd,
                  child: number,
                ),
              ),
              if (entry.symbol case final String symbol) ...<Widget>[
                SizedBox(width: tokens.heroSymbolGap),
                Text(symbol, style: style),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTime(BuildContext context) {
    final int? timestamp = widget.entry.timestamp;
    final TextStyle style = AppTokens.of(context).bodyText.copyWith(
      color: AppTokens.of(context).dim,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    if (timestamp == null || timestamp <= 0 || timestamp > 8640000000000) {
      return Text(
        context.l10n.pending,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final DateTime confirmed = DateTime.fromMillisecondsSinceEpoch(
      timestamp * Duration.millisecondsPerSecond,
    );
    final Duration age = widget.now.difference(confirmed);
    final String text = age.inMinutes < 1
        ? context.l10n.activityNow
        : age.inHours < 1
        ? context.l10n.activityMinutes(age.inMinutes)
        : age.inDays < 1
        ? context.l10n.activityHours(age.inHours)
        : context.l10n.activityDays(age.inDays);
    return Tooltip(
      message: FormatUtils.formatDateTimeSeconds(
        timestamp * Duration.millisecondsPerSecond,
        locale: Localizations.localeOf(context),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: style,
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ActivityEntry entry = widget.entry;
    if (entry.hasMessage) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SeamGate(
          key: ValueKey<String>('activity_message:${entry.hash}'),
          seam: Seam.zapReceive,
          child: TextButton(
            onPressed: () => throw const SeamNotBuilt(Seam.zapReceive),
            style: TextButton.styleFrom(
              backgroundColor: tokens.card2,
              foregroundColor: tokens.foreground,
              padding: tokens.activityMessagePadding,
              minimumSize: Size(0, tokens.smallButtonHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              shape: StadiumBorder(side: BorderSide(color: tokens.line)),
              textStyle: tokens.captionText.copyWith(
                color: tokens.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(
              context.l10n.activityMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }
    final Uri? link = ExplorerLinks.transaction(
      entry.hash,
      chainId: widget.chainId,
    );
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: IconButton(
        key: ValueKey<String>('activity_explorer:${entry.hash}'),
        tooltip: context.l10n.activityExplorer,
        onPressed: link == null
            ? null
            : () {
                if (widget.onOpenExplorer case final ValueChanged<Uri> open) {
                  open(link);
                } else {
                  unawaited(NavigationUtils.openUrl(link.toString()));
                }
              },
        style: IconButton.styleFrom(
          foregroundColor: tokens.faint,
          disabledForegroundColor: tokens.faint,
          minimumSize: Size.square(tokens.smallButtonHeight),
          maximumSize: Size.square(tokens.smallButtonHeight),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(Icons.open_in_new_rounded, size: tokens.activityIconSize),
      ),
    );
  }

  static String _short(String value) => value.length <= 12
      ? value
      : '${value.substring(0, 6)}…${value.substring(value.length - 4)}';

  static IconData _icon(ActivityKind kind) => switch (kind) {
    ActivityKind.received => Icons.south_rounded,
    ActivityKind.sent => Icons.north_rounded,
    ActivityKind.delegated => Icons.layers_outlined,
    ActivityKind.fused || ActivityKind.zap => Icons.bolt_outlined,
    ActivityKind.reward || ActivityKind.staked => Icons.bubble_chart_outlined,
    ActivityKind.other => Icons.history_rounded,
  };

  static String _label(BuildContext context, ActivityKind kind) =>
      switch (kind) {
        ActivityKind.received => context.l10n.activityReceived,
        ActivityKind.sent => context.l10n.sent,
        ActivityKind.delegated => context.l10n.activityDelegated,
        ActivityKind.fused => context.l10n.activityFused,
        ActivityKind.reward => context.l10n.activityReward,
        ActivityKind.staked => context.l10n.activityStaked,
        ActivityKind.zap => context.l10n.transferZap,
        ActivityKind.other => context.l10n.activityTitle,
      };
}
