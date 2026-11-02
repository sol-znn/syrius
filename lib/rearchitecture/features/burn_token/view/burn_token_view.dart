import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_action_dialog.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Legacy Burn opens the same complete selected-account proof as the row.
class BurnTokenView extends StatelessWidget {
  /// Public-holder and selected-owner burn permissions remain distinct.
  const BurnTokenView({required this._token, this.publisher, super.key});

  final Token _token;

  /// Explicit injection without wallet or RPC execution.
  final TokenActionPublisher? publisher;

  /// A cached multi-address balance no longer grants burn authority.
  static Future<void> show(BuildContext context, {required Token token}) =>
      TokenActionDialog.open(context, token: token, mode: TokenActionMode.burn);

  @override
  Widget build(BuildContext context) => TokenActionDialog(
    token: _token,
    mode: TokenActionMode.burn,
    publisher: publisher,
  );
}
