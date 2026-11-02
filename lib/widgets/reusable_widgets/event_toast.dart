import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

/// A short event over the page, with one clock for its bar and dismissal.
///
/// It rises 6 px over 300 ms and drains for five seconds. Hover or keyboard
/// focus within the card holds the remaining time; leaving both resumes it.
/// Escape dismisses while focus is in the card, without taking a page's
/// keyboard focus when the toast appears.
///
/// A changed [message] starts a fresh entrance and clock. Otherwise give each
/// event its own key. Dismissal hides the card even when [onDismiss] does not
/// remove it from its parent.
class EventToast extends StatefulWidget {
  /// Creates a toast for an event.
  const EventToast({
    required this.message,
    this.detail,
    this.icon = Icons.info_outline,
    this.accent,
    this.onDismiss,
    super.key,
  });

  /// The event, in a few words.
  final String message;

  /// Optional context, such as the source address of an incoming transfer.
  final String? detail;

  /// The event's mark. The label carries its meaning as well as its colour.
  final IconData icon;

  /// The icon and draining bar. Null takes the brand token.
  final Color? accent;

  /// Called once when the toast closes or its clock runs out.
  final VoidCallback? onDismiss;

  @override
  State<EventToast> createState() => _EventToastState();
}

class _EventToastState extends State<EventToast> with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    // Motion is event feedback. Both clocks keep their durations whatever
    // the platform or MediaQuery reports about animation effects.
    animationBehavior: AnimationBehavior.preserve,
  );
  late final AnimationController _remaining = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onRemainingStatus);

  bool _hovered = false;
  bool _focused = false;
  bool _dismissed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _entrance.forward();
    _remaining.reverse();
  }

  @override
  void didUpdateWidget(EventToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      if (_dismissed) {
        _hovered = false;
        _focused = false;
      }
      _dismissed = false;
      _entrance.forward(from: 0);
      _remaining.value = 1;
      _runCountdown();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _entrance.dispose();
    _remaining.dispose();
    super.dispose();
  }

  void _runCountdown() {
    if (_disposed || _dismissed) return;
    if (_hovered || _focused) {
      _remaining.stop();
    } else {
      // reverse() uses only the remaining fraction of the five-second
      // clock, so crossing the card never grants a fresh five seconds.
      _remaining.reverse();
    }
  }

  void _onRemainingStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _dismiss();
  }

  void _dismiss() {
    if (_disposed || _dismissed) return;
    setState(() => _dismissed = true);
    _entrance.stop();
    _remaining.stop();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final AppTokens tokens = AppTokens.of(context);
    final Color accent = widget.accent ?? tokens.znn;
    final BorderRadius radius = BorderRadius.circular(tokens.toastRadius);
    final Animation<double> entrance = _entrance.drive(
      CurveTween(curve: tokens.spring),
    );
    final Widget card = MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _runCountdown();
      },
      onExit: (_) {
        _hovered = false;
        _runCountdown();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        },
        child: Focus(
          skipTraversal: true,
          onFocusChange: (bool focused) {
            _focused = focused;
            _runCountdown();
          },
          child: Semantics(
            liveRegion: true,
            container: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tokens.toastWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: <BoxShadow>[tokens.toastShadow],
                ),
                child: FrostedSurface(
                  sigma: tokens.panelBlur,
                  borderRadius: radius,
                  child: Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: tokens.line),
                      ),
                      child: Padding(
                        padding: tokens.toastPadding,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    widget.icon,
                                    size: 16,
                                    color: accent,
                                  ),
                                ),
                                SizedBox(width: tokens.inlineGap),
                                Expanded(
                                  child: Text(
                                    widget.message,
                                    style: tokens.bodyText.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: MaterialLocalizations.of(
                                    context,
                                  ).closeButtonTooltip,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 24,
                                    height: 24,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _dismiss,
                                  icon: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: tokens.faint,
                                  ),
                                ),
                              ],
                            ),
                            if (widget.detail != null) ...<Widget>[
                              SizedBox(height: tokens.inlineGap),
                              Text(
                                widget.detail!,
                                style: tokens.bodyText.copyWith(
                                  fontSize: 13,
                                  color: tokens.dim,
                                ),
                              ),
                            ],
                            SizedBox(height: tokens.inlineGap),
                            ExcludeSemantics(
                              child: ClipRRect(
                                // The mockup's three-pixel draining bar.
                                borderRadius: BorderRadius.circular(2),
                                child: SizedBox(
                                  height: 3,
                                  child: ColoredBox(
                                    color: tokens.line,
                                    child: AnimatedBuilder(
                                      animation: _remaining,
                                      child: ColoredBox(color: accent),
                                      builder:
                                          (
                                            BuildContext context,
                                            Widget? child,
                                          ) => FractionallySizedBox(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            widthFactor: _remaining.value,
                                            child: child,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
      ),
    );
    return AnimatedBuilder(
      animation: entrance,
      child: card,
      builder: (BuildContext context, Widget? child) => IgnorePointer(
        ignoring: entrance.value == 0,
        child: ExcludeSemantics(
          excluding: entrance.value == 0,
          child: ExcludeFocus(
            excluding: entrance.value == 0,
            child: FadeTransition(
              opacity: entrance,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - entrance.value)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
