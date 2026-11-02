import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The parts Settings, Connected sites, Notifications and the screens
/// Settings opens are built from, on top of the shared `Panel` and
/// `PageGrid`.
///
/// They exist because those pages were a wall of expandable cards, each with
/// its own paddings, buttons and loading spinner. One row, one quiet note and
/// two button tones replace them.

/// Secondary text of a setting: what it does, in one line.
TextStyle settingHintStyle(BuildContext context) =>
    AppTokens.of(context).settingsHintText;

/// Data shown in a setting: a node, an address, a hash, a path.
TextStyle settingMonoStyle(BuildContext context) =>
    monoStyle(Theme.of(context).textTheme.titleMedium).copyWith(fontSize: 13);

/// The gap between the fields of a form.
const double kSettingFormGap = 12;

/// The least size of an action at the foot of a screen Settings opens, so
/// the way back and the main action stand at one height.
const Size kScreenActionSize = Size(96, 40);

/// An error under a field or a row: one short red line.
TextStyle settingErrorStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error);

/// An empty, loading or failed panel: one dim line, no spinner and no
/// artwork, so a page with nothing to show stays calm.
class QuietNote extends StatelessWidget {
  /// Creates a note saying [text].
  const QuietNote(this.text, {super.key});

  /// The note of a panel waiting for its data.
  const QuietNote.loading({super.key}) : text = 'Loading';

  /// The note of a panel whose data could not be read.
  factory QuietNote.error(Object error, {Key? key}) {
    final String text = error.toString();
    // The SDK's own words for a dropped socket say nothing to a person.
    return QuietNote(
      text.toLowerCase().contains('the client is closed')
          ? 'Not connected to a node'
          : text,
      key: key,
    );
  }

  /// What the note says.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// One setting: its name, an optional line about it, the control at the
/// right, and an optional form under them.
class SettingRow extends StatelessWidget {
  /// Creates a row.
  const SettingRow({
    required this.label,
    this.hint,
    this.trailing,
    this.below,
    super.key,
  });

  /// The setting's name, in sentence case.
  final String label;

  /// One line about it. Left out when the name says it all.
  final String? hint;

  /// The control: a switch, a button, a choice.
  final Widget? trailing;

  /// A form that needs the row's whole width.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: AppTokens.of(context).settingsRowPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(label, style: theme.textTheme.bodyLarge),
                    if (hint != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(hint!, style: settingHintStyle(context)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          if (below != null) ...<Widget>[
            const SizedBox(height: 10),
            below!,
          ],
        ],
      ),
    );
  }
}

/// The width of a slider at the right of its row.
const double kSettingSliderWidth = 240;

/// How long a slider waits after an arrow-key step before it saves.
const Duration kSliderKeySaveDelay = Duration(milliseconds: 400);

/// A whole number picked on a slider and saved when the slider is let go.
///
/// The line under the name follows the thumb, so the person reads what the
/// value will be before letting go. Nothing is saved while it moves: a drag
/// from 3 to 10 is one change, not seven. Arrow keys on the focused slider
/// save once, [kSliderKeySaveDelay] after the last step: each save posts a
/// notification and restarts the lock timer, and a held key was one of each
/// per step.
class SliderSetting extends StatefulWidget {
  /// Creates the row.
  const SliderSetting({
    required this.label,
    required this.hintOf,
    required this.saved,
    required this.min,
    required this.max,
    required this.onCommitted,
    super.key,
  });

  /// The setting's name.
  final String label;

  /// The line under the name for a value, such as "After 5 minutes".
  final String Function(int value) hintOf;

  /// The value in effect.
  final int saved;

  /// The least value.
  final int min;

  /// The greatest value.
  final int max;

  /// Saves the value picked and says whether it was saved. On false the
  /// slider goes back to the last value that was.
  final Future<bool> Function(int value) onCommitted;

  @override
  State<SliderSetting> createState() => _SliderSettingState();
}

class _SliderSettingState extends State<SliderSetting> {
  /// What is stored: the value of the newest save that went through.
  late int _stored = widget.saved.clamp(widget.min, widget.max);

  /// What is taken as saved: [_stored], or what a save still being written
  /// picked.
  late int _saved = _stored;
  late double _value = _saved.toDouble();

  /// How many saves were started, and which of them wrote [_stored]. Saves
  /// can overlap, and the store keeps the one started last.
  int _started = 0;
  int _storedBy = 0;

  /// Whether the save started last failed, so the slider rests on [_stored].
  bool _newestFailed = false;

  /// Whether a pointer is on the slider, which tells a release from a key.
  bool _pointerDown = false;

  /// Runs out [kSliderKeySaveDelay] after the last key step.
  Timer? _keyTimer;

