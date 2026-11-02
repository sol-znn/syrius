import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/screens/project_details_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_parts.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Builds details from the exact copied project supplied by the selected row.
typedef AcceleratorProjectDetailBuilder =
    Widget Function(
      BuildContext context,
      AcceleratorListProject project,
    );

/// A single ledger row. Voting belongs to the fresh project detail proof.
class AcceleratorProjectListItem extends StatelessWidget {
  /// Compatibility for the existing phase list, without legacy vote senders.
  const AcceleratorProjectListItem({
    required this.acceleratorProject,
    required this.onStepperNotificationSeeMorePressed,
    this.pillarInfo,
    this.project,
    super.key,
  }) : row = null,
       needsVote = false,
       stillCurrent = null,
       nowTimestamp = null,
       detailBuilder = null;

  /// Displays one copied source-bound project with guarded details navigation.
  const AcceleratorProjectListItem.presented({
    required this.row,
    required this.needsVote,
    required this.nowTimestamp,
    required this.stillCurrent,
    required this.onStepperNotificationSeeMorePressed,
    this.detailBuilder,
    super.key,
  }) : acceleratorProject = null,
       pillarInfo = null,
       project = null;

  /// Legacy project or phase supplied directly by the original caller.
  final AcceleratorProject? acceleratorProject;

  /// Legacy Pillar context, never permission for a fresh details-page vote.
  final PillarInfo? pillarInfo;

  /// Legacy parent project context for a supplied phase.
  final Project? project;

  /// Copied source-bound row, absent for the legacy phase-display constructor.
  final AcceleratorListProject? row;

  /// Whether complete original owner and vote facts prove an absent vote.
  final bool needsVote;

  /// Unix-second display clock, supplied by the original list presenter.
  final int? nowTimestamp;

  /// Original source-generation check required before opening details.
  final bool Function()? stillCurrent;

  /// Optional inert details builder for isolated presentation fixtures.
  final AcceleratorProjectDetailBuilder? detailBuilder;

