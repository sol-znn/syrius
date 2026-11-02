import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'burn_token_event.dart';

part 'burn_token_state.dart';

/// A bloc that burns an amount of a ZTS token on-chain.
class BurnTokenBloc extends Bloc<BurnTokenEvent, BurnTokenState> {
  /// Creates a [BurnTokenBloc].
  BurnTokenBloc({required this._publisher}) : super(const BurnTokenInitial()) {
    on<BurnTokenRequested>(_onBurnTokenRequested);
  }

  final TokenActionPublisher _publisher;
  bool _pending = false;
  bool _closing = false;

  /// Original results remain available after form disposal.
  TokenActionOutcome? _lastOutcome;

  /// Read-only view of the original publication outcome.
  TokenActionOutcome? get lastOutcome => _lastOutcome;

  @override
  void add(BurnTokenEvent event) {
    if (_closing || _pending) return;
    _pending = true;
    super.add(event);
  }

  FutureOr<void> _onBurnTokenRequested(
    BurnTokenRequested event,
    Emitter<BurnTokenState> emit,
  ) async {
    try {
      late final BurnTokenState terminal;
      try {
        emit(const BurnTokenLoading());

        final TokenActionIntent intent =
            event.intent ??
            TokenActionIntent(
              proof: await _publisher.read(event.token.tokenStandard),
              mode: TokenActionMode.burn,
              amount: event.amount,
              receiver: null,
              isCurrent: () => !_closing,
            );
        if (intent.mode != TokenActionMode.burn ||
            intent.amount != event.amount ||
            intent.standard != event.token.tokenStandard) {
          throw const TokenActionRefused();
        }
        final TokenActionOutcome outcome = await _publisher.publish(
          intent.fenced(() => !_closing),
        );
        _lastOutcome = outcome;
        terminal =
            outcome.status == TokenActionStatus.submitted &&
                outcome.belongsTo(intent)
            ? BurnTokenDone(accountBlock: outcome.block!, outcome: outcome)
            : BurnTokenFailure(
                error: outcome.error ?? const TokenActionRefused(),
                outcome: outcome,
              );
      } on Object catch (error, trace) {
        _report(error, trace);
        terminal = BurnTokenFailure(error: error);
      }
      if (!emit.isDone) emit(terminal);
    } finally {
      _pending = false;
    }
  }

  @override
  void onChange(Change<BurnTokenState> change) {
    if (change.nextState is! BurnTokenDone &&
        change.nextState is! BurnTokenFailure) {
      super.onChange(change);
      return;
    }
    try {
      super.onChange(change);
    } on Object catch (error, trace) {
      // The original terminal state must still reach state and stream delivery.
      _report(error, trace);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    try {
      super.onError(error, stackTrace);
    } on Object {
      // A diagnostic observer cannot substitute its own error for the original.
    }
  }

  void _report(Object error, StackTrace trace) {
    try {
      addError(error, trace);
    } on Object {
      // Diagnostics cannot replace the original preparation or SDK outcome.
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    return super.close();
  }
}
