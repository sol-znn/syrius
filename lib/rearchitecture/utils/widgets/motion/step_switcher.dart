import 'package:animations/animations.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// How far the package slides a step along the axis, in logical pixels. The
/// clip leaves this much room at each side, so a step in motion is cut at
/// the bottom edge and nowhere else.
const double _kTravel = 30;

/// Places retained step bodies without changing their order or ancestry.
/// Each entry collapses when it is not the selected step.
typedef RetainedStepLayoutBuilder =
    Widget Function(BuildContext context, List<Widget> entries);

/// Whether a retained step is visible and ready to receive input.
///
/// A form can be selected before its shared-axis entrance has finished.
/// Its own autofocus must wait for this gate rather than focus an invisible
/// control. Forms outside a retained switcher remain interactive.
class StepInteraction extends InheritedWidget {
  /// Publishes the input gate of one retained step.
  const StepInteraction({
    required this.interactive,
    required super.child,
    super.key,
  });

  /// Whether this step has finished entering and can receive input.
  final bool interactive;

  /// Reads the nearest retained gate, or allows a standalone form.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<StepInteraction>()
          ?.interactive ??
      true;

  @override
  bool updateShouldNotify(StepInteraction oldWidget) =>
      oldWidget.interactive != interactive;
}

/// Shows one step of a flow at a time and, when [step] changes, moves along
/// the axis the steps share: a higher step comes in from the end side while
/// the old one leaves to the start side, a lower step the other way round.
///
/// For steps that follow one another: a stepper, onboarding. Destinations
/// with no order between them take `RiseSwitcher`, and the states of one
/// surface take `StateSwitcher`.
///
/// ```dart
/// StepSwitcher(step: index, child: steps[index])
/// ```
///
/// With the child constructor, only [step] replaces the content. A rebuild
/// with the same step updates it in place, and departed content is disposed.
/// Use [StepSwitcher.retained] for a wallet flow whose draft and submission
/// listeners must survive Back and completion.
///
/// The switcher is as tall as the current step. While two steps swap, its
/// height travels from the old step's to the new one's, so what sits under
/// it moves once and does not jump. The first step appears without motion.
class StepSwitcher extends StatefulWidget {
  /// Creates a switcher showing [child], the content of step [step].
  const StepSwitcher({
    required this.step,
    required this.child,
    this.fillColor = Colors.transparent,
    this.duration = Durations.medium2,
    super.key,
  }) : children = null,
       showContent = true,
       layoutBuilder = null;

  /// Keeps every step mounted for the lifetime of this switcher.
  ///
  /// Step identity is its position in [children]; replace the switcher's key
  /// to start a different flow. A child's own key can still reset its draft.
  /// Hiding completed content keeps its original submission listener alive.
  const StepSwitcher.retained({
    required this.step,
    required List<Widget> children,
    this.showContent = true,
    this.layoutBuilder,
    this.fillColor = Colors.transparent,
    super.key,
  }) : assert(children.length > 0, 'A retained flow needs a step.'),
       assert(
         step >= 0 && step < children.length,
         'The selected step must belong to the retained flow.',
       ),
       children = children,
       child = const SizedBox.shrink(),
       duration = retainedDuration;

  /// The shared-axis clock for retained wallet steps, including size changes.
  static const Duration retainedDuration = Duration(milliseconds: 300);

  /// The index of the step shown. A higher one than before moves the flow
  /// on, a lower one moves it back.
  final int step;

  /// The content of the step.
  final Widget child;

  /// All bodies of a retained flow, in stable step order.
  final List<Widget>? children;

  /// False after completion, while the retained bodies still own their state.
  final bool showContent;

  /// An optional layout for interleaved headers and collapsing step bodies.
  /// Without one, the selected body determines the switcher's height.
  final RetainedStepLayoutBuilder? layoutBuilder;

  /// Painted behind the step that leaves. Transparent, so the card under
  /// the switcher stays what is seen: left to itself the package fills with
  /// the theme's canvas colour, which is not the card's and shows as a
  /// flash. Pass the card's own surface where the two steps must not show
  /// through each other.
  final Color fillColor;

  /// How long the swap takes, and the change of height with it.
  final Duration duration;

  @override
  State<StepSwitcher> createState() => _StepSwitcherState();
}

