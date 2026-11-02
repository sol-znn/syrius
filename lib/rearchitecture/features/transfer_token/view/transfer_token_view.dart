import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_action_dialog.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Transfers ownership using freshly read, unchanged contract flags.
class TransferTokenView extends StatelessWidget {
  /// The new owner is frozen before the confirmation opens.
  const TransferTokenView({required this._token, this.publisher, super.key});

  final Token _token;

  /// Explicit injection without wallet or signing access.
  final TokenActionPublisher? publisher;

  /// Captures the existing shell sender before crossing the dialog boundary.
  static Future<void> show(BuildContext context, {required Token token}) =>
      TokenActionDialog.open(
        context,
        token: token,
        mode: TokenActionMode.transfer,
      );

  @override
  Widget build(BuildContext context) => TokenActionDialog(
    token: _token,
    mode: TokenActionMode.transfer,
    publisher: publisher,
  );
}
