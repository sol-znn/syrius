import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/skeleton.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/p2p_swaps_list_item.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';

enum _Filter { all, active, completed, reclaimable }

enum _Menu { recover, tutorial, clear }

/// One complete catalogue; filters never perform a second independent read.
class P2pSwapsCard extends StatefulWidget {
  /// Builds the table and local filters over the presenter's complete snapshot.
  const P2pSwapsCard({
    required this.presenter,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
    required this.onClear,
    required this.onRecover,
    required this.onTutorial,
    super.key,
  });

  /// Original catalogue owner, absent when complete history is unavailable.
  final SwapListPresenter? presenter;

  /// Requests a fresh complete capture through the enclosing owner.
  final VoidCallback onRefresh;

  /// Opens the exact rendered row in the original-wallet detail flow.
  final ValueChanged<SwapListRecord> onOpen;

  /// Requests confirmation before deleting one eligible historical row.
  final ValueChanged<SwapListRecord> onDelete;

  /// Requests confirmation before clearing eligible inactive history.
  final VoidCallback onClear;

  /// Opens the explicit exact-deposit recovery lookup.
  final VoidCallback onRecover;

  /// Opens the existing public swap tutorial link.
  final VoidCallback onTutorial;

  @override
  State<P2pSwapsCard> createState() => _P2pSwapsCardState();
}

