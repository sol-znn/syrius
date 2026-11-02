import 'package:znn_sdk_dart/znn_sdk_dart.dart';

final RegExp _decimalAmount = RegExp(
  r'^(?:(?:0|[1-9][0-9]*)(?:\.[0-9]*)?|\.[0-9]+)$',
);
final RegExp _leadingZeroes = RegExp('^0+');
final int _maxUnitDigits = kBigP255m1.toString().length;

/// Reads a positive human amount without floating point or truncation.
///
/// The legacy request stores base units. Rejecting extra decimal places
/// before conversion prevents a request from silently asking for less.
BigInt? parseReceiveRequestAmount(String amount, int decimals) {
  final RegExpMatch? match = _decimalAmount.firstMatch(amount);
  if (decimals < 0 || decimals > 255 || match?.end != amount.length) {
    return null;
  }
  final List<String> parts = amount.split('.');
  final String fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  final String whole = parts.first.isEmpty ? '0' : parts.first;
  if (whole != '0' && whole.length + decimals > _maxUnitDigits) return null;
  // A zero whole part can still represent one unit at 255 decimals. Its
  // fraction is bounded above, so normalization cannot allocate huge input.
  final String digits = '$whole${fraction.padRight(decimals, '0')}'
      .replaceFirst(_leadingZeroes, '');
  if (digits.isEmpty || digits.length > _maxUnitDigits) return null;
  final BigInt units = BigInt.parse(digits);
  return units > BigInt.zero && units <= kBigP255m1 ? units : null;
}

/// Keeps the wallet's existing QR shape and base-unit amount contract.
///
/// An empty optional amount retains the legacy zero sentinel. Invalid
/// nonempty input has no payload, so it cannot become a zero request.
String? receiveRequestData({
  required String address,
  required Token token,
  required String amount,
}) {
  final BigInt? units = amount.isEmpty
      ? BigInt.zero
      : parseReceiveRequestAmount(amount, token.decimals);
  if (address.isEmpty || units == null) return null;
  return '${token.symbol.toLowerCase()}:$address'
      '?zts=${token.tokenStandard}&amount=$units';
}
