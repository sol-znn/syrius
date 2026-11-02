import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/bloc/latest_transactions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/model/activity_entry.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/view/activity_row.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/infinite_list/infinite_list_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/models/card/card_type.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/skeleton.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Compact, selected-address history with exact source-bound movements.
class LatestTransactionsCard extends StatelessWidget {
  /// Retains both existing card types while drawing the Home activity shape.
  const LatestTransactionsCard({
    required this.type,
    this.address,
    this.chainId,
    this.zapPreviews = const <String, ActivityZapPreview>{},
    super.key,
  }) : assert(
         type == CardType.latestTransactions ||
             type == CardType.latestTransactionsDashboard,
         'Use a latest-transactions card type.',
       );

  /// The existing caller's history-card identity.
  final CardType type;

  /// The selected address that owns this presentation; legacy callers fall
  /// back to the current selected address. This does not own the RPC reader.
  final String? address;

  /// The source chain. Without a supplied chain no explorer link is enabled.
  final int? chainId;

  /// Isolated preview metadata attached to exact existing history hashes.
  /// An ordinary caller supplies none; this never creates a live Zap row.
  final Map<String, ActivityZapPreview> zapPreviews;

  @override
  Widget build(BuildContext context) {
    final String? owner = address ?? kSelectedAddress;
    final AppTokens tokens = AppTokens.of(context);
    return BlocBuilder<LatestTransactionsBloc, InfiniteListState<AccountBlock>>(
      builder: (BuildContext context, InfiniteListState<AccountBlock> state) {
        final Set<String> seen = <String>{};
        final List<ActivityEntry> entries = <ActivityEntry>[
          for (final AccountBlock block in state.data ?? <AccountBlock>[])
            if (owner != null &&
                block.address.toString() == owner &&
                (chainId == null || block.chainIdentifier == chainId) &&
                seen.add(block.hash.toString()))
              ActivityEntry.fromBlock(
                block,
                zapPreview: zapPreviews[block.hash.toString()],
              ),
        ];
        final String scope = '${chainId ?? 'unknown'}:$owner';
        return ClipRRect(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          child: ColoredBox(
            color: tokens.card,
            child: ListEntrance(
              key: ValueKey<String>('activity_scope:$scope'),
              itemKeys: <LocalKey>[
                for (final ActivityEntry entry in entries)
                  ValueKey<String>('$scope:${entry.hash}'),
              ],
              child: Column(
                key: const Key('home_activity'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Header(address: owner),
                  Expanded(
                    child: switch (state.status) {
                      InfiniteListStatus.initial => const _Loading(),
                      InfiniteListStatus.failure => Center(
                        child: Text(
                          context.l10n.activityUnavailable,
                          style: tokens.bodyText.copyWith(color: tokens.error),
                        ),
                      ),
                      InfiniteListStatus.success when entries.isEmpty =>
                        EmptyNote(text: context.l10n.noItemsFound),
                      InfiniteListStatus.success => _ActivityList(
                        key: ValueKey<String>(scope),
                        scope: scope,
                        address: owner,
                        chainId: chainId,
                        entries: entries,
                        readRevision: state.data,
                        hasReachedMax: state.hasReachedMax,
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.address});

  final String? address;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? label = kAddressLabelMap[address];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: tokens.activityHeaderHeight),
        child: Padding(
          padding: tokens.activityHeaderPadding,
          child: Row(
            children: <Widget>[
              Text(context.l10n.activityTitle, style: tokens.headingText),
              SizedBox(width: tokens.activityColumnGap),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Tooltip(
                    message: address ?? context.l10n.activitySelectedAddress,
                    child: Container(
                      key: const Key('activity_scope'),
                      padding: tokens.activityMessagePadding,
                      constraints: BoxConstraints(
                        minHeight: tokens.smallButtonHeight,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: tokens.line),
                        borderRadius: BorderRadius.circular(tokens.pillRadius),
                      ),
                      child: Text(
                        label ?? context.l10n.activitySelectedAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.captionText.copyWith(color: tokens.dim),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: tokens.cardPadding,
        child: SkeletonRows(gap: tokens.activityColumnGap),
      ),
    );
  }
}

class _ActivityList extends StatefulWidget {
  const _ActivityList({
    required this.scope,
    required this.address,
    required this.chainId,
    required this.entries,
    required this.readRevision,
    required this.hasReachedMax,
    super.key,
  });

  final String scope;
  final String? address;
  final int? chainId;
  final List<ActivityEntry> entries;
  final Object? readRevision;
  final bool hasReachedMax;

  @override
  State<_ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<_ActivityList> {
  final ScrollController _scroll = ScrollController();
  Timer? _clock;
  bool _requestedMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _checkViewport();
  }

  @override
  void didUpdateWidget(_ActivityList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.readRevision, widget.readRevision) ||
        oldWidget.hasReachedMax != widget.hasReachedMax) {
      _requestedMore = false;
      _checkViewport();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _checkViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _scroll.hasClients &&
          _scroll.position.maxScrollExtent == 0) {
        _requestMore();
      }
    });
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent * 0.9) {
      _requestMore();
    }
  }

  void _requestMore() {
    final String? owner = widget.address;
    if (_requestedMore || widget.hasReachedMax || owner == null) return;
    _requestedMore = true;
    context.read<LatestTransactionsBloc>().add(
      InfiniteListMoreRequested(address: Address.parse(owner)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return ListView.builder(
      key: const Key('activity_list'),
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: widget.entries.length + (widget.hasReachedMax ? 0 : 1),
      findChildIndexCallback: (Key key) {
        final int index = widget.entries.indexWhere(
          (ActivityEntry entry) =>
              key == ValueKey<String>('${widget.scope}:${entry.hash}'),
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (BuildContext context, int index) {
        if (index == widget.entries.length) return const _Loading();
        final ActivityEntry entry = widget.entries[index];
        final ValueKey<String> identity = ValueKey<String>(
          '${widget.scope}:${entry.hash}',
        );
        return ListEntranceItem(
          key: identity,
          child: ActivityRow(
            entry: entry,
            chainId: widget.chainId,
            now: now,
            addressLabels: kAddressLabelMap,
          ),
        );
      },
    );
  }
}
