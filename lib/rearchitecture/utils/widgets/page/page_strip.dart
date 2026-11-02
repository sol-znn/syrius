import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The edge of the strip's [PageStrip.lead] slot: the smallest size an
/// object animation is still drawn at.
const double kStripLeadSize = 48;

/// The style of a figure's value in a [PageStrip].
///
/// The mockup's 19 px mono value: a strip holds four of them beside a
/// button where a card holds one. A plain `Text` inherits it; a unit inside
/// a `Text.rich` sets its own size and colour over it.
TextStyle stripValueStyle(BuildContext context) =>
    AppTokens.of(context).stripAmountText;

/// The style of what stands beside a value in a [PageStrip]: its worth in
/// dollars, a weight. Small and faint, so the value is read first.
TextStyle stripTrailingStyle(BuildContext context) =>
    AppTokens.of(context).dollarText;

/// One headline figure of a [PageStrip]: a ledger label over a value.
///
/// A description and not a widget, so the strip decides how its figures
/// share the width.
class StripFigure {
  /// Creates a figure.
  const StripFigure({
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  /// The label, written in sentence case; shown in capitals where the
  /// language has them.
  final String label;

  /// The value: a `Text`, or a `Text.rich` of an amount and its unit, or a
  /// name and a chip. It inherits [stripValueStyle].
  ///
  /// The strip does not pin it left to right, because it cannot tell an
  /// amount from a translated word: an amount comes wrapped in `Ltr`.
  final Widget value;

  /// Shown after the value, dim: a dollar amount. It inherits
  /// [stripTrailingStyle].
  final Widget? trailing;

  /// Makes the figure a button with a chevron at its end: "Your pillar"
  /// opening its panel.
  final VoidCallback? onTap;
}

/// The bar at the top of a page: the headline figures and the page's main
/// action, on the card colour.
///
/// The figures keep to one row and give way before the actions do. Each
/// has at most an equal share of what the lead and the actions leave; in
/// that share its label is cut with an ellipsis and its value is drawn
/// smaller, whole, since half an amount is a different amount.
class PageStrip extends StatelessWidget {
  /// Creates a strip.
  const PageStrip({
    required this.figures,
    this.lead,
    this.actions = const <Widget>[],
    super.key,
  });

  /// What leads the strip, in a square of [kStripLeadSize]: the page's
  /// object animation, or the plasma glow.
  final Widget? lead;

  /// The figures, from the start.
  final List<StripFigure> figures;

  /// The page's main button and anything beside it, at the end. They keep
  /// their own width.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // The strip's inset differs from the list title's: its figures
        // have the extra room drawn in the mockup's stripcard rule.
        padding: tokens.stripPadding,
        // As tall as the lead slot with or without a lead, so the strip
        // does not change height between a page that has one and its
        // neighbour.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kStripLeadSize),
          child: Row(
            children: <Widget>[
              if (lead != null) ...<Widget>[
                SizedBox.square(dimension: kStripLeadSize, child: lead),
                SizedBox(width: tokens.cardGap),
              ],
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < figures.length; i++) ...<Widget>[
                      if (i > 0) SizedBox(width: tokens.panelGap * 2),
                      Flexible(child: _StripFigureView(figures[i])),
                    ],
                  ],
                ),
              ),
              for (final Widget action in actions) ...<Widget>[
                SizedBox(width: tokens.inlineGap),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One figure as drawn, and the button round it when it has an
/// [StripFigure.onTap].
class _StripFigureView extends StatefulWidget {
  const _StripFigureView(this.figure);

  final StripFigure figure;

  @override
  State<_StripFigureView> createState() => _StripFigureViewState();
}

class _StripFigureViewState extends State<_StripFigureView> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final StripFigure figure = widget.figure;
    final AppTokens tokens = AppTokens.of(context);
    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          usesLatinScript(context) ? figure.label.toUpperCase() : figure.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ledgerLabelStyle(context),
        ),
        const SizedBox(height: 3),
        // The value and what trails it shrink as one, so the dollar amount
        // is never pushed out by the amount it belongs to.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DefaultTextStyle.merge(
                style: stripValueStyle(context),
                maxLines: 1,
                softWrap: false,
                child: figure.value,
              ),
              if (figure.trailing != null) ...<Widget>[
                SizedBox(width: tokens.pageGap),
                DefaultTextStyle.merge(
                  style: stripTrailingStyle(context),
                  maxLines: 1,
                  softWrap: false,
                  child: figure.trailing!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (figure.onTap == null) return column;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      child: InkWell(
        // Said outright: left to itself the ink keeps the arrow on a
        // desktop, and the figure would not look pressable.
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        hoverColor: tokens.hover,
        // Focus is the ring below, as on a panel's title row.
        focusColor: Colors.transparent,
        onFocusChange: (bool value) => setState(() => _focused = value),
        onTap: figure.onTap,
        child: DecoratedBox(
          // Drawn inside the figure's own box, so focus moves nothing.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: _focused
                ? Border.all(color: tokens.focusRing, width: 2)
                : null,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: column),
              // The chevron points the way the interface reads.
              Icon(
                rtl ? Icons.chevron_left : Icons.chevron_right,
                size: 20,
                color: tokens.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
