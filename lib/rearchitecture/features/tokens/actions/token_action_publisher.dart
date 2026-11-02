import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_session.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

export 'token_action_session.dart';

/// Captured before the question. No getter rereads an editable controller.
class TokenActionIntent {
  /// The proof and presentation generation must still be current when sent.
  TokenActionIntent({
    required this.proof,
    required this.mode,
    required this.amount,
    required this.receiver,
    required this._isCurrent,
  });

  /// The exact token, owner, chain and successful read shown for this intent.
  final TokenActionProof proof;

  /// Flags has no send path.
  final TokenActionMode mode;

  /// Original smallest units. Ownership transfers use zero.
  final BigInt amount;

  /// Original beneficiary or new owner, frozen before the question.
  final String? receiver;
  final bool Function() _isCurrent;
  bool _revoked = false;

  /// The selected account cannot be substituted after a question.
  String get owner => proof.session.address;

  /// The exact ZTS comes from the original successful getByZts.
  TokenStandard get standard => proof.token.tokenStandard;

  /// Closing and reopening a row or mode cannot restore an observed intent.
  bool get isCurrent =>
      !_revoked && !(_revoked = !proof.isCurrent || !_isCurrent());

  /// One fingerprint across inline forms, legacy dialogs and BLoCs.
  String get fingerprint =>
      '${proof.session.chainId}:$owner:$standard:'
      '${mode.name}:$amount:$receiver';

  /// An existing BLoC adapter adds its own disposal authority to the question.
  TokenActionIntent fenced(bool Function() current) => TokenActionIntent(
    proof: proof,
    mode: mode,
    amount: amount,
    receiver: receiver,
    isCurrent: () => isCurrent && current(),
  );

  /// Fresh proof, permissions and bounds are required before preparation.
  bool accepts(TokenActionProof fresh) {
    if (!isCurrent ||
        !identical(proof.session, fresh.session) ||
        !sameTokenActionMetadata(
          proof.token,
          fresh.token,
          includeSupply: false,
        ) ||
        !fresh.permits(mode) ||
        amount.isNegative ||
        amount.bitLength > 256) {
      return false;
    }
    switch (mode) {
      case TokenActionMode.mint:
        return receiver != null &&
            _validReceiver(receiver!) &&
            amount > BigInt.zero &&
            amount <= fresh.token.maxSupply - fresh.token.totalSupply;
      case TokenActionMode.burn:
        return receiver == null &&
            amount > BigInt.zero &&
            amount <= fresh.balance;
      case TokenActionMode.transfer:
        return receiver != null &&
            _validReceiver(receiver!) &&
            amount == BigInt.zero;
      case TokenActionMode.flags:
        return false;
    }
  }
}

bool _validReceiver(String receiver) {
  try {
    return Address.parse(receiver).toString() == receiver;
  } on Object {
    return false;
  }
}

/// An admitted failure does not prove the node rejected a publication.
enum TokenActionStatus {
  /// Refused before admission. A fresh successful proof may rearm it.
  refused,

  /// The original admitted request is still running.
  submitting,

  /// The original response agrees with the exact original contract block.
  submitted,

  /// The original admitted operation has no exact accepted response.
  unknown,
}

/// Original results survive form disposal, observers and subsequent reads.
class TokenActionOutcome {
  /// Retains the original request, SDK result and error without replacement.
  TokenActionOutcome({
    required this.intent,
    required this.status,
    this.result,
    this.error,
    this.stackTrace,
    this.requestId,
  }) : publicationHash = _originalHash(result);

  /// The immutable original question and fields.
  final TokenActionIntent intent;

  /// Submission is distinct from chain confirmation.
  final TokenActionStatus status;

  /// The sender's identical original result, including an unmodified SDK block.
  final SendRequestResult? result;

  /// The original error, including non-Syrius errors.
  final Object? error;

  /// The original preparation trace when available.
  final StackTrace? stackTrace;

  /// Identity allocated only for this original request.
  final Object? requestId;

  /// The accepted hash is copied once; the SDK result itself stays identical.
  final String? publicationHash;

  /// The SDK response amount is never replaced by the requested mint amount.
  AccountBlockTemplate? get block => result?.block;

