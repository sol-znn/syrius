import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Between the track's line and a segment. No token names a gap this small
/// (the nearest, `cardGap`, is 10), so the mockup's 3 px is kept as it is.
const double _kTrackPadding = 3;

/// Round a label, from the mockup. The 14 is `panelGap`'s number and not its
/// meaning: a page that spaced its panels wider must not fatten every pill.
const EdgeInsets _kSegmentPadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 5,
);

const double _kIconSize = 14;
const double _kIconGap = 6;

/// The focus ring is the switch's: 2 px, drawn inside the track's edge so
/// that taking the focus moves nothing.
const double _kFocusRingWidth = 2;

/// The surface shared by the choices in a [Segment].
enum SegmentAppearance {
  /// A filled track and a rounded sliding thumb.
  pill,

  /// Flat card headings with one sliding underline.
  heading,
}

/// One choice of a [Segment].
@immutable
class SegmentItem<T> {
  /// Creates the choice [value], shown as [label].
  const SegmentItem({
    required this.value,
    required this.label,
    this.icon,
    this.count,
    this.enabled = true,
    this.seam,
    this.labelStyle,
  });

  /// What [Segment.onChanged] is given when this is picked.
  final T value;

  /// The word on the segment, already in the interface language.
  final String label;

  /// Drawn before the label, in the label's colour.
  final IconData? icon;

  /// A reported total beside the label. Unknown totals are absent.
  final int? count;

  /// A drawn choice can be unavailable without changing the other choices.
  final bool enabled;

  /// Missing backing behavior denies direct callbacks as well as input.
  final Seam? seam;

  /// Numeric preferences use the same mono role as the values they select.
  final TextStyle? labelStyle;
}

/// A choice between a few values, with one thumb that slides to whichever
/// is picked. [SegmentAppearance.pill] is the default; card headings use
/// [SegmentAppearance.heading] on the same measured track.
///
/// It is the only control of its kind in the interface: Send, Receive and
/// Zap on Transfer, the filters over a list, the choices in Settings. A
/// choice made here applies at once; there is no confirm step under it.
///
/// ```dart
/// Segment<TokenFilter>(
///   keyPrefix: 'tokens_filter',
///   items: const <SegmentItem<TokenFilter>>[
///     SegmentItem<TokenFilter>(value: TokenFilter.held, label: 'Held'),
///     SegmentItem<TokenFilter>(value: TokenFilter.all, label: 'All'),
///   ],
///   selected: filter,
///   onChanged: (TokenFilter value) => setState(() => filter = value),
/// )
/// ```
///
/// The control holds no selection of its own. [onChanged] reports a pick,
/// and the thumb moves when the widget is rebuilt with the new [selected],
/// wherever that came from: a click, an arrow key, or the page itself.
///
/// Each segment is as wide as its label. Under a width too small for all of
/// them the segments narrow in proportion and the labels are cut with an
/// ellipsis, so the control never overflows. Given more width than it needs
/// it keeps its own and sits at the start, which is the right side under a
/// right-to-left interface; the order of the segments mirrors there too.
///
/// The keyboard treats it as one stop: Tab reaches the control, and the
/// left and right arrows move the selection towards that side of the screen.
class Segment<T> extends StatefulWidget {
  /// Creates a choice between [items].
  const Segment({
    required this.items,
    required this.selected,
    required this.onChanged,
    this.appearance = SegmentAppearance.pill,
    this.pillPadding,
    this.keyPrefix,
    super.key,
  });

  /// How long the thumb takes from one segment to another.
  static const Duration slideDuration = Duration(milliseconds: 360);

  /// The thumb's easing: slow away, fast across, slow home.
  static const Cubic slideCurve = Cubic(0.65, 0, 0.35, 1);

  /// What can be picked, in reading order.
  final List<SegmentItem<T>> items;

  /// The value in effect. With null, or a value that is not among [items],
  /// no segment is lit and the thumb is closed.
  final T? selected;

