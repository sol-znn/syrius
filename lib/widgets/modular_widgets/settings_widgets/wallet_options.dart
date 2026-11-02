import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_view.dart';

/// Owns the captured Wallet presenter. The root owns navigation and RPC scans.
class WalletOptions extends StatefulWidget {
  /// Optional injection exercises this owning widget without native services.
  const WalletOptions({
    required this.isCurrent,
    required this.scanForReceives,
    required this.onDeleteCache,
    required this.onResetWallet,
    this.senderIsCurrent,
    this.binding,
    super.key,
  });

  /// Frozen Settings section authority, including close/reopen ABA protection.
  final bool Function() isCurrent;

  /// Root captures one receive origin before its fresh discovery scan.
  final Future<void> Function() scanForReceives;

  /// Confirms maintenance and hands off its exact original route.
  final void Function(bool Function() sourceIsCurrent) onDeleteCache;

  /// Opens the root's captured reset question.
  final void Function(bool Function() sourceIsCurrent) onResetWallet;

  /// The root binds the exact worker sender attachment when one exists.
  final bool Function()? senderIsCurrent;

  /// A complete injected original boundary, with no production fallbacks.
  final WalletSettingsBinding? binding;

  @override
  State<WalletOptions> createState() => _WalletOptionsState();
}

class _WalletOptionsState extends State<WalletOptions> {
  late WalletSettingsPresenter _presenter;

  @override
  void initState() {
    super.initState();
    _presenter = _createPresenter();
  }

  WalletSettingsPresenter _createPresenter() => WalletSettingsPresenter(
    binding:
        widget.binding ??
        WalletSettingsBinding.capture(
          scanForReceives: widget.scanForReceives,
          senderIsCurrent: widget.senderIsCurrent,
        ),
  );

  @override
  void didUpdateWidget(WalletOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.binding, widget.binding)) {
      unawaited(_presenter.close());
      _presenter = _createPresenter();
    }
  }

  @override
  Widget build(BuildContext context) => WalletSettingsView(
    presenter: _presenter,
    isCurrent: widget.isCurrent,
    onDeleteCache: widget.onDeleteCache,
    onResetWallet: widget.onResetWallet,
  );

  @override
  void dispose() {
    unawaited(_presenter.close());
    super.dispose();
  }
}

/// Kept for existing imports. Every destructive route belongs to the root.
class WalletReset extends StatelessWidget {
  /// There are no default recapturing or no-op maintenance callbacks.
  const WalletReset({
    required this.onDeleteCache,
    required this.onResetWallet,
    this.isCurrent,
    super.key,
  });

  /// Root-owned cache confirmation and route handoff.
  final void Function(bool Function() sourceIsCurrent) onDeleteCache;

  /// Root-owned reset confirmation and route handoff.
  final void Function(bool Function() sourceIsCurrent) onResetWallet;

  /// Optional original view authority in addition to the guarded callbacks.
  final bool Function()? isCurrent;

  @override
  Widget build(BuildContext context) {
    final bool Function()? authority = isCurrent;
    bool sourceIsCurrent() => context.mounted && (authority?.call() ?? true);
    void owned(void Function(bool Function()) action) {
      if (sourceIsCurrent()) {
        action(sourceIsCurrent);
      }
    }

    return Panel(
      title: context.l10n.walletSettingsMaintenance,
      shrinkWrap: true,
      child: SettingsList(
        children: <Widget>[
          SettingRow(
            label: context.l10n.goToPaletteDeleteCache,
            trailing: TextButton(
              onPressed: () => owned(onDeleteCache),
              child: Text(context.l10n.walletSettingsDelete),
            ),
          ),
          SettingRow(
            label: context.l10n.securitySettingsResetWallet,
            trailing: DangerAction(
              child: OutlinedButton(
                onPressed: () => owned(onResetWallet),
                child: Text(context.l10n.securitySettingsReset),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
