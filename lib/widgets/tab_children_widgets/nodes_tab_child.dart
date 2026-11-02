import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_panels.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation_stats/view/delegation_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/pillar_owner_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/nodes/cubit/nodes_counts_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels_by_owner/view/sentinel_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_command.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The two views of the single Nodes destination.
enum NodesTab {
  /// Pillars and the selected address's delegation.
  pillars,

  /// Sentinels and the selected address's sentinel rewards.
  sentinels,
}

NodesTab _lastNodesTab = NodesTab.pillars;

/// Existing forms that the shell can open in the mounted Nodes scope.
enum NodesCommand {
  /// Opens the actual shared delegation chooser.
  delegate,
}

/// One rail destination for the two node lists.
///
/// A null [initialTab] resumes the choice made during this app session. An
/// explicit tab lets an old Sentinel link reach the same page directly.
class NodesTabChild extends StatelessWidget {
  /// Creates the Nodes destination.
  const NodesTabChild({
    required this.onStepperNotificationSeeMorePressed,
    this.initialTab,
    this.commands,
    super.key,
  });

  /// An explicit destination, or the last session choice when null.
  final NodesTab? initialTab;

  /// Optional shell routing into the page's existing action providers.
  final PageCommandController<NodesCommand>? commands;

  /// Opens the notification for an owner action's stepper.
  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) {
    context.watch<SelectedAddressNotifier>();
    final String selected = kSelectedAddress!;
    return BlocProvider<PillarsBloc>(
      // Fetches and owner actions are bound to this address. A change of
      // address must not retain the previous address's collection scope.
      key: ValueKey<Object>((
        selected,
        zenon,
        kCurrentNode,
        kNodeChainId,
        getChainIdentifier(),
        WalletContextRevision.value,
      )),
      create: (_) =>
          PillarsBloc(zenon: zenon!)..add(const InfiniteListRequested()),
      child: NodesDelegationScope(
        child: _bindCommands(
          _NodesOwnerContent(
            initialTab: initialTab,
            onStepperNotificationSeeMorePressed:
                onStepperNotificationSeeMorePressed,
          ),
        ),
      ),
    );
  }

  Widget _bindCommands(Widget child) {
    final PageCommandController<NodesCommand>? target = commands;
    return target == null
        ? child
        : PageCommandAction<NodesCommand>(
            controller: target,
            command: NodesCommand.delegate,
            onInvoke: (BuildContext context) =>
                unawaited(showDelegationChooser(context)),
            child: child,
          );
  }
}

class _NodesOwnerContent extends StatefulWidget {
  const _NodesOwnerContent({
    required this.onStepperNotificationSeeMorePressed,
    this.initialTab,
  });

  final VoidCallback onStepperNotificationSeeMorePressed;
  final NodesTab? initialTab;

  @override
  State<_NodesOwnerContent> createState() => _NodesOwnerContentState();
}

class _NodesOwnerContentState extends State<_NodesOwnerContent> {
  bool _ownerOpen = false;

