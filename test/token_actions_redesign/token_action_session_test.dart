import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

void main() {
  initHydratedStorage();
  late ActionFixture fixture;
  setUp(() => fixture = ActionFixture());
  tearDown(() => fixture.close());

  test(
    'raw decimal conversion preserves exact units above float precision',
    () {
      expect(
        parseTokenActionAmount('9007199254740993.12345678', 8),
        BigInt.parse('900719925474099312345678'),
      );
      expect(parseTokenActionAmount('0.00000001', 8), BigInt.one);
      for (final String invalid in <String>[
        '1,2',
        '-1',
        '1e8',
        '1.000000001',
        '1.',
        '.5',
        ' 1',
      ]) {
        expect(parseTokenActionAmount(invalid, 8), isNull, reason: invalid);
      }
      expect(parseTokenActionAmount('1', 256), isNull);
      expect(parseTokenActionAmount((BigInt.one << 256).toString(), 0), isNull);
    },
  );

  test(
    'proof snapshots resist changes to SDK responses and returned copies',
    () async {
      final TokenActionProof proof = await fixture.publisher.read(
        fixture.token.tokenStandard,
      );
      final Token copy = proof.token..owner = tokenAddress;
      expect(copy.owner, tokenAddress);
      expect(proof.token.owner, emptyAddress);
      final TokenActionIntent intent = await fixture.intent(
        amount: BigInt.from(123),
      );
      fixture.token = actionToken(id: 2);
      expect(intent.standard, proof.token.tokenStandard);
      expect(intent.amount, BigInt.from(123));
    },
  );

  test('fresh exact ZTS and valid numeric metadata are mandatory', () async {
    final TokenStandard standard = fixture.token.tokenStandard;
    fixture.tokenRead = (_) async => null;
    await expectLater(
      fixture.publisher.read(standard),
      throwsA(isA<TokenActionRefused>()),
    );
    fixture.tokenRead = (_) async => actionToken(id: 2);
    await expectLater(
      fixture.publisher.read(standard),
      throwsA(isA<TokenActionRefused>()),
    );
    for (final Token invalid in <Token>[
      actionToken(decimals: -1),
      actionToken(decimals: 256),
      actionToken(supply: -BigInt.one),
      actionToken(supply: BigInt.one << 256),
    ]) {
      fixture.tokenRead = (_) async => invalid;
      await expectLater(
        fixture.publisher.read(standard),
        throwsFormatException,
      );
    }
    expect(fixture.transport.calls, isEmpty);
  });

  test(
    'incomplete and invalid accounts grant no action authority',
    () async {
      final String owner = fixture.session.address;
      for (final AccountInfo invalid in <AccountInfo>[
        AccountInfo(address: owner, blockCount: 1),
        AccountInfo(
          address: owner,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
        AccountInfo(
          address: tokenAddress.toString(),
          blockCount: 1,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
        AccountInfo(
          address: owner,
          blockCount: -1,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
        AccountInfo(
          address: owner,
          blockCount: 0,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: fixture.token, balance: BigInt.one),
          ],
        ),
        AccountInfo(
          address: owner,
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: fixture.token, balance: -BigInt.one),
          ],
        ),
        AccountInfo(
          address: owner,
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: fixture.token, balance: null),
          ],
        ),
        AccountInfo(
          address: owner,
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(
              token: fixture.token,
              balance: fixture.token.totalSupply + BigInt.one,
            ),
          ],
        ),
        AccountInfo(
          address: owner,
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: fixture.token, balance: BigInt.one),
            BalanceInfoListItem(token: fixture.token, balance: BigInt.one),
          ],
        ),
      ]) {
        fixture.accountRead = () async => invalid;
        await expectLater(
          fixture.publisher.read(fixture.token.tokenStandard),
          throwsFormatException,
        );
      }
      fixture.accountRead = () async => AccountInfo(
        address: owner,
        blockCount: 0,
        balanceInfoList: const <BalanceInfoListItem>[],
      );
      expect(
        (await fixture.publisher.read(fixture.token.tokenStandard)).balance,
        BigInt.zero,
      );
    },
  );

  test('account token metadata must agree with exact getByZts', () async {
    final Token other = actionToken(owner: tokenAddress);
    fixture.accountRead = () async => AccountInfo(
      address: fixture.session.address,
      blockCount: 1,
      balanceInfoList: <BalanceInfoListItem>[
        BalanceInfoListItem(token: other, balance: BigInt.one),
      ],
    );
    await expectLater(
      fixture.publisher.read(fixture.token.tokenStandard),
      throwsA(isA<TokenActionRefused>()),
    );
  });

  test(
    'selected holders burn public tokens with their own account permissions',
    () async {
      fixture.token = actionToken(owner: tokenAddress);
      TokenActionProof proof = await fixture.publisher.read(
        fixture.token.tokenStandard,
      );
      expect(proof.permits(TokenActionMode.burn), isTrue);
      expect(proof.permits(TokenActionMode.mint), isFalse);
      expect(proof.permits(TokenActionMode.transfer), isFalse);
      fixture.token = actionToken(owner: tokenAddress, burnable: false);
      proof = await fixture.publisher.read(fixture.token.tokenStandard);
      expect(proof.permits(TokenActionMode.burn), isFalse);
      fixture.token = actionToken(burnable: false);
      proof = await fixture.publisher.read(fixture.token.tokenStandard);
      expect(proof.permits(TokenActionMode.burn), isTrue);
      fixture.balance = BigInt.zero;
      proof = await fixture.publisher.read(fixture.token.tokenStandard);
      expect(proof.permits(TokenActionMode.burn), isFalse);
    },
  );

  test('shared API rebind cannot redirect a delayed original proof', () async {
    final Completer<Object?> pending = Completer<Object?>();
    final _Client original = _Client(
      (String method) => pending.future,
    );
    final _Client replacement = _Client(
      (_) async => throw StateError('Replacement must not run'),
    );
    final TokenApi tokens = TokenApi()..setClient(original);
    final LedgerApi ledger = LedgerApi()..setClient(original);
    final TokenActionSession session = TokenActionSession.boundApis(
      address: emptyAddress.toString(),
      chainId: 321,
      tokenSource: tokens,
      ledgerSource: ledger,
      isCurrent: () => true,
    );
    final Future<TokenActionProof> proof = session.prove(
      fixture.token.tokenStandard,
    );
    final Future<void> refused = expectLater(
      proof,
      throwsA(isA<TokenActionRefused>()),
    );
    tokens.setClient(replacement);
    ledger.setClient(replacement);
    pending.complete(fixture.token.toJson());
    await refused;
    expect(original.methods, <String>['embedded.token.getByZts']);
    expect(replacement.methods, isEmpty);
    expect(session.readAccount, throwsA(isA<TokenActionRefused>()));
    tokens.setClient(original);
    ledger.setClient(original);
    expect(session.isCurrent, isFalse);
  });

  test('revision changes permanently revoke the bound source', () {
    final _Client client = _Client(
      (_) async => throw StateError('No RPC expected'),
    );
    final TokenApi tokens = TokenApi()..setClient(client);
    final LedgerApi ledger = LedgerApi()..setClient(client);
    int revision = 0;
    final int captured = revision;
    final TokenActionSession session = TokenActionSession.boundApis(
      address: emptyAddress.toString(),
      chainId: 321,
      tokenSource: tokens,
      ledgerSource: ledger,
      isCurrent: () => revision == captured,
    );
    revision += 2;
    expect(session.isCurrent, isFalse);
    expect(
      () => session.mintBlock(
        fixture.token.tokenStandard,
        BigInt.one,
        emptyAddress,
      ),
      throwsA(isA<TokenActionRefused>()),
    );
    expect(client.methods, isEmpty);
  });

  test(
    'same websocket client with a different URL is permanently revoked',
    () async {
      final _Ws client = _Ws()..url = 'ws://fixture.invalid/original';
      try {
        final TokenActionSession session = TokenActionSession.boundApis(
          address: emptyAddress.toString(),
          chainId: 321,
          tokenSource: TokenApi()..setClient(client),
          ledgerSource: LedgerApi()..setClient(client),
          isCurrent: () => true,
        );
        client.url = 'ws://fixture.invalid/replacement';
        expect(session.isCurrent, isFalse);
        client.url = 'ws://fixture.invalid/original';
        expect(session.isCurrent, isFalse);
        expect(
          () => session.readToken(fixture.token.tokenStandard),
          throwsA(isA<TokenActionRefused>()),
        );
        expect(client.calls, 0);
      } finally {
        await client.restartedStreamController.close();
      }
    },
  );
}

class _Client extends Client {
  _Client(this.reply);
  final Future<Object?> Function(String) reply;
  final List<String> methods = <String>[];

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) {
    methods.add(method);
    return reply(method);
  }
}

class _Ws extends WsClient {
  int calls = 0;
  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    calls++;
    throw StateError('No fixture socket may dispatch');
  }
}
