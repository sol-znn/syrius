import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/event_toast.dart';

/// Shows the latest short event above the page.
abstract final class ToastUtils {
  static _ToastEntry? _current;

  /// Replaces the current toast, including one inserted before its first frame.
  /// [color] accents the icon and bar; the surface uses the theme's glass.
  static void showToast(BuildContext context, String message, {Color? color}) {
    // Clipboard completion may arrive after the page that requested it left.
    if (!context.mounted) return;
    final OverlayState? owner = Overlay.maybeOf(context);
    if (owner == null || !owner.mounted) return;
    _current?.dismiss();

    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: owner.context,
    );
    final TextDirection direction = Directionality.of(context);
    late final _ToastEntry toast;
    final OverlayEntry entry = OverlayEntry(
      // Keep the lifecycle host mounted if a later opaque route covers it.
      // TickerMode supplied by Overlay stops its hidden tickers.
      maintainState: true,
      builder: (BuildContext context) => _ToastLifecycle(
        onDispose: () => toast.ownerDisposed(),
        child: themes.wrap(
          Directionality(
            textDirection: direction,
            child: Builder(
              builder: (BuildContext context) {
                final AppTokens tokens = AppTokens.of(context);
                return PositionedDirectional(
                  top: tokens.toastTop,
                  start: tokens.toastEdge,
                  end: tokens.toastEdge,
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    heightFactor: 1,
                    child: EventToast(
                      message: message,
                      accent: color,
                      onDismiss: () => toast.dismiss(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    toast = _ToastEntry(
      owner: owner,
      entry: entry,
      onRetire: (_ToastEntry value) {
        if (identical(_current, value)) _current = null;
      },
    );
    _current = toast;
    owner.insert(entry);
    // An overlay removed before this entry's first build never mounts its
    // lifecycle host. Release that case after the current frame as well.
    WidgetsBinding.instance.addPostFrameCallback((_) => toast.checkOwner());
  }
}

class _ToastEntry {
  _ToastEntry({
    required this.owner,
    required this.entry,
    required this.onRetire,
  });

  final OverlayState owner;
  final OverlayEntry entry;
  final ValueChanged<_ToastEntry> onRetire;
  bool _retired = false;
  bool _released = false;

  void dismiss() => _retire();

  void checkOwner() {
    if (!owner.mounted) _retire();
  }

  void ownerDisposed() => _retire(deferRelease: true);

  void _retire({bool deferRelease = false}) {
    if (_retired) return;
    _retired = true;
    onRetire(this);
    if (deferRelease) {
      // Descendants unmount before OverlayState. Wait for the owner to finish
      // unmounting so remove() cannot dirty a tree being torn down.
      scheduleMicrotask(_release);
    } else {
      _release();
    }
  }

  void _release() {
    if (_released) return;
    _released = true;
    entry
      ..remove()
      ..dispose();
  }
}

class _ToastLifecycle extends StatefulWidget {
  const _ToastLifecycle({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_ToastLifecycle> createState() => _ToastLifecycleState();
}

class _ToastLifecycleState extends State<_ToastLifecycle> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
