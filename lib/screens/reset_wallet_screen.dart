import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';

/// The confirmation before the wallet is erased from this computer.
///
/// Reset is the red outline, never the filled action, and Cancel takes the
/// focus first, so Enter on arrival does not erase anything.
class ResetWalletScreen extends StatelessWidget {
  /// The original owner captures every resource before creating this screen.
  const ResetWalletScreen({
    required this.request,
    required this.onConfirm,
    super.key,
  });

  /// The exact original question and cleanup capability.
  final WalletMaintenanceRequest request;

  /// Replaces only the exact source Main while this question covers it.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final ModalRoute<dynamic>? originalRoute = ModalRoute.of(context);
    final bool reset = request.kind == WalletMaintenanceKind.reset;
    return ListenableBuilder(
      listenable: WalletContextRevision.changes,
      builder: (_, _) => SettingsScreenFrame(
        title: reset
            ? context.l10n.securitySettingsResetWallet
            : context.l10n.goToPaletteDeleteCache,
        note: reset
            ? context.l10n.securitySettingsResetWarning
            : context.l10n.walletSettingsCacheHint,
        actions: <Widget>[
          ScreenBackAction(
            label: context.l10n.cancel,
            autofocus: true,
            onPressed: () {
              if (context.mounted && request.ownsCancellation(originalRoute)) {
                request.cancel();
                request.navigator.pop();
              }
            },
          ),
          DangerAction(
            child: OutlinedButton(
              key: const Key('reset_wallet_confirm'),
              style: OutlinedButton.styleFrom(minimumSize: kScreenActionSize),
              onPressed: request.ownsQuestion(originalRoute)
                  ? () {
                      if (context.mounted &&
                          request.ownsQuestion(originalRoute)) {
                        onConfirm();
                      }
                    }
                  : null,
              child: Text(
                reset
                    ? context.l10n.securitySettingsReset
                    : context.l10n.walletSettingsDelete,
              ),
            ),
          ),
        ],
        child: request.canApprove
            ? const SizedBox.shrink()
            : Text(context.l10n.walletSettingsUnavailable),
      ),
    );
  }
}
