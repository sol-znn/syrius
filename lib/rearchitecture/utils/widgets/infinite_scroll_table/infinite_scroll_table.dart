import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/constants/app_sizes.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'infinite_scroll_table_column_type.dart';

part 'infinite_scroll_table_cell.dart';

part 'infinite_scroll_table_column.dart';

/// A table for displaying a large set of items
///
/// It should receive an [onScrollReachedBottom] callback that is triggered
/// when the user scrolls to the bottom of the list. The callback should load
/// the next batch of items.
///
/// There is the case that the first batch can fit inside the view port of the
/// widget, without any need of scrolling. These scenario will block the
/// automatic loading of the next batches, because the [ScrollController]
/// listener won't be triggered. The [onScrollReachedBottom] callback is called
/// after the widget has finished rendering in order to immediately fetch more
/// items, if possible, so that the scroll actives
class InfiniteScrollTable<T> extends StatefulWidget {
  /// Creates a new instance.
  const InfiniteScrollTable({
    required this.items,
    required this.hasReachedMax,
    required this.generateRowCells,
    required this.onScrollReachedBottom,
    required this.columns,
    this.heads =
        const <InfiniteScrollTableColumnType, InfiniteScrollTableHead>{},
    this.itemKeyGenerator,
    this.onItemTap,
    this.rowBuilder,
    super.key,
  });

  /// The columns that will the organized in an fixed header
  final List<InfiniteScrollTableColumnType> columns;

  /// The columns whose head this table names or sizes itself. A column with
  /// no entry keeps its type's name and flex, which is every column by
  /// default.
  final Map<InfiniteScrollTableColumnType, InfiniteScrollTableHead> heads;

  /// Function that takes in an item and returns the cells consisting the row
  final List<Widget> Function(T) generateRowCells;

  /// Callback to be executed when the bottom of the table was reached.
  final VoidCallback onScrollReachedBottom;

  /// List of items that constitutes the rows.
  final List<T> items;

  /// Whether there are still items that can be fetched.
  final bool hasReachedMax;

  /// Generates a stable key for an item row.
  final Key Function(T)? itemKeyGenerator;

  /// Callback to be executed when an item is tapped
  final void Function(int)? onItemTap;

  /// Wraps the complete hover and input row, for a view's keyed entrance.
  /// The table retains the item's key on the outermost subtree so lazy
  /// row identity does not depend on the wrapper a caller supplies.
  final Widget Function(T item, int index, Widget row)? rowBuilder;

  @override
  State createState() => _InfiniteScrollTableState<T>();
}

class _InfiniteScrollTableState<T> extends State<InfiniteScrollTable<T>> {
  final ScrollController _scrollController = ScrollController();
  bool _isRequestingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _requestMoreIfViewportIsNotFilled();
  }

  @override
  void didUpdateWidget(covariant InfiniteScrollTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.hasReachedMax != widget.hasReachedMax) {
      _isRequestingMore = false;
      _requestMoreIfViewportIsNotFilled();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return SyriusErrorWidget(context.l10n.noItemsFound);
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: <Widget>[
        PinnedHeaderSliver(
          child: _Header(columns: widget.columns, heads: widget.heads),
        ),
        SliverList.separated(
          separatorBuilder: (_, _) => const Divider(
            thickness: 0.75,
          ),
          itemCount: widget.items.length + 1,
          itemBuilder: (BuildContext context, int index) {
            final Widget lastChild = widget.hasReachedMax
                ? SyriusErrorWidget(context.l10n.noMoreItems)
                : const SyriusLoadingWidget();

            return index == widget.items.length
                ? lastChild
                : _getTableRow(
                    widget.items[index],
                    index,
                  );
          },
        ),
      ],
    );
  }

  void _onScroll() {
    if (_isBottom) {
      _requestMore();
    }
  }

  void _requestMore() {
    if (_isRequestingMore || widget.hasReachedMax) return;

    _isRequestingMore = true;
    try {
      widget.onScrollReachedBottom();
    } on Object {
      _isRequestingMore = false;
      rethrow;
    }
  }

  void _requestMoreIfViewportIsNotFilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      if (_scrollController.position.maxScrollExtent == 0) {
        _requestMore();
      }
    });
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  Widget _getTableRow(T item, int indexOfRow) {
    final Key? key = widget.itemKeyGenerator?.call(item);

    final Widget child = DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 13),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kInfiniteTableHorizontalPadding,
          vertical: kInfiniteTableHorizontalPadding / 2,
        ),
        child: Row(
          children: widget.generateRowCells(item),
        ),
      ),
    );

    final Widget row = _RowHover(
      key: widget.rowBuilder == null ? key : null,
      child: widget.onItemTap == null
          ? child
          : InkWell(
              mouseCursor: SystemMouseCursors.click,
              // The row owns its hover tint, so a second ink stays clear.
              hoverColor: Colors.transparent,
              onTap: () => widget.onItemTap!(indexOfRow),
              child: child,
            ),
    );
    final Widget Function(T item, int index, Widget row)? rowBuilder =
        widget.rowBuilder;
    return rowBuilder == null
        ? row
        : KeyedSubtree(key: key, child: rowBuilder(item, indexOfRow, row));
  }
}

/// A row as a surface: tinted under the pointer, so a wide row can be read
/// across without losing the line.
///
/// It only watches the pointer. It takes no tap and no focus and leaves the
/// cursor alone, so a row with nothing to click does not claim to have it.
class _RowHover extends StatefulWidget {
  const _RowHover({required this.child, super.key});

  final Widget child;

  @override
  State<_RowHover> createState() => _RowHoverState();
}

class _RowHoverState extends State<_RowHover> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered != value) {
      setState(() => _hovered = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color tint = AppTokens.of(context).hover;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _hovered ? tint : tint.withValues(alpha: 0)),
        duration: Durations.short3,
        curve: Easing.standard,
        // A Material rather than a coloured box, so the ink of the row and
        // of its buttons is painted over the tint and not under it. A
        // Material also sets its own default text style; handing it the
        // inherited one keeps the row's type as it was without the tint.
        builder: (BuildContext context, Color? color, Widget? child) =>
            Material(
              color: color ?? Colors.transparent,
              textStyle: DefaultTextStyle.of(context).style,
              child: child,
            ),
        child: widget.child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.columns, required this.heads});

  final List<InfiniteScrollTableColumnType> columns;
  final Map<InfiniteScrollTableColumnType, InfiniteScrollTableHead> heads;

  @override
  Widget build(BuildContext context) {
    // The content is scrolled under the header, hence we need to cover it up
    // with the colour of the panel the table sits in.
    final Color background = Theme.of(context).colorScheme.primary;

    final List<Widget> children = List<Widget>.generate(
      columns.length,
      (int index) {
        final InfiniteScrollTableColumnType column = columns[index];

        final InfiniteScrollTableHead? head = heads[column];

        final int flex = head?.flex ?? column.flex;

        final String name = head?.name ?? column.name(context: context);

        final MainAxisAlignment alignment = head?.alignment ?? column.aligment;

        return InfiniteScrollTableColumn(
          alignment: alignment,
          name: name,
          flex: flex,
          tooltip: head?.tooltip,
        );
      },
    );

    return ColoredBox(
      color: background,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kInfiniteTableHorizontalPadding,
              ),
              child: Row(
                children: children,
              ),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
