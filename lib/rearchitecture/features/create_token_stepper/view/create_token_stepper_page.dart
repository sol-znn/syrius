import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_preflight.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_scope.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A wrapper widget that registers create token stepper dependencies.
class CreateTokenStepperPage extends StatelessWidget {
  /// Creates a [CreateTokenStepperPage].
  const CreateTokenStepperPage({this.sender, super.key});

  /// The originating shell sender, captured before opening this route.
  final SendTransactionBloc? sender;

  @override
  Widget build(BuildContext context) {
    return RegistrationScope(
      sender: sender,
      builder:
          (
            RegistrationConfirmation confirmation,
            AccountBlockUtils publisher,
          ) => _Bindings(
            confirmation: confirmation,
            publisher: publisher,
          ),
    );
  }
}

class _Bindings extends StatefulWidget {
  const _Bindings({required this.confirmation, required this.publisher});

  final RegistrationConfirmation confirmation;
  final AccountBlockUtils publisher;

  @override
  State<_Bindings> createState() => _BindingsState();
}

class _BindingsState extends State<_Bindings> {
  TokenCreatePreflight? _preflight;
  late final TokenCreatePublisher _publisher;
  late final Zenon _client;
  late final TokenApi _token;

  @override
  void initState() {
    super.initState();
    final RegistrationConfirmation confirmation = widget.confirmation;
    if (confirmation.context == null || !confirmation.isCurrent) return;
    _client = confirmation.context!.client;
    _token = _client.embedded.token;
    _preflight = TokenCreatePreflight(
      session: TokenCreateSession.wallet(confirmation),
      authority: Listenable.merge(<Listenable>[
        confirmation,
        WalletContextRevision.changes,
      ]),
    );
    _publisher = TokenCreatePublisher(
      publisher: widget.publisher,
      preflight: _preflight!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TokenCreatePreflight? preflight = _preflight;
    if (preflight == null) {
      return Center(child: Text(context.l10n.publicationSessionChanged));
    }
    return RepositoryProvider<FavoriteTokensRepository>(
      create: (_) => HiveFavoriteTokensRepository(),
      child: BlocProvider<IssueTokenBloc>(
        create: (_) => IssueTokenBloc(
          accountBlockUtils: _publisher,
          zenon: _client,
          tokenApi: _token,
          zenonAddressUtils: ZenonAddressUtils(),
        ),
        child: CreateTokenStepperView(
          confirmation: widget.confirmation,
          preflight: preflight,
          canStartIssue: () => _publisher.canStartNewAttempt,
          isIssueUncertain: () => _publisher.isUncertain,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _preflight?.dispose();
    super.dispose();
  }
}
