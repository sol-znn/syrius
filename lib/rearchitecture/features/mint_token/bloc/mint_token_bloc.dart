import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'mint_token_event.dart';

part 'mint_token_state.dart';

/// A bloc that mints an amount of a ZTS token on-chain.
class MintTokenBloc extends Bloc<MintTokenEvent, MintTokenState> {
  /// Creates a [MintTokenBloc].
  MintTokenBloc({required this._publisher}) : super(const MintTokenInitial()) {
    on<MintTokenRequested>(_onMintTokenRequested);
  }

  final TokenActionPublisher _publisher;
  bool _pending = false;
  bool _closing = false;

  /// An original result remains inspectable after this adapter closes.
  TokenActionOutcome? _lastOutcome;

  /// Read-only view of the original publication outcome.
  TokenActionOutcome? get lastOutcome => _lastOutcome;

  @override
  void add(MintTokenEvent event) {
    if (_closing || _pending) return;
    _pending = true;
    super.add(event);
  }

  FutureOr<void> _onMintTokenRequested(
    MintTokenRequested event,
    Emitter<MintTokenState> emit,
  ) async {
    try {
      late final MintTokenState terminal;
      try {
        emit(const MintTokenLoading());

        final TokenActionIntent intent =
            event.intent ??
            TokenActionIntent(
              proof: await _publisher.read(event.token.tokenStandard),
              mode: TokenActionMode.mint,
              amount: event.amount,
              receiver: event.beneficiaryAddress.toString(),
              isCurrent: () => !_closing,
            );
        if (intent.mode != TokenActionMode.mint ||
            intent.amount != event.amount ||
            intent.receiver != event.beneficiaryAddress.toString() ||
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
            ? MintTokenDone(
                accountBlock: outcome.block!,
                requestedMintAmount: intent.amount,
                outcome: outcome,
              )
            : MintTokenFailure(
                error: outcome.error ?? const TokenActionRefused(),
                outcome: outcome,
              );
      } on Object catch (error, trace) {
        _report(error, trace);
        terminal = MintTokenFailure(error: error);
      }
      if (!emit.isDone) emit(terminal);
    } finally {
      _pending = false;
    }
  }

  @override
  void onChange(Change<MintTokenState> change) {
    if (change.nextState is! MintTokenDone &&
        change.nextState is! MintTokenFailure) {
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
