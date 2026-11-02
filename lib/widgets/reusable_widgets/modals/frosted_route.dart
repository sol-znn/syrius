import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The blur behind a dialog at rest, in logical pixels. The mockup's overlay
/// is `backdrop-filter: blur(6px)`, and a CSS blur radius is a sigma.
const double kFrostSigma = 6;

/// How much of the scrim colour lies over the blurred page at rest. The
/// mockup uses `rgba(0, 0, 0, .35)` in both themes.
const double kFrostTintOpacity = 0.35;

/// The tint of the frost under the theme in force: the theme's scrim at
/// [kFrostTintOpacity].
///
/// The light theme keeps a dark tint on purpose. A white one would wash the
/// page out to the dialog's own tone and the card would lose its edge.
Color frostTintOf(BuildContext context) => Theme.of(
  context,
).colorScheme.scrim.withValues(alpha: kFrostTintOpacity);

/// How many frosts are up, for whatever animates underneath one.
///
/// A backdrop blur is recomputed whenever the pixels under it change, so a
/// shader that keeps ticking behind a dialog costs a full-window blur per
/// frame for motion nobody can make out. A widget that runs its own ticker
/// can listen here and hold while [count] is above zero. Stop and restart
/// the ticker from the listener; do not call `setState` from it, since the
/// count can change while a route is being torn down.
abstract final class FrostHold {
  static final ValueNotifier<int> _count = ValueNotifier<int>(0);

  /// The number of frosts showing. Zero means nothing is covered.
  static ValueListenable<int> get count => _count;

  /// Notes one more frost. A [FrostedDialogRoute] does this by itself; an
  /// owner of a bare [FrostedBarrier] calls it when the barrier appears.
  static void acquire() => _count.value += 1;

  /// Takes back one [acquire].
  static void release() {
    if (_count.value > 0) {
      _count.value -= 1;
    }
  }
}

/// A blur and a tint over whatever is painted beneath, both scaled by
/// [animation]: nothing at 0, [sigma] and the whole [tint] at 1.
///
/// It fills the space it is given and takes no pointer events of its own;
/// [child] decides what a tap on it does. Always animates: nothing here
/// reads the reduced-motion setting.
class FrostedBarrier extends StatelessWidget {
  /// Creates a frost driven by [animation].
  const FrostedBarrier({
    required this.animation,
    this.sigma = kFrostSigma,
    this.tint,
    this.child,
    super.key,
  });

  /// 0 is the bare page, 1 the full frost. Any curve is the caller's.
  final Animation<double> animation;

  /// The blur at rest.
  final double sigma;

  /// The colour over the blur at rest, alpha included. Null takes
  /// [frostTintOf].
  final Color? tint;

