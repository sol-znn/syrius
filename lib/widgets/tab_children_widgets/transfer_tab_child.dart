import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';

/// Transfer's single card, with the wallet's live forms and pending blocks.
class TransferTabChild extends StatelessWidget {
  /// Creates Transfer, optionally retaining its mode in the session shell.
  const TransferTabChild({this.controller, super.key});

  /// The session's selected mode and active refresh callback.
  final TransferController? controller;

  @override
  Widget build(BuildContext context) => TransferPage(controller: controller);
}