  Future<void> _commit(double value) async {
    final int picked = value.round();
    if (picked == _saved) return;
    final int save = ++_started;
    // Taken as saved at once, so a second release while the first is being
    // written is compared against the right value.
    _saved = picked;
    _newestFailed = false;
    final bool ok = await widget.onCommitted(picked);
    if (ok && save > _storedBy) {
      _storedBy = save;
      _stored = picked;
    }
    if (!ok && save == _started) _newestFailed = true;
    // An older save that fails changes nothing while a newer one stands.
    // Going back to the value from before it left the slider on a value
    // that was not the stored one.
    if (!_newestFailed || _saved == _stored || !mounted) return;
    setState(() {
      _saved = _stored;
      // Key steps not saved yet stay where they are; their save is coming.
      if (_keyTimer == null) _value = _stored.toDouble();
    });
  }

  void _onChangeEnd(double value) {
    _keyTimer?.cancel();
    _keyTimer = null;
    if (_pointerDown) {
      unawaited(_commit(value));
      return;
    }
    _keyTimer = Timer(kSliderKeySaveDelay, _saveKeySteps);
  }

  void _saveKeySteps() {
    _keyTimer = null;
    unawaited(_commit(_value));
  }

  /// The slider ends its change inside the dispatch of the pointer's last
  /// event, after this listener has heard it, so the flag drops a microtask
  /// later.
  void _onPointerGone(PointerEvent event) {
    scheduleMicrotask(() => _pointerDown = false);
  }

  @override
  void dispose() {
    if (_keyTimer != null) {
      _keyTimer!.cancel();
      _keyTimer = null;
      // Saved rather than dropped: the hint already showed this value.
      unawaited(_commit(_value));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SettingRow(
      label: widget.label,
      hint: widget.hintOf(_value.round()),
      trailing: SizedBox(
        width: kSettingSliderWidth,
        child: Listener(
          onPointerDown: (PointerDownEvent event) => _pointerDown = true,
          onPointerUp: _onPointerGone,
          onPointerCancel: _onPointerGone,
          child: Slider(
            value: _value,
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            label: '${_value.round()}',
            activeColor: AppColors.znnColor,
            inactiveColor: theme.dividerTheme.color,
            onChanged: (double value) => setState(() => _value = value),
            onChangeEnd: _onChangeEnd,
          ),
        ),
      ),
    );
  }
}

/// The body of a settings panel: rows under each other with a line between
/// them and none after the last.
///
/// As tall as its rows, so it goes in a `Panel` with `shrinkWrap: true`
/// inside a [SettingsSection]. It used to scroll inside a panel whose height
/// was a number written at the call site; when the rows came to more than
/// that number the last row lost its bottom padding to the panel's edge.
///
/// Not lazy on purpose. A slider or a form keeps what was typed into it only
/// while it is built, and these lists are a handful of rows.
class SettingsList extends StatelessWidget {
  /// Creates a list of [children].
  const SettingsList({required this.children, super.key});

  /// The rows, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const Divider(),
          children[i],
        ],
      ],
    );
  }
}

/// A section of Settings made of panels as tall as their content: they
/// stack from the top with the page gap between, and the section scrolls
/// as a whole when the window is shorter than they are.
///
/// Nothing in it has a height of its own to outgrow, so a larger text size
/// or an error line under a field moves what is below it instead of
/// cutting it off.
class SettingsSection extends StatelessWidget {
  /// Creates a section of [children].
  const SettingsSection({required this.children, super.key});

  /// Panels and [SettingsColumns], top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final double gap = AppTokens.of(context).pageGap;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Panels side by side in a [SettingsSection]: equal widths, tops in line,
/// each as tall as its own content.
class SettingsColumns extends StatelessWidget {
  /// Creates a line of [children].
  const SettingsColumns({required this.children, super.key});

  /// Left to right.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final double gap = AppTokens.of(context).panelGap;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// The label over a group of rows inside one panel.
class SettingGroupLabel extends StatelessWidget {
  /// Creates a label. Written in sentence case, shown in capitals.
  const SettingGroupLabel(this.label, {super.key});

  /// The group's name.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(label.toUpperCase(), style: ledgerLabelStyle(context)),
    );
  }
}

/// Makes the outlined buttons under it secondary actions.
///
/// The theme draws every `OutlinedButton` as the filled green main action.
/// A panel has at most one of those; Confirm, Add, Change and Back next to
/// it are this neutral pill. It is a theme rather than a button class
/// because `LoadingButton` and `SettingsButton` build their own
/// `OutlinedButton` and only the theme reaches it.
class SecondaryAction extends StatelessWidget {
  /// Wraps [child], a button or a subtree of buttons.
  const SecondaryAction({required this.child, super.key});

  /// The button.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color ink = theme.textTheme.bodyLarge!.color!;
    return _ButtonTone(
      ink: ink,
      fill: theme.colorScheme.primaryContainer,
      line: theme.dividerTheme.color!,
      child: child,
    );
  }
}

/// Makes the outlined buttons under it destructive actions: red ink on no
/// fill, so erasing a wallet never looks like the way forward.
class DangerAction extends StatelessWidget {
  /// Wraps [child], a button.
  const DangerAction({required this.child, super.key});

