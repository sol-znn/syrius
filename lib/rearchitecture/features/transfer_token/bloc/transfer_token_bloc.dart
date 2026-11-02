import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'transfer_token_event.dart';

part 'transfer_token_state.dart';

/// A bloc that transfers ownership of a ZTS token on-chain.
class TransferTokenBloc extends Bloc<TransferTokenEvent, TransferTokenState> {
  /// Creates a [TransferTokenBloc].
  TransferTokenBloc({required this._publisher})
    : super(const TransferTokenInitial()) {
    on<TransferTokenRequested>(_onTransferTokenRequested);
  }

  final TokenActionPublisher _publisher;
  bool _pending = false;
  bool _closing = false;

  /// Original outcomes survive closure of this view adapter.
  TokenActionOutcome? _lastOutcome;

  /// Read-only view of the original publication outcome.
  TokenActionOutcome? get lastOutcome => _lastOutcome;

  @override
  void add(TransferTokenEvent event) {
    if (_closing || _pending) return;
    _pending = true;
    super.add(event);
  }

  FutureOr<void> _onTransferTokenRequested(
    TransferTokenRequested event,
    Emitter<TransferTokenState> emit,
  ) async {
    try {
      late final TransferTokenState terminal;
      try {
        emit(const TransferTokenLoading());

        final TokenActionIntent intent =
            event.intent ??
            TokenActionIntent(
              proof: await _publisher.read(event.token.tokenStandard),
              mode: TokenActionMode.transfer,
              amount: BigInt.zero,
              receiver: event.newOwnerAddress.toString(),
              isCurrent: () => !_closing,
            );
        if (intent.mode != TokenActionMode.transfer ||
            intent.receiver != event.newOwnerAddress.toString() ||
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
            ? TransferTokenDone(
                accountBlock: outcome.block!,
                newOwnerAddress: intent.receiver!,
                outcome: outcome,
              )
            : TransferTokenFailure(
                error: outcome.error ?? const TokenActionRefused(),
                outcome: outcome,
              );
      } on Object catch (error, trace) {
        _report(error, trace);
        terminal = TransferTokenFailure(error: error);
      }
      if (!emit.isDone) emit(terminal);
    } finally {
      _pending = false;
    }
  }

  @override
  void onChange(Change<TransferTokenState> change) {
    if (change.nextState is! TransferTokenDone &&
        change.nextState is! TransferTokenFailure) {
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
