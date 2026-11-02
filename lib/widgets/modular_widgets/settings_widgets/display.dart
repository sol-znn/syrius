import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/explorer_links.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notification_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/app_theme_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/locale_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/text_scaling_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';

/// The existing stored text-size choices. Legacy choices remain readable.
enum TextScaling {
  /// The platform's default text size.
  system,

  /// The smaller bundled scale.
  small,

  /// A fixed scale of one, retained for stored profiles.
  normal,

  /// The larger bundled scale.
  large,

  /// The legacy largest scale, retained while selected.
  huge,
}

enum _MenuStyle { icons, labels }

/// Appearance, visibility and the explorer used by the wallet.
///
/// A choice applies and is saved the moment it is picked. These used to be
/// radios that changed the window at once but were forgotten at the next
/// start unless "Confirm theme" or "Confirm scale" was pressed as well.
class DisplayWidget extends StatefulWidget {
  /// Creates the controls over the wallet's shared choices.
  const DisplayWidget({
    this.railCollapse,
    this.balanceVisibility,
    this.priceFeed,
    super.key,
  });

  /// The shell's choice; a standalone page owns its fallback.
  final RailCollapse? railCollapse;

  /// The same notifier used by Home's eye and the hide-balances shortcut.
  final BalanceVisibility? balanceVisibility;

  /// The existing price feed whose default-on setting this page controls.
  final PriceFeed? priceFeed;

  @override
  State<DisplayWidget> createState() => _DisplayWidget();
}

class _DisplayWidget extends State<DisplayWidget> {
  late RailCollapse _rail = widget.railCollapse ?? RailCollapse();
  BalanceVisibility get _visibility =>
      widget.balanceVisibility ?? BalanceVisibility.instance;
  PriceFeed get _prices => widget.priceFeed ?? PriceFeed.instance;

