import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/explorer_links.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The selected address's account chain: how many blocks it holds, of which
/// kinds, and its block hash.
class AccountChainStatsWidget extends StatefulWidget {
  /// Creates the chart over the selected account's existing statistics bloc.
  const AccountChainStatsWidget({
    required this.accountChainStatsBloc,
    super.key,
  });

  /// The source of the account's observed block counts and provenance.
  final AccountChainStatsBloc accountChainStatsBloc;

  @override
  State createState() {
    return _AccountChainStatsState();
  }
}

class _AccountChainStatsState extends State<AccountChainStatsWidget> {
  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Account chain',
      child: _buildStreamBuilder(),
    );
  }

  Widget _buildBody(AccountChainStats stats) {
    // An address that has never sent or received has nothing to chart.
    if (stats.blockCount == 0) {
      return const QuietNote('None yet');
    }
    final String hash = stats.firstHash.toString();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    NumberAnimation(
                      end: stats.blockCount,
                      isInt: true,
                      style: monoStyle(
                        Theme.of(context).textTheme.headlineSmall,
                      ).copyWith(fontSize: 22, fontWeight: FontWeight.w500),
                    ),
                    Text('BLOCKS', style: ledgerLabelStyle(context)),
                  ],
                ),
                // The chart is the one thing here that draws every frame
                // while it animates in.
                RepaintBoundary(child: _buildChart(stats)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildChartLegend(stats),
          const SizedBox(height: 8),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: <Widget>[
                Text('BLOCK HASH', style: ledgerLabelStyle(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Tooltip(
                    message: hash,
                    child: Text(
                      hash,
                      overflow: TextOverflow.ellipsis,
                      style: settingMonoStyle(context),
                    ),
                  ),
                ),
                CopyToClipboardButton(hash, iconSize: 16),
                StreamBuilder<void>(
                  stream: NodeChange.stream,
                  builder: (BuildContext context, _) => IconButton(
                    tooltip: 'Open in explorer',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const Icon(Icons.open_in_new, color: AppColors.faint),
                    onPressed:
                        ExplorerLinks.transaction(
                              hash,
                              chainId: stats.chainIdentifier == kNodeChainId
                                  ? kNodeChainId
                                  : null,
                            ) ==
                            null
                        ? null
                        : () {
                            final Uri? link = ExplorerLinks.transaction(
                              hash,
                              chainId: stats.chainIdentifier == kNodeChainId
                                  ? kNodeChainId
                                  : null,
                            );
                            if (link != null) {
                              unawaited(
                                NavigationUtils.openUrl(link.toString()),
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(AccountChainStats stats) {
    return SizedBox(
      width: 140,
      height: 140,
      child: StandardPieChart(
        sections: _getChartSections(stats),
      ),
    );
  }

  PieChartSectionData _getChartSection(
    AccountChainStats stats,
    BlockTypeEnum blockType,
  ) {
    final int blockTypeCount = stats.blockTypeNumOfBlocksMap[blockType]!;

    return PieChartSectionData(
      showTitle: false,
      radius: 7,
      color: kBlockTypeColorMap[blockType] ?? AppColors.errorColor,
      value: 100.0 * blockTypeCount / stats.blockCount,
    );
  }

  Widget _buildStreamBuilder() {
    return StreamBuilder<AccountChainStats?>(
      stream: widget.accountChainStatsBloc.stream,
      builder: (_, AsyncSnapshot<AccountChainStats?> snapshot) {
        if (snapshot.hasError) {
          // The bloc reports an address with no blocks as an error.
          final Object? error = snapshot.error;
          return error.toString() == 'Empty account-chain' ||
                  (error is StateError &&
                      error.message == 'Empty account-chain')
              ? const QuietNote('None yet')
              : QuietNote.error(snapshot.error!);
        }
        if (snapshot.hasData) return _buildBody(snapshot.data!);
        return const QuietNote.loading();
      },
    );
  }

  List<PieChartSectionData> _getChartSections(AccountChainStats stats) =>
      List<PieChartSectionData>.generate(
        BlockTypeEnum.values.length,
        (int index) => _getChartSection(
          stats,
          BlockTypeEnum.values.elementAt(index),
        ),
      );

  Widget _buildBlockTypeCountDetails(
    BlockTypeEnum blockType,
    int? blockTypeCount,
  ) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBlockTypeColorMap[blockType] ?? AppColors.errorColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              FormatUtils.extractNameFromEnum<BlockTypeEnum>(blockType),
              overflow: TextOverflow.ellipsis,
              style: settingHintStyle(context),
            ),
          ),
          Text(
            blockTypeCount.toString(),
            style: monoStyle(theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(AccountChainStats stats) {
    final List<BlockTypeEnum> typesWithBlocks = stats
        .blockTypeNumOfBlocksMap
        .keys
        .where((BlockTypeEnum key) => stats.blockTypeNumOfBlocksMap[key]! > 0)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final BlockTypeEnum type in typesWithBlocks)
          _buildBlockTypeCountDetails(
            type,
            stats.blockTypeNumOfBlocksMap[type],
          ),
      ],
    );
  }
}
