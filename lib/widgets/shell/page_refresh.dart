import 'package:material_ui/material_ui.dart';

/// Runs the read refreshes registered by one mounted page.
///
/// A controller per destination prevents an outgoing page's fade from
/// refreshing the previous destination when the user presses the shortcut.
class PageRefreshController {
  final Map<Object, VoidCallback> _actions = <Object, VoidCallback>{};
  bool _disposed = false;

  void _attach(Object owner, VoidCallback callback) {
    if (!_disposed) _actions[owner] = callback;
  }

  void _detach(Object owner) => _actions.remove(owner);

  /// Invokes the currently registered reads once each.
  /// Each binding rechecks its visibility before calling the page's source.
  void refresh() {
    if (_disposed) return;
    final Map<Object, VoidCallback> snapshot = Map<Object, VoidCallback>.of(
      _actions,
    );
    for (final MapEntry<Object, VoidCallback> entry in snapshot.entries) {
      if (_actions[entry.key] == entry.value) entry.value();
    }
  }

  /// Releases bindings without taking ownership of their page data sources.
  void dispose() {
    _disposed = true;
    _actions.clear();
  }
}

/// Gives a page's existing refresh controls one shell shortcut target.
class PageRefreshScope extends InheritedWidget {
  /// Creates the scope around one destination.
  const PageRefreshScope({
    required this.controller,
    required super.child,
    super.key,
  });

  /// Owned by the shell for this destination.
  final PageRefreshController controller;

  /// The nearest page's controller, absent in a standalone screen or test.
  static PageRefreshController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageRefreshScope>()
      ?.controller;

  @override
  bool updateShouldNotify(PageRefreshScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Registers an existing page read without adding a visible refresh icon.
/// Hidden tabs, inactive routes and detached children refuse the shortcut.
class PageRefreshAction extends StatefulWidget {
  /// Creates a binding beneath the blocs that [onRefresh] reads.
  const PageRefreshAction({
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// The same read the page's existing control performs.
  final VoidCallback onRefresh;

  /// The page content or its visible refresh button.
  final Widget child;

  /// Whether this page read is currently available.
  final bool enabled;

  @override
  State<PageRefreshAction> createState() => _PageRefreshActionState();
}

class _PageRefreshActionState extends State<PageRefreshAction> {
  PageRefreshController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final PageRefreshController? next = PageRefreshScope.maybeOf(context);
    if (_controller != next) {
      _controller?._detach(this);
      _controller = next;
    }
    _controller?._attach(this, _run);
  }

  void _run() {
    if (mounted &&
        widget.enabled &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      widget.onRefresh();
    }
  }

  @override
  void deactivate() {
    _controller?._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _controller?._attach(this, _run);
  }

  @override
  void dispose() {
    _controller?._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
