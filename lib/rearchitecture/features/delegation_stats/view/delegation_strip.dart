import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_panels.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Whether a known reward has anything for the existing Collect action.
bool hasNodesRewards(FetchState<UncollectedReward> state) =>
    state is FetchPopulated<UncollectedReward> &&
    (state.data.znnAmount > BigInt.zero || state.data.qsrAmount > BigInt.zero);

/// Exact node rewards, with one dollar estimate after the coin amounts.
///
/// An unknown reward is a skeleton, not zero. Both coins enter a total when
/// there is QSR, and inactive tabs unmount the price listener while keeping
/// their transaction scope and list state alive.
StripFigure nodesRewardsFigure(
  BuildContext context, {
  required FetchState<UncollectedReward> state,
  PriceFeed? priceFeed,
}) {
  final AppTokens tokens = AppTokens.of(context);
  final UncollectedReward? due = state is FetchPopulated<UncollectedReward>
      ? state.data
      : null;
  final bool hidden = BalanceVisibility.instance.hidden;
  final bool qsr = due != null && due.qsrAmount > BigInt.zero;
  final List<CoinAmount> parts = <CoinAmount>[
    if (due != null)
      (
        amount: due.znnAmount,
        decimals: kZnnCoin.decimals,
        coin: PricedCoin.znn,
      ),
    if (due != null && qsr)
      (
        amount: due.qsrAmount,
        decimals: kQsrCoin.decimals,
        coin: PricedCoin.qsr,
      ),
  ];
  return StripFigure(
    label: context.l10n.nodesToCollect,
    value: state is FetchFailure<UncollectedReward>
        ? Text(cardErrorText(state.exception), style: tokens.compactText)
        : due == null
        ? const Skeleton(width: 120)
        : ValueFlash(
            key: const ValueKey<String>('nodes_rewards_value'),
            value: (due.znnAmount, due.qsrAmount),
            child: HiddenAmount(
              child: Ltr(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AmountText(
                      due.znnAmount,
                      decimals: kZnnCoin.decimals,
                      symbol: kZnnCoin.symbol,
                      symbolColor: tokens.znnInk,
                      style: stripValueStyle(context),
                    ),
                    if (qsr) ...<Widget>[
                      Text(' · ', style: tokens.dollarText),
                      AmountText(
                        due.qsrAmount,
                        decimals: kQsrCoin.decimals,
                        symbol: kQsrCoin.symbol,
                        symbolColor: tokens.qsrInk,
                        style: stripValueStyle(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
    trailing: due != null && TickerMode.valuesOf(context).enabled
        ? DollarText.sum(
            parts,
            approx: qsr,
            hidden: hidden,
            feed: priceFeed,
          )
        : null,
  );
}

/// The selected address's delegation and rewards in one strip.
class DelegationStrip extends StatelessWidget {
  /// Creates the strip with access to the existing owner stepper.
  const DelegationStrip({
    required this.onStepperNotificationSeeMorePressed,
    this.onOpenOwner,
    this.provideCollectScope = true,
    super.key,
  });

  /// Opens the notification after a pillar owner action.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Opens the inline panel when the shared Nodes page owns it.
  final VoidCallback? onOpenOwner;

  /// False when the page already retains the single collection scope.
  final bool provideCollectScope;

  @override
  Widget build(BuildContext context) {
    final Widget view = _View(
      onStepperNotificationSeeMorePressed: onStepperNotificationSeeMorePressed,
      onOpenOwner: onOpenOwner,
    );
    return provideCollectScope ? PillarCollectScope(child: view) : view;
  }
}

enum _MoreAction { owner, undelegate }

class _View extends StatelessWidget {
  const _View({
    required this.onStepperNotificationSeeMorePressed,
    this.onOpenOwner,
  });

  final VoidCallback onStepperNotificationSeeMorePressed;
  final VoidCallback? onOpenOwner;

  Future<void> _openRewards(BuildContext context) => showNodesPanel(
    context: context,
    title: context.l10n.nodesRewards,
    body: BlocProvider<PillarRewardsHistoryBloc>.value(
      value: context.read<PillarRewardsHistoryBloc>(),
      child: const PillarRewardsChart(),
    ),
  );

  Future<void> _openMore(BuildContext context, {String? pillarName}) async {
    final _MoreAction? action = await showFrostedDialog<_MoreAction>(
      context: context,
      builder: (BuildContext dialogContext) => MultiBlocProvider(
        providers: <SingleChildWidget>[
          BlocProvider<DelegationBloc>.value(
            value: context.read<DelegationBloc>(),
          ),
          BlocProvider<UndelegateBloc>.value(
            value: context.read<UndelegateBloc>(),
          ),
        ],
        child: Builder(
          builder: (BuildContext menuContext) {
            final bool busy = watchNodesDelegationBusy(menuContext);
            return DialogCard(
              title: context.l10n.nodesMore,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton(
                    key: const Key('nodes_pillar_owner'),
                    style: quietButtonStyle(menuContext),
                    onPressed: () =>
                        Navigator.of(menuContext).pop(_MoreAction.owner),
                    child: Text(context.l10n.nodesYourPillar),
                  ),
                  if (pillarName != null)
                    TextButton(
                      key: const Key('nodes_undelegate'),
                      style: quietButtonStyle(menuContext),
                      onPressed: busy
                          ? null
                          : () => Navigator.of(
                              menuContext,
                            ).pop(_MoreAction.undelegate),
                      child: Text(context.l10n.nodesUndelegate),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _MoreAction.owner:
        if (onOpenOwner case final VoidCallback openOwner) {
          openOwner();
          return;
        }
        await showNodesPanel(
          context: context,
          title: context.l10n.nodesYourPillar,
          body: MultiBlocProvider(
            providers: <SingleChildWidget>[
              BlocProvider<PillarsBloc>.value(
                value: context.read<PillarsBloc>(),
              ),
              BlocProvider<PillarsByOwnerBloc>.value(
                value: context.read<PillarsByOwnerBloc>(),
              ),
              BlocProvider<SendTransactionBloc>.value(
                value: context.read<SendTransactionBloc>(),
              ),
            ],
            child: PillarStatsCard(
              onStepperNotificationSeeMorePressed:
                  onStepperNotificationSeeMorePressed,
            ),
          ),
        );
        if (context.mounted) {
          context.read<PillarsByOwnerBloc>().add(
            FetchRequestData(address: Address.parse(kSelectedAddress!)),
          );
          context.read<PillarsBloc>().add(const InfiniteListRefreshRequested());
        }
      case _MoreAction.undelegate:
        if (pillarName != null) {
          await requestNodesUndelegation(context, pillarName: pillarName);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool busy = watchNodesDelegationBusy(context);
    final FetchState<DelegationInfo> state = context
        .watch<DelegationStatsBloc>()
        .state;
    final UncollectedPillarRewardsBloc rewardsReader = context
        .watch<UncollectedPillarRewardsBloc>();
    final String? address = kSelectedAddress;
    final FetchState<UncollectedReward> rewards =
        address != null && rewardsReader.isCurrentFor(address)
        ? rewardsReader.state
        : const FetchInitial<UncollectedReward>();
    final DelegationInfo? delegation = state is FetchPopulated<DelegationInfo>
        ? state.data
        : null;
    final bool empty =
        state is FetchFailure<DelegationInfo> &&
        state.exception is NoDelegationStatsException;
    return ListenableBuilder(
      listenable: BalanceVisibility.instance,
      builder: (BuildContext context, Widget? child) => PageStrip(
        key: const Key('nodes_pillars_strip'),
        figures: <StripFigure>[
          StripFigure(
            label: context.l10n.nodesDelegatedTo,
            value: delegation != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(delegation.name, style: tokens.dataText),
                      SizedBox(width: tokens.inlineGap),
                      ValueFlash(
                        key: ValueKey<String>(delegation.name),
                        value: delegation.weight,
                        child: HiddenAmount(
                          child: Ltr(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text('· ', style: tokens.dollarText),
                                AmountText(
                                  delegation.weight,
                                  decimals: kZnnCoin.decimals,
                                  symbol: kZnnCoin.symbol,
                                  style: tokens.dollarText,
                                ),
                                Text(
                                  ' ${context.l10n.nodesWeight}',
                                  style: tokens.dollarText,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : state is FetchInitial<DelegationInfo>
                ? const Skeleton(width: 120)
                : empty
                ? Text(context.l10n.nodesNoneYet, style: tokens.compactText)
                : Text(
                    cardErrorText(
                      (state as FetchFailure<DelegationInfo>).exception,
                    ),
                    style: tokens.compactText,
                  ),
            trailing: TextButton(
              key: const Key('nodes_delegate'),
              style: nodesQuietButtonStyle(context),
              onPressed: busy ? null : () => showDelegationChooser(context),
              child: Text(
                delegation == null
                    ? context.l10n.nodesDelegate
                    : context.l10n.nodesChange,
              ),
            ),
          ),
          nodesRewardsFigure(context, state: rewards),
        ],
        actions: <Widget>[
          PillarCollectAction(enabled: hasNodesRewards(rewards)),
          TextButton.icon(
            key: const Key('nodes_pillar_rewards'),
            style: nodesQuietButtonStyle(context),
            onPressed: () => _openRewards(context),
            icon: const Icon(Icons.bar_chart_rounded, size: 16),
            label: Text(context.l10n.nodesRewards),
          ),
          IconButton(
            key: const Key('nodes_pillar_more'),
            tooltip: context.l10n.nodesMore,
            onPressed: () => _openMore(context, pillarName: delegation?.name),
            icon: const Icon(Icons.more_horiz, size: 18),
          ),
        ],
      ),
    );
  }
}
