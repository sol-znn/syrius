import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_action_dialog.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The retained legacy Mint entry uses the row's exact proof and sender.
class MintTokenView extends StatelessWidget {
  /// Fresh exact token and account reads authorize the described action.
  const MintTokenView({required this._token, this.publisher, super.key});

  final Token _token;

  /// Synthetic sources keep source tests independent of wallets and nodes.
  final TokenActionPublisher? publisher;

  /// Captures the original account and shared sender before opening.
  static Future<void> show(BuildContext context, {required Token token}) =>
      TokenActionDialog.open(context, token: token, mode: TokenActionMode.mint);

  @override
  Widget build(BuildContext context) => TokenActionDialog(
    token: _token,
    mode: TokenActionMode.mint,
    publisher: publisher,
  );
}
