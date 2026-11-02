import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

UncollectedReward _reward(int znn, int qsr) => UncollectedReward.fromJson(
  <String, dynamic>{
    'address': 'z1qq9n7fpaqd8lpcljandzmx4xtku9w4ftwyg0mq',
    'znnAmount': '$znn',
    'qsrAmount': '$qsr',
  },
);

HomeSnapshot _snapshot({int plasma = 84000, int znn = 1}) => HomeSnapshot(
  znn: BigInt.from(znn),
  qsr: BigInt.zero,
  tokens: const <BalanceInfoListItem>[],
  currentPlasma: plasma,
  maxPlasma: 100000,
  fusedQsr: BigInt.zero,
  rewards: <String, UncollectedReward>{
    'Delegation': _reward(5, 0),
    'Sentinel': _reward(0, 0),
    'Staking': _reward(0, 7),
  },
);

void main() {
  group('HomeCubit', () {
    test('starts loading, then holds the snapshot', () async {
      final HomeCubit cubit = HomeCubit(read: () async => _snapshot());
      expect(cubit.state.status, HomeStatus.loading);
      await cubit.refresh();
      expect(cubit.state.status, HomeStatus.ready);
      expect(cubit.state.snapshot, _snapshot());
      await cubit.close();
    });

    test('keeps the last snapshot through a failed read', () async {
      int calls = 0;
      final HomeCubit cubit = HomeCubit(
        read: () async {
          calls++;
          if (calls > 1) throw StateError('node down');
          return _snapshot();
        },
      );
      await cubit.refresh();
      await cubit.refresh();
      expect(cubit.state.status, HomeStatus.failed);
      expect(cubit.state.snapshot, _snapshot());
      await cubit.close();
    });

    test(
      'concurrent refreshes share one read and closed refreshes do nothing',
      () async {
        final Completer<HomeSnapshot> pending = Completer<HomeSnapshot>();
        int calls = 0;
        final HomeCubit cubit = HomeCubit(
          read: () {
            calls++;
            return pending.future;
          },
        );
        final Future<void> first = cubit.refresh();
        expect(cubit.refresh(), same(first));
        expect(calls, 1);
        pending.complete(_snapshot());
        await first;
        await cubit.close();
        await cubit.refresh();
        expect(calls, 1);
      },
    );

    test(
      'an equal fresh read still delivers its exact snapshot to the view',
      () async {
        final HomeSnapshot original = _snapshot();
        final HomeSnapshot fresh = _snapshot();
        int calls = 0;
        final HomeCubit cubit = HomeCubit(
          read: () async => calls++ == 0 ? original : fresh,
        );
        await cubit.refresh();
        expect(cubit.state.snapshot, same(original));
        await cubit.refresh();
        expect(cubit.state.snapshot, same(fresh));
        expect(cubit.state.readRevision, 2);
        await cubit.close();
      },
    );

    test('reads again after the interval and stops when closed', () async {
      int calls = 0;
      final HomeCubit cubit = HomeCubit(
        read: () async {
          calls++;
          return _snapshot(znn: calls);
        },
        interval: const Duration(milliseconds: 20),
      );
      await cubit.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(calls, greaterThan(1));
      await cubit.close();
      final int closedAt = calls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, closedAt);
    });

    test('a read that ends after close emits nothing', () async {
      final Completer<HomeSnapshot> slow = Completer<HomeSnapshot>();
      final HomeCubit cubit = HomeCubit(read: () => slow.future);
      final Future<void> pending = cubit.refresh();
      await cubit.close();
      slow.complete(_snapshot());
      await pending;
      expect(cubit.state.status, HomeStatus.loading);
    });
  });

  group('HomeSnapshot', () {
    test('counts the sends the plasma pays for', () {
      expect(_snapshot().sendsCovered, 4);
      expect(_snapshot(plasma: 20999).sendsCovered, 0);
      expect(_snapshot(plasma: 0).sendsCovered, 0);
    });

    test('lists only the rewards that are due', () {
      expect(_snapshot().rewardsDue.keys, <String>['Delegation', 'Staking']);
    });
  });

  group('splitAmount', () {
    test('groups thousands and quiets trailing zeros without rounding', () {
      expect(splitAmount(BigInt.parse('120450000000'), 8), (
        '1,204.5',
        '0000000',
      ));
      expect(splitAmount(BigInt.parse('100000000'), 8), ('1', '.00000000'));
      expect(splitAmount(BigInt.parse('1'), 8), ('0.00000001', ''));
      expect(splitAmount(BigInt.zero, 8), ('0', '.00000000'));
      expect(splitAmount(BigInt.parse('1234567'), 0), ('1,234,567', ''));
      expect(splitAmount(BigInt.parse('-150000000'), 8), ('-1.5', '0000000'));
      expect(
        splitAmount(BigInt.parse('9000000000000000000'), 8),
        ('90,000,000,000', '.00000000'),
      );
    });
  });
}
