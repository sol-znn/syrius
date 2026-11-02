import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_list_item.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_vote_policy.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The existing project, its phases, and one exact selected vote target.
class AcceleratorProjectView extends StatefulWidget {
  /// Presents one original project with callbacks supplied by its route owner.
  const AcceleratorProjectView({
    required this.presenter,
    required this.onBack,
    required this.onRefresh,
    required this.title,
    this.onCreatePhase,
    this.onUpdatePhase,
    this.onOpenUrl,
    this.explorer,
    super.key,
  });

  /// Original read and action orchestration owner for the exact project hash.
  final AcceleratorProjectPresenter presenter;

  /// Copied original project title used while fresh detail facts are read.
  final String title;

  /// The original guarded route-exit action.
  final VoidCallback onBack;

  /// Explicit fresh-read and original-effect rearm action.
  final VoidCallback onRefresh;

  /// Admits a phase form using the exact copied current project.
  final ValueChanged<Project>? onCreatePhase;

  /// Admits an update form using the exact copied current project and phase.
  final void Function(Project, Phase)? onUpdatePhase;

  /// Opens an exact original URL only through its route owner's guard.
  final ValueChanged<String>? onOpenUrl;

  /// Original chain-specific explorer URL, absent when unavailable.
  final String? explorer;
  @override
  State<AcceleratorProjectView> createState() => _AcceleratorProjectViewState();
}

