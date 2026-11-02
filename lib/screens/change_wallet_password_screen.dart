import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_fields.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Draws Change password while the owned recovery migration remains missing.
class ChangeWalletPasswordScreen extends StatefulWidget {
  /// Production has no secret backend. Tests may inject an owned session.
  const ChangeWalletPasswordScreen({
    required this.onStepperNotificationSeeMorePressed,
    this.session,
    this.routeLease,
    this.isCurrent,
    super.key,
  });

  /// Retained for existing callers of this child screen.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Complete owned operation for presentation tests, never a legacy fallback.
  final SettingsPasswordSession? session;

  /// The exact owned route, if opened by Settings.
  final SettingsRouteLease? routeLease;

  /// The original caller's synchronous scope, frozen before suspension.
  final bool Function()? isCurrent;

  @override
  State<ChangeWalletPasswordScreen> createState() =>
      _ChangeWalletPasswordScreenState();
}

class _ChangeWalletPasswordScreenState
    extends State<ChangeWalletPasswordScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  late final SettingsScreenScope _scope = SettingsScreenScope(
    mounted: () => mounted,
  );
  bool _busy = false;
  String? _error;

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
  void didUpdateWidget(ChangeWalletPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.routeLease, oldWidget.routeLease)) {
      _scope.revoke();
    }
    _bind();
  }

  bool get _valid =>
      _current.text.isNotEmpty &&
      InputValidators.validatePassword(_password.text) == null &&
      InputValidators.checkPasswordMatch(_password.text, _repeat.text) == null;

  Future<void> _change(bool Function() current) async {
    if (_busy || !current() || !_valid) {
      return;
    }
    final SettingsPasswordSession? session = widget.session;
    final String oldPassword = _current.text;
    final String newPassword = _password.text;
    final String failed = context.l10n.securitySettingsPasswordChangeFailed;
    final String unavailable = context.l10n.securitySettingsPasswordUnavailable;
    final String incorrect = context.l10n.walletPasswordIncorrectError;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (session == null) {
        // Direct saved callbacks meet the same missing-service boundary.
        await const UnbuiltPasswordChangeMigrationService().change();
        return;
      }
      if (!session.isCurrent) {
        return;
      }
      await session.changePassword(oldPassword, newPassword);
      if (current() && session.isCurrent) {
        _scope.back(current);
      }
    } on SeamNotBuilt {
      if (current()) {
        setState(() => _error = unavailable);
      }
    } on IncorrectPasswordException {
      if (current()) {
        setState(() => _error = incorrect);
      }
    } on Object {
      if (current()) {
        setState(() => _error = failed);
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
    void changed(String _) {
      if (current() && !_busy) {
        setState(() => _error = null);
      }
    }

    final Widget action = OutlinedButton(
      key: const Key('security_password_change'),
      style: OutlinedButton.styleFrom(minimumSize: kScreenActionSize),
      onPressed: !_busy && _valid ? () => unawaited(_change(current)) : null,
      child: Text(context.l10n.securitySettingsChangePassword),
    );
    return SettingsScreenFrame(
      title: context.l10n.securitySettingsChangePassword,
      note: context.l10n.securitySettingsPasswordRules,
      actions: <Widget>[
        ScreenBackAction(
          label: context.l10n.securitySettingsBack,
          onPressed: () => _scope.back(current),
        ),
        if (widget.session == null)
          SeamGate(seam: Seam.passwordChangeMigration, child: action)
        else
          action,
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SettingsSecretField(
            key: const Key('security_password_current'),
            controller: _current,
            label: context.l10n.securitySettingsCurrentPassword,
            isCurrent: current,
            enabled: !_busy,
            onChanged: changed,
            error: _error,
          ),
          const SizedBox(height: kSettingFormGap),
          SettingsSecretField(
            key: const Key('security_password_new'),
            controller: _password,
            label: context.l10n.securitySettingsNewPassword,
            isCurrent: current,
            enabled: !_busy,
            onChanged: changed,
            validator: InputValidators.validatePassword,
          ),
          const SizedBox(height: kSettingFormGap),
          SettingsSecretField(
            key: const Key('security_password_repeat'),
            controller: _repeat,
            label: context.l10n.securitySettingsRepeatPassword,
            isCurrent: current,
            enabled: !_busy,
            onChanged: changed,
            validator: (String? value) =>
                InputValidators.checkPasswordMatch(_password.text, value),
            onSubmitted: (String _) => unawaited(_change(current)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scope.revoke();
    _current.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }
}
