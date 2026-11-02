import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart';

/// Legacy donation positions retained for compatible entry callers.
enum AcceleratorDonationStep {
  /// Review the fixed Accelerator donation destination.
  donationAddress,

  /// Enter exact native-coin donation amounts.
  donationDetails,

  /// Explicitly submit the original donation draft.
  submitDonation,
}

/// Original coin outcomes remain retained if a two-coin donation stops partway.
class AcceleratorDonationStepper extends StatelessWidget {
  /// Opens the donation form with the captured original action capability.
  const AcceleratorDonationStepper({this.source, super.key});

  /// Original action source; absence cannot authorize publication.
  final AcceleratorActionSource? source;
  @override
  Widget build(BuildContext context) => AcceleratorActionStepper(
    kind: AcceleratorActionKind.donate,
    source: source,
  );
}