  /// Called with the value picked, once per pick, and never with the value
  /// already in effect.
  final ValueChanged<T> onChanged;

  /// The track and thumb's surface. Selection and keyboard behavior are shared.
  final SegmentAppearance appearance;

  /// Optional pill label spacing; heading tabs keep their existing tokens.
  final EdgeInsetsGeometry? pillPadding;

  /// When given, each segment carries [keyOf] of it and its value, which is
  /// how the UI harness finds one.
  final String? keyPrefix;

  /// The key of the segment for [value] under [keyPrefix]: the prefix, an
  /// underscore, then the name of an enum value or the `toString` of any
  /// other.
  static ValueKey<String> keyOf(String keyPrefix, Object? value) =>
      ValueKey<String>('${keyPrefix}_${value is Enum ? value.name : value}');

  @override
  State<Segment<T>> createState() => _SegmentState<T>();
}

class _MoveIntent extends Intent {
  const _MoveIntent({required this.right});

  /// Towards the right of the screen, whichever way the interface runs.
  final bool right;
}

class _EdgeIntent extends Intent {
  const _EdgeIntent({required this.last});

  final bool last;
}

class _SegmentState<T> extends State<Segment<T>>
    with SingleTickerProviderStateMixin {
  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveIntent(
          right: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): _MoveIntent(
          right: true,
        ),
        SingleActivator(LogicalKeyboardKey.home): _EdgeIntent(last: false),
        SingleActivator(LogicalKeyboardKey.end): _EdgeIntent(last: true),
      };

  // At rest the controller sits at 1, with the thumb on the selected
  // segment. It keeps its length whatever the system says about reduced
  // motion ([AnimationBehavior.preserve]; the default plays it in a
  // twentieth of the time, which is a jump).
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Segment.slideDuration,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  late final CurvedAnimation _slide = CurvedAnimation(
    parent: _controller,
    curve: Segment.slideCurve,
  );

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    _MoveIntent: CallbackAction<_MoveIntent>(onInvoke: _move),
    _EdgeIntent: CallbackAction<_EdgeIntent>(onInvoke: _edge),
  };

  /// How lit each label was when the slide under way began, 0 dim to 1
  /// full. A pick made mid-slide starts each label from the colour it has,
  /// as the thumb starts from where it is.
  Map<T, double> _inkFrom = <T, double>{};

  bool _showRing = false;

  int _indexIn(Segment<T> of) {
    final T? selected = of.selected;
    return selected == null
        ? -1
        : of.items.indexWhere(
            (SegmentItem<T> item) => item.value == selected,
          );
  }

  double _inkAt(T value, T? selected, double t) =>
      lerpDouble(_inkFrom[value] ?? 0, value == selected ? 1 : 0, t)!;

  @override
  void didUpdateWidget(Segment<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The index and not the value: it is what the thumb's place hangs on,
    // and the render object starts its slide on the same change.
    if (_indexIn(oldWidget) != _indexIn(widget)) {
      final double t = _slide.value;
      _inkFrom = <T, double>{
        for (final SegmentItem<T> item in oldWidget.items)
          item.value: _inkAt(item.value, oldWidget.selected, t),
      };
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _pick(T value) {
    if (!mounted || value == widget.selected) {
      return;
    }
    for (final SegmentItem<T> item in widget.items) {
      if (item.value == value) {
        if (item.enabled) {
          runUnlessSeamed(
            seam: item.seam,
            action: () => widget.onChanged(value),
          );
        }
        return;
      }
    }
  }

  bool _available(int index) =>
      widget.items[index].enabled && widget.items[index].seam == null;

  Object? _edge(_EdgeIntent intent) {
    final int step = intent.last ? -1 : 1;
    for (
      int index = intent.last ? widget.items.length - 1 : 0;
      index >= 0 && index < widget.items.length;
      index += step
    ) {
      if (_available(index)) {
        _pick(widget.items[index].value);
        break;
      }
    }
    return null;
  }

  Object? _move(_MoveIntent intent) {
    if (widget.items.isEmpty) {
      return null;
    }
    final int index = _indexIn(widget);
    // An arrow points at a side of the screen, and the segments run from
    // the right under a right-to-left interface.
    final bool forward =
        intent.right == (Directionality.of(context) == TextDirection.ltr);
    final int step = index < 0 || forward ? 1 : -1;
    int next = index < 0 ? 0 : index + step;
    while (next >= 0 && next < widget.items.length) {
      if (_available(next)) {
        _pick(widget.items[next].value);
        break;
      }
      next += step;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final String? prefix = widget.keyPrefix;
    final bool heading = widget.appearance == SegmentAppearance.heading;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: FocusableActionDetector(
        enabled: widget.items.any(
          (SegmentItem<T> item) => item.enabled && item.seam == null,
        ),
        shortcuts: _shortcuts,
        actions: _actions,
        onShowFocusHighlight: (bool show) => setState(() => _showRing = show),
        child: DecoratedBox(
          decoration: heading
              ? const BoxDecoration()
              : ShapeDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: StadiumBorder(side: BorderSide(color: _lineOf(theme))),
                ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: heading
                ? BoxDecoration(
                    border: _showRing
                        ? Border.all(
                            color: tokens.focusRing,
                            width: _kFocusRingWidth,
                          )
                        : null,
                  )
                : ShapeDecoration(
                    shape: StadiumBorder(
                      side: _showRing
                          ? BorderSide(
                              color: tokens.focusRing,
                              width: _kFocusRingWidth,
                            )
                          : BorderSide.none,
                    ),
                  ),
            child: Padding(
              // The track's own line takes the first pixel.
              padding: heading
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(_kTrackPadding + 1),
              child: _SegmentRow(
                selectedIndex: _indexIn(widget),
                slide: _slide,
                textDirection: Directionality.of(context),
                gap: heading ? tokens.tabGap : 0,
                minHeight: heading ? tokens.panelHeaderHeight : 0,
                children: <Widget>[
                  SegmentThumb(appearance: widget.appearance),
                  for (final SegmentItem<T> item in widget.items)
                    _cell(item, prefix),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(SegmentItem<T> item, String? prefix) {
    final Widget cell = _SegmentCell(
      key: prefix == null ? null : Segment.keyOf(prefix, item.value),
      label: item.label,
      icon: item.icon,
      count: item.count,
      appearance: widget.appearance,
      selected: item.value == widget.selected,
      enabled: item.enabled && item.seam == null,
      labelStyle: item.labelStyle,
      pillPadding: widget.pillPadding,
      slide: _slide,
      ink: () => _inkAt(item.value, widget.selected, _slide.value),
      onTap: () => _pick(item.value),
    );
    final Seam? seam = item.seam;
    return seam == null ? cell : SeamGate(seam: seam, child: cell);
  }
}

Color _lineOf(ThemeData theme) =>
    theme.dividerTheme.color ?? theme.dividerColor;

/// The pill or underline under the selected label of a [Segment].
///
/// A segment has exactly one, for as long as it lives: picking another value
/// moves and resizes this widget, it does not build a second.
class SegmentThumb extends StatelessWidget {
  /// Creates the thumb. [Segment] does; nothing else needs to.
  const SegmentThumb({this.appearance = SegmentAppearance.pill, super.key});

  /// Follows the track's appearance without changing its measured rectangle.
  final SegmentAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    if (appearance == SegmentAppearance.heading) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: tokens.znn,
              width: tokens.tabUnderlineThickness,
            ),
          ),
        ),
      );
    }
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        // The mockup's third card tone has no name in the theme. The hover
        // tint laid over the track lands within three steps of it in both
        // themes, and stays a step above the track if either is retuned.
        color: Color.alphaBlend(
          tokens.hover,
          theme.colorScheme.primaryContainer,
        ),
        shape: StadiumBorder(side: BorderSide(color: _lineOf(theme))),
      ),
    );
  }
}

