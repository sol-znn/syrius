import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// What the chart's open or closed state is stored under.
const String _kChartStoreKey = 'staking.chart';

/// The least height the list keeps when the form and the chart are both
/// open in a short window: its title row, the column names and two rows.
const double _kListLeast = 170;

/// Bounds automatic list reads; exhaustion cannot resolve an original hash.
const int _kStakeRowReadLimit = 6;

bool _isEmptyStakingPage(BuildContext context) {
  final InfiniteListState<StakeEntry> stakes = context
      .watch<StakesBloc>()
      .state;
  final StakingState total = context.watch<StakingCubit>().state;
  final FetchState<UncollectedReward> rewards = context
      .watch<UncollectedStakingRewardsBloc>()
      .state;
  final FetchState<RewardHistoryList> history = context
      .watch<StakingRewardsHistoryBloc>()
      .state;
  final bool noTotal =
      (total.status == TimerStatus.failure &&
          total.error is NoActiveStakingEntriesException) ||
      (total.status == TimerStatus.success &&
          total.data?.totalAmount == BigInt.zero);
  final bool noHistory =
      (history is FetchFailure<RewardHistoryList> &&
          history.exception is NoRewardsLastWeekException) ||
      (history is FetchPopulated<RewardHistoryList> &&
          history.data.list.every(
            (RewardHistoryEntry entry) => entry.qsrAmount == BigInt.zero,
          ));
  return noTotal &&
      stakes.status == InfiniteListStatus.success &&
      stakes.data!.isEmpty &&
      rewards is FetchPopulated<UncollectedReward> &&
      rewards.data.qsrAmount == BigInt.zero &&
      noHistory;
}

/// Staking: a strip of what the address has staked and can collect, then
/// its stakes. The new-stake form and the reward chart open under the
/// strip.
///
/// This widget owns the blocs; [StakingPage] is the page drawn from them.
class StakingTabChild extends StatelessWidget {
  /// Creates a staking tab child.
  const StakingTabChild({super.key});

  @override
  Widget build(BuildContext context) {
    // Every bloc below is bound to the address it was made for, so another
    // address is another page: without this the strip would go on showing
    // the first address's total.
    context.watch<SelectedAddressNotifier>();
    final String selected = kSelectedAddress!;
    return MultiBlocProvider(
      key: ValueKey<String>(selected),
      providers: <SingleChildWidget>[
        BlocProvider<StakesBloc>(
          create: (_) =>
              StakesBloc(zenon: zenon!)
                ..add(InfiniteListRequested(address: Address.parse(selected))),
        ),
        // The list is paged, so its rows do not add up to the total; the
        // node's own total comes with this cubit's answer.
        BlocProvider<StakingCubit>(
          create: (_) {
            final StakingCubit cubit = StakingCubit(
              address: Address.parse(selected),
              zenon: zenon!,
            );
            unawaited(cubit.fetchDataPeriodically());
            return cubit;
          },
        ),
      ],
      child: const StakeCollectScope(child: StakingPage()),
    );
  }
}

/// The Staking page, drawn from the blocs above it: [StakesBloc],
/// [StakingCubit], [UncollectedStakingRewardsBloc],
/// [StakingRewardsHistoryBloc], and the [SendTransactionBloc] the Collect
/// button sends through.
class StakingPage extends StatefulWidget {
  /// Creates the page.
  const StakingPage({this.priceFeed, super.key});

  /// The feed the dollar values read. The wallet's own when null; a test
  /// passes one that never touches the network.
  final PriceFeed? priceFeed;

  @override
  State<StakingPage> createState() => _StakingPageState();
}

class _StakingPageState extends State<StakingPage> {
  final DisclosureController _form = DisclosureController();
  final DisclosureController _chart = DisclosureController();
  final Set<String> _pendingStakeRows = <String>{};
  int _stakeRowReadsRemaining = 0;
  late final String? _stakeReadAddress;
  late final int _stakeReadChain;
  late final int _stakeReadRevision;
  late final StakesBloc _stakeReadBloc;
  bool _stakeReadRevoked = false;

