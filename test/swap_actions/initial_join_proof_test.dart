import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

ActionFixture _proof() => ActionFixture()..now = 1800000000;

void main() {
  test(
    'initial inspection requires exact live, creation '
    'and contract receive proofs',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      final HtlcInfo proven = await fixture.initial(live);
      expect(proven.id, live.id);
      expect(proven, isNot(same(live)));
      expect(fixture.htlcReads, <String>[live.id.toString()]);
      expect(fixture.creationReads, <String>[live.id.toString()]);
      expect(fixture.contractReads, <int>[
        live.expirationTime - kMaxAllowedInitialHtlcDuration.inSeconds,
      ]);
      expect(fixture.timeReads, 2);
      expect(fixture.publications, 0);
      expect(fixture.storeReservations, 0);
    },
  );

  test(
    'omitted optional paired confirmation '
    'is supplied by the independent exact Create',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      fixture.contractBlocks.single.pairedAccountBlock!.confirmationDetail =
          null;
      expect(
        fixture
            .creations[live.id.toString()]!
            .confirmationDetail!
            .numConfirmations,
        greaterThan(0),
      );
      expect((await fixture.initial(live)).id, live.id);
    },
  );

  test(
    'another originally owned recipient '
    'can be inspected without changing selection',
    () async {
      final ActionFixture fixture = _proof();
      fixture
        ..selected = actionAddress(3)
        ..members = <String>[fixture.owner, fixture.selected!];
      final HtlcInfo live = fixture.seedInitial();
      expect(
        (await fixture.initial(live)).hashLocked.toString(),
        fixture.owner,
      );
      expect(fixture.selected, actionAddress(3));
      expect(fixture.publications, 0);
    },
  );

  for (final String defect in <String>[
    'id',
    'recipient',
    'owned-sender',
    'zero-amount',
    'negative-amount',
    'lock-size',
    'key-size',
    'hash-type',
    'unsafe-expiry',
    'excessive-expiry',
  ]) {
    test('initial $defect refuses without publication', () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      HtlcInfo bad = live;
      if (defect == 'id') {
        bad = copyActionDeposit(live, id: Hash.parse(actionHash(999)));
      }
      if (defect == 'recipient') {
        bad = copyActionDeposit(
          live,
          recipient: Address.parse(actionAddress(9)),
        );
      }
      if (defect == 'owned-sender') {
        bad = copyActionDeposit(live, sender: Address.parse(fixture.owner));
      }
      if (defect == 'zero-amount') {
        bad = copyActionDeposit(live, amount: BigInt.zero);
      }
      if (defect == 'negative-amount') {
        bad = copyActionDeposit(live, amount: -BigInt.one);
      }
      if (defect == 'lock-size') {
        bad = copyActionDeposit(live, lock: List<int>.filled(31, 8));
      }
      if (defect == 'key-size') {
        bad = copyActionDeposit(live, keySize: htlcPreimageDefaultLength - 1);
      }
      if (defect == 'hash-type') bad = copyActionDeposit(live, hashType: 99);
      if (defect == 'unsafe-expiry') {
        bad = copyActionDeposit(
          live,
          expires:
              fixture.now +
              (kMinSafeTimeToFindPreimage + kCounterHtlcDuration).inSeconds -
              1,
        );
      }
      if (defect == 'excessive-expiry') {
        bad = copyActionDeposit(
          live,
          expires: fixture.now + kMaxAllowedInitialHtlcDuration.inSeconds + 1,
        );
      }
      fixture.deposits[live.id.toString()] = bad;
      await expectLater(
        fixture.initial(live),
        throwsA(isA<SwapActionRefused>()),
      );
      expect(fixture.publications, 0);
      expect(fixture.marker.preparations, 0);
    });
  }

  for (final int time in <int>[0, -1]) {
    test(
      'initial chain time $time is unavailable rather than an expiry authority',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcInfo live = fixture.seedInitial();
        fixture.now = time;
        await expectLater(
          fixture.initial(live),
          throwsA(isA<SwapActionRefused>()),
        );
        expect(fixture.publications, 0);
      },
    );
  }

  for (final String defect in <String>[
    'missing',
    'hash',
    'chain',
    'sender',
    'destination',
    'type',
    'amount',
    'token',
    'confirmation',
    'zero-confirmations',
    'timestamp',
    'future',
    'ABI',
    'ABI-recipient',
    'ABI-expiry',
    'ABI-hash-type',
    'ABI-key-size',
    'ABI-lock',
  ]) {
    test(
      'initial creation $defect cannot be replaced by live lookup alone',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcInfo live = fixture.seedInitial();
        final AccountBlock block = fixture.creations[live.id.toString()]!;
        if (defect == 'missing') fixture.creations[live.id.toString()] = null;
        if (defect == 'hash') block.hash = Hash.parse(actionHash(999));
        if (defect == 'chain') block.chainIdentifier++;
        if (defect == 'sender') block.address = Address.parse(actionAddress(9));
        if (defect == 'destination') block.toAddress = emptyAddress;
        if (defect == 'type') block.blockType = BlockTypeEnum.userReceive.index;
        if (defect == 'amount') block.amount += BigInt.one;
        if (defect == 'token') {
          block.tokenStandard = fixture.token.tokenStandard;
        }
        if (defect == 'confirmation') block.confirmationDetail = null;
        if (defect == 'zero-confirmations') {
          block.confirmationDetail!.numConfirmations = 0;
        }
        if (defect == 'timestamp') {
          block.confirmationDetail!.momentumTimestamp = 0;
        }
        if (defect == 'future') {
          block.confirmationDetail!.momentumTimestamp = fixture.now + 1;
        }
        if (defect == 'ABI') block.data = fixture.builder.reclaim(live.id).data;
        if (defect.startsWith('ABI-')) {
          block.data = fixture.builder
              .create(
                fixture.receiving,
                live.amount,
                defect == 'ABI-recipient'
                    ? Address.parse(actionAddress(9))
                    : live.hashLocked,
                live.expirationTime + (defect == 'ABI-expiry' ? 1 : 0),
                defect == 'ABI-hash-type' ? 99 : live.hashType,
                live.keyMaxSize - (defect == 'ABI-key-size' ? 1 : 0),
                defect == 'ABI-lock' ? List<int>.filled(32, 8) : live.hashLock,
              )
              .data;
        }
        await expectLater(
          fixture.initial(live),
          throwsA(isA<SwapActionRefused>()),
        );
        expect(fixture.publications, 0);
      },
    );
  }

  for (final String defect in <String>[
    'missing',
    'owner',
    'chain',
    'hash',
    'confirmation',
    'zero-confirmations',
    'future',
    'origin-link',
    'pair',
    'pair-chain',
    'pair-id',
    'pair-tuple',
  ]) {
    test(
      'initial contract effect $defect refuses an unproven catalogue',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcInfo live = fixture.seedInitial();
        final AccountBlock effect = fixture.contractBlocks.single;
        if (defect == 'missing') fixture.contractBlocks.clear();
        if (defect == 'owner') effect.address = emptyAddress;
        if (defect == 'chain') effect.chainIdentifier++;
        if (defect == 'hash') effect.hash = emptyHash;
        if (defect == 'confirmation') effect.confirmationDetail = null;
        if (defect == 'zero-confirmations') {
          effect.confirmationDetail!.numConfirmations = 0;
        }
        if (defect == 'future') {
          effect.confirmationDetail!.momentumTimestamp = fixture.now + 1;
        }
        if (defect == 'origin-link') {
          effect.fromBlockHash = Hash.parse(actionHash(999));
        }
        if (defect == 'pair') effect.pairedAccountBlock = null;
        if (defect == 'pair-chain') {
          effect.pairedAccountBlock!.chainIdentifier++;
        }
        if (defect == 'pair-id') {
          effect.pairedAccountBlock!.hash = Hash.parse(actionHash(999));
          effect.fromBlockHash = effect.pairedAccountBlock!.hash;
        }
        if (defect == 'pair-tuple') {
          effect.pairedAccountBlock!.amount += BigInt.one;
        }
        await expectLater(
          fixture.initial(live),
          throwsA(isA<SwapActionRefused>()),
        );
        expect(fixture.publications, 0);
      },
    );
  }

  test(
    'an original history error is retained without an empty-history substitute',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      final Object failure = StateError('Synthetic original history');
      fixture.contractRead = (_) => Future<List<AccountBlock>>.error(failure);
      await expectLater(fixture.initial(live), throwsA(same(failure)));
      expect(fixture.publications, 0);
    },
  );

  test(
    'missing live data retains the original error and cannot publish Join',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      final Object failure = StateError('Synthetic unavailable live deposit');
      fixture.htlcRead = (_) => Future<HtlcInfo>.error(failure);
      await expectLater(fixture.initial(live), throwsA(same(failure)));
      final SwapActionResult result = await fixture.join(live);
      expect(result.status, SwapActionStatus.refused);
      expect(result.error, same(failure));
      expect(fixture.publications, 0);
      expect(fixture.marker.preparations, 0);
      expect(fixture.store.writes, 0);
    },
  );

  test(
    'a newer history confirmation uses the fresh positive chain clock',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      fixture.contractBlocks.single.confirmationDetail!.momentumTimestamp =
          fixture.now + 1;
      fixture.timeRead = () async =>
          fixture.now + (fixture.timeReads == 1 ? 0 : 1);
      expect((await fixture.initial(live)).id, live.id);
      expect(fixture.timeReads, 2);
    },
  );

  for (final String clock in <String>['backwards', 'unsafe', 'nonpositive']) {
    test('initial fresh $clock history clock cannot authorize Join', () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      fixture.timeRead = () async => fixture.timeReads == 1
          ? fixture.now
          : clock == 'backwards'
          ? fixture.now - 1
          : clock == 'nonpositive'
          ? 0
          : live.expirationTime -
                (kMinSafeTimeToFindPreimage + kCounterHtlcDuration).inSeconds +
                1;
      expect((await fixture.join(live)).status, SwapActionStatus.refused);
      expect(fixture.timeReads, 2);
      expect(fixture.accountReads, isEmpty);
      expect(fixture.publications, 0);
    });
  }

  test(
    'a low positive chain clock clamps the generic history cutoff at zero',
    () async {
      final ActionFixture fixture = ActionFixture();
      final HtlcInfo live = fixture.seedInitial();
      expect((await fixture.initial(live)).id, live.id);
      expect(fixture.contractReads, <int>[0]);
    },
  );

  test(
    'a live read that departs from the original source cannot be adopted',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      final Completer<HtlcInfo> reply = fixture.ownCompleter<HtlcInfo>();
      fixture.htlcRead = (_) => reply.future;
      final Future<HtlcInfo> original = fixture.initial(live);
      final Future<void> refusal = expectLater(
        original,
        throwsA(isA<SwapActionRefused>()),
      );
      fixture.revision++;
      reply.complete(live);
      await refusal;
      expect(fixture.creationReads, isEmpty);
    },
  );

  test(
    'Join captures sender and reservations before reading the original deposit',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      fixture.htlcRead = (String _) async {
        expect(fixture.senderCaptures, 1);
        expect(fixture.storeReservations, 1);
        expect(fixture.markerReservations, 1);
        return live;
      };
      final SwapActionResult result = await fixture.join(live);
      expect(result.status, SwapActionStatus.submitted);
      expect(result.swap!.direction, P2pSwapDirection.incoming);
      expect(result.swap!.state, P2pSwapState.active);
      expect(result.swap!.initialHtlcId, live.id.toString());
      expect(result.swap!.counterHtlcId, result.acceptedHash);
      expect(result.swap!.toAmount, live.amount);
      expect(result.swap!.preimage, isNull);
      final BlockData data = AccountBlockUtils.getDecodedBlockData(
        Definitions.htlc,
        fixture.sent!.data,
      )!;
      expect(data.function, 'Create');
      expect(data.params['hashLocked'], live.timeLocked);
      expect(
        data.params['expirationTime'].toString(),
        (fixture.now + kCounterHtlcDuration.inSeconds).toString(),
      );
      expect(fixture.sent!.amount, BigInt.from(100));
      expect(fixture.markerKeys.single, (
        'join',
        live.id.toString(),
        fixture.owner,
      ));
    },
  );

  test(
    'Join rejects changed drawn terms '
    'even when the new live tuple has valid independent proof',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo drawn = fixture.seedInitial();
      final HtlcInfo changed = copyActionDeposit(
        drawn,
        amount: drawn.amount + BigInt.one,
      );
      fixture.contractBlocks.clear();
      fixture.seedDeposit(
        changed,
        token: fixture.receiving,
        timestamp: fixture.now - 10,
      );
      final SwapActionResult result = await fixture.join(drawn);
      expect(result.status, SwapActionStatus.refused);
      expect(fixture.publications, 0);
    },
  );

  test(
    'Join refuses missing receive metadata and an uncertain funding balance',
    () async {
      final ActionFixture missing = _proof();
      final HtlcInfo first = missing.seedInitial();
      missing.tokens[first.tokenStandard.toString()] = null;
      expect((await missing.join(first)).status, SwapActionStatus.refused);
      expect(missing.publications, 0);
      final ActionFixture balance = _proof();
      final HtlcInfo second = balance.seedInitial();
      balance.accountReply = Future<AccountInfo>.value(
        AccountInfo(
          address: balance.owner,
          blockCount: 0,
        ),
      );
      expect((await balance.join(second)).status, SwapActionStatus.refused);
      expect(balance.publications, 0);
    },
  );

  test(
    'Join refreshes chain time after funding and refuses a newly unsafe window',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      final int first = fixture.now;
      fixture.timeRead = () async => fixture.timeReads <= 2
          ? first
          : live.expirationTime -
                (kMinSafeTimeToFindPreimage + kCounterHtlcDuration).inSeconds +
                1;
      expect((await fixture.join(live)).status, SwapActionStatus.refused);
      expect(fixture.timeReads, 3);
      expect(fixture.publications, 0);
    },
  );

  test(
    'Join refuses a backward final clock '
    'after both initial proof clocks succeeded',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      fixture.timeRead = () async =>
          fixture.timeReads <= 2 ? fixture.now : fixture.now - 1;
      expect((await fixture.join(live)).status, SwapActionStatus.refused);
      expect(fixture.timeReads, 3);
      expect(fixture.accountReads, <String>[fixture.owner]);
      expect(fixture.publications, 0);
      expect(fixture.marker.preparations, 0);
    },
  );

  test(
    'a late older chain-time reply cannot replace a newer original proof',
    () async {
      final ActionFixture fixture = _proof();
      final Completer<int> first = fixture.ownCompleter<int>();
      final Completer<int> second = fixture.ownCompleter<int>();
      fixture.timeRead = () =>
          fixture.timeReads == 1 ? first.future : second.future;
      final SwapActionOrigin origin = fixture.origin();
      final Future<int> older = fixture.observe(origin.readChainTime());
      final Future<void> refused = expectLater(
        older,
        throwsA(isA<SwapActionRefused>()),
      );
      final Future<int> newer = fixture.observe(origin.readChainTime());
      second.complete(fixture.now + 2);
      expect(await newer, fixture.now + 2);
      first.complete(fixture.now + 1);
      await refused;
      expect(fixture.publications, 0);
    },
  );

  test(
    'a pending unknown Join retains its exact original Future '
    'across repeated clicks',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcInfo live = fixture.seedInitial();
      final Completer<AccountBlockTemplate> reply = fixture
          .ownCompleter<AccountBlockTemplate>();
      fixture.publicationReply = reply.future;
      final Future<SwapActionResult> original = fixture.join(live);
      await microtasksUntil(() => fixture.publications == 1);
      expect(fixture.join(live), same(original));
      final Object failure = StateError('Synthetic original Join publication');
      final StackTrace trace = StackTrace.current;
      reply.completeError(failure, trace);
      final SwapActionResult result = await original;
      expect(result.status, SwapActionStatus.unknown);
      expect(result.publication, same(reply.future));
      expect(result.error, same(failure));
      expect(result.stackTrace, same(trace));
      expect(fixture.join(live), same(original));
      expect(fixture.publications, 1);
    },
  );
}
