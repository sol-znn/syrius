import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart'
    show kSharedPrefsBox;
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_dismiss.dart';

/// The gap between panels on every page of the refreshed interface.
///
/// The same value as `AppTokens.panelGap`, kept for the places that need a
/// constant. With a context at hand, read the token.
const double kPanelGap = 14;

/// What a collapsible panel's state is filed under in the shared
/// preferences: this, then the panel's [Panel.collapseKey].
///
/// Kept here and not with the other preference keys because it is a prefix
/// that only this file completes.
const String _kPanelCollapsedKeyPrefix = 'panel_collapsed_';

/// The shared preferences, or null while their box is not open: before the
/// wallet has opened it, and in a test that pumps a panel on its own.
Box<dynamic>? _panelPreferences() =>
    Hive.isBoxOpen(kSharedPrefsBox) ? Hive.box<dynamic>(kSharedPrefsBox) : null;

/// Whether the panel filed under [collapseKey] was left collapsed. Null
/// when nothing says so: it was never toggled, there is no box, or the
/// entry is damaged.
bool? _storedCollapsed(String collapseKey) {
  final Object? stored = _panelPreferences()?.get(
    '$_kPanelCollapsedKeyPrefix$collapseKey',
  );
  return stored is bool ? stored : null;
}

/// Stores the choice for the next start. Without a box it lives only as
/// long as the panel's own state does.
void _storeCollapsed(String collapseKey, {required bool collapsed}) {
  final Box<dynamic>? preferences = _panelPreferences();
  if (preferences == null) return;
  unawaited(
    preferences.put('$_kPanelCollapsedKeyPrefix$collapseKey', collapsed),
  );
}

/// The title of a panel: the one size every card heading uses.
TextStyle panelTitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.headlineSmall!.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

/// The ledger label: mono capitals, faint. Labels only, never values.
///
/// Spaced only where the language is written in Latin letters: spacing
/// pulls joined Arabic letters apart. Zero and not null elsewhere, because
/// the theme's own style carries Material's spacing and null would keep it.
TextStyle ledgerLabelStyle(BuildContext context) => monoStyle(
  Theme.of(context).textTheme.titleSmall!.copyWith(
    fontSize: 11,
    letterSpacing: usesLatinScript(context) ? 0.66 : 0,
    // The theme's faint: the dark theme's is too pale on a white card.
    color: AppTokens.of(context).faint,
  ),
);

/// A surface of mockup B: the card colour, the card radius, an optional title
/// row with actions, and a body.
///
/// A titled panel can also be its title row alone: closed by its reader
/// ([collapsible]), or because it has nothing to show ([isEmpty]).
class Panel extends StatelessWidget {
  /// Creates a panel.
  const Panel({
    required this.child,
    this.title,
    this.heading,
    this.actions = const <Widget>[],
    this.padding,
    this.shrinkWrap = false,
    this.collapsible = false,
    this.initiallyCollapsed = false,
    this.collapseKey,
    this.emptyNote,
    this.isEmpty = false,
    super.key,
  }) : assert(
         !collapsible || collapseKey != null,
         'A collapsible panel needs a collapseKey to store its state under.',
       ),
       assert(
         title != null || (!collapsible && emptyNote == null),
         'Only a titled panel folds: its title row is what is left.',
       ),
       assert(
         !isEmpty || emptyNote != null,
         'An empty panel says so in its title row: pass emptyNote.',
       );

  /// The heading. Without one the panel is a bare surface.
  final String? title;

  /// Shared Nodes tabs replace the plain title without duplicating a header.
  final Widget? heading;

  /// Small controls at the right of the title row.
  final List<Widget> actions;

  /// Padding around [child]. None when null, for a table or list that runs
  /// to the edges.
  final EdgeInsetsGeometry? padding;

  /// The body.
  final Widget child;

  /// Whether a titled panel is as tall as its title row and body, instead of
  /// filling the height it is given.
  ///
  /// A titled panel puts its body in an `Expanded`, which needs a bounded
  /// height: right in a grid cell, an error in a column that gives none.
  /// Set this for a short panel stacked in such a column, so its owner does
  /// not have to work its height out. The body must then size itself (no
  /// list that scrolls to fill). A panel without a title is always as tall
  /// as its body.
  final bool shrinkWrap;

  /// Whether the title row opens and closes the body: by a click, or by
  /// Enter or Space when it has the focus. A chevron at its end shows which.
  ///
  /// Closed, the panel is its title row and nothing else. What that gives
  /// back depends on who sized the panel. Stacked in a column at its own
  /// height ([shrinkWrap]), the panels after it move up and a sibling in an
  /// `Expanded` takes the height. In a slot of fixed height (an `Expanded`,
  /// a [PageGrid] cell) the card still shrinks to its title row, at the top
  /// of the slot, but the slot keeps its height: only its owner can hand
  /// that to someone else.
  ///
  /// The body leaves the tree while the panel is closed, and with it what
  /// it held: a scroll position, a half-typed field.
  final bool collapsible;