  /// Mint's contract units are notification data, separate from native units.
  BigInt? get requestedMintAmount =>
      intent.mode == TokenActionMode.mint ? intent.amount : null;

  /// An adapter can report success only for its own original proof and fields.
  bool belongsTo(TokenActionIntent request) =>
      identical(intent.proof.ticket, request.proof.ticket) &&
      intent.fingerprint == request.fingerprint;
}

/// The exact attempt and Future that original dialog chrome may observe.
class TokenActionSubmission {
  /// Observation never grants publication or confirmation authority.
  const TokenActionSubmission({
    required this.publisher,
    required this.intent,
    required this.settlement,
  });

  /// The captured publisher that owns the original sender journal.
  final TokenActionPublisher publisher;

  /// The original proof, account, token and immutable question fields.
  final TokenActionIntent intent;

  /// The actual original Future, including refusal or uncertainty.
  final Future<TokenActionOutcome> settlement;
}

class _TokenActionRecord {
  _TokenActionRecord(this.outcome);

  TokenActionOutcome outcome;
  final Completer<TokenActionOutcome> settled = Completer<TokenActionOutcome>();
  bool rearming = false;
}

typedef _TokenActionKey = (String, int, String);

class _TokenActionTicket {
  _TokenActionTicket(this.key, {this.original});

  final _TokenActionKey key;
  _TokenActionRecord? original;
}

class _TokenActionJournal {
  final Map<_TokenActionKey, _TokenActionRecord> holds =
      <_TokenActionKey, _TokenActionRecord>{};
  final Map<_TokenActionKey, _TokenActionRecord> latest =
      <_TokenActionKey, _TokenActionRecord>{};
  final Map<Object, _TokenActionTicket> tickets =
      <Object, _TokenActionTicket>{};
  final List<TokenActionOutcome> originals = <TokenActionOutcome>[];
}

/// One typed publication boundary for every existing token action surface.
class TokenActionPublisher {
  /// Injected sessions and the existing sender allow wholly offline tests.
  TokenActionPublisher({
    required this.sender,
    required this.session,
    this.confirmationChanges,
    this._hasConfirmedOriginal,
  }) : _journal = _journals[sender] ??= _TokenActionJournal();

  /// Returns unavailable while locked or without the exact selected account.
  static TokenActionPublisher? capture({
    required SendTransactionBloc sender,
    required String address,
  }) {
    final WalletActionContext? action = WalletActionContext.capture(address);
    if (action == null) return null;
    final TokenActionSession session = TokenActionSession.wallet(action);
    final List<String> addresses = List<String>.unmodifiable(
      kDefaultAddressList.whereType<String>(),
    );
    final InFlightBlocks flights = WalletFlightRegistry.instance.forWallet(
      session.chainId,
      addresses,
    );
    return TokenActionPublisher(
      sender: sender,
      session: session,
      confirmationChanges: flights,
      hasConfirmedOriginal:
          ({
            required String hash,
            required String owner,
            required int chainId,
          }) {
            if (!session.isCurrent ||
                chainId != session.chainId ||
                owner != session.address ||
                !addresses.contains(owner)) {
              return false;
            }
            return flights.hasConfirmed(Hash.parse(hash));
          },
    );
  }

  static final Expando<_TokenActionJournal> _journals =
      Expando<_TokenActionJournal>('Token action originals');

  /// Shared with Send, collection and the other contract forms.
  final SendTransactionBloc sender;

  /// Captured APIs, transports, URLs and wallet revision.
  final TokenActionSession session;

  /// The existing wallet flight model owns this signal and its lifetime.
  final Listenable? confirmationChanges;
  final bool Function({
    required String hash,
    required String owner,
    required int chainId,
  })?
  _hasConfirmedOriginal;
  final _TokenActionJournal _journal;

  /// The most recently observed original result for this publisher instance.
  TokenActionOutcome? _lastOutcome;

  /// Presentation cannot replace this journal's original result.
  TokenActionOutcome? get lastOutcome => _lastOutcome;

