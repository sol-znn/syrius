import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class TokenTestZenon extends Mock implements Zenon {}

class _TokenTestWs extends Mock implements WsClient {}

/// Synthetic SDK transport. No websocket, wallet, signer or real node exists.
class TokenTestClient implements Client {
  TokenTestClient(this.respond);

  Future<Object?> Function(String method, List<dynamic> parameters) respond;
  final List<(String, List<dynamic>)> requests = <(String, List<dynamic>)>[];

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) {
    final List<dynamic> arguments = List<dynamic>.of(
      parameters as List<dynamic>,
    );
    requests.add((method, arguments));
    return respond(method, arguments);
  }
}

class TokenTestSdk {
  TokenTestSdk(TokenTestClient transport) {
    embedded = EmbeddedApi()..setClient(transport);
    ledger = LedgerApi()..setClient(transport);
    final _TokenTestWs ws = _TokenTestWs();
    when(() => ws.restartedStreamController).thenReturn(restarts);
    when(() => zenon.wsClient).thenReturn(ws);
    when(() => zenon.embedded).thenAnswer((_) => embedded);
    when(() => zenon.ledger).thenAnswer((_) => ledger);
  }

  final TokenTestZenon zenon = TokenTestZenon();
  final StreamController<bool> restarts = StreamController<bool>.broadcast();
  late EmbeddedApi embedded;
  late LedgerApi ledger;

  Future<void> close() => restarts.close();
}

class TokenTestGlobals {
  TokenTestGlobals()
    : _client = app.zenon,
      _selection = kSelectedAddress,
      _node = kCurrentNode,
      _nodeChain = kNodeChainId,
      _chain = getChainIdentifier();

  final Zenon? _client;
  final String? _selection;
  final String? _node;
  final int? _nodeChain;
  final int _chain;

  void install(Zenon client) {
    app.zenon = client;
    kSelectedAddress = emptyAddress.toString();
    kCurrentNode = 'isolated-token-fixture';
    kNodeChainId = 321;
    setChainIdentifier(chainIdentifier: 321);
    WalletContextRevision.invalidate();
  }

  void restore() {
    app.zenon = _client;
    kSelectedAddress = _selection;
    kCurrentNode = _node;
    kNodeChainId = _nodeChain;
    setChainIdentifier(chainIdentifier: _chain);
    WalletContextRevision.invalidate();
  }
}

Token tokenFixture(
  int index, {
  String? name,
  String? symbol,
  Address? owner,
  int decimals = 8,
  BigInt? supply,
}) => Token(
  name ?? 'Fixture token $index',
  symbol ?? 'T$index',
  'example.invalid',
  supply ?? BigInt.from(10).pow(38),
  decimals,
  owner ?? emptyAddress,
  TokenStandard.fromBytes(<int>[
    index & 255,
    (index >> 8) & 255,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]),
  BigInt.parse('1000000000000000000000000000000000000000'),
  true,
  true,
  false,
);

Map<String, dynamic> tokenPage(List<Token> rows, {int? count}) =>
    <String, dynamic>{
      'count': count ?? rows.length,
      'list': rows.map((Token token) => token.toJson()).toList(),
    };

Map<String, dynamic> tokenAccount(
  List<(Token, BigInt)> balances, {
  String? address,
}) => <String, dynamic>{
  'address': address ?? emptyAddress.toString(),
  'accountHeight': 1,
  'balanceInfoMap': <String, dynamic>{
    for (final (Token token, BigInt units) in balances)
      token.tokenStandard.toString(): <String, dynamic>{
        'token': token.toJson(),
        'balance': units.toString(),
      },
  },
};

class TokenTestFavorites implements FavoriteTokensRepository {
  final Set<String> standards = <String>{};
  Completer<void>? pending;
  Object? failure;

  @override
  bool contains(TokenStandard standard) =>
      standards.contains(standard.toString());

  @override
  Future<void> add(TokenStandard standard) async {
    if (pending != null) await pending!.future;
    final Object? originalFailure = failure;
    if (originalFailure != null) {
      Error.throwWithStackTrace(originalFailure, StackTrace.current);
    }
    standards.add(standard.toString());
  }

  @override
  Future<void> remove(TokenStandard standard) async {
    if (pending != null) await pending!.future;
    final Object? originalFailure = failure;
    if (originalFailure != null) {
      Error.throwWithStackTrace(originalFailure, StackTrace.current);
    }
    standards.remove(standard.toString());
  }
}

Future<T> nextTokenState<T>(Stream<T> stream, bool Function(T) predicate) =>
    stream.firstWhere(predicate).timeout(const Duration(seconds: 3));

Future<void> tokenTurns() async {
  for (int turn = 0; turn < 4; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
