import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/screens/dump_mnemonic_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/export/export_wallet_info_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_rows.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

/// Seed and Vault rows with injected actions and no native presentation work.
class SecurityBackupPanel extends StatelessWidget {
  /// Hardware seeds remain unavailable through both existing actions.
  const SecurityBackupPanel({
    required this.hardware,
    required this.onShow,
    required this.onExport,
    super.key,
  });

  /// The original wallet type, never inferred from a pending operation.
  final bool hardware;

  /// Shows the password route for the original software wallet.
  final VoidCallback? onShow;

  /// Reads the original unlocked seed before opening the Vault steps.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Panel(
      key: const Key('security_settings_backup'),
      title: context.l10n.securitySettingsBackup,
      shrinkWrap: true,
      child: SettingsList(
        children: <Widget>[
          SecuritySettingRow(
            label: context.l10n.securitySettingsSeedPhrase,
            hint: hardware
                ? context.l10n.securitySettingsHardwareBackupHint
                : context.l10n.securitySettingsSeedPhraseHint,
            control: SecuritySettingsButton(
              key: const Key('security_settings_show_seed'),
              label: context.l10n.securitySettingsShow,
              symbol: 'eye',
              onPressed: hardware ? null : onShow,
            ),
          ),
          SecuritySettingRow(
            label: context.l10n.securitySettingsSeedVault,
            hint: hardware
                ? context.l10n.securitySettingsHardwareBackupHint
                : context.l10n.securitySettingsSeedVaultHint,
            control: SecuritySettingsButton(
              key: const Key('security_settings_export_vault'),
              label: context.l10n.securitySettingsExport,
              symbol: 'dl',
              onPressed: hardware ? null : onExport,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compatibility owner for callers that display Backup on its own.
class BackupWidget extends StatefulWidget {
  /// A caller may bind the same synchronous Settings section epoch.
  const BackupWidget({this.isCurrent, super.key});

  /// Captured by each action before any awaited wallet acquisition.
  final bool Function()? isCurrent;

  @override
  State<BackupWidget> createState() => _BackupWidgetState();
}

class _BackupWidgetState extends State<BackupWidget> {
  SettingsSensitiveRoutes _routes = SettingsSensitiveRoutes();
  late final SettingsScreenScope _scope = SettingsScreenScope(
    mounted: () => mounted,
  );
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WalletContextRevision.changes.addListener(_onRevision);
  }

  void _onRevision() {
    _scope.revoke();
    _routes.close();
    _routes = SettingsSensitiveRoutes();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope.bind(context, isCurrent: widget.isCurrent);
  }

  @override
  void didUpdateWidget(BackupWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scope
      ..revoke()
      ..bind(context, isCurrent: widget.isCurrent);
  }

  Future<void> _open(bool Function() visible, {required bool export}) async {
    final bool Function()? external = widget.isCurrent;
    final ModalRoute<void>? parent = ModalRoute.of<void>(context);
    if (_busy ||
        !visible() ||
        !(parent?.isCurrent ?? false) ||
        (external != null && !external())) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final String fileType = context.l10n.securitySettingsVaultFileType;
    final String title = context.l10n.securitySettingsVaultExported;
    final SettingsSensitiveRoutes routes = _routes;
    bool source() => mounted && (external == null || external());
    setState(() => _busy = true);
    try {
      final SettingsSensitiveSession? session = captureSettingsSensitiveSession(
        isCurrent: source,
        fileType: fileType,
      );
      if (session == null || session.isHardwareWallet) {
        return;
      }
      final NotificationsBloc? notifications = export
          ? app.sl.get<NotificationsBloc>()
          : null;
      final String? seed = export
          ? await session.readExportSeed(
              isCurrent: visible,
            )
          : null;
      if (!visible() || !source() || !session.isCurrent || !parent!.isCurrent) {
        return;
      }
      await routes.open(
        navigator: navigator,
        isCurrent: () => source() && session.isCurrent,
        builder: (SettingsRouteLease lease) => export
            ? ExportWalletInfoScreen(
                seed!,
                session: session,
                routeLease: lease,
                backupWalletFlow: true,
                onExported: () async {
                  final bool Function() child = lease.capture();
                  if (source() && session.isCurrent && child()) {
                    await notifications!.addNotification(
                      WalletNotification(
                        title: title,
                        details: '',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        type: NotificationType.paymentSent,
                      ),
                      shouldDisplay: () =>
                          child() && source() && session.isCurrent,
                    );
                  }
                },
              )
            : DumpMnemonicScreen(session: session, routeLease: lease),
      );
    } on Object {
      // Child screens display their localized result only in their own scope.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool Function() visible = _scope.capture();
    return SecurityBackupPanel(
      hardware: kWalletFile?.isHardwareWallet ?? true,
      onShow: _busy ? null : () => unawaited(_open(visible, export: false)),
      onExport: _busy ? null : () => unawaited(_open(visible, export: true)),
    );
  }

  @override
  void dispose() {
    WalletContextRevision.changes.removeListener(_onRevision);
    _scope.revoke();
    _routes.close();
    super.dispose();
  }
}
