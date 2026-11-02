import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Gives existing registration blocs the shared sender's exact admission.
class RegistrationPublisher extends AccountBlockUtils {
  /// Supplied owner publishers already carry their own fresh ownership checks.
  RegistrationPublisher({
    required SendTransactionBloc sender,
    required this._confirmation,
  }) : _sender = sender,
       _journal = _journals[sender] ??= <String, _RegistrationAttempt>{},
       _ownerJournal = _ownerJournals[sender] ??=
           <(String, int), _RegistrationAttempt>{};

  static final Expando<Map<String, _RegistrationAttempt>> _journals =
      Expando<Map<String, _RegistrationAttempt>>();
  static final Expando<List<SendRequestResult>> _results =
      Expando<List<SendRequestResult>>();
  static final Expando<Map<(String, int), _RegistrationAttempt>>
  _ownerJournals = Expando<Map<(String, int), _RegistrationAttempt>>();

  final SendTransactionBloc _sender;
  final RegistrationConfirmation _confirmation;
  final Map<String, _RegistrationAttempt> _journal;
  final Map<(String, int), _RegistrationAttempt> _ownerJournal;
  _RegistrationAttempt? _lastAttempt;

  _RegistrationAttempt? get _ownedAttempt {
    final String? owner = _confirmation.context?.ownerAddress;
    return _ownerJournal[(owner ?? '', _confirmation.chainId)] ?? _lastAttempt;
  }

  /// Retains the original outcome even if the form leaves while it is running.
  SendRequestResult? get lastResult => _ownedAttempt?.result;

  /// Every admitted original survives route disposal and later registrations.
  static List<SendRequestResult> originalResultsFor(
    SendTransactionBloc sender,
  ) => List<SendRequestResult>.unmodifiable(
    _results[sender] ?? const <SendRequestResult>[],
  );

  /// A failure after admission cannot authorize another signature.
  bool get isUncertain {
    final _RegistrationAttempt? attempt = _ownedAttempt;
    return attempt != null &&
        attempt.admitted &&
        attempt.completion.isCompleted &&
        !attempt.exactAccepted;
  }

  /// A later explicit registration needs positive original confirmation.
  bool get canStartNewAttempt {
    if (!_confirmation.isCurrent) return false;
    final _RegistrationAttempt? attempt = _ownedAttempt;
    return attempt == null || !attempt.admitted || _confirmed(attempt);
  }

  bool _confirmed(_RegistrationAttempt attempt) =>
      attempt.exactAccepted &&
      _confirmation.hasConfirmedOriginal(
        hash: attempt.publicationHash!,
        owner: attempt.owner,
        chainId: attempt.chainId,
      );

