import 'package:material_ui/material_ui.dart';

const Duration _kEntranceDuration = Duration(milliseconds: 320);
const Duration _kStagger = Duration(milliseconds: 40);
const double _kRise = 6;
const Cubic _kSpring = Cubic(0.2, 0.8, 0.2, 1);

/// Remembers which logical rows have arrived during one view's lifetime.
///
/// Put this above the list or grid and wrap its rows in [ListEntranceItem].
/// [itemKeys] describes the whole data set, including rows a lazy builder has
/// not mounted. Without that snapshot, scrolling to an old row would look
/// like receiving a new one.
///
/// The first nonempty snapshot's mounted rows enter 40 ms apart. Later new
/// identities enter together, without restarting rows already on screen.
/// Each arrival is eligible only during its first frame: an offscreen row
/// first mounted later appears settled. Rebuilds, sorting, removing a row
/// and inserting the same key again never replay its entrance.
///
/// Keep this scope mounted while the view is alive. Disposing it, or giving
/// it a new widget key, starts a new view and forgets the old identities.
class ListEntrance extends StatefulWidget {
  /// Creates an entrance scope around [child].
  const ListEntrance({
    required this.itemKeys,
    required this.child,
    super.key,
  });

  /// All current logical identities, including offscreen items, once each.
  ///
  /// Use stable value keys from the data, such as a block hash or token
  /// standard. An index identifies a position after sorting, not a row.
  final List<LocalKey> itemKeys;

  /// The list, grid or short column whose rows use [ListEntranceItem].
  final Widget child;

  @override
  State<ListEntrance> createState() => _ListEntranceState();
}

class _ListEntranceState extends State<ListEntrance> {
  final Set<LocalKey> _known = <LocalKey>{};
  final Map<LocalKey, _Arrival> _pending = <LocalKey, _Arrival>{};
  Set<LocalKey> _current = <LocalKey>{};
  bool _initialStarted = false;
  bool _initialOpen = false;
  int _initialRank = 0;
  int _batch = 0;

  @override
  void initState() {
    super.initState();
    _acceptSnapshot();
  }

  @override
  void didUpdateWidget(ListEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Copy every snapshot: callers may have updated a list in place.
    _acceptSnapshot();
  }

  void _acceptSnapshot() {
    final Set<LocalKey> next = widget.itemKeys.toSet();
    assert(
      next.length == widget.itemKeys.length,
      'ListEntrance.itemKeys must contain each logical key once.',
    );
    _current = next;
    _pending.removeWhere((LocalKey key, _Arrival value) => !next.contains(key));
    final Set<LocalKey> added = next.difference(_known);
    _known.addAll(next);
    if (added.isEmpty) return;

    if (!_initialStarted) {
      _initialStarted = true;
      _initialOpen = true;
    }
    final int batch = _batch++;
    for (final LocalKey key in added) {
      _pending[key] = _Arrival(batch: batch, initial: _initialOpen);
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) {
      if (!mounted) return;
      _pending.removeWhere(
        (LocalKey key, _Arrival arrival) => arrival.batch == batch,
      );
      _initialOpen = false;
    });
  }

  _Admission claim(LocalKey key) {
    assert(
      _current.contains(key),
      'A ListEntranceItem key must occur in ListEntrance.itemKeys.',
    );
    // Consuming the admission also prevents replay if a row is recreated
    // during this same frame. The history is retained when rows leave.
    final _Arrival? arrival = _pending.remove(key);
    if (arrival == null) return _Admission.settled;
    return _Admission(
      delay: arrival.initial ? _kStagger * _initialRank++ : Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) =>
      _ListEntranceScope(state: this, child: widget.child);
}

class _Arrival {
  const _Arrival({required this.batch, required this.initial});

  final int batch;
  final bool initial;
}

class _Admission {
  const _Admission({required this.delay, this.animate = true});

  static const _Admission settled = _Admission(
    delay: Duration.zero,
    animate: false,
  );

  final Duration delay;
  final bool animate;
}

class _ListEntranceScope extends InheritedWidget {
  const _ListEntranceScope({required this.state, required super.child});

  final _ListEntranceState state;

  static _ListEntranceState of(BuildContext context) {
    final _ListEntranceScope? scope = context
        .dependOnInheritedWidgetOfExactType<_ListEntranceScope>();
    if (scope == null) {
      throw FlutterError('ListEntranceItem requires a ListEntrance ancestor.');
    }
    return scope.state;
  }

  @override
  bool updateShouldNotify(_ListEntranceScope oldWidget) =>
      state != oldWidget.state;
}

/// Fades a newly arrived row in while it rises 6 px over 320 ms.
///
/// Its required key must also occur in the nearest [ListEntrance.itemKeys].
/// The scope decides whether the identity has just arrived; mounting alone
/// never decides that. The child keeps its full layout size throughout.
///
/// A row at zero opacity takes no pointer input, keyboard focus or semantic
/// action. Once visible, its own controls work throughout the remaining
/// entrance. Amounts and positions within the row are never interpolated.
class ListEntranceItem extends StatefulWidget {
  /// Wraps the content of one stably keyed row.
  const ListEntranceItem({required LocalKey super.key, required this.child});

  /// The row itself; it is not rebuilt by the entrance clock.
  final Widget child;

  @override
  State<ListEntranceItem> createState() => _ListEntranceItemState();
}

class _ListEntranceItemState extends State<ListEntranceItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  _ListEntranceState? _scope;
  Curve _curve = _kSpring;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kEntranceDuration,
      value: 1,
      // The wallet's motion always runs at its declared duration. The
      // default controller behavior shortens it when the OS asks for less.
      animationBehavior: AnimationBehavior.preserve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _ListEntranceState scope = _ListEntranceScope.of(context);
    if (identical(scope, _scope)) return;
    _scope = scope;
    final _Admission admission = scope.claim(widget.key! as LocalKey);
    final Duration total = _kEntranceDuration + admission.delay;
    _controller.duration = total;
    _curve = Interval(
      admission.delay.inMicroseconds / total.inMicroseconds,
      1,
      curve: _kSpring,
    );
    if (admission.animate) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (BuildContext context, Widget? child) {
      final double progress = _curve.transform(_controller.value);
      final bool hidden = progress == 0;
      return Focus(
        canRequestFocus: false,
        // An inherited traversal barrier can stay latched in EditableText
        // after the first visible frame. Focusability is enough while hidden.
        descendantsAreFocusable: !hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: IgnorePointer(
            ignoring: hidden,
            child: Transform.translate(
              offset: Offset(0, _kRise * (1 - progress)),
              child: Opacity(opacity: progress, child: child),
            ),
          ),
        ),
      );
    },
  );
}
