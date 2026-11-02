import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/step_switcher.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The state of a [Step] which is used to control the style of the circle and
/// text.
///
/// See also:
///
///  * [Step]
enum StepState {
  /// A step that displays its index in its circle.
  indexed,

  /// A step that displays a pencil icon in its circle.
  editing,

  /// A step that displays a tick icon in its circle.
  complete,

  /// A step that is disabled and does not to react to taps.
  disabled,

  /// A step with an error, such as invalid submitted input.
  error,
}

/// Defines the [Stepper]'s main axis.
enum StepperType {
  /// A vertical layout of the steps with their content in-between the titles.
  vertical,

  /// A horizontal layout of the steps with their content below the titles.
  horizontal,
}

// The step number: mono, small, in a 28 px dot.
const TextStyle _kStepStyle = TextStyle(
  fontFamily: kMonoFontFamily,
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  fontSize: 13,
  color: AppColors.faint,
  fontWeight: FontWeight.w600,
);
const Color _kErrorLight = AppColors.errorColor;
const Color _kErrorDark = AppColors.errorColor;
const Color _kDisabledLight = Colors.black38;
const Color _kDisabledDark = Colors.white38;
// The box a step's mark sits in. It stays 40 wide so the connector and the
// steps' content keep the indent the feature steppers were laid out for; the
// mark inside is [_kDotSize].
const double _kStepSize = 40;
const double _kDotSize = 28;
const double _kTriangleHeight =
    _kDotSize * 0.866025; // Triangle height. sqrt(3.0) / 2.0
// A finished step's mark: the active colour as a tint, with a line of it.
const double _kDoneFill = 0.16;
const double _kDoneLine = 0.5;
// The connector between two steps: a hairline, and the stub of it above and
// below each mark.
const double _kConnectorWidth = 1;
const double _kConnectorStub = 12;
// A connector is three parts in a row: the stub under a mark, the line
// beside the step's content, the stub over the next mark. Each takes its
// share of the fill, so the green runs from one mark to the next.
const Interval _kFillLeaving = Interval(0, 0.2, curve: Easing.standard);
const Interval _kFillBody = Interval(0.2, 0.8, curve: Easing.standard);
const Interval _kFillArriving = Interval(0.8, 1, curve: Easing.standard);
const Interval _kFillWhole = Interval(0, 1, curve: Easing.standard);

/// A material step used in [Stepper]. The step can have a title and subtitle,
/// an icon within its circle, some content and a state that governs its
/// styling.
///
/// See also:
///
///  * [Stepper]
///  * <https://material.io/archive/guidelines/components/steppers.html>
@immutable
class Step {
  /// Creates a step for a [Stepper].
  ///
  /// The [title], [content], and [state] arguments must not be null.
  const Step({
    required this.title,
    required this.content,
    this.subtitle,
    this.state = StepState.indexed,
    this.isActive = false,
  });

  /// The title of the step that typically describes it.
  final Widget title;

  /// The subtitle of the step that appears below the title and has a smaller
  /// font size. It typically gives more details that complement the title.
  ///
  /// If null, the subtitle is not shown.
  final Widget? subtitle;

  /// The content of the step that appears below the [title] and [subtitle].
  ///
  /// Below the content, every step has a 'continue' and 'cancel' button.
  final Widget content;

  /// The state of the step which determines the styling of its components
  /// and whether steps are interactive.
  final StepState state;

  /// Whether or not the step is active. The flag only influences styling.
  final bool isActive;
}

/// A material stepper widget that displays progress through a sequence of
/// steps. Steppers are particularly useful in the case of forms where one step
/// requires the completion of another one, or where multiple steps need to be
/// completed in order to submit the whole form.
///
/// The widget is a flexible wrapper. A parent class should pass [currentStep]
/// to this widget based on some logic triggered by the three callbacks that it
/// provides.
///
/// See also:
///
///  * [Step]
///  * <https://material.io/archive/guidelines/components/steppers.html>
class Stepper extends StatefulWidget {
  /// Creates a stepper from a list of steps.
  ///
  /// This widget is not meant to be rebuilt with a different list of steps
  /// unless a key is provided in order to distinguish the old stepper from the
  /// new one.
  ///
  /// The [steps], [type], and [currentStep] arguments must not be null.
  const Stepper({
    required this.steps,
    super.key,
    this.physics,
    this.type = StepperType.vertical,
    this.currentStep = 0,
    this.onStepTapped,
    this.onStepContinue,
    this.onStepCancel,
    this.controlsBuilder,
    this.activeColor = AppColors.znnColor,
  }) : assert(
         0 <= currentStep && currentStep < steps.length,
         'The selected step must belong to the stepper.',
       );

