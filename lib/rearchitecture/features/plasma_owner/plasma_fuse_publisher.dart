import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One explicit Fuse draft. Reusing it observes its original attempt only.
class PlasmaFuseDraft {
  PlasmaFuseDraft._(this.address, this.chainId, this._current);

  /// The draft's exact spending account.
  final String address;

  /// The signing chain captured with this draft.
  final int chainId;
  final bool Function() _current;
  _FuseAttempt? _attempt;
  bool _revoked = false;

  bool get _isCurrent => !_revoked && !(_revoked = !_current());
}

/// An admitted Fuse's immutable arguments and identical original SDK result.
class PlasmaFuseOutcome {
  /// Copies receipt identity without inferring chain confirmation.
  const PlasmaFuseOutcome({
    required this.address,
    required this.chainId,
    required this.beneficiary,
    required this.amount,
    required this.result,
    required this.accepted,
    this.publicationHash,
  });

  /// The original spending account.
  final String address;

  /// The original signing chain.
  final int chainId;

  /// The original address receiving plasma.
  final String beneficiary;

  /// The exact original QSR smallest units.
  final BigInt amount;

  /// The sender's original result or original error, without replacement.
  final SendRequestResult result;

  /// An exact accepted SDK response, distinct from confirmation.
  final bool accepted;

  /// Copied once before a caller can mutate the returned SDK block.
  final String? publicationHash;
}

class _FuseOwner extends ChangeNotifier {
  _FuseAttempt? held;
  PlasmaFuseDraft? rearmed;

  void changed() {
    try {
      notifyListeners();
    } on Object {
      // Display observers cannot replace an original request or its hold.
    }
  }
}

class _FuseAttempt {
  _FuseAttempt(this.session, this.beneficiary, this.amount, this.expected);

  final PlasmaSession session;
  final String beneficiary;
  final BigInt amount;
  final AccountBlockTemplate expected;
  final Completer<AccountBlockTemplate> completion =
      Completer<AccountBlockTemplate>();
  bool admitted = false;
  PlasmaFuseOutcome? outcome;
  Object? error;
}

/// Shares Fuse holds across every publisher using the shell's sender.
class PlasmaFusePublisher extends AccountBlockUtils {
  /// Captures a draft before fresh proof, sender admission or preparation.
  PlasmaFusePublisher({
    required this.sender,
    required this.session,
    required this.beneficiary,
    required this.amount,
    this.isCurrent,
    this.draft,
  }) : _owner = _ownerFor(sender, session.address, session.chainId) {
    _attempt = draft?._attempt;
    if (_attempt == null &&
        !(draft != null && identical(_owner.rearmed, draft))) {
      _attempt = _owner.held;
    }
  }

  /// The existing shared sender, also used by cancellation and other forms.
  final SendTransactionBloc sender;

  /// Captured account and original transports.
  final PlasmaSession session;

  /// The original beneficiary.
  final String beneficiary;

  /// Exact QSR smallest units, without a floating-point conversion.
  final BigInt amount;

  /// The original opening and page authority.
  final bool Function()? isCurrent;

  /// An explicit form draft; old events keep their original association.
  final PlasmaFuseDraft? draft;
  final _FuseOwner _owner;
  _FuseAttempt? _attempt;

  static final Expando<Map<(int, String), _FuseOwner>> _owners =
      Expando<Map<(int, String), _FuseOwner>>();
  static final Expando<List<PlasmaFuseOutcome>> _outcomes =
      Expando<List<PlasmaFuseOutcome>>();

  static _FuseOwner _ownerFor(
    SendTransactionBloc sender,
    String address,
    int chainId,
  ) => (_owners[sender] ??= <(int, String), _FuseOwner>{}).putIfAbsent(
    (chainId, address),
    _FuseOwner.new,
  );

  /// Every admitted original remains inspectable after later explicit drafts.
  static List<PlasmaFuseOutcome> outcomesFor(SendTransactionBloc sender) =>
      List<PlasmaFuseOutcome>.unmodifiable(
        _outcomes[sender] ?? const <PlasmaFuseOutcome>[],
      );