  @override
  void initState() {
    super.initState();
    _stakeReadAddress = kSelectedAddress;
    _stakeReadChain = getChainIdentifier();
    _stakeReadRevision = WalletContextRevision.value;
    _stakeReadBloc = context.read<StakesBloc>();
  }

  bool get _stakeReadCurrent {
    if (_stakeReadRevoked) return false;
    final bool current = mounted && _stakeReadAddress != null &&
        _stakeReadAddress == kSelectedAddress &&
        _stakeReadChain == getChainIdentifier() &&
        _stakeReadRevision == WalletContextRevision.value &&
        identical(_stakeReadBloc, context.read<StakesBloc>());
    if (!current) {
      _stakeReadRevoked = true;
      _pendingStakeRows.clear();
      _stakeRowReadsRemaining = 0;
    }
    return current;
  }

  void _stakePublished(AccountBlockTemplate original) {
    if (!_stakeReadCurrent || original.hash == emptyHash ||
        original.address.toString() != _stakeReadAddress ||
        original.chainIdentifier != _stakeReadChain ||
        original.toAddress != stakeAddress ||
        original.tokenStandard != znnZts ||
        original.amount <= BigInt.zero) {
      return;
    }
    // Copy the accepted hash before a mutable SDK response can change it.
    if (_pendingStakeRows.add(original.hash.toString())) {
      _stakeRowReadsRemaining = _kStakeRowReadLimit;
    }
    _observeStakeRows(_stakeReadBloc.state);
  }

  void _observeStakeRows(InfiniteListState<StakeEntry> state) {
    if (!_stakeReadCurrent || state.status != InfiniteListStatus.success) {
      return;
    }
    _pendingStakeRows.removeAll(
      (state.data ?? const <StakeEntry>[])
          .map((StakeEntry entry) => entry.id.toString()),
    );
    if (_pendingStakeRows.isEmpty) _stakeRowReadsRemaining = 0;
  }

  void _refreshPendingStakeRows() {
    if (!_stakeReadCurrent || _pendingStakeRows.isEmpty ||
        _stakeRowReadsRemaining == 0) {
      return;
    }
    _stakeRowReadsRemaining--;
    _refreshStakes();
  }


  @override
  void dispose() {
    _stakeReadRevoked = true;
    _pendingStakeRows.clear();
    _stakeRowReadsRemaining = 0;
    _form.dispose();
    _chart.dispose();
    super.dispose();
  }

  void _refreshStakes() {
    context.read<StakesBloc>().add(
      InfiniteListRefreshRequested(address: Address.parse(kSelectedAddress!)),
    );
  }

