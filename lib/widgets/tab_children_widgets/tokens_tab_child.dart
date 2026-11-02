import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/tokens.dart';

/// Tokens has one ledger with the selected address's balance in each row.
class TokensTabChild extends StatelessWidget {
  /// Preserves the existing create-token notification route.
  const TokensTabChild({
    required this._onStepperNotificationSeeMorePressed,
    this.controller,
    this.onSendToken,
    super.key,
  });

  final VoidCallback _onStepperNotificationSeeMorePressed;

  /// The shell retains filter, query and scroll across ordinary navigation.
  final TokensPageController? controller;

  /// Opens the original selected token in the shell's Send mode.
  final ValueChanged<String>? onSendToken;

  @override
  Widget build(BuildContext context) => TokensPage(
    controller: controller,
    onSendToken: onSendToken,
    onStepperNotificationSeeMorePressed: _onStepperNotificationSeeMorePressed,
  );
}
