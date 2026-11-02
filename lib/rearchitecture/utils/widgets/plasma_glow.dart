import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/shaders/shader_clock.dart';

const String _kShader = 'assets/shaders/heatmap.frag';
const String _kTexture = 'assets/images/plasma_heatmap.png';

/// How fast heat rises, as the demo this comes from sets it: shader time
/// advances by 0.2 for each elapsed millisecond.
const double _kSpeed = 0.2;

/// The shader program and the bolt's texture, loaded once for the app.
class _PlasmaGlowAssets {
  _PlasmaGlowAssets(this.program, this.texture);

  final ui.FragmentProgram program;
  final ui.Image texture;

  static Future<_PlasmaGlowAssets>? _loading;

  static Future<_PlasmaGlowAssets> load() => _loading ??= _load();

  static Future<_PlasmaGlowAssets> _load() async {
    final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
      _kShader,
    );
    final ByteData bytes = await rootBundle.load(_kTexture);
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
    );
    try {
      final ui.FrameInfo frame = await codec.getNextFrame();
      return _PlasmaGlowAssets(program, frame.image);
    } finally {
      codec.dispose();
    }
  }
}

/// The Syrius plasma mark, glowing: heat rising through the lightning bolt.
///
/// A fragment shader (see `assets/shaders/heatmap.frag`) over a texture of
/// the bolt made by `tool/heatmap_texture.dart`. While [active] the heat
/// moves; otherwise the mark holds still on the frame it reached, so an idle
/// wallet does not repaint sixty times a second for an ornament.
class PlasmaGlow extends StatefulWidget {
  /// Creates the mark at [size] logical pixels square.
  const PlasmaGlow({
    required this.size,
    this.active = true,
    this.innerGlow = 0.5,
    this.outerGlow = 0.3,
    this.contour = 0.5,
    super.key,
  });

  /// The side of the square the mark is drawn in. The bolt itself fills
  /// about 57% of it; the rest is room for the glow.
  final double size;

  /// Whether the heat moves.
  final bool active;

  /// Heat inside the mark, 0 to 1.
  final double innerGlow;

  /// Heat spilling outside the mark, 0 to 0.5.
  final double outerGlow;

  /// Heat along the mark's edge, 0 to 1.
  final double contour;

  @override
  State<PlasmaGlow> createState() => _PlasmaGlowState();
}

class _PlasmaGlowState extends State<PlasmaGlow>
    with SingleTickerProviderStateMixin {
  late final ShaderClock _clock;
  ui.FragmentShader? _shader;
  ui.Image? _texture;

  @override
  void initState() {
    super.initState();
    _clock = ShaderClock(vsync: this);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.updateVisibility(context);
  }

  Future<void> _load() async {
    try {
      final _PlasmaGlowAssets assets = await _PlasmaGlowAssets.load();
      if (!mounted) return;
      setState(() {
        // One shader object for the life of the widget, reused each frame.
        _shader = assets.program.fragmentShader();
        _texture = assets.texture;
      });
      _sync();
    } on Object {
      // The mark is an ornament. Without the shader the widget stays empty
      // and whatever is around it still works.
    }
  }

  @override
  void didUpdateWidget(PlasmaGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _clock.active = widget.active && _shader != null;
  }

  @override
  void dispose() {
    _clock.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentShader? shader = _shader;
    final ui.Image? texture = _texture;
    return SizedBox.square(
      dimension: widget.size,
      child: shader == null || texture == null
          ? null
          // Its own layer: the mark repaints every frame while active, and
          // must not take the page around it along.
          : RepaintBoundary(
              child: CustomPaint(
                painter: _PlasmaGlowPainter(
                  shader: shader,
                  texture: texture,
                  time: _clock,
                  innerGlow: widget.innerGlow,
                  outerGlow: widget.outerGlow,
                  contour: widget.contour,
                ),
              ),
            ),
    );
  }
}

class _PlasmaGlowPainter extends CustomPainter {
  _PlasmaGlowPainter({
    required this.shader,
    required this.texture,
    required this.time,
    required this.innerGlow,
    required this.outerGlow,
    required this.contour,
  }) : super(repaint: time);

  final ui.FragmentShader shader;
  final ui.Image texture;
  final ValueListenable<double> time;
  final double innerGlow;
  final double outerGlow;
  final double contour;

  @override
  void paint(Canvas canvas, Size size) {
    // Float uniforms in the order the shader declares them; the sampler has
    // its own index.
    shader
      ..setImageSampler(0, texture)
      ..setFloat(0, size.width) // u_size
      ..setFloat(1, size.height)
      ..setFloat(2, time.value * 1000 * _kSpeed) // u_time
      ..setFloat(3, 0) // u_angle
      ..setFloat(4, 0) // u_noise
      ..setFloat(5, innerGlow) // u_innerGlow
      ..setFloat(6, outerGlow) // u_outerGlow
      ..setFloat(7, contour); // u_contour
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PlasmaGlowPainter old) =>
      old.innerGlow != innerGlow ||
      old.outerGlow != outerGlow ||
      old.contour != contour ||
      old.texture != texture;
}
