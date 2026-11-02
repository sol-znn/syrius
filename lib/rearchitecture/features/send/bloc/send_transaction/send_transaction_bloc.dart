import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'send_transaction_bloc.g.dart';

part 'send_transaction_event.dart';

part 'send_transaction_state.dart';

part 'send_request.dart';

/// A bloc that handles sending payments.
class SendTransactionBloc
    extends HydratedBloc<SendTransactionEvent, SendTransactionState> {
  /// Creates a new instance of [SendTransactionBloc].
  ///
  /// Initializes the Bloc with the initial state and sets up event handlers for
  /// [SendTransactionInitiate] and [SendTransactionInitiateFromBlock] events.
  SendTransactionBloc({
    AccountBlockUtils? accountBlockUtilsHelper,
    ZenonAddressUtils? zenonAddressUtils,
    Future<void> Function(String from, String to)? recordRecipient,
  }) : accountBlockUtilsHelper = accountBlockUtilsHelper ?? AccountBlockUtils(),
       zenonAddressUtilsHelper = zenonAddressUtils ?? ZenonAddressUtils(),
       _recordRecipient = recordRecipient ?? ContactsStore.instance.noteSent,
       super(const SendTransactionState()) {
    on<SendTransactionInitiate>(_onSendTransfer);
    on<SendTransactionInitiateFromBlock>(_onSendTransferWithBlock);
  }

  /// Helper class with the purpose of facilitating dependency injections.
  final AccountBlockUtils accountBlockUtilsHelper;

  /// Helper class with the purpose of facilitating dependency injections.
  final ZenonAddressUtils zenonAddressUtilsHelper;

  final Future<void> Function(String from, String to) _recordRecipient;

  late final _SenderBusyNotifier _busy = _SenderBusyNotifier(_report);
  Object? _reservation;
  _SendAdmission? _active;
  bool _releaseWhenIdle = false;
  Future<void>? _closing;

  /// Admission includes a collection batch's gap between its requests.
  ValueListenable<bool> get busy => _busy;

  /// Admits one confirmed transfer and retains its outcome through close.
  /// A request identity is required to bind the result to its confirmation.
  /// [canStart] is rechecked after reentrant loading observers, before
  /// transport.
  SendRequestHandle? trySubmitTransfer(
    SendTransactionInitiate event, {
    bool Function()? canStart,
  }) {
    if (event.requestId == null ||
        _closing != null ||
        isClosed ||
        _active != null ||
        _reservation != null) {
      return null;
    }
    final _SendAdmission admission = _SendAdmission(event, canStart: canStart);
    _active = admission;
    _enqueue(admission);
    return SendRequestHandle._(event.requestId!, admission.completion.future);
  }

  /// Reserves the existing sender without queuing or starting a publication.
  bool tryReserve(Object owner) {
    if (_closing != null ||
        isClosed ||
        _active != null ||
        _reservation != null) {
      return false;
    }
    _reservation = owner;
    _refreshBusy();
    return _closing == null && !isClosed && identical(owner, _reservation);
  }

  /// Admits one request only while its exact batch still owns the reservation.
  SendRequestHandle? trySubmitOwned({
    required Object owner,
    required Object requestId,
    required AccountBlockTemplate block,
    required String fromAddress,
    required String reasonForGeneratingPlasma,
    SendTransactionOrigin origin = SendTransactionOrigin.collection,
    bool Function()? canStart,
    bool Function()? canPublish,
  }) {
    if (_closing != null ||
        isClosed ||
        !identical(owner, _reservation) ||
        _active != null ||
        _releaseWhenIdle) {
      return null;
    }
    final SendTransactionInitiateFromBlock event =
        SendTransactionInitiateFromBlock(
          block: block,
          fromAddress: fromAddress,
          reasonForGeneratingPlasma: reasonForGeneratingPlasma,
          requestId: requestId,
          origin: origin,
        );
    final _SendAdmission admission = _SendAdmission(
      event,
      owner: owner,
      canStart: canStart,
      canPublish: canPublish,
    );
    _active = admission;
    _enqueue(admission);
    return SendRequestHandle._(requestId, admission.completion.future);
  }

  /// A running original request keeps its hold until its outcome is observed.
  void releaseReservation(Object owner) {
    if (!identical(owner, _reservation)) return;
    if (_active != null) {
      _releaseWhenIdle = true;
    } else {
      _reservation = null;
      _releaseWhenIdle = false;
      _refreshBusy();
    }
  }

  /// Refuses overlapping legacy events instead of queuing a second send.
  @override
  void add(SendTransactionEvent event) {
    if (_closing != null ||
        isClosed ||
        _active != null ||
        _reservation != null) {
      return;
    }
    final _SendAdmission admission = _SendAdmission(event);
    _active = admission;
    _enqueue(admission);
  }

  void _enqueue(_SendAdmission admission) {
    try {
      // A busy listener may close the sender, so enqueue before notifying it.
      super.add(admission.event);
    } on Object catch (error, trace) {
      _report(error, trace);
      _finish(admission, SendRequestResult(error: error));
    }
    _refreshBusy();
  }

  void _refreshBusy() {
    try {
      _busy.value = _active != null || _reservation != null;
    } on Object catch (error, trace) {
      _report(error, trace);
    }
  }

  Future<void> _onSendTransfer(
    SendTransactionInitiate event,
    Emitter<SendTransactionState> emit,
  ) => _run(
    event,
    emit,
    () => accountBlockUtilsHelper.createAccountBlock(
      AccountBlockTemplate.send(
        Address.parse(event.toAddress),
        event.token.tokenStandard,
        event.amount,
        event.data,
      ),
      PlasmaPurpose.sendTransaction.message,
      address: Address.parse(event.fromAddress),
      waitForRequiredPlasma: true,
    ),
  );

  Future<void> _onSendTransferWithBlock(
    SendTransactionInitiateFromBlock event,
    Emitter<SendTransactionState> emit,
  ) => _run(
    event,
    emit,
    () {
      final bool Function()? guard = _active?.canPublish;
      if (guard != null) {
        return accountBlockUtilsHelper.createAccountBlock(
          event.block,
          event.reasonForGeneratingPlasma,
          address: Address.parse(event.fromAddress),
          waitForRequiredPlasma: true,
          canPublish: guard,
        );
      }
      return accountBlockUtilsHelper.createAccountBlock(
        event.block,
        event.reasonForGeneratingPlasma,
        address: Address.parse(event.fromAddress),
        waitForRequiredPlasma: true,
      );
    },
  );

  Future<void> _run(
    SendTransactionEvent event,
    Emitter<SendTransactionState> emit,
    Future<AccountBlockTemplate> Function() publish,
  ) async {
    final _SendAdmission? admission = _active;
    if (admission == null || !identical(admission.event, event)) return;
    _display(
      emit,
      SendTransactionState(
        status: SendTransactionStatus.loading,
        requestId: event.requestId,
        origin: event.origin,
      ),
    );
    // A loading observer can close before the original publication starts.
    if (admission.drained.isCompleted) return;
    SendRequestResult result;
    try {
      // Busy and loading observers can revoke the original confirmation
      // before this queued handler reaches the existing transport.
      if (!(admission.canStart?.call() ?? true)) {
        throw StateError('Publication context changed before dispatch');
      }
      if (admission.drained.isCompleted ||
          _closing != null ||
          !identical(_active, admission)) {
        return;
      }
      admission.started = true;
      final AccountBlockTemplate response = await publish();
      result = SendRequestResult(block: response);
    } on Object catch (error, trace) {
      result = SendRequestResult(error: error);
      _report(error, trace);
    }
    try {
      final Object? error = result.error;
      if (result.accepted) {
        _refreshBalance();
        if (event is SendTransactionInitiate) {
          // Read the original accepted event, even if its form left or this
          // sender is draining through close. Convenience storage cannot
          // change the original publication's result or delay its settlement.
          unawaited(
            Future<void>.sync(
              () => _recordRecipient(event.fromAddress, event.toAddress),
            ).catchError(_report),
          );
        }
      }
      _display(
        emit,
        SendTransactionState(
          status: result.accepted
              ? SendTransactionStatus.success
              : SendTransactionStatus.failure,
          data: result.block,
          error: result.accepted
              ? null
              : error is SyriusException
              ? error
              : FailureException(),
          requestId: event.requestId,
          origin: event.origin,
        ),
      );
    } finally {
      _finish(admission, result);
    }
  }

  void _finish(_SendAdmission admission, SendRequestResult result) {
    if (admission.drained.isCompleted) return;
    if (identical(_active, admission)) {
      _active = null;
      if (_releaseWhenIdle) {
        _reservation = null;
        _releaseWhenIdle = false;
      }
    }
    // Settle the original result before any idle listener can close or reenter.
    admission.completion.complete(result);
    admission.drained.complete();
    _refreshBusy();
  }

  void _refreshBalance() {
    try {
      unawaited(
        Future<void>.sync(
          zenonAddressUtilsHelper.refreshBalance,
        ).catchError(_report),
      );
    } on Object catch (error, trace) {
      _report(error, trace);
    }
  }

  void _display(
    Emitter<SendTransactionState> emit,
    SendTransactionState next,
  ) {
    try {
      if (!emit.isDone) emit(next);
    } on Object catch (error, trace) {
      _report(error, trace);
    }
  }

  void _report(Object error, StackTrace trace) {
    try {
      addError(error, trace);
    } on Object {
      // A diagnostic observer cannot change an original publication outcome.
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    final Completer<void> completion = Completer<void>();
    _closing = completion.future;
    final _SendAdmission? admission = _active;
    if (admission != null && !admission.started) {
      _finish(
        admission,
        SendRequestResult(
          error: StateError('Sender closed before publication started'),
        ),
      );
    }
    final Future<void> frameworkClose = super.close();
    unawaited(
      _closeOwned(admission, frameworkClose).then<void>(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<void> _closeOwned(
    _SendAdmission? admission,
    Future<void> frameworkClose,
  ) async {
    try {
      await frameworkClose;
    } finally {
      // Bloc.close cancels emitters; it does not drain the original operation.
      if (admission != null) await admission.drained.future;
      _reservation = null;
      _releaseWhenIdle = false;
      _refreshBusy();
      _busy.dispose();
    }
  }

  @override
  SendTransactionState? fromJson(Map<String, dynamic> json) =>
      SendTransactionState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(SendTransactionState state) => state.toJson();

  @override
  void onError(Object error, StackTrace stackTrace) {
    Logger('SendTransactionBloc').warning(
      'onError triggered',
      error,
      stackTrace,
    );
    super.onError(error, stackTrace);
  }
}
