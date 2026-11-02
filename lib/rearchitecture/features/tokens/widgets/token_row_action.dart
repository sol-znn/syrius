import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The side of a row action's hit area.
const double kTokenRowActionSize = 32;

/// The size of a row action's icon.
const double kTokenRowActionIconSize = 18;

/// An action a token row repeats on every line: a small quiet icon with a
/// tooltip, the click cursor and a hover tint.
///
/// A row of filled or coloured buttons on every line would compete with the
/// page's one primary action, so these stay faint until pointed at.
///
/// It stays an [IconButton] by type, so a test that finds one by its key
/// can still read `onPressed` from it.
class TokenRowAction extends IconButton {
  /// Creates the action. [tooltip] names it, for a person and for the
  /// harness. Without a [color] it takes the theme's faint ink.
  const TokenRowAction({
    required super.icon,
    required String super.tooltip,
    required super.onPressed,
    super.color,
    super.key,
  });

  // The faint ink differs between the light and the dark theme, so it is
  // read here and not given as a constant default.
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      color: color ?? AppTokens.of(context).faint,
      iconSize: kTokenRowActionIconSize,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      mouseCursor: WidgetStateMouseCursor.clickable,
      // Compact density reduces minimum constraints, so fix the visible size
      // and remove the inherited tap padding to fit the four-action column.
      style: const ButtonStyle(
        fixedSize: WidgetStatePropertyAll<Size>(
          Size.square(kTokenRowActionSize),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(
        width: kTokenRowActionSize,
        height: kTokenRowActionSize,
      ),
    );
  }
}
