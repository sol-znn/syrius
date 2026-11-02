import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/shaders/shader_clock.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';

/// The asset the meter's fill is drawn by. Listed under `flutter: shaders:`.
const String kPlasmaFlowShader = 'assets/shaders/plasma_flow.frag';

/// A bar that fills with a share of plasma, with light moving through the
/// fill, and that moves to a new level instead of jumping to it.
///
/// The fill is QSR's brand blue in both themes; the light in it is tinted
/// with the plasma pink. Until the shader has loaded, and wherever it cannot
/// load, the bar is the same fill painted flat: the level is information and
/// must never wait for an ornament.
///
/// The light moves while [active], inside its own layer. One clock drives
/// both that flow and the finite level easing. A hidden page, an unfocused
/// window or a frosted overlay holds the current frame.
class PlasmaMeter extends StatefulWidget {
  /// Creates a meter filled to [value], 0 to 1.
  const PlasmaMeter({
    required this.value,
    required this.trackColor,
    this.active = false,
    this.height = 6,
    super.key,
  });

  /// The level, 0 to 1.
  final double value;

  /// The bar behind the fill.
  final Color trackColor;

  /// Whether plasma is being generated. An idle meter holds its light.
  final bool active;

  /// The bar's thickness. Its ends are rounded to half of it.
  final double height;

  @override
  State<PlasmaMeter> createState() => _PlasmaMeterState();
}

class _PlasmaMeterState extends State<PlasmaMeter>
    with SingleTickerProviderStateMixin {
  late final ShaderClock _clock;
  late final ValueNotifier<_MeterFrame> _frame;
  bool _shaderReady = false;
  bool _changing = false;
  double _from = 0;
  double _target = 0;
  double _changeStart = 0;
  double _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _target = widget.value.clamp(0, 1).toDouble();
    _frame = ValueNotifier<_MeterFrame>(_MeterFrame(_target, 0));
    _clock = ShaderClock(vsync: this)..addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.updateVisibility(context);
  }

  @override
  void didUpdateWidget(PlasmaMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double target = widget.value.clamp(0, 1).toDouble();
    if (target != _target) {
      _from = _frame.value.level;
      _target = target;
      _changeStart = _clock.value;
      _changing = _from != _target;
    }
    _sync();
  }

  void _sync() {
    _clock.active = _changing || (_shaderReady && widget.active && _target > 0);
  }

  void _onTick() {
    final double now = _clock.value;
    final double delta = now - _lastTick;
    _lastTick = now;
    double level = _frame.value.level;
    if (_changing) {
      final double duration =
          Durations.long2.inMicroseconds / Duration.microsecondsPerSecond;
      final double t = ((now - _changeStart) / duration).clamp(0, 1);
      level =
          _from + (_target - _from) * Easing.emphasizedDecelerate.transform(t);
      if (t >= 1) {
        level = _target;
        _changing = false;
      }
    }
    final double seconds =
        _frame.value.seconds + (widget.active && _shaderReady ? delta : 0);
    if (level != _frame.value.level || seconds != _frame.value.seconds) {
      _frame.value = _MeterFrame(level, seconds);
    }
    _sync();
  }

  @override
  void dispose() {
    _clock
      ..removeListener(_onTick)
      ..dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection direction = Directionality.of(context);
    return Semantics(
      value: '${(widget.value.clamp(0, 1) * 100).round()}%',
      child: RepaintBoundary(
        child: ShaderBuilder(
          assetKey: kPlasmaFlowShader,
          (BuildContext context, ui.FragmentShader shader, Widget? child) {
            _shaderReady = true;
            _sync();
            return _buildBar(shader, direction);
          },
          child: _buildBar(null, direction),
        ),
      ),
    );
  }

  Widget _buildBar(ui.FragmentShader? shader, TextDirection direction) =>
      CustomPaint(
        painter: _PlasmaMeterPainter(
          shader: shader,
          frame: _frame,
          trackColor: widget.trackColor,
          direction: direction,
        ),
        child: SizedBox(height: widget.height, width: double.infinity),
      );
}

/// The level and flow share one repaint notification without rebuilding
/// the surrounding page on every shader frame.
class _MeterFrame {
  const _MeterFrame(this.level, this.seconds);

  final double level;
  final double seconds;
}

class _PlasmaMeterPainter extends CustomPainter {
  _PlasmaMeterPainter({
    required this.shader,
    required this.frame,
    required this.trackColor,
    required this.direction,
  }) : super(repaint: frame);

  /// Null until the shader has loaded: the bar is then painted flat.
  final ui.FragmentShader? shader;
  final ValueListenable<_MeterFrame> frame;
  final Color trackColor;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final double value = frame.value.level;
    final ui.FragmentShader? shader = this.shader;
    if (shader == null) {
      final double width = size.width * value;
      final Rect fill = direction == TextDirection.ltr
          ? Rect.fromLTWH(0, 0, width, size.height)
          : Rect.fromLTWH(size.width - width, 0, width, size.height);
      canvas
        ..save()
        ..clipRRect(bar)
        ..drawRect(Offset.zero & size, Paint()..color = trackColor)
        ..drawRect(fill, Paint()..color = AppColors.qsrColor)
        ..restore();
      return;
    }
    // Floats in the order the shader declares them.
    int i = 0;
    shader
      ..setFloat(i++, size.width) // u_size
      ..setFloat(i++, size.height)
      ..setFloat(i++, frame.value.seconds) // u_time
      ..setFloat(i++, value) // u_fill
      ..setFloat(i++, direction == TextDirection.ltr ? 1 : -1) // u_dir
      ..setFloat(i++, AppColors.qsrColor.r) // u_base
      ..setFloat(i++, AppColors.qsrColor.g)
      ..setFloat(i++, AppColors.qsrColor.b)
      ..setFloat(i++, AppColors.plasmaPink.r) // u_hot
      ..setFloat(i++, AppColors.plasmaPink.g)
      ..setFloat(i++, AppColors.plasmaPink.b)
      ..setFloat(i++, trackColor.r) // u_track
      ..setFloat(i++, trackColor.g)
      ..setFloat(i++, trackColor.b)
      ..setFloat(i++, trackColor.a);
    canvas.drawRRect(bar, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PlasmaMeterPainter old) =>
      old.frame != frame ||
      old.trackColor != trackColor ||
      old.direction != direction ||
      old.shader != shader;
}
