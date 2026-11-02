import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/screens/export/export_wallet_password_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

/// First Vault step. The promise opens only this exact owned export child.
class ExportWalletInfoScreen extends StatefulWidget {
  /// Existing onboarding callers keep their captured seed and completion list.
  const ExportWalletInfoScreen(
    this.seed, {
    this.backupWalletFlow = false,
    this.session,
    this.routeLease,
    this.isCurrent,
    this.onExported,
    super.key,
  });

  /// The seed captured before this route was opened.
  final String seed;

  /// Backup does not mark an onboarding seed as exported.
  final bool backupWalletFlow;

  /// Injected original-resource actions, with no native default in tests.
  final SettingsSensitiveSession? session;

  /// The exact chain supplied by Settings, or attached on this screen.
  final SettingsRouteLease? routeLease;

  /// Captured external authority, independent of intentional child coverage.
  final bool Function()? isCurrent;

  /// The original owner's success effect, awaited before owned navigation.
  final FutureOr<void> Function()? onExported;

  @override
  State<ExportWalletInfoScreen> createState() => _ExportWalletInfoScreenState();
}

class _ExportWalletInfoScreenState extends State<ExportWalletInfoScreen> {
  late final SettingsScreenScope _scope = SettingsScreenScope(
    mounted: () => mounted,
  );
  SettingsRouteLease? _attached;
  SettingsSensitiveSession? _captured;
  bool _promised = false;
  bool _opening = false;
  int _formEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.routeLease == null && _attached == null) {
      final ModalRoute<void>? route = ModalRoute.of<void>(context);
      final bool Function()? external = widget.isCurrent;
      if (route != null) {
        _attached = SettingsRouteLease.attached(
          navigator: Navigator.of(context),
          route: route,
          isCurrent: () => mounted && (external == null || external()),
        );
      }
    }
    _bind();
  }

  void _bind() => _scope.bind(
    context,
    lease: widget.routeLease ?? _attached,
    isCurrent: widget.isCurrent,
  );

  @override
  void didUpdateWidget(ExportWalletInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.routeLease, oldWidget.routeLease) ||
        widget.seed != oldWidget.seed) {
      _scope.revoke();
      _formEpoch++;
      _promised = false;
      _captured = null;
    }
    _bind();
  }

  Future<void> _continue(bool Function() current, int epoch) async {
    if (_opening || !current() || !_promised || epoch != _formEpoch) {
      return;
    }
    final SettingsRouteLease? lease = widget.routeLease ?? _attached;
    if (lease == null) {
      return;
    }
    final String seed = widget.seed;
    final bool backup = widget.backupWalletFlow;
    final bool Function()? external = widget.isCurrent;
    final SettingsSensitiveSession? session =
        widget.session ??
        (_captured ??= captureOnboardingVaultSession(
          isCurrent: () => mounted && (external == null || external()),
          fileType: context.l10n.securitySettingsVaultFileType,
        ));
    if (session == null || !session.isCurrent || session.isHardwareWallet) {
      return;
    }
    FutureOr<void> Function()? completion = widget.onExported;
    if (!backup && completion == null && widget.session == null) {
      final ValueNotifier<List<String>> original =
          Provider.of<ValueNotifier<List<String>>>(context, listen: false);
      completion = () {
        if (mounted && session.isCurrent && (external == null || external())) {
          original.value = <String>[...original.value, seed];
        }
      };
    }
    final FutureOr<void> Function()? originalCompletion = completion;
    setState(() => _opening = true);
    try {
      await lease.push(
        (SettingsRouteLease child) => ExportWalletPasswordScreen(
          seed,
          backupWalletFlow: backup,
          session: session,
          routeLease: child,
          onExported: originalCompletion,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool Function() current = _scope.capture();
    final int epoch = _formEpoch;
    return SettingsScreenFrame(
      title: context.l10n.securitySettingsVaultInfoTitle,
      note: context.l10n.securitySettingsVaultInfo,
      actions: <Widget>[
        ScreenBackAction(
          label: context.l10n.securitySettingsBack,
          onPressed: () => _scope.back(current),
        ),
        OutlinedButton(
          key: const Key('export_seed_vault_continue'),
          style: OutlinedButton.styleFrom(minimumSize: kScreenActionSize),
          onPressed: _promised && !_opening
              ? () => unawaited(_continue(current, epoch))
              : null,
          child: Text(context.l10n.continueText),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const ExportStepLabel(step: 1),
          const SizedBox(height: kSettingFormGap),
          CheckboxListTile(
            key: const Key('export_seed_vault_promise'),
            value: _promised,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              context.l10n.securitySettingsVaultPromise,
              style: AppTokens.of(context).bodyText,
            ),
            onChanged: !_opening
                ? (bool? value) {
                    if (current() && epoch == _formEpoch) {
                      setState(() {
                        _promised = value ?? false;
                        _formEpoch++;
                      });
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scope.revoke();
    _attached?.close();
    super.dispose();
  }
}

/// The localized, tabular step label shared by both existing Vault screens.
class ExportStepLabel extends StatelessWidget {
  /// Creates step one or two.
  const ExportStepLabel({required this.step, super.key});

  /// The exact existing step number.
  final int step;

  @override
  Widget build(BuildContext context) => Text(
    context.l10n.securitySettingsExportStep(step),
    style: ledgerLabelStyle(context),
  );
}
