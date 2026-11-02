import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// How long the detail takes to open or close.
const Duration _kRevealDuration = Duration(milliseconds: 240);

/// How long the chevron takes to turn. Shorter than the detail, so it has
/// arrived before the height has.
const Duration _kTurnDuration = Duration(milliseconds: 220);

/// How far above its place the detail starts, to slide down into it.
const double _kSlide = 8;

/// The least height of the row: the least a pointer can be asked to hit.
const double _kRowHeight = 32;

/// The mockup's spring: fast out, long settle, and never past either end,
/// so a height that follows it is never negative.
const Cubic _kSpring = Cubic(0.2, 0.8, 0.2, 1);

/// Lets only one [RowDetail] below it be open at a time: opening one closes
/// the other.
///
/// It also keeps which one is open, so put above a lazy list the open row
/// is still open when it has been scrolled away and built again. A row
/// takes part by having an [RowDetail.id]; one without is on its own.
class RowDetailGroup extends StatefulWidget {
  /// Creates a group round [child].
  const RowDetailGroup({
    required this.child,
    this.initiallyOpen,
    this.onChanged,
    super.key,
  });

  /// What holds the rows: a table, a list.
  final Widget child;

  /// The id of the row that is open the first time the group is shown.
  final Object? initiallyOpen;

  /// Called with the id of the open row, or null when the last one closed.
  final ValueChanged<Object?>? onChanged;

  /// The group round [context], or null. The caller is rebuilt when the
  /// open row changes.
  static RowDetailGroupState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowDetailGroupScope>()?.state;

  @override
  State<RowDetailGroup> createState() => RowDetailGroupState();
}

/// What a [RowDetailGroup] knows, and how to change it from elsewhere on
/// the page: a search that closes the open row as its results change.
class RowDetailGroupState extends State<RowDetailGroup> {
  late Object? _openId = widget.initiallyOpen;

  /// The id of the open row, or null when all are closed.
  Object? get openId => _openId;

  /// Opens the row with [id], closing the one that was open.
  void open(Object id) => _set(id);

  /// Closes the row with [id] if it is the open one, or whichever is open
  /// when no id is given.
  void close([Object? id]) {
    if (id == null || id == _openId) _set(null);
  }

  /// Opens the row with [id] if it is closed and closes it if it is open.
  void toggle(Object id) => _set(id == _openId ? null : id);

  void _set(Object? id) {
    if (id == _openId) return;
    setState(() => _openId = id);
    widget.onChanged?.call(id);
  }

  @override
  Widget build(BuildContext context) =>
      _RowDetailGroupScope(state: this, openId: _openId, child: widget.child);
}

class _RowDetailGroupScope extends InheritedWidget {
  const _RowDetailGroupScope({
    required this.state,
    required this.openId,
    required super.child,
  });

  final RowDetailGroupState state;

  /// Held here as well as in [state]: the state is the same object before
  /// and after a change, and could not tell the rows that there was one.
  final Object? openId;

  @override
  bool updateShouldNotify(_RowDetailGroupScope oldWidget) =>
      openId != oldWidget.openId;
}

/// Hands the row's chevron what it turns with, wherever in the row the
/// caller put it.
class _RowDetailScope extends InheritedWidget {
  const _RowDetailScope({required this.turned, required super.child});

  /// 0 closed, 1 open.
  final Animation<double> turned;

  @override
  bool updateShouldNotify(_RowDetailScope oldWidget) =>
      turned != oldWidget.turned;
}

/// A list row that opens its details in place, under itself.
///
/// A table keeps to a few columns and everything else is one press away.
/// The whole row is the button; the open row and its detail share one tint
/// and read as one block.
///
/// Who holds the open state, first that applies:
///
/// * the caller, when [open] is given: [onToggle] asks for the change and
///   the row waits to be rebuilt with it;
/// * the [RowDetailGroup] above, when the row has an [id]: one row open at
///   a time, and the state outlives the row;
/// * the row itself. In a lazy list that state goes when the row is
///   scrolled away, and it comes back closed.
///
/// A button inside the row keeps its own press. A disabled one has nothing
/// to take the press with and lets it through to the row, so wrap an inner
/// control that can be disabled in [RowDetailIgnore].
///
/// It needs a bounded width, and is as tall as what it shows.
class RowDetail extends StatefulWidget {
  /// Creates a row with a detail under it.
  const RowDetail({
    required this.row,
    required this.detail,
    this.open,
    this.onToggle,
    this.id,
    this.initiallyOpen = false,
    this.hoverTint = true,
    this.tintBleed = EdgeInsetsDirectional.zero,
    this.keyPrefix,
    super.key,
  });

  /// The row itself, laid out by the caller: the cells, and a
  /// [RowDetailChevron] where it wants one.
  final Widget row;

  /// The detail. Called only while the row is open or on its way, so a
  /// closed row costs nothing of what its detail would load.
  final WidgetBuilder detail;

