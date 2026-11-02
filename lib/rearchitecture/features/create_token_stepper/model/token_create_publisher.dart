import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_preflight.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Carries the original fresh-read predicate through the existing sender.
class TokenCreatePublisher extends AccountBlockUtils {
  /// No replacement sender or publication outcome is introduced.
  TokenCreatePublisher({required this.publisher, required this.preflight});

  /// The page's captured RegistrationPublisher and shared shell admission.
  final AccountBlockUtils publisher;

  /// Fresh facts are invalidated by any later read or disposed presentation.
  final TokenCreatePreflight preflight;

  /// The original sender owns whether an admitted attempt may be replaced.
  bool get canStartNewAttempt {
    final AccountBlockUtils original = publisher;
    return original is! RegistrationPublisher || original.canStartNewAttempt;
  }

  /// Uncertainty retains the original outcome and cannot authorize a new Issue.
  bool get isUncertain {
    final AccountBlockUtils original = publisher;
    return original is RegistrationPublisher && original.isUncertain;
  }

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purposeOfGeneratingPlasma, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) {
    final Object? ticket = preflight.ticket;
    bool current() =>
        preflight.sufficient &&
        identical(preflight.ticket, ticket) &&
        (canPublish?.call() ?? true);
    if (!current() ||
        ticket == null ||
        transactionParams.chainIdentifier != preflight.session.chainId ||
        (address != null && address.toString() != preflight.session.owner)) {
      return Future<AccountBlockTemplate>.error(
        FailureException(message: currentL10n.publicationSessionChanged),
      );
    }
    // The returned Future and accepted object belong to the original sender.
    // Context leaving after dispatch cannot turn that acceptance into refusal.
    return publisher.createAccountBlock(
      transactionParams,
      purposeOfGeneratingPlasma,
      address: address,
      waitForRequiredPlasma: waitForRequiredPlasma,
      canPublish: current,
    );
  }
}
