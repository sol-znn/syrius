import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/refresh_bloc_mixin.dart';
import 'package:zenon_syrius_wallet_flutter/screens/stepper_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_donation_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/project_creation_stepper.dart';

/// Accelerator reads have one original wallet, member set, node and revision.
class AcceleratorTabChild extends StatefulWidget {
  /// Mounts source-bound reads and admits forms only from an explicit action.
  const AcceleratorTabChild({
    required this.onStepperNotificationSeeMorePressed,
    super.key,
  });

  /// Original notification-details navigation callback for nested steppers.
  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  State<AcceleratorTabChild> createState() => _AcceleratorTabChildState();
}

class _AcceleratorTabChildState extends State<AcceleratorTabChild>
    with RefreshBlocMixin {
  final AcceleratorListPresenter _presenter = AcceleratorListPresenter();
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    WalletContextRevision.changes.addListener(_queueRefresh);
    _queueRefresh();
  }

  void _queueRefresh() {
    if (!mounted) return;
    // Context revisions clear paint synchronously. Capturing in the next
    // turn lets the source change finish before a new read is admitted.
    _presenter.invalidate();
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!mounted) return;
      listenToWsRestart(_queueRefresh);
      try {
        final AcceleratorListBinding? binding =
            AcceleratorListBinding.capture();
        if (binding != null) unawaited(_presenter.load(binding));
      } on Object {
        // An unbound transport cannot establish an empty current list.
        _presenter.invalidate();
      }
    });
  }

  void _openStepper(
    AcceleratorListSnapshot source,
    AcceleratorActionKind kind,
  ) {
    final AcceleratorListBinding? binding = source.binding;
    if (!mounted ||
        binding == null ||
        !source.isCurrent ||
        !identical(binding, _presenter.snapshot.binding) ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    final AcceleratorActionBinding? origin;
    try {
      origin = AcceleratorActionBinding.capture();
    } on Object {
      return;
    }
    if (origin == null || !origin.isCurrent || !source.isCurrent) return;
    final Widget stepper = kind == AcceleratorActionKind.donate
        ? AcceleratorDonationStepper(source: origin)
        : ProjectCreationStepper(source: origin);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => StepperScreen(
          stepper: stepper,
          onStepperNotificationSeeMorePressed:
              widget.onStepperNotificationSeeMorePressed,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WalletContextRevision.changes.removeListener(_queueRefresh);
    cancelStreamSubscription();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AcceleratorListView(
    presenter: _presenter,
    onRefresh: _queueRefresh,
    onDonate: (AcceleratorListSnapshot source) =>
        _openStepper(source, AcceleratorActionKind.donate),
    onCreateProject: (AcceleratorListSnapshot source) =>
        _openStepper(source, AcceleratorActionKind.createProject),
    onStepperNotificationSeeMorePressed:
        widget.onStepperNotificationSeeMorePressed,
  );
}