  /// Notifies presentation of an admitted hold or its original outcome.
  static Listenable changesFor(
    SendTransactionBloc sender,
    PlasmaSession session,
  ) => _ownerFor(sender, session.address, session.chainId);

  /// The current owner's held original, including admitted uncertainty.
  static PlasmaFuseOutcome? heldOutcome(
    SendTransactionBloc sender,
    PlasmaSession session,
  ) => _ownerFor(sender, session.address, session.chainId).held?.outcome;

  /// A held owner cannot spend through an edited payload or another publisher.
  static bool allowsDraft(
    SendTransactionBloc sender,
    PlasmaSession session,
    PlasmaFuseDraft? draft,
  ) {
    final _FuseOwner owner = _ownerFor(
      sender,
      session.address,
      session.chainId,
    );
    return session.isCurrent &&
        (draft == null ||
            (draft.address == session.address &&
                draft.chainId == session.chainId &&
                draft._isCurrent)) &&
        (owner.held == null ||
            (draft != null &&
                draft._attempt == null &&
                identical(owner.rearmed, draft)));
  }

  /// Begins an initial draft only while this owner has no original hold.
  static PlasmaFuseDraft? beginDraft({
    required SendTransactionBloc sender,
    required PlasmaSession session,
    required bool Function() isCurrent,
  }) {
    if (!session.isCurrent ||
        !isCurrent() ||
        _ownerFor(sender, session.address, session.chainId).held != null) {
      return null;
    }
    return PlasmaFuseDraft._(session.address, session.chainId, isCurrent);
  }

  /// SDK acceptance and pending-list absence cannot enable Another.
  static bool canRearm(
    SendTransactionBloc sender,
    PlasmaSession session,
  ) {
    final PlasmaFuseOutcome? original = heldOutcome(sender, session);
    final String? hash = original?.publicationHash;
    return original != null &&
        original.accepted &&
        hash != null &&
        session.confirmsOriginal(hash, original.address, original.chainId);
  }

  /// Only an explicit action after positive exact confirmation grants a draft.
  static PlasmaFuseDraft? another({
    required SendTransactionBloc sender,
    required PlasmaSession session,
    required bool Function() isCurrent,
  }) {
    if (!isCurrent() || !canRearm(sender, session)) return null;
    final _FuseOwner owner = _ownerFor(
      sender,
      session.address,
      session.chainId,
    );
    final PlasmaFuseDraft next = PlasmaFuseDraft._(
      session.address,
      session.chainId,
      isCurrent,
    );
    owner
      ..rearmed = next
      ..changed();
    return next;
  }

  /// This publisher's original result remains available after disposal.
  PlasmaFuseOutcome? get outcome => _attempt?.outcome;

