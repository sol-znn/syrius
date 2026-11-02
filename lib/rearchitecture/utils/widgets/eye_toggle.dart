import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// What stands in for an amount while balances are hidden.
const String kHiddenAmountDots = '••••';

/// The dots are set apart as the mockup sets them, in ems.
const double _kDotsSpacing = 0.08;

/// The eye file is 800 px square and the eye is the 106 px in its middle
/// (101 of outline and a 5 px stroke). Two more so the stroke is not shaved.
const double _kEyeCanvas = 800;
const double _kEyeGlyph = 108;

/// Room round the eye for the pointer, the hover fill and the focus line.
const double _kEyePadding = 6;

/// The wallet's original eye, as the control for hidden balances.
///
/// The file (`ic_anim_eye.json`, 232 frames at 60 a second) is three parts:
/// the eye opens (0 to 30, the lid moving from frame 3 to 20), looks about
/// and blinks three times (30 to 200), and closes (200 to 232, the lid
/// moving from 209 to 226, nothing drawn after). So the eye is open while
/// balances are hidden, as it was on a card whose content was hidden, and a
/// closed lid while they show.
///
/// The file's middle part is three blinks and two glances in under three
/// seconds, which beside money is a busy loop. A blink here is the opening
/// part run back and then forward: the same two lid shapes, from and to the
/// pose the eye rests in, so nothing jumps.
///
/// The motion always runs. The controller keeps its durations whatever the
/// system says about reduced motion, and nothing here asks MediaQuery.
class EyeToggle extends StatefulWidget {
  /// The eye bound to [visibility], or to the wallet's own when null.
  const EyeToggle({
    required this.keyPrefix,
    this.tooltip,
    this.size = 20,
    this.padding = const EdgeInsets.all(_kEyePadding),
    this.visibility,
    super.key,
  });

  /// Names the button for the harness: its key is `<keyPrefix>_eye`.
  final String keyPrefix;

  /// What the button says under the pointer and to a screen reader. The
  /// caller's, because it changes with the state and is translated there.
  final String? tooltip;

  /// The width of the eye itself, in logical pixels.
  final double size;

  /// The pointer and focus inset around the glyph.
  final EdgeInsetsGeometry padding;

  /// What it shows and toggles. [BalanceVisibility.instance] when null.
  final BalanceVisibility? visibility;

  /// The file's length in frames; a controller value is a frame over this.
  @visibleForTesting
  static const double frames = 232;

  /// Where the controller rests while balances are hidden: the eye open.
  @visibleForTesting
  static const double hiddenFrame = 30;

  /// Where the controller rests while balances show: the lid closed, the
  /// last frame the file draws.
  @visibleForTesting
  static const double shownFrame = 226;

  /// How long the eye stays still between two blinks.
  @visibleForTesting
  static const Duration blinkEvery = Duration(seconds: 7);

  @override
  State<EyeToggle> createState() => _EyeToggleState();
}

