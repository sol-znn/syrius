import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/search_token/bloc/search_token_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../tokens_redesign/support.dart';

void main() {
  late TokenTestClient transport;
  late TokenTestSdk sdk;
  late TokenTestGlobals globals;
  late SearchTokenBloc bloc;
  late List<Token> tokens;

  setUp(() {
    tokens = <Token>[
      tokenFixture(1, name: 'Alpha token', symbol: 'ALPHA'),
      tokenFixture(2, name: 'Beta token', symbol: 'BETA', owner: tokenAddress),
    ];
    transport = TokenTestClient((_, _) async => tokenPage(tokens));
    sdk = TokenTestSdk(transport);
    globals = TokenTestGlobals()..install(sdk.zenon);
    bloc = SearchTokenBloc(zenon: sdk.zenon, debounceDuration: Duration.zero);
  });

  tearDown(() async {
    await bloc.close();
    await sdk.close();
    globals.restore();
  });

  Future<SearchTokenPopulated> search(
    String query, {
    bool refresh = false,
  }) async {
    final Future<SearchTokenState> result = nextTokenState(
      bloc.stream,
      (SearchTokenState state) =>
          state is SearchTokenPopulated && state.query == query,
    );
    bloc.add(SearchTokenRequested(query: query, refresh: refresh));
    return await result as SearchTokenPopulated;
  }

  test('initial and empty queries have no catalog RPC', () async {
    expect(bloc.state, const SearchTokenInitial());
    bloc.add(const SearchTokenRequested(query: '  '));
    await tokenTurns();
    expect(bloc.state, const SearchTokenInitial());
    expect(transport.requests, isEmpty);
  });

  test(
    'search matches name, symbol, exact owner text and ZTS case-insensitively',
    () async {
      expect(
        (await search('alpha')).tokens.single.tokenStandard,
        tokens[0].tokenStandard,
      );
      expect(
        (await search('BETA TOKEN')).tokens.single.tokenStandard,
        tokens[1].tokenStandard,
      );
      expect(
        (await search(
          tokenAddress.toString().toUpperCase(),
        )).tokens.single.symbol,
        'BETA',
      );
      expect(
        (await search(
          tokens[0].tokenStandard.toString().toUpperCase(),
        )).tokens.single.symbol,
        'ALPHA',
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'both native coins are excluded without excluding a same-symbol token',
    () async {
      tokens = <Token>[
        Token.fromJson(kZnnCoin.toJson()),
        Token.fromJson(kQsrCoin.toJson()),
        tokenFixture(3, name: 'Native-looking name', symbol: 'ZNN'),
      ];
      final SearchTokenPopulated result = await search('znn');
      expect(result.tokens, hasLength(1));
      expect(result.tokens.single.tokenStandard, tokens.last.tokenStandard);
    },
  );

  test('later catalog pages are searched together', () async {
    final Token later = tokenFixture(rpcMaxPageSize + 1, symbol: 'LATER');
    transport.respond = (_, List<dynamic> arguments) async => arguments[0] == 0
        ? tokenPage(<Token>[
            for (int i = 1; i <= rpcMaxPageSize; i++) tokenFixture(i),
          ], count: rpcMaxPageSize + 1)
        : tokenPage(<Token>[later], count: rpcMaxPageSize + 1);
    final SearchTokenPopulated result = await search('later');
    expect(result.tokens.single.tokenStandard, later.tokenStandard);
    expect(transport.requests, hasLength(2));
  });

  test(
    'no match is a complete empty result, while unavailable rows fail',
    () async {
      expect((await search('absent')).tokens, isEmpty);
      transport.respond = (_, _) async => <String, dynamic>{
        'count': 0,
        'list': null,
      };
      final Future<SearchTokenState> failure = nextTokenState(
        bloc.stream,
        (SearchTokenState state) => state is SearchTokenFailure,
      );
      bloc.add(const SearchTokenRequested(query: 'alpha', refresh: true));
      expect(await failure, isA<SearchTokenFailure>());
    },
  );

  test('debounced simultaneous inputs only request the latest query', () async {
    final Future<SearchTokenState> result = nextTokenState(
      bloc.stream,
      (SearchTokenState state) => state is SearchTokenPopulated,
    );
    bloc
      ..add(const SearchTokenRequested(query: 'alpha'))
      ..add(const SearchTokenRequested(query: 'beta'));
    expect((await result as SearchTokenPopulated).query, 'beta');
    expect(transport.requests, hasLength(1));
  });

  test(
    'refresh supersedes an older result before its delayed completion',
    () async {
      final Completer<Object?> old = Completer<Object?>();
      final Completer<void> started = Completer<void>();
      transport.respond = (_, _) {
        if (!started.isCompleted) {
          started.complete();
          return old.future;
        }
        return Future<Object?>.value(tokenPage(tokens));
      };
      bloc.add(const SearchTokenRequested(query: 'alpha'));
      await started.future.timeout(const Duration(seconds: 3));
      final SearchTokenPopulated current = await search('beta', refresh: true);
      old.complete(tokenPage(<Token>[tokens.first]));
      await tokenTurns();
      expect(bloc.state, same(current));
      expect(current.tokens.single.symbol, 'BETA');
    },
  );

  test('a node ABA cannot reuse an earlier complete catalog cache', () async {
    await search('alpha');
    kCurrentNode = 'another-isolated-node';
    WalletContextRevision.invalidate();
    kCurrentNode = 'isolated-token-fixture';
    WalletContextRevision.invalidate();
    tokens = <Token>[tokenFixture(3, symbol: 'BETA')];
    expect(
      (await search('beta')).tokens.single.tokenStandard,
      tokens.single.tokenStandard,
    );
    expect(transport.requests, hasLength(2));
  });
}
