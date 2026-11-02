import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_success_surface.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// Waiting and confirmed views of the original sentinel registration.
class SentinelRegisteredSuccess extends StatelessWidget {
  /// Keeps the existing return callback.
  const SentinelRegisteredSuccess({
    required this.onViewSentinelsPressed,
    this.confirmation,
    super.key,
  });

  /// Returns to the sentinel owner view.
  final VoidCallback onViewSentinelsPressed;

  /// The original account, chain and exact positive evidence.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) {
    final RegistrationPublication? publication = confirmation?.publication;
    final BigInt? qsrCost = publication?.qsrCost;
    final AppTokens tokens = AppTokens.of(context);
    return RegistrationSuccessSurface(
      asset: AppLottieAsset.sentinel,
      confirmation: confirmation,
      confirmedKey: const Key('sentinel_registration_confirmed'),
      heading: context.l10n.sentinelRegistered,
      steps: <String>[
        context.l10n.plasmaCheck,
        context.l10n.management(kQsrCoin.symbol),
        context.l10n.management(kZnnCoin.symbol),
        context.l10n.registerSentinel,
      ],
      facts: <Widget>[
        if (qsrCost != null)
          RegistrationReceiptFact(
            label: context.l10n.createSentinelDepositLabel,
            value: AmountText(
              qsrCost,
              decimals: kQsrCoin.decimals,
              symbol: kQsrCoin.symbol,
              style: tokens.dataText,
            ),
          ),
        if (publication != null)
          RegistrationReceiptFact(
            label: context.l10n.createPillarCollateralLabel,
            value: AmountText(
              publication.amount,
              decimals: kZnnCoin.decimals,
              symbol: kZnnCoin.symbol,
              style: tokens.dataText,
            ),
          ),
      ],
      viewLabel: context.l10n.registrationViewSentinel,
      onView: onViewSentinelsPressed,
    );
  }
}

/// The legacy entry point also requires the original positive confirmation.
class SentinelRegisteredSuccessAnimation extends StatelessWidget {
  /// A standalone animation without a confirmation owner stays empty.
  const SentinelRegisteredSuccessAnimation({this.confirmation, super.key});

  /// The original registration's confirmation owner.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) => RegistrationConfirmedArt(
    asset: AppLottieAsset.sentinel,
    confirmation: confirmation,
  );
}