  /// Whether the row is open, when the caller holds that. Null leaves it to
  /// the group or to the row.
  final bool? open;

  /// Called with the state a press asks for. With [open] given this is the
  /// only thing a press does.
  final ValueChanged<bool>? onToggle;

  /// What a [RowDetailGroup] knows this row by: the item's own identity, a
  /// pillar's name or a token standard. Never its index, which another
  /// item has after a sort.
  final Object? id;

  /// Whether a row that holds its own state starts open.
  final bool initiallyOpen;

  /// Whether the row is tinted under the pointer. Off inside a table that
  /// tints its rows itself, or the two are laid one over the other.
  final bool hoverTint;

  /// How far the tint is painted past the row's own box. A table that pads
  /// its rows leaves this one short of the table's edges, and the block
  /// should reach them.
  final EdgeInsetsDirectional tintBleed;

  /// Gives the row `ValueKey('<keyPrefix>_row')`, for the UI harness.
  final String? keyPrefix;

  @override
  State<RowDetail> createState() => _RowDetailState();
}

class _RowDetailState extends State<RowDetail> with TickerProviderStateMixin {
  // Made at the first didChangeDependencies and not in initState: where
  // they start depends on the group, which cannot be asked before then.
  // They start where the row is, so a row scrolled back into a list is open
  // at once. The motion always runs: the controllers keep their duration
  // whatever the system says about reduced motion
  // ([AnimationBehavior.preserve]), and nothing here asks MediaQuery.
  late final AnimationController _body;
  late final AnimationController _turn;
  late final CurvedAnimation _reveal;
  late final CurvedAnimation _turned;

  RowDetailGroupState? _group;
  bool _started = false;

  /// The row's own state, used when neither the caller nor a group has it.
  late bool _own = widget.initiallyOpen;

  /// Where the animations were last sent.
  bool _open = false;

  bool _hovered = false;
  bool _focused = false;

  bool get _grouped => _group != null && widget.id != null;

