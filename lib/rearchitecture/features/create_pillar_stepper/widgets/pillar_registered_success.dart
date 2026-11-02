import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_success_surface.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// Waiting and confirmed views of the original pillar registration.
class PillarRegisteredSuccess extends StatelessWidget {
  /// Existing callbacks retain their navigation and explicit reset meanings.
  const PillarRegisteredSuccess({
    required this.onRegisterAnotherPressed,
    required this.onViewPillarsPressed,
    this.confirmation,
    super.key,
  });

  /// Starts another registration only after this one is confirmed.
  final VoidCallback onRegisterAnotherPressed;

  /// Returns to the pillar owner view.
  final VoidCallback onViewPillarsPressed;

  /// The original account, chain and exact positive evidence.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) {
    final RegistrationPublication? publication = confirmation?.publication;
    final String? name = publication?.name;
    final BigInt? qsrCost = publication?.qsrCost;
    final AppTokens tokens = AppTokens.of(context);
    return RegistrationSuccessSurface(
      asset: AppLottieAsset.pillar,
      confirmation: confirmation,
      confirmedKey: const Key('pillar_registration_confirmed'),
      heading: name == null || name.isEmpty
          ? context.l10n.pillarRegistered
          : context.l10n.registrationPillarRegistered(name),
      caption: context.l10n.registrationPillarReady,
      steps: <String>[
        context.l10n.plasmaCheck,
        context.l10n.management(kQsrCoin.symbol),
        context.l10n.management(kZnnCoin.symbol),
        context.l10n.registerPillar,
      ],
      facts: <Widget>[
        if (qsrCost != null)
          RegistrationReceiptFact(
            label: context.l10n.createPillarSlotFeeLabel,
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
      viewLabel: context.l10n.registrationViewPillar,
      onView: onViewPillarsPressed,
      anotherLabel: context.l10n.registerAnotherPillar,
      onAnother: onRegisterAnotherPressed,
    );
  }
}

/// The legacy entry point also requires the original positive confirmation.
class PillarRegisteredSuccessAnimation extends StatelessWidget {
  /// A standalone animation without a confirmation owner stays empty.
  const PillarRegisteredSuccessAnimation({this.confirmation, super.key});

  /// The original registration's confirmation owner.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) => RegistrationConfirmedArt(
    asset: AppLottieAsset.pillar,
    confirmation: confirmation,
  );
}
