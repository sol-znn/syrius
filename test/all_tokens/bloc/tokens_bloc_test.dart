import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/all_tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../tokens_redesign/support.dart';

void main() {
  initHydratedStorage();
  late TokenTestClient transport;
  late TokenTestSdk sdk;
  late TokenTestGlobals globals;
  late AllTokensBloc bloc;
  final Token token = tokenFixture(1);

  setUp(() {
    transport = TokenTestClient((_, _) async => tokenPage(<Token>[token]));
    sdk = TokenTestSdk(transport);
    globals = TokenTestGlobals()..install(sdk.zenon);
    bloc = AllTokensBloc(zenon: sdk.zenon);
  });

  tearDown(() async {
    await bloc.close();
    await sdk.close();
    globals.restore();
  });

  Future<AllTokensState> fetch() {
    final Future<AllTokensState> result = nextTokenState(
      bloc.stream,
      (AllTokensState state) => state is! AllTokensInitial,
    );
    bloc.add(const AllTokensRequested());
    return result;
  }

  test(
    'starts unknown and a complete response establishes current facts',
    () async {
      expect(bloc.state, const AllTokensInitial());
      final AllTokensPopulated result = await fetch() as AllTokensPopulated;
      expect(result.data.single.tokenStandard, token.tokenStandard);
      expect(result.isCurrent, isTrue);
      expect(transport.requests.single.$1, 'embedded.token.getAll');
      expect(transport.requests.single.$2, <int>[0, rpcMaxPageSize]);
    },
  );

  test('success variants serialize but hydration has no live authority', () {
    final AllTokensState decoded = AllTokensState.fromJson(
      AllTokensPopulated(data: <Token>[token]).toJson(),
    );
    expect(decoded, isA<AllTokensPopulated>());
    expect((decoded as AllTokensPopulated).isCurrent, isFalse);
    expect(bloc.fromJson(decoded.toJson()), isNull);
    expect(
      AllTokensState.fromJson(const AllTokensInitial().toJson()),
      const AllTokensInitial(),
    );
    expect(
      AllTokensState.fromJson(
        AllTokensFailure(exception: FailureException()).toJson(),
      ),
      isA<AllTokensFailure>(),
    );
  });

  test(
    'every unique later page is included before declaring completeness',
    () async {
      final List<Token> first = <Token>[
        for (int index = 1; index <= rpcMaxPageSize; index++)
          tokenFixture(index),
      ];
      final Token later = tokenFixture(rpcMaxPageSize + 1);
      transport.respond = (_, List<dynamic> arguments) async =>
          arguments[0] == 0
          ? tokenPage(first, count: rpcMaxPageSize + 1)
          : tokenPage(<Token>[later], count: rpcMaxPageSize + 1);
      final AllTokensPopulated result = await fetch() as AllTokensPopulated;
      expect(result.data, hasLength(rpcMaxPageSize + 1));
      expect(result.data.last.tokenStandard, later.tokenStandard);
      expect(
        transport.requests.map(((String, List<dynamic>) call) => call.$2[0]),
        <int>[0, 1],
      );
    },
  );

  test('complete actual zero is distinct from unavailable rows', () async {
    transport.respond = (_, _) async => tokenPage(<Token>[]);
    final AllTokensPopulated result = await fetch() as AllTokensPopulated;
    expect(result.data, isEmpty);
    expect(result.isCurrent, isTrue);
  });

  final Map<String, Map<String, dynamic>> incomplete =
      <String, Map<String, dynamic>>{
        'null rows': <String, dynamic>{'count': 0, 'list': null},
        'null count': <String, dynamic>{'count': null, 'list': <dynamic>[]},
        'negative count': <String, dynamic>{'count': -1, 'list': <dynamic>[]},
        'premature short page': tokenPage(<Token>[token], count: 2),
        'duplicate exact ZTS': tokenPage(<Token>[token, token]),
        'rows exceed count': tokenPage(<Token>[token], count: 0),
      };
  for (final MapEntry<String, Map<String, dynamic>> fixture
      in incomplete.entries) {
    test('${fixture.key} stays unavailable', () async {
      transport.respond = (_, _) async => fixture.value;
      expect(await fetch(), isA<AllTokensFailure>());
    });
  }

  final Map<String, void Function(Token)> invalidMetadata =
      <String, void Function(Token)>{
        'negative decimals': (Token token) => token.decimals = -1,
        'unbounded decimals': (Token token) => token.decimals = 1000000000,
        'negative supply': (Token token) => token.totalSupply = -BigInt.one,
        'negative maximum': (Token token) => token.maxSupply = -BigInt.one,
        'oversized supply': (Token token) =>
            token.totalSupply = BigInt.one << 256,
        'oversized maximum': (Token token) =>
            token.maxSupply = BigInt.one << 256,
        'impossible supply': (Token token) =>
            token.totalSupply = token.maxSupply + BigInt.one,
      };
  for (final MapEntry<String, void Function(Token)> invalid
      in invalidMetadata.entries) {
    test('${invalid.key} makes catalog unavailable', () async {
      final Token malformed = tokenFixture(7);
      invalid.value(malformed);
      transport.respond = (_, _) async => tokenPage(<Token>[malformed]);
      expect(await fetch(), isA<AllTokensFailure>());
    });
  }

  test(
    'a changed total between pages cannot establish an owner count',
    () async {
      final List<Token> first = <Token>[
        for (int index = 1; index <= rpcMaxPageSize; index++)
          tokenFixture(index),
      ];
      transport.respond = (_, List<dynamic> arguments) async =>
          arguments[0] == 0
          ? tokenPage(first, count: rpcMaxPageSize + 1)
          : tokenPage(<Token>[
              tokenFixture(rpcMaxPageSize + 1),
            ], count: rpcMaxPageSize + 2);
      expect(await fetch(), isA<AllTokensFailure>());
    },
  );

  test(
    'a later page failure preserves unavailable rather than a partial catalog',
    () async {
      transport.respond = (_, List<dynamic> arguments) async {
        if (arguments[0] == 1) throw StateError('isolated failure');
        return tokenPage(<Token>[
          for (int index = 1; index <= rpcMaxPageSize; index++)
            tokenFixture(index),
        ], count: rpcMaxPageSize + 1);
      };
      expect(await fetch(), isA<AllTokensFailure>());
    },
  );

  test('new request wins over a late older success and failure', () async {
    final Completer<Object?> first = Completer<Object?>();
    final Completer<Object?> second = Completer<Object?>();
    transport.respond = (_, _) =>
        transport.requests.length == 1 ? first.future : second.future;
    bloc
      ..add(const AllTokensRequested())
      ..add(const AllTokensRequested());
    final Future<AllTokensState> result = nextTokenState(
      bloc.stream,
      (AllTokensState state) => state is AllTokensPopulated,
    );
    second.complete(tokenPage(<Token>[tokenFixture(2)]));
    final AllTokensPopulated current = await result as AllTokensPopulated;
    first.completeError(StateError('late failure'));
    await tokenTurns();
    expect(bloc.state, same(current));
    expect(current.data.single.symbol, 'T2');
  });

  test(
    'node and chain ABA revoke the original pending and completed reads',
    () async {
      final AllTokensPopulated completed = await fetch() as AllTokensPopulated;
      final Completer<Object?> pending = Completer<Object?>();
      transport.respond = (_, _) => pending.future;
      bloc.add(const AllTokensRequested());
      kCurrentNode = 'another-isolated-node';
      setChainIdentifier();
      WalletContextRevision.invalidate();
      kCurrentNode = 'isolated-token-fixture';
      setChainIdentifier(chainIdentifier: 321);
      WalletContextRevision.invalidate();
      pending.complete(tokenPage(<Token>[tokenFixture(3)]));
      await tokenTurns();
      expect(bloc.state, const AllTokensInitial());
      expect(completed.isCurrent, isFalse);
    },
  );

  test('rebinding the SDK transport refuses another catalog page', () async {
    final Completer<Object?> pending = Completer<Object?>();
    transport.respond = (_, _) => pending.future;
    bloc.add(const AllTokensRequested());
    sdk.embedded.token.setClient(
      TokenTestClient(
        (_, _) async =>
            throw StateError('replacement must not receive old pages'),
      ),
    );
    pending.complete(
      tokenPage(<Token>[
        for (int index = 1; index <= rpcMaxPageSize; index++)
          tokenFixture(index),
      ], count: rpcMaxPageSize + 1),
    );
    await tokenTurns();
    expect(transport.requests, hasLength(1));
    expect(bloc.state, const AllTokensInitial());
  });

  test(
    'an old SDK owner cannot start reading after global client replacement',
    () async {
      app.zenon = TokenTestZenon();
      bloc.add(const AllTokensRequested());
      await tokenTurns();
      expect(transport.requests, isEmpty);
      expect(bloc.state, const AllTokensInitial());
    },
  );

  test('close revokes an in-flight reply without waiting for a node', () async {
    final Completer<Object?> pending = Completer<Object?>();
    transport.respond = (_, _) => pending.future;
    bloc.add(const AllTokensRequested());
    await bloc.close();
    pending.complete(tokenPage(<Token>[token]));
    await tokenTurns();
    expect(bloc.isClosed, isTrue);
    expect(bloc.state, const AllTokensInitial());
  });
}
