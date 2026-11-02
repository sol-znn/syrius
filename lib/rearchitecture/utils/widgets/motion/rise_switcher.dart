import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Shows one [child] at a time and, when it is replaced, fades the new one
/// in while it rises [rise] pixels into place.
///
/// For destinations with no order between them, such as the pages behind
/// the side rail: a sideways slide would claim one. The old child fades out
/// during the fade-through's first 30 percent and keeps its last position.
/// It leaves the tree when that fade finishes. Once settled, only the current
/// child is built.
///
/// A child is "replaced" when its type or key differs from the last one, so
/// give each destination its own key. Keep that top-level type and key stable
/// when returning to the destination, including when its descendants have
/// [GlobalKey]s. This lets the switcher retire a live copy before reusing those
/// descendants:
///
/// ```dart
/// RiseSwitcher(
///   child: KeyedSubtree(key: ValueKey<int>(index), child: page),
/// )
/// ```
///
/// The child fills the switcher. The first child appears without motion.
class RiseSwitcher extends StatefulWidget {
  /// Creates a switcher showing [child].
  const RiseSwitcher({
    required this.child,
    this.rise = 6,
    this.duration = const Duration(milliseconds: 320),
    this.reverseDuration = const Duration(milliseconds: 320),
    super.key,
  });

  /// The current destination, keyed.
  final Widget child;

  /// How far below its place the new child starts, in logical pixels.
  final double rise;

  /// The incoming transition's clock, captured when the child is replaced.
  ///
  /// A longer outgoing clock delays this clock's start just enough for its
  /// fade-in to follow every outgoing fade. The default clocks need no delay.
  final Duration duration;

  /// The outgoing transition's clock, captured when the child is replaced.
  ///
  /// Fade-through uses its first 30 percent, so the default visible exit lasts
  /// 96 ms. The child is retired then, rather than waiting on a hidden page.
  final Duration reverseDuration;

  @override
  State<RiseSwitcher> createState() => _RiseSwitcherState();
}

// FadeThroughTransition's outgoing fade occupies the first 30 percent.
const double _exitEnd = 0.3;

class _SwitchEntry {
  _SwitchEntry({
    required this.child,
    required this.rise,
    required TickerProvider vsync,
    required Duration duration,
    Duration delay = Duration.zero,
    bool initial = false,
  }) {
    final Duration total = duration + delay;
    // Motion is wallet feedback, so these clocks always keep their duration
    // regardless of the platform's animation-effects setting.
    entrance = AnimationController(
      vsync: vsync,
      duration: total,
      value: initial ? 1 : 0,
      animationBehavior: AnimationBehavior.preserve,
    );
    primary = delay == Duration.zero
        ? entrance
        : entrance.drive(
            CurveTween(
              curve: Interval(
                delay.inMicroseconds / total.inMicroseconds,
                1,
              ),
            ),
          );
    exit = AnimationController(
      vsync: vsync,
      animationBehavior: AnimationBehavior.preserve,
    );
  }

  final Key key = UniqueKey();
  final FocusNode focus = FocusNode(
    debugLabel: 'RiseSwitcher page',
    canRequestFocus: false,
  );
  Widget child;
  final double rise;
  late final AnimationController entrance;
  late final Animation<double> primary;
  late final AnimationController exit;
  bool outgoing = false;

  bool get interactive => !outgoing && primary.value > _exitEnd;

  int get remainingExitMicroseconds {
    final double remaining = _exitEnd - exit.value;
    return remaining <= 0
        ? 0
        : (exit.duration!.inMicroseconds * remaining).ceil();
  }

  void clearBlockedFocus() {
    if (!interactive && focus.hasFocus) {
      focus.unfocus();
    }
  }

  void dispose() {
    entrance.dispose();
    exit.dispose();
    focus.dispose();
  }
}

class _RiseSwitcherState extends State<RiseSwitcher>
    with TickerProviderStateMixin {
  final List<_SwitchEntry> _entries = <_SwitchEntry>[];
  late _SwitchEntry _current;

  @override
  void initState() {
    super.initState();
    _current = _SwitchEntry(
      child: widget.child,
      rise: widget.rise,
      vsync: this,
      duration: widget.duration,
      initial: true,
    );
    _entries.add(_current);
  }

  @override
  void didUpdateWidget(RiseSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Widget.canUpdate(_current.child, widget.child)) {
      _current.child = widget.child;
      return;
    }

    // A returning destination may carry the very same GlobalKey. Retire its
    // old entry before rebuilding, so only one subtree can claim that key.
    for (final _SwitchEntry entry in _entries.toList()) {
      if (entry != _current && Widget.canUpdate(entry.child, widget.child)) {
        _remove(entry);
      }
    }
    _retire(_current);

    int remaining = 0;
    for (final _SwitchEntry entry in _entries) {
      final int exit = entry.remainingExitMicroseconds;
      if (exit > remaining) {
        remaining = exit;
      }
    }
    final int handoff = (widget.duration.inMicroseconds * _exitEnd).round();
    final int delay = remaining > handoff ? remaining - handoff : 0;
    _current = _SwitchEntry(
      child: widget.child,
      rise: widget.rise,
      vsync: this,
      duration: widget.duration,
      delay: Duration(microseconds: delay),
    );
    _entries.add(_current);
    final _SwitchEntry arriving = _current;
    arriving.entrance.forward();
    // A GlobalKey can bring an already-focused node into the hidden arrival.
    // New focus requests are excluded; this also clears retained focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entries.contains(arriving)) {
        arriving.clearBlockedFocus();
      }
    });
  }

  void _retire(_SwitchEntry entry) {
    entry
      ..outgoing = true
      ..entrance.stop();
    entry.focus.descendantsAreFocusable = false;
    entry.clearBlockedFocus();
    if (entry.primary.value <= _exitEnd ||
        widget.reverseDuration == Duration.zero) {
      _remove(entry);
      return;
    }
    entry.exit.duration = widget.reverseDuration;
    entry.exit.animateTo(_exitEnd).whenCompleteOrCancel(() {
      if (mounted && _entries.contains(entry)) {
        setState(() => _remove(entry));
      }
    });
  }

  void _remove(_SwitchEntry entry) {
    if (_entries.remove(entry)) {
      entry.dispose();
    }
  }

  @override
  void dispose() {
    final List<_SwitchEntry> entries = _entries.toList();
    _entries.clear();
    for (final _SwitchEntry entry in entries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      for (final _SwitchEntry entry in _entries)
        KeyedSubtree(
          key: entry.key,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              entry.entrance,
              entry.exit,
            ]),
            child: entry.child,
            builder: (BuildContext context, Widget? child) {
              final bool interactive = entry.interactive;
              return IgnorePointer(
                ignoring: !interactive,
                child: ExcludeSemantics(
                  excluding: !interactive,
                  child: Focus(
                    focusNode: entry.focus,
                    canRequestFocus: false,
                    skipTraversal: true,
                    descendantsAreFocusable: interactive,
                    includeSemantics: false,
                    onFocusChange: (_) => entry.clearBlockedFocus(),
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        entry.rise *
                            (1 -
                                AppTokens.of(context).spring.transform(
                                  entry.primary.value,
                                )),
                      ),
                      child: FadeThroughTransition(
                        animation: entry.primary,
                        secondaryAnimation: entry.exit,
                        fillColor: Colors.transparent,
                        child: child,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}
