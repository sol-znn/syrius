import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The compact Settings switch, with independent movement and colour clocks.
/// Both controllers preserve their durations whatever the OS reports.
class SettingsSwitch extends StatefulWidget {
  /// Creates a switch named [label] for pointer, keyboard and accessibility.
  const SettingsSwitch({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });

  /// The stored choice shown by the switch.
  final bool value;

  /// The setting's localized accessible name.
  final String label;

  /// Applies a choice. Null holds the switch disabled.
  final ValueChanged<bool>? onChanged;

  @override
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch>
    with TickerProviderStateMixin {
  late final AnimationController _position = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final AnimationController _colour = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final Listenable _motion = Listenable.merge(<Listenable>[
    _position,
    _colour,
  ]);
  bool _focused = false;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  void didUpdateWidget(SettingsSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final AppTokens tokens = AppTokens.of(context);
      final double target = widget.value ? 1 : 0;
      _position.animateTo(
        target,
        duration: tokens.settingsSwitchDuration,
        curve: tokens.spring,
      );
      _colour.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: tokens.ease,
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _colour.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool enabled = widget.onChanged != null;
    return Semantics(
      container: true,
      label: widget.label,
      toggled: widget.value,
      enabled: enabled,
      focusable: enabled,
      focused: _focused,
      onTap: enabled ? _toggle : null,
      child: ExcludeSemantics(
        child: ExcludeFocus(
          excluding: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : tokens.disabledOpacity,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (BuildContext context, Widget? child) => Material(
                type: MaterialType.transparency,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: enabled ? _toggle : null,
                  mouseCursor: enabled
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  onFocusChange: (bool focused) {
                    if (mounted) setState(() => _focused = focused);
                  },
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(
                        side: BorderSide(
                          width: tokens.focusWidth,
                          color: _focused
                              ? tokens.focusRing
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: SizedBox(
                        width: tokens.settingsSwitchWidth,
                        height: tokens.settingsSwitchHeight,
                        child: DecoratedBox(
                          key: const Key('settings_switch_track'),
                          decoration: ShapeDecoration(
                            color: Color.lerp(
                              tokens.line,
                              tokens.znn,
                              _colour.value,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          child: Stack(
                            children: <Widget>[
                              PositionedDirectional(
                                start:
                                    tokens.settingsSwitchInset +
                                    (tokens.settingsSwitchWidth -
                                            2 * tokens.settingsSwitchInset -
                                            tokens.settingsSwitchThumb) *
                                        _position.value,
                                top: tokens.settingsSwitchInset,
                                child: SizedBox.square(
                                  dimension: tokens.settingsSwitchThumb,
                                  child: DecoratedBox(
                                    key: const Key('settings_switch_thumb'),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color.lerp(
                                        tokens.foreground,
                                        tokens.onZnn,
                                        _colour.value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