  /// Every terminal original survives later attempts and presentation disposal.
  static List<TokenActionOutcome> originalOutcomesFor(
    SendTransactionBloc sender,
  ) => List<TokenActionOutcome>.unmodifiable(
    _journals[sender]?.originals ?? const <TokenActionOutcome>[],
  );

  _TokenActionKey _key(TokenStandard standard) =>
      (session.address, session.chainId, standard.toString());

  /// A display catalog is never publication authority.
  Future<TokenActionProof> read(TokenStandard standard) async {
    final _TokenActionKey key = _key(standard);
    final _TokenActionRecord? heldAtStart = _journal.holds[key];
    final _TokenActionRecord? latestAtStart = _journal.latest[key];
    final TokenActionProof proof = await session.prove(standard);
    final _TokenActionRecord? latest = _journal.latest[key];
    _journal.tickets[proof.ticket] = _TokenActionTicket(
      key,
      original:
          heldAtStart ??
          _journal.holds[key] ??
          (identical(latestAtStart, latest) ? null : latest),
    );
    return proof;
  }

  /// A payload or mode edit cannot evade this owner, chain and token hold.
  TokenActionOutcome? heldFor(TokenStandard standard) =>
      _journal.holds[_key(standard)]?.outcome;

  /// A reopened view can follow the exact held original without publishing.
  Future<TokenActionOutcome>? settlementFor(TokenStandard standard) =>
      _journal.holds[_key(standard)]?.settled.future;

  /// Returns an existing original hold instead of starting a duplicate request.
  TokenActionOutcome? held(TokenActionIntent intent) =>
      (_journal.tickets[intent.proof.ticket]?.original ??
              _journal.holds[_key(intent.standard)])
          ?.outcome;

  /// SDK acceptance alone cannot enable another signature.
  bool canStartAnother(TokenActionOutcome original) {
    final _TokenActionRecord? record =
        _journal.holds[_key(original.intent.standard)];
    final String? hash = original.publicationHash;
    if (!session.isCurrent ||
        record == null ||
        record.rearming ||
        !identical(record.outcome, original) ||
        original.status != TokenActionStatus.submitted ||
        original.intent.owner != session.address ||
        original.intent.proof.session.chainId != session.chainId ||
        hash == null) {
      return false;
    }
    try {
      return _hasConfirmedOriginal?.call(
            hash: hash,
            owner: original.intent.owner,
            chainId: original.intent.proof.session.chainId,
          ) ??
          false;
    } on Object {
      return false;
    }
  }

