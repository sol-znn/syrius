import 'dart:async';

import 'package:collection/collection.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Exact decimal input. Excess precision is refused rather than truncated.
BigInt? swapAmount(String value, int decimals) {
  if (decimals < 0 ||
      decimals > 255 ||
      value.length > 1024 ||
      !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(value)) {
    return null;
  }
  final List<String> parts = value.split('.');
  final String fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  return BigInt.parse(parts.first + fraction.padRight(decimals, '0'));
}

/// Formats exact base units for an input without rounding or trailing zeros.
String swapAmountInput(BigInt amount, int decimals) {
  final String digits = amount.toString().padLeft(decimals + 1, '0');
  if (decimals == 0) return digits;
  final String fraction = digits
      .substring(digits.length - decimals)
      .replaceFirst(RegExp(r'0+$'), '');
  final String whole = digits.substring(0, digits.length - decimals);
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

/// Accepts a canonical address only when it is outside captured membership.
bool swapCounterparty(String value, Set<String> members) {
  try {
    return Address.parse(value).toString() == value && !members.contains(value);
  } on Object {
    return false;
  }
}

/// Parses only a canonical nonempty deposit hash, without fuzzy normalization.
Hash? swapDepositId(String value) {
  try {
    final Hash hash = Hash.parse(value);
    return hash != emptyHash && hash.toString() == value ? hash : null;
  } on Object {
    return null;
  }
}

/// Only complete positive account reads become spendable UI choices.
class SwapFunds {
  SwapFunds._(this.address, this.tokens, this.balances);

  /// Exact captured member account whose complete balances were read.
  final String address;

  /// Immutable copied token metadata from that same complete account response.
  final List<Token> tokens;

  /// Immutable exact base-unit balances keyed by token standard.
  final Map<String, BigInt> balances;

  /// Returns a token's exact balance; zero is valid only because the account
  /// catalogue was positively complete before this object was constructed.
  BigInt balance(Token token) =>
      balances[token.tokenStandard.toString()] ?? BigInt.zero;

  /// Requires an owned member and complete matching account facts before any
  /// amount or token choice becomes spendable in the form.
  static Future<SwapFunds> read(SwapActionOrigin origin, String address) async {
    origin.requireCurrent();
    if (!origin.members.contains(address)) {
      throw const SwapActionRefused('signer');
    }
    final AccountInfo account = await origin.readAccount(address);
    origin.requireCurrent();
    final List<BalanceInfoListItem>? items = account.balanceInfoList;
    if (account.address != address ||
        account.blockCount == null ||
        account.blockCount! < 0 ||
        items == null ||
        items.any(
          (BalanceInfoListItem item) =>
              item.token == null ||
              item.balance == null ||
              item.balance! < BigInt.zero ||
              item.token!.decimals < 0 ||
              item.token!.decimals > 255,
        ) ||
        items
                .map(
                  (BalanceInfoListItem item) =>
                      item.token!.tokenStandard.toString(),
                )
                .toSet()
                .length !=
            items.length) {
      throw const SwapActionRefused('balance');
    }
    return SwapFunds._(
      address,
      List<Token>.unmodifiable(
        items.map(
          (BalanceInfoListItem item) => Token.fromJson(item.token!.toJson()),
        ),
      ),
      Map<String, BigInt>.unmodifiable(<String, BigInt>{
        for (final BalanceInfoListItem item in items)
          item.token!.tokenStandard.toString(): item.balance!,
      }),
    );
  }
}

/// Retains the original operation and result after its view departs.
class SwapUiRun {
  /// Invokes once and retains its original Future before observing completion.
  SwapUiRun(Future<SwapActionResult> Function() operation) {
    // Reserve completion before a source can synchronously reenter.
    try {
      original = operation();
    } on Object catch (error, trace) {
      original = Future<SwapActionResult>.error(error, trace);
    }
    unawaited(
      original.then(
        (SwapActionResult value) {
          result = value;
          _completion.complete(value);
        },
        onError: (Object error, StackTrace trace) {
          final SwapActionResult value = SwapActionResult(
            status: SwapActionStatus.unknown,
            error: error,
            stackTrace: trace,
          );
          result = value;
          _completion.complete(value);
        },
      ),
    );
  }
  final Completer<SwapActionResult> _completion = Completer<SwapActionResult>();

  /// Actual admitted action Future, independent of mounted presentation.
  late final Future<SwapActionResult> original;

  /// Original result, or an unknown result retaining an unexpected error.
  SwapActionResult? result;

  /// Stable view-observation Future that never retries or cancels the action.
  Future<SwapActionResult> get completion => _completion.future;
}

/// Public projection of one positive current HTLC response. No secret fields.
class SwapDepositFact {
  SwapDepositFact._({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.amount,
    required this.token,
    required this.expires,
    required this.chainTime,
    required this._hashLock,
    required this._hashType,
  });

  /// Canonical exact deposit identifier from a positive current lookup.
  final String id;

  /// Current time-locked reclaim owner.
  final String sender;

  /// Current hash-locked withdrawal recipient.
  final String recipient;

  /// Exact live amount in base units.
  final BigInt amount;

  /// Copied positive metadata matching the live token standard.
  final Token token;

  /// Exact live contract expiration.
  final int expires;

  /// Positive original-chain timestamp read with this fact.
  final int chainTime;
  final String _hashLock;
  final int _hashType;

  /// Whether this positive live expiration has passed on the original chain.
  bool get expired => expires <= chainTime;

  /// Reads current deposit, matching token metadata and positive chain time.
  /// This public projection alone never authorizes publication.
  static Future<SwapDepositFact> read(
    SwapActionOrigin origin,
    Hash id, {
    HtlcInfo? exact,
  }) async {
    origin.requireCurrent();
    final HtlcInfo? requiredDeposit = exact == null
        ? null
        : HtlcInfo.fromJson(exact.toJson());
    final HtlcInfo value = HtlcInfo.fromJson(
      (await origin.readHtlc(id.toString())).toJson(),
    );
    origin.requireCurrent();
    if (id == emptyHash ||
        value.id != id ||
        value.amount <= BigInt.zero ||
        value.expirationTime <= 0 ||
        value.hashLock.length != 32 ||
        (requiredDeposit != null && !_sameDeposit(value, requiredDeposit))) {
      throw const SwapActionRefused('deposit');
    }
    final Token? loaded = await origin.readToken(
      value.tokenStandard.toString(),
    );
    origin.requireCurrent();
    if (loaded == null ||
        loaded.tokenStandard != value.tokenStandard ||
        loaded.decimals < 0 ||
        loaded.decimals > 255) {
      throw const SwapActionRefused('token');
    }
    final int now = await origin.readChainTime();
    origin.requireCurrent();
    if (now <= 0) throw const SwapActionRefused('chain-time');
    return SwapDepositFact._(
      id: id.toString(),
      sender: value.timeLocked.toString(),
      recipient: value.hashLocked.toString(),
      amount: value.amount,
      token: Token.fromJson(loaded.toJson()),
      expires: value.expirationTime,
      chainTime: now,
      hashLock: FormatUtils.encodeHexString(value.hashLock),
      hashType: value.hashType,
    );
  }
}

bool _sameDeposit(HtlcInfo first, HtlcInfo second) =>
    first.id == second.id &&
    first.timeLocked == second.timeLocked &&
    first.hashLocked == second.hashLocked &&
    first.amount == second.amount &&
    first.tokenStandard == second.tokenStandard &&
    first.expirationTime == second.expirationTime &&
    first.hashType == second.hashType &&
    first.keyMaxSize == second.keyMaxSize &&
    const ListEquality<int>().equals(first.hashLock, second.hashLock);

/// Copies exact original history before asynchronous reads.
HtlcSwap swapOriginalRecord(SwapActionOrigin origin, String id) {
  origin.requireCurrent();
  final List<HtlcSwap> matches = origin
      .readHistory()
      .where((HtlcSwap item) => item.id == id)
      .toList();
  if (matches.length != 1) throw const SwapActionRefused('record');
  final HtlcSwap result = HtlcSwap.fromJson(matches.single.toJson());
  if (result.chainId != origin.chainId ||
      !origin.members.contains(result.selfAddress) ||
      result.type != P2pSwapType.native ||
      result.mode != P2pSwapMode.htlc ||
      result.fromChain != P2pSwapChain.nom ||
      result.toChain != P2pSwapChain.nom ||
      result.fromAmount <= BigInt.zero ||
      result.fromDecimals < 0 ||
      result.fromDecimals > 255 ||
      swapDepositId(result.initialHtlcId) == null) {
    throw const SwapActionRefused('record');
  }
  return result;
}

/// A view may compare a live public deposit with its copied original record.
bool swapFactMatches(
  SwapDepositFact fact,
  HtlcSwap record, {
  required bool own,
}) {
  final bool initial = (record.direction == P2pSwapDirection.outgoing) == own;
  return fact.id == (initial ? record.initialHtlcId : record.counterHtlcId) &&
      fact.sender == (own ? record.selfAddress : record.counterpartyAddress) &&
      fact.recipient ==
          (own ? record.counterpartyAddress : record.selfAddress) &&
      fact.amount == (own ? record.fromAmount : record.toAmount) &&
      fact.token.tokenStandard.toString() ==
          (own ? record.fromTokenStandard : record.toTokenStandard) &&
      fact.token.decimals == (own ? record.fromDecimals : record.toDecimals) &&
      fact.token.symbol == (own ? record.fromSymbol : record.toSymbol) &&
      fact._hashLock == record.hashLock &&
      fact._hashType == record.hashType &&
      fact.expires ==
          (initial
              ? record.initialHtlcExpirationTime
              : record.counterHtlcExpirationTime);
}

/// The original private record is retained only for an explicit engine action.
/// The UI renders positive public facts without serialized recovery data.
class SwapDetailRead {
  SwapDetailRead._(
    this.original,
    this.sending,
    this.receiving,
    this.own,
    this.other,
  );

  /// Copied private record, reserved solely for explicit engine actions.
  final HtlcSwap original;

  /// Positive sending metadata matching the copied original record.
  final Token sending;

  /// Positive receiving metadata, absent until the original standard is known.
  final Token? receiving;

  /// Positive current public sending deposit, or honest unavailability.
  final SwapDepositFact? own;

  /// Positive current public receiving deposit, or honest unavailability.
  final SwapDepositFact? other;

  /// Whether every public own-deposit term matches the copied original record.
  bool get ownMatches =>
      own != null && swapFactMatches(own!, original, own: true);

  /// Whether every public receiving term matches the copied original record.
  bool get otherMatches =>
      other != null && swapFactMatches(other!, original, own: false);

  /// Copies original history first, then reads positive metadata and optional
  /// live deposits on the same source, keeping lookup errors uncertain.
  static Future<SwapDetailRead> read(SwapActionOrigin origin, String id) async {
    final HtlcSwap record = swapOriginalRecord(origin, id);
    final Token? from = await origin.readToken(record.fromTokenStandard);
    origin.requireCurrent();
    if (from == null ||
        from.tokenStandard.toString() != record.fromTokenStandard ||
        from.decimals != record.fromDecimals ||
        from.symbol != record.fromSymbol) {
      throw const SwapActionRefused('token');
    }
    Token? to;
    final String? receivingStandard = record.toTokenStandard;
    if (receivingStandard != null) {
      final Token? loaded = await origin.readToken(receivingStandard);
      origin.requireCurrent();
      if (loaded == null ||
          loaded.tokenStandard.toString() != receivingStandard ||
          loaded.decimals != record.toDecimals ||
          loaded.symbol != record.toSymbol) {
        throw const SwapActionRefused('token');
      }
      to = Token.fromJson(loaded.toJson());
    }
    final bool outgoing = record.direction == P2pSwapDirection.outgoing;
    final String? ownId = outgoing
        ? record.initialHtlcId
        : record.counterHtlcId;
    final String? otherId = outgoing
        ? record.counterHtlcId
        : record.initialHtlcId;
    Future<SwapDepositFact?> positive(String? depositId) async {
      final Hash? hash = depositId == null ? null : swapDepositId(depositId);
      if (hash == null) return null;
      try {
        return await SwapDepositFact.read(origin, hash);
      } on Object {
        origin.requireCurrent();
        // Absence, a failed read and a terminal history label all stay unknown.
        return null;
      }
    }

    final SwapDepositFact? own = await positive(ownId);
    origin.requireCurrent();
    final SwapDepositFact? other = await positive(otherId);
    origin.requireCurrent();
    return SwapDetailRead._(
      record,
      Token.fromJson(from.toJson()),
      to,
      own,
      other,
    );
  }
}