  bool get _current =>
      session.isCurrent &&
      (isCurrent?.call() ?? true) &&
      (draft?._isCurrent ?? true);

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purposeOfGeneratingPlasma, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) {
    try {
      final AccountBlockTemplate block = AccountBlockTemplate.fromJson(
        transactionParams.toJson(),
      );
      final _FuseAttempt? associated = _attempt ?? draft?._attempt;
      if (associated != null) {
        _attempt = associated;
        return _observe(associated, block, address);
      }
      final _FuseAttempt? held = _owner.held;
      final bool rearmed = draft != null && identical(_owner.rearmed, draft);
      if (held != null && !rearmed) {
        _attempt = held;
        return _observe(held, block, address);
      }
      if (!_current ||
          amount < fuseMinQsrAmount ||
          (draft != null &&
              (draft!.address != session.address ||
                  draft!.chainId != session.chainId)) ||
          (held != null && !canRearm(sender, session))) {
        throw FailureException();
      }
      final AccountBlockTemplate expected = AccountBlockTemplate.fromJson(
        session.fuseBlock(beneficiary, amount).toJson(),
      );
      if (!_matches(block, expected) ||
          expected.chainIdentifier != session.chainId ||
          (address != null && address.toString() != session.address)) {
        throw FailureException();
      }
      final _FuseAttempt attempt = _FuseAttempt(
        session,
        beneficiary,
        amount,
        expected,
      );
      _attempt = attempt;
      if (draft != null) draft!._attempt = attempt;
      final Object reservation = Object();
      if (!sender.tryReserve(reservation)) {
        attempt.error = FailureException();
        attempt.completion.completeError(attempt.error!);
        return attempt.completion.future;
      }
      _owner.held = attempt;
      _owner.rearmed = null;
      _owner.changed();
      unawaited(
        _publish(
          attempt,
          block,
          reservation,
          purposeOfGeneratingPlasma,
          canPublish,
        ),
      );
      return attempt.completion.future;
    } on Object catch (error, trace) {
      return Future<AccountBlockTemplate>.error(error, trace);
    }
  }

  Future<AccountBlockTemplate> _observe(
    _FuseAttempt attempt,
    AccountBlockTemplate block,
    Address? address,
  ) {
    if (attempt.session.address != session.address ||
        attempt.session.chainId != session.chainId ||
        (draft != null &&
            (draft!.address != session.address ||
                draft!.chainId != session.chainId))) {
      return Future<AccountBlockTemplate>.error(FailureException());
    }
    if (attempt.beneficiary != beneficiary ||
        attempt.amount != amount ||
        !_matches(block, attempt.expected) ||
        (address != null && address.toString() != session.address)) {
      return Future<AccountBlockTemplate>.error(
        attempt.outcome?.result.error ?? attempt.error ?? FailureException(),
      );
    }
    return attempt.completion.future;
  }

  Future<void> _publish(
    _FuseAttempt attempt,
    AccountBlockTemplate block,
    Object reservation,
    String purpose,
    bool Function()? canPublish,
  ) async {
    SendRequestResult? original;
    try {
      if (!_current) throw FailureException();
      final AccountInfo account = await session.readAccount();
      final BigInt? available = plasmaQsrFromAccount(account, session.address);
      if (!_current || available == null || available < amount) {
        throw FailureException();
      }
      bool current() => _current && (canPublish?.call() ?? true);
      final SendRequestHandle? handle = sender.trySubmitOwned(
        owner: reservation,
        requestId: Object(),
        block: block,
        fromAddress: session.address,
        reasonForGeneratingPlasma: purpose,
        origin: SendTransactionOrigin.contract,
        canStart: current,
        canPublish: current,
      );
      if (handle == null) throw FailureException();
      attempt.admitted = true;
      original = await handle.result;
      final AccountBlockTemplate? response = original.block;
      final bool exact =
          original.accepted &&
          response != null &&
          response.address.toString() == session.address &&
          response.hash != emptyHash &&
          _matches(response, attempt.expected);
      _retain(attempt, original, exact);
      if (exact) {
        attempt.completion.complete(response);
      } else {
        final Object error = original.error ?? FailureException();
        attempt.error = error;
        attempt.completion.completeError(error);
      }
    } on Object catch (error, trace) {
      attempt.error = original?.error ?? error;
      if (attempt.admitted) {
        if (attempt.outcome == null) {
          _retain(attempt, original ?? SendRequestResult(error: error), false);
        }
      } else if (identical(_owner.held, attempt)) {
        _owner.held = null;
      }
      if (!attempt.completion.isCompleted) {
        attempt.completion.completeError(attempt.error!, trace);
      }
    } finally {
      sender.releaseReservation(reservation);
      _owner.changed();
    }
  }

  void _retain(_FuseAttempt attempt, SendRequestResult result, bool exact) {
    final PlasmaFuseOutcome outcome = PlasmaFuseOutcome(
      address: session.address,
      chainId: session.chainId,
      beneficiary: beneficiary,
      amount: amount,
      result: result,
      accepted: exact,
      publicationHash: _originalHash(result),
    );
    attempt.outcome = outcome;
    (_outcomes[sender] ??= <PlasmaFuseOutcome>[]).add(outcome);
  }
}

String? _originalHash(SendRequestResult result) {
  try {
    return result.block?.hash.toString();
  } on Object {
    return null;
  }
}

bool _matches(AccountBlockTemplate a, AccountBlockTemplate b) =>
    a.chainIdentifier == b.chainIdentifier &&
    a.toAddress == b.toAddress &&
    a.blockType == b.blockType &&
    a.tokenStandard == b.tokenStandard &&
    a.amount == b.amount &&
    listEquals(a.data, b.data);
