import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/model/activity_entry.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'activity_fixtures.dart';

void main() {
  test('outgoing rows keep the recipient and exact source hash and amount', () {
    final AccountBlock block = activityBlock(
      amount: BigInt.parse('900719925474099312345'),
    );
    final ActivityEntry entry = ActivityEntry.fromBlock(block);
    expect(entry.kind, ActivityKind.sent);
    expect(entry.counterparty, pillarAddress);
    expect(entry.hash, block.hash.toString());
    expect(entry.amount, BigInt.parse('900719925474099312345'));
    expect(entry.decimals, 8);
    expect(entry.symbol, 'ZNN');
  });

  test('receive uses its source identity and time but its paired movement', () {
    final AccountBlock send = activityBlock(
      address: pillarAddress,
      to: emptyAddress,
      timestamp: 1700000000,
      amount: BigInt.one,
    );
    final AccountBlock receive = activityReceive(send: send);
    final ActivityEntry entry = ActivityEntry.fromBlock(receive);
    expect(entry.kind, ActivityKind.received);
    expect(entry.counterparty, pillarAddress);
    expect(entry.hash, receive.hash.toString());
    expect(entry.hash, isNot(send.hash.toString()));
    expect(entry.timestamp, 1800000000);
    expect(entry.amount, BigInt.one);
  });

  test('missing pair never represents the receive zero as incoming funds', () {
    final ActivityEntry entry = ActivityEntry.fromBlock(
      activityBlock(
        type: BlockTypeEnum.userReceive,
        amount: BigInt.zero,
      ),
    );
    expect(entry.kind, ActivityKind.received);
    expect(entry.amount, isNull);
    expect(entry.counterparty, isNull);
    expect(entry.symbol, isNull);
  });

  test(
    'mismatched paired hash, recipient or chain cannot supply an amount',
    () {
      final AccountBlock pair = activityBlock(to: emptyAddress);
      for (final AccountBlock block in <AccountBlock>[
        activityBlock(
          type: BlockTypeEnum.userReceive,
          paired: pair,
          fromHash: emptyHash,
        ),
        activityBlock(
          type: BlockTypeEnum.userReceive,
          paired: pair,
          address: pillarAddress,
        ),
        activityBlock(
          type: BlockTypeEnum.userReceive,
          paired: pair,
          chainId: 321,
        ),
      ]) {
        expect(ActivityEntry.fromBlock(block).amount, isNull);
      }
    },
  );

  test('native coin units are fixed even when RPC metadata is absent', () {
    final ActivityEntry entry = ActivityEntry.fromBlock(
      activityBlock(
        missingToken: true,
        standard: kQsrCoin.tokenStandard,
      ),
    );
    expect(entry.decimals, 8);
    expect(entry.symbol, 'QSR');
    expect(entry.amount, isNotNull);
  });

  test(
    'unknown token without matching metadata cannot silently use zero decimals',
    () {
      final TokenStandard standard = TokenStandard.parse(
        'zts1zdl4pmr425t0j97v4eu0du',
      );
      for (final bool missing in <bool>[true, false]) {
        final ActivityEntry entry = ActivityEntry.fromBlock(
          activityBlock(
            missingToken: missing,
            standard: standard,
          ),
        );
        expect(entry.amount, isNull);
        expect(entry.decimals, isNull);
        expect(entry.symbol, isNull);
      }
    },
  );

  test(
    'known delegation requires destination, token and canonical SDK ABI',
    () {
      final List<int> data = Definitions.pillar.encodeFunction(
        'Delegate',
        <dynamic>['dev1'],
      );
      final ActivityEntry entry = ActivityEntry.fromBlock(
        activityBlock(
          to: pillarAddress,
          amount: BigInt.zero,
          data: data,
        ),
      );
      expect(entry.kind, ActivityKind.delegated);
      expect(entry.name, 'dev1');
      expect(entry.amount, BigInt.zero);
      for (final AccountBlock block in <AccountBlock>[
        activityBlock(to: emptyAddress, amount: BigInt.zero, data: data),
        activityBlock(
          to: pillarAddress,
          amount: BigInt.zero,
          token: kQsrCoin,
          data: data,
        ),
        activityBlock(
          to: pillarAddress,
          amount: BigInt.zero,
          data: data.sublist(0, data.length - 1),
        ),
        activityBlock(
          to: pillarAddress,
          amount: BigInt.zero,
          data: <int>[...data, 0],
        ),
      ]) {
        expect(ActivityEntry.fromBlock(block).kind, ActivityKind.sent);
      }
    },
  );

  test('Fuse identifies the beneficiary from the matching Plasma ABI', () {
    final List<int> data = Definitions.plasma.encodeFunction('Fuse', <dynamic>[
      emptyAddress,
    ]);
    final ActivityEntry entry = ActivityEntry.fromBlock(
      activityBlock(
        to: plasmaAddress,
        token: kQsrCoin,
        data: data,
      ),
    );
    expect(entry.kind, ActivityKind.fused);
    expect(entry.fuseBeneficiary, emptyAddress);
    expect(entry.symbol, 'QSR');
    expect(
      ActivityEntry.fromBlock(
        activityBlock(to: pillarAddress, token: kQsrCoin, data: data),
      ).kind,
      ActivityKind.sent,
    );
    expect(
      ActivityEntry.fromBlock(
        activityBlock(to: plasmaAddress, data: data),
      ).kind,
      ActivityKind.sent,
    );
  });

  test('Stake shows only the term established by the matching contract', () {
    final List<int> data = Definitions.stake.encodeFunction('Stake', <dynamic>[
      stakeTimeUnitSec * 6,
    ]);
    final ActivityEntry entry = ActivityEntry.fromBlock(
      activityBlock(
        to: stakeAddress,
        data: data,
      ),
    );
    expect(entry.kind, ActivityKind.staked);
    expect(entry.stakeMonths, 6);
    expect(
      ActivityEntry.fromBlock(
        activityBlock(to: plasmaAddress, data: data),
      ).kind,
      ActivityKind.sent,
    );
  });

  test('contract refunds are not inferred to be rewards from sender alone', () {
    final AccountBlock send = activityBlock(
      type: BlockTypeEnum.contractSend,
      address: stakeAddress,
      to: emptyAddress,
    );
    expect(
      ActivityEntry.fromBlock(activityReceive(send: send)).kind,
      ActivityKind.received,
    );
    final ActivityEntry explicit = ActivityEntry.fromBlock(
      activityReceive(
        send: activityBlock(
          type: BlockTypeEnum.contractSend,
          address: stakeAddress,
          to: emptyAddress,
          data: Definitions.common.encodeFunction('CollectReward', <dynamic>[]),
        ),
      ),
    );
    expect(explicit.kind, ActivityKind.reward);
  });

  test('a user payload cannot impersonate a contract reward', () {
    final AccountBlock send = activityBlock(
      to: emptyAddress,
      data: Definitions.common.encodeFunction('CollectReward', <dynamic>[]),
    );
    expect(
      ActivityEntry.fromBlock(activityReceive(send: send)).kind,
      ActivityKind.received,
    );
  });

  test('marker bytes do not activate Zap reading or Message', () {
    final AccountBlock send = activityBlock(data: <int>[0x7a, 0x61, 0x70, 1]);
    final ActivityEntry ordinary = ActivityEntry.fromBlock(send);
    expect(ordinary.kind, ActivityKind.sent);
    expect(ordinary.hasMessage, isFalse);
    final ActivityEntry preview = ActivityEntry.fromBlock(
      send,
      zapPreview: const ActivityZapPreview(),
    );
    expect(preview.kind, ActivityKind.zap);
    expect(preview.hasMessage, isTrue);
    expect(preview.hash, ordinary.hash);
    expect(preview.amount, ordinary.amount);
    expect(
      ActivityEntry.fromBlock(
        send,
        zapPreview: const ActivityZapPreview(hasMessage: false),
      ).hasMessage,
      isFalse,
    );
  });

  test('negative movement and absent confirmation stay explicitly unknown', () {
    final ActivityEntry entry = ActivityEntry.fromBlock(
      activityBlock(
        amount: -BigInt.one,
        timestamp: null,
      ),
    );
    expect(entry.amount, isNull);
    expect(entry.timestamp, isNull);
  });
}