  @override
  void didUpdateWidget(DisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.railCollapse != widget.railCollapse) {
      if (oldWidget.railCollapse == null) _rail.dispose();
      _rail = widget.railCollapse ?? RailCollapse();
    }
  }

  @override
  void dispose() {
    if (widget.railCollapse == null) _rail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeMode? themeMode = context
        .watch<AppThemeNotifier>()
        .currentThemeMode;
    final TextScaling? textScaling = context
        .watch<TextScalingNotifier>()
        .currentTextScaling;
    final AppLanguage language = context
        .watch<LocaleNotifier>()
        .currentLanguage;
    final List<TextScaling> scales = <TextScaling>[
      TextScaling.small,
      TextScaling.system,
      TextScaling.large,
      if (textScaling == TextScaling.huge) TextScaling.huge,
    ];
    // Default retains the platform-default choice. A stored fixed scale of
    // one has the same label until the person chooses another size.
    final TextScaling? shownScale = textScaling == TextScaling.normal
        ? TextScaling.system
        : textScaling;
    return SettingsSection(
      children: <Widget>[
        Panel(
          key: const Key('display_page'),
          shrinkWrap: true,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[_rail, _visibility]),
            builder: (BuildContext context, Widget? child) => SettingsList(
              children: <Widget>[
                SettingRow(
                  label: context.l10n.displayTheme,
                  trailing: Segment<ThemeMode>(
                    keyPrefix: 'display_theme',
                    items: <SegmentItem<ThemeMode>>[
                      SegmentItem<ThemeMode>(
                        value: ThemeMode.system,
                        label: context.l10n.displaySystem,
                      ),
                      SegmentItem<ThemeMode>(
                        value: ThemeMode.dark,
                        label: context.l10n.displayDark,
                      ),
                      SegmentItem<ThemeMode>(
                        value: ThemeMode.light,
                        label: context.l10n.displayLight,
                      ),
                    ],
                    selected: themeMode,
                    onChanged: _onThemeModeSelected,
                  ),
                ),
                SettingRow(
                  label: context.l10n.displayTextSize,
                  trailing: Segment<TextScaling>(
                    keyPrefix: 'display_scale',
                    items: <SegmentItem<TextScaling>>[
                      for (final TextScaling scale in scales)
                        SegmentItem<TextScaling>(
                          value: scale,
                          label: switch (scale) {
                            TextScaling.small => context.l10n.displaySmall,
                            TextScaling.large => context.l10n.displayLarge,
                            TextScaling.huge => context.l10n.displayHuge,
                            _ => context.l10n.displayDefault,
                          },
                        ),
                    ],
                    selected: shownScale,
                    onChanged: _onTextScalingSelected,
                  ),
                ),
                // A menu, not pills: six pills outgrow the row at the
                // smallest window once the text size is Large or Huge.
                SettingRow(
                  label: context.l10n.displayLanguage,
                  trailing: _LanguageMenu(
                    selected: language,
                    onSelected: _onLanguageSelected,
                  ),
                ),
                SettingRow(
                  label: context.l10n.displayMenu,
                  hint: context.l10n.displayMenuHint,
                  trailing: Segment<_MenuStyle>(
                    keyPrefix: 'display_menu',
                    items: <SegmentItem<_MenuStyle>>[
                      SegmentItem<_MenuStyle>(
                        value: _MenuStyle.icons,
                        label: context.l10n.displayIcons,
                      ),
                      SegmentItem<_MenuStyle>(
                        value: _MenuStyle.labels,
                        label: context.l10n.displayLabels,
                      ),
                    ],
                    selected: _rail.value
                        ? _MenuStyle.icons
                        : _MenuStyle.labels,
                    onChanged: (_MenuStyle style) => _rail.setCollapsed(
                      collapsed: style == _MenuStyle.icons,
                    ),
                  ),
                ),
                SettingRow(
                  label: context.l10n.displayHideBalances,
                  hint: context.l10n.displayHideBalancesHint,
                  trailing: SettingsSwitch(
                    key: const Key('display_hide_balances'),
                    label: context.l10n.displayHideBalances,
                    value: _visibility.hidden,
                    onChanged: _visibility.set,
                  ),
                ),
                SettingRow(
                  label: context.l10n.displayDollarValues,
                  hint: context.l10n.displayDollarValuesHint,
                  trailing: SettingsSwitch(
                    key: const Key('display_dollar_values'),
                    label: context.l10n.displayDollarValues,
                    value: _prices.enabled,
                    // Listening here would start price requests while this
                    // page shows no dollar value. Only DollarText subscribes.
                    onChanged: (bool enabled) => setState(() {
                      _prices.enabled = enabled;
                    }),
                  ),
                ),
                StreamBuilder<void>(
                  stream: NodeChange.stream,
                  builder:
                      (BuildContext context, AsyncSnapshot<void> snapshot) =>
                          SettingRow(
                            label: context.l10n.displayExplorer,
                            hint: context.l10n.displayExplorerHint,
                            trailing: DropdownMenu<String>(
                              key: const Key('display_explorer'),
                              initialSelection: ExplorerLinks.providerHost,
                              enabled: ExplorerLinks.available(kNodeChainId),
                              selectOnly: true,
                              textStyle: AppTokens.of(context).compactText,
                              inputDecorationTheme: _menuDecoration(context),
                              dropdownMenuEntries: <DropdownMenuEntry<String>>[
                                DropdownMenuEntry<String>(
                                  value: ExplorerLinks.providerHost,
                                  label: ExplorerLinks.providerHost,
                                ),
                              ],
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onThemeModeSelected(ThemeMode themeMode) async {
    Provider.of<AppThemeNotifier>(
      context,
      listen: false,
    ).changeThemeMode(themeMode);
    try {
      await sharedPrefsService?.put(kThemeModeKey, themeMode.toString());
    } on Object catch (e) {
      if (!mounted) return;
      await NotificationUtils.sendNotificationError(
        e,
        context.l10n.displaySaveFailed(context.l10n.displayTheme),
      );
    }
  }

  Future<void> _onTextScalingSelected(TextScaling textScaling) async {
    Provider.of<TextScalingNotifier>(
      context,
      listen: false,
    ).changeTextScaling(textScaling);
    try {
      await sharedPrefsService?.put(kTextScalingKey, textScaling.toString());
    } on Object catch (e) {
      if (!mounted) return;
      await NotificationUtils.sendNotificationError(
        e,
        context.l10n.displaySaveFailed(context.l10n.displayTextSize),
      );
    }
  }

  Future<void> _onLanguageSelected(AppLanguage language) async {
    Provider.of<LocaleNotifier>(
      context,
      listen: false,
    ).changeLanguage(language);
    try {
      await sharedPrefsService?.put(kLanguageKey, language.toString());
    } on Object catch (e) {
      if (!mounted) return;
      await NotificationUtils.sendNotificationError(
        e,
        context.l10n.displaySaveFailed(context.l10n.displayLanguage),
      );
    }
  }
}

/// The languages, each under its own name.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.selected, required this.onSelected});

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    final Color faint = AppTokens.of(context).faint;
    return DropdownMenu<AppLanguage>(
      key: const Key('display_language_menu'),
      initialSelection: selected,
      textStyle: AppTokens.of(context).compactText,
      inputDecorationTheme: _menuDecoration(context),
      dropdownMenuEntries: <DropdownMenuEntry<AppLanguage>>[
        for (final AppLanguage language in AppLanguage.values)
          DropdownMenuEntry<AppLanguage>(
            value: language,
            label: language.nativeName,
          ),
      ],
      onSelected: (AppLanguage? language) {
        if (language != null && language != selected) {
          onSelected(language);
        }
      },
      selectOnly: true,
      trailingIcon: Icon(Icons.keyboard_arrow_down_rounded, color: faint),
      selectedTrailingIcon: Icon(
        Icons.keyboard_arrow_up_rounded,
        color: faint,
      ),
    );
  }
}

InputDecorationThemeData _menuDecoration(BuildContext context) {
  final AppTokens tokens = AppTokens.of(context);
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(tokens.pillRadius),
    borderSide: BorderSide(color: tokens.line),
  );
  return InputDecorationThemeData(
    isDense: true,
    isCollapsed: true,
    filled: true,
    fillColor: tokens.card2,
    constraints: BoxConstraints(minHeight: tokens.settingsMenuHeight),
    suffixIconConstraints: BoxConstraints.tightFor(
      width: tokens.settingsMenuHeight,
      height: tokens.settingsMenuHeight,
    ),
    contentPadding: EdgeInsetsDirectional.symmetric(horizontal: tokens.cardGap),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: tokens.focusRing),
    ),
  );
}
