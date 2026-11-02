import 'package:material_ui/material_ui.dart';

/// The open page layers that Escape can close without leaving the wallet.
class PageDismissController {
  final Map<Object, bool Function()> _layers = <Object, bool Function()>{};
  bool _disposed = false;

  void _attach(Object owner, bool Function() dismiss) {
    if (!_disposed) _layers[owner] = dismiss;
  }

  void _detach(Object owner) => _layers.remove(owner);

  /// Closes the latest visible open layer, leaving inactive tabs alone.
  bool dismissLatest() {
    if (_disposed) return false;
    final List<MapEntry<Object, bool Function()>> snapshot = _layers.entries
        .toList()
        .reversed
        .toList();
    for (final MapEntry<Object, bool Function()> entry in snapshot) {
      if (_layers[entry.key] == entry.value && entry.value()) return true;
    }
    return false;
  }

  /// Releases the bindings when the shell's destination is no longer owned.
  void dispose() {
    _disposed = true;
    _layers.clear();
  }
}

/// Gives one destination its own Escape targets during a page transition.
class PageDismissScope extends InheritedWidget {
  /// Creates the scope for one page.
  const PageDismissScope({
    required this.controller,
    required super.child,
    super.key,
  });

  /// The destination's shell-owned layer registry.
  final PageDismissController controller;

  /// The nearest destination's registry, when there is a shell.
  static PageDismissController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageDismissScope>()
      ?.controller;

  @override
  bool updateShouldNotify(PageDismissScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Lets Escape close a disclosure from its body or from an external opener.
/// Dismissal never disposes data sources or claims a transaction succeeded.
class PageDismissAction extends StatefulWidget {
  /// Creates a binding around one controlled page layer.
  const PageDismissAction({
    required this.open,
    required this.onDismiss,
    required this.child,
    super.key,
  });

  /// Whether the layer is open, including its opening transition.
  final bool open;

  /// An idempotent close operation owned by the layer.
  final VoidCallback onDismiss;

  /// The header and content whose local Escape takes priority.
  final Widget child;

  @override
  State<PageDismissAction> createState() => _PageDismissActionState();
}

class _PageDismissActionState extends State<PageDismissAction> {
  PageDismissController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final PageDismissController? next = PageDismissScope.maybeOf(context);
    if (_controller != next) {
      _controller?._detach(this);
      _controller = next;
      if (widget.open) _controller?._attach(this, _dismiss);
    }
  }

  @override
  void didUpdateWidget(PageDismissAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) {
      if (widget.open) {
        _controller?._attach(this, _dismiss);
      } else {
        _controller?._detach(this);
      }
    }
  }

  bool _dismiss() {
    if (!mounted ||
        !widget.open ||
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    widget.onDismiss();
    return true;
  }

  @override
  void deactivate() {
    _controller?._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (widget.open) _controller?._attach(this, _dismiss);
  }

  @override
  void dispose() {
    _controller?._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (DismissIntent intent) {
          if (!_dismiss()) Actions.maybeInvoke(context, intent);
          return null;
        },
      ),
    },
    child: widget.child,
  );
}