class _StepSwitcherState extends State<StepSwitcher>
    with SingleTickerProviderStateMixin {
  // Drives the height. `preserve`, because a controller built without it
  // runs twenty times faster when the platform asks for less motion, and
  // motion always runs here. At rest it sits at 1, where the height is the
  // current step's.
  late final AnimationController _resize;

  // Counts the changes of step. It keys the child, so the content is
  // replaced when the step changes and at no other time, and it tells the
  // step that leaves from the one that arrives: going 1, 2, 1 quickly puts
  // two steps numbered 1 in the tree.
  int _swaps = 0;

  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _resize = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
      animationBehavior: AnimationBehavior.preserve,
    );
  }

  @override
  void didUpdateWidget(StepSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resize.duration = widget.duration;
    if (widget.step != oldWidget.step) {
      _forward = widget.step > oldWidget.step;
      _swaps++;
    }
  }

  @override
  void dispose() {
    _resize.dispose();
    super.dispose();
  }

  Widget _buildTransition(
    Widget child,
    Animation<double> primary,
    Animation<double> secondary,
  ) {
    return _StepEntry(
      swaps: (child.key! as ValueKey<int>).value,
      child: SharedAxisTransition(
        animation: primary,
        secondaryAnimation: secondary,
        transitionType: SharedAxisTransitionType.horizontal,
        fillColor: widget.fillColor,
        child: child,
      ),
    );
  }

  // Steps sit at the top and the start, the stack's own default, where a
  // form begins. Nothing is clipped here: the step that leaves may be taller
  // than the one this stack is sized to, and it is the animated height above
  // that cuts it.
  static Widget _buildLayout(List<Widget> entries) {
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: entries,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget>? children = widget.children;
    if (children != null) {
      return _RetainedSteps(
        step: widget.step,
        showContent: widget.showContent,
        fillColor: widget.fillColor,
        layoutBuilder: widget.layoutBuilder,
        children: children,
      );
    }
    // The package's horizontal axis is physical: moving on, the new step
    // comes in from the right. Its `reverse` mirrors every offset, so read
    // right to left the two directions trade places.
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return _StepExtent(
      resize: _resize,
      swaps: _swaps,
      // The step that leaves is taken out of the layout, which would let it
      // be any height. It keeps the limits it had while it was the current
      // one, read here.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            _CurrentStep(
              swaps: _swaps,
              heights: constraints.heightConstraints(),
              child: PageTransitionSwitcher(
                duration: widget.duration,
                reverse: _forward == rtl,
                layoutBuilder: _buildLayout,
                transitionBuilder: _buildTransition,
                child: KeyedSubtree(
                  key: ValueKey<int>(_swaps),
                  child: widget.child,
                ),
              ),
            ),
      ),
    );
  }
}

class _RetainedEntry {
  _RetainedEntry({
    required this.child,
    required TickerProvider vsync,
    required bool selected,
  }) : current = selected,
       painting = selected {
    primary = _controller(vsync, selected ? 1 : 0);
    secondary = _controller(vsync, 0);
    extent = _controller(vsync, selected ? 1 : 0);
  }

  static AnimationController _controller(TickerProvider vsync, double value) =>
      AnimationController(
        vsync: vsync,
        duration: StepSwitcher.retainedDuration,
        value: value,
        // The OS flag must not shorten a step or leave its focus gate behind.
        animationBehavior: AnimationBehavior.preserve,
      );

  Widget child;
  late final AnimationController primary;
  late final AnimationController secondary;
  late final AnimationController extent;
  final FocusNode focus = FocusNode(
    debugLabel: 'Retained step',
    canRequestFocus: false,
  );
  bool current;
  bool painting;

  bool get animating =>
      primary.isAnimating || secondary.isAnimating || extent.isAnimating;

  bool get interactive =>
      current && !animating && primary.value == 1 && secondary.value == 0;

  void enter({required bool forward}) {
    if (!painting) {
      primary.value = forward ? 0 : 1;
      secondary.value = forward ? 0 : 1;
    }
    current = true;
    painting = true;
    _to(primary, 1);
    _to(secondary, 0);
    _to(extent, 1);
  }

  void leave({required bool forward}) {
    current = false;
    if (focus.hasFocus) {
      focus.unfocus();
    }
    _to(primary, forward ? 1 : 0);
    _to(secondary, forward ? 1 : 0);
    _to(extent, 0);
  }

  // A quick Back reverses the same entry from its current frame. Creating a
  // second copy would duplicate form controllers and submission listeners.
  static void _to(AnimationController controller, double value) {
    // DualTransitionBuilder uses status as well as value. Even a channel
    // already at zero must report dismissed rather than completed.
    if (value == 0) {
      controller.animateBack(value, duration: StepSwitcher.retainedDuration);
    } else {
      controller.animateTo(value, duration: StepSwitcher.retainedDuration);
    }
  }

  void dispose() {
    primary.dispose();
    secondary.dispose();
    extent.dispose();
    focus.dispose();
  }
}

