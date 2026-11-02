import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// The edge of the no-data mark in an empty list.
const double kEmptyNoteMarkSize = 44;

/// The edge of the no-data mark in a one-line empty card.
const double kEmptyNoteLineMarkSize = 16;

/// What stands where a list has nothing in it: the wallet's original
/// no-data mark and a line of text.
///
/// The mark plays once as it appears and holds its last frame, as every
/// object animation does: a loop beside amounts draws the eye from them.
/// It plays whatever the system says about reduced motion; nothing here
/// asks.
class EmptyNote extends StatelessWidget {
  /// The list size: the mark at [kEmptyNoteMarkSize] with [text] under it,
  /// centred in the space given.
  const EmptyNote({required this.text, this.action, super.key}) : _line = false;

  /// The line size: the mark at [kEmptyNoteLineMarkSize] with [text]
  /// beside it, as wide as the two, for a card that is one line when empty.
  const EmptyNote.line({required this.text, super.key})
    : action = null,
      _line = true;

  /// What it says, localized by the caller: the app's "None yet".
  final String text;

  /// Under the text of the list size: the one thing to do about an empty
  /// list, when there is one.
  final Widget? action;

  final bool _line;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // The theme's dim, which each theme sets for its own card colour.
    final TextStyle style = _line
        ? Theme.of(context).textTheme.titleMedium!
        : tokens.bodyText.copyWith(color: tokens.dim);
    if (_line) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _Mark(size: kEmptyNoteLineMarkSize, opacity: 0.7),
          SizedBox(width: tokens.cardGap),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.panelGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _Mark(size: kEmptyNoteMarkSize, opacity: 0.85),
            SizedBox(height: tokens.pageGap),
            Text(text, textAlign: TextAlign.center, style: style),
            if (action != null) ...<Widget>[
              SizedBox(height: tokens.panelGap),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The no-data mark, held back a little so that it does not outweigh the
/// text it stands for.
class _Mark extends StatelessWidget {
  const _Mark({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: AppLottie(AppLottieAsset.noData, size: size, repeat: false),
    );
  }
}