  @override
  Widget build(BuildContext context) => BlocProvider<SentinelsByOwnerBloc>(
    create: (_) =>
        SentinelsByOwnerBloc(zenon: zenon!)
          ..add(FetchRequestData(address: Address.parse(kSelectedAddress!))),
    child: BlocProvider<NodesCountsCubit>(
      create: (_) {
        final WalletActionContext? original = WalletActionContext.capture(
          kSelectedAddress!,
        );
        final Zenon client = zenon!;
        final NodesCountsCubit reader = NodesCountsCubit(
          loadPillars: () async =>
              (await client.embedded.pillar.getAll(pageSize: 1)).count,
          loadSentinels: () async =>
              (await client.embedded.sentinel.getAllActive(pageSize: 1)).count,
          isCurrent: () => original?.isCurrent ?? false,
        );
        unawaited(reader.refresh());
        return reader;
      },
      child: Builder(
        builder: (BuildContext scoped) => PillarCollectScope(
          sender: scoped.read<SendTransactionBloc>(),
          child: BlocBuilder<NodesCountsCubit, NodesCounts>(
            builder: (_, NodesCounts counts) => NodesPage(
              initialTab: widget.initialTab,
              pillarCount: counts.pillars,
              sentinelCount: counts.sentinels,
              pillarsStrip: _ownerOpen
                  ? _PillarOwnerStrip(
                      onClose: () => setState(() => _ownerOpen = false),
                    )
                  : DelegationStrip(
                      provideCollectScope: false,
                      onOpenOwner: () => setState(() => _ownerOpen = true),
                      onStepperNotificationSeeMorePressed:
                          widget.onStepperNotificationSeeMorePressed,
                    ),
              pillarsPanel: _ownerOpen
                  ? PillarOwnerCard(
                      onClose: () => setState(() => _ownerOpen = false),
                      onStepperNotificationSeeMorePressed:
                          widget.onStepperNotificationSeeMorePressed,
                    )
                  : null,
              sentinelsStrip: _SentinelStrip(
                onStepperNotificationSeeMorePressed:
                    widget.onStepperNotificationSeeMorePressed,
              ),
              pillars: const NodesDelegationList(),
              sentinels: const SentinelsCard(),
              pillarsBuilder: (Widget tabs) =>
                  NodesDelegationList(heading: tabs),
              sentinelsBuilder: (Widget tabs) => SentinelsCard(
                heading: tabs,
                selectedAddress: kSelectedAddress,
                onSpawn: () => _showSentinelOwner(
                  scoped,
                  widget.onStepperNotificationSeeMorePressed,
                ),
                onOpenOwner: () => _showSentinelOwner(
                  scoped,
                  widget.onStepperNotificationSeeMorePressed,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PillarOwnerStrip extends StatelessWidget {
  const _PillarOwnerStrip({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final PillarsByOwnerBloc reader = context.watch<PillarsByOwnerBloc>();
    final String? address = kSelectedAddress;
    final FetchState<List<PillarInfo>> state = reader.state;
    final PillarInfo? own =
        address != null &&
            reader.isCurrentFor(address) &&
            state is FetchPopulated<List<PillarInfo>>
        ? state.data.firstOrNull
        : null;
    final UncollectedPillarRewardsBloc rewardsReader = context
        .watch<UncollectedPillarRewardsBloc>();
    final FetchState<UncollectedReward> rewards =
        address != null && rewardsReader.isCurrentFor(address)
        ? rewardsReader.state
        : const FetchInitial<UncollectedReward>();
    return PageStrip(
      key: const Key('nodes_pillar_owner_strip'),
      lead: own == null ? null : const NodeObject.pillar(size: kStripLeadSize),
      figures: <StripFigure>[
        StripFigure(
          label: context.l10n.nodesYourPillar,
          value: own != null
              ? Text(own.name, style: AppTokens.of(context).pillarOwnerNameText)
              : state is FetchPopulated<List<PillarInfo>> &&
                    state.data.isEmpty &&
                    address != null &&
                    reader.isCurrentFor(address)
              ? Text(context.l10n.nodesNoneYet)
              : const Skeleton(width: 120),
        ),
        nodesRewardsFigure(context, state: rewards),
      ],
      actions: <Widget>[
        PillarCollectAction(enabled: hasNodesRewards(rewards)),
        TextButton.icon(
          onPressed: onClose,
          icon: const Icon(Icons.close),
          label: Text(context.l10n.commonClose),
        ),
      ],
    );
  }
}

/// The Nodes layout with its data supplied by the caller.
///
/// A visited view stays mounted so its scroll, disclosure and transaction
/// state survive a tab change. An unvisited view is not fetched early, and
/// a hidden view cannot receive input or keep an animation running.
class NodesPage extends StatefulWidget {
  /// Creates the layout around the two strips and lists.
  const NodesPage({
    required this.pillarsStrip,
    required this.sentinelsStrip,
    required this.pillars,
    required this.sentinels,
    this.initialTab,
    this.pillarsPanel,
    this.pillarsBuilder,
    this.sentinelsBuilder,
    this.pillarCount,
    this.sentinelCount,
    super.key,
  });

  /// The initial destination, or the remembered choice when null.
  final NodesTab? initialTab;

  /// The selected address's delegation and pillar rewards.
  final Widget pillarsStrip;

  /// The selected address's sentinel and sentinel rewards.
  final Widget sentinelsStrip;

  /// The pillar list, retained after its first visit.
  final Widget pillars;

  /// The sentinel list, retained after its first visit.
  final Widget sentinels;

  /// The inline owner panel shares the list's address and publication scope.
  final Widget? pillarsPanel;

  /// Production list cards draw these common tabs inside their own heading.
  final Widget Function(Widget tabs)? pillarsBuilder;

  /// The Sentinel list has the same heading and keeps its own controls.
  final Widget Function(Widget tabs)? sentinelsBuilder;

  /// Reported network totals; unknown values stay absent.
  final int? pillarCount;

  /// Active sentinels only, as reported by the existing endpoint.
  final int? sentinelCount;

  /// Keeps widget tests independent of a previous test's tab choice.
  @visibleForTesting
  static void resetSessionSelection() => _lastNodesTab = NodesTab.pillars;

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage>
    with SingleTickerProviderStateMixin {
  late NodesTab _selected = widget.initialTab ?? _lastNodesTab;
  late final Set<NodesTab> _visited = <NodesTab>{_selected};
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    animationBehavior: AnimationBehavior.preserve,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _lastNodesTab = _selected;
  }

  @override
  void didUpdateWidget(NodesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final NodesTab? requested = widget.initialTab;
    if (requested != null && requested != oldWidget.initialTab) {
      _select(requested);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _select(NodesTab tab) {
    if (tab == _selected) return;
    setState(() {
      _selected = tab;
      _lastNodesTab = tab;
      _visited.add(tab);
    });
    _fade.forward(from: 0);
  }

  Widget _buildKeptView(NodesTab tab, Widget child) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    final bool active = tab == _selected;
    return TickerMode(
      enabled: active,
      child: ExcludeFocus(
        excluding: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: IgnorePointer(ignoring: !active, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Animation<double> opacity = _fade.drive(
      CurveTween(curve: tokens.ease),
    );
    final bool embeddedTabs =
        widget.pillarsBuilder != null && widget.sentinelsBuilder != null;
    Widget tabs() => Segment<NodesTab>(
      key: const Key('nodes_segment'),
      keyPrefix: 'nodes_tab',
      appearance: SegmentAppearance.heading,
      selected: _selected,
      onChanged: _select,
      items: <SegmentItem<NodesTab>>[
        SegmentItem<NodesTab>(
          value: NodesTab.pillars,
          label: context.l10n.pillars,
          count: widget.pillarCount,
        ),
        SegmentItem<NodesTab>(
          value: NodesTab.sentinels,
          label: context.l10n.sentinels,
          count: widget.sentinelCount,
        ),
      ],
    );
    return FocusTraversalGroup(
      child: Column(
        key: const Key('nodes_page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FadeTransition(
            opacity: opacity,
            child: IndexedStack(
              index: _selected.index,
              children: <Widget>[
                _buildKeptView(NodesTab.pillars, widget.pillarsStrip),
                _buildKeptView(NodesTab.sentinels, widget.sentinelsStrip),
              ],
            ),
          ),
          SizedBox(height: tokens.pageGap),
          if (widget.pillarsPanel case final Widget panel) ...<Widget>[
            Offstage(
              offstage: _selected != NodesTab.pillars,
              child: _buildKeptView(NodesTab.pillars, panel),
            ),
            if (_selected == NodesTab.pillars) SizedBox(height: tokens.pageGap),
          ],
          if (!embeddedTabs) ...<Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: tabs(),
            ),
            SizedBox(height: tokens.pageGap),
          ],
          Expanded(
            child: FadeTransition(
              opacity: opacity,
              child: IndexedStack(
                index: _selected.index,
                sizing: StackFit.expand,
                children: <Widget>[
                  _buildKeptView(
                    NodesTab.pillars,
                    widget.pillarsBuilder?.call(tabs()) ?? widget.pillars,
                  ),
                  _buildKeptView(
                    NodesTab.sentinels,
                    widget.sentinelsBuilder?.call(tabs()) ?? widget.sentinels,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SentinelStrip extends StatelessWidget {
  const _SentinelStrip({
    required this.onStepperNotificationSeeMorePressed,
  });

  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) {
    return SentinelCollectScope(
      sender: context.read<SendTransactionBloc>(),
      child: _SentinelStripView(
        onStepperNotificationSeeMorePressed:
            onStepperNotificationSeeMorePressed,
      ),
    );
  }
}

class _SentinelStripView extends StatelessWidget {
  const _SentinelStripView({
    required this.onStepperNotificationSeeMorePressed,
  });

  final VoidCallback onStepperNotificationSeeMorePressed;

  Future<void> _openOwner(BuildContext context) =>
      _showSentinelOwner(context, onStepperNotificationSeeMorePressed);

  Future<void> _openRewards(BuildContext context) => showNodesPanel(
    context: context,
    title: context.l10n.nodesRewards,
    body: BlocProvider<SentinelRewardsHistoryBloc>.value(
      value: context.read<SentinelRewardsHistoryBloc>(),
      child: const SentinelRewardsChart(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final SentinelsByOwnerBloc ownerReader = context
        .watch<SentinelsByOwnerBloc>();
    final UncollectedSentinelRewardsBloc rewardsReader = context
        .watch<UncollectedSentinelRewardsBloc>();
    final String address = kSelectedAddress!;
    final FetchState<List<SentinelInfo>> own = ownerReader.isCurrentFor(address)
        ? ownerReader.state
        : const FetchInitial<List<SentinelInfo>>();
    final FetchState<UncollectedReward> rewards =
        rewardsReader.isCurrentFor(address)
        ? rewardsReader.state
        : const FetchInitial<UncollectedReward>();
    return ListenableBuilder(
      listenable: BalanceVisibility.instance,
      builder: (BuildContext context, Widget? child) {
        final StripFigure reward = nodesRewardsFigure(context, state: rewards);
        return SentinelStrip(
          selectedAddress: address,
          ownerState: own,
          rewards: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: reward.value),
              if (reward.trailing case final Widget dollars) ...<Widget>[
                SizedBox(width: AppTokens.of(context).inlineGap),
                Flexible(child: dollars),
              ],
            ],
          ),
          collectAction: SentinelCollectAction(
            enabled: hasNodesRewards(rewards),
          ),
          onOpenOwner: () => _openOwner(context),
          onOpenRewards: () => _openRewards(context),
          onRefreshOwner: () => ownerReader.add(
            FetchRequestData(address: Address.parse(address)),
          ),
        );
      },
    );
  }
}

Future<void> _showSentinelOwner(
  BuildContext context,
  VoidCallback onStepper,
) async {
  if (!context.mounted || !TickerMode.valuesOf(context).enabled) return;
  final String? address = kSelectedAddress;
  if (address == null) return;
  final WalletActionContext? session = WalletActionContext.capture(address);
  if (session == null) return;
  final SentinelsByOwnerBloc reader = context.read<SentinelsByOwnerBloc>();
  final SendTransactionBloc sender = context.read<SendTransactionBloc>();
  await showNodesPanel(
    context: context,
    title: context.l10n.nodesYourSentinel,
    body: SentinelStatsCard(
      ownerReader: reader,
      sender: sender,
      onStepperNotificationSeeMorePressed: onStepper,
    ),
  );
  if (context.mounted && session.isCurrent && !reader.isClosed) {
    reader.add(FetchRequestData(address: Address.parse(address)));
  }
}
