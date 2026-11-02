import 'package:material_ui/material_ui.dart';

/// Addresses existing page actions without building a second transaction owner.
class PageCommandController<T extends Object> {
  final Map<T, bool Function()> _actions = <T, bool Function()>{};
  bool _disposed = false;

  void _attach(T command, bool Function() action) {
    if (!_disposed) _actions[command] = action;
  }

  void _detach(T command, bool Function() action) {
    if (_actions[command] == action) _actions.remove(command);
  }

  /// Refuses commands whose page is absent, hidden or covered by a modal.
  bool invoke(T command) => !_disposed && (_actions[command]?.call() ?? false);

  /// Stops accepting commands when the shell releases this destination.
  void dispose() {
    _disposed = true;
    _actions.clear();
  }
}

/// Binds beneath the providers that own an existing page action.
class PageCommandAction<T extends Object> extends StatefulWidget {
  /// Creates a binding for this mounted destination.
  const PageCommandAction({
    required this.controller,
    required this.command,
    required this.onInvoke,
    required this.child,
    super.key,
  });

  /// The shell-owned command target.
  final PageCommandController<T> controller;

  /// The action supported by this binding.
  final T command;

  /// Receives a context beneath the existing transaction providers.
  final ValueChanged<BuildContext> onInvoke;

  /// The existing page, retained without an extra provider or fetch.
  final Widget child;

  @override
  State<PageCommandAction<T>> createState() => _PageCommandActionState<T>();
}

class _PageCommandActionState<T extends Object>
    extends State<PageCommandAction<T>> {
  @override
  void initState() {
    super.initState();
    widget.controller._attach(widget.command, _run);
  }

  @override
  void didUpdateWidget(PageCommandAction<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller._detach(oldWidget.command, _run);
    widget.controller._attach(widget.command, _run);
  }

  bool _run() {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    widget.onInvoke(context);
    return true;
  }

  @override
  void deactivate() {
    widget.controller._detach(widget.command, _run);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.controller._attach(widget.command, _run);
  }

  @override
  void dispose() {
    widget.controller._detach(widget.command, _run);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
