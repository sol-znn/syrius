import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'seed_policy.dart';

/// Observes one actual confirmation's original shared-sender request.
/// It never submits, reserves, signs, replaces or cancels that request.
final class LabTransferWitness implements SeedOriginal {
  LabTransferWitness._(this.sender, this.intent, this._ownerCurrent) {
    _subscription = sender.stream.listen(
      _observe,
      onError: (Object error, StackTrace trace) {
        if (!_terminal) {
          _invalid = true;
          _error ??= error;
        }
      },
      onDone: () {
        if (!_terminal) {
          _invalid = true;
          _terminal = true;
        }
      },
    );
  }

  /// The caller supplies its live owned-lab receipt and actual UI intent.
  /// A saved snapshot or a similarly populated request is not authority.
  factory LabTransferWitness.capture({
    required SendTransactionBloc sender,
    required SendIntent intent,
    required String owner,
    required String recipient,
    required bool Function() isCurrent,
  }) {
    bool current;
    try {
      current = isCurrent();
    } on Object {
      current = false;
    }
    if (!current || sender.isClosed || sender.busy.value ||
        identical(sender.state.requestId, intent.requestId) ||
        intent.fromAddress != owner || intent.toAddress != recipient ||
        owner == recipient || intent.tokenStandard != znnZts.toString() ||
        intent.amount != BigInt.from(100000000)) {
      throw const SeedRefused('original-transfer-review-required');
    }
    return LabTransferWitness._(sender, intent, isCurrent);
  }

  /// The identical shared sender captured from the actual Send view.
  final SendTransactionBloc sender;

  /// The identical immutable intent displayed by the original confirmation.
  final SendIntent intent;
  final bool Function() _ownerCurrent;
  late final StreamSubscription<SendTransactionState> _subscription;
  Future<void>? _closing;
  bool _started = false;
  bool _terminal = false;
  bool _invalid = false;
  bool _revoked = false;
  bool _detached = false;
  SendTransactionStatus? _terminalStatus;
  AccountBlockTemplate? _result;
  Object? _error;
  String? _hash;

  /// The original owner cannot be revived by returning to old scalar values.
  bool get isCurrent {
    if (_revoked || _detached) return false;
    try {
      _revoked = sender.isClosed || !_ownerCurrent();
    } on Object {
      _revoked = true;
    }
    return !_revoked;
  }

  /// The original result object remains available after owner revocation.
  AccountBlockTemplate? get result => _result;

  /// The sender's observed failure cannot establish node rejection.
  Object? get error => _error;

  /// Whether the same live request has entered the original sender.
  bool get started => _started;

  /// One passive label from already retained facts, never new authority.
  /// Reading it cannot revoke, revive, submit or alter the original request.
  String get observedState {
    if (_detached) return 'detached';
    if (_revoked) return 'owner_revoked';
    if (_error != null) return 'sender_failed';
    if (_invalid) return 'witness_invalid';
    if (!_started) return 'not_started';
    if (!_terminal) return 'pending';
    return 'result_observed';
  }

  /// Classifies only the retained display error of this exact terminal request.
  /// The sender can sanitize its original error to a generic failure. This
  /// label cannot establish the original cause, rejection or publication state.
  String? get observedDisplayError {
    final Object? error = _error;
    if (_detached || _revoked || !_started || !_terminal ||
        _terminalStatus != SendTransactionStatus.failure || error == null) {
      return null;
    }
    if (error is NodeNotSyncedException) return 'node_not_synced';
    if (error is FailureException) return 'generic_failure';
    return 'other';
  }

  /// Recheck before pointer down/up, never after normal confirmation closure.
  void requireReady() {
    if (!isCurrent || _started || _terminal || sender.busy.value) {
      throw const SeedRefused('original-transfer-attempt-held');
    }
  }

  @override
  Object get identity => intent.requestId;
  @override
  bool get settled => _terminal;
  @override
  bool get failed {
    if (_invalid || _error != null || _revoked ||
        !_detached && !isCurrent) {
      return true;
    }
    final AccountBlockTemplate? original = _result;
    try {
      if (original != null &&
          (original.hash.toString() != _hash || !_matches(original))) {
        _invalid = true;
      }
    } on Object {
      _invalid = true;
    }
    return _invalid;
  }

  /// Success is observed after the original publisher returns from release.
  /// A release exception reaches [failed]; it cannot be a positive result.
  @override
  bool get releaseFailed => false;
  @override
  String? get acceptedHash => _hash;

  bool _matches(AccountBlockTemplate value) =>
      value.chainIdentifier == 321 &&
      value.blockType == BlockTypeEnum.userSend.index &&
      value.address.toString() == intent.fromAddress &&
      value.toAddress.toString() == intent.toAddress &&
      value.tokenStandard.toString() == intent.tokenStandard &&
      value.amount == intent.amount && value.data.isEmpty;

  void _observe(SendTransactionState state) {
    // In particular, automatic receives use their own request identities.
    if (!identical(state.requestId, intent.requestId)) return;
    if (_terminal) {
      if (state.status != _terminalStatus ||
          !identical(state.data, _result) ||
          !identical(state.error, _error)) {
        _invalid = true;
      }
      return;
    }
    if (state.origin != SendTransactionOrigin.transfer) _invalid = true;
    if (state.status == SendTransactionStatus.loading) {
      if (state.data != null || state.error != null) _invalid = true;
      _started = true;
      return;
    }
    _terminal = true;
    _terminalStatus = state.status;
    _result = state.data;
    _error = state.error;
    final AccountBlockTemplate? original = _result;
    if (original != null) {
      final String hash = original.hash.toString();
      if (seedHash(hash)) _hash = hash;
    }
    if (!_started || state.status != SendTransactionStatus.success ||
        _error != null || original == null || _hash == null ||
        !_matches(original)) {
      _invalid = true;
    }
  }

  /// Detaches only this observer; the original sender and Future keep running.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _detached = true;
    if (!_terminal) _invalid = true;
    await _subscription.cancel();
  }
}
