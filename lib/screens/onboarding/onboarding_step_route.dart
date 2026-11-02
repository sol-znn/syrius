import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/step_switcher.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Uses one preserving route clock for the existing onboarding stack.
class OnboardingStepRoute<T> extends PageRouteBuilder<T> {
  /// Builds the admitted next owner with the preserved shared-axis clock.
  OnboardingStepRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: StepSwitcher.retainedDuration,
        reverseTransitionDuration: StepSwitcher.retainedDuration,
        pageBuilder:
            (BuildContext context, Animation<double> _, Animation<double> _) =>
                builder(context),
        transitionsBuilder:
            (
              BuildContext context,
              Animation<double> primary,
              Animation<double> secondary,
              Widget child,
            ) => SharedAxisTransition(
              animation: primary,
              secondaryAnimation: secondary,
              transitionType: SharedAxisTransitionType.horizontal,
              fillColor: AppTokens.of(context).background,
              child: child,
            ),
      );

  @override
  AnimationController createAnimationController() => AnimationController(
    vsync: navigator!,
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    // Entry steps keep their declared timing regardless of OS motion flags.
    animationBehavior: AnimationBehavior.preserve,
  );
}
