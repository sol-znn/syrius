import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The tint at its strongest, as the alpha of [ValueFlash.color].
const double _kPeak = 0.26;

/// The share of the flash spent rising to the peak; the rest fades.
const double _kAttack = 0.12;

/// Tints [child] once, briefly, when [value] changes.
///
/// A figure that updates in place gives no sign that it did; this is the
/// sign. It reports a change and nothing else: no flash on the first build,
/// none while [value] stays equal (`==`), one for each change.
///
/// ```dart
/// ValueFlash(
///   value: balance,
///   child: AmountText(balance, decimals: 8, style: style),
/// )
/// ```
///
/// [value] is only compared, never shown: pass whatever the child displays
/// (a `BigInt`, an `int`, a `String`, a record of several). A change from
/// or to `null` counts as a change, so build the widget once there is
/// something to show if a loading state should not flash.
///
/// The tint is painted behind the child and a few pixels past its edges. It
/// takes no space, so wrapping a value does not move the layout, and it
/// repaints without rebuilding [child].
class ValueFlash extends StatefulWidget {
  /// Creates a flash round [child] that fires when [value] changes.
  const ValueFlash({
    required this.value,
    required this.child,
    this.color,
    this.duration = const Duration(milliseconds: 1200),
    super.key,
  });

  /// What [child] shows. A flash fires when this stops being equal to what
  /// it was at the last build.
  final Object? value;

  /// The widget showing the value.
  final Widget child;

  /// The tint. The flash peaks at about a quarter of its opacity. The
  /// theme's ZNN ink when null: the brand green is too pale to show on a
  /// white card.
  final Color? color;

  /// How long one flash lasts, start to gone.
  final Duration duration;

  @override
  State<ValueFlash> createState() => _ValueFlashState();
}

class _ValueFlashState extends State<ValueFlash>
    with SingleTickerProviderStateMixin {
  // At rest the controller sits at 1, where the painter draws nothing.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
    // This tint reports a changed value, so it keeps its full duration even
    // when the platform turns animation effects off.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(ValueFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.value != oldWidget.value) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FlashPainter(
        _controller,
        widget.color ?? AppTokens.of(context).znnInk,
      ),
      child: widget.child,
    );
  }
}

class _FlashPainter extends CustomPainter {
  _FlashPainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.value;
    if (t <= 0 || t >= 1) return;
    final double strength = t < _kAttack
        ? t / _kAttack
        : 1 - Curves.easeInOut.transform((t - _kAttack) / (1 - _kAttack));
    canvas.drawRRect(
      RRect.fromLTRBR(
        -4,
        -1,
        size.width + 4,
        size.height + 1,
        const Radius.circular(4),
      ),
      Paint()..color = color.withValues(alpha: _kPeak * strength),
    );
  }

  @override
  bool shouldRepaint(_FlashPainter old) =>
      old.progress != progress || old.color != color;
}
