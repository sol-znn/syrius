import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/cancel_plasma/view/cancel_countdown.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Presentation for an owned cancellation. The page freezes facts and questions
/// through its shared owner rather than creating an independent row sender.
class CancelPlasmaButton extends StatelessWidget {
  /// Creates a button whose owner supplies the guarded cancellation action.
  const CancelPlasmaButton({
    required this.plasmaHash,
    required this.amount,
    required this.onCancelled,
    this.onPressed,
    this.unlocksIn,
    this.onUnlocked,
    super.key,
  });

  /// The complete original fusion hash shown by the tooltip.
  final Hash plasmaHash;

  /// The original fusion amount in QSR smallest units.
  final BigInt amount;

  /// Legacy completion hook retained for existing callers.
  final VoidCallback onCancelled;

  /// The owner's action that captures exact facts before asking the user.
  final VoidCallback? onPressed;

  /// Optional display estimate; the owner checks the actual frontier again.
  final Duration? unlocksIn;

  /// Requests a fresh owner read after the displayed countdown finishes.
  final VoidCallback? onUnlocked;

  @override
  Widget build(BuildContext context) {
    final Duration? left = unlocksIn;
    if (left != null) {
      return CancelCountdown(
        duration: left,
        onFinished: onUnlocked ?? () {},
        builder: (BuildContext context, String text) => Tooltip(
          message: context.l10n.cancelUnlocksIn(text),
          child: OutlinedButton.icon(
            style: cardSecondaryButtonStyle(context),
            onPressed: null,
            icon: const Icon(Icons.lock_clock_outlined),
            label: Text(context.l10n.cancel),
          ),
        ),
      );
    }
    return Tooltip(
      message: plasmaHash.toString(),
      child: OutlinedButton(
        style: cardSecondaryButtonStyle(context),
        onPressed: onPressed,
        child: Text(context.l10n.cancel),
      ),
    );
  }
}
