import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_scope.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A wrapper widget that registers create sentinel stepper dependencies.
class CreateSentinelStepperPage extends StatelessWidget {
  /// {@macro default_constructor}
  const CreateSentinelStepperPage({
    this.accountBlockUtils,
    this.client,
    this.sender,
    super.key,
  });

  /// The owner workflow supplies its original account and shared admission.
  final AccountBlockUtils? accountBlockUtils;

  /// All steps retain their originating transport.
  final Zenon? client;

  /// A route can retain the shell's sender without relying on route ancestry.
  final SendTransactionBloc? sender;

  @override
  Widget build(BuildContext context) {
    return RegistrationScope(
      accountBlockUtils: accountBlockUtils,
      sender: sender,
      builder:
          (
            RegistrationConfirmation confirmation,
            AccountBlockUtils publisher,
          ) => MultiBlocProvider(
            providers: <SingleChildWidget>[
              BlocProvider<CreateSentinelQsrInfoBloc>(
                create: (_) => CreateSentinelQsrInfoBloc(
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                ),
              ),
              BlocProvider<SentinelWithdrawQsrBloc>(
                create: (_) => SentinelWithdrawQsrBloc(
                  accountBlockUtils: publisher,
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                  zenonAddressUtils: ZenonAddressUtils(),
                ),
              ),
              BlocProvider<SentinelDepositQsrBloc>(
                create: (_) => SentinelDepositQsrBloc(
                  accountBlockUtils: publisher,
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                  zenonAddressUtils: ZenonAddressUtils(),
                ),
              ),
              BlocProvider<DeploySentinelBloc>(
                create: (_) => DeploySentinelBloc(
                  accountBlockUtils: publisher,
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                  zenonAddressUtils: ZenonAddressUtils(),
                ),
              ),
            ],
            child: CreateSentinelStepperView(confirmation: confirmation),
          ),
    );
  }
}
