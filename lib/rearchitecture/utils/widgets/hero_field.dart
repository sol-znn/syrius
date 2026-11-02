import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/shaders/shader_clock.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';

/// The asset the field is drawn by. Listed under `flutter: shaders:`.
const String kHeroFieldShader = 'assets/shaders/hero_field.frag';

/// A slow field of blue, pink and green light under the card colour: the
/// surface behind the Home hero.
///
/// It fills whatever box it is given and draws nothing until its shader has
/// loaded, so the card is simply its own colour for the first frames. Put it
/// under the content in a `Stack`, inside the card's clip.
///
/// It repaints every frame while it is on screen, so it sits in its own
/// layer and takes nothing around it along. A hidden page, an unfocused
/// window or a frosted overlay holds the field on its current frame.
class HeroField extends StatefulWidget {
  /// Creates the field.
  const HeroField({this.strength, super.key});

  /// How far a light pulls the card colour at its centre, 0 to 1. Null
  /// takes the value for the theme: less on a white card, where the same
  /// pull reads as a stain.
  final double? strength;

  @override
  State<HeroField> createState() => _HeroFieldState();
}

class _HeroFieldState extends State<HeroField>
    with SingleTickerProviderStateMixin {
  late final ShaderClock _clock;

  @override
  void initState() {
    super.initState();
    _clock = ShaderClock(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.updateVisibility(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return RepaintBoundary(
      child: ShaderBuilder(
        assetKey: kHeroFieldShader,
        (BuildContext context, ui.FragmentShader shader, Widget? child) {
          // An unavailable shader has no frames worth scheduling.
          _clock.active = true;
          return CustomPaint(
            painter: _HeroFieldPainter(
              shader: shader,
              seconds: _clock,
              // The card colour, as `Panel` paints it.
              base: theme.colorScheme.primary,
              strength: widget.strength ?? (dark ? 0.16 : 0.07),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _HeroFieldPainter extends CustomPainter {
  _HeroFieldPainter({
    required this.shader,
    required this.seconds,
    required this.base,
    required this.strength,
  }) : super(repaint: seconds);

  final ui.FragmentShader shader;
  final ValueListenable<double> seconds;
  final Color base;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    // Floats in the order the shader declares them; a vec3 takes three.
    int i = 0;
    void rgb(Color color) {
      shader
        ..setFloat(i++, color.r)
        ..setFloat(i++, color.g)
        ..setFloat(i++, color.b);
    }

    shader
      ..setFloat(i++, size.width) // u_size
      ..setFloat(i++, size.height)
      ..setFloat(i++, seconds.value); // u_time
    rgb(base); // u_base
    rgb(AppColors.qsrColor); // u_a
    rgb(AppColors.plasmaPink); // u_b
    rgb(AppColors.znnColor); // u_c
    shader.setFloat(i++, strength); // u_strength
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_HeroFieldPainter old) =>
      old.base != base || old.strength != strength || old.shader != shader;
}