  void _requireCurrent() {
    if (!_confirmation.isCurrent || _confirmation.publication != null) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
  }

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purposeOfGeneratingPlasma, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) {
    try {
      _requireCurrent();
      // Copy before busy observers or deferred admission can change the draft.
      final AccountBlockTemplate block = AccountBlockTemplate.fromJson(
        transactionParams.toJson(),
      );
      final String ownerAddress = _confirmation.context!.ownerAddress;
      if ((address != null && address.toString() != ownerAddress) ||
          block.chainIdentifier != _confirmation.chainId) {
        throw FailureException(message: currentL10n.publicationSessionChanged);
      }
      final String key = jsonEncode(<Object?>[
        _confirmation.chainId,
        ownerAddress,
        block.blockType,
        block.toAddress.toString(),
        block.tokenStandard.toString(),
        block.amount.toString(),
        block.data,
      ]);
      final (String, int) ownerKey = (ownerAddress, _confirmation.chainId);
      final _RegistrationAttempt? heldOwner = _ownerJournal[ownerKey];
      if (heldOwner != null && heldOwner.admitted && !_confirmed(heldOwner)) {
        _lastAttempt = heldOwner;
        if (identical(_journal[key], heldOwner) &&
            heldOwner.completion.isCompleted) {
          return heldOwner.completion.future;
        }
        // Editing a name or amount cannot turn uncertainty into new authority.
        Error.throwWithStackTrace(
          heldOwner.result?.error ?? FailureException(),
          StackTrace.current,
        );
      }
      final _RegistrationAttempt? previous = _journal[key];
      if (previous != null && !_confirmed(previous)) {
        _lastAttempt = previous;
        if (!previous.completion.isCompleted) throw FailureException();
        return previous.completion.future;
      }
      final AccountBlockTemplate expected = AccountBlockTemplate.fromJson(
        block.toJson(),
      );
      final Object reservation = Object();
      if (!_sender.tryReserve(reservation)) throw FailureException();
      final _RegistrationAttempt attempt = _RegistrationAttempt(
        ownerAddress,
        _confirmation.chainId,
        expected,
      );
      _journal[key] = attempt;
      _ownerJournal[ownerKey] = attempt;
      _lastAttempt = attempt;
      unawaited(
        _publish(
          key: key,
          attempt: attempt,
          reservation: reservation,
          block: block,
          purpose: purposeOfGeneratingPlasma,
          canPublish: canPublish,
        ),
      );
      return attempt.completion.future;
    } on Object catch (error, trace) {
      return Future<AccountBlockTemplate>.error(error, trace);
    }
  }

  Future<void> _publish({
    required String key,
    required _RegistrationAttempt attempt,
    required Object reservation,
    required AccountBlockTemplate block,
    required String purpose,
    required bool Function()? canPublish,
  }) async {
    try {
      _requireCurrent();
      final SendRequestHandle? request = _sender.trySubmitOwned(
        owner: reservation,
        requestId: Object(),
        block: block,
        fromAddress: attempt.owner,
        reasonForGeneratingPlasma: purpose,
        origin: SendTransactionOrigin.contract,
        canStart: () =>
            _confirmation.isCurrent &&
            _confirmation.publication == null &&
            (canPublish?.call() ?? true),
        canPublish: () =>
            _confirmation.isCurrent &&
            _confirmation.publication == null &&
            (canPublish?.call() ?? true),
      );
      if (request == null) throw FailureException();
      attempt.admitted = true;
      final SendRequestResult result = await request.result;
      attempt.result = result;
      (_results[_sender] ??= <SendRequestResult>[]).add(result);
      final AccountBlockTemplate? accepted = result.block;
      final AccountBlockTemplate expected = attempt.expected;
      attempt.exactAccepted =
          result.accepted &&
          accepted != null &&
          accepted.address.toString() == attempt.owner &&
          accepted.chainIdentifier == attempt.chainId &&
          accepted.hash != emptyHash &&
          accepted.blockType == expected.blockType &&
          accepted.toAddress == expected.toAddress &&
          accepted.tokenStandard == expected.tokenStandard &&
          accepted.amount == expected.amount &&
          listEquals(accepted.data, expected.data);
      if (attempt.exactAccepted) {
        attempt.publicationHash = accepted!.hash.toString();
        attempt.completion.complete(accepted);
        return;
      }
      final Object? error = result.error;
      Error.throwWithStackTrace(
        error ?? FailureException(),
        StackTrace.current,
      );
    } on Object catch (error, trace) {
      if (!attempt.admitted && identical(_journal[key], attempt)) {
        _journal.remove(key);
        final (String, int) ownerKey = (attempt.owner, attempt.chainId);
        if (identical(_ownerJournal[ownerKey], attempt)) {
          _ownerJournal.remove(ownerKey);
        }
      }
      attempt.completion.completeError(error, trace);
    } finally {
      _sender.releaseReservation(reservation);
    }
  }
}

class _RegistrationAttempt {
  _RegistrationAttempt(this.owner, this.chainId, this.expected);

  final String owner;
  final int chainId;
  final AccountBlockTemplate expected;
  final Completer<AccountBlockTemplate> completion =
      Completer<AccountBlockTemplate>();
  bool admitted = false;
  bool exactAccepted = false;
  String? publicationHash;
  SendRequestResult? result;
}
