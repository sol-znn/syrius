import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/wallet_ready_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_ready_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/main_app_container.dart';

/// The final step for the exact file that completed initialization.
class WalletSuccessScreen extends StatefulWidget {
  /// Captures Ready against the exact successfully initialized original file.
  const WalletSuccessScreen({
    required this.originalFile,
    this.progressBarNumLevels = 5,
    this.imported = false,
    super.key,
  });

  /// Legacy caller flow length retained for source-compatible entry routes.
  final int progressBarNumLevels;

  /// Passed by the successful creation owner, before selecting a node.
  final WalletFile originalFile;

  /// Imported wallets did not perform the new-wallet seed quiz.
  final bool imported;

  @override
  State<WalletSuccessScreen> createState() => _WalletSuccessScreenState();
}

class _WalletSuccessScreenState extends State<WalletSuccessScreen> {
  late final WalletFile _originalFile = widget.originalFile;
  late final WalletReadyBinding? _binding = WalletReadyBinding.capture(
    expectedFile: widget.originalFile,
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: WalletContextRevision.changes,
    builder: (BuildContext context, int _, Widget? child) => WalletReadySurface(
      binding: identical(widget.originalFile, _originalFile) ? _binding : null,
      hardware: widget.originalFile.isHardwareWallet,
      imported: widget.imported,
      onCopy: (String address) async {
        try {
          await Clipboard.setData(ClipboardData(text: address));
        } on Object {
          // An unavailable clipboard never creates a success notification.
          return;
        }
      },
      onOpen: () {
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: MainAppContainer.route),
            builder: (_) =>
                const MainAppContainer(redirectedFromWalletSuccess: true),
          ),
          (_) => false,
        );
      },
    ),
  );
}
