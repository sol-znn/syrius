import 'package:material_ui/material_ui.dart';

/// One captured generation of an entry route and its displayed source.
class EntryActionLease {
  EntryActionLease._(this._current);

  final bool Function() _current;

  /// Coverage, replacement and disposal permanently revoke this generation.
  bool get isCurrent => _current();

  /// Checks ownership before evaluating a callback that constructs an owner.
  VoidCallback guard(VoidCallback action) => () {
    if (isCurrent) action();
  };
}

/// Captures route ownership without mounting a wallet or persistence owner.
class EntryActionBoundary extends StatefulWidget {
  /// Binds action callbacks to one foreground route and source generation.
  const EntryActionBoundary({
    required this.source,
    required this.builder,
    super.key,
  });

  /// Changes whenever the input that an action would use is replaced.
  final Object source;

  /// Builds callbacks against this route's current generation.
  final Widget Function(BuildContext, EntryActionLease) builder;

  @override
  State<EntryActionBoundary> createState() => _EntryActionBoundaryState();
}

class _EntryActionBoundaryState extends State<EntryActionBoundary>
    with WidgetsBindingObserver {
  final FocusNode _barrier = FocusNode(debugLabel: 'Entry actions');
  ModalRoute<dynamic>? _route;
  Animation<double>? _primary;
  Animation<double>? _secondary;
  FocusNode? _parent;
  Object _generation = Object();
  bool _enabled = true;
  bool _foreground = true;
  bool _available = false;

  bool get _current =>
      mounted &&
      _enabled &&
      _foreground &&
      (_route?.isCurrent ?? true) &&
      (_primary?.value ?? 1) == 1 &&
      (_secondary?.value ?? 0) == 0 &&
      (_parent?.descendantsAreFocusable ?? true) &&
      (_parent?.ancestors.every(
            (FocusNode node) => node.descendantsAreFocusable,
          ) ??
          true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _generation = Object();
      _primary?.removeListener(_routeMotion);
      _secondary?.removeListener(_routeMotion);
      _route = route;
      _primary = route?.animation;
      _secondary = route?.secondaryAnimation;
      _primary?.addListener(_routeMotion);
      _secondary?.addListener(_routeMotion);
    }
    _parent = Focus.maybeOf(context, scopeOk: true);
    _enabled = TickerMode.valuesOf(context).enabled;
    _refresh();
  }

  @override
  void didUpdateWidget(EntryActionBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source)) _generation = Object();
  }

  void _refresh() {
    final bool next = _current;
    if (next != _available) _generation = Object();
    _available = next;
    if (!next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_current && _barrier.hasFocus) _barrier.unfocus();
      });
    }
  }

  void _routeMotion() {
    // The route clock keeps moving outside this gate. Input arrives only
    // once the actual shared-axis entrance or return has reached its end.
    if (mounted && _current != _available) setState(_refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _refresh();
    });
  }

  EntryActionLease _capture() {
    final Object generation = _generation;
    final Object source = widget.source;
    final ModalRoute<dynamic>? route = _route;
    return EntryActionLease._(() {
      if (!_current) {
        _generation = Object();
        _available = false;
        return false;
      }
      return _available &&
          identical(generation, _generation) &&
          identical(source, widget.source) &&
          identical(route, _route);
    });
  }

  @override
  void deactivate() {
    _generation = Object();
    _available = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _refresh();
  }

  @override
  void dispose() {
    _generation = Object();
    _available = false;
    WidgetsBinding.instance.removeObserver(this);
    _primary?.removeListener(_routeMotion);
    _secondary?.removeListener(_routeMotion);
    _barrier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _barrier,
    canRequestFocus: false,
    skipTraversal: true,
    descendantsAreFocusable: _current,
    descendantsAreTraversable: _current,
    child: IgnorePointer(
      ignoring: !_current,
      child: ExcludeSemantics(
        excluding: !_current,
        child: TickerMode(
          enabled: _current,
          child: widget.builder(context, _capture()),
        ),
      ),
    ),
  );
}