  /// The color of the circle next to the name of the step when the step
  /// is selected or completed
  final Color activeColor;

  /// The steps of the stepper whose titles, subtitles, icons always get shown.
  ///
  /// The length of [steps] must not change.
  final List<Step> steps;

  /// How the stepper's scroll view should respond to user input.
  ///
  /// For example, determines how the scroll view continues to
  /// animate after the user stops dragging the scroll view.
  ///
  /// If the stepper is contained within another scrollable it
  /// can be helpful to set this property to [ClampingScrollPhysics].
  final ScrollPhysics? physics;

  /// The type of stepper that determines the layout. In the case of
  /// [StepperType.horizontal], the content of the current step is displayed
  /// underneath as opposed to the [StepperType.vertical] case where it is
  /// displayed in-between.
  final StepperType type;

  /// The index into [steps] of the current step whose content is displayed.
  final int currentStep;

  /// The callback called when a step is tapped, with its index passed as
  /// an argument.
  final ValueChanged<int>? onStepTapped;

  /// The callback called when the 'continue' button is tapped.
  ///
  /// If null, the 'continue' button will be disabled.
  final VoidCallback? onStepContinue;

  /// The callback called when the 'cancel' button is tapped.
  ///
  /// If null, the 'cancel' button will be disabled.
  final VoidCallback? onStepCancel;

  /// The callback for creating custom controls.
  ///
  /// If null, the default controls from the current theme will be used.
  ///
  /// This callback which takes in a context and two functions: [onStepContinue]
  /// and [onStepCancel]. These can be used to control the stepper.
  ///
  /// {@tool dartpad --template=stateless_widget_scaffold}
  /// Creates a stepper control with custom buttons.
  ///
  /// ```dart
  /// Widget build(BuildContext context) {
  ///   return Stepper(
  ///     controlsBuilder:
  ///       (BuildContext context, {
  ///         VoidCallback onStepContinue,
  ///         VoidCallback onStepCancel,
  ///       }) {
  ///          return Row(
  ///            children: <Widget>[
  ///              TextButton(
  ///                onPressed: onStepContinue,
  ///                child: const Text('NEXT'),
  ///              ),
  ///              TextButton(
  ///                onPressed: onStepCancel,
  ///                child: const Text('CANCEL'),
  ///              ),
  ///            ],
  ///          );
  ///       },
  ///     steps: const <Step>[
  ///       Step(
  ///         title: Text('A'),
  ///         content: const SizedBox(
  ///           width: 100.0,
  ///           height: 100.0,
  ///         ),
  ///       ),
  ///       Step(
  ///         title: Text('B'),
  ///         content: const SizedBox(
  ///           width: 100.0,
  ///           height: 100.0,
  ///         ),
  ///       ),
  ///     ],
  ///   );
  /// }
  /// ```
  /// {@end-tool}
  final ControlsWidgetBuilder? controlsBuilder;

  @override
  State<Stepper> createState() => _StepperState();
}

class _StepperState extends State<Stepper> with TickerProviderStateMixin {
  late List<GlobalKey> _keys;
  final Map<int, StepState> _oldStates = <int, StepState>{};

  @override
  void initState() {
    super.initState();
    _keys = List<GlobalKey>.generate(
      widget.steps.length,
      (int i) => GlobalKey(),
    );

    for (int i = 0; i < widget.steps.length; i += 1) {
      _oldStates[i] = widget.steps[i].state;
    }
  }

  @override
  void didUpdateWidget(Stepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.steps.length == oldWidget.steps.length,
      'Use a new stepper key when changing the number of steps.',
    );