  /// Where whoever holds the state says the row is.
  bool get _wanted =>
      widget.open ?? (_grouped ? _group!.openId == widget.id : _own);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _group = RowDetailGroup.maybeOf(context);
    if (_started) {
      _follow();
      return;
    }
    _started = true;
    _open = _wanted;
    _body = AnimationController(
      vsync: this,
      duration: _kRevealDuration,
      value: _open ? 1 : 0,
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onBodyStatus);
    _turn = AnimationController(
      vsync: this,
      duration: _kTurnDuration,
      value: _open ? 1 : 0,
      animationBehavior: AnimationBehavior.preserve,
    );
    _reveal = CurvedAnimation(parent: _body, curve: _kSpring);
    _turned = CurvedAnimation(parent: _turn, curve: _kSpring);
  }

  @override
  void didUpdateWidget(RowDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  @override
  void dispose() {
    _reveal.dispose();
    _turned.dispose();
    _body.dispose();
    _turn.dispose();
    super.dispose();
  }

  /// The two ends take a build that no change of the widget asks for:
  /// closed, the detail leaves the tree; open, the clip comes off.
  void _onBodyStatus(AnimationStatus status) {
    if (!mounted || status.isAnimating) return;
    setState(() {});
  }

  /// Sends both animations to where the state now is, if that has changed.
  void _follow() {
    final bool wanted = _wanted;
    if (wanted == _open) return;
    _open = wanted;
    if (_open) {
      _body.forward();
      _turn.forward();
    } else {
      _body.reverse();
      _turn.reverse();
    }
  }

  void _toggle() {
    final bool next = !_open;
    if (widget.open == null) {
      if (_grouped) {
        // The group rebuilds its rows, this one among them, and each
        // follows from didChangeDependencies.
        if (next) {
          _group!.open(widget.id!);
        } else {
          _group!.close(widget.id);
        }
      } else {
        setState(() {
          _own = next;
          _follow();
        });
      }
    }
    widget.onToggle?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool closed = !_open && _body.isDismissed;
    final String? keyPrefix = widget.keyPrefix;

    final Widget row = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        key: keyPrefix == null ? null : ValueKey<String>('${keyPrefix}_row'),
        // Said outright: left to itself the ink keeps the arrow on a
        // desktop, and the row would not look pressable.
        mouseCursor: SystemMouseCursors.click,
        // The tint is painted below, where it can run on under the detail.
        // The ink's own would stop at the row, and its splash would start
        // under a press held on an inner button that the row never gets.
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        // Focus is the ring below, not a fill.
        focusColor: Colors.transparent,
        onHover: (bool value) => setState(() => _hovered = value),
        onFocusChange: (bool value) => setState(() => _focused = value),
        onTap: _toggle,
        child: DecoratedBox(
          // Drawn inside the row's own box, so focus moves nothing.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: _focused
                ? Border.all(color: tokens.focusRing, width: 2)
                : null,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _kRowHeight),
            child: widget.row,
          ),
        ),
      ),
    );

    return _RowDetailScope(
      turned: _turned,
      child: CustomPaint(
        painter: _TintPainter(
          reveal: _reveal,
          hovered: _hovered && widget.hoverTint,
          color: tokens.hover,
          bleed: widget.tintBleed.resolve(Directionality.of(context)),
        ),
        // The ink needs a Material to draw on, and the row does not know
        // whether the surface it was put in is one. A Material also sets
        // its own text style; handed the inherited one, the row's type
        // stays what the table made it.
        child: Material(
          type: MaterialType.transparency,
          textStyle: DefaultTextStyle.of(context).style,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              row,
              if (!closed)
                // Closing details refuse input and semantic actions while
                // the same body can still reverse its reveal.
                IgnorePointer(
                  ignoring: !_open,
                  child: ExcludeSemantics(
                    excluding: !_open,
                    child: Focus(
                      canRequestFocus: false,
                      // Keep retained EditableText traversal flags unchanged.
                      descendantsAreFocusable: _open,
                      child: _RowDetailReveal(
                        reveal: _reveal,
                        child: Builder(builder: widget.detail),
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

/// The one tint behind the row and its detail.
///
/// Full under the pointer, and otherwise as far in as the detail is open,
/// so it leaves with the detail and not a frame after it. Never the two
/// added up: an open row under the pointer is no darker than an open row.
class _TintPainter extends CustomPainter {
  _TintPainter({
    required this.reveal,
    required this.hovered,
    required this.color,
    required this.bleed,
  }) : super(repaint: reveal);

  /// 0 closed, 1 open.
  final Animation<double> reveal;
  final bool hovered;
  final Color color;
  final EdgeInsets bleed;

  @override
  void paint(Canvas canvas, Size size) {
    final double strength = hovered ? 1 : reveal.value;
    if (strength <= 0) return;
    canvas.drawRect(
      bleed.inflateRect(Offset.zero & size),
      Paint()..color = color.withValues(alpha: color.a * strength),
    );
  }

  @override
  bool shouldRepaint(_TintPainter oldDelegate) =>
      hovered != oldDelegate.hovered ||
      color != oldDelegate.color ||
      bleed != oldDelegate.bleed ||
      reveal != oldDelegate.reveal;
}

/// The part that opens and closes.
///
/// The detail is laid out at its full height throughout and uncovered from
/// the top, while it fades in and comes down the last few pixels into its
/// place. Squeezed into the height reached so far, it would overflow on
/// every frame of the way.
class _RowDetailReveal extends StatelessWidget {
  const _RowDetailReveal({required this.reveal, required this.child});

  /// 0 closed, 1 open.
  final Animation<double> reveal;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      // Align hands its child loose constraints; the detail is to be as
      // wide as the row is.
      child: SizedBox(
        width: double.infinity,
        child: FadeTransition(opacity: reveal, child: child),
      ),
      builder: (BuildContext context, Widget? child) {
        final double t = reveal.value;
        // Clipped only on the way. Open, a button's focus ring reaches
        // past the detail's box and must not be cut.
        return ClipRect(
          clipBehavior: reveal.isCompleted ? Clip.none : Clip.hardEdge,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: t,
            child: Transform.translate(
              offset: Offset(0, -_kSlide * (1 - t)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The chevron of the [RowDetail] it is in, put wherever in the row the
/// caller wants it: sideways while closed, pointing the way the text runs
/// on, and turned a quarter to point down as the detail opens.
///
/// Right to left it starts from the other side, as the row does, and both
/// arrive at the same place. Outside a [RowDetail] it stays closed.
class RowDetailChevron extends StatelessWidget {
  /// Creates the chevron.
  const RowDetailChevron({this.size = 16, super.key});

  /// The side of the icon's box.
  final double size;

  @override
  Widget build(BuildContext context) {
    final Animation<double> turned =
        context.dependOnInheritedWidgetOfExactType<_RowDetailScope>()?.turned ??
        kAlwaysDismissedAnimation;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return RotationTransition(
      turns: Tween<double>(begin: rtl ? 0.25 : -0.25, end: 0).animate(turned),
      child: Icon(
        Icons.expand_more,
        size: size,
        color: AppTokens.of(context).faint,
      ),
    );
  }
}

/// Keeps a press on [child] from reaching the [RowDetail] it is in.
///
/// An enabled button wins the press over the row by itself. A disabled one
/// takes no press at all, so the row behind it does, and a press on a
/// greyed "Delegate" opens the row. This takes the press in its place and
/// does nothing with it; an enabled child still gets its own.
class RowDetailIgnore extends StatelessWidget {
  /// Wraps an inner control of a row.
  const RowDetailIgnore({required this.child, super.key});

  /// The control: a button, a copy icon, a link.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // It is not a button: a screen reader should find only the child.
      excludeFromSemantics: true,
      onTap: () {},
      child: child,
    );
  }
}
