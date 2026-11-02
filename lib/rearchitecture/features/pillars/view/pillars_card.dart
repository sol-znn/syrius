import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars/model/pillar_list_data.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/reusable_widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'pillars_table.dart';

/// Loaded pillars, with their network weight and production.
///
/// The caller's existing delegation scope owns pending actions and results.
/// Without one, the list retains its original local action scope.
class PillarsCard extends StatelessWidget {
  /// Creates the list with an optional shared delegation scope.
  const PillarsCard({
    this.delegationBloc,
    this.delegationBlocked = false,
    this.heading,
    super.key,
  });

  /// A shared action bloc whose caller owns result handling and disposal.
  final DelegationBloc? delegationBloc;

  /// Another delegation or undelegation is pending in the shared scope.
  final bool delegationBlocked;

  /// A shared Nodes heading; null keeps the list's own title.
  final Widget? heading;

  @override
  Widget build(BuildContext context) {
    final DelegationBloc? shared = delegationBloc;
    final Widget view = _View(
      sharedDelegation: shared != null,
      delegationBlocked: delegationBlocked,
      heading: heading,
    );
    if (shared != null) {
      return BlocProvider<DelegationBloc>.value(value: shared, child: view);
    }
    return BlocProvider<DelegationBloc>(
      create: (_) => DelegationBloc(
        accountBlockUtils: AccountBlockUtils(),
        zenon: zenon!,
      ),
      child: view,
    );
  }
}

class _View extends StatefulWidget {
  const _View({
    required this.sharedDelegation,
    required this.delegationBlocked,
    required this.heading,
  });

