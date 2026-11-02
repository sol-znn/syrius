import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_success_surface.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// Waiting and confirmed views of the original token issuance.
class TokenCreatedSuccess extends StatelessWidget {
  /// Keeps both existing callbacks and their explicit meanings.
  const TokenCreatedSuccess({
    required this.onCreateAnotherTokenPressed,
    required this.onViewTokensPressed,
    this.confirmation,
    super.key,
  });

  /// Starts another token only after this one is confirmed.
  final VoidCallback onCreateAnotherTokenPressed;

  /// Returns to the token list.
  final VoidCallback onViewTokensPressed;

  /// The original account, chain and exact positive evidence.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) {
    final RegistrationPublication? publication = confirmation?.publication;
    return RegistrationSuccessSurface(
      asset: AppLottieAsset.zts,
      confirmation: confirmation,
      confirmedKey: const Key('token_registration_confirmed'),
      heading: context.l10n.registrationTokenCreated,
      steps: <String>[
        context.l10n.tokenCreateNameAndSymbol,
        context.l10n.tokensSupply,
        context.l10n.tokenCreateOptions,
        context.l10n.tokenCreateIssue,
      ],
      facts: <Widget>[
        if (publication != null)
          RegistrationReceiptFact(
            label: context.l10n.createTokenFeeLabel,
            value: AmountText(
              publication.amount,
              decimals: kZnnCoin.decimals,
              symbol: kZnnCoin.symbol,
              style: AppTokens.of(context).dataText,
            ),
          ),
      ],
      viewLabel: context.l10n.registrationViewToken,
      onView: onViewTokensPressed,
      anotherLabel: context.l10n.createAnotherToken,
      onAnother: onCreateAnotherTokenPressed,
    );
  }
}

/// The legacy entry point also requires the original positive confirmation.
class TokenCreatedSuccessAnimation extends StatelessWidget {
  /// A standalone animation without a confirmation owner stays empty.
  const TokenCreatedSuccessAnimation({this.confirmation, super.key});

  /// The original registration's confirmation owner.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) => RegistrationConfirmedArt(
    asset: AppLottieAsset.zts,
    confirmation: confirmation,
  );
}
