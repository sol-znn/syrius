import 'package:zenon_syrius_wallet_flutter/blocs/accelerator/accelerator_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';

/// Compatibility observer for an explicit donation in exact native units.
class SubmitDonationBloc extends AcceleratorActionBloc {
  /// Retains the original injected or captured action capabilities.
  SubmitDonationBloc({super.source, super.controller});

  /// Submits the original coin amounts without retrying an uncertain transfer.
  Future<AcceleratorActionOutcome> submitDonation(
    BigInt znnAmount,
    BigInt qsrAmount,
  ) => run(
    AcceleratorActionRequest(
      kind: AcceleratorActionKind.donate,
      znn: znnAmount,
      qsr: qsrAmount,
    ),
  );
}