  /// Whether a [collapsible] panel is closed the first time it is shown.
  ///
  /// Only the first time: once the reader has opened or closed it, what
  /// they chose is stored and wins over this.
  final bool initiallyCollapsed;

  /// What the open or closed state is stored under, so that it outlives a
  /// restart. Required when [collapsible].
  ///
  /// A fixed identifier of the panel's place, such as `home.activity`.
  /// Never the title: that is translated, and a state keyed on it is lost
  /// when the language changes.
  final String? collapseKey;

  /// What the title row says beside the title while [isEmpty], such as the
  /// app's "None yet". Passing it is what lets the panel fold when empty.
  final String? emptyNote;

  /// Whether there is nothing to show. The panel is then one line: its
  /// title row with [emptyNote] beside the title, no body, and no chevron
  /// to open what has nothing in it. [actions] stay.
  ///
  /// When this turns false the body comes back, unless the reader had the
  /// panel closed.
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    // A panel that can fold is laid out apart, so that one that cannot is
    // built exactly as it was before any could.
    if (collapsible || emptyNote != null) {
      return _FoldingPanel(this);
    }
    final ThemeData theme = Theme.of(context);
    final Widget body = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(AppTokens.of(context).cardRadius),
      clipBehavior: Clip.antiAlias,
      child: title == null && heading == null
          ? body
          : Column(
              mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(context),
                const Divider(),
                if (shrinkWrap) body else Expanded(child: body),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Widget header = Padding(
      padding: heading == null
          ? tokens.panelHeaderPadding
          : tokens.tabHeaderPadding,
      child: Row(
        crossAxisAlignment: heading == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child:
                heading ??
                Text(
                  title!,
                  overflow: TextOverflow.ellipsis,
                  style: panelTitleStyle(context),
                ),
          ),
          for (final Widget action in actions)
            if (heading == null)
              action
            else
              Center(widthFactor: 1, child: action),
        ],
      ),
    );
    if (heading == null) {
      return SizedBox(height: tokens.panelHeaderHeight, child: header);
    }
    // Headings and actions share the full row height. Asking their actual
    // intrinsics lets translated or scaled labels grow without moving the
    // underline away from the card's divider.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: tokens.panelHeaderHeight),
      child: IntrinsicHeight(child: header),
    );
  }
}

/// A titled [Panel] that can be its title row alone.
///
/// It holds what the plain panel has no use for: whether the reader has it
/// closed, and the one animation that the body's height, its fade and the
/// chevron all follow, so the three cannot come apart.
class _FoldingPanel extends StatefulWidget {
  const _FoldingPanel(this.panel);

  /// The panel as its owner wrote it.
  final Panel panel;

  @override
  State<_FoldingPanel> createState() => _FoldingPanelState();
}

class _FoldingPanelState extends State<_FoldingPanel>
    with SingleTickerProviderStateMixin {
  late bool _collapsed = _startsCollapsed();

  // Starts where the panel is, so nothing opens or closes as a page is
  // shown. The motion always runs: the controller keeps its duration
  // whatever the system says about reduced motion
  // ([AnimationBehavior.preserve]; the default shortens it to a twentieth),
  // and nothing here asks MediaQuery.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Durations.short4,
    value: _bodyShown ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );

  late final CurvedAnimation _reveal = CurvedAnimation(
    parent: _controller,
    curve: Easing.standard,
  );

  /// Whether the body is shown, or on its way to being.
  bool get _bodyShown => !widget.panel.isEmpty && !_collapsed;

  /// The stored choice, and [Panel.initiallyCollapsed] until there is one.
  bool _startsCollapsed() {
    final Panel panel = widget.panel;
    if (!panel.collapsible) return false;
    return _storedCollapsed(panel.collapseKey!) ?? panel.initiallyCollapsed;
  }

  @override
  void didUpdateWidget(_FoldingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Panel was = oldWidget.panel;
    final Panel now = widget.panel;
    // Another key is another panel's state, to be read as on a first show.
    if (was.collapsible != now.collapsible ||
        was.collapseKey != now.collapseKey) {
      _collapsed = _startsCollapsed();
    }
    // The content may have come or gone.
    _follow();
  }

  @override
  void dispose() {
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    _storeCollapsed(widget.panel.collapseKey!, collapsed: _collapsed);
    _follow();
  }

  void _dismiss() {
    if (widget.panel.collapsible && !_collapsed) _toggle();
  }

  /// Sends the animation to where [_bodyShown] says it belongs.
  void _follow() {
    if (_bodyShown == _controller.status.isForwardOrCompleted) return;
    if (_bodyShown) {
      _controller.forward();
      return;
    }
    // Once closed the body leaves the tree, which takes a build that no
    // change of the panel asks for. A close that is turned back before it
    // ends never completes, and so never gets here.
    unawaited(
      _controller.reverse().then<void>((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Panel panel = widget.panel;
    final bool closed = !_bodyShown && _controller.isDismissed;
    final Widget body = panel.padding == null
        ? panel.child
        : Padding(padding: panel.padding!, child: panel.child);
    final Widget reveal = _PanelReveal(
      reveal: _reveal,
      shrinkWrap: panel.shrinkWrap,
      child: body,
    );
    // The card is as tall as what it shows. Told to be taller, by a slot of
    // fixed height, it stays at the top of the slot at its own height and
    // leaves the rest clear: a card stretched over a body that is not there
    // would read as an empty panel, the very thing closing it removes.
    return PageDismissAction(
      open: panel.collapsible && _bodyShown,
      onDismiss: _dismiss,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        heightFactor: 1,
        child: Material(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(AppTokens.of(context).cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PanelHeader(
                title: panel.title!,
                note: panel.isEmpty ? panel.emptyNote : null,
                actions: panel.actions,
                reveal: _reveal,
                open: !_collapsed,
                onToggle: panel.collapsible && !panel.isEmpty ? _toggle : null,
              ),
              // Loosely flexible where the plain panel's body is `Expanded`:
              // open, the body has all the height that is left, as there; on
              // the way it has the part of it the animation has reached.
              if (!closed && panel.shrinkWrap)
                reveal
              else if (!closed)
                Flexible(child: reveal),
            ],
          ),
        ),
      ),
    );
  }
}