class _EyeToggleState extends State<EyeToggle>
    with SingleTickerProviderStateMixin {
  // Frame 3 is the first the opening part draws, and a controller value
  // that rounds under it draws nothing, so the lid starts a little inside.
  static const double _closedStart = 3.25;
  static const double _opened = 20;
  static const double _closingStart = 200;

  static const Duration _change = Duration(milliseconds: 500);
  // The file's own blink: six frames to close, seventeen to open.
  static const Duration _blinkClose = Duration(milliseconds: 100);
  static const Duration _blinkOpen = Duration(milliseconds: 283);

  late final AnimationController _frame;
  late BalanceVisibility _visibility;
  Timer? _blinks;
  bool _focused = false;
  bool _hovered = false;

  static double _at(double frame) => frame / EyeToggle.frames;

  @override
  void initState() {
    super.initState();
    _visibility = widget.visibility ?? BalanceVisibility.instance;
    _frame = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
      value: _at(
        _visibility.hidden ? EyeToggle.hiddenFrame : EyeToggle.shownFrame,
      ),
    );
    _visibility.addListener(_follow);
    _scheduleBlinks();
  }

  @override
  void didUpdateWidget(EyeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final BalanceVisibility next =
        widget.visibility ?? BalanceVisibility.instance;
    if (identical(next, _visibility)) {
      return;
    }
    final bool changed = next.hidden != _visibility.hidden;
    _visibility.removeListener(_follow);
    _visibility = next..addListener(_follow);
    if (changed) {
      _follow();
    }
  }

  @override
  void dispose() {
    _blinks?.cancel();
    _visibility.removeListener(_follow);
    _frame.dispose();
    super.dispose();
  }

  /// Plays the part for the new state. Each part starts on the pose the
  /// other ends on, so the jump between them is not seen.
  void _follow() {
    setState(() {});
    if (_visibility.hidden) {
      _frame.value = _at(_closedStart);
      _frame.animateTo(_at(EyeToggle.hiddenFrame), duration: _change);
    } else {
      _frame.value = _at(_closingStart);
      _frame.animateTo(_at(EyeToggle.shownFrame), duration: _change);
    }
    _scheduleBlinks();
  }

  void _scheduleBlinks() {
    _blinks?.cancel();
    _blinks = _visibility.hidden
        ? Timer.periodic(EyeToggle.blinkEvery, (_) => _blink())
        : null;
  }

  void _blink() {
    if (!mounted || !_visibility.hidden || _frame.isAnimating) {
      return;
    }
    // Frames 20 to 30 are the open eye held still: start where it moves.
    _frame.value = _at(_opened);
    unawaited(
      // A toggle in the middle cancels this, and the future of a cancelled
      // run never completes, so the second half cannot land on a closed eye.
      _frame.animateBack(_at(_closedStart), duration: _blinkClose).then((_) {
        if (mounted && _visibility.hidden) {
          _frame.animateTo(_at(EyeToggle.hiddenFrame), duration: _blinkOpen);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final double canvas = widget.size * _kEyeCanvas / _kEyeGlyph;
    final String? tooltip = widget.tooltip;

    final Widget eye = SizedBox.square(
      dimension: widget.size,
      child: ClipRect(
        child: OverflowBox(
          minWidth: canvas,
          maxWidth: canvas,
          minHeight: canvas,
          maxHeight: canvas,
          // The file is drawn in the dark theme's green. Its background
          // layer draws nothing, so the ink can be laid over what it does.
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(tokens.znnInk, BlendMode.srcIn),
            child: AppLottie(
              AppLottieAsset.eye,
              size: canvas,
              controller: _frame,
            ),
          ),
        ),
      ),
    );

    final Widget button = Semantics(
      button: true,
      toggled: _visibility.hidden,
      child: FocusableActionDetector(
        key: ValueKey<String>('${widget.keyPrefix}_eye'),
        mouseCursor: SystemMouseCursors.click,
        // Its own, so it answers Enter under any app, a test's included.
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent _) {
              _visibility.toggle();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (bool show) => setState(() => _focused = show),
        onShowHoverHighlight: (bool show) => setState(() => _hovered = show),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _visibility.toggle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered ? tokens.hover : null,
              border: Border.all(
                color: _focused ? tokens.focusRing : const Color(0x00000000),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: widget.padding,
              child: eye,
            ),
          ),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// An amount that becomes dots while balances are hidden.
///
/// Wrap whatever draws the amount and nothing else: it listens to the
/// notifier itself.
///
/// The child stays laid out while hidden, unpainted and out of semantics,
/// and gives the dots its height, so a row is as tall hidden as shown. Its
/// width is not kept: how long a number is says how large it is.
class HiddenAmount extends StatelessWidget {
  /// Draws [child], or dots in its place.
  const HiddenAmount({
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
    this.style,
    this.visibility,
    super.key,
  });

  /// What draws the amount.
  final Widget child;

  /// Where the child, and the dots, sit in the room this is given. It
  /// matters under a fixed width (a table cell): put the dots where the
  /// figures were.
  final AlignmentGeometry alignment;

  /// The style the dots are built on, for a child that sets its own and
  /// does not take it from a `DefaultTextStyle`. The inherited one when
  /// null. The face is the mono either way.
  final TextStyle? style;

  /// What it follows. [BalanceVisibility.instance] when null.
  final BalanceVisibility? visibility;

  @override
  Widget build(BuildContext context) {
    final BalanceVisibility visibility =
        this.visibility ?? BalanceVisibility.instance;
    return ListenableBuilder(
      listenable: visibility,
      child: child,
      builder: (BuildContext context, Widget? child) {
        final bool hidden = visibility.hidden;
        final TextStyle base = style ?? DefaultTextStyle.of(context).style;
        // One tree for both states, so the child keeps its state (a price
        // it is listening for, a count it is animating) across a toggle.
        return Stack(
          alignment: alignment,
          children: <Widget>[
            Visibility(
              visible: !hidden,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: Align(
                alignment: alignment,
                widthFactor: hidden ? 0 : 1,
                heightFactor: 1,
                child: child,
              ),
            ),
            if (hidden)
              Text(
                kHiddenAmountDots,
                maxLines: 1,
                softWrap: false,
                style: monoStyle(base).copyWith(
                  letterSpacing: (base.fontSize ?? 14) * _kDotsSpacing,
                ),
              ),
          ],
        );
      },
    );
  }
}