class _SegmentCell extends StatefulWidget {
  const _SegmentCell({
    required this.label,
    required this.icon,
    required this.count,
    required this.appearance,
    required this.selected,
    required this.enabled,
    required this.labelStyle,
    required this.pillPadding,
    required this.slide,
    required this.ink,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final int? count;
  final SegmentAppearance appearance;
  final bool selected;
  final bool enabled;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? pillPadding;

  /// Ticks while the thumb moves, which is when [ink] changes.
  final Listenable slide;

  /// How lit the label is now, 0 dim to 1 full.
  final ValueGetter<double> ink;

  final VoidCallback onTap;

  @override
  State<_SegmentCell> createState() => _SegmentCellState();
}

class _SegmentCellState extends State<_SegmentCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final bool heading = widget.appearance == SegmentAppearance.heading;
    // Medium, the weight of the compact buttons: the mockup's segments take
    // whatever weight surrounds them, 600 in a card's header and 400 in a
    // settings row, and one control cannot be both.
    final TextStyle style =
        widget.labelStyle ??
        (heading ? tokens.bodyText : theme.textTheme.bodyMedium!).copyWith(
          fontWeight: FontWeight.w500,
        );
    final Color lit = style.color ?? theme.colorScheme.onSurface;
    final Color dim = heading
        ? tokens.dim
        : theme.textTheme.titleMedium?.color ?? tokens.faint;
    final IconData? icon = widget.icon;
    final int? count = widget.count;

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      enabled: widget.enabled ? null : false,
      inMutuallyExclusiveGroup: true,
      label: count == null ? widget.label : '${widget.label}, $count',
      onTap: widget.enabled ? widget.onTap : null,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: !widget.enabled
            ? SystemMouseCursors.basic
            : widget.selected
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: DecoratedBox(
            // Not on the selected one: the thumb is already there, and a
            // tint over it would read as a third state.
            decoration: heading
                ? BoxDecoration(
                    color: _hovered && !widget.selected ? tokens.hover : null,
                  )
                : ShapeDecoration(
                    color: _hovered && !widget.selected ? tokens.hover : null,
                    shape: const StadiumBorder(),
                  ),
            child: Padding(
              padding: heading
                  ? tokens.tabPadding.add(
                      EdgeInsets.only(bottom: tokens.tabUnderlineThickness),
                    )
                  : widget.pillPadding ?? _kSegmentPadding,
              // Sized to the label when the row asks what it needs, centred
              // when the row hands it a taller or a narrower box.
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: AnimatedBuilder(
                  animation: widget.slide,
                  builder: (BuildContext context, Widget? _) {
                    final TextStyle inked = style.copyWith(
                      color: Color.lerp(dim, lit, widget.ink()),
                    );
                    if (icon == null && count == null) {
                      return Text(
                        widget.label,
                        style: inked,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      );
                    }
                    // One paragraph and not a Row: a paragraph narrower
                    // than its icon is clipped, a Row reports an overflow.
                    // The paragraph also puts the icon on the leading side
                    // by itself under a right-to-left interface.
                    return Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          if (icon != null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: _kIconGap,
                                ),
                                child: Icon(
                                  icon,
                                  size: _kIconSize,
                                  color: inked.color,
                                ),
                              ),
                            ),
                          TextSpan(text: widget.label),
                          if (count != null && heading)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: SizedBox(
                                width:
                                    tokens.tabCountGap +
                                    tokens.tabCountPadding.start,
                              ),
                            ),
                          if (count != null)
                            TextSpan(
                              text: heading ? '$count' : ' $count',
                              style: tokens.dataText.copyWith(
                                fontSize: heading ? 11 : inked.fontSize,
                                fontWeight: inked.fontWeight,
                                height: inked.height,
                                letterSpacing: inked.letterSpacing,
                                color: heading ? tokens.faint : inked.color,
                              ),
                            ),
                          if (count != null && heading)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: SizedBox(
                                width: tokens.tabCountPadding.end,
                              ),
                            ),
                        ],
                      ),
                      style: inked,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the segments out in a row, each as wide as it asks, and the thumb
