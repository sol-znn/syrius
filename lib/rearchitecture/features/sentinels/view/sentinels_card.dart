import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/bloc/sentinels_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/view/sentinel_values.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/error_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_refresh.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Every active sentinel on the network, with its actual registration window.
///
/// Owner actions go to the existing workflow through caller-owned callbacks.
/// The active endpoint cannot supply revoked history, so no historical row is
/// invented or merged into this list from an ownership lookup.
class SentinelsCard extends StatelessWidget {
  /// Creates the list; an injected bloc remains owned by its caller.
  const SentinelsCard({
    this.bloc,
    this.selectedAddress,
    this.onSpawn,
    this.onOpenOwner,
    this.heading,
    super.key,
  });

  /// An already scoped reader, chiefly supplied by the Nodes integration.
  final SentinelsBloc? bloc;

  /// The captured address to mark, without inferring wallet ownership.
  final String? selectedAddress;

  /// Opens the existing registration workflow after current admission checks.
  final VoidCallback? onSpawn;

  /// Opens the selected owner's existing management and revoke workflow.
  final VoidCallback? onOpenOwner;

  /// The shared Nodes tabs, or the localized title when omitted.
  final Widget? heading;

  @override
  Widget build(BuildContext context) {
    final Widget view = _View(
      selectedAddress: selectedAddress ?? kSelectedAddress,
      onSpawn: onSpawn,
      onOpenOwner: onOpenOwner,
      heading: heading,
    );
    final SentinelsBloc? supplied = bloc;
    if (supplied != null) {
      return BlocProvider<SentinelsBloc>.value(value: supplied, child: view);
    }
    return BlocProvider<SentinelsBloc>(
      create: (_) =>
          SentinelsBloc(zenon: zenon!)..add(const InfiniteListRequested()),
      child: view,
    );
  }
}

class _View extends StatelessWidget {
  const _View({
    required this.selectedAddress,
    required this.onSpawn,
    required this.onOpenOwner,
    required this.heading,
  });

  final String? selectedAddress;
  final VoidCallback? onSpawn;
  final VoidCallback? onOpenOwner;
  final Widget? heading;

