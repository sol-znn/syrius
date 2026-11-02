import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

// What the steps of the create-token stepper share: the frame every step is
// laid out in, and the row of a yes-or-no choice.

/// A step's header in the stepper: the mark, and a stub of connector above
/// and below it.
const double _kStepHeader = 76;

/// The space above the action row.
const double _kActionsGap = 20;

/// The height of a button of the action row.
const double _kActionsHeight = 40;

/// Kept clear under the action row.
const double _kActionsClearance = 8;

/// The least a step's fields are given, however short the window.
const double _kLeastBody = 96;

/// The height of the card the stepper is laid out in.
///
/// A step sits in a list, which gives it any height it asks for. With this
/// it knows how tall it may be for its header, its fields and its actions to
/// be on screen together.
class TokenStepViewport extends InheritedWidget {
  /// Tells the steps under [child] they have [height] to fill.
  const TokenStepViewport({
    required this.height,
    required super.child,
    super.key,
  });

  /// The card's height.
  final double height;

  /// The height given by the nearest [TokenStepViewport], if there is one.
  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TokenStepViewport>()?.height;

  @override
  bool updateShouldNotify(TokenStepViewport oldWidget) =>
      oldWidget.height != height;
}

/// One step of the stepper: its fields, and under them Back and the step's
/// main action.
///
/// The fields scroll when the window is short; the actions do not, and are
/// brought into view when the step opens. Tab walks the fields in reading
/// order, then Back, then the main action. The first control takes the
/// focus when the step opens, and Enter anywhere in the fields runs
/// [onSubmit].
class TokenStepFrame extends StatefulWidget {
  /// Creates the frame of a step.
  const TokenStepFrame({
    required this.active,
    required this.body,
    required this.primary,
    this.onSubmit,
    this.onBack,
    this.busy = false,
    super.key,
  });

  /// Whether this is the step shown. Every step stays mounted, so a step
  /// learns from this that it has just opened.
  final bool active;

  /// The fields.
  final Widget body;

  /// The step's main action; it comes last.
  final Widget primary;

  /// What Enter does; null while the step is not valid.
  final VoidCallback? onSubmit;

  /// Goes one step back. No Back button when null.
  final VoidCallback? onBack;

  /// Whether the step is sending. Back is disabled meanwhile.
  final bool busy;

  @override
  State<TokenStepFrame> createState() => _TokenStepFrameState();
}

