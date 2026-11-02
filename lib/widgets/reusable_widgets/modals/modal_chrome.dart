import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

/// The widest a dialog gets.
const double kDialogWidth = 420;

/// The padding inside every dialog and modal.
const EdgeInsets kDialogPadding = EdgeInsets.fromLTRB(24, 20, 24, 20);

/// The line colour of the theme in force. The stepper screens run under a
/// theme whose divider has no colour, so this falls back to the app's.
Color lineColorOf(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return theme.dividerTheme.color ??
      (theme.brightness == Brightness.dark
          ? AppColors.darkDividerColor
          : AppColors.lightDividerColor);
}

/// The secondary text tone of the theme in force.
Color dimColorOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppColors.subtitleColor
    : AppColors.lightSubtitleColor;

/// The secondary action beside a filled primary: text only, no fill.
///
/// The app's TextButton theme is a filled green pill, which makes a "Cancel"
/// or a "Back" compete with the action it sits next to.
ButtonStyle quietButtonStyle(BuildContext context) {
  final Color dim = dimColorOf(context);
  final Color fg =
      Theme.of(context).textTheme.bodyLarge?.color ??
      Theme.of(context).colorScheme.onSurface;
  return TextButton.styleFrom(
    backgroundColor: Colors.transparent,
    shape: const StadiumBorder(),
    minimumSize: Size(64, AppTokens.of(context).buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    textStyle: kOutlinedButtonTextStyle,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ).copyWith(
    foregroundColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) => states.contains(WidgetState.disabled)
          ? AppColors.faint
          : states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)
          ? fg
          : dim,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) => states.contains(WidgetState.disabled)
          ? AppColors.faint
          : states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)
          ? fg
          : dim,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) => states.contains(WidgetState.pressed)
          ? fg.withValues(alpha: 0.12)
          : states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
          ? fg.withValues(alpha: 0.07)
          : Colors.transparent,
    ),
  );
}

/// A second choice that is not the main one: the raised surface with a line
/// round it, as Receive and Swap are beside Send on the home page.
ButtonStyle secondaryButtonStyle(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  final Color fg =
      theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
  final Color line = lineColorOf(context);
  return OutlinedButton.styleFrom(
    shape: const StadiumBorder(),
    minimumSize: Size(64, AppTokens.of(context).buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    textStyle: kOutlinedButtonTextStyle,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ).copyWith(
    backgroundColor: WidgetStatePropertyAll<Color>(
      theme.colorScheme.primaryContainer,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) =>
          states.contains(WidgetState.disabled) ? AppColors.faint : fg,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) =>
          states.contains(WidgetState.disabled) ? AppColors.faint : fg,
    ),
    side: WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) => BorderSide(
        color:
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? AppColors.faint
            : line,
      ),
    ),
  );
}

/// The one entrance of the refreshed interface: a fade and a 6 px rise.
///
/// It always runs. Nothing here reads the reduced-motion setting.
class RiseIn extends StatefulWidget {
  /// Creates the entrance for [child].
  const RiseIn({
    required this.child,
    this.duration = Durations.medium2,
    super.key,
  });

  /// What enters.
  final Widget child;

  /// How long the rise takes.
  final Duration duration;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    // This entrance must keep its clock when platform animation effects are
    // disabled, just like the modal route that carries it.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> curve = _controller.drive(
      CurveTween(curve: AppTokens.of(context).spring),
    );
    return FadeTransition(
      opacity: curve,
      child: AnimatedBuilder(
        animation: curve,
        // Built once; only the offset changes per frame.
        child: widget.child,
        builder: (BuildContext context, Widget? child) => Transform.translate(
          offset: Offset(0, 6 * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }
}

/// The surface of an ordinary dialog: the glass tone, the dialog radius, a
/// title in the panel title style, a short body, and the actions at the
/// right with the primary one last.
class DialogCard extends StatelessWidget {
  /// Creates a dialog surface.
  const DialogCard({
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.icon,
    this.width = kDialogWidth,
    this.radius,
    super.key,
  });

  /// The heading.
  final String title;

  /// A small mark before the title, for a warning.
  final Widget? icon;

  /// What the dialog says. Text without a style of its own is dim.
  final Widget body;

  /// A quiet secondary first, the filled primary last.
  final List<Widget> actions;

  /// The widest the dialog gets.
  final double width;

  /// Transfer dialogs use their shared card shape.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final BorderRadius radius = BorderRadius.circular(
      this.radius ?? tokens.dialogRadius,
    );
    return RiseIn(
      duration: const Duration(milliseconds: 240),
      child: Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: <BoxShadow>[tokens.dialogShadow],
            ),
            child: FrostedSurface(
              borderRadius: radius,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: tokens.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: Border(top: tokens.glassTopEdge),
                    ),
                    child: Padding(
                      padding: kDialogPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              if (icon != null) ...<Widget>[
                                icon!,
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  style: panelTitleStyle(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: SingleChildScrollView(
                              child: DefaultTextStyle.merge(
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  color: dimColorOf(context),
                                ),
                                child: body,
                              ),
                            ),
                          ),
                          if (actions.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                for (
                                  int i = 0;
                                  i < actions.length;
                                  i++
                                ) ...<Widget>[
                                  if (i > 0) const SizedBox(width: 8),
                                  actions[i],
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
