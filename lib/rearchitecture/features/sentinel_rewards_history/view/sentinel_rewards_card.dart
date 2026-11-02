import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The sentinel rewards of the selected address: what it can collect now,
/// with the Collect button, over the chart of what it earned.
///
/// The amounts to collect used to be a card of their own beside this one.
class SentinelRewardsCard extends StatelessWidget {
  /// Constructs a new instance.
  const SentinelRewardsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const SentinelCollectScope(child: _View());
  }
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Rewards',
      actions: <Widget>[
        RefreshButton(
          onPressed: () {
            final Address address = Address.parse(kSelectedAddress!);
            context.read<SentinelRewardsHistoryBloc>().add(
              FetchRequestData(address: address),
            );
            context.read<UncollectedSentinelRewardsBloc>().add(
              FetchRequestData(address: address),
            );
          },
        ),
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SentinelCollect(),
          Divider(),
          Expanded(child: SentinelRewardsChart()),
        ],
      ),
    );
  }
}

/// The existing history states without a collection scope or action.
///
/// The strip stays the only sender while its history is open, so a pending
/// collection cannot be repeated through a second rewards card.
class SentinelRewardsChart extends StatelessWidget {
  /// Creates the chart under a [SentinelRewardsHistoryBloc].
  const SentinelRewardsChart({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SentinelRewardsHistoryBloc, FetchState<RewardHistoryList>>(
        builder: (_, FetchState<RewardHistoryList> state) => StateSwitcher(
          child: switch (state) {
            FetchFailure<RewardHistoryList>() => CardNote.error(
              state.exception,
              key: ValueKey<String>(
                state.exception is NoRewardsLastWeekException
                    ? 'empty'
                    : 'failure',
              ),
            ),
            FetchInitial<RewardHistoryList>() => const _ChartLoading(
              key: ValueKey<String>('loading'),
            ),
            FetchPopulated<RewardHistoryList>() => _Chart(
              key: const ValueKey<String>('chart'),
              rewardsHistoryList: state.data,
            ),
          },
        ),
      );
}

/// The chart while it loads: bars down the space it will fill.
class _ChartLoading extends StatelessWidget {
  const _ChartLoading({super.key});

  @override
  Widget build(BuildContext context) {
    // A short card shows fewer bars instead of overflowing.
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: kCardBodyPadding,
      child: SkeletonRows(rows: 5, gap: 26),
    );
  }
}

/// A [StandardChart] adapted to show the sentinel rewards.
class _Chart extends StatelessWidget {
  /// Constructs a new instance.
  const _Chart({
    required this._rewardsHistoryList,
    super.key,
  });

  final RewardHistoryList _rewardsHistoryList;

  @override
  Widget build(BuildContext context) {
    return StandardChart(
      maxY: _getMaxValueOfRewards() < 1.0
          ? _getMaxValueOfRewards().toDouble()
          : _getMaxValueOfRewards().ceilToDouble(),
      lineBarsData: _linesBarData(),
      titlesReferenceDate:
          DateTime.fromMillisecondsSinceEpoch(genesisTimestamp * 1000).add(
            Duration(
              // First epoch is zero
              days: _rewardsHistoryList.list.reversed.last.epoch + 1,
            ),
          ),
    );
  }

  List<FlSpot> _getZnnRewardsSpots() => List<FlSpot>.generate(
    _rewardsHistoryList.list.length,
    (int index) => FlSpot(
      index.toDouble(),
      _getRewardsByIndex(index, kZnnCoin.tokenStandard).toDouble(),
    ),
  );

  List<FlSpot> _getQsrRewardsSpots() => List<FlSpot>.generate(
    _rewardsHistoryList.list.length,
    (int index) => FlSpot(
      index.toDouble(),
      _getRewardsByIndex(index, kQsrCoin.tokenStandard).toDouble(),
    ),
  );

  List<LineChartBarData> _linesBarData() => <LineChartBarData>[
    StandardLineChartBarData(
      color: AppColors.znnColor,
      spots: _getZnnRewardsSpots(),
    ),
    StandardLineChartBarData(
      color: AppColors.qsrColor,
      spots: _getQsrRewardsSpots(),
    ),
  ];

  num _getRewardsByIndex(int index, TokenStandard tokenId) {
    final RewardHistoryEntry entry = _rewardsHistoryList.list.reversed
        .toList()[index];
    return tokenId == kZnnCoin.tokenStandard
        ? entry.znnAmount.addDecimals(coinDecimals).toNum()
        : entry.qsrAmount.addDecimals(coinDecimals).toNum();
  }

  num _getMaxValueOfRewards() {
    final num maxZnn = _getMaxValueOfZnnRewards()
        .addDecimals(
          coinDecimals,
        )
        .toNum();
    final num maxQsr = _getMaxValueOfQsrRewards()
        .addDecimals(
          coinDecimals,
        )
        .toNum();
    return max(maxQsr, maxZnn);
  }

  BigInt _getMaxValueOfZnnRewards() {
    BigInt max = _rewardsHistoryList.list.first.znnAmount;
    for (final RewardHistoryEntry element in _rewardsHistoryList.list) {
      if (element.znnAmount > max) {
        max = element.znnAmount;
      }
    }
    return max;
  }

  BigInt _getMaxValueOfQsrRewards() {
    BigInt max = _rewardsHistoryList.list.first.qsrAmount;
    for (final RewardHistoryEntry element in _rewardsHistoryList.list) {
      if (element.qsrAmount > max) {
        max = element.qsrAmount;
      }
    }
    return max;
  }
}
