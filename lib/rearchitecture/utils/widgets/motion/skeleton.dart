import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// How far the band of light travels in one pass, in logical pixels: about
/// the width of the window.
const double _kSpan = 1200;

/// How long one pass takes, in milliseconds.
const double _kPass = 1400;

/// The rest before the next band sets off, in milliseconds.
const double _kRest = 400;

/// The width of the band, edge to edge. Its light rises and falls as a
/// cosine, so the bright part is about half of this.
const double _kBand = 240;

/// The band's speed, in logical pixels a millisecond.
const double _kSpeed = _kSpan / _kPass;

/// The distance from one band to the next.
///
/// The sweep is a wave, not one band on a track of fixed length: a band
/// every this many pixels, all moving at [_kSpeed]. A window up to about
/// 1,300 px wide has one in it at a time and the rest between them; a wider
/// one has no stretch on its far side that the light never reaches.
const double _kWavelength = _kSpeed * (_kPass + _kRest);

/// How much of its ink a bar is drawn in. The fade this replaced breathed
/// between 0.35 and 0.8; a bar that holds still stays at the low end, where
/// it is about as strong as the faint text beside it.
const double _kInk = 0.35;

/// How much the middle of the band adds to [_kInk], or takes from it. On
/// screen that is 6 to 7% of the way from black to white in either theme: a
/// passing light, not a flash.
const double _kLift = 0.07;

/// The light across the band, in sixths of [_kBand], and none from there to
/// the next band: a raised cosine, which has no edge to catch the eye where
/// a plain ramp up and down has three.
const List<double> _kProfile = <double>[0, 0.25, 0.75, 1, 0.75, 0.25, 0, 0];

const double _kSixth = _kBand / _kWavelength / 6;

/// Where each value of [_kProfile] falls, as a share of [_kWavelength].
const List<double> _kStops = <double>[
  0,
  _kSixth,
  2 * _kSixth,
  3 * _kSixth,
  4 * _kSixth,
  5 * _kSixth,
  6 * _kSixth,
  1,
];

/// The one clock behind every [Skeleton] on screen.
///
/// Each bar places the band from this clock and from where the bar is in
/// the window, so the light is at one place for all of them: a bar further
/// along is lit later, and two cards side by side read as one surface under
/// one light. A ticker in each bar would start when its card did, and the
/// page would blink out of step.
///
/// The ticker exists only while a mounted bar holds the clock. A wallet
/// with nothing loading schedules no frames for it.
class _SweepClock extends ChangeNotifier {
  _SweepClock._();

  static final _SweepClock instance = _SweepClock._();

  Ticker? _ticker;
  int _holders = 0;

  /// How far the light has come since the clock started, less the whole
  /// wavelengths in it.
  double get travel => _travel;
  double _travel = 0;

  /// Keeps the clock running until [release]. The first holder starts it,
  /// with the band just off the edge of the window.
  void hold() {
    if (_holders++ == 0) {
      _ticker = Ticker(_onTick, debugLabel: 'skeleton sweep')..start();
    }
  }

  /// Gives up one [hold]. The last one out stops the clock.
  ///
  /// The holders are counted here and not read off the listeners: a rebuild
  /// swaps a bar's painter, the old one stops listening before the new one
  /// starts, and a lone bar would send the band back to the edge each time.
  void release() {
    assert(_holders > 0, 'released more often than held');
    if (--_holders == 0) {
      _ticker?.dispose();
      _ticker = null;
      _travel = 0;
    }
  }

  void _onTick(Duration elapsed) {
    _travel = elapsed.inMicroseconds / 1000 * _kSpeed % _kWavelength;
    notifyListeners();
  }
}

/// A placeholder for a line of content that is still loading: a rounded bar
/// that a band of light sweeps across.
///
/// A loading state should not look like an empty one or a broken one. A
/// spinner in the middle of a card says "wait" but not what for; bars where
/// the rows will be say what is coming and keep the card's height.
///
/// The light crosses every bar on the page as one sweep, from the start of
/// the line to its end. Each bar is its own layer, so the sweep repaints
/// the bars and nothing around them.
class Skeleton extends StatefulWidget {
  /// Creates a bar. Without a [width] it fills the width it is given.
  const Skeleton({this.width, this.height = 12, this.radius = 4, super.key});

  /// The bar's width, or null to fill.
  final double? width;

