import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/screens/export/export_wallet_info_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_actions.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_fields.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

/// Captures the Vault key once, then waits for the original export receipt.
class ExportWalletPasswordScreen extends StatefulWidget {
  /// Existing callers can still provide the original seed and Backup mode.
  const ExportWalletPasswordScreen(
    this.seed, {
    this.backupWalletFlow = false,
    this.session,
    this.routeLease,
    this.isCurrent,
    this.onExported,
    super.key,
  });

  /// The seed from the original first step.
  final String seed;

  /// Retained for existing Backup and onboarding callers.
  final bool backupWalletFlow;

  /// The original owned action; tests supply one with no native effects.
  final SettingsSensitiveSession? session;

  /// A completed export removes this chain, never unrelated covering routes.
  final SettingsRouteLease? routeLease;

  /// The original external source scope.
  final bool Function()? isCurrent;

  /// The original success effect, only while its child still owns the UI.
  final FutureOr<void> Function()? onExported;

  @override
  State<ExportWalletPasswordScreen> createState() =>
      _ExportWalletPasswordScreenState();
}

class _ExportWalletPasswordScreenState
    extends State<ExportWalletPasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  late final SettingsScreenScope _scope = SettingsScreenScope(
    mounted: () => mounted,
  );
  SettingsSensitiveSession? _captured;
  bool _busy = false;
  bool _writeUncertain = false;
  String? _error;
  int _formEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  void _bind() => _scope.bind(
    context,
    lease: widget.routeLease,
    isCurrent: widget.isCurrent,
  );

  @override
  void didUpdateWidget(ExportWalletPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.routeLease, oldWidget.routeLease) ||
        oldWidget.seed != widget.seed) {
      _scope.revoke();
      _formEpoch++;
      _captured = null;
      _password.clear();
      _repeat.clear();
    }
    _bind();
  }

  bool get _valid =>
      InputValidators.validatePassword(_password.text) == null &&
      InputValidators.checkPasswordMatch(_password.text, _repeat.text) == null;

  Future<void> _export(bool Function() current, int epoch) async {
    if (_busy ||
        _writeUncertain ||
        !current() ||
        epoch != _formEpoch ||
        !_valid) {
      return;
    }
    final String seed = widget.seed;
    final String password = _password.text;
    final String failed = context.l10n.securitySettingsVaultExportFailed;
    final String uncertain = context.l10n.securitySettingsVaultExportUncertain;
    final SettingsRouteLease? lease = widget.routeLease;
    final FutureOr<void> Function()? onExported = widget.onExported;
    final SettingsSensitiveSession? session =
        widget.session ??
        (_captured ??= captureOnboardingVaultSession(
          isCurrent: current,
          fileType: context.l10n.securitySettingsVaultFileType,
        ));
    if (session == null || !session.isCurrent || session.isHardwareWallet) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bool exported = await session.exportVault(
        seed: seed,
        password: password,
        isCurrent: () => current() && epoch == _formEpoch,
      );
      if (!exported || !current() || !session.isCurrent) {
        return;
      }
      if (onExported != null) {
        try {
          await onExported();
        } on Object {
          // A notification failure cannot replace a completed write receipt.
        }
      }
      if (!current() || !session.isCurrent) {
        return;
      }
      if (lease == null) {
        _scope.back(current);
      } else {
        lease.complete(current);
      }
    } on Object {
      if (current() && session.isCurrent) {
        setState(() {
          _writeUncertain =
              session is SettingsSensitiveActions &&
              session.outcome == SettingsVaultOutcome.uncertain;
          _error = _writeUncertain ? uncertain : failed;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool Function() current = _scope.capture();
    final int epoch = _formEpoch;
    void changed(String _) {
      if (current() && !_busy && !_writeUncertain && epoch == _formEpoch) {
        setState(() {
          _formEpoch++;
          _error = null;
        });
      }
    }

    return SettingsScreenFrame(
      title: context.l10n.securitySettingsVaultKey,
      note: context.l10n.securitySettingsVaultKeyRules,
      actions: <Widget>[
        ScreenBackAction(
          label: context.l10n.securitySettingsBack,
          onPressed: () => _scope.back(current),
        ),
        OutlinedButton(
          key: const Key('export_seed_vault_export'),
          style: OutlinedButton.styleFrom(minimumSize: kScreenActionSize),
          onPressed: !_busy && !_writeUncertain && _valid
              ? () => unawaited(_export(current, epoch))
              : null,
          child: Text(context.l10n.securitySettingsExport),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const ExportStepLabel(step: 2),
          const SizedBox(height: kSettingFormGap),
          SettingsSecretField(
            key: const Key('security_vault_key'),
            controller: _password,
            label: context.l10n.securitySettingsVaultKey,
            isCurrent: current,
            enabled: !_busy && !_writeUncertain,
            error: _error,
            validator: InputValidators.validatePassword,
            onChanged: changed,
          ),
          const SizedBox(height: kSettingFormGap),
          SettingsSecretField(
            key: const Key('security_vault_repeat'),
            controller: _repeat,
            label: context.l10n.securitySettingsRepeatVaultKey,
            isCurrent: current,
            enabled: !_busy && !_writeUncertain,
            onChanged: changed,
            validator: (String? value) =>
                InputValidators.checkPasswordMatch(_password.text, value),
            onSubmitted: (String _) => unawaited(_export(current, epoch)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scope.revoke();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }
}
