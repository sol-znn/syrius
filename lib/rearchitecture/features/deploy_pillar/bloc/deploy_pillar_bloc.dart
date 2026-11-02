import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'deploy_pillar_event.dart';

part 'deploy_pillar_state.dart';

/// A bloc that registers a new pillar on-chain.
class DeployPillarBloc extends Bloc<DeployPillarEvent, DeployPillarState> {
  /// Creates a new [DeployPillarBloc].
  DeployPillarBloc({
    required this._accountBlockUtils,
    required this._zenon,
    required this._zenonAddressUtils,
  }) : super(const DeployPillarInitial()) {
    on<DeployPillarRequested>(_onDeployPillarRequested);
  }

  final Zenon _zenon;
  final AccountBlockUtils _accountBlockUtils;
  final ZenonAddressUtils _zenonAddressUtils;

  FutureOr<void> _onDeployPillarRequested(
    DeployPillarRequested event,
    Emitter<DeployPillarState> emit,
  ) async {
    if (emit.isDone) return;
    late final DeployPillarState terminal;
    try {
      emit(const DeployPillarLoading());
      final bool nameExists = await _pillarNameAlreadyExists(event.pillarName);
      if (emit.isDone) return;
      if (nameExists) {
        throw PillarNameAlreadyExistsException();
      }
      final AccountBlockTemplate transactionParams = _zenon.embedded.pillar
          .register(
            event.pillarName,
            event.blockProducingAddress,
            event.rewardAddress,
            event.giveBlockRewardPercentage,
            event.giveDelegateRewardPercentage,
          );
      final AccountBlockTemplate response = await _accountBlockUtils
          .createAccountBlock(
            transactionParams,
            PlasmaPurpose.registerPillar.message,
            waitForRequiredPlasma: true,
          );

      terminal = DeployPillarDone(accountBlock: response);
    } on SyriusException catch (e, stackTrace) {
      _reportError(e, stackTrace);
      terminal = DeployPillarFailure(exception: e, error: e);
    } on Object catch (e, stackTrace) {
      _reportError(e, stackTrace);
      terminal = DeployPillarFailure(exception: FailureException(), error: e);
    }
    if (!emit.isDone) emit(terminal);
    if (terminal is DeployPillarDone) {
      try {
        _zenonAddressUtils.refreshBalance();
      } on Object catch (error, trace) {
        _reportError(error, trace);
      }
    }
  }

  @override
  void onChange(Change<DeployPillarState> change) {
    if (change.nextState is! DeployPillarDone &&
        change.nextState is! DeployPillarFailure) {
      super.onChange(change);
      return;
    }
    try {
      super.onChange(change);
    } on Object catch (error, trace) {
      // Terminal observer failure cannot replace the original delivered state.
      _reportError(error, trace);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    try {
      super.onError(error, stackTrace);
    } on Object {
      // A diagnostic observer cannot replace an original preparation or result.
    }
  }

  void _reportError(Object error, StackTrace trace) {
    try {
      addError(error, trace);
    } on Object {
      // Diagnostic observers cannot strand a form or replace acceptance.
    }
  }

  Future<bool> _pillarNameAlreadyExists(String pillarName) async =>
      !(await _zenon.embedded.pillar.checkNameAvailability(
        pillarName,
      ));
}