  final bool sharedDelegation;
  final bool delegationBlocked;
  final Widget? heading;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final TextEditingController _search = TextEditingController();
  PillarListSort _sort = PillarListSort.weight;
  String? _delegatingTo;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    context.read<MultipleBalanceBloc>().add(
      MultipleBalanceFetch(
        addresses: kDefaultAddressList.map((String? item) => item!).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _loadMore() {
    final PillarsBloc reader = context.read<PillarsBloc>();
    if (_loadingMore ||
        reader.state.status != InfiniteListStatus.success ||
        reader.state.hasReachedMax) {
      return;
    }
    setState(() => _loadingMore = true);
    reader.add(const InfiniteListMoreRequested());
  }

  void _onDelegationStateChanged(BuildContext context, DelegationState state) {
    if (state is DelegationDone) {
      if (!widget.sharedDelegation) {
        context.read<DelegationStatsBloc>().add(
          FetchRequestData(address: Address.parse(kSelectedAddress!)),
        );
      }
    } else if (state is DelegationFailure) {
      if (!widget.sharedDelegation) {
        unawaited(
          NotificationUtils.sendNotificationError(
            state.exception,
            context.l10n.pillarDelegationError,
          ),
        );
      }
    } else {
      return;
    }
    setState(() => _delegatingTo = null);
  }

  void _delegate(PillarInfo item) {
    if (widget.delegationBlocked ||
        _delegatingTo != null ||
        context.read<DelegationBloc>().state is DelegationLoading) {
      return;
    }
    // A refreshed balance or delegation can invalidate a row that remains
    // painted until the next frame, so activation rechecks both facts.
    final BigInt balance =
        context
            .read<MultipleBalanceBloc>()
            .state
            .data?[kSelectedAddress]
            ?.znn() ??
        BigInt.zero;
    final FetchState<DelegationInfo> current = context
        .read<DelegationStatsBloc>()
        .state;
    if (balance < kMinDelegationAmount ||
        (current is FetchPopulated<DelegationInfo> &&
            current.data.name == item.name)) {
      return;
    }
    setState(() => _delegatingTo = item.name);
    context.read<DelegationBloc>().add(
      DelegationRequested(
        address: Address.parse(kSelectedAddress!),
        pillarName: item.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canDelegate = context.select<MultipleBalanceBloc, bool>(
      (MultipleBalanceBloc bloc) =>
          (bloc.state.data?[kSelectedAddress]?.znn() ?? BigInt.zero) >=
          kMinDelegationAmount,
    );
    final String? delegatedTo = context.select<DelegationStatsBloc, String?>((
      DelegationStatsBloc bloc,
    ) {
      final FetchState<DelegationInfo> state = bloc.state;
      return state is FetchPopulated<DelegationInfo> ? state.data.name : null;
    });
    final bool busy =
        widget.delegationBlocked ||
        _delegatingTo != null ||
        context.watch<DelegationBloc>().state is DelegationLoading;
    return BlocListener<DelegationBloc, DelegationState>(
      listener: _onDelegationStateChanged,
      child: BlocConsumer<PillarsBloc, InfiniteListState<PillarInfo>>(
        listener: (_, InfiniteListState<PillarInfo> state) {
          if (_loadingMore) setState(() => _loadingMore = false);
        },
        builder: (BuildContext context, InfiniteListState<PillarInfo> state) {
          final List<PillarInfo> source = state.data ?? const <PillarInfo>[];
          final List<PillarInfo> visible = selectLoadedPillars(
            source,
            query: _search.text,
            sort: _sort,
          );
          return Panel(
            title: context.l10n.pillars,
            heading: widget.heading,
            actions: <Widget>[
              _buildSearch(context),
              _buildSort(context),
              RefreshButton(
                onPressed: () => context.read<PillarsBloc>().add(
                  InfiniteListRefreshRequested(
                    address: Address.parse(kSelectedAddress!),
                  ),
                ),
              ),
            ],
            child: RowDetailGroup(
              // These scopes survive loading, errors and empty filters.
              // Source identities, rather than positions, own arrivals.
              child: ListEntrance(
                itemKeys: source.map(_pillarKey).toList(),
                child: switch (state.status) {
                  InfiniteListStatus.initial => const _Loading(),
                  InfiniteListStatus.failure => CardNote.error(state.error!),
                  InfiniteListStatus.success => _PillarsTable(
                    visible: visible,
                    filtered: _search.text.trim().isNotEmpty,
                    hasReachedMax: state.hasReachedMax,
                    loadingMore: _loadingMore,
                    canDelegate: canDelegate,
                    delegatedTo: delegatedTo,
                    busy: busy,
                    delegatingTo: _delegatingTo,
                    onLoadMore: _loadMore,
                    onDelegate: _delegate,
                  ),
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return SizedBox(
      width: tokens.pillarSearchWidth,
      height: tokens.pillarSearchHeight,
      child: TextField(
        key: const Key('pillars_search'),
        controller: _search,
        style: tokens.compactText,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: context.l10n.pillarsSearchLoaded,
          isDense: true,
          contentPadding: EdgeInsetsDirectional.symmetric(
            horizontal: tokens.inlineGap,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: tokens.settingsIconSize,
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: tokens.pillarSearchHeight,
          ),
          filled: true,
          fillColor: tokens.card2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            borderSide: BorderSide(color: tokens.line),
          ),
        ),
      ),
    );
  }

  Widget _buildSort(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return PopupMenuButton<PillarListSort>(
      key: const Key('pillars_sort'),
      tooltip: context.l10n.pillarsSortLoaded,
      initialValue: _sort,
      onSelected: (PillarListSort sort) => setState(() => _sort = sort),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<PillarListSort>>[
        CheckedPopupMenuItem<PillarListSort>(
          key: const Key('pillars_sort_weight'),
          value: PillarListSort.weight,
          checked: _sort == PillarListSort.weight,
          child: Text(context.l10n.weight),
        ),
        CheckedPopupMenuItem<PillarListSort>(
          key: const Key('pillars_sort_production'),
          value: PillarListSort.production,
          checked: _sort == PillarListSort.production,
          child: Text(context.l10n.pillarsSortProduction),
        ),
        PopupMenuItem<PillarListSort>(
          key: const Key('pillars_sort_apr'),
          enabled: false,
          child: SeamGate(
            seam: Seam.pillarAprEstimate,
            child: Text(context.l10n.pillarsAprEstimate),
          ),
        ),
      ],
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tokens.card2,
          shape: StadiumBorder(side: BorderSide(color: tokens.line)),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: tokens.cardGap,
            vertical: tokens.fieldLabelGap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.swap_vert_rounded, size: tokens.settingsIconSize),
              SizedBox(width: tokens.fieldLabelGap),
              Text(
                _sort == PillarListSort.weight
                    ? context.l10n.weight
                    : context.l10n.pillarsSortProduction,
                style: tokens.compactText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

LocalKey _pillarKey(PillarInfo item) => ValueKey<String>(item.name);

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: tokens.pillarCellPadding,
      child: SkeletonRows(gap: tokens.pageGap),
    );
  }
}
