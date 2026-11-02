import 'package:zenon_syrius_wallet_flutter/model/new_token_data.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Converts a raw supply without a float, rounding or truncating a fraction.
BigInt? parseTokenCreateSupply(String text, int decimals) {
  if (decimals < 0 ||
      decimals > 18 ||
      text.length > kBigP255m1.toString().length + 20 ||
      !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(text)) {
    return null;
  }
  final List<String> parts = text.split('.');
  final String fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  final BigInt amount = BigInt.parse(
    '${parts[0]}${fraction.padRight(decimals, '0')}',
  );
  return amount <= kBigP255m1 ? amount : null;
}

/// Recomputes both supplies whenever decimals or the mintable option changes.
NewTokenData? tokenCreateSupplyDraft({
  required NewTokenData draft,
  required String total,
  required String maximum,
}) {
  final BigInt? initial = parseTokenCreateSupply(total, draft.decimals);
  final BigInt? max = draft.isMintable
      ? parseTokenCreateSupply(maximum, draft.decimals)
      : initial;
  if (initial == null ||
      max == null ||
      max < kMinTokenTotalMaxSupply ||
      initial < (draft.isMintable ? BigInt.zero : kMinTokenTotalMaxSupply) ||
      initial > max) {
    return null;
  }
  return draft.copyWith(totalSupply: initial, maxSupply: max);
}
