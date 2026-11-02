import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart'
    show kStripLeadSize;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_list_item.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_stats.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// The fund strip and one project ledger, with presentation state retained.
class AcceleratorListView extends StatefulWidget {
  /// Presents a supplied source-bound model without constructing action owners.
  const AcceleratorListView({
    required this.presenter,
    required this.onStepperNotificationSeeMorePressed,
    required this.onRefresh,
    this.onDonate,
    this.onCreateProject,
    this.detailBuilder,
    this.showStrip = true,
    super.key,
  });

  /// Original list orchestration owner, retaining filter, search and ordering.
  final AcceleratorListPresenter presenter;

  /// Original notification-details navigation callback.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Explicit refresh callback, supplied by the original source owner.
  final VoidCallback onRefresh;

  /// Donation action receiving the exact snapshot that displayed its control.
  final ValueChanged<AcceleratorListSnapshot>? onDonate;

  /// Creation action receiving the exact snapshot that displayed its control.
  final ValueChanged<AcceleratorListSnapshot>? onCreateProject;

  /// Optional inert details builder for isolated presentation fixtures.
  final AcceleratorProjectDetailBuilder? detailBuilder;

  /// Whether to include the native-fund and current-project summary strip.
  final bool showStrip;

  @override
  State<AcceleratorListView> createState() => _AcceleratorListViewState();
}

class _AcceleratorListViewState extends State<AcceleratorListView> {
  late final TextEditingController _search = TextEditingController(
    text: widget.presenter.query,
  );
  final ScrollController _scroll = ScrollController();
  final ScrollController _horizontal = ScrollController();
  Timer? _clock;
  int _epoch = 0;
  AcceleratorListFilter? _lastFilter;
  String? _lastQuery;
  bool? _lastNewest;

  @override
  void initState() {
    super.initState();
    widget.presenter.addListener(_changed);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(AcceleratorListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presenter != widget.presenter) {
      oldWidget.presenter.removeListener(_changed);
      widget.presenter.addListener(_changed);
      _epoch++;
    }
  }

  void _changed() {
    if (!mounted) return;
    final AcceleratorListPresenter model = widget.presenter;
    final bool changed =
        _lastFilter != model.filter ||
        _lastQuery != model.query ||
        _lastNewest != model.newestFirst;
    _lastFilter = model.filter;
    _lastQuery = model.query;
    _lastNewest = model.newestFirst;
    if (changed && _scroll.hasClients) _scroll.jumpTo(0);
    if (_search.text != model.query) _search.text = model.query;
    setState(() => _epoch++);
  }

  bool _owns(AcceleratorListSnapshot source, int epoch) =>
      mounted &&
      epoch == _epoch &&
      source.isCurrent &&
      identical(source.binding, widget.presenter.snapshot.binding) &&
      identical(source.projects, widget.presenter.snapshot.projects);

  bool get _onPage =>
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  void _act(
    AcceleratorListSnapshot source,
    int epoch,
    ValueChanged<AcceleratorListSnapshot>? action,
  ) {
    if (_owns(source, epoch) && _onPage) action?.call(source);
  }

  @override
  void dispose() {
    _epoch++;
    _clock?.cancel();
    widget.presenter.removeListener(_changed);
    _search.dispose();
    _scroll.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorListSnapshot source = widget.presenter.snapshot;
    final int epoch = _epoch;
    final Widget ledger = _buildLedger(context, source, epoch);
    if (!widget.showStrip) return ledger;
    return PageGrid(
      rows: <PageRow>[
        PageRow.fixed(
          math.max(
            tokens.acceleratorStripHeight,
            kStripLeadSize + tokens.stripPadding.vertical,
          ),
          <PageCell>[
            PageCell(
              AcceleratorStats(
                snapshot: source,
                nowTimestamp: widget.presenter.nowTimestamp,
                onDonate: widget.onDonate == null
                    ? null
                    : () => _act(source, epoch, widget.onDonate),
                onCreateProject: widget.onCreateProject == null
                    ? null
                    : () => _act(source, epoch, widget.onCreateProject),
              ),
            ),
          ],
        ),
        PageRow.fill(<PageCell>[PageCell(ledger)]),
      ],
    );
  }

