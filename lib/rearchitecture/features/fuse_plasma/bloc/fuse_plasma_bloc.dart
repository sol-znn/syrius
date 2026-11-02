import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_fuse_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'fuse_plasma_event.dart';

part 'fuse_plasma_state.dart';

/// A bloc that helps with fusing QSR for Plasma.
class FusePlasmaBloc extends Bloc<FusePlasmaEvent, FusePlasmaState> {
  /// Creates a [FusePlasmaBloc].
  FusePlasmaBloc({
    required this._accountBlockUtils,
    required this._zenon,
    required this._zenonAddressUtils,
    this.sender,
  }) : super(const FusePlasmaInitial()) {
    on<FusePlasmaRequested>(_onFusePlasmaRequested);
  }

  final AccountBlockUtils _accountBlockUtils;
  final Zenon _zenon;
  final ZenonAddressUtils _zenonAddressUtils;

  /// Production callers share the shell sender and freeze the event's session.
  final SendTransactionBloc? sender;
  bool _busy = false;
  bool _closing = false;
  PlasmaFuseOutcome? _lastOutcome;

  /// The original admitted result survives this view adapter's closure.
  PlasmaFuseOutcome? get lastOutcome => _lastOutcome;

  FutureOr<void> _onFusePlasmaRequested(
    FusePlasmaRequested event,
    Emitter<FusePlasmaState> emit,
  ) async {
    if (_busy) return;
    _busy = true;
    PlasmaFusePublisher? originalPublisher;
    try {
      late final FusePlasmaState terminal;
      try {
        emit(const FusePlasmaLoading());
        final PlasmaSession? session = event.session;
        if (_closing ||
            (session != null &&
                (sender == null ||
                    !session.isCurrent ||
                    !(event.isCurrent?.call() ?? true)))) {
          throw FailureException();
        }
        final AccountBlockTemplate transactionParams = session == null
            ? _zenon.embedded.plasma.fuse(
                Address.parse(event.beneficiaryAddress),
                event.amount,
              )
            : session.fuseBlock(event.beneficiaryAddress, event.amount);
        final AccountBlockUtils publisher;
        if (session == null) {
          publisher = _accountBlockUtils;
        } else {
          final PlasmaFusePublisher owned = PlasmaFusePublisher(
            sender: sender!,
            session: session,
            beneficiary: event.beneficiaryAddress,
            amount: event.amount,
            isCurrent: () => !_closing && (event.isCurrent?.call() ?? true),
            draft: event.draft,
          );
          originalPublisher = owned;
          publisher = owned;
        }

        final AccountBlockTemplate accountBlock = await publisher
            .createAccountBlock(
              transactionParams,
              PlasmaPurpose.fuseQsrForPlasma.message,
              waitForRequiredPlasma: true,
            );

        try {
          _zenonAddressUtils.refreshBalance();
        } on Object {
          // A convenience refresh cannot replace an original submitted result.
        }
        _lastOutcome = originalPublisher?.outcome;
        terminal = FusePlasmaDone(
          accountBlock: accountBlock,
          outcome: _lastOutcome,
        );
      } on SyriusException catch (e, stackTrace) {
        _report(e, stackTrace);
        _lastOutcome = originalPublisher?.outcome;
        terminal = FusePlasmaFailure(
          exception: e,
          error: e,
          outcome: _lastOutcome,
        );
      } on Object catch (e, stackTrace) {
        _report(e, stackTrace);
        _lastOutcome = originalPublisher?.outcome;
        terminal = FusePlasmaFailure(
          exception: FailureException(),
          error: e,
          outcome: _lastOutcome,
        );
      }
      if (!emit.isDone) emit(terminal);
    } finally {
      _busy = false;
    }
  }

  @override
  void onChange(Change<FusePlasmaState> change) {
    if (change.nextState is! FusePlasmaDone &&
        change.nextState is! FusePlasmaFailure) {
      super.onChange(change);
      return;
    }
    try {
      super.onChange(change);
    } on Object catch (error, trace) {
      // Terminal observer failure cannot replace the original delivered state.
      _report(error, trace);
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

  @override
  Future<void> close() {
    _closing = true;
    return super.close();
  }

  void _report(Object error, StackTrace trace) {
    try {
      addError(error, trace);
    } on Object {
      // Diagnostics cannot strand the original operation's terminal state.
    }
  }
}
