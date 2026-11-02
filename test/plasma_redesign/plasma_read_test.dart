import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_stats/widgets/plasma_level.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

void main() {
  initHydratedStorage();

  test('decimal QSR parsing preserves integers above double precision', () {
    expect(
      parsePlasmaQsr('9007199254740993.00000001'),
      BigInt.parse('900719925474099300000001'),
    );
    expect(parsePlasmaQsr('10.5'), BigInt.from(1050000000));
    expect(parsePlasmaQsr('10'), BigInt.from(1000000000));
    expect(parsePlasmaQsr('0.00000001'), BigInt.one);
    for (final String value in <String>[
      '',
      '-10',
      '+10',
      '1e2',
      '10,5',
      '10.000000001',
      '10.',
      ' 10',
      '.5',
    ]) {
      expect(parsePlasmaQsr(value), isNull, reason: value);
    }
  });

  test(
    'unknown balances differ from a complete successful empty account',
    () {
      final String address = emptyAddress.toString();
      final Map<String, AccountInfo> accounts = <String, AccountInfo>{
        address: AccountInfo(
          address: address,
          blockCount: 0,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
      };
      for (final MultipleBalanceStatus status in <MultipleBalanceStatus>[
        MultipleBalanceStatus.initial,
        MultipleBalanceStatus.loading,
        MultipleBalanceStatus.failure,
      ]) {
        expect(
          plasmaAvailableQsr(
            MultipleBalanceState(status: status, data: accounts),
            address,
          ),
          isNull,
        );
      }
      expect(
        plasmaAvailableQsr(
          MultipleBalanceState(
            status: MultipleBalanceStatus.success,
            data: accounts,
          ),
          address,
        ),
        BigInt.zero,
      );
    },
  );

  test(
    'Plasma math keeps the full raw integer and refuses saturated displays',
    () {
      final BigInt huge = BigInt.parse('900719925474099300000001');
      expect(
        plasmaForQsrExact(huge, coinDecimals),
        huge * BigInt.from(2100) ~/ BigInt.from(100000000),
      );
      expect(plasmaForQsr(BigInt.from(1000000001), coinDecimals), 21000);
      expect(
        () => plasmaForQsr(BigInt.one << 100, coinDecimals),
        throwsRangeError,
      );
    },
  );

  test(
    'incomplete, foreign, duplicate and negative account balances are refused',
    () {
      final String owner = emptyAddress.toString();
      final BigInt huge = BigInt.parse('900719925474099300000001');
      final AccountInfo account = AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(token: kQsrCoin, balance: huge),
        ],
      );
      expect(plasmaQsrFromAccount(account, owner), huge);
      expect(plasmaQsrFromAccount(account, kZnnCoin.owner.toString()), isNull);
      account.balanceInfoList!.add(
        BalanceInfoListItem(token: kQsrCoin, balance: huge),
      );
      expect(plasmaQsrFromAccount(account, owner), isNull);
      account.balanceInfoList = <BalanceInfoListItem>[
        BalanceInfoListItem(token: kQsrCoin, balance: -BigInt.one),
      ];
      expect(plasmaQsrFromAccount(account, owner), isNull);
      account.balanceInfoList = null;
      expect(plasmaQsrFromAccount(account, owner), isNull);
    },
  );

  test(
    'first page retains the complete SDK aggregate',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.owner.load(fixture.session());
      final PlasmaOwnerRead read = fixture.owner.read!;
      expect(read.entries.length, 2);
      expect(read.count, 3);
      expect(read.total, BigInt.from(600000000));
      expect(
        read.entries.fold<BigInt>(
          BigInt.zero,
          (BigInt sum, PlasmaFusion row) => sum + row.amount,
        ),
        BigInt.from(300000000),
      );
      expect(read.hasMore, isTrue);
      await fixture.owner.loadMore();
      expect(
        fixture.owner.read!.entries.map((PlasmaFusion e) => e.hash),
        <String>[plasmaTestHash(1), plasmaTestHash(2), plasmaTestHash(3)],
      );
      expect(fixture.owner.read!.hasMore, isFalse);
      expect(fixture.owner.read!.total, read.total);
    },
  );

  test('successful complete zero has an explicit read and aggregate', () async {
    final PlasmaFixture fixture = PlasmaFixture()..rows = <FusionEntry>[];
    addTearDown(fixture.close);
    await fixture.loadAll();
    expect(fixture.owner.status, PlasmaOwnerStatus.success);
    expect(fixture.owner.read!.count, 0);
    expect(fixture.owner.read!.total, BigInt.zero);
    expect(fixture.owner.read!.entries, isEmpty);
  });

  test(
    'a superseded first page cannot replace a newer completed owner read',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      final Completer<FusionEntryList> old = Completer<FusionEntryList>();
      fixture.fetch = (_, _) => old.future;
      final Future<void> first = fixture.owner.load(fixture.session());
      fixture.fetch = (_, _) async =>
          plasmaTestPage(<FusionEntry>[plasmaTestEntry(9)]);
      await fixture.owner.load(fixture.session());
      final Object ticket = fixture.owner.read!.ticket;
      old.complete(plasmaTestPage(<FusionEntry>[plasmaTestEntry(1)]));
      await first;
      expect(fixture.owner.read!.ticket, same(ticket));
      expect(fixture.owner.read!.entries.single.hash, plasmaTestHash(9));
    },
  );

  test(
    'scroll callbacks coalesce and reject changing page aggregates',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.owner.load(fixture.session());
      final Completer<FusionEntryList> next = Completer<FusionEntryList>();
      fixture.fetch = (_, _) => next.future;
      final Future<void> first = fixture.owner.loadMore();
      await fixture.owner.loadMore();
      expect(fixture.pages, <(int, int)>[(0, 2), (1, 2)]);
      next.complete(
        plasmaTestPage(
          <FusionEntry>[plasmaTestEntry(3)],
          count: 3,
          total: BigInt.from(700000000),
        ),
      );
      await first;
      expect(fixture.owner.status, PlasmaOwnerStatus.failure);
      expect(fixture.owner.read, isNull);
    },
  );

  test(
    'overlapping page hashes are refused without appending a duplicate',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.owner.load(fixture.session());
      fixture.fetch = (_, _) async => plasmaTestPage(
        <FusionEntry>[plasmaTestEntry(2)],
        count: 3,
        total: BigInt.from(600000000),
      );
      await fixture.owner.loadMore();
      expect(fixture.owner.status, PlasmaOwnerStatus.failure);
      expect(fixture.owner.read, isNull);
    },
  );

  test(
    'context round trips and observed revocation cannot revive a session',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      final PlasmaSession session = fixture.session();
      await fixture.owner.load(session);
      fixture.revision += 2;
      expect(session.isCurrent, isFalse);
      fixture.revision = 0;
      expect(session.isCurrent, isFalse);
      expect(fixture.owner.read, isNull);
    },
  );

  test('mutable SDK fields cannot change a completed row snapshot', () async {
    final PlasmaFixture fixture = PlasmaFixture();
    addTearDown(fixture.close);
    final FusionEntryList response = plasmaTestPage(<FusionEntry>[
      plasmaTestEntry(1),
    ]);
    fixture.fetch = (_, _) async => response;
    await fixture.owner.load(fixture.session());
    response.list.single
      ..id = Hash.parse(plasmaTestHash(9))
      ..qsrAmount = BigInt.from(999)
      ..expirationHeight = 100;
    final PlasmaFusion entry = fixture.owner.read!.entries.single;
    expect(entry.hash, plasmaTestHash(1));
    expect(entry.amount, BigInt.from(100000000));
    expect(entry.expirationHeight, 10);
  });
}
