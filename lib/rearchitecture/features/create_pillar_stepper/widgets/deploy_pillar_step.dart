import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_pillar_stepper/widgets/pillar_step_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Deploy step for registering a pillar: its name, its two addresses, what
/// it shares with delegators, and under them the review of what Register
/// sends.
class DeployPillarStep extends StatefulWidget {
  /// Creates a [DeployPillarStep].
  const DeployPillarStep({
    required this.onDeployDone,
    this.onBackPressed,
    this.onPublished,
    this.registrationRun = 0,
    this.active = true,
    super.key,
  });

  /// Called when deployment completes.
  final VoidCallback onDeployDone;

  /// Retains the original result before the legacy completion callback runs.
  final ValueChanged<RegistrationPublication>? onPublished;

  /// Changes only when the user explicitly starts another registration.
  final int registrationRun;

  /// Called when the user wants to go back. No Back button when null.
  final VoidCallback? onBackPressed;

  /// Whether this is the step shown.
  final bool active;

  @override
  State<DeployPillarStep> createState() => _DeployPillarStepState();
}

class _DeployPillarStepState extends State<DeployPillarStep> {
  GlobalKey<LoadingButtonState> _registerButtonKey = GlobalKey();

  final TextEditingController _pillarNameController = TextEditingController();
  final TextEditingController _pillarRewardAddressController =
      TextEditingController();
  final TextEditingController _pillarMomentumController =
      TextEditingController();

  String? get _pillarNameError =>
      Validations.pillarName(_pillarNameController.text);

  String? get _pillarRewardAddressError =>
      InputValidators.checkAddress(_pillarRewardAddressController.text);

  String? get _pillarMomentumError =>
      InputValidators.validatePillarMomentumAddress(
        _pillarMomentumController.text,
      );

  final ValueNotifier<double> _momentumRewardPercentage = .new(0);
  final ValueNotifier<double> _delegateRewardPercentage = .new(0);

  // From the press until the bloc is done or has failed.
  bool _isSending = false;
  bool _accepted = false;
  String? _submittedName;
  BigInt? _submittedQsrCost;

  @override
  void didUpdateWidget(DeployPillarStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registrationRun != widget.registrationRun) {
      _accepted = false;
      _isSending = false;
      _registerButtonKey = GlobalKey<LoadingButtonState>();
      _submittedName = null;
      _submittedQsrCost = null;
      _pillarNameController.clear();
      _pillarMomentumController.clear();
      _pillarRewardAddressController.text = kSelectedAddress ?? '';
      _momentumRewardPercentage.value = 0;
      _delegateRewardPercentage.value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _pillarRewardAddressController.text = kSelectedAddress!;
  }