    for (int i = 0; i < oldWidget.steps.length; i += 1) {
      _oldStates[i] = oldWidget.steps[i].state;
    }
  }

  bool _isFirst(int index) {
    return index == 0;
  }

  bool _isLast(int index) {
    return widget.steps.length - 1 == index;
  }

  bool _isCurrent(int index) {
    return widget.currentStep == index;
  }

  bool _isDark() {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// The theme's hairline. The stepper screens run under a theme whose
  /// divider has no colour, so this falls back to the app's.
  Color _restLineColor() {
    return Theme.of(context).dividerTheme.color ??
        (_isDark() ? AppColors.darkDividerColor : AppColors.lightDividerColor);
  }

  /// Whether the connector leaving the step at [fromIndex] is filled: it is
  /// once that step is complete.
  bool _isFilled(int fromIndex) {
    if (fromIndex < 0 || fromIndex >= widget.steps.length) {
      return false;
    }
    return widget.steps[fromIndex].state == StepState.complete;
  }

  /// One part of the connector that leaves the step at [fromIndex]. It
  /// rests on the hairline and fills with the active colour, over [part] of
  /// the fill, when that step completes.
  Widget _buildConnector(
    int fromIndex, {
    required Interval part,
    Axis axis = Axis.vertical,
    double? length,
  }) {
    return _Connector(
      filled: _isFilled(fromIndex),
      color: widget.activeColor,
      rest: _restLineColor(),
      axis: axis,
      length: length,
      part: part,
    );
  }

  /// The stub of connector above or below a mark. An end of the stepper has
  /// none, but keeps its height so every header is as tall as the others.
  Widget _buildLine(bool visible, int fromIndex, Interval part) {
    if (!visible) {
      return const SizedBox(height: _kConnectorStub);
    }
    return _buildConnector(fromIndex, part: part, length: _kConnectorStub);
  }

  Widget? _buildCircleChild(int index, bool oldState) {
    final StepState state = oldState
        ? _oldStates[index]!
        : widget.steps[index].state;
    final bool current = _isCurrent(index);
    // On the filled green dot of the current step the mark is dark; on the
    // tinted dot of a finished step it is green.
    final Color mark = current ? kOnZnnColor : widget.activeColor;
    switch (state) {
      case StepState.indexed:
      case StepState.disabled:
        return Text(
          '${index + 1}',
          style: current
              ? _kStepStyle.copyWith(color: kOnZnnColor)
              : _kStepStyle,
        );
      case StepState.editing:
        return Icon(
          Icons.edit,
          color: mark,
          size: 14,
        );
      case StepState.complete:
        return Icon(
          Icons.check,
          color: mark,
          size: 16,
        );
      case StepState.error:
        return Text('!', style: _kStepStyle.copyWith(color: Colors.white));
    }
  }

  Widget _buildCircle(int index, bool oldState) {
    final bool complete = widget.steps[index].state == StepState.complete;
    final bool current = _isCurrent(index);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: _kStepSize,
      height: _kStepSize,
      alignment: Alignment.center,
      child: AnimatedContainer(
        curve: Easing.standard,
        duration: Durations.medium1,
        width: _kDotSize,
        height: _kDotSize,
        decoration: BoxDecoration(
          color: current
              ? widget.activeColor
              : complete
              ? widget.activeColor.withValues(alpha: _kDoneFill)
              : Colors.transparent,
          border: Border.all(
            color: current
                ? widget.activeColor
                : complete
                ? widget.activeColor.withValues(alpha: _kDoneLine)
                : _restLineColor(),
          ),
          shape: BoxShape.circle,
        ),
        child: Center(
          // The number gives way to the tick with a small scale and fade.
          child: AnimatedSwitcher(
            duration: Durations.short4,
            reverseDuration: Durations.short2,
            switchInCurve: Easing.emphasizedDecelerate,
            switchOutCurve: Easing.emphasizedAccelerate,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
            child: KeyedSubtree(
              key: ValueKey<String>(
                '${widget.steps[index].state.name} $current',
              ),
              child: _buildCircleChild(
                index,
                oldState && widget.steps[index].state == StepState.error,
              )!,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTriangle(int index, bool oldState) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: _kStepSize,
      height: _kStepSize,
      child: Center(
        child: SizedBox(
          width: _kDotSize,
          height: _kTriangleHeight,
          child: CustomPaint(
            painter: _TrianglePainter(
              color: _isDark() ? _kErrorDark : _kErrorLight,
            ),
            child: Align(
              alignment: const Alignment(
                0,
                0.8,
              ), // 0.8 looks better than the geometrical 0.33.
              child: _buildCircleChild(
                index,
                oldState && widget.steps[index].state != StepState.error,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(int index) {
    if (widget.steps[index].state != _oldStates[index]) {
      return AnimatedCrossFade(
        firstChild: _buildCircle(index, true),
        secondChild: _buildTriangle(index, true),
        firstCurve: const Interval(0, 0.6, curve: Easing.standard),
        secondCurve: const Interval(0.4, 1, curve: Easing.standard),
        sizeCurve: Easing.standard,
        crossFadeState: widget.steps[index].state == StepState.error
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        duration: Durations.short4,
      );
    } else {
      if (widget.steps[index].state != StepState.error) {
        return _buildCircle(index, false);
      } else {
        return _buildTriangle(index, false);
      }
    }
  }

  Widget _buildVerticalControls() {
    return const SizedBox(
      height: 0,
    );
  }

  // The step titles take the panel title size; a step that is neither the
  // current one nor finished is dim. The font is set here because the
  // stepper screens run under a theme without the app's faces.
  TextStyle? _titleStyle(int index) {
    final ThemeData themeData = Theme.of(context);
    final TextStyle base = themeData.textTheme.bodyLarge!.copyWith(
      fontFamily: kSansFontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    final Color dim = _isDark()
        ? AppColors.subtitleColor
        : AppColors.lightSubtitleColor;

    switch (widget.steps[index].state) {
      case StepState.indexed:
        // A step still to come is dim. The weight stays the same, so a title
        // does not change width as its step opens.
        return _isCurrent(index) ? base : base.copyWith(color: dim);
      case StepState.editing:
      case StepState.complete:
        return base;
      case StepState.disabled:
        return base.copyWith(
          color: _isDark() ? _kDisabledDark : _kDisabledLight,
        );
      case StepState.error:
        return base.copyWith(color: _isDark() ? _kErrorDark : _kErrorLight);
    }
  }

  TextStyle? _subtitleStyle(int index) {
    final ThemeData themeData = Theme.of(context);
    final TextStyle base = themeData.textTheme.bodySmall!.copyWith(
      fontFamily: kSansFontFamily,
      fontSize: 12,
    );

    switch (widget.steps[index].state) {
      case StepState.indexed:
      case StepState.editing:
      case StepState.complete:
        return base;
      case StepState.disabled:
        return base.copyWith(
          color: _isDark() ? _kDisabledDark : _kDisabledLight,
        );
      case StepState.error:
        return base.copyWith(color: _isDark() ? _kErrorDark : _kErrorLight);
    }
  }

  Widget _buildHeaderText(int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedDefaultTextStyle(
          style: _titleStyle(index)!,
          duration: Durations.short4,
          curve: Easing.standard,
          child: widget.steps[index].title,
        ),
        if (widget.steps[index].subtitle != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: AnimatedDefaultTextStyle(
              style: _subtitleStyle(index)!,
              duration: Durations.short4,
              curve: Easing.standard,
              child: widget.steps[index].subtitle!,
            ),
          ),
      ],
    );
  }

  Widget _buildVerticalHeader(int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: <Widget>[
          Column(
            children: <Widget>[
              // Line parts are always added in order for the ink splash to
              // flood the tips of the connector lines.
              _buildLine(!_isFirst(index), index - 1, _kFillArriving),
              _buildIcon(index),
              _buildLine(!_isLast(index), index, _kFillLeaving),
            ],
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsetsDirectional.only(start: 12),
              child: _buildHeaderText(index),
            ),
          ),
        ],
      ),
    );
  }

  bool get _showContent =>
      !_isLast(widget.currentStep) ||
      widget.steps[widget.currentStep].state != StepState.complete;

  Widget _buildVerticalBody(int index, Widget entry) {
    return Stack(
      children: <Widget>[
        PositionedDirectional(
          start: 32,
          top: 0,
          bottom: 0,
          child: SizedBox(
            width: 24,
            child: Center(
              // The line beside the content, as tall as the content is.
              child: _isLast(index)
                  ? const SizedBox.shrink()
                  : _buildConnector(index, part: _kFillBody),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsetsDirectional.only(start: 40, end: 24),
          child: entry,
        ),
      ],
    );
  }

  Widget _buildVertical() {
    return StepSwitcher.retained(
      step: widget.currentStep,
      showContent: _showContent,
      fillColor: AppTokens.of(context).card,
      children: <Widget>[
        for (final Step step in widget.steps) step.content,
      ],
      layoutBuilder: (BuildContext context, List<Widget> entries) =>
          SingleChildScrollView(
            physics: widget.physics,
            // A lazy list can dispose a closed step outside the viewport.
            // The flow owns every body until the stepper itself is removed.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < widget.steps.length; i += 1)
                  Column(
                    key: _keys[i],
                    children: <Widget>[
                      InkWell(
                        overlayColor: WidgetStateProperty.resolveWith(
                          (Set<WidgetState> states) =>
                              states.contains(WidgetState.hovered)
                              ? Colors.transparent
                              : null,
                        ),
                        onTap: widget.steps[i].state != StepState.disabled
                            ? () {
                                Scrollable.ensureVisible(
                                  _keys[i].currentContext!,
                                  curve: Easing.standard,
                                  duration: Durations.short4,
                                );
                                widget.onStepTapped?.call(i);
                              }
                            : null,
                        canRequestFocus:
                            widget.steps[i].state != StepState.disabled,
                        child: _buildVerticalHeader(i),
                      ),
                      _buildVerticalBody(i, entries[i]),
                    ],
                  ),
              ],
            ),
          ),
    );
  }

  Widget _buildHorizontal() {
    final List<Widget> children = <Widget>[
      for (int i = 0; i < widget.steps.length; i += 1) ...<Widget>[
        InkResponse(
          onTap: widget.steps[i].state != StepState.disabled
              ? () {
                  widget.onStepTapped?.call(i);
                }
              : null,
          canRequestFocus: widget.steps[i].state != StepState.disabled,
          child: Row(
            children: <Widget>[
              SizedBox(
                height: 72,
                child: Center(
                  child: _buildIcon(i),
                ),
              ),
              Container(
                margin: const EdgeInsetsDirectional.only(start: 12),
                child: _buildHeaderText(i),
              ),
            ],
          ),
        ),
        if (!_isLast(i))
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildConnector(
                i,
                part: _kFillWhole,
                axis: Axis.horizontal,
              ),
            ),
          ),
      ],
    ];

    return Column(
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _restLineColor())),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: children,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            physics: widget.physics,
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              StepSwitcher.retained(
                step: widget.currentStep,
                showContent: _showContent,
                fillColor: AppTokens.of(context).card,
                children: <Widget>[
                  for (final Step step in widget.steps) step.content,
                ],
              ),
              _buildVerticalControls(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterial(context), 'A stepper needs Material.');
    assert(
      debugCheckHasMaterialLocalizations(context),
      'A stepper needs Material localizations.',
    );
    assert(() {
      if (context.findAncestorWidgetOfExactType<Stepper>() != null) {
        throw FlutterError(
          'Steppers must not be nested.\n'
          'The material specification advises that one should avoid embedding '
          'steppers within steppers. '
          'https://material.io/archive/guidelines/components/steppers.html#steppers-usage',
        );
      }
      return true;
    }(), 'Steppers cannot be nested.');
    switch (widget.type) {
      case StepperType.vertical:
        return _buildVertical();
      case StepperType.horizontal:
        return _buildHorizontal();
    }
  }
}

/// One part of the hairline between two steps. It rests on [rest] and
/// fills with [color], from the step it leaves towards the next, when
/// [filled] becomes true; it empties the same way when a step is undone.
class _Connector extends StatelessWidget {
  const _Connector({
    required this.filled,
    required this.color,
    required this.rest,
    required this.part,
    this.axis = Axis.vertical,
    this.length,
  });

  /// Whether the step this connector leaves is complete.
  final bool filled;

  /// The fill.
  final Color color;

  /// The line before it fills.
  final Color rest;

  /// The share of the whole connector's fill that this part takes.
  final Interval part;

  /// The way the steps run.
  final Axis axis;

  /// How long this part is; all the room there is when null.
  final double? length;

  @override
  Widget build(BuildContext context) {
    final bool vertical = axis == Axis.vertical;
    return SizedBox(
      width: vertical ? _kConnectorWidth : length ?? double.infinity,
      height: vertical ? length ?? double.infinity : _kConnectorWidth,
      child: ColoredBox(
        color: rest,
        // Without a `begin` the tween starts where it ends, so a stepper
        // opened part-way shows its finished connectors already filled.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: filled ? 1 : 0),
          duration: Durations.medium4,
          curve: part,
          builder: (BuildContext context, double t, Widget? child) =>
              FractionallySizedBox(
                alignment: vertical
                    ? Alignment.topCenter
                    : AlignmentDirectional.centerStart,
                widthFactor: vertical ? null : t,
                heightFactor: vertical ? t : null,
                child: child,
              ),
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}

// Paints a triangle whose base is the bottom of the bounding rectangle and its
// top vertex the middle of its top.
class _TrianglePainter extends CustomPainter {
  _TrianglePainter({
    this.color,
  });

  final Color? color;

  @override
  bool hitTest(Offset point) => true; // Hitting the rectangle is fine enough.

  @override
  bool shouldRepaint(_TrianglePainter oldPainter) {
    return oldPainter.color != color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double base = size.width;
    final double halfBase = size.width / 2.0;
    final double height = size.height;
    final List<Offset> points = <Offset>[
      Offset(0, height),
      Offset(base, height),
      Offset(halfBase, 0),
    ];

    canvas.drawPath(
      Path()..addPolygon(points, true),
      Paint()..color = color!,
    );
  }
}
