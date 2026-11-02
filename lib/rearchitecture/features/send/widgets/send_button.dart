import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/sheen.dart';

/// The full-width transfer action, with the shared plasma paint and sheen.
class SendButton extends StatefulWidget {
  /// A null callback holds both pointer and keyboard activation.
  const SendButton({
    required this.onPressed,
    required this.text,
    super.key,
  });

  /// Starts the existing confirmation flow.
  final VoidCallback? onPressed;

  /// The exact amount, or the first missing requirement.
  final String text;

  @override
  State<SendButton> createState() => SendButtonState();
}

/// Keeps completion feedback separate from the shared sender's admission.
class SendButtonState extends State<SendButton> {
  final SheenController _sheen = SheenController();
  bool _busy = false;

  /// Reports that this form's original operation has started.
  void animateForward() {
    if (!_busy) setState(() => _busy = true);
  }

  /// Releases this form's display on its original success or failure.
  void animateReverse() {
    if (_busy) setState(() => _busy = false);
  }

  /// Plays one sheen only for an accepted result.
  void landed() => _sheen.pass();

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return SizedBox(
      height: tokens.transferActionHeight,
      child: PrimaryPill(
        onPressed: _busy ? null : widget.onPressed,
        sheen: _sheen,
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(0, tokens.transferActionHeight),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            tokens.transferActionText,
          ),
        ),
        icon: _busy
            ? SizedBox.square(
                dimension: tokens.heroIconSize,
                child: CircularProgressIndicator(
                  strokeWidth: tokens.focusWidth,
                  color: tokens.primaryButtonForeground,
                ),
              )
            : const Icon(Icons.arrow_upward),
        child: Text(widget.text),
      ),
    );
  }
}
