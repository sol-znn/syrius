import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/model/new_token_data.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_supply.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  test('supply preserves integers above floating point precision', () {
    expect(
      parseTokenCreateSupply('9007199254740993.00000001', 8),
      BigInt.parse('900719925474099300000001'),
    );
    expect(parseTokenCreateSupply('1.000', 3), BigInt.from(1000));
    expect(parseTokenCreateSupply(kBigP255m1.toString(), 0), kBigP255m1);
    expect(
      parseTokenCreateSupply((kBigP255m1 + BigInt.one).toString(), 0),
      isNull,
    );
    for (final String invalid in <String>[
      '',
      '-1',
      '+1',
      '1e3',
      '1,2',
      '.5',
      '1.',
      ' 1',
    ]) {
      expect(parseTokenCreateSupply(invalid, 8), isNull, reason: invalid);
    }
    expect(parseTokenCreateSupply('1.01', 1), isNull);
    expect(parseTokenCreateSupply('1', 19), isNull);
  });

  test('mintability and decimals recompute both exact supply bounds', () {
    final NewTokenData initial = NewTokenData.initial(
      address: emptyAddress.toString(),
    );
    NewTokenData? supply(NewTokenData draft, String total, String maximum) =>
        tokenCreateSupplyDraft(draft: draft, total: total, maximum: maximum);
    expect(supply(initial, '10', '')!.maxSupply, BigInt.from(10));
    expect(supply(initial, '0', ''), isNull);
    final NewTokenData mintable = initial.copyWith(isMintable: true);
    expect(supply(mintable, '10', ''), isNull);
    expect(supply(mintable, '10', '9'), isNull);
    expect(supply(mintable, '0', '1')!.totalSupply, BigInt.zero);
    expect(
      supply(initial.copyWith(decimals: 2), '1.01', '')!.totalSupply,
      BigInt.from(101),
    );
    expect(supply(initial, '1.01', ''), isNull);
  });

  test(
    'unknown, incomplete and foreign accounts never manufacture zero ZNN',
    () {
      final String owner = emptyAddress.toString();
      final AccountInfo account = tokenCreateAccount();
      expect(
        tokenCreateZnnBalance(account, owner),
        tokenZtsIssueFeeInZnn * BigInt.from(2000),
      );
      expect(tokenCreateZnnBalance(account, kQsrCoin.owner.toString()), isNull);
      account.balanceInfoList!.add(
        BalanceInfoListItem(token: kZnnCoin, balance: BigInt.one),
      );
      expect(tokenCreateZnnBalance(account, owner), isNull);
      account.balanceInfoList = <BalanceInfoListItem>[
        BalanceInfoListItem(token: kZnnCoin, balance: -BigInt.one),
      ];
      expect(tokenCreateZnnBalance(account, owner), isNull);
      account.balanceInfoList = null;
      expect(tokenCreateZnnBalance(account, owner), isNull);
      expect(
        tokenCreateZnnBalance(
          AccountInfo(
            address: owner,
            balanceInfoList: const <BalanceInfoListItem>[],
          ),
          owner,
        ),
        isNull,
      );
      expect(
        tokenCreateZnnBalance(
          AccountInfo(
            address: owner,
            blockCount: 0,
            balanceInfoList: const <BalanceInfoListItem>[],
          ),
          owner,
        ),
        BigInt.zero,
      );
    },
  );

  test('the fee and Plasma must both be known and sufficient', () async {
    final TokenCreateFixture fixture = TokenCreateFixture();
    addTearDown(fixture.dispose);
    expect(fixture.preflight.znn, isNull);
    expect(fixture.preflight.plasma, isNull);
    expect(fixture.preflight.sufficient, isFalse);
    expect(await fixture.preflight.refresh(), isTrue);
    expect(fixture.accountReads, 1);
    expect(fixture.plasmaReads, 1);
    fixture.account = tokenCreateAccount(
      balance: tokenZtsIssueFeeInZnn - BigInt.one,
    );
    expect(await fixture.preflight.refresh(), isFalse);
    fixture
      ..account = tokenCreateAccount(balance: tokenZtsIssueFeeInZnn)
      ..plasma = tokenCreatePlasma(kIssueTokenPlasmaAmountNeeded - 1);
    expect(await fixture.preflight.refresh(), isFalse);
    fixture.plasma = tokenCreatePlasma();
    expect(await fixture.preflight.refresh(), isTrue);
  });

  test(
    'inconsistent height, uint256 overflow and invalid metadata stay unknown',
    () {
      final String owner = emptyAddress.toString();
      final AccountInfo emptyHeight = AccountInfo(
        address: owner,
        blockCount: 0,
        balanceInfoList: tokenCreateAccount().balanceInfoList,
      );
      expect(tokenCreateZnnBalance(emptyHeight, owner), isNull);
      expect(
        tokenCreateZnnBalance(
          tokenCreateAccount(balance: BigInt.one << 256),
          owner,
        ),
        isNull,
      );
      expect(
        tokenCreateZnnBalance(
          tokenCreateAccount(balance: kZnnCoin.totalSupply + BigInt.one),
          owner,
        ),
        isNull,
      );
      final Token invalid = Token.fromJson(<String, dynamic>{
        ...kZnnCoin.toJson(),
        'decimals': 256,
      });
      final AccountInfo malformed = AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(token: invalid, balance: BigInt.zero),
        ],
      );
      expect(tokenCreateZnnBalance(malformed, owner), isNull);
    },
  );

  test(
    'a pending or failed refresh revokes previously sufficient facts',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      await fixture.preflight.refresh();
      final Completer<AccountInfo> account = Completer<AccountInfo>();
      fixture.accountRead = () => account.future;
      final Future<bool> pending = fixture.preflight.refresh();
      expect(fixture.preflight.znn, isNull);
      expect(fixture.preflight.ticket, isNull);
      expect(fixture.preflight.sufficient, isFalse);
      account.completeError(StateError('in-memory read failure'));
      expect(await pending, isFalse);
      expect(fixture.preflight.failed, isTrue);
      expect(fixture.preflight.znn, isNull);
      expect(fixture.preflight.plasma, isNull);
    },
  );

  test('newer explicit reads supersede an older deferred completion', () async {
    final TokenCreateFixture fixture = TokenCreateFixture();
    addTearDown(fixture.dispose);
    final Completer<AccountInfo> old = Completer<AccountInfo>();
    fixture.accountRead = () => old.future;
    final Future<bool> first = fixture.preflight.refresh();
    fixture.accountRead = null;
    expect(await fixture.preflight.refresh(), isTrue);
    final Object ticket = fixture.preflight.ticket!;
    old.complete(tokenCreateAccount(balance: BigInt.zero));
    expect(await first, isFalse);
    expect(fixture.preflight.ticket, same(ticket));
    expect(fixture.preflight.sufficient, isTrue);
  });

  test(
    'authority revocation clears facts and refuses late callbacks',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      final Completer<PlasmaInfo> pending = Completer<PlasmaInfo>();
      fixture.plasmaRead = () => pending.future;
      final Future<bool> read = fixture.preflight.refresh();
      fixture.revoke();
      pending.complete(tokenCreatePlasma());
      expect(await read, isFalse);
      expect(fixture.preflight.znn, isNull);
      expect(fixture.preflight.plasma, isNull);
      fixture.authority.value = 0;
      expect(await fixture.preflight.refresh(), isFalse);
      expect(fixture.accountReads, 1);
      expect(fixture.plasmaReads, 1);
    },
  );

  test(
    'closing a presentation suppresses deferred paint and dispatch',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      final Completer<AccountInfo> pending = Completer<AccountInfo>();
      fixture.accountRead = () => pending.future;
      int notifications = 0;
      fixture.preflight.addListener(() => notifications++);
      final Future<bool> read = fixture.preflight.refresh();
      fixture.preflight.closePresentation();
      final int before = notifications;
      pending.complete(tokenCreateAccount());
      expect(await read, isFalse);
      expect(notifications, before);
      expect(fixture.preflight.sufficient, isFalse);
      expect(fixture.preflight.znn, isNull);
    },
  );

  test(
    'disposing pending readers produces no later notification or authority',
    () async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      addTearDown(fixture.dispose);
      final Completer<AccountInfo> pending = Completer<AccountInfo>();
      fixture.accountRead = () => pending.future;
      int notifications = 0;
      fixture.preflight.addListener(() => notifications++);
      final Future<bool> read = fixture.preflight.refresh();
      fixture.dispose();
      final int before = notifications;
      pending.complete(tokenCreateAccount());
      expect(await read, isFalse);
      expect(notifications, before);
      expect(fixture.preflight.isCurrent, isFalse);
      expect(fixture.preflight.ticket, isNull);
    },
  );
}
