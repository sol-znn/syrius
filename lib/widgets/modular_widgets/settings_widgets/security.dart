import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/screens/dump_mnemonic_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/export/export_wallet_info_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

/// Owns captured Security effects behind the pure, single-column section.
class SecurityWidget extends StatefulWidget {
  /// Awaits the original lock-policy callback after its saved preference.
  const SecurityWidget(
    this._onPolicyChanged, {
    required this.onStepperNotificationSeeMorePressed,
    this.isCurrent,
    this.onResetWallet,
    super.key,
  });

  final FutureOr<void> Function() _onPolicyChanged;

  /// Retained for callers sharing the existing notification navigation.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Root binds a captured section epoch so leaving cannot revive old work.
  final bool Function()? isCurrent;

  /// Root captures destructive maintenance before pushing its owned question.
  final void Function(bool Function() isCurrent)? onResetWallet;

  @override
  State<SecurityWidget> createState() => _SecurityWidgetState();
}

class _SecurityWidgetState extends State<SecurityWidget> {
  late SecuritySettingsPresenter _presenter;
  SettingsSensitiveRoutes _routes = SettingsSensitiveRoutes();
  Object? _sensitiveOperation;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _presenter = _createPresenter();
    WalletContextRevision.changes.addListener(_onRevision);
  }

  SecuritySettingsPresenter _createPresenter() => SecuritySettingsPresenter(
    initial: readSecuritySettingsState(),
    capture: () {
      final bool Function() current = _captureSection(requireVisible: true);
      final FutureOr<void> Function() callback = widget._onPolicyChanged;
      return captureSecurityPolicy(
        isCurrent: current,
        onPolicyChanged: callback,
        lockChanged: context.l10n.securitySettingsLockChanged,
        limitChanged: context.l10n.securitySettingsLimitChanged,
      );
    },
  );

  void _onRevision() {
    _generation++;
    _routes.close();
    _routes = SettingsSensitiveRoutes();
    unawaited(_presenter.close());
    if (mounted) {
      setState(() => _presenter = _createPresenter());
    }
  }

  bool Function() _captureSection({required bool requireVisible}) {
    final bool Function()? external = widget.isCurrent;
    final int generation = _generation;
    final ModalRoute<void>? route = ModalRoute.of<void>(context);
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            !mounted ||
            generation != _generation ||
            (external != null && !external()) ||
            (requireVisible && !(route?.isCurrent ?? false)));
  }

  Future<void> _openSensitive(
    bool Function() visible, {
    required bool export,
  }) async {
    if (!visible() || _routes.busy || _sensitiveOperation != null) {
      return;
    }
    final Object operation = Object();
    _sensitiveOperation = operation;
    try {
      final bool Function() source = _captureSection(requireVisible: false);
      final NavigatorState navigator = Navigator.of(context);
      final SettingsSensitiveRoutes routes = _routes;
      final String title = context.l10n.securitySettingsVaultExported;
      final SettingsSensitiveSession? session = captureSettingsSensitiveSession(
        isCurrent: source,
        fileType: context.l10n.securitySettingsVaultFileType,
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
      if (!visible() || !source() || !session.isCurrent) {
        return;
      }
      await routes.open(
        navigator: navigator,
        isCurrent: () => source() && session.isCurrent,
        builder: (SettingsRouteLease lease) => export
            ? ExportWalletInfoScreen(
                seed!,
                backupWalletFlow: true,
                session: session,
                routeLease: lease,
                onExported: () async {
                  final bool Function() child = lease.capture();
                  if (source() && session.isCurrent) {
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
    } finally {
      if (identical(operation, _sensitiveOperation)) {
        _sensitiveOperation = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool Function() visible = _captureSection(requireVisible: true);
    final bool Function() source = _captureSection(requireVisible: false);
    final void Function(bool Function())? reset = widget.onResetWallet;
    return SecuritySettingsView(
      key: ValueKey<int>(_generation),
      presenter: _presenter,
      hardware: kWalletFile?.isHardwareWallet ?? true,
      isCurrent: source,
      captureCrypto: (bool Function() current) => captureSecurityCrypto(
        isCurrent: () => visible() && current(),
      ),
      onShowSeed: (bool Function() current) =>
          _openSensitive(current, export: false),
      onExportVault: (bool Function() current) =>
          _openSensitive(current, export: true),
      onResetWallet: reset,
      fileDropBuilder: (Widget child, ValueChanged<String> onPath) =>
          DropTarget(
            onDragDone: (DropDoneDetails details) {
              if (details.files.isNotEmpty) {
                onPath(details.files.first.path);
              }
            },
            child: child,
          ),
    );
  }

  @override
  void dispose() {
    WalletContextRevision.changes.removeListener(_onRevision);
    _generation++;
    _routes.close();
    unawaited(_presenter.close());
    super.dispose();
  }
}