  /// Laid over the frost, usually what catches the dismissing tap.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final Color tint = this.tint ?? frostTintOf(context);
    // The clip bounds the filter: without one a BackdropFilter blurs
    // everything up to the nearest enclosing clip, which may be the window.
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        child: child ?? const SizedBox.expand(),
        builder: (BuildContext context, Widget? child) {
          final double t = animation.value.clamp(0.0, 1.0);
          return BackdropFilter(
            // A zero blur is still a saved layer and a copy of the window.
            enabled: t > 0,
            filter: ImageFilter.blur(sigmaX: sigma * t, sigmaY: sigma * t),
            child: ColoredBox(
              color: tint.withValues(alpha: tint.a * t),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// A glass surface whose filter is clipped to the card it paints.
///
/// Dialogs, panels, menus and entry cards share this treatment. The caller
/// supplies its radius and blur when they differ from an ordinary dialog.
///
/// Set [grouped] only for non-overlapping surfaces over the same backdrop,
/// inside one [BackdropGroup]. Overlapping filters, such as a dialog and its
/// full-window barrier, must keep separate backdrop keys or their overlap
/// would receive only one of the filters.
class FrostedSurface extends StatelessWidget {
  /// Creates a bounded glass surface around [child].
  const FrostedSurface({
    required this.child,
    this.sigma,
    this.tint,
    this.borderRadius,
    this.grouped = false,
    super.key,
  }) : assert(
         sigma == null || (sigma >= 0 && sigma < double.infinity),
         'Blur must be finite and nonnegative.',
       );

  /// The content laid over the glass.
  final Widget child;

  /// Blur at rest. Null takes the dialog blur token.
  final double? sigma;

  /// The surface colour, including its glass opacity.
  final Color? tint;

  /// The boundary of the filter. Null takes the dialog radius token.
  final BorderRadiusGeometry? borderRadius;

  /// Whether to share the nearest [BackdropGroup]'s backdrop input.
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final double sigma = this.sigma ?? tokens.dialogBlur;
    final ImageFilter filter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    final Widget surface = ColoredBox(
      color: tint ?? tokens.glass,
      child: child,
    );
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(tokens.dialogRadius),
      child: grouped
          ? BackdropFilter.grouped(
              enabled: sigma > 0,
              filter: filter,
              child: surface,
            )
          : BackdropFilter(
              enabled: sigma > 0,
              filter: filter,
              child: surface,
            ),
    );
  }
}

/// A dialog route whose barrier is a [FrostedBarrier] that follows the
/// route's own animation, in and out.
///
/// The `filter` a [ModalRoute] can carry is applied at full strength for as
/// long as the route is up, so the page would snap to blurred and snap back.
/// Building the barrier here lets the blur ride the transition instead.
///
/// The route adds no movement to its page: `DialogCard` already rises.
class FrostedDialogRoute<T> extends RawDialogRoute<T> {
  /// Creates a route for [pageBuilder]. [barrierColor] is the tint at rest;
  /// null takes [frostTintOf] under the navigator's theme.
  FrostedDialogRoute({
    required super.pageBuilder,
    super.barrierDismissible,
    super.barrierLabel,
    super.barrierColor = null,
    this.sigma = kFrostSigma,
    super.transitionDuration,
    super.transitionBuilder,
    super.settings,
    super.requestFocus,
    super.anchorPoint,
    super.traversalEdgeBehavior,
    super.fullscreenDialog,
  });

  /// The blur at rest.
  final double sigma;

  bool _holding = false;

  @override
  AnimationController createAnimationController() => AnimationController(
    vsync: navigator!,
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    // The route owns the barrier's clock. Preserve its duration just as the
    // dialog's rise does, regardless of the system animation-effects flag.
    animationBehavior: AnimationBehavior.preserve,
  );

  void _release() {
    if (_holding) {
      _holding = false;
      FrostHold.release();
    }
  }

  @override
  void install() {
    super.install();
    _holding = true;
    FrostHold.acquire();
  }

  @override
  bool didPop(T? result) {
    final bool popped = super.didPop(result);
    if (popped) {
      // Let what is underneath move again while the blur clears, not after.
      _release();
    }
    return popped;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget buildModalBarrier() {
    return FrostedBarrier(
      animation: animation!.drive(CurveTween(curve: barrierCurve)),
      sigma: sigma,
      tint: barrierColor,
      child: ModalBarrier(
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
      ),
    );
  }
}

/// `showDialog` with the frost for a barrier: same page, same fade, same
/// timing, and the same answer when the route is popped.
Future<T?> showFrostedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  // The dialog is built under the navigator, not under the caller, so the
  // caller's themes have to be carried across or a themed subtree would
  // open a dialog in the app's default colours.
  final CapturedThemes themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  return navigator.push<T>(
    FrostedDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) => FadeTransition(
            // A driven animation holds no listener of its own, so building
            // one per rebuild leaks nothing.
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: child,
          ),
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            Widget dialog = themes.wrap(Builder(builder: builder));
            if (useSafeArea) {
              dialog = SafeArea(child: dialog);
            }
            return dialog;
          },
    ),
  );
}