class _RetainedSteps extends StatefulWidget {
  const _RetainedSteps({
    required this.step,
    required this.children,
    required this.showContent,
    required this.fillColor,
    required this.layoutBuilder,
  });

  final int step;
  final List<Widget> children;
  final bool showContent;
  final Color fillColor;
  final RetainedStepLayoutBuilder? layoutBuilder;

  @override
  State<_RetainedSteps> createState() => _RetainedStepsState();
}

class _RetainedStepsState extends State<_RetainedSteps>
    with TickerProviderStateMixin {
  late final List<_RetainedEntry> _entries;
  late final AnimationController _resize;
  int _swaps = 0;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    // Construct even for an interleaved layout: creating an unused ticker
    // for the first time during disposal would read a deactivated context.
    _resize = AnimationController(
      vsync: this,
      duration: StepSwitcher.retainedDuration,
      value: 1,
      animationBehavior: AnimationBehavior.preserve,
    );
    _entries = List<_RetainedEntry>.generate(widget.children.length, (int i) {
      final _RetainedEntry entry = _RetainedEntry(
        child: widget.children[i],
        vsync: this,
        selected: widget.showContent && i == widget.step,
      );
      for (final AnimationController controller in <AnimationController>[
        entry.primary,
        entry.secondary,
        entry.extent,
      ]) {
        controller
          ..addListener(_changed)
          ..addStatusListener(_statusChanged);
      }
      return entry;
    });
  }

  void _statusChanged(AnimationStatus _) => _changed();

  void _changed() {
    if (_updating || !mounted) {
      return;
    }
    _updating = true;
    try {
      for (final _RetainedEntry entry in _entries) {
        <AnimationController>[
          entry.primary,
          entry.secondary,
          entry.extent,
        ].forEach(_settleEndpoint);
        if (!entry.current && !entry.animating) {
          entry.painting = false;
        }
      }
    } finally {
      _updating = false;
    }
    setState(() {});
  }

  static void _settleEndpoint(AnimationController controller) {
    final bool reached = switch (controller.status) {
      AnimationStatus.forward => controller.value == controller.upperBound,
      AnimationStatus.reverse => controller.value == controller.lowerBound,
      _ => false,
    };
    if (controller.isAnimating && reached) {
      // Flutter's interpolation isDone uses a strict greater-than check.
      // A terminal value at 300 ms is already the final frame of this flow.
      controller
        ..stop(canceled: false)
        ..value = controller.value;
    }
  }

  @override
  void didUpdateWidget(_RetainedSteps oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.children.length == oldWidget.children.length,
      'Use a new flow key when changing the number of retained steps.',
    );
    for (int i = 0; i < _entries.length; i++) {
      _entries[i].child = widget.children[i];
    }
    if (widget.step == oldWidget.step &&
        widget.showContent == oldWidget.showContent) {
      return;
    }
    _swaps++;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final bool forward = (widget.step >= oldWidget.step) != rtl;
    _updating = true;
    if (oldWidget.showContent) {
      _entries[oldWidget.step].leave(forward: forward);
    }
    if (widget.showContent) {
      _entries[widget.step].enter(forward: forward);
    }
    _updating = false;
  }

  Widget _buildBody(_RetainedEntry entry) {
    final bool interactive = entry.interactive;
    return Offstage(
      offstage: !entry.painting,
      child: TickerMode(
        enabled: interactive,
        child: IgnorePointer(
          ignoring: !interactive,
          child: ExcludeSemantics(
            excluding: !interactive,
            child: Focus(
              focusNode: entry.focus,
              canRequestFocus: false,
              descendantsAreFocusable: interactive,
              // The focus barrier already removes hidden controls from Tab.
              // EditableText can latch an inherited traversal barrier into
              // its own node while rebuilding under the pinned Flutter.
              child: StepInteraction(
                interactive: interactive,
                child: SharedAxisTransition(
                  animation: entry.primary,
                  secondaryAnimation: entry.secondary,
                  transitionType: SharedAxisTransitionType.horizontal,
                  fillColor: widget.fillColor,
                  child: entry.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RetainedStepLayoutBuilder? layoutBuilder = widget.layoutBuilder;
    if (layoutBuilder != null) {
      return layoutBuilder(context, <Widget>[
        for (int i = 0; i < _entries.length; i++)
          ClipRect(
            key: ValueKey<int>(i),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              heightFactor: Easing.standard.transform(_entries[i].extent.value),
              child: _buildBody(_entries[i]),
            ),
          ),
      ]);
    }
    return _StepExtent(
      resize: _resize,
      swaps: _swaps,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: <Widget>[
            // With every step hidden after completion there is still a
            // finite, zero-height layout anchor for the positioned entries.
            const SizedBox(width: double.infinity, height: 0),
            for (int i = 0; i < _entries.length; i++)
              PositionedDirectional(
                key: ValueKey<int>(i),
                top: _entries[i].current ? null : 0,
                start: _entries[i].current ? null : 0,
                end: _entries[i].current ? null : 0,
                child: ConstrainedBox(
                  constraints: constraints.heightConstraints(),
                  child: _buildBody(_entries[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final _RetainedEntry entry in _entries) {
      entry.dispose();
    }
    _resize.dispose();
    super.dispose();
  }
}

/// Tells the steps under it which of them is the current one, and how tall
/// a step may be.
class _CurrentStep extends InheritedWidget {
  const _CurrentStep({
    required this.swaps,
    required this.heights,
    required super.child,
  });

  final int swaps;
  final BoxConstraints heights;

  static _CurrentStep of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CurrentStep>()!;

  @override
  bool updateShouldNotify(_CurrentStep oldWidget) =>
      oldWidget.swaps != swaps || oldWidget.heights != heights;
}

/// One step in the switcher's stack, in motion or at rest.
///
/// The stack takes the size of the current step alone. A step that leaves
/// is pinned over it and takes no input: it no longer holds the layout
/// open, and a press meant for the new step cannot land on the old one. The
/// widgets are the same in both cases, so a step keeps its state as it
/// turns from one into the other.
class _StepEntry extends StatelessWidget {
  const _StepEntry({required this.swaps, required this.child});

  /// The value of the switcher's count when this step arrived.
  final int swaps;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _CurrentStep scope = _CurrentStep.of(context);
    final bool leaving = scope.swaps != swaps;
    return PositionedDirectional(
      top: leaving ? 0 : null,
      start: leaving ? 0 : null,
      end: leaving ? 0 : null,
      child: ConstrainedBox(
        constraints: scope.heights,
        child: IgnorePointer(ignoring: leaving, child: child),
      ),
    );
  }
}

/// Sizes itself to its child, except that after a change of [swaps] its
/// height travels from what it was to the child's over [resize].
///
/// `AnimatedSize` does this for any change of size, on a controller of its
/// own that cannot be told to keep its duration. Here the controller is the
/// switcher's, and a step that grows by itself, for a message under a field,
/// is followed at once.
class _StepExtent extends SingleChildRenderObjectWidget {
  const _StepExtent({
    required this.resize,
    required this.swaps,
    required super.child,
  });

  final AnimationController resize;
  final int swaps;

  @override
  _RenderStepExtent createRenderObject(BuildContext context) =>
      _RenderStepExtent(resize, swaps);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStepExtent renderObject,
  ) {
    renderObject.swaps = swaps;
  }
}

class _RenderStepExtent extends RenderProxyBox {
  _RenderStepExtent(this._resize, this._swaps);

  final AnimationController _resize;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  int _swaps;

  // Set by a change of step, taken by the next layout: only there is the
  // new step's height known.
  bool _swapped = false;

  // The height the change starts from, and the height last laid out.
  double? _from;
  double? _shown;

  // The controller's value at the last layout. A tick that brings nothing
  // new asks for no layout, which is what lets the change be started from
  // inside one.
  double _lastValue = 1;

  int get swaps => _swaps;

  set swaps(int value) {
    if (value == _swaps) {
      return;
    }
    _swaps = value;
    _swapped = true;
    markNeedsLayout();
  }

  void _onTick() {
    if (_resize.isAnimating && _resize.value == 1) {
      _resize
        ..stop(canceled: false)
        ..value = 1;
    }
    if (_resize.value != _lastValue) {
      markNeedsLayout();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _resize.addListener(_onTick);
  }

  @override
  void detach() {
    _resize.removeListener(_onTick);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    _lastValue = _resize.value;
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final double target = child.size.height;
    if (_swapped) {
      _swapped = false;
      _from = _shown;
      _lastValue = 0;
      _resize.forward(from: 0);
    }
    final double from = _from ?? target;
    final double t = Easing.standard.transform(_resize.value);
    final double height = from + (target - from) * t;
    _shown = height;
    // The width is the child's throughout: only the height differs from
    // one step to the next.
    size = constraints.constrain(Size(child.size.width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // At rest the child fits and there is nothing to cut. In motion one of
    // the two steps is taller than the height shown.
    if (child == null || !_resize.isAnimating) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(-_kTravel, 0, size.width + _kTravel, size.height),
      super.paint,
      oldLayer: _clip.layer,
    );
  }
}
