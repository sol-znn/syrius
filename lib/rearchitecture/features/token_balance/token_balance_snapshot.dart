import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/token_metadata.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Exact balances from one complete successful account response.
final class TokenBalanceSnapshot {
  TokenBalanceSnapshot._(this._units, this._tokens);

  /// Rejects unavailable fields, another owner, negative units and
  /// duplicate ZTS.
  factory TokenBalanceSnapshot.fromAccount(
    AccountInfo account,
    String address,
  ) {
    final List<BalanceInfoListItem>? entries = account.balanceInfoList;
    if (account.address != address ||
        account.blockCount == null ||
        account.blockCount! < 0 ||
        entries == null ||
        (account.blockCount == 0 && entries.isNotEmpty)) {
      throw const FormatException('Token balances unavailable');
    }
    final Map<String, BigInt> units = <String, BigInt>{};
    final Map<String, Token> tokens = <String, Token>{};
    for (final BalanceInfoListItem entry in entries) {
      final Token? token = entry.token;
      final BigInt? balance = entry.balance;
      if (token == null ||
          balance == null ||
          balance.isNegative ||
          balance.bitLength > 256 ||
          units.containsKey(token.tokenStandard.toString())) {
        throw const FormatException('Token balances incomplete');
      }
      requireValidTokenMetadata(token);
      if (balance > token.totalSupply) {
        throw const FormatException('Token balance exceeds issued supply');
      }
      final String standard = token.tokenStandard.toString();
      units[standard] = balance;
      tokens[standard] = Token.fromJson(token.toJson());
    }
    return TokenBalanceSnapshot._(
      Map<String, BigInt>.unmodifiable(units),
      Map<String, Token>.unmodifiable(tokens),
    );
  }

  final Map<String, BigInt> _units;
  final Map<String, Token> _tokens;

  /// Missing membership in a complete account establishes actual zero.
  BigInt unitsFor(TokenStandard standard) =>
      _units[standard.toString()] ?? BigInt.zero;

  /// Held rows also carry token metadata when the catalog is unavailable.
  Iterable<Token> get heldTokens => _tokens.values.where(
    (Token token) =>
        isNonNativeToken(token) && unitsFor(token.tokenStandard) > BigInt.zero,
  );

  /// Both native coins are excluded, and a zero balance is not a holding.
  int get heldCount => heldTokens.length;
}

/// Native membership is exact ZTS identity, never a matching symbol or name.
bool isNonNativeToken(Token token) =>
    token.tokenStandard != znnZts && token.tokenStandard != qsrZts;