class _AcceleratorProjectViewState extends State<AcceleratorProjectView> {
  Timer? _clock;
  int _epoch = 0;
  bool _visible = true;
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    widget.presenter.addListener(_changed);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible = TickerMode.valuesOf(context).enabled;
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (_visible && !visible || !identical(route, _route)) _epoch++;
    _visible = visible;
    _route = route;
  }

  @override
  void didUpdateWidget(AcceleratorProjectView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presenter != widget.presenter) {
      oldWidget.presenter.removeListener(_changed);
      widget.presenter.addListener(_changed);
      _epoch++;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _onPage => mounted && _visible && (_route?.isCurrent ?? true);
  bool _can(AcceleratorProjectSnapshot source, int epoch) =>
      _onPage && epoch == _epoch && widget.presenter.owns(source.authority);
  @override
  void dispose() {
    _epoch++;
    _clock?.cancel();
    widget.presenter.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorProjectSnapshot source = widget.presenter.snapshot;
    final Project? project = source.isCurrent
        ? source.project?.toProject()
        : null;
    final int epoch = _epoch;
    return Material(
      key: const Key('accelerator_project_detail'),
      color: tokens.card,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context, source, project, epoch),
          Divider(height: 1, color: tokens.line),
          Expanded(
            child: project == null
                ? Center(
                    child: source.failed || !source.isCurrent
                        ? Text(
                            source.failed
                                ? context.l10n.acceleratorReadFailed
                                : context.l10n.acceleratorSessionChanged,
                            style: tokens.compactText,
                          )
                        : const Padding(
                            padding: EdgeInsets.all(24),
                            child: SkeletonRows(rows: 4),
                          ),
                  )
                : KeyedSubtree(
                    key:
                        source.ownerComplete &&
                            (source.pillarName == null || source.votesComplete)
                        ? const Key('accelerator_project_loaded')
                        : null,
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final double width = math.max(
                              constraints.maxWidth,
                              tokens.acceleratorDetailMinWidth,
                            );
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: width,
                                height: constraints.maxHeight,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Padding(
                                          padding: tokens
                                              .acceleratorDetailBodyPadding,
                                          child: _buildProject(
                                            context,
                                            source,
                                            project,
                                            epoch,
                                          ),
                                        ),
                                      ),
                                    ),
                                    VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color: tokens.line,
                                    ),
                                    SizedBox(
                                      key: const Key('accelerator_vote_aside'),
                                      width: tokens.acceleratorVoteAsideWidth,
                                      child: SingleChildScrollView(
                                        child: Padding(
                                          padding: tokens
                                              .acceleratorVoteAsidePadding,
                                          child: _buildVoteAside(
                                            context,
                                            source,
                                            project,
                                            epoch,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AcceleratorProjectSnapshot source,
    Project? project,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    Widget link(String label, String? url) => TextButton.icon(
      style: quietButtonStyle(context).copyWith(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 30)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 6),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(tokens.compactText),
      ),
      onPressed: url == null || url.isEmpty || widget.onOpenUrl == null
          ? null
          : () {
              if (_can(source, epoch)) widget.onOpenUrl!(url);
            },
      icon: const Icon(Icons.open_in_new, size: 12),
      label: Text(label),
    );
    final Widget back = TextButton.icon(
      key: const Key('project_details_back'),
      style: quietButtonStyle(context).copyWith(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, tokens.smallButtonHeight),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(
          kTextButtonTextStyle.copyWith(fontSize: 12),
        ),
      ),
      onPressed: () {
        if (_onPage) widget.onBack();
      },
      icon: const Icon(Icons.chevron_left, size: 16),
      label: Text(context.l10n.acceleratorProjects),
    );
    final TextStyle titleStyle = tokens.bodyText.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    final Widget? status = project == null
        ? null
        : source.needsVote
        ? AccChip(
            label: context.l10n.acceleratorYourVote,
            icon: Icons.how_to_vote_outlined,
            dotColor: tokens.warn,
            filled: true,
          )
        : AccStatusChip(project.status);
    final List<Widget> actions = <Widget>[
      link(context.l10n.acceleratorArticle, project?.url),
      link(context.l10n.acceleratorExplorer, widget.explorer),
      IconButton(
        key: const Key('accelerator_project_refresh'),
        tooltip: context.l10n.acceleratorRefresh,
        iconSize: 16,
        onPressed: source.busy
            ? null
            : () {
                if (_onPage) widget.onRefresh();
              },
        icon: Icon(Icons.refresh, color: tokens.faint),
      ),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: tokens.panelHeaderHeight),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.acceleratorCellPadding.start,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double labelSize = tokens.compactText.fontSize!;
            final double labelScale = math.max(
              1,
              MediaQuery.textScalerOf(context).scale(labelSize) / labelSize,
            );
            if (constraints.maxWidth <
                tokens.acceleratorDetailMinWidth * labelScale) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.inlineGap / 2),
                child: Wrap(
                  spacing: tokens.inlineGap,
                  runSpacing: tokens.inlineGap / 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    back,
                    Text(project?.name ?? widget.title, style: titleStyle),
                    ?status,
                    ...actions,
                  ],
                ),
              );
            }
            return Row(
              children: <Widget>[
                back,
                SizedBox(width: tokens.inlineGap),
                Flexible(
                  child: Text(
                    project?.name ?? widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                SizedBox(width: tokens.inlineGap),
                ?status,
                const Spacer(),
                ...actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildProject(
    BuildContext context,
    AcceleratorProjectSnapshot source,
    Project project,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    Widget fact(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label.toUpperCase(), style: tokens.ledgerText),
        SizedBox(height: tokens.inlineGap),
        child,
      ],
    );
    final String owner = project.owner.toString();
    final String short = owner.length > 14
        ? '${owner.substring(0, 7)}…${owner.substring(owner.length - 6)}'
        : owner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: tokens.acceleratorDetailFactsGap,
          runSpacing: tokens.cardGap,
          children: <Widget>[
            fact(
              context.l10n.acceleratorBudget,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AmountText(
                    project.znnFundsNeeded,
                    decimals: coinDecimals,
                    symbol: 'ZNN',
                    style: tokens.dataText.copyWith(fontSize: 19),
                  ),
                  Text(
                    '  ·  ',
                    style: tokens.dataText.copyWith(
                      fontSize: 13,
                      color: tokens.dim,
                    ),
                  ),
                  AmountText(
                    project.qsrFundsNeeded,
                    decimals: coinDecimals,
                    symbol: 'QSR',
                    style: tokens.dataText.copyWith(
                      fontSize: 13,
                      color: tokens.dim,
                    ),
                  ),
                ],
              ),
            ),
            fact(
              context.l10n.acceleratorOwner,
              Tooltip(
                message: owner,
                child: Text(
                  short,
                  style: tokens.dataText.copyWith(color: tokens.dim),
                ),
              ),
            ),
            fact(
              context.l10n.acceleratorCreated,
              Text(
                FormatUtils.formatDate(project.creationTimestamp * 1000),
                style: tokens.bodyText,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.panelGap),
        Text(
          project.description,
          style: tokens.bodyText.copyWith(color: tokens.dim, height: 1.4),
        ),
        SizedBox(height: tokens.panelGap),
        _buildPhases(context, source, project, epoch),
      ],
    );
  }

  Widget _buildPhases(
    BuildContext context,
    AcceleratorProjectSnapshot source,
    Project project,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final List<String> ids = project.phaseIds
        .map((Hash id) => id.toString())
        .toList();
    final List<Phase> ordered = <Phase>[
      for (final String id in ids)
        for (final Phase phase in project.phases)
          if (phase.id.toString() == id) phase,
    ];
    final bool exact =
        ordered.length == ids.length &&
        ids.length == ids.toSet().length &&
        project.phases.length == ids.length &&
        source.project!.targets.every(
          (AcceleratorVoteTarget target) =>
              !target.isPhase || target.exactPhaseMembership,
        );
    final bool canCreate =
        exact &&
        source.owner &&
        !source.busy &&
        project.status == AcceleratorProjectStatus.active &&
        (ordered.isEmpty ||
            ordered.last.status == AcceleratorProjectStatus.paid);
    return Material(
      color: tokens.card2,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: tokens.panelHeaderHeight,
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: tokens.acceleratorCellPadding.start,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    context.l10n.acceleratorPhases,
                    style: tokens.bodyText.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: tokens.cardGap),
                  Text(
                    exact ? '${ids.length}' : context.l10n.acceleratorUnknown,
                    style: tokens.dataText.copyWith(
                      fontSize: 12,
                      color: tokens.dim,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    key: const Key('acc_create_phase'),
                    style: accCompactQuietStyle(context).copyWith(
                      minimumSize: WidgetStatePropertyAll<Size>(
                        Size(0, tokens.smallButtonHeight),
                      ),
                      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                      textStyle: WidgetStatePropertyAll<TextStyle>(
                        kTextButtonTextStyle.copyWith(fontSize: 12),
                      ),
                    ),
                    onPressed: canCreate && widget.onCreatePhase != null
                        ? () {
                            if (_can(source, epoch)) {
                              widget.onCreatePhase!(project);
                            }
                          }
                        : null,
                    child: Text(context.l10n.acceleratorCreatePhase),
                  ),
                ],
              ),
            ),
          ),
          if (!exact)
            Padding(
              padding: tokens.cardPadding,
              child: Text(
                context.l10n.acceleratorUnknown,
                style: tokens.compactText,
              ),
            )
          else if (ordered.isEmpty)
            EmptyNote.line(text: context.l10n.acceleratorNoneYet)
          else
            for (int index = 0; index < ordered.length; index++) ...<Widget>[
              Divider(height: 1, color: tokens.line),
              _buildPhase(
                context,
                source,
                project,
                ordered[index],
                index,
                epoch,
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildPhase(
    BuildContext context,
    AcceleratorProjectSnapshot source,
    Project project,
    Phase phase,
    int index,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final String id = phase.id.toString();
    final bool latest =
        project.phaseIds.isNotEmpty && project.phaseIds.last.toString() == id;
    return InkWell(
      key: ValueKey<String>('accelerator_phase_$id'),
      onTap: () {
        if (_can(source, epoch)) widget.presenter.select(id, source.authority);
      },
      hoverColor: tokens.hover,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: tokens.acceleratorPhaseMinHeight,
        ),
        child: Padding(
          padding: tokens.acceleratorCellPadding,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${index + 1} · ${phase.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.bodyText,
                    ),
                    if (phase.url.isNotEmpty)
                      Tooltip(
                        message: phase.url,
                        child: InkWell(
                          onTap: () {
                            if (_can(source, epoch)) {
                              widget.onOpenUrl?.call(phase.url);
                            }
                          },
                          child: Text(
                            '${context.l10n.acceleratorProof}: ${phase.url}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.compactText.copyWith(
                              color: tokens.dim,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: tokens.acceleratorPhaseBudgetWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    AmountText(
                      phase.znnFundsNeeded,
                      decimals: coinDecimals,
                      symbol: 'ZNN',
                      style: tokens.dataText,
                    ),
                    AmountText(
                      phase.qsrFundsNeeded,
                      decimals: coinDecimals,
                      symbol: 'QSR',
                      style: tokens.dataText.copyWith(color: tokens.dim),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.panelGap),
              SizedBox(
                width: tokens.acceleratorPhaseVotesWidth,
                child: AcceleratorVoteBar(
                  tally: AcceleratorListTally.from(phase.voteBreakdown, id),
                ),
              ),
              SizedBox(
                width: tokens.acceleratorPhaseStatusWidth,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AccStatusChip(phase.status),
                ),
              ),
              if (latest &&
                  source.owner &&
                  phase.status == AcceleratorProjectStatus.voting &&
                  widget.onUpdatePhase != null)
                IconButton(
                  tooltip: context.l10n.acceleratorUpdatePhase,
                  iconSize: 16,
                  onPressed: () {
                    if (_can(source, epoch) && !source.busy) {
                      widget.onUpdatePhase!(project, phase);
                    }
                  },
                  icon: Icon(Icons.edit_outlined, color: tokens.faint),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoteAside(
    BuildContext context,
    AcceleratorProjectSnapshot source,
    Project project,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorVoteTarget? target = source.target;
    Phase? phase;
    for (final Phase value in project.phases) {
      if (value.id.toString() == source.selectedId) phase = value;
    }
    final int phaseIndex = project.phaseIds.indexWhere(
      (Hash id) => id.toString() == source.selectedId,
    );
    final String selected = phaseIndex < 0
        ? context.l10n.acceleratorProject
        : context.l10n.acceleratorPhaseNumber(phaseIndex + 1);
    final AcceleratorProject item = phase ?? project;
    final AcceleratorListTally? tally = AcceleratorListTally.from(
      item.voteBreakdown,
      item.id.toString(),
    );
    final int? chosen = source.votesComplete
        ? source.votes[source.selectedId]
        : null;
    Future<void> vote(AcceleratorProjectVote value) async {
      if (!_can(source, epoch) || !source.canVote) return;
      final Future<AcceleratorActionOutcome> original = widget.presenter.vote(
        value,
        authority: source.authority,
        canContinue: () => _can(source, epoch),
      );
      await original;
    }

    Widget choice(AcceleratorProjectVote value, String label) => Semantics(
      key: Key('accelerator_detail_vote_${value.name}'),
      selected: chosen == value.index,
      child: value == AcceleratorProjectVote.yes
          ? PrimaryPill(
              onPressed: source.canVote ? () => vote(value) : null,
              child: Text(label),
            )
          : TextButton(
              style: value == AcceleratorProjectVote.no
                  ? secondaryButtonStyle(context)
                  : quietButtonStyle(context),
              onPressed: source.canVote ? () => vote(value) : null,
              child: Text(label),
            ),
    );
    Widget number(String label, String value) => Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.inlineGap / 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: tokens.compactText.copyWith(color: tokens.dim),
            ),
          ),
          SizedBox(width: tokens.inlineGap),
          Expanded(
            child: Text(
              value,
              style: tokens.dataText,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int? left =
        target != null &&
            !target.isPhase &&
            target.status == AcceleratorProjectStatus.voting
        ? target.creationTimestamp +
              AcceleratorVotePolicy.projectVotingSeconds -
              now
        : null;
    final AcceleratorActionOutcome? outcome = source.outcome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          source.pillarName == null
              ? context.l10n.acceleratorVoteUnavailable
              : context.l10n
                    .acceleratorVoteAs(source.pillarName!, selected)
                    .toUpperCase(),
          style: tokens.ledgerText,
        ),
        SizedBox(height: tokens.panelGap),
        Row(
          children: <Widget>[
            Expanded(
              child: choice(
                AcceleratorProjectVote.yes,
                context.l10n.acceleratorYes,
              ),
            ),
            SizedBox(width: tokens.inlineGap),
            Expanded(
              child: choice(
                AcceleratorProjectVote.no,
                context.l10n.acceleratorNo,
              ),
            ),
            SizedBox(width: tokens.inlineGap),
            choice(
              AcceleratorProjectVote.abstain,
              context.l10n.acceleratorAbstain,
            ),
          ],
        ),
        SizedBox(height: tokens.panelGap),
        Material(
          color: tokens.card2,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          child: Padding(
            padding: tokens.cardPadding,
            child: Column(
              children: <Widget>[
                number(
                  context.l10n.acceleratorYes,
                  tally?.yes.toString() ?? context.l10n.acceleratorUnknown,
                ),
                number(
                  context.l10n.acceleratorNo,
                  tally?.no.toString() ?? context.l10n.acceleratorUnknown,
                ),
                number(
                  context.l10n.acceleratorAbstain,
                  tally?.abstain.toString() ?? context.l10n.acceleratorUnknown,
                ),
                Divider(color: tokens.line),
                number(
                  context.l10n.acceleratorQuorum,
                  context.l10n.acceleratorUnknown,
                ),
                SizedBox(height: tokens.inlineGap),
                const AccMeter(parts: <(double, Color)>[]),
              ],
            ),
          ),
        ),
        SizedBox(height: tokens.panelGap),
        if (left != null && left >= 0)
          Text(
            context.l10n.acceleratorClosesIn(
              FormatUtils.formatDurationCoarse(
                context.l10n,
                Duration(seconds: left),
              ),
            ),
            style: tokens.compactText.copyWith(color: tokens.faint),
          ),
        if (outcome != null)
          Text(switch (outcome.state) {
            AcceleratorActionState.submitted =>
              context.l10n.acceleratorActionSubmitted,
            AcceleratorActionState.uncertain =>
              context.l10n.acceleratorActionUnknown,
            AcceleratorActionState.held => context.l10n.acceleratorActionHeld,
            AcceleratorActionState.refused =>
              context.l10n.acceleratorActionRefused,
          }, style: tokens.compactText.copyWith(color: tokens.dim)),
        for (final String hash in outcome?.hashes ?? <String>[])
          Tooltip(
            message: hash,
            child: Text(
              '${hash.substring(0, 7)}…${hash.substring(hash.length - 6)}',
              style: tokens.dataText.copyWith(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
