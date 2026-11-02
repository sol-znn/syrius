import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_scope.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A wrapper widget that helps with registering dependencies inside the
/// context object.
///
/// Dependencies latter used by the view [CreatePillarStepperView].
class CreatePillarStepperPage extends StatelessWidget {
  /// {@macro default_constructor}
  const CreatePillarStepperPage({
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
              BlocProvider<CreatePillarQsrInfoBloc>(
                create: (_) => CreatePillarQsrInfoBloc(
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                ),
              ),
              BlocProvider<PillarWithdrawQsrBloc>(
                create: (_) => PillarWithdrawQsrBloc(
                  accountBlockUtils: publisher,
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                  zenonAddressUtils: ZenonAddressUtils(),
                ),
              ),
              BlocProvider<PillarDepositQsrBloc>(
                create: (_) => PillarDepositQsrBloc(
                  accountBlockUtils: publisher,
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                  zenonAddressUtils: ZenonAddressUtils(),
                ),
              ),
              BlocProvider<DeployPillarBloc>(
                create: (_) => DeployPillarBloc(
                  accountBlockUtils: publisher,
                  zenon: client ?? confirmation.context?.client ?? zenon!,
                  zenonAddressUtils: ZenonAddressUtils(),
                ),
              ),
            ],
            child: CreatePillarStepperView(confirmation: confirmation),
          ),
    );
  }
}
