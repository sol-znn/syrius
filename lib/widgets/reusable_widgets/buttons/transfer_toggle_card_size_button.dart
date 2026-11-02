import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The legacy transfer toggle, held only by the current PoW display owner.
class TransferToggleCardSizeButton extends StatelessWidget {
  /// Uses the existing transfer layout callback and icon.
  const TransferToggleCardSizeButton({
    required this.onPressed,
    required this.iconData,
    super.key,
  });

  /// Changes transfer layout only while generation is inactive.
  final VoidCallback? onPressed;

  /// The layout affordance supplied by its existing caller.
  final IconData iconData;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PowGenerationState>(
      stream: sl.get<PowGeneratingStatusBloc>().stream,
      builder: (_, AsyncSnapshot<PowGenerationState> snapshot) {
        final bool generating =
            !snapshot.hasError &&
            snapshot.connectionState != ConnectionState.done &&
            (snapshot.data?.isGenerating ?? false);
        return _getButton(context, generating ? null : onPressed);
      },
    );
  }

  Widget _getButton(
    BuildContext context,
    VoidCallback? onButtonPressed,
  ) {
    return IconButton(
      onPressed: onButtonPressed,
      icon: Icon(
        iconData,
        color: onButtonPressed == null
            ? AppTokens.of(context).dim
            : Theme.of(context).textTheme.headlineSmall!.color,
      ),
    );
  }
}
