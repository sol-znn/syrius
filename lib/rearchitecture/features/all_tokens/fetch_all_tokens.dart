import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/token_metadata.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Reads a complete catalog. A missing page cannot establish an empty catalog.
Future<List<Token>> fetchAllTokens({
  required Zenon zenon,
  TokenApi? tokenApi,
  bool Function()? isCurrent,
}) async {
  final TokenApi api = tokenApi ?? zenon.embedded.token;
  final List<Token> tokens = <Token>[];
  final Set<String> standards = <String>{};
  int? expectedCount;
  int pageIndex = 0;

  while (true) {
    if (isCurrent != null && !isCurrent()) {
      throw const FormatException('Token catalog read superseded');
    }
    final TokenList result = await api.getAll(
      pageIndex: pageIndex,
      // Keep the completeness check aligned with the requested page size.
      // ignore: avoid_redundant_argument_values
      pageSize: rpcMaxPageSize,
    );
    if (isCurrent != null && !isCurrent()) {
      throw const FormatException('Token catalog read superseded');
    }
    final int? count = result.count;
    final List<Token>? page = result.list;
    if (count == null ||
        count < 0 ||
        page == null ||
        page.length > rpcMaxPageSize ||
        (expectedCount != null && count != expectedCount)) {
      throw const FormatException('Token catalog unavailable');
    }
    expectedCount = count;
    for (final Token token in page) {
      requireValidTokenMetadata(token);
      if (!standards.add(token.tokenStandard.toString())) {
        throw const FormatException('Token catalog contains duplicate ZTS');
      }
      // The SDK's Token is mutable. Retain the fields returned by this read.
      tokens.add(Token.fromJson(token.toJson()));
    }
    if (tokens.length > count ||
        (tokens.length < count && page.length < rpcMaxPageSize)) {
      throw const FormatException('Token catalog incomplete');
    }
    if (tokens.length == count) return List<Token>.unmodifiable(tokens);
    pageIndex++;
  }
}
