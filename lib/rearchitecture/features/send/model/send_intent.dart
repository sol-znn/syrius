import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Optional presentation work after an original result has already settled.
typedef SendResultObserver =
    Future<void> Function(
      SendIntent intent,
      SendRequestResult result,
    );

/// The captured owner's admission check, injectable without wallet material.
class SendSession {
  /// Describes one original session, with no secret or file path exposed.
  const SendSession({required this.isCurrent, this.hardware = false});

  /// False after any captured wallet context leaves, even if it returns.
  final bool Function() isCurrent;

  /// Whether the original wallet requires confirmation on a device.
  final bool hardware;
}

/// The exact transfer presented for one confirmation.
///
/// SDK tokens are mutable. This copies their scalar JSON data before a dialog
/// can yield, and creates a fresh SDK token for the admitted event.
class SendIntent {
  SendIntent._({
    required this.fromAddress,
    required this.toAddress,
    required this.recipientInput,
    required this.amountInput,
    required this.amount,
    required Map<String, dynamic> token,
  }) : _token = Map<String, dynamic>.unmodifiable(token);

  /// Validates plain decimal text without rounding or converting to a double.
  factory SendIntent.capture({
    required String fromAddress,
    required String recipient,
    required String amount,
    required Token token,
  }) {
    final Map<String, dynamic> snapshot = token.toJson();
    final int decimals = snapshot['decimals'] as int;
    final String symbol = snapshot['symbol'] as String;
    final BigInt? units = parseSendAmount(amount, decimals);
    if (units == null || symbol.trim().isEmpty) {
      throw const FormatException('Invalid transfer amount');
    }
    return SendIntent._(
      fromAddress: _address(fromAddress),
      toAddress: _address(recipient),
      recipientInput: recipient,
      amountInput: amount,
      amount: units,
      token: snapshot,
    );
  }

  /// The original sending account.
  final String fromAddress;

  /// The full canonical destination presented for confirmation.
  final String toAddress;

  /// Exact text used to detect a changed draft after the dialog yields.
  final String recipientInput;

  /// Exact text used to detect an edited amount after confirmation opens.
  final String amountInput;

  /// The confirmed amount in smallest units.
  final BigInt amount;

  final Map<String, dynamic> _token;

  /// A single live identity follows this confirmation and its original result.
  final Object requestId = Object();

  /// Confirmed precision, independent of subsequent SDK model mutations.
  int get decimals => _token['decimals'] as int;

  /// Confirmed symbol, independent of subsequent SDK model mutations.
  String get symbol => _token['symbol'] as String;

  /// The exact asset identifier presented to the user.
  String get tokenStandard => _token['tokenStandard'] as String;

  /// Canonical display text with no trailing fractional zeroes.
  String get displayAmount => amount.addDecimals(decimals);

  /// A fresh event contains no reference to a form controller or live token.
  SendTransactionInitiate toEvent() => SendTransactionInitiate(
    fromAddress: fromAddress,
    toAddress: toAddress,
    amount: amount,
    token: Token.fromJson(Map<String, dynamic>.of(_token)),
    requestId: requestId,
  );

  /// Every field the person confirmed must still be the displayed draft.
  bool matches({
    required String fromAddress,
    required String recipient,
    required String amount,
    required Token token,
  }) =>
      fromAddress == this.fromAddress &&
      recipient == recipientInput &&
      amount == amountInput &&
      token.tokenStandard.toString() == tokenStandard &&
      token.decimals == decimals &&
      token.symbol == symbol;

  static String _address(String text) {
    try {
      final Address address = Address.parse(text);
      if (address.hrp == Address.prefix &&
          address.core?.length == Address.coreSize) {
        return address.toString();
      }
    } on Object {
      // The SDK codec throws several unrelated types for malformed text.
    }
    throw const FormatException('Invalid transfer address');
  }
}

final RegExp _plainAmount = RegExp(r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$');

/// Exact positive units within the existing SDK token-supply bound.
BigInt? parseSendAmount(String text, int decimals) {
  if (decimals < 0 ||
      decimals > 255 ||
      _plainAmount.firstMatch(text)?.end != text.length) {
    return null;
  }
  final List<String> parts = text.split('.');
  final String fraction = parts.length == 2 ? parts.last : '';
  if (fraction.length > decimals) return null;
  final String whole = parts.first.replaceFirst(RegExp('^0+'), '');
  final int cap = kBigP255m1.toString().length;
  if (whole.isNotEmpty && whole.length + decimals > cap) return null;
  final String digits = '$whole${fraction.padRight(decimals, '0')}'
      .replaceFirst(RegExp('^0+'), '');
  if (digits.isEmpty || digits.length > cap) return null;
  final BigInt amount = BigInt.parse(digits);
  return amount <= kBigP255m1 ? amount : null;
}