class _P2pSwapsCardState extends State<P2pSwapsCard> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  _Filter _filter = _Filter.all;
  String? _opened;
  bool _choseInitial = false;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final SwapListPresenter? presenter = widget.presenter;
    final bool current = presenter?.isCurrent ?? false;
    final SwapListSnapshot? snapshot = current ? presenter?.snapshot : null;
    return Panel(
      key: const Key('p2p_swaps_list'),
      title: context.l10n.swapListTitle,
      heading: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(context.l10n.swapListTitle, style: tokens.headingText),
          SizedBox(width: tokens.inlineGap),
          Text(
            snapshot?.rows.length.toString() ?? context.l10n.swapListUnknown,
            style: tokens.captionText,
          ),
        ],
      ),
      actions: <Widget>[
        if (snapshot != null && snapshot.rows.length >= kMaxP2pSwapsToStore)
          Tooltip(
            message: context.l10n.swapListHistoryFullHint,
            child: Icon(
              Icons.info_outline,
              size: tokens.settingsIconSize,
              color: tokens.warn,
            ),
          ),
        PopupMenuButton<_Filter>(
          key: const Key('swap_filter'),
          tooltip: _label(context, _filter),
          onSelected: (_Filter filter) => setState(() {
            _filter = filter;
            _opened = null;
          }),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<_Filter>>[
            for (final _Filter filter in _Filter.values)
              PopupMenuItem<_Filter>(
                value: filter,
                child: Text(_label(context, filter)),
              ),
          ],
          child: Container(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: tokens.inlineGap,
              vertical: tokens.fieldLabelGap,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.line),
              borderRadius: BorderRadius.circular(tokens.pillRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_label(context, _filter), style: tokens.captionText),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: tokens.settingsIconSize,
                  color: tokens.faint,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const Key('swap_refresh'),
          tooltip: context.l10n.swapListRefresh,
          onPressed: presenter?.loading == true ? null : widget.onRefresh,
          icon: Icon(
            Icons.refresh,
            size: tokens.settingsIconSize,
            color: tokens.faint,
          ),
        ),
        PopupMenuButton<_Menu>(
          key: const Key('p2p_swaps_menu'),
          tooltip: context.l10n.swapListMore,
          icon: Icon(
            Icons.more_horiz,
            size: tokens.railIconSize,
            color: tokens.faint,
          ),
          onSelected: (_Menu value) {
            switch (value) {
              case _Menu.recover:
                widget.onRecover();
              case _Menu.tutorial:
                widget.onTutorial();
              case _Menu.clear:
                widget.onClear();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<_Menu>>[
            PopupMenuItem<_Menu>(
              value: _Menu.recover,
              enabled: current,
              child: Text(context.l10n.swapListRecover),
            ),
            PopupMenuItem<_Menu>(
              value: _Menu.tutorial,
              child: Text(context.l10n.swapListTutorial),
            ),
            PopupMenuItem<_Menu>(
              value: _Menu.clear,
              enabled:
                  current &&
                  presenter?.deleting != true &&
                  snapshot?.rows.any(
                        (SwapListRow row) => row.record.canDelete,
                      ) ==
                      true,
              child: Text(context.l10n.swapListClearHistory),
            ),
          ],
        ),
      ],
      child: ListEntrance(
        itemKeys:
            snapshot?.rows
                .map((SwapListRow row) => ValueKey<String>(row.record.id))
                .toList() ??
            const <LocalKey>[],
        child: presenter?.loading == true && snapshot == null
            ? Padding(
                padding: tokens.cardPadding,
                child: SkeletonRows(gap: tokens.cardGap),
              )
            : snapshot == null
            ? Center(
                child: Padding(
                  padding: tokens.cardPadding,
                  child: Text(
                    presenter == null || current
                        ? context.l10n.swapListUnavailable
                        : context.l10n.swapListSourceChanged,
                    style: tokens.compactText.copyWith(color: tokens.dim),
                  ),
                ),
              )
            : _buildTable(context, snapshot),
      ),
    );
  }

  Widget _buildTable(BuildContext context, SwapListSnapshot snapshot) {
    final AppTokens tokens = AppTokens.of(context);
    if (!_choseInitial && snapshot.rows.isNotEmpty) {
      _choseInitial = true;
      for (final SwapListRow row in snapshot.rows) {
        if (row.record.state == P2pSwapState.active ||
            row.record.state == P2pSwapState.pending) {
          _opened = row.record.id;
          break;
        }
      }
    }
    final List<SwapListRow> rows = snapshot.rows
        .where(
          (SwapListRow row) => switch (_filter) {
            _Filter.all => true,
            _Filter.active =>
              row.record.state == P2pSwapState.pending ||
                  row.record.state == P2pSwapState.active,
            _Filter.completed => row.record.state == P2pSwapState.completed,
            _Filter.reclaimable => row.record.state == P2pSwapState.reclaimable,
          },
        )
        .toList();
    if (rows.isEmpty) return EmptyNote(text: context.l10n.noItemsFound);
    final List<String> names = <String>[
      context.l10n.swapListStatus,
      context.l10n.swapListYouSend,
      context.l10n.swapListYouReceive,
      context.l10n.swapListCounterparty,
      context.l10n.swapListExpires,
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1, 3);
        final double width = constraints.maxWidth.clamp(
          tokens.swapTableMinWidth * scale,
          double.infinity,
        );
        return Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: <Widget>[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: tokens.swapHeaderHeight,
                    ),
                    child: Padding(
                      padding: tokens.swapCellPadding,
                      child: Row(
                        children: <Widget>[
                          for (int index = 0; index < names.length; index++)
                            Expanded(
                              flex: kP2pSwapColumnFlex[index],
                              child: Text(
                                usesLatinScript(context)
                                    ? names[index].toUpperCase()
                                    : names[index],
                                style: ledgerLabelStyle(context),
                              ),
                            ),
                          SizedBox(width: tokens.swapChevronWidth),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: tokens.line),
                  Expanded(
                    child: RowDetailGroup(
                      key: ValueKey<_Filter>(_filter),
                      initiallyOpen: _opened,
                      onChanged: (Object? value) => _opened = value as String?,
                      child: Scrollbar(
                        controller: _vertical,
                        child: ListView.separated(
                          controller: _vertical,
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: tokens.line),
                          itemBuilder: (BuildContext context, int index) {
                            final SwapListRow row = rows[index];
                            return ListEntranceItem(
                              key: ValueKey<String>(row.record.id),
                              child: P2pSwapsListItem(
                                row: row,
                                canAct:
                                    widget.presenter?.canOpen(row.record) ==
                                        true &&
                                    widget.presenter?.deleting != true,
                                onOpen: widget.onOpen,
                                onDelete: widget.onDelete,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _label(BuildContext context, _Filter value) => switch (value) {
    _Filter.all => context.l10n.swapListAll,
    _Filter.active => context.l10n.swapListActive,
    _Filter.completed => context.l10n.swapListCompleted,
    _Filter.reclaimable => context.l10n.swapListReclaimable,
  };
}
