import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/event_toast.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/notifications_tab_child.dart';

export 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';

/// Opens over the existing page. The shell retains ownership of the controller.
Future<void> showBellPanel({
  required BuildContext context,
  required BellController controller,
}) async {
  if (controller.state.private || !context.mounted) return;
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final FocusNode? previousFocus = FocusManager.instance.primaryFocus;
  final CapturedThemes themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  final TextDirection direction = Directionality.of(context);
  late final FrostedDialogRoute<void> route;
  route = FrostedDialogRoute<void>(
    settings: const RouteSettings(name: 'bell-panel'),
    barrierLabel: context.l10n.commonClose,
    // Frost belongs to the panel's clipped surface. The uncovered page stays
    // at its original brightness, as in the home-bell mockup.
    barrierColor: Colors.transparent,
    sigma: 0,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => themes.wrap(
      Directionality(
        textDirection: direction,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: BellPanel(controller: controller),
        ),
      ),
    ),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) {
          final Animation<double> motion = animation.drive(
            CurveTween(curve: AppTokens.of(context).spring),
          );
          return AnimatedBuilder(
            animation: motion,
            child: child,
            builder: (_, Widget? child) => IgnorePointer(
              ignoring:
                  animation.status == AnimationStatus.reverse ||
                  animation.value == 0,
              child: ExcludeFocus(
                excluding:
                    animation.status == AnimationStatus.reverse ||
                    animation.value == 0,
                child: ExcludeSemantics(
                  excluding:
                      animation.status == AnimationStatus.reverse ||
                      animation.value == 0,
                  child: Opacity(
                    opacity: motion.value,
                    child: Transform.translate(
                      offset: Offset(
                        (direction == TextDirection.ltr ? 24 : -24) *
                            (1 - motion.value),
                        0,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
  );
  final StreamSubscription<BellState> privacy = controller.stream.listen(
    (BellState state) {
      final NavigatorState? owner = route.navigator;
      if (state.private && owner != null && route.isActive) {
        // A lock can put another route above this one. Remove this exact route
        // rather than popping whichever route happens to be on top.
        owner.removeRoute(route);
      }
    },
  );
  void acknowledge(AnimationStatus status) {
    if (status == AnimationStatus.completed && route.isCurrent) {
      controller.markSeen(controller.state.identities);
    }
  }

  try {
    final Future<void> closed = navigator.push<void>(route);
    route.animation?.addStatusListener(acknowledge);
    await closed;
  } finally {
    route.animation?.removeStatusListener(acknowledge);
    await privacy.cancel();
  }
  if (!controller.state.private &&
      context.mounted &&
      previousFocus?.context != null &&
      previousFocus!.canRequestFocus) {
    previousFocus.requestFocus();
  }
}

/// The frosted history and connection-decision panel at the reading edge.
class BellPanel extends StatelessWidget {
  /// Uses the shell's existing history and privacy owner.
  const BellPanel({required this.controller, super.key});

  /// The shell-owned bell state; the panel does not close it.
  final BellController controller;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return BlocBuilder<BellController, BellState>(
      bloc: controller,
      builder: (BuildContext context, BellState state) {
        if (state.private) return const SizedBox.shrink();
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.of(context).maybePop();
            },
          },
          child: FocusScope(
            autofocus: true,
            child: Semantics(
              container: true,
              scopesRoute: true,
              explicitChildNodes: true,
              namesRoute: true,
              label: context.l10n.railNotifications,
              child: SizedBox(
                key: const Key('bell_panel'),
                width: tokens.bellPanelWidth,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: <BoxShadow>[tokens.panelShadow],
                  ),
                  child: FrostedSurface(
                    sigma: tokens.panelBlur,
                    borderRadius: BorderRadius.zero,
                    child: Material(
                      type: MaterialType.transparency,
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: tokens.line),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                16,
                                8,
                                8,
                                8,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      context.l10n.railNotifications,
                                      style: tokens.bodyText.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    key: const Key('bell_clear'),
                                    onPressed: state.records.isEmpty
                                        ? null
                                        : () => unawaited(
                                            controller.clearHistory(),
                                          ),
                                    child: Text(context.l10n.bellClear),
                                  ),
                                  IconButton(
                                    key: const Key('bell_close'),
                                    tooltip: context.l10n.commonClose,
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    icon: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: tokens.faint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: tokens.line),
                            Expanded(
                              child: NotificationsTabChild(
                                controller: controller,
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
        );
      },
    );
  }
}

/// The shell positions this beside its panel. History replay never enters here.
class BellToast extends StatefulWidget {
  /// Listens only for newly inserted events from the shell-owned controller.
  const BellToast({required this.controller, super.key});

  /// The source of fresh events and the current wallet privacy state.
  final BellController controller;

  @override
  State<BellToast> createState() => _BellToastState();
}

class _BellToastState extends State<BellToast> {
  StreamSubscription<BellRecord>? _subscription;
  BellRecord? _record;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.controller.toasts.listen((BellRecord record) {
      if (mounted && !widget.controller.state.private) {
        setState(() => _record = record);
      }
    });
  }

  @override
  void didUpdateWidget(BellToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription?.cancel());
      _record = null;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<BellController, BellState>(
    bloc: widget.controller,
    builder: (BuildContext context, BellState state) {
      if (state.private) {
        _record = null;
        return const SizedBox.shrink();
      }
      final BellRecord? record = _record;
      if (record == null) return const SizedBox.shrink();
      return EventToast(
        key: ValueKey<String>('bell_toast_${record.identity}'),
        message:
            record.notification.title ?? context.l10n.notificationEmptyTitle,
        detail: record.notification.details,
        icon: bellEventIcon(record.notification),
        accent: bellEventColor(context, record.notification),
        onDismiss: () {
          if (mounted && identical(_record, record)) {
            setState(() => _record = null);
          }
        },
      );
    },
  );
}