  /// Explicitly rearms only a confirmed original with a new complete proof.
  Future<TokenActionProof?> another(
    TokenActionOutcome original, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() || !canStartAnother(original)) return null;
    final _TokenActionKey key = _key(original.intent.standard);
    final _TokenActionRecord record = _journal.holds[key]!;
    final Object reservation = Object();
    if (!sender.tryReserve(reservation)) return null;
    record.rearming = true;
    try {
      final TokenActionProof proof = await session.prove(
        original.intent.standard,
      );
      record.rearming = false;
      if (!isCurrent() ||
          !proof.isCurrent ||
          !canStartAnother(original) ||
          !identical(_journal.holds[key], record)) {
        return null;
      }
      _journal.holds.remove(key);
      _journal.tickets[proof.ticket] = _TokenActionTicket(key);
      return proof;
    } on Object {
      return null;
    } finally {
      record.rearming = false;
      sender.releaseReservation(reservation);
    }
  }

  /// Sender reservation covers the fresh proof and every preparation stage.
  Future<TokenActionOutcome> publish(TokenActionIntent intent) async {
    final _TokenActionKey key = _key(intent.standard);
    final _TokenActionTicket? ticket = _journal.tickets[intent.proof.ticket];
    final _TokenActionRecord? previous =
        ticket?.original ?? _journal.holds[key];
    if (previous != null) {
      if (ticket != null) ticket.original = previous;
      return _lastOutcome = await previous.settled.future;
    }
    final _TokenActionRecord record = _TokenActionRecord(
      TokenActionOutcome(intent: intent, status: TokenActionStatus.submitting),
    );
    for (final _TokenActionTicket issued in _journal.tickets.values) {
      if (issued.key == key) issued.original ??= record;
    }
    _journal.holds[key] = record;
    _journal.latest[key] = record;
    final Object owner = Object();
    bool reserved = false;
    SendRequestHandle? request;
    SendRequestResult? originalResult;
    TokenActionOutcome outcome;
    try {
      if (ticket == null ||
          ticket.key != key ||
          !identical(intent.proof.session, session) ||
          !intent.isCurrent) {
        throw const TokenActionRefused();
      }
      reserved = sender.tryReserve(owner);
      if (!reserved) throw const TokenActionRefused();
      final TokenActionProof fresh = await session.prove(intent.standard);
      if (!intent.accepts(fresh)) throw const TokenActionRefused();
      final Token token = fresh.token;
      final AccountBlockTemplate transaction = switch (intent.mode) {
        TokenActionMode.mint => session.mintBlock(
          intent.standard,
          intent.amount,
          Address.parse(intent.receiver!),
        ),
        TokenActionMode.burn => session.burnBlock(
          intent.standard,
          intent.amount,
        ),
        TokenActionMode.transfer => session.transferBlock(
          token,
          Address.parse(intent.receiver!),
        ),
        TokenActionMode.flags => throw const TokenActionRefused(),
      };
      // The sender and SDK may prepare their own copy. The comparison baseline
      // must not be the mutable object handed to them.
      final AccountBlockTemplate expected = AccountBlockTemplate.fromJson(
        transaction.toJson(),
      );
      if (expected.chainIdentifier != session.chainId) {
        throw const TokenActionRefused();
      }
      final Object requestId = Object();
      final String purpose = switch (intent.mode) {
        TokenActionMode.mint => PlasmaPurpose.mintToken.message,
        TokenActionMode.burn => PlasmaPurpose.burnToken.message,
        TokenActionMode.transfer => PlasmaPurpose.transferToken.message,
        TokenActionMode.flags => throw const TokenActionRefused(),
      };
      bool current() => intent.isCurrent && intent.accepts(fresh);
      if (!current()) throw const TokenActionRefused();
      request = sender.trySubmitOwned(
        owner: owner,
        requestId: requestId,
        block: transaction,
        fromAddress: intent.owner,
        reasonForGeneratingPlasma: purpose,
        origin: SendTransactionOrigin.contract,
        canStart: current,
        canPublish: current,
      );
      if (request == null) throw const TokenActionRefused();
      final SendRequestResult result = await request.result;
      originalResult = result;
      final AccountBlockTemplate? block = result.block;
      outcome = TokenActionOutcome(
        intent: intent,
        status:
            result.accepted &&
                block != null &&
                block.address.toString() == intent.owner &&
                block.hash != emptyHash &&
                _sameContract(expected, block)
            ? TokenActionStatus.submitted
            : TokenActionStatus.unknown,
        result: result,
        error: result.error,
        requestId: requestId,
      );
    } on Object catch (error, trace) {
      outcome = TokenActionOutcome(
        intent: intent,
        status: request == null
            ? TokenActionStatus.refused
            : TokenActionStatus.unknown,
        result: originalResult,
        error: originalResult?.error ?? error,
        stackTrace: trace,
        requestId: request?.requestId,
      );
    } finally {
      if (reserved) sender.releaseReservation(owner);
    }
    record.outcome = outcome;
    _journal.originals.add(outcome);
    if (outcome.status == TokenActionStatus.refused &&
        identical(_journal.holds[key], record)) {
      _journal.holds.remove(key);
    }
    _lastOutcome = outcome;
    record.settled.complete(outcome);
    return outcome;
  }
}

String? _originalHash(SendRequestResult? result) {
  try {
    return result?.block?.hash.toString();
  } on Object {
    // An incomplete response remains the original unknown result.
    return null;
  }
}

bool _sameContract(AccountBlockTemplate expected, AccountBlockTemplate block) =>
    expected.blockType == block.blockType &&
    expected.chainIdentifier == block.chainIdentifier &&
    expected.toAddress == block.toAddress &&
    expected.tokenStandard == block.tokenStandard &&
    expected.amount == block.amount &&
    listEquals<int>(expected.data, block.data);