  @override
  void dispose() {
    _pillarNameController.dispose();
    _pillarRewardAddressController.dispose();
    _pillarMomentumController.dispose();
    _momentumRewardPercentage.dispose();
    _delegateRewardPercentage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DeployPillarBloc, DeployPillarState>(
      listener: (_, DeployPillarState state) => _onDeployStateChanged(state),
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _pillarNameController,
          _pillarMomentumController,
          _pillarRewardAddressController,
          _momentumRewardPercentage,
          _delegateRewardPercentage,
        ]),
        builder: (BuildContext context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool valid = _isInputValid();
    return TokenStepFrame(
      active: widget.active,
      busy: _isSending,
      onBack: widget.onBackPressed,
      // Enter does not send from here. It is pressed out of habit at the end
      // of a field, and this step locks 15,000 ZNN and burns the deposit:
      // that takes the button, under the review.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildTextFields(context),
          SizedBox(height: tokens.cardGap),
          // What is sent stays what the review says while it is on its way.
          AbsorbPointer(
            absorbing: _isSending,
            child: ExcludeFocus(
              excluding: _isSending,
              child: PillarRewardSliders(
                delegateRewardPercentage: _delegateRewardPercentage,
                momentumRewardPercentage: _momentumRewardPercentage,
              ),
            ),
          ),
          SizedBox(height: tokens.cardGap),
          Divider(height: 1, color: lineColorOf(context)),
          SizedBox(height: tokens.cardGap),
          PillarReview(
            name: _pillarNameController.text,
            rewardAddress: _pillarRewardAddressController.text,
            producerAddress: _pillarMomentumController.text,
            momentumPercentage: _momentumRewardPercentage.value.toInt(),
            delegatePercentage: _delegateRewardPercentage.value.toInt(),
            costs: <Widget>[
              PillarReviewRow.amount(
                context: context,
                label: context.l10n.createPillarCollateralLabel,
                amount: pillarRegisterZnnAmount,
                token: kZnnCoin,
              ),
              const _SlotFeeRow(),
            ],
          ),
        ],
      ),
      // The key stays on a wrapper: the button is looked up under it.
      primary: KeyedSubtree(
        key: const Key('pillar_register_button'),
        child: LoadingButton(
          text: context.l10n.register,
          onPressed: valid && !_isSending && !_accepted
              ? _onDeployPressed
              : null,
          circularBorderRadius: kLoadingButtonMinSize.height / 2,
          key: _registerButtonKey,
        ),
      ),
    );
  }

  Widget _buildTextFields(BuildContext context) {
    final double gap = AppTokens.of(context).cardGap;
    final TextStyle text = accFieldTextStyle(context);
    // An address reads left to right in every language.
    final TextStyle address = accFieldTextStyle(context, mono: true);
    final TextAlign addressAlign = ltrTextAlign(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AccField(
          label: context.l10n.pillarName,
          child: TextField(
            key: const Key('pillar_name_field'),
            controller: _pillarNameController,
            readOnly: _isSending,
            style: text,
            decoration: InputDecoration(
              errorText: _pillarNameController.text.isNotEmpty
                  ? _pillarNameError
                  : null,
            ),
          ),
        ),
        SizedBox(height: gap),
        AccField(
          label: context.l10n.pillarRewardAddress,
          help: context.l10n.addressToCollectRewards,
          child: TextField(
            key: const Key('pillar_reward_address_field'),
            controller: _pillarRewardAddressController,
            readOnly: _isSending,
            style: address,
            textDirection: TextDirection.ltr,
            textAlign: addressAlign,
            decoration: InputDecoration(
              errorText: _pillarRewardAddressController.text.isNotEmpty
                  ? _pillarRewardAddressError
                  : null,
              suffixIcon: FieldSuffixButtons(
                controller: _pillarRewardAddressController,
              ),
            ),
          ),
        ),
        SizedBox(height: gap),
        AccField(
          label: context.l10n.pillarProducerAddress,
          help: context.l10n.addressToProduceMomentums,
          child: TextField(
            key: const Key('pillar_producer_address_field'),
            controller: _pillarMomentumController,
            readOnly: _isSending,
            style: address,
            textDirection: TextDirection.ltr,
            textAlign: addressAlign,
            decoration: InputDecoration(
              errorText: _pillarMomentumController.text.isNotEmpty
                  ? _pillarMomentumError
                  : null,
              suffixIcon: FieldSuffixButtons(
                controller: _pillarMomentumController,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onDeployStateChanged(DeployPillarState state) {
    if (_accepted) return;
    if (state is DeployPillarDone) {
      _accepted = true;
      try {
        widget.onPublished?.call(
          RegistrationPublication(
            accountBlock: state.accountBlock,
            name: _submittedName,
            qsrCost: _submittedQsrCost,
          ),
        );
      } on Object {
        // Receipt display cannot replace the accepted result in the bloc.
      }
      _registerButtonKey.currentState?.animateReverse();
      setState(() {
        _isSending = false;
      });
      try {
        widget.onDeployDone();
      } on Object {
        // A completion observer never reopens or retries the accepted action.
      }
    } else if (state is DeployPillarFailure) {
      _registerButtonKey.currentState?.animateReverse();
      setState(() {
        _isSending = false;
      });
      unawaited(
        NotificationUtils.sendNotificationError(
          state.exception,
          context.l10n.errorDeployingPillar,
        ),
      );
    } else if (state is DeployPillarLoading) {
      _registerButtonKey.currentState?.animateForward();
      setState(() {
        _isSending = true;
      });
    }
  }

  bool _isInputValid() =>
      _pillarNameError == null &&
      _pillarRewardAddressError == null &&
      _pillarMomentumError == null;

  void _onDeployPressed() {
    if (_isSending || _accepted || !widget.active) {
      return;
    }
    _submittedName = _pillarNameController.text;
    if (widget.onPublished != null) {
      final FetchState<CreatePillarQsrInfoData> state = context
          .read<CreatePillarQsrInfoBloc>()
          .state;
      _submittedQsrCost = state is FetchPopulated<CreatePillarQsrInfoData>
          ? state.data.cost
          : null;
    }
    setState(() {
      _isSending = true;
    });
    context.read<DeployPillarBloc>().add(
      DeployPillarRequested(
        pillarName: _pillarNameController.text,
        rewardAddress: Address.parse(_pillarRewardAddressController.text),
        blockProducingAddress: Address.parse(
          _pillarMomentumController.text,
        ),
        giveBlockRewardPercentage: _momentumRewardPercentage.value.toInt(),
        giveDelegateRewardPercentage: _delegateRewardPercentage.value.toInt(),
      ),
    );
  }
}

/// The QSR the slot takes, in the review. It is read from what the QSR step
/// fetched, and left out until that is known.
class _SlotFeeRow extends StatelessWidget {
  const _SlotFeeRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      CreatePillarQsrInfoBloc,
      FetchState<CreatePillarQsrInfoData>
    >(
      builder: (BuildContext context, FetchState<CreatePillarQsrInfoData> s) =>
          switch (s) {
            FetchPopulated<CreatePillarQsrInfoData>() => PillarReviewRow.amount(
              context: context,
              label: context.l10n.createPillarSlotFeeLabel,
              amount: s.data.cost,
              token: kQsrCoin,
            ),
            _ => const SizedBox.shrink(),
          },
    );
  }
}