  /// The button.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _ButtonTone(
      ink: AppColors.errorColor,
      fill: Colors.transparent,
      line: AppColors.errorColor,
      child: child,
    );
  }
}

class _ButtonTone extends StatelessWidget {
  const _ButtonTone({
    required this.ink,
    required this.fill,
    required this.line,
    required this.child,
  });

  final Color ink;
  final Color fill;
  final Color line;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color off = theme.dividerTheme.color!;
    return Theme(
      data: theme.copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style:
              OutlinedButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
                minimumSize: const Size(64, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: kOutlinedButtonTextStyle,
              ).copyWith(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (Set<WidgetState> states) =>
                      states.contains(WidgetState.disabled)
                      ? ink.withValues(alpha: 0.38)
                      : ink,
                ),
                iconColor: WidgetStateProperty.resolveWith(
                  (Set<WidgetState> states) =>
                      states.contains(WidgetState.disabled)
                      ? ink.withValues(alpha: 0.38)
                      : ink,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (Set<WidgetState> states) =>
                      states.contains(WidgetState.disabled)
                      ? Colors.transparent
                      : fill,
                ),
                overlayColor: WidgetStatePropertyAll<Color>(
                  ink.withValues(alpha: 0.08),
                ),
                side: WidgetStateProperty.resolveWith(
                  (Set<WidgetState> states) => BorderSide(
                    color: states.contains(WidgetState.disabled)
                        ? off
                        : states.contains(WidgetState.hovered)
                        ? AppColors.faint
                        : line,
                  ),
                ),
              ),
        ),
      ),
      child: child,
    );
  }
}

/// A choice of a few values shown side by side, applied when picked.
///
/// Replaces a column of radios and the Confirm button under it.
class ChoicePills<T> extends StatelessWidget {
  /// Creates a choice between [values].
  const ChoicePills({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    super.key,
  });

  /// What can be picked, in order.
  final List<T> values;

  /// The value in effect.
  final T? selected;

  /// The word for a value.
  final String Function(T value) labelOf;

  /// Called with the value picked.
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final T value in values)
          _Pill(
            key: ValueKey<String>('choice_$value'),
            label: labelOf(value),
            selected: value == selected,
            onTap: () => onSelected(value),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fill = theme.colorScheme.primaryContainer;
    return AnimatedContainer(
      duration: Durations.short3,
      curve: Easing.standard,
      decoration: ShapeDecoration(
        color: selected ? fill : fill.withValues(alpha: 0),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.faint : theme.dividerTheme.color!,
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: selected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontWeight: selected ? FontWeight.w500 : null,
                color: selected ? null : theme.textTheme.titleMedium!.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The way out of a screen Settings opens: a neutral pill beside the main
/// action. Pops the screen unless told otherwise.
class ScreenBackAction extends StatelessWidget {
  /// Creates the action.
  const ScreenBackAction({
    this.label = 'Back',
    this.onPressed,
    this.autofocus = false,
    super.key,
  });

  /// What it says.
  final String label;

  /// What it does; pops the screen when null.
  final VoidCallback? onPressed;

  /// Whether it holds the focus when the screen opens, so that Enter backs
  /// out of a screen whose other action cannot be undone.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SecondaryAction(
      child: OutlinedButton(
        autofocus: autofocus,
        style: OutlinedButton.styleFrom(minimumSize: kScreenActionSize),
        onPressed: onPressed ?? () => Navigator.of(context).pop(),
        child: Text(label),
      ),
    );
  }
}

/// The chrome of a screen Settings opens: one card in the middle of the
/// window with a title, a line about what happens, the form and its actions,
/// the main one last.
///
/// The card is one focus group, so Tab walks its fields and then its
/// actions before it leaves for the banner above.
class SettingsScreenFrame extends StatelessWidget {
  /// Creates the frame.
  const SettingsScreenFrame({
    required this.title,
    required this.child,
    this.note,
    this.actions = const <Widget>[],
    this.top,
    this.width = 480,
    super.key,
  });

  /// What the screen does, in a few words.
  final String title;

  /// One or two sentences under the title.
  final String? note;

  /// The form.
  final Widget child;

  /// Left to right; the main action is the last one.
  final List<Widget> actions;

  /// A strip above the card, for the notification banner.
  final Widget? top;

  /// The card's width when the window allows it.
  final double width;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            ?top,
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: Panel(
                      padding: const EdgeInsets.all(24),
                      child: FocusTraversalGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              title,
                              style: theme.textTheme.headlineSmall!.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (note != null) ...<Widget>[
                              const SizedBox(height: 8),
                              Text(
                                note!,
                                style: theme.textTheme.titleMedium!.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            child,
                            if (actions.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 24),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: AppTokens.of(
                                  context,
                                ).settingsActionGap,
                                runSpacing: AppTokens.of(
                                  context,
                                ).settingsActionGap,
                                children: actions,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