  /// Original callback opening notification details from a nested stepper.
  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorListProject? presented = row;
    if (presented == null) return _buildLegacyPhase(context);
    return OpenContainer<void>(
      key: ValueKey<String>('accelerator_transform_${presented.id}'),
      transitionDuration: tokens.acceleratorTransformDuration,
      tappable: false,
      closedElevation: 0,
      openElevation: 0,
      closedColor: tokens.card,
      openColor: tokens.card,
      closedShape: const RoundedRectangleBorder(),
      openShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      closedBuilder: (BuildContext context, VoidCallback open) => InkWell(
        key: ValueKey<String>('accelerator_project_${presented.id}'),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: tokens.hover,
        onTap: () {
          if ((stillCurrent?.call() ?? false) &&
              (ModalRoute.of(context)?.isCurrent ?? true) &&
              TickerMode.valuesOf(context).enabled) {
            open();
          }
        },
        child: _buildProject(context, presented),
      ),
      openBuilder: (BuildContext context, VoidCallback close) {
        if (!(stillCurrent?.call() ?? false)) {
          return Center(
            child: Text(
              context.l10n.acceleratorUnknown,
              style: tokens.bodyText,
            ),
          );
        }
        return detailBuilder?.call(context, presented) ??
            ProjectDetailsScreen(
              project: presented.toProject(),
              // Details obtains fresh exact ownership. A list's Pillar cannot
              // authorize a vote after navigation or another asynchronous read.
              pillarInfo: null,
              onStepperNotificationSeeMorePressed:
                  onStepperNotificationSeeMorePressed,
            );
      },
    );
  }

  Widget _buildProject(BuildContext context, AcceleratorListProject value) {
    final AppTokens tokens = AppTokens.of(context);
    final int now =
        nowTimestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int elapsedSeconds = now > value.creationTimestamp
        ? now - value.creationTimestamp
        : 0;
    final String elapsed = context.l10n.nodesAgoDuration(
      FormatUtils.formatDurationCoarse(
        context.l10n,
        Duration(seconds: elapsedSeconds),
      ),
    );
    final String shortOwner = value.owner.length > 14
        ? value.owner.replaceRange(7, value.owner.length - 6, '…')
        : value.owner;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: tokens.acceleratorRowHeight),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: tokens.acceleratorCellPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      value.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.bodyText,
                    ),
                    Tooltip(
                      message: value.owner,
                      child: Ltr(
                        child: Text(
                          context.l10n.acceleratorByOwner(shortOwner, elapsed),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.dataText.copyWith(
                            fontSize: 12,
                            color: tokens.dim,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _cell(
              tokens.acceleratorBudgetWidth,
              tokens,
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _budget(context, value.znn, value.qsr),
              ),
            ),
            _cell(
              tokens.acceleratorVotesWidth,
              tokens,
              AcceleratorVoteBar(tally: value.tallyAt(now)),
            ),
            _cell(
              tokens.acceleratorQuorumWidth,
              tokens,
              Text(
                context.l10n.acceleratorUnknown,
                key: ValueKey<String>('accelerator_quorum_${value.id}'),
                style: tokens.compactText.copyWith(color: tokens.dim),
              ),
            ),
            _cell(
              tokens.acceleratorStatusWidth,
              tokens,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: needsVote
                    ? AccChip(
                        label: context.l10n.acceleratorYourVote,
                        dotColor: tokens.warn,
                        icon: Icons.how_to_vote_outlined,
                        filled: true,
                      )
                    : AccStatusChip(value.status),
              ),
            ),
            SizedBox(
              width: tokens.acceleratorChevronWidth,
              child: Icon(Icons.chevron_right, size: 16, color: tokens.faint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(double width, AppTokens tokens, Widget child) => SizedBox(
    width: width,
    child: Padding(
      padding: tokens.acceleratorCellPadding,
      child: Center(
        heightFactor: 1,
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    ),
  );

  Widget _budget(BuildContext context, BigInt znn, BigInt qsr) {
    final AppTokens tokens = AppTokens.of(context);
    return Ltr(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AmountText(
            znn,
            decimals: coinDecimals,
            symbol: 'ZNN',
            style: tokens.dataText,
          ),
          AmountText(
            qsr,
            decimals: coinDecimals,
            symbol: 'QSR',
            style: tokens.dataText.copyWith(color: tokens.dim),
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyPhase(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorProject item = acceleratorProject!;
    return Padding(
      padding: tokens.acceleratorCellPadding,
      child: Row(
        children: <Widget>[
          Expanded(child: Text(item.name, style: tokens.bodyText)),
          SizedBox(
            width: tokens.acceleratorBudgetWidth,
            child: _budget(context, item.znnFundsNeeded, item.qsrFundsNeeded),
          ),
          SizedBox(
            width: tokens.acceleratorVotesWidth,
            child: AcceleratorVoteBar(
              tally: AcceleratorListTally.from(
                item.voteBreakdown,
                item.id.toString(),
              ),
            ),
          ),
          AccStatusChip(item.status),
        ],
      ),
    );
  }
}

/// Vote shares use the actual tally total. They never imply a quorum total.
class AcceleratorVoteBar extends StatelessWidget {
  /// Displays only the validated tally, with unknown retained as unknown.
  const AcceleratorVoteBar({required this.tally, super.key});

  /// Original validated counts; null does not imply zero votes or quorum.
  final AcceleratorListTally? tally;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorListTally? votes = tally;
    if (votes == null) {
      return Text(
        context.l10n.acceleratorUnknown,
        style: tokens.compactText.copyWith(color: tokens.dim),
      );
    }
    final int total = votes.total;
    double share(int value) => total == 0 ? 0 : value / total;
    return Ltr(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: tokens.acceleratorVoteBarWidth,
            height: tokens.acceleratorVoteBarHeight,
            child: AccMeter(
              parts: <(double, Color)>[
                (share(votes.yes), tokens.znn),
                (share(votes.no), tokens.error),
                (share(votes.abstain), tokens.faint),
              ],
            ),
          ),
          SizedBox(width: tokens.inlineGap),
          Flexible(
            child: Text(
              context.l10n.acceleratorVoteTally(
                votes.yes,
                votes.no,
                votes.abstain,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.dataText.copyWith(fontSize: 12, color: tokens.dim),
            ),
          ),
        ],
      ),
    );
  }
}