/// The part of a folding panel that opens and closes: the divider under the
/// title row and the body, so that a closed panel has neither.
///
/// The body is laid out at its full height throughout and uncovered from
/// the top, as a blind is. Squeezed into the height reached so far, a form
/// would overflow on every frame of the way.
class _PanelReveal extends StatelessWidget {
  const _PanelReveal({
    required this.reveal,
    required this.shrinkWrap,
    required this.child,
  });

  /// 0 closed, 1 open.
  final Animation<double> reveal;

  /// Whether the body sizes itself, as [Panel.shrinkWrap] says.
  final bool shrinkWrap;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // SizeTransition clips to a plain rectangle, which costs no layer of
    // its own; the card already rounds the corners.
    return SizeTransition(
      sizeFactor: reveal,
      alignment: AlignmentDirectional.topStart,
      child: FadeTransition(
        opacity: reveal,
        child: Column(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Divider(),
            if (shrinkWrap) child else Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// The title row of a folding panel: the title, the note of an empty panel
/// beside it, the owner's actions, and the chevron of one that toggles.
///
/// The row is the button, and it is the same widget whether it toggles or
/// not (a button with nothing to do is switched off, not taken out), so the
/// actions keep their state when the content comes or goes.
class _PanelHeader extends StatefulWidget {
  const _PanelHeader({
    required this.title,
    required this.note,
    required this.actions,
    required this.reveal,
    required this.open,
    required this.onToggle,
  });

  final String title;

  /// Shown beside the title, muted. Null when the panel has content.
  final String? note;

  final List<Widget> actions;

  /// 0 closed, 1 open: what the chevron turns with.
  final Animation<double> reveal;

  /// Where the panel is going, for a screen reader.
  final bool open;

  /// Null when the row does not toggle: it is then no button, has no
  /// chevron and takes no focus.
  final VoidCallback? onToggle;

  @override
  State<_PanelHeader> createState() => _PanelHeaderState();
}

class _PanelHeaderState extends State<_PanelHeader> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool toggles = widget.onToggle != null;
    return SizedBox(
      height: tokens.panelHeaderHeight,
      child: Semantics(
        button: toggles,
        expanded: toggles ? widget.open : null,
        // An action inside the row is hit before the row is, so its tap is
        // its own and never reaches this one.
        child: InkWell(
          // Said outright: left to itself the ink keeps the arrow on a
          // desktop, and the row would not look pressable.
          mouseCursor: toggles ? SystemMouseCursors.click : null,
          hoverColor: tokens.hover,
          // Focus is the ring below, not a fill: the theme's focus fill is
          // heavier than the hover it would sit beside.
          focusColor: Colors.transparent,
          onFocusChange: (bool value) => setState(() => _focused = value),
          onTap: widget.onToggle,
          child: DecoratedBox(
            // Drawn inside the row's own box, so focus moves nothing.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: _focused && toggles
                  ? Border.all(color: tokens.focusRing, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
            ),
            child: Padding(
              padding: tokens.panelHeaderPadding,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _PanelTitle(
                      title: widget.title,
                      note: widget.note,
                    ),
                  ),
                  ...widget.actions,
                  if (toggles) _PanelChevron(reveal: widget.reveal),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel's title, and beside it the note of a panel with nothing in it.
class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final Widget heading = Text(
      title,
      overflow: TextOverflow.ellipsis,
      style: panelTitleStyle(context),
    );
    if (note == null) return heading;
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      // The note is smaller than the title and stands on its line.
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Flexible(child: heading),
        SizedBox(width: tokens.cardGap),
        Flexible(
          child: Text(
            note!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              fontSize: 13,
              color: tokens.faint,
            ),
          ),
        ),
      ],
    );
  }
}

/// The chevron at the end of a toggling title row: down while the panel is
/// closed, turned half a circle to point up as it opens.
///
/// It turns towards the end of the row, which is the other way round right
/// to left. Both turns arrive at the same place; only the way there is
/// mirrored, as the row is.
class _PanelChevron extends StatelessWidget {
  const _PanelChevron({required this.reveal});

  /// 0 closed, 1 open.
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    // As wide as leaves the icon the title's inset from the card's edge.
    return SizedBox(
      width: 36,
      child: RotationTransition(
        turns: Tween<double>(begin: 0, end: rtl ? -0.5 : 0.5).animate(reveal),
        child: Icon(
          Icons.expand_more,
          size: 20,
          color: AppTokens.of(context).faint,
        ),
      ),
    );
  }
}

/// One figure: a ledger label over a value.
class Figure extends StatelessWidget {
  /// Creates a figure.
  const Figure({
    required this.label,
    required this.value,
    this.valueStyle,
    super.key,
  });

  /// The label, written in sentence case; shown in capitals where the
  /// language has them.
  final String label;

  /// The value. Numbers and identifiers are mono.
  final String value;

  /// Overrides the value's style.
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          usesLatinScript(context) ? label.toUpperCase() : label,
          style: ledgerLabelStyle(context),
        ),
        const SizedBox(height: 4),
        // A number, an amount or a Latin name runs left to right in every
        // language, at the app's start. A translated word ("None yet", an
        // error) has right-to-left letters and keeps the app's direction.
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: ltrUnlessRtl(value),
          textAlign: ltrTextAlign(context),
          style:
              valueStyle ??
              monoStyle(Theme.of(context).textTheme.headlineSmall).copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

/// A cell of a [PageGrid] row: a share of the width.
class PageCell {
  /// Creates a cell taking [flex] parts of its row.
  const PageCell(this.child, {this.flex = 1});

  /// What the cell shows.
  final Widget child;

  /// Its share of the row.
  final int flex;
}

/// A row of a [PageGrid].
class PageRow {
  /// A row of fixed [height].
  const PageRow.fixed(this.height, this.cells) : grow = 0;

  /// A row that takes what is left, never less than [height]; several such
  /// rows share it by [grow].
  const PageRow.fill(this.cells, {this.height = 220, this.grow = 1});

  /// The fixed height, or the least a filling row may have.
  final double height;

  /// 0 for a fixed row; otherwise this row's share of the spare height.
  final int grow;

  /// The panels, left to right.
  final List<PageCell> cells;
}

/// The page layout of mockup B: rows of panels that fill the window.
///
/// The old pages were a grid of cards sized from the window's width, so a
/// short or narrow window clipped a form's button and a tall one left space
/// under the tables. Here fixed rows keep their height and filling rows take
/// the rest. Only when the window is shorter than the rows' least heights
/// does the page scroll, and then every row keeps that least height.
class PageGrid extends StatelessWidget {
  /// Creates a page of [rows].
  const PageGrid({required this.rows, super.key});

  /// Top to bottom.
  final List<PageRow> rows;

  @override
  Widget build(BuildContext context) {
    final double gap = AppTokens.of(context).panelGap;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double least =
            rows.fold<double>(
              0,
              (double sum, PageRow r) => sum + r.height,
            ) +
            gap * (rows.length - 1);
        final bool fits = constraints.maxHeight >= least;
        final List<Widget> children = <Widget>[];
        for (int i = 0; i < rows.length; i++) {
          if (i > 0) children.add(SizedBox(height: gap));
          final PageRow row = rows[i];
          final Widget line = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int c = 0; c < row.cells.length; c++) ...<Widget>[
                if (c > 0) SizedBox(width: gap),
                Expanded(flex: row.cells[c].flex, child: row.cells[c].child),
              ],
            ],
          );
          children.add(
            fits && row.grow > 0
                ? Expanded(flex: row.grow, child: line)
                : SizedBox(height: row.height, child: line),
          );
        }
        final Widget column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
        return fits ? column : SingleChildScrollView(child: column);
      },
    );
  }
}