  void _refreshRewards() {
    final Address address = Address.parse(kSelectedAddress!);
    context.read<StakingRewardsHistoryBloc>().add(
      FetchRequestData(address: address),
    );
    context.read<UncollectedStakingRewardsBloc>().add(
      FetchRequestData(address: address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double gap = AppTokens.of(context).pageGap;
    final bool empty = _isEmptyStakingPage(context);
    return MultiBlocListener(
      listeners: <SingleChildWidget>[
        BlocListener<StakesBloc, InfiniteListState<StakeEntry>>(
          // Retain the original list-to-total refresh direction.
          listenWhen: (
            InfiniteListState<StakeEntry> before,
            InfiniteListState<StakeEntry> after,
          ) => before.status != InfiniteListStatus.initial &&
              after.status == InfiniteListStatus.success &&
              before.data != after.data,
          listener: (BuildContext context, _) =>
              unawaited(context.read<StakingCubit>().fetchDataPeriodically()),
        ),
        BlocListener<StakesBloc, InfiniteListState<StakeEntry>>(
          listener: (_, InfiniteListState<StakeEntry> state) =>
              _observeStakeRows(state),
        ),
        BlocListener<NodeSyncStatusCubit, NodeSyncStatusState>(
          listenWhen: (
            NodeSyncStatusState before,
            NodeSyncStatusState after,
          ) => after.status == TimerStatus.success && after.data != null &&
              after.data!.second.currentHeight > 0 &&
              before.data?.second.currentHeight !=
                  after.data!.second.currentHeight,
          // Use the shell's existing height reads, without another timer,
          // subscription request, publication or confirmation shortcut.
          listener: (_, _) => _refreshPendingStakeRows(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Strip(form: _form, chart: _chart, priceFeed: widget.priceFeed),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // What opens under the strip scrolls before it takes
                    // the list's last rows.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.max(
                          0,
                          constraints.maxHeight - gap - _kListLeast,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            // Kept alive, so an amount half typed is still
                            // there when the form is opened again.
                            Disclosure.bare(
                              key: const Key('staking_form'),
                              controller: _form,
                              keepAlive: true,
                              child: Padding(
                                padding: EdgeInsetsDirectional.only(top: gap),
                                child: CreateStakeCard(
                                  framed: false,
                                  onStakePublished: _stakePublished,
                                  onStakeCreated: () {
                                    _form.close();
                                    _refreshStakes();
                                  },
                                ),
                              ),
                            ),
                            Disclosure.bare(
                              key: const Key('staking_chart'),
                              controller: _chart,
                              storeKey: _kChartStoreKey,
                              child: empty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: EdgeInsetsDirectional.only(
                                        top: gap,
                                      ),
                                      child: const StakingRewardsChart(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: gap),
                    Expanded(child: StakesCard(onRefresh: _refreshRewards)),
                    if (empty) ...<Widget>[
                      SizedBox(height: gap),
                      const _EmptyRewardsLine(
                        key: Key('staking_empty_rewards'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRewardsLine extends StatelessWidget {
  const _EmptyRewardsLine({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Panel(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.cardPadding.left,
          vertical: tokens.cardPadding.top,
        ),
        child: Row(
          children: <Widget>[
            const Opacity(
              opacity: 0.7,
              child: AppLottie(
                AppLottieAsset.noData,
                size: kEmptyNoteLineMarkSize,
                repeat: false,
              ),
            ),
            SizedBox(width: tokens.cardGap),
            Text(context.l10n.stakingChart, style: panelTitleStyle(context)),
            const Spacer(),
            Text(
              context.l10n.noItemsFound,
              style: tokens.compactText.copyWith(color: tokens.dim),
            ),
          ],
        ),
      ),
    );
  }
}

/// The strip: staked, to collect, the last seven days, and the page's
/// buttons.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.form,
    required this.chart,
    required this.priceFeed,
  });

  final DisclosureController form;
  final DisclosureController chart;
  final PriceFeed? priceFeed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool empty = _isEmptyStakingPage(context);
    final StakingState staking = context.watch<StakingCubit>().state;
    final FetchState<UncollectedReward> uncollected = context
        .watch<UncollectedStakingRewardsBloc>()
        .state;
    final FetchState<RewardHistoryList> history = context
        .watch<StakingRewardsHistoryBloc>()
        .state;

    // An address with no stake is a failure to the cubit; here it is zero.
    // Anything else that is not an answer leaves the figure blank: a zero
    // that is only "not known yet" would read as an empty address.
    final BigInt? staked = switch (staking.status) {
      TimerStatus.success => staking.data?.totalAmount,
      TimerStatus.failure
          when staking.error is NoActiveStakingEntriesException =>
        BigInt.zero,
      _ => null,
    };
    final BigInt? toCollect = uncollected is FetchPopulated<UncollectedReward>
        ? uncollected.data.qsrAmount
        : null;
    // The reward periods the chart draws, added up. Shown only when the
    // node has answered with some: a week without rewards has no figure,
    // as an empty page has none in the mockup.
    final BigInt? week = history is FetchPopulated<RewardHistoryList>
        ? history.data.list.fold<BigInt>(
            BigInt.zero,
            (BigInt sum, RewardHistoryEntry entry) => sum + entry.qsrAmount,
          )
        : null;

    // The dollar values hide with the amounts they stand beside.
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        BalanceVisibility.instance,
        form,
        chart,
      ]),
      builder: (BuildContext context, _) {
        final bool hidden = BalanceVisibility.instance.hidden;
        return PageStrip(
          key: const Key('staking_strip'),
          figures: <StripFigure>[
            StripFigure(
              label: context.l10n.stakingStaked,
              value: _StripAmount(
                staked,
                key: const Key('staking_staked_value'),
                symbol: kZnnCoin.symbol,
                ink: tokens.znnInk,
              ),
              trailing: staked == null || staked == BigInt.zero
                  ? null
                  : DollarText(
                      amount: staked,
                      decimals: kZnnCoin.decimals,
                      coin: PricedCoin.znn,
                      hidden: hidden,
                      feed: priceFeed,
                    ),
            ),
            StripFigure(
              label: context.l10n.stakingToCollect,
              value: _StripAmount(
                toCollect,
                key: const Key('staking_to_collect_value'),
                symbol: kQsrCoin.symbol,
                ink: tokens.qsrInk,
              ),
              trailing: toCollect == null || toCollect == BigInt.zero
                  ? null
                  : DollarText(
                      amount: toCollect,
                      decimals: kQsrCoin.decimals,
                      coin: PricedCoin.qsr,
                      hidden: hidden,
                      feed: priceFeed,
                    ),
            ),
            if (week != null && !empty)
              StripFigure(
                label: context.l10n.stakingLast7Days,
                value: _StripAmount(
                  week,
                  key: const Key('staking_week_value'),
                  symbol: kQsrCoin.symbol,
                  // Earned already, not to be had: quieter than the two
                  // amounts before it.
                  dim: true,
                ),
              ),
          ],
          actions: <Widget>[
            if (!empty)
              KeyedSubtree(
                key: const Key('staking_collect_button'),
                child: StakeCollectButton(
                  enabled: toCollect != null && toCollect > BigInt.zero,
                ),
              ),
            if (!empty)
              TextButton.icon(
                key: const Key('staking_chart_button'),
                style: TextButton.styleFrom(
                  foregroundColor: chart.isOpen
                      ? Theme.of(context).textTheme.bodyLarge?.color
                      : Theme.of(context).textTheme.titleMedium?.color,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 12,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: chart.toggle,
                icon: const Icon(Icons.bar_chart_rounded, size: 16),
                label: Text(context.l10n.stakingChart),
              ),
            // One place, two buttons: the page's main action while the
            // form is closed, and the way back out of it while it is open.
            KeyedSubtree(
              key: const Key('staking_stake_button'),
              child: form.isOpen
                  ? OutlinedButton.icon(
                      style: cardSecondaryButtonStyle(context).copyWith(
                        minimumSize: WidgetStatePropertyAll<Size>(
                          Size(0, tokens.buttonHeight),
                        ),
                        padding:
                            const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                              EdgeInsets.symmetric(horizontal: 16),
                            ),
                        textStyle: const WidgetStatePropertyAll<TextStyle>(
                          kOutlinedButtonTextStyle,
                        ),
                      ),
                      onPressed: form.close,
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(context.l10n.commonClose),
                    )
                  : PrimaryPill(
                      onPressed: form.open,
                      icon: const Icon(Icons.add, size: 18),
                      child: Text(context.l10n.stake),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// An amount in the strip: without trailing zeros, left to right, dots
/// while balances are hidden. Blank while [raw] is not known, at the height
/// of an amount, so the strip does not move when the answer comes.
class _StripAmount extends StatelessWidget {
  const _StripAmount(
    this.raw, {
    required this.symbol,
    this.ink,
    this.dim = false,
    super.key,
  });

  final BigInt? raw;
  final String symbol;

  /// The coin's colour, for its symbol.
  final Color? ink;

  /// Whether the amount is drawn in the theme's dim; a zero always is.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final BigInt? raw = this.raw;
    if (raw == null) return const Text('');
    final bool quiet = dim || raw == BigInt.zero;
    final Color? dimColor = Theme.of(context).textTheme.titleMedium?.color;
    return HiddenAmount(
      child: Ltr(
        child: AmountText(
          raw,
          decimals: coinDecimals,
          style: stripValueStyle(context).copyWith(
            color: quiet ? dimColor : null,
          ),
          symbol: symbol,
          symbolColor: quiet ? null : ink,
        ),
      ),
    );
  }
}