/// over the selected one.
///
/// The first child is the thumb; the rest are the segments in order. It is
/// a render object and not a `Stack` with an `AnimatedPositioned` because
/// the thumb's place is the segments' measured rectangles, which a widget
/// only learns a frame late: here they are known in the same layout pass, so
/// a label that changes length, a new text scale or a new direction moves
/// the thumb with it and never leaves it behind for a frame.
class _SegmentRow extends MultiChildRenderObjectWidget {
  const _SegmentRow({
    required this.selectedIndex,
    required this.slide,
    required this.textDirection,
    required this.gap,
    required this.minHeight,
    required super.children,
  });

  final int selectedIndex;
  final Animation<double> slide;
  final TextDirection textDirection;
  final double gap;
  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSegmentRow(
    selectedIndex: selectedIndex,
    slide: slide,
    textDirection: textDirection,
    gap: gap,
    minHeight: minHeight,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSegmentRow renderObject,
  ) {
    renderObject
      ..selectedIndex = selectedIndex
      ..slide = slide
      ..textDirection = textDirection
      ..gap = gap
      ..minHeight = minHeight;
  }
}

class _SegmentParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSegmentRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SegmentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SegmentParentData> {
  _RenderSegmentRow({
    required this._selectedIndex,
    required this._slide,
    required this._textDirection,
    required this._gap,
    required this._minHeight,
  });

