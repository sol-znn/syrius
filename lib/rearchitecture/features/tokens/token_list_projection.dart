import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/controller/tokens_page_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One stable projection. Missing account or catalog facts stay unavailable.
final class TokenListProjection {
  /// Combines exact ZTS keys without moving favorites above unrelated rows.
  TokenListProjection({
    required List<Token>? catalog,
    required TokenBalanceSnapshot? balances,
    required Set<String> favorites,
    required TokensFilter filter,
    required String query,
  }) : rows = _project(catalog, balances, favorites, filter, query);

  /// Null means the selected filter's required source is unavailable.
  final List<Token>? rows;

  static List<Token>? _project(
    List<Token>? catalog,
    TokenBalanceSnapshot? balances,
    Set<String> favorites,
    TokensFilter filter,
    String query,
  ) {
    if (filter == TokensFilter.held && balances == null) return null;
    if (filter != TokensFilter.held && catalog == null) return null;
    final Map<String, Token> source = <String, Token>{
      for (final Token token in balances?.heldTokens ?? <Token>[])
        token.tokenStandard.toString(): token,
      for (final Token token in catalog ?? <Token>[])
        token.tokenStandard.toString(): token,
    };
    final String normalized = query.trim().toLowerCase();
    return List<Token>.unmodifiable(
      source.values.where((Token token) {
        if (!isNonNativeToken(token)) return false;
        final String standard = token.tokenStandard.toString();
        if (filter == TokensFilter.held &&
            balances!.unitsFor(token.tokenStandard) <= BigInt.zero) {
          return false;
        }
        if (filter == TokensFilter.favorites && !favorites.contains(standard)) {
          return false;
        }
        return normalized.isEmpty || tokenMatchesQuery(token, normalized);
      }),
    );
  }
}

/// Names, symbols and owners are searchable; ZTS membership remains exact.
bool tokenMatchesQuery(Token token, String normalizedQuery) =>
    token.name.toLowerCase().contains(normalizedQuery) ||
    token.symbol.toLowerCase().contains(normalizedQuery) ||
    token.owner.toString().toLowerCase().contains(normalizedQuery) ||
    token.tokenStandard.toString().toLowerCase().contains(normalizedQuery);

/// Only a complete live catalog can establish how many tokens an owner issued.
int? issuedTokenCount(List<Token>? catalog, String? address) =>
    catalog == null || address == null
    ? null
    : catalog
          .where(
            (Token token) =>
                isNonNativeToken(token) && token.owner.toString() == address,
          )
          .length;