  Widget _buildLedger(
    BuildContext context,
    AcceleratorListSnapshot source,
    int epoch,
  ) {
    return Panel(
      key: const Key('accelerator_list'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildToolbar(context),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final AppTokens tokens = AppTokens.of(context);
                final double width = math.max(
                  constraints.maxWidth,
                  tokens.acceleratorTableMinWidth,
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
                          _buildHeader(context),
                          const Divider(height: 1),
                          Expanded(child: _buildRows(context, source, epoch)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final AcceleratorListPresenter model = widget.presenter;
    final Widget segment = Segment<AcceleratorListFilter>(
      keyPrefix: 'accelerator_filter',
      selected: model.filter,
      onChanged: model.select,
      items: <SegmentItem<AcceleratorListFilter>>[
        SegmentItem<AcceleratorListFilter>(
          value: AcceleratorListFilter.voting,
          label: context.l10n.acceleratorVoting,
        ),
        SegmentItem<AcceleratorListFilter>(
          value: AcceleratorListFilter.active,
          label: context.l10n.acceleratorActive,
        ),
        SegmentItem<AcceleratorListFilter>(
          value: AcceleratorListFilter.mine,
          label: context.l10n.acceleratorMine,
        ),
        SegmentItem<AcceleratorListFilter>(
          value: AcceleratorListFilter.all,
          label: context.l10n.acceleratorAll,
        ),
      ],
    );
    final Widget search = SizedBox(
      width: tokens.acceleratorSearchWidth,
      height: tokens.tokenSearchHeight,
      child: TextField(
        key: const Key('accelerator_search'),
        controller: _search,
        onChanged: model.search,
        style: tokens.compactText,
        decoration: InputDecoration(
          hintText: context.l10n.acceleratorSearch,
          hintStyle: tokens.compactText.copyWith(color: tokens.faint),
          prefixIcon: Icon(Icons.search, size: 16, color: tokens.faint),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: tokens.inlineGap),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            borderSide: BorderSide(color: tokens.line),
          ),
        ),
      ),
    );
    final Widget sort = TextButton.icon(
      key: const Key('accelerator_sort'),
      style: accToolbarButtonStyle(context),
      onPressed: model.toggleSort,
      icon: const Icon(Icons.swap_vert, size: 14),
      label: Text(
        model.newestFirst
            ? context.l10n.acceleratorNewest
            : context.l10n.acceleratorOldest,
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: tokens.acceleratorToolbarHeight),
      child: Padding(
        padding: tokens.panelHeaderPadding,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double labelSize = tokens.compactText.fontSize!;
            final double labelScale = math.max(
              1,
              MediaQuery.textScalerOf(context).scale(labelSize) / labelSize,
            );
            if (constraints.maxWidth <
                tokens.acceleratorSearchWidth * 3 * labelScale) {
              return Wrap(
                spacing: tokens.inlineGap,
                runSpacing: tokens.inlineGap,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[segment, search, sort],
              );
            }
            return Row(
              children: <Widget>[
                segment,
                const Spacer(),
                search,
                SizedBox(width: tokens.inlineGap),
                sort,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    Widget label(String value, {double? width, bool end = false}) => SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.acceleratorCellPadding.start,
        ),
        child: Text(
          value.toUpperCase(),
          textAlign: end ? TextAlign.end : null,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.ledgerText,
        ),
      ),
    );
    return SizedBox(
      height: tokens.acceleratorHeaderHeight,
      child: Row(
        children: <Widget>[
          Expanded(child: label(context.l10n.acceleratorProject)),
          label(
            context.l10n.acceleratorBudget,
            width: tokens.acceleratorBudgetWidth,
            end: true,
          ),
          label(
            context.l10n.acceleratorVotes,
            width: tokens.acceleratorVotesWidth,
          ),
          label(
            context.l10n.acceleratorQuorum,
            width: tokens.acceleratorQuorumWidth,
          ),
          label(
            context.l10n.acceleratorStatus,
            width: tokens.acceleratorStatusWidth,
          ),
          SizedBox(width: tokens.acceleratorChevronWidth),
        ],
      ),
    );
  }

  Widget _buildRows(
    BuildContext context,
    AcceleratorListSnapshot source,
    int epoch,
  ) {
    final List<AcceleratorListProject>? rows = widget.presenter.rows;
    if (rows == null) {
      if (source.projectsFailed && source.isCurrent) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.l10n.acceleratorReadFailed,
                style: AppTokens.of(context).compactText,
              ),
              TextButton.icon(
                key: const Key('accelerator_refresh'),
                style: quietButtonStyle(context),
                onPressed: () {
                  if (mounted && _onPage) widget.onRefresh();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(context.l10n.acceleratorRefresh),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: AppTokens.of(context).cardPadding,
        child: const SkeletonRows(rows: 4),
      );
    }
    if (rows.isEmpty) return EmptyNote(text: context.l10n.acceleratorNoneYet);
    return ListEntrance(
      itemKeys: <LocalKey>[
        for (final AcceleratorListProject row in rows) ValueKey<String>(row.id),
      ],
      child: ListView.separated(
        key: const Key('accelerator_rows'),
        controller: _scroll,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final AcceleratorListProject row = rows[index];
          return ListEntranceItem(
            key: ValueKey<String>(row.id),
            child: AcceleratorProjectListItem.presented(
              row: row,
              needsVote: source.needsVote(row, widget.presenter.nowTimestamp),
              nowTimestamp: widget.presenter.nowTimestamp,
              stillCurrent: () =>
                  mounted &&
                  source.isCurrent &&
                  identical(
                    source.binding,
                    widget.presenter.snapshot.binding,
                  ) &&
                  identical(
                    source.projects,
                    widget.presenter.snapshot.projects,
                  ) &&
                  (widget.presenter.rows?.contains(row) ?? false),
              detailBuilder: widget.detailBuilder,
              onStepperNotificationSeeMorePressed:
                  widget.onStepperNotificationSeeMorePressed,
            ),
          );
        },
      ),
    );
  }
}

/// Shared compact secondary action style for the Accelerator ledger toolbar.
ButtonStyle accToolbarButtonStyle(BuildContext context) =>
    secondaryButtonStyle(context).copyWith(
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(0, AppTokens.of(context).compactButtonHeight),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        AppTokens.of(context).compactText,
      ),
    );
