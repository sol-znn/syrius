import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'deploy_sentinel_event.dart';

part 'deploy_sentinel_state.dart';

/// A bloc that registers a new sentinel on-chain.
class DeploySentinelBloc
    extends Bloc<DeploySentinelEvent, DeploySentinelState> {
  /// Creates a new [DeploySentinelBloc].
  DeploySentinelBloc({
    required this._accountBlockUtils,
    required this._zenon,
    required this._zenonAddressUtils,
  }) : super(const DeploySentinelInitial()) {
    on<DeploySentinelRequested>(_onDeploySentinelRequested);
  }

  final Zenon _zenon;
  final AccountBlockUtils _accountBlockUtils;
  final ZenonAddressUtils _zenonAddressUtils;

  FutureOr<void> _onDeploySentinelRequested(
    DeploySentinelRequested event,
    Emitter<DeploySentinelState> emit,
  ) async {
    if (emit.isDone) return;
    late final DeploySentinelState terminal;
    try {
      emit(const DeploySentinelLoading());
      final AccountBlockTemplate transactionParams = _zenon.embedded.sentinel
          .register();

      final AccountBlockTemplate response = await _accountBlockUtils
          .createAccountBlock(
            transactionParams,
            PlasmaPurpose.registerSentinel.message,
            waitForRequiredPlasma: true,
          );

      terminal = DeploySentinelDone(accountBlock: response);
    } on SyriusException catch (e, stackTrace) {
      _reportError(e, stackTrace);
      terminal = DeploySentinelFailure(exception: e, error: e);
    } on Object catch (e, stackTrace) {
      _reportError(e, stackTrace);
      terminal = DeploySentinelFailure(exception: FailureException(), error: e);
    }
    if (!emit.isDone) emit(terminal);
    if (terminal is DeploySentinelDone) {
      try {
        _zenonAddressUtils.refreshBalance();
      } on Object catch (error, trace) {
        _reportError(error, trace);
      }
    }
  }

  @override
  void onChange(Change<DeploySentinelState> change) {
    if (change.nextState is! DeploySentinelDone &&
        change.nextState is! DeploySentinelFailure) {
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
}
