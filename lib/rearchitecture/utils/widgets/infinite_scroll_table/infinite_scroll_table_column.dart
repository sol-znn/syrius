part of 'infinite_scroll_table.dart';

/// What one table changes about the head of one of its columns.
///
/// A column type carries one name and one flex for every table that uses it.
/// A table whose columns are too many for those, or whose values are much
/// narrower than the type's name, passes one of these for the column in
/// [InfiniteScrollTable.heads]. A field left null keeps the type's own value.
///
/// The row's cells set their own flex, so a table that changes [flex] here
/// gives the same number to the cell under it.
class InfiniteScrollTableHead {
  /// Creates a new instance.
  const InfiniteScrollTableHead({
    this.name,
    this.tooltip,
    this.flex,
    this.alignment,
  });

  /// The name shown, in place of the column type's.
  final String? name;

  /// What the head says on hover: the full name, when [name] is a short one.
  final String? tooltip;

  /// The space the column takes, in place of the column type's.
  final int? flex;

  /// A status heading can align with the status chips below it.
  final MainAxisAlignment? alignment;
}

/// A widget that represents a column inside the [InfiniteScrollTable] header.
///
/// Currently the sort arrows are not visible, by default, so the row sorting
/// is disabled
class InfiniteScrollTableColumn extends StatelessWidget {
  /// Creates a new instance.
  const InfiniteScrollTableColumn({
    required this.alignment,
    required this.name,
    this.onSortArrowsPressed,
    this.flex = 1,
    this.tooltip,
    super.key,
  });

  /// The name of the column.
  final String name;

  /// Shown on hover when not null: the full name behind a short [name].
  final String? tooltip;

  /// Callback to be executed when the sort arrows are pressed.
  final Function(String)? onSortArrowsPressed;

  /// Defines how much space the column should take.
  final int flex;

  /// Alignment of the column header content.
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    // Spaced capitals only where the language is written in Latin letters;
    // see usesLatinScript. Zero and not null, to clear the theme's spacing.
    final bool latin = usesLatinScript(context);
    final Widget label = Text(
      latin ? name.toUpperCase() : name,
      overflow: TextOverflow.ellipsis,
      style:
          monoStyle(
            Theme.of(context).textTheme.bodyMedium,
          ).copyWith(
            fontSize: 11,
            letterSpacing: latin ? 0.66 : 0,
            color: AppTokens.of(context).faint,
          ),
    );

    return Expanded(
      flex: flex,
      child: Row(
        mainAxisAlignment: alignment,
        children: <Widget>[
          Flexible(
            child: tooltip == null
                ? label
                : Tooltip(message: tooltip, child: label),
          ),
          // Mono capitals fill their column; without a gap two narrow headers
          // read as one word.
          const SizedBox(width: 8),
          // TODO(community): enable row sorting
          Visibility(
            visible: false,
            child: InkWell(
              onTap: () => onSortArrowsPressed!(name),
              child: Icon(
                Icons.sort,
                size: 15,
                color: Theme.of(context).iconTheme.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
