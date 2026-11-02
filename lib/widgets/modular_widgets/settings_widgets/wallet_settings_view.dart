import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';

/// Full-width Wallet settings, with every operation supplied by its owner.
class WalletSettingsView extends StatefulWidget {
  /// Pure presentation never captures preferences or creates native services.
  const WalletSettingsView({
    required this.presenter,
    required this.isCurrent,
    required this.onDeleteCache,
    required this.onResetWallet,
    super.key,
  });

  /// The external owner disposes this adapter after the view unmounts.
  final WalletSettingsPresenter presenter;

  /// Captured Settings section authority supplied by the root owner.
  final bool Function() isCurrent;

  /// Root-owned confirmation and exact maintenance route handoff.
  final void Function(bool Function() sourceIsCurrent) onDeleteCache;

  /// Root-owned reset confirmation without recapturing mutable globals here.
  final void Function(bool Function() sourceIsCurrent) onResetWallet;

  @override
  State<WalletSettingsView> createState() => _WalletSettingsViewState();
}

class _WalletSettingsViewState extends State<WalletSettingsView>
    with WidgetsBindingObserver {
  final DisclosureController _maintenance = DisclosureController();
  int _epoch = 0;
  int _sourceEpoch = 0;
  int _maintenanceEpoch = 0;
  bool _visible = true;
  bool _windowActive = true;
  FocusNode? _parentFocus;
  ModalRoute<dynamic>? _route;

  bool get _focusAllowsInput =>
      _parentFocus == null ||
      (_parentFocus!.descendantsAreFocusable &&
          _parentFocus!.ancestors.every(
            (FocusNode node) => node.descendantsAreFocusable,
          ));

  bool get _sourceVisible =>
      _windowActive &&
      widget.isCurrent() &&
      _focusAllowsInput &&
      (_route?.isCurrent ?? true);

  bool get _current => mounted && _visible && _sourceVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maintenance.addListener(_maintenanceChanged);
  }

  void _maintenanceChanged() {
    if (!_maintenance.isOpen) {
      _maintenanceEpoch++;
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parentFocus = Focus.maybeOf(context, scopeOk: true);
    _route = ModalRoute.of(context);
    _setVisible(_sourceVisible && TickerMode.valuesOf(context).enabled);
  }

  void _setVisible(bool visible) {
    if (_visible && !visible) {
      _epoch++;
    }
    _visible = visible;
  }

  @override
  void didUpdateWidget(WalletSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter) ||
        !oldWidget.isCurrent()) {
      _epoch++;
      _sourceEpoch++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_windowActive && state != AppLifecycleState.resumed) {
      _sourceEpoch++;
    }
    _windowActive = state == AppLifecycleState.resumed;
    _setVisible(_sourceVisible && TickerMode.valuesOf(context).enabled);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _epoch++;
    _sourceEpoch++;
    _maintenanceEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _maintenance
      ..removeListener(_maintenanceChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WalletSettingsPresenter owner = widget.presenter;
    final bool Function() external = widget.isCurrent;
    final int epoch = _epoch;
    final int sourceEpoch = _sourceEpoch;
    final int maintenanceEpoch = _maintenanceEpoch;
    final bool maintenanceOpen = _maintenance.isOpen;
    bool current() =>
        identical(owner, widget.presenter) &&
        epoch == _epoch &&
        _current &&
        external();
    bool maintenanceCurrent() =>
        maintenanceOpen &&
        maintenanceEpoch == _maintenanceEpoch &&
        _maintenance.isOpen &&
        current();
    // An owned question covers this route and takes its focus. Source
    // authority survives that exact coverage, while input still uses current.
    bool sourceIsCurrent() =>
        mounted &&
        identical(owner, widget.presenter) &&
        sourceEpoch == _sourceEpoch &&
        _windowActive &&
        external();
    bool maintenanceSourceIsCurrent() =>
        maintenanceOpen &&
        maintenanceEpoch == _maintenanceEpoch &&
        _maintenance.isOpen &&
        sourceIsCurrent();
    return BlocBuilder<WalletSettingsPresenter, WalletSettingsState>(
      bloc: owner,
      builder: (BuildContext context, WalletSettingsState state) =>
          SettingsSection(
            key: const Key('wallet_settings_page'),
            children: <Widget>[
              Panel(
                key: const Key('wallet_settings_preferences'),
                child: SettingsList(
                  children: <Widget>[
                    _buildPreference(
                      state,
                      WalletPreference.autoReceive,
                      context.l10n.walletSettingsAutoReceive,
                      current,
                      hint: context.l10n.walletSettingsAutoReceiveHint,
                    ),
                    _buildPreference(
                      state,
                      WalletPreference.desktopNotifications,
                      context.l10n.walletSettingsDesktopNotifications,
                      current,
                    ),
                    _buildPreference(
                      state,
                      WalletPreference.launchAtStartup,
                      context.l10n.walletSettingsLaunchAtStartup,
                      current,
                    ),
                    _buildModes(),
                    SettingRow(
                      label: context.l10n.goToPaletteDeleteCache,
                      hint: context.l10n.walletSettingsCacheHint,
                      trailing: SecondaryAction(
                        child: TextButton(
                          key: const Key('wallet_settings_delete_cache'),
                          onPressed: current()
                              ? () {
                                  if (current()) {
                                    widget.onDeleteCache(sourceIsCurrent);
                                  }
                                }
                              : null,
                          child: Text(context.l10n.walletSettingsDelete),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SeamGate(
                key: const Key('wallet_settings_wallets_gate'),
                seam: Seam.walletPicker,
                child: Disclosure(
                  title: context.l10n.walletSettingsWallets,
                  summary: context.l10n.walletSettingsWalletsHint,
                  keyPrefix: 'wallet_settings_wallets',
                  child: const SizedBox.shrink(),
                ),
              ),
              Disclosure(
                title: context.l10n.walletSettingsMaintenance,
                controller: _maintenance,
                keepAlive: true,
                keyPrefix: 'wallet_settings_maintenance',
                child: Panel(
                  child: SettingsList(
                    children: <Widget>[
                      _buildPreference(
                        state,
                        WalletPreference.clipboard,
                        context.l10n.walletSettingsClipboard,
                        maintenanceCurrent,
                        hint: context.l10n.walletSettingsClipboardHint,
                      ),
                      SettingRow(
                        label: context.l10n.securitySettingsResetWallet,
                        trailing: DangerAction(
                          child: OutlinedButton(
                            key: const Key('wallet_settings_reset_wallet'),
                            onPressed: maintenanceCurrent()
                                ? () {
                                    if (maintenanceCurrent()) {
                                      widget.onResetWallet(
                                        maintenanceSourceIsCurrent,
                                      );
                                    }
                                  }
                                : null,
                            child: Text(context.l10n.securitySettingsReset),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildPreference(
    WalletSettingsState state,
    WalletPreference preference,
    String label,
    bool Function() current, {
    String? hint,
  }) {
    final bool? value = state.values[preference];
    final WalletPreferenceStatus? failure = state.failures[preference];
    return SettingRow(
      key: ValueKey<String>('wallet_settings_row_${preference.name}'),
      label: label,
      hint: hint,
      trailing: value == null
          ? Text(
              context.l10n.walletSettingsUnavailable,
              style: settingHintStyle(context),
            )
          : SettingsSwitch(
              key: ValueKey<String>('wallet_settings_${preference.name}'),
              label: label,
              value: value,
              onChanged:
                  state.available &&
                      !state.busy.contains(preference) &&
                      current()
                  ? (bool next) {
                      if (!current()) {
                        return;
                      }
                      final Future<WalletPreferenceOutcome>? operation = widget
                          .presenter
                          .change(preference, value: next, isCurrent: current);
                      if (operation != null) {
                        unawaited(operation.then<void>((_) {}));
                      }
                    }
                  : null,
            ),
      below: failure == null
          ? null
          : Text(
              failure == WalletPreferenceStatus.saveFailed
                  ? context.l10n.walletSettingsSaveFailed
                  : context.l10n.walletSettingsApplyFailed,
              style: settingErrorStyle(context),
            ),
    );
  }

  Widget _buildModes() => SeamGate(
    key: const Key('wallet_settings_modes_gate'),
    seam: Seam.operatorModes,
    child: Padding(
      padding: AppTokens.of(context).settingsRowPadding,
      child: Wrap(
        spacing: AppTokens.of(context).pageGap,
        runSpacing: AppTokens.of(context).inlineGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.l10n.walletSettingsModes),
              Text(
                context.l10n.walletSettingsModesHint,
                style: settingHintStyle(context),
              ),
            ],
          ),
          for (final String label in <String>[
            context.l10n.pillar,
            context.l10n.sentinel,
            context.l10n.nodeSettingsSporks,
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label),
                SizedBox(width: AppTokens.of(context).inlineGap),
                ChoicePills<String>(
                  values: const <String>['auto', 'on', 'off'],
                  // No backing policy exists, so no effective mode is claimed.
                  selected: null,
                  labelOf: (String mode) => switch (mode) {
                    'auto' => context.l10n.walletSettingsAuto,
                    'on' => context.l10n.walletSettingsOn,
                    _ => context.l10n.walletSettingsOff,
                  },
                  onSelected: (_) => runUnlessSeamed(
                    seam: Seam.operatorModes,
                    action: () {},
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
