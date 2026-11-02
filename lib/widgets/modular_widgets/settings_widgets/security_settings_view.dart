import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/backup.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_crypto.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_rows.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';

/// Pure Security presentation. Mounting never opens a wallet or native input.
class SecuritySettingsView extends StatefulWidget {
  /// Effects are explicit injected boundaries, including saved callbacks.
  const SecuritySettingsView({
    required this.presenter,
    required this.captureCrypto,
    required this.hardware,
    required this.onShowSeed,
    required this.onExportVault,
    this.onResetWallet,
    this.isCurrent,
    this.fileDropBuilder,
    super.key,
  });

  /// Owns the positive policy write lane.
  final SecuritySettingsPresenter presenter;

  /// No default crypto or wallet dependency is constructed by this view.
  final SecurityCryptoSession? Function(bool Function() isCurrent)
  captureCrypto;

  /// The captured current wallet type.
  final bool hardware;

  /// Opens an owned seed child only under the original visible section.
  final Future<void> Function(bool Function() isCurrent) onShowSeed;

  /// Acquires the original unlocked seed, then owns both Vault child steps.
  final Future<void> Function(bool Function() isCurrent) onExportVault;

  /// Root captures maintenance before opening its exact confirmation route.
  final void Function(bool Function() isCurrent)? onResetWallet;

  /// A synchronous section epoch supplied by the route owner.
  final bool Function()? isCurrent;

  /// Only production supplies desktop drop registration.
  final SecurityFileDropBuilder? fileDropBuilder;

  @override
  State<SecuritySettingsView> createState() => _SecuritySettingsViewState();
}