  void _refresh(BuildContext context) {
    context.read<SentinelsBloc>().add(const InfiniteListRefreshRequested());
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return PageRefreshAction(
      onRefresh: () => _refresh(context),
      child: BlocBuilder<SentinelsBloc, InfiniteListState<SentinelInfo>>(
        builder: (_, InfiniteListState<SentinelInfo> state) {
          // Pagination can overlap while network membership changes. Owner
          // identity remains unique, and this endpoint remains active-only.
          final List<SentinelInfo> sentinels = <String, SentinelInfo>{
            for (final SentinelInfo item in state.data ?? <SentinelInfo>[])
              if (item.active) item.owner.toString(): item,
          }.values.toList();
          return Panel(
            key: const Key('sentinels_list'),
            title: context.l10n.sentinels,
            heading: heading,
            actions: <Widget>[
              TextButton.icon(
                key: const Key('sentinels_spawn'),
                style: secondaryButtonStyle(context).copyWith(
                  visualDensity: VisualDensity.standard,
                  minimumSize: WidgetStatePropertyAll<Size>(
                    Size(0, tokens.pillarActionHeight),
                  ),
                  padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    EdgeInsetsDirectional.symmetric(horizontal: tokens.cardGap),
                  ),
                  textStyle: WidgetStatePropertyAll<TextStyle>(
                    tokens.compactText,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onSpawn,
                icon: Icon(Icons.add, size: tokens.settingsIconSize),
                label: Text(context.l10n.spawn),
              ),
            ],
            child: ListEntrance(
              key: ValueKey<String>('sentinels_$selectedAddress'),
              itemKeys: sentinels.map(_sentinelKey).toList(),
              child: StateSwitcher(
                child: switch (state.status) {
                  InfiniteListStatus.initial => const _Loading(
                    key: ValueKey<String>('loading'),
                  ),
                  InfiniteListStatus.failure => SyriusErrorWidget(
                    context.l10n.nodesUnavailable,
                    onRetry: () => _refresh(context),
                    key: const ValueKey<String>('failure'),
                  ),
                  InfiniteListStatus.success when sentinels.isEmpty =>
                    EmptyNote(
                      text: context.l10n.nodesNoneYet,
                      key: const ValueKey<String>('empty'),
                    ),
                  InfiniteListStatus.success => _Populated(
                    key: const ValueKey<String>('table'),
                    hasReachedMax: state.hasReachedMax,
                    sentinels: sentinels,
                    selectedAddress: selectedAddress,
                    onOpenOwner: onOpenOwner,
                    onRefresh: () => _refresh(context),
                  ),
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

LocalKey _sentinelKey(SentinelInfo item) =>
    ValueKey<String>(item.owner.toString());

/// The head is shared with InfiniteScrollTable. Rows fit the compact chip.
const double _kHeadHeight = 40;
const double _kSkeletonBar = 12;

/// The list while it loads: a bar where each of the first rows will be,
/// under the space the column names take, so the rows arrive where the bars
/// stood.
class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    final double rowHeight =
        AppTokens.of(context).pillarActionHeight +
        kInfiniteTableHorizontalPadding;
    // A short card shows fewer bars instead of overflowing.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        kInfiniteTableHorizontalPadding,
        _kHeadHeight + 1 + (rowHeight - _kSkeletonBar) / 2,
        kInfiniteTableHorizontalPadding,
        0,
      ),
      child: SkeletonRows(rows: 5, gap: rowHeight + 1 - _kSkeletonBar),
    );
  }
}

class _Populated extends StatelessWidget {
  const _Populated({
    required this.hasReachedMax,
    required this.sentinels,
    required this.selectedAddress,
    required this.onOpenOwner,
    required this.onRefresh,
    super.key,
  });

  final bool hasReachedMax;
  final List<SentinelInfo> sentinels;
  final String? selectedAddress;
  final VoidCallback? onOpenOwner;
  final VoidCallback onRefresh;

  static const int _ownerFlex = 5;
  static const int _registeredFlex = 3;
  static const int _revocableFlex = 3;
  static const int _statusFlex = 2;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // Tab goes through the rows' buttons, top to bottom, before it leaves
    // the card.
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: SizedBox.expand(
        key: const Key('sentinels_loaded'),
        child: InfiniteScrollTable<SentinelInfo>(
          // Keeps the scroll position when the page is left and shown again.
          key: const PageStorageKey<String>('sentinels_table'),
          itemKeyGenerator: _sentinelKey,
          rowBuilder: (SentinelInfo item, int index, Widget row) =>
              ListEntranceItem(key: _sentinelKey(item), child: row),
          items: sentinels,
          hasReachedMax: hasReachedMax,
          columns: _columns,
          heads: <InfiniteScrollTableColumnType, InfiniteScrollTableHead>{
            .sentinelAddress: InfiniteScrollTableHead(
              name: context.l10n.nodesOwner,
              flex: _ownerFlex,
            ),
            .date: InfiniteScrollTableHead(
              name: context.l10n.nodesRegistered,
              flex: _registeredFlex,
            ),
            .duration: InfiniteScrollTableHead(
              name: context.l10n.nodesRevocable,
              flex: _revocableFlex,
            ),
            .type: InfiniteScrollTableHead(
              name: context.l10n.nodesStatus,
              flex: _statusFlex,
              alignment: MainAxisAlignment.end,
            ),
          },
          generateRowCells: (SentinelInfo sentinelInfo) => _buildRowCells(
            sentinelInfo: sentinelInfo,
            tokens: tokens,
          ),
          onScrollReachedBottom: () {
            context.read<SentinelsBloc>().add(
              const InfiniteListMoreRequested(),
            );
          },
        ),
      ),
    );
  }

  List<InfiniteScrollTableCell> _buildRowCells({
    required SentinelInfo sentinelInfo,
    required AppTokens tokens,
  }) {
    final String owner = sentinelInfo.owner.toString();
    final bool own = owner == selectedAddress;
    final Widget identifier = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: SentinelOwnerText(
            address: owner,
            style: tokens.dataText.copyWith(
              fontSize: tokens.compactText.fontSize,
              color: tokens.dim,
            ),
          ),
        ),
        if (own) ...<Widget>[
          SizedBox(width: tokens.inlineGap),
          const SentinelStatusChip(active: true, yours: true),
        ],
      ],
    );

    return <InfiniteScrollTableCell>[
      InfiniteScrollTableCell(
        flex: _ownerFlex,
        child: own && onOpenOwner != null
            ? InkWell(
                key: const Key('sentinels_open_owner'),
                onTap: onOpenOwner,
                borderRadius: BorderRadius.circular(tokens.compactRadius),
                child: identifier,
              )
            : identifier,
      ),
      InfiniteScrollTableCell(
        flex: _registeredFlex,
        child: SentinelRegistrationTime(
          timestamp: sentinelInfo.registrationTimestamp,
        ),
      ),
      InfiniteScrollTableCell(
        flex: _revocableFlex,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SentinelRevocationTime(
            key: ValueKey<String>(owner),
            sentinel: sentinelInfo,
            onRefresh: onRefresh,
          ),
        ),
      ),
      InfiniteScrollTableCell(
        flex: _statusFlex,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SentinelStatusChip(active: sentinelInfo.active),
        ),
      ),
    ];
  }

  static const List<InfiniteScrollTableColumnType> _columns =
      <InfiniteScrollTableColumnType>[
        .sentinelAddress,
        .date,
        .duration,
        .type,
      ];
}