  /// The bar's height: about the cap height of the text it stands for.
  final double height;

  /// The corner radius.
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> {
  bool _holding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A bar on a page under another route is not shown. TickerMode is how
    // the framework says so, and such a bar must not keep the clock alive.
    _hold(TickerMode.valuesOf(context).enabled);
  }

  void _hold(bool wanted) {
    if (wanted == _holding) return;
    _holding = wanted;
    if (wanted) {
      _SweepClock.instance.hold();
    } else {
      _SweepClock.instance.release();
    }
  }

  @override
  void dispose() {
    _hold(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A loading bar stands in for content. Outline now carries the mockup's
    // quiet border colour; using it as ink makes the moving band disappear.
    final Color ink = Theme.of(context).colorScheme.onSurface;
    // The band is lighter than the bar in both themes. Light ink gets
    // lighter with more of it, dark ink with less: there the bar thins
    // toward the card as the light passes.
    final bool lightInk =
        ThemeData.estimateBrightnessForColor(ink) == Brightness.light;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BarPainter(
          context: context,
          clock: _SweepClock.instance,
          color: _inked(ink, _kInk),
          highlight: _inked(ink, lightInk ? _kInk + _kLift : _kInk - _kLift),
          radius: widget.radius,
          rightToLeft: Directionality.maybeOf(context) == TextDirection.rtl,
        ),
        // The size the decorated Container here used to take: the width and
        // height given, all of a bounded axis that has none, and nothing of
        // an unbounded one.
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: const LimitedBox(
            maxWidth: 0,
            maxHeight: 0,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// [ink] at [share] of its own opacity.
Color _inked(Color ink, double share) => ink.withValues(alpha: ink.a * share);

/// Paints one bar, and on it whatever part of the band is over it.
///
/// It listens to the clock itself, so a tick repaints the bar without
/// rebuilding a widget. The fill is a gradient on the bar's own paint: no
/// mask and no offscreen layer.
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.context,
    required this.clock,
    required this.color,
    required this.highlight,
    required this.radius,
    required this.rightToLeft,
  }) : super(repaint: clock);

  /// The bar's element. Where the bar is in the window is read from its
  /// render object at paint time: a painter is handed a size, not a place.
  final BuildContext context;

  final _SweepClock clock;
  final Color color;
  final Color highlight;
  final double radius;
  final bool rightToLeft;

  late final List<Color> _colors = <Color>[
    for (final double light in _kProfile) Color.lerp(color, highlight, light)!,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final double? band = _bandStart(size.width);
    if (band == null) {
      paint.color = color;
    } else {
      // One wavelength of the wave, repeated, so a bar wider than a
      // wavelength shows the next band as well.
      paint.shader = ui.Gradient.linear(
        Offset(band, 0),
        Offset(band + _kWavelength, 0),
        _colors,
        _kStops,
        TileMode.repeated,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  /// The near edge of the band, in the bar's own coordinates, or null while
  /// no band is over the bar. That is most frames for a short bar, and they
  /// are painted in the flat colour without a shader.
  double? _bandStart(double width) {
    if (!context.mounted) return null;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final double x = box.localToGlobal(Offset.zero).dx;
    // Against the direction of reading the wave runs the other way.
    final double travel = rightToLeft ? -clock.travel : clock.travel;
    // The one band whose far edge is at or past the bar's left side.
    final double start = (travel - x) % _kWavelength - _kBand;
    return start < width ? start : null;
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color ||
      old.highlight != highlight ||
      old.radius != radius ||
      old.rightToLeft != rightToLeft ||
      old.clock != clock ||
      old.context != context;
}

/// Rows of [Skeleton] bars, for a list or table that is loading.
class SkeletonRows extends StatelessWidget {
  /// Creates [rows] bars, [gap] apart, the last one shorter.
  const SkeletonRows({this.rows = 3, this.gap = 14, super.key});

  /// How many bars.
  final int rows;

  /// The space between them.
  final double gap;

  @override
  Widget build(BuildContext context) {
    // No layer of its own: each bar has one.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < rows; i++) ...<Widget>[
          if (i > 0) SizedBox(height: gap),
          FractionallySizedBox(
            widthFactor: i == rows - 1 ? 0.6 : 1,
            child: const Skeleton(),
          ),
        ],
      ],
    );
  }
}
