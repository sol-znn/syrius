import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_success_surface.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/custom_material_stepper.dart'
    as custom_material_stepper;
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

enum _Step {
  checkPlasma,
  qsrManagement,
  znnManagement,
  deploySentinel,
}

/// A stepper that guides the user through creating a sentinel.
///
/// The deposit QSR step does not let more QSR be deposited, by mistake,
/// than a Sentinel takes.
class CreateSentinelStepperView extends StatefulWidget {
  /// {@macro default_constructor}
  const CreateSentinelStepperView({this.confirmation, super.key});

  /// A page-owned confirmation survives every retained step and balance read.
  final RegistrationConfirmation? confirmation;

  @override
  State<CreateSentinelStepperView> createState() => _MainSentinelState();
}

class _MainSentinelState extends State<CreateSentinelStepperView> {
  late final RegistrationConfirmation _confirmation;
  AccountInfo? _lastAccountInfo;
  final TextEditingController _qsrAmountController = TextEditingController();
  final TextEditingController _znnAmountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // When value is null, it means the stepper has completed.
  final ValueNotifier<_Step?> _currentStep = .new(
    .checkPlasma,
  );

  @override
  void initState() {
    super.initState();
    _confirmation = widget.confirmation ?? RegistrationConfirmation.capture();
    // Shown, never typed: grouped, and with no trailing zeros.
    _znnAmountController.text = cardAmount(
      sentinelRegisterZnnAmount,
      coinDecimals,
      '',
    );
    _addressController.text = kSelectedAddress!;
    sl.get<MultipleBalanceBloc>().add(
      MultipleBalanceFetch(
        addresses: kDefaultAddressList.map((String? e) => e!).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MultipleBalanceBloc, MultipleBalanceState>(
      // Loading, the steps and an error fade into one another. The steps
      // themselves change with the stepper's own transition.
      builder: (_, MultipleBalanceState state) {
        final AccountInfo? account = state.data?[_addressController.text];
        if (state.status == MultipleBalanceStatus.success && account != null) {
          _lastAccountInfo = account;
        }
        return StateSwitcher(
          alignment: Alignment.center,
          child: _lastAccountInfo != null
              ? KeyedSubtree(
                  key: const ValueKey<String>('steps'),
                  child: _buildBody(context, _lastAccountInfo!),
                )
              : switch (state.status) {
                  MultipleBalanceStatus.failure => SyriusErrorWidget(
                    state.error!,
                    key: const ValueKey<String>('error'),
                  ),
                  MultipleBalanceStatus.initial ||
                  MultipleBalanceStatus.loading => const SyriusLoadingWidget(
                    key: ValueKey<String>('loading'),
                  ),
                  MultipleBalanceStatus.success => const SyriusLoadingWidget(
                    key: ValueKey<String>('loading'),
                  ),
                },
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AccountInfo accountInfo) {
    // The steps are told how tall the card is: the list they sit in would
    // give a step any height, and its actions would end below the window.
    return LayoutBuilder(
      builder: (_, BoxConstraints constraints) => TokenStepViewport(
        height: constraints.maxHeight,
        child: ValueListenableBuilder<_Step?>(
          valueListenable: _currentStep,
          builder: (_, _Step? currentStep, _) {
            return RegistrationRetainedFlow(
              published: currentStep == null,
              form: ListView(
                children: <Widget>[
                  _buildMaterialStepper(
                    accountInfo: accountInfo,
                    currentStep: currentStep,
                  ),
                ],
              ),
              receipt: SentinelRegisteredSuccess(
                confirmation: _confirmation,
                onViewSentinelsPressed: () => Navigator.pop(context),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMaterialStepper({
    required AccountInfo accountInfo,
    required _Step? currentStep,
  }) {
    final int lastStepIndex = _Step.values.last.index;
    // The one accent of the stepper: its marks, the lines between them and
    // what a finished step says under its title.
    final Color accent = AppTokens.of(context).znnInk;

    custom_material_stepper.StepState getStepState(
      _Step step,
      _Step? currentStep,
    ) {
      return step.index < (currentStep?.index ?? lastStepIndex + 1)
          ? custom_material_stepper.StepState.complete
          : custom_material_stepper.StepState.indexed;
    }

    return custom_material_stepper.Stepper(
      activeColor: accent,
      currentStep: currentStep?.index ?? lastStepIndex,
      onStepTapped: (int index) {},
      steps: <custom_material_stepper.Step>[
        StepperUtils.getMaterialStep(
          stepTitle: context.l10n.plasmaCheck,
          stepContent: SentinelPlasmaCheckStep(
            active: currentStep == _Step.checkPlasma,
            addressController: _addressController,
            onNextPressed: _onPlasmaCheckNextPressed,
          ),
          stepSubtitle: context.l10n.sufficientPlasma,
          stepState: getStepState(
            _Step.checkPlasma,
            currentStep,
          ),
          context: context,
          stepSubtitleColor: accent,
        ),
        StepperUtils.getMaterialStep(
          stepTitle: context.l10n.management(kQsrCoin.symbol),
          stepContent: SentinelQsrManagementStep(
            active: currentStep == _Step.qsrManagement,
            accountInfo: accountInfo,
            addressController: _addressController,
            onBackPressed: _navigateToPreviousStep,
            onNextPressed: _navigateToNextStep,
            qsrAmountController: _qsrAmountController,
          ),
          stepSubtitle: context.l10n.deposited(kQsrCoin.symbol),
          stepState: getStepState(
            _Step.qsrManagement,
            currentStep,
          ),
          context: context,
          stepSubtitleColor: accent,
          expanded: true,
        ),
        StepperUtils.getMaterialStep(
          stepTitle: context.l10n.management(kZnnCoin.symbol),
          stepContent: SentinelZnnManagementStep(
            active: currentStep == _Step.znnManagement,
            accountInfo: accountInfo,
            addressController: _addressController,
            onBackPressed: _navigateToPreviousStep,
            onNextPressed: _navigateToNextStep,
            znnAmountController: _znnAmountController,
          ),
          stepSubtitle: context.l10n.locked(kZnnCoin.symbol),
          stepState: getStepState(
            _Step.znnManagement,
            currentStep,
          ),
          context: context,
          stepSubtitleColor: accent,
        ),
        StepperUtils.getMaterialStep(
          stepTitle: context.l10n.registerSentinel,
          stepContent: DeploySentinelStep(
            active: currentStep == _Step.deploySentinel,
            address: _addressController.text,
            onBackPressed: _navigateToPreviousStep,
            onDeployDone: _onDeployDone,
            onPublished: _confirmation.accept,
          ),
          stepSubtitle: context.l10n.sentinelRegistered,
          stepState: getStepState(
            _Step.deploySentinel,
            currentStep,
          ),
          context: context,
          stepSubtitleColor: accent,
        ),
      ],
    );
  }

  void _refreshSentinelQsrInfo() {
    context.read<CreateSentinelQsrInfoBloc>().add(
      FetchRequestData(
        address: Address.parse(_addressController.text),
      ),
    );
  }

  void _onDeployDone() {
    // All steps have been completed.
    _currentStep.value = null;
  }

  void _navigateToNextStep() {
    final _Step? currentStep = _currentStep.value;

    // Every step stays mounted, so a Next that still holds the focus can be
    // pressed once more after its step has closed.
    if (currentStep == null || currentStep == _Step.values.last) {
      return;
    }

    _currentStep.value = _Step.values[currentStep.index + 1];
  }

  void _navigateToPreviousStep() {
    final _Step? currentStep = _currentStep.value;

    if (currentStep == null || currentStep.index == 0) {
      return;
    }

    _currentStep.value = _Step.values[currentStep.index - 1];
  }

  void _onPlasmaCheckNextPressed() {
    _navigateToNextStep();
    _refreshSentinelQsrInfo();
  }

  @override
  void dispose() {
    if (widget.confirmation == null) _confirmation.dispose();
    _qsrAmountController.dispose();
    _znnAmountController.dispose();
    _addressController.dispose();
    _currentStep.dispose();
    super.dispose();
  }
}