class _SecuritySettingsViewState extends State<SecuritySettingsView> {
  bool _visible = true;
  bool _routing = false;
  bool _signOpen = false;
  bool _verifyOpen = false;
  bool _removeOpen = false;
  int _epoch = 0;
  int _signEpoch = 0;
  int _verifyEpoch = 0;
  int _removeEpoch = 0;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of<void>(context)?.isCurrent ?? true);
    if (_visible != visible) {
      _epoch++;
      _visible = visible;
    }
    widget.presenter.setVisible(visible: visible);
  }

  @override
  void didUpdateWidget(SecuritySettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _epoch++;
    if (!identical(oldWidget.presenter, widget.presenter)) {
      oldWidget.presenter.setVisible(visible: false);
      widget.presenter.setVisible(visible: _visible);
    }
  }

  bool Function() _capture() {
    final int epoch = _epoch;
    final bool Function()? external = widget.isCurrent;
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            !mounted ||
            !_visible ||
            epoch != _epoch ||
            (external != null && !external()));
  }

  Future<void> _route(
    bool Function() current,
    Future<void> Function(bool Function() isCurrent) action, {
    required bool export,
  }) async {
    if (_routing || !current()) {
      return;
    }
    final String failed = export
        ? context.l10n.securitySettingsVaultExportFailed
        : context.l10n.securitySettingsSeedFailed;
    setState(() {
      _routing = true;
      _error = null;
    });
    try {
      await action(current);
    } on Object {
      if (current()) {
        setState(() => _error = failed);
      }
    } finally {
      if (mounted) {
        setState(() => _routing = false);
      }
    }
  }

  Future<void> _password(bool Function() current) async {
    if (!current()) {
      return;
    }
    final String unavailable = context.l10n.securitySettingsPasswordUnavailable;
    try {
      await const UnbuiltPasswordChangeMigrationService().change();
    } on SeamNotBuilt {
      if (current()) {
        setState(() => _error = unavailable);
      }
    }
  }

  Future<void> _choose(
    SecuritySettingsPresenter presenter,
    SecurityPreference preference,
    String value,
    List<int> values,
    bool Function() current,
    int epoch,
  ) async {
    if (!current()) {
      return;
    }
    if (value == 'close' || value == 'off') {
      try {
        if (value == 'close') {
          await const UnbuiltSecurityPolicyService().lockOnClose();
        } else {
          await const UnbuiltSecurityPolicyService()
              .disableWrongPasswordLimit();
        }
      } on SeamNotBuilt {
        return;
      }
      return;
    }
    final int? number = int.tryParse(value);
    if (number != null && values.contains(number)) {
      await presenter.choose(preference, number, epoch: epoch);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SecuritySettingsPresenter, SecuritySettingsState>(
    bloc: widget.presenter,
    builder: (BuildContext context, SecuritySettingsState state) {
      final AppTokens tokens = AppTokens.of(context);
      final bool Function() current = _capture();
      final int sign = _signEpoch;
      final int verify = _verifyEpoch;
      final int remove = _removeEpoch;
      final void Function(bool Function())? reset = widget.onResetWallet;
      final SecuritySettingsPresenter presenter = widget.presenter;
      final bool Function()? external = widget.isCurrent;
      return SettingsSection(
        key: const Key('security_settings_page'),
        children: <Widget>[
          _buildPolicies(state, current),
          SecurityBackupPanel(
            hardware: widget.hardware,
            onShow: _routing
                ? null
                : () => unawaited(
                    _route(current, widget.onShowSeed, export: false),
                  ),
            onExport: _routing
                ? null
                : () => unawaited(
                    _route(current, widget.onExportVault, export: true),
                  ),
          ),
          Panel(
            child: Disclosure(
              title: context.l10n.securitySettingsSignMessage,
              keyPrefix: 'security_settings_sign',
              keepAlive: true,
              onChanged: (bool open) {
                if (current()) {
                  setState(() {
                    _signOpen = open;
                    _signEpoch++;
                  });
                }
              },
              child: SecurityCryptoPanel(
                signing: true,
                capture: widget.captureCrypto,
                fileDropBuilder: widget.fileDropBuilder,
                isCurrent: () => current() && _signOpen && sign == _signEpoch,
              ),
            ),
          ),
          Panel(
            child: Disclosure(
              title: context.l10n.securitySettingsVerifySignature,
              keyPrefix: 'security_settings_verify',
              keepAlive: true,
              onChanged: (bool open) {
                if (current()) {
                  setState(() {
                    _verifyOpen = open;
                    _verifyEpoch++;
                  });
                }
              },
              child: SecurityCryptoPanel(
                signing: false,
                capture: widget.captureCrypto,
                fileDropBuilder: widget.fileDropBuilder,
                isCurrent: () =>
                    current() && _verifyOpen && verify == _verifyEpoch,
              ),
            ),
          ),
          Panel(
            child: Disclosure(
              title: context.l10n.securitySettingsRemoveWallet,
              summary: context.l10n.securitySettingsRemoveWalletHint,
              keyPrefix: 'security_settings_remove',
              onChanged: (bool open) {
                if (current()) {
                  setState(() {
                    _removeOpen = open;
                    _removeEpoch++;
                  });
                }
              },
              child: Padding(
                padding: tokens.settingsRowPadding,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SecuritySettingsButton(
                    key: const Key('security_settings_remove_wallet'),
                    label: context.l10n.securitySettingsRemoveWallet,
                    destructive: true,
                    onPressed: reset == null
                        ? null
                        : () {
                            // The root owns intentional question coverage.
                            bool owned() =>
                                mounted &&
                                identical(presenter, widget.presenter) &&
                                _removeOpen &&
                                remove == _removeEpoch &&
                                (external == null || external());
                            if (current() && owned()) {
                              reset(owned);
                            }
                          },
                  ),
                ),
              ),
            ),
          ),
          if (_error != null || state.failed)
            Text(
              _error ?? context.l10n.securitySettingsSaveFailed,
              style: tokens.bodyText.copyWith(color: tokens.error),
            ),
        ],
      );
    },
  );

  Widget _buildPolicies(SecuritySettingsState state, bool Function() current) {
    final AppTokens tokens = AppTokens.of(context);
    final SecuritySettingsPresenter presenter = widget.presenter;
    final int epoch = presenter.epoch;
    final List<int> locks = <int>{
      5,
      15,
      60,
      if (state.lockMinutes != null && state.lockMinutes! > 0)
        state.lockMinutes!,
    }.toList()..sort();
    final List<int> limits = <int>{
      3,
      5,
      10,
      if (state.wrongPasswords != null && state.wrongPasswords! > 0)
        state.wrongPasswords!,
    }.toList()..sort();
    Widget choices(
      SecurityPreference preference,
      List<int> values,
      int? saved,
    ) {
      final bool lock = preference == SecurityPreference.lockMinutes;
      return Segment<String>(
        keyPrefix: lock ? 'security_lock' : 'security_limit',
        items: <SegmentItem<String>>[
          if (!lock)
            SegmentItem<String>(
              value: 'off',
              label: context.l10n.securitySettingsOff,
              seam: Seam.wrongPasswordLimitOff,
            ),
          for (final int value in values)
            SegmentItem<String>(
              value: '$value',
              enabled: !state.busy,
              labelStyle: tokens.dataText,
              label: lock
                  ? value == 60
                        ? context.l10n.securitySettingsHour
                        : context.l10n.securitySettingsMinutes(value)
                  : '$value',
            ),
          if (lock)
            SegmentItem<String>(
              value: 'close',
              label: context.l10n.securitySettingsOnClose,
              seam: Seam.autoLockOnClose,
            ),
        ],
        selected: saved?.toString(),
        onChanged: (String value) => unawaited(
          _choose(presenter, preference, value, values, current, epoch),
        ),
      );
    }

    final String method = Theme.of(context).platform == TargetPlatform.macOS
        ? context.l10n.securitySettingsTouchId
        : context.l10n.securitySettingsWindowsHello;
    return Panel(
      key: const Key('security_settings_policies'),
      child: SettingsList(
        children: <Widget>[
          SecuritySettingRow(
            label: context.l10n.securitySettingsLockAfter,
            hint: state.lockMinutes == null
                ? context.l10n.securitySettingsPolicyUnavailable
                : context.l10n.securitySettingsInactivity,
            control: choices(
              SecurityPreference.lockMinutes,
              locks,
              state.lockMinutes,
            ),
          ),
          SecuritySettingRow(
            label: context.l10n.securitySettingsBiometricUnlock(method),
            hint: context.l10n.securitySettingsBiometricHint,
            control: SeamGate(
              seam: Seam.biometricUnlock,
              key: const Key('security_settings_biometric_gate'),
              child: SettingsSwitch(
                value: false,
                label: context.l10n.securitySettingsBiometricUnlock(method),
                onChanged: (bool value) {
                  if (current()) {
                    unawaited(_biometric());
                  }
                },
              ),
            ),
          ),
          SecuritySettingRow(
            label: context.l10n.securitySettingsWrongPasswordLimit,
            hint: state.wrongPasswords == null
                ? context.l10n.securitySettingsPolicyUnavailable
                : context.l10n.securitySettingsWrongPasswordHint,
            control: choices(
              SecurityPreference.wrongPasswords,
              limits,
              state.wrongPasswords,
            ),
          ),
          SecuritySettingRow(
            label: context.l10n.password,
            control: SeamGate(
              seam: Seam.passwordChangeMigration,
              key: const Key('security_settings_password_gate'),
              child: SecuritySettingsButton(
                key: const Key('security_settings_password'),
                label: context.l10n.securitySettingsChange,
                onPressed: () => unawaited(_password(current)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _biometric() async {
    try {
      await const UnbuiltBiometricUnlockService().unlock();
    } on SeamNotBuilt {
      return;
    }
  }

  @override
  void dispose() {
    _epoch++;
    widget.presenter.setVisible(visible: false);
    super.dispose();
  }
}
