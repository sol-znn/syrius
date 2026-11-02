import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The mockup's status pulse: expand the halo during the first 70 percent,
/// then hold it transparent for the rest of the 2.4 second cycle.
class StatusDot extends StatefulWidget {
  /// Creates a status marker. The fill can change without restarting its clock.
  const StatusDot({required this.color, this.fillKey, super.key});

  /// The current connection or publication state, independent of money values.
  final Color color;

  /// Identifies the solid dot separately from its larger painted halo.
  final Key? fillKey;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // Motion communicates current work even when the OS disables animation.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Duration duration = AppTokens.of(context).statusPulseDuration;
    if (_clock.duration != duration) {
      _clock.duration = duration;
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (BuildContext context, Widget? child) {
          final double progress = tokens.ease.transform(
            (_clock.value / 0.7).clamp(0.0, 1.0),
          );
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                // CSS uses the brand halo for every .dot.live; the solid
                // centre carries blue waiting, amber behind or error state.
                BoxShadow(
                  color: tokens.znn.withValues(alpha: 0.6 * (1 - progress)),
                  spreadRadius: tokens.statusDotHalo * progress,
                ),
              ],
            ),
            child: child,
          );
        },
        child: AnimatedContainer(
          key: widget.fillKey,
          duration: Durations.short3,
          curve: tokens.ease,
          width: tokens.statusDotSize,
          height: tokens.statusDotSize,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
