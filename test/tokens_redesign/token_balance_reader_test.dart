import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  late TokenTestClient transport;
  late TokenTestSdk sdk;
  late TokenTestGlobals globals;
  late TokenBalanceCubit reader;
  final Token token = tokenFixture(1);

  setUp(() {
    transport = TokenTestClient(
      (_, _) async => tokenAccount(<(Token, BigInt)>[
        (token, BigInt.parse('900719925474099312345678901')),
      ]),
    );
    sdk = TokenTestSdk(transport);
    globals = TokenTestGlobals()..install(sdk.zenon);
    reader = TokenBalanceCubit(
      zenon: sdk.zenon,
      address: emptyAddress.toString(),
    );
  });

  tearDown(() async {
    await reader.close();
    await sdk.close();
    globals.restore();
  });

  Future<TokenBalanceState> refresh() {
    final Future<TokenBalanceState> next = nextTokenState(
      reader.stream,
      (TokenBalanceState state) => state.current != null || state.failed,
    );
    reader.refresh();
    return next;
  }

  test('complete selected account keeps exact large units', () async {
    final TokenBalanceState state = await refresh();
    expect(
      state.current!.unitsFor(token.tokenStandard),
      BigInt.parse('900719925474099312345678901'),
    );
    expect(transport.requests.single.$1, 'ledger.getAccountInfoByAddress');
    expect(transport.requests.single.$2, <String>[emptyAddress.toString()]);
  });

  test('another account and unavailable map never become zero', () async {
    transport.respond = (_, _) async =>
        tokenAccount(<(Token, BigInt)>[], address: tokenAddress.toString());
    final TokenBalanceState wrong = await refresh();
    expect(wrong.failed, isTrue);
    expect(wrong.current, isNull);
    transport.respond = (_, _) async => <String, dynamic>{
      'address': emptyAddress.toString(),
      'accountHeight': 1,
      'balanceInfoMap': null,
    };
    expect((await refresh()).current, isNull);
  });

  test('a complete empty response establishes zero', () async {
    transport.respond = (_, _) async => tokenAccount(<(Token, BigInt)>[]);
    final TokenBalanceState state = await refresh();
    expect(state.current!.heldCount, 0);
    expect(state.current!.unitsFor(token.tokenStandard), BigInt.zero);
  });

  test(
    'malformed RPC numeric metadata is unavailable rather than zero',
    () async {
      for (final int decimals in <int>[-1, 256, 1000000000]) {
        transport.respond = (_, _) async => tokenAccount(<(Token, BigInt)>[
          (tokenFixture(9, decimals: decimals), BigInt.one),
        ]);
        final TokenBalanceState state = await refresh();
        expect(state.failed, isTrue);
        expect(state.current, isNull);
      }
    },
  );

  test(
    'out-of-order account replies cannot overwrite the current read',
    () async {
      final Completer<Object?> old = Completer<Object?>();
      transport.respond = (_, _) => transport.requests.length == 1
          ? old.future
          : Future<Object?>.value(
              tokenAccount(<(Token, BigInt)>[
                (token, BigInt.two),
              ]),
            );
      reader.refresh();
      final TokenBalanceState current = await refresh();
      old.complete(tokenAccount(<(Token, BigInt)>[(token, BigInt.one)]));
      await tokenTurns();
      expect(reader.state, same(current));
      expect(reader.state.current!.unitsFor(token.tokenStandard), BigInt.two);
    },
  );

  test('selection round trip revokes completed and pending facts', () async {
    final TokenBalanceState completed = await refresh();
    final Completer<Object?> old = Completer<Object?>();
    transport.respond = (_, _) => old.future;
    reader.refresh();
    kSelectedAddress = tokenAddress.toString();
    WalletContextRevision.invalidate();
    kSelectedAddress = emptyAddress.toString();
    WalletContextRevision.invalidate();
    old.complete(tokenAccount(<(Token, BigInt)>[(token, BigInt.one)]));
    await tokenTurns();
    expect(completed.current, isNull);
    expect(reader.state.current, isNull);
    expect(reader.state.failed, isFalse);
  });

  test('transport replacement and close revoke a pending response', () async {
    final Completer<Object?> old = Completer<Object?>();
    transport.respond = (_, _) => old.future;
    reader.refresh();
    sdk.ledger.setClient(
      TokenTestClient(
        (_, _) async => throw StateError('must not use replacement transport'),
      ),
    );
    await reader.close();
    old.complete(tokenAccount(<(Token, BigInt)>[(token, BigInt.one)]));
    await tokenTurns();
    expect(reader.state.current, isNull);
    expect(transport.requests, hasLength(1));
  });
}
