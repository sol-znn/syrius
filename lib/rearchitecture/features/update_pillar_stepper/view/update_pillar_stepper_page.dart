import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A widget that helps with DI
class UpdatePillarStepperPage extends StatelessWidget {
  /// {@macro default_constructor}
  const UpdatePillarStepperPage({
    required this._pillarInfo,
    this.accountBlockUtils,
    this.client,
    super.key,
  });

  final PillarInfo _pillarInfo;

  /// The owner panel supplies its captured account and shared admission.
  final AccountBlockUtils? accountBlockUtils;

  /// A retained form keeps its original transport.
  final Zenon? client;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<UpdatePillarBloc>(
          create: (_) => UpdatePillarBloc(
            accountBlockUtils: accountBlockUtils ?? AccountBlockUtils(),
            zenon: client ?? zenon!,
          ),
        ),
      ],
      child: UpdatePillarStepperView(pillarInfo: _pillarInfo),
    );
  }
}
