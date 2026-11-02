import 'package:material_ui/material_ui.dart';

/// One presentation generation. Leaving it permanently revokes its callbacks.
class SwapViewLease {
  SwapViewLease._(this._current);
  final bool Function() _current;

  /// Whether this exact visible presentation generation still owns callbacks.
  bool get isCurrent => _current();

  /// Silences a callback permanently after its captured generation departs.
  VoidCallback guard(VoidCallback action) => () {
    if (isCurrent) action();
  };
}

/// Owns input and visibility independently of wallet, timer and persistence.
class SwapActionBoundary extends StatefulWidget {
  /// Revokes input after source, route, focus or foreground context departs.
  const SwapActionBoundary({
    required this.source,
    required this.builder,
    super.key,
  });

  /// Presentation generation identity, independent of signing authority.
  final Object source;

  /// Builds controls with callbacks guarded by the exact visible generation.
  final Widget Function(BuildContext, SwapViewLease) builder;

  @override
  State<SwapActionBoundary> createState() => _SwapActionBoundaryState();
}

class _SwapActionBoundaryState extends State<SwapActionBoundary>
    with WidgetsBindingObserver {
  final FocusNode _barrier = FocusNode(debugLabel: 'Swap actions');
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
  void didUpdateWidget(SwapActionBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _generation = Object();
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

  SwapViewLease _capture() {
    final Object generation = _generation;
    final Object source = widget.source;
    final ModalRoute<dynamic>? route = _route;
    return SwapViewLease._(() {
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