  /// Where the thumb was last laid out, and where the slide under way set
  /// off from. Rectangles and not indices: a pick made mid-slide starts
  /// from between two segments.
  Rect? _thumbRect;
  Rect? _slideFrom;

  int get selectedIndex => _selectedIndex;
  int _selectedIndex;
  set selectedIndex(int value) {
    if (value == _selectedIndex) {
      return;
    }
    _selectedIndex = value;
    _slideFrom = _thumbRect;
    markNeedsLayout();
  }

  Animation<double> get slide => _slide;
  Animation<double> _slide;
  set slide(Animation<double> value) {
    if (value == _slide) {
      return;
    }
    if (attached) {
      _slide.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _slide = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    // The row mirrors in one step: a slide across it would be motion that
    // no pick asked for.
    _slideFrom = null;
    markNeedsLayout();
  }

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double get minHeight => _minHeight;
  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _slide.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _slide.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentParentData) {
      child.parentData = _SegmentParentData();
    }
  }

  List<RenderBox> get _segments {
    final List<RenderBox> segments = <RenderBox>[];
    RenderBox? child = firstChild == null ? null : childAfter(firstChild!);
    while (child != null) {
      segments.add(child);
      child = childAfter(child);
    }
    return segments;
  }

  double _gapFor(int count, BoxConstraints constraints) =>
      count < 2 ? 0 : math.min(_gap, constraints.maxWidth / (count - 1));

  /// The size of each segment under [constraints]: what its label asks for,
  /// or the same share less of each where the labels do not fit, and one
  /// height for all. A hovered pill a pixel shorter than its neighbour
  /// shows.
  ///
  /// Measured dry, so that each segment is laid out once per pass and not
  /// once to be asked and once to be told.
  List<Size> _measure(List<RenderBox> segments, BoxConstraints constraints) {
    final BoxConstraints natural = BoxConstraints(
      maxHeight: constraints.maxHeight,
    );
    final List<Size> asked = <Size>[
      for (final RenderBox child in segments) child.getDryLayout(natural),
    ];
    double width = 0;
    double height = _minHeight == 0
        ? 0
        : constraints.constrainHeight(_minHeight);
    for (final Size size in asked) {
      width += size.width;
      height = math.max(height, size.height);
    }
    final double available = math.max(
      0,
      constraints.maxWidth -
          _gapFor(segments.length, constraints) *
              math.max(0, segments.length - 1),
    );
    final double squeeze = width > available ? available / width : 1;
    return <Size>[
      for (final Size size in asked) Size(size.width * squeeze, height),
    ];
  }

  Size _sizeOf(List<Size> sizes, BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          sizes.fold<double>(0, (double sum, Size size) => sum + size.width) +
              _gapFor(sizes.length, constraints) *
                  math.max(0, sizes.length - 1),
          sizes.isEmpty ? 0 : sizes.first.height,
        ),
      );

  @override
  double computeMinIntrinsicWidth(double height) =>
      _segments.fold<double>(
        0,
        (double sum, RenderBox child) =>
            sum + child.getMinIntrinsicWidth(height),
      ) +
      _gap * math.max(0, _segments.length - 1);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _segments.fold<double>(
        0,
        (double sum, RenderBox child) =>
            sum + child.getMaxIntrinsicWidth(height),
      ) +
      _gap * math.max(0, _segments.length - 1);

  @override
  double computeMinIntrinsicHeight(double width) => _segments.fold(
    _minHeight,
    (double tallest, RenderBox child) =>
        math.max(tallest, child.getMinIntrinsicHeight(double.infinity)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _segments.fold(
    _minHeight,
    (double tallest, RenderBox child) =>
        math.max(tallest, child.getMaxIntrinsicHeight(double.infinity)),
  );

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final List<RenderBox> segments = _segments;
    final List<Size> sizes = _measure(segments, constraints);
    double? highest;
    for (int i = 0; i < segments.length; i++) {
      final double? distance = segments[i].getDryBaseline(
        BoxConstraints.tight(sizes[i]),
        baseline,
      );
      if (distance != null) {
        highest = highest == null ? distance : math.min(highest, distance);
      }
    }
    return highest;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _sizeOf(_measure(_segments, constraints), constraints);

  @override
  void performLayout() {
    final RenderBox? thumb = firstChild;
    if (thumb == null) {
      size = constraints.smallest;
      return;
    }
    final List<RenderBox> segments = _segments;
    final List<Size> sizes = _measure(segments, constraints);
    size = _sizeOf(sizes, constraints);

    final bool rtl = _textDirection == TextDirection.rtl;
    final List<Rect> rects = <Rect>[];
    final double spacing = _gapFor(segments.length, constraints);
    double edge = rtl ? size.width : 0;
    for (int i = 0; i < segments.length; i++) {
      segments[i].layout(BoxConstraints.tight(sizes[i]));
      if (rtl) {
        edge -= sizes[i].width;
      }
      final Offset offset = Offset(edge, 0);
      (segments[i].parentData! as _SegmentParentData).offset = offset;
      rects.add(offset & sizes[i]);
      edge += rtl ? -spacing : sizes[i].width + spacing;
    }

    // With nothing selected the thumb closes on the spot it held, and it
    // opens again on the spot it is given.
    final Rect? target = _selectedIndex >= 0 && _selectedIndex < rects.length
        ? rects[_selectedIndex]
        : null;
    final Rect? from = (_slideFrom?.isEmpty ?? true) ? null : _slideFrom;
    final Rect end = target ?? _closed(from ?? Rect.zero);
    final Rect rect = Rect.lerp(from ?? _closed(end), end, _slide.value)!;
    thumb.layout(BoxConstraints.tight(rect.size));
    (thumb.parentData! as _SegmentParentData).offset = rect.topLeft;
    _thumbRect = rect;
  }

  static Rect _closed(Rect rect) =>
      Rect.fromCenter(center: rect.center, width: 0, height: rect.height);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    while (child != null) {
      // A closed thumb is not drawn: a stadium of no width still strokes
      // its line.
      if (!child.size.isEmpty) {
        context.paintChild(
          child,
          (child.parentData! as _SegmentParentData).offset + offset,
        );
      }
      child = childAfter(child);
    }
  }
}