class _TokenStepFrameState extends State<TokenStepFrame>
    with SingleTickerProviderStateMixin {
  // Neither node takes the focus: one hears Enter from the fields under it
  // and finds the first of them, the other finds the main action.
  final FocusNode _fields = FocusNode(debugLabel: 'token step fields');
  final FocusNode _primary = FocusNode(debugLabel: 'token step action');
  final FocusNode _frameFocus = FocusNode(debugLabel: 'token step');
  final GlobalKey _actionsKey = GlobalKey();
  bool _stepAllowsInput = true;
  bool _interactive = false;
  int _focusGeneration = 0;

  // Follow the actions after the shared-axis gate opens. Focusing before
  // then would target a field that is still invisible or excluded.
  late final AnimationController _opening;

  @override
  void initState() {
    super.initState();
    // Never-selected steps still dispose this controller with the flow.
    _opening = AnimationController(
      vsync: this,
      duration: StepSwitcher.retainedDuration,
      animationBehavior: AnimationBehavior.preserve,
    )..addListener(_followActions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stepAllowsInput = StepInteraction.of(context);
    _syncActivity();
  }

  @override
  void didUpdateWidget(TokenStepFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActivity();
  }

  void _syncActivity() {
    final bool interactive = widget.active && _stepAllowsInput;
    if (interactive == _interactive) {
      return;
    }
    _interactive = interactive;
    if (interactive) {
      _open();
    } else {
      _focusGeneration++;
      _opening.stop();
      if (_frameFocus.hasFocus) {
        _frameFocus.unfocus();
      }
    }
  }

  void _open() {
    final int generation = ++_focusGeneration;
    _opening.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_interactive ||
          generation != _focusGeneration ||
          _frameFocus.hasFocus) {
        return;
      }
      _findFirstControl()?.requestFocus();
    });
  }

  /// Finds the first control of the step in reading order: the topmost,
  /// and of two on one line the one at the start. A step with no field
  /// focuses its main action.
  FocusNode? _findFirstControl() {
    final TextDirection direction = Directionality.of(context);
    FocusNode? first;
    for (final FocusNode node in _fields.traversalDescendants) {
      if (first == null || _isBefore(node.rect, first.rect, direction)) {
        first = node;
      }
    }
    return first ?? _primary.traversalDescendants.firstOrNull;
  }

  static bool _isBefore(Rect a, Rect b, TextDirection direction) {
    final bool onOneLine = a.top < b.bottom && b.top < a.bottom;
    if (!onOneLine) {
      return a.top < b.top;
    }
    return direction == TextDirection.ltr ? a.left < b.left : a.right > b.right;
  }

  /// Scrolls the list the stepper is in, when the actions would otherwise
  /// end below the window.
  void _followActions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? actions = _actionsKey.currentContext;
      if (!mounted || !_interactive || actions == null) {
        return;
      }
      Scrollable.ensureVisible(
        actions,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (!_interactive) {
      return KeyEventResult.handled;
    }
    // A button inside a field, such as Paste, keeps Enter for itself.
    if (_isOnButton()) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      widget.onSubmit?.call();
    }
    // The repeats of a held key are taken too: they must not run on through
    // the next step, nor toggle the box the focus has just moved to.
    return KeyEventResult.handled;
  }

  KeyEventResult _onFrameKey(FocusNode node, KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    // A review without fields focuses its action. A key held from the
    // previous step must be released before that action can be activated.
    if (event is KeyRepeatEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether the focus is on a button between the fields.
  bool _isOnButton() {
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    final BuildContext? fields = _fields.context;
    if (focused == null || fields == null) {
      return false;
    }
    bool found = false;
    focused.visitAncestorElements((Element element) {
      if (element == fields) {
        return false;
      }
      found = element.widget is InkWell || element.widget is InkResponse;
      return !found;
    });
    return found;
  }

  @override
  void dispose() {
    _focusGeneration++;
    _opening.dispose();
    _fields.dispose();
    _primary.dispose();
    _frameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !_interactive,
    child: ExcludeSemantics(
      excluding: !_interactive,
      child: ExcludeFocus(
        excluding: !_interactive,
        child: Focus(
          focusNode: _frameFocus,
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onFrameKey,
          child: _buildFrame(context),
        ),
      ),
    ),
  );

  Widget _buildFrame(BuildContext context) {
    final double? card = TokenStepViewport.maybeOf(context);
    final double room = card != null && card.isFinite
        ? card
        : MediaQuery.sizeOf(context).height;
    final double bodyMax = math.max(
      _kLeastBody,
      room - _kStepHeader - _kActionsGap - _kActionsHeight - _kActionsClearance,
    );
    return FocusTraversalGroup(
      // A message that appears under a field makes the step taller after it
      // has opened; the actions are followed then too.
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _followActions();
          return false;
        },
        child: SizeChangedLayoutNotifier(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: bodyMax),
                  child: Focus(
                    focusNode: _fields,
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onKey,
                    child: SingleChildScrollView(child: widget.body),
                  ),
                ),
              ),
              Padding(
                key: _actionsKey,
                padding: const EdgeInsetsDirectional.only(top: _kActionsGap),
                child: Row(
                  children: <Widget>[
                    if (widget.onBack != null) ...<Widget>[
                      TextButton(
                        style: quietButtonStyle(context),
                        onPressed: widget.busy ? null : widget.onBack,
                        child: Text(context.l10n.goBack),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Focus(
                      focusNode: _primary,
                      canRequestFocus: false,
                      skipTraversal: true,
                      child: widget.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A yes-or-no choice of a step: a checkbox, what it decides, and a help
/// mark that explains it on hover.
class TokenStepToggle extends StatelessWidget {
  /// Creates the row. [checkboxKey] goes on the checkbox itself.
  const TokenStepToggle({
    required this.checkboxKey,
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
    this.adaptive = false,
    super.key,
  });

  /// The key of the checkbox.
  final Key checkboxKey;

  /// What is switched on.
  final String label;

  /// Shown on hover of the help mark.
  final String help;

  /// Whether it is on.
  final bool value;

  /// Called with the new value.
  final ValueChanged<bool> onChanged;

  /// Whether the checkbox takes the platform's look.
  final bool adaptive;

  void _onChanged(bool? value) {
    if (value != null) {
      onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        if (adaptive)
          Checkbox.adaptive(
            key: checkboxKey,
            activeColor: tokens.znnInk,
            value: value,
            onChanged: _onChanged,
          )
        else
          Checkbox(
            key: checkboxKey,
            activeColor: tokens.znnInk,
            value: value,
            onChanged: _onChanged,
          ),
        const SizedBox(width: 4),
        Flexible(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(!value),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kBodyLargeTextStyle.copyWith(
                  fontFamily: kSansFontFamily,
                  color:
                      theme.textTheme.bodyLarge?.color ??
                      theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: help,
          child: Icon(Icons.help_outline, size: 14, color: tokens.faint),
        ),
      ],
    );
  }
}
