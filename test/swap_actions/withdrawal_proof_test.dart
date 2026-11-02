import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

ActionFixture _proof() => ActionFixture()..now = 1800000000;

void main() {
  for (final P2pSwapDirection direction in P2pSwapDirection.values) {
    test(
      'Complete ${direction.name} publishes the exact receive ID '
      'and preserves nonterminal state',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcSwap swap = fixture.seedSwap(direction: direction);
        final String id = direction == P2pSwapDirection.incoming
            ? swap.initialHtlcId
            : swap.counterHtlcId!;
        final SwapActionResult result = await fixture.complete(swap);
        expect(result.status, SwapActionStatus.submitted);
        expect(result.acceptedHash, actionHash(1));
        expect(result.swap!.state, P2pSwapState.active);
        expect(fixture.store.stored!.state, P2pSwapState.active);
        expect(fixture.creationReads, <String>[id]);
        expect(fixture.timeReads, 2);
        expect(fixture.markerKeys.single, ('complete', id, fixture.owner));
        final BlockData data = AccountBlockUtils.getDecodedBlockData(
          Definitions.htlc,
          fixture.sent!.data,
        )!;
        expect(data.function, 'Unlock');
        expect(data.params['id'].toString(), id);
        expect(
          (data.params['preimage'] as List<int>).length,
          htlcPreimageDefaultLength,
        );
        expect(fixture.sent!.address.toString(), fixture.owner);
        expect(fixture.sent!.amount, BigInt.zero);
        expect(result.publication, same(fixture.publicationOriginal));
      },
    );
  }

  for (final String defect in <String>[
    'id',
    'recipient',
    'sender',
    'amount',
    'token',
    'expiry',
    'hash-type',
    'key-limit',
    'hash-lock',
  ]) {
    test(
      'Complete fresh $defect cannot replace the original accepted terms',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcSwap swap = fixture.seedSwap();
        final HtlcInfo live = fixture.deposits[swap.initialHtlcId]!;
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
        if (defect == 'sender') {
          bad = copyActionDeposit(
            live,
            sender: Address.parse(actionAddress(9)),
          );
        }
        if (defect == 'amount') {
          bad = copyActionDeposit(live, amount: live.amount + BigInt.one);
        }
        if (defect == 'token') {
          bad = copyActionDeposit(live, standard: fixture.token.tokenStandard);
        }
        if (defect == 'expiry') {
          bad = copyActionDeposit(live, expires: live.expirationTime + 1);
        }
        if (defect == 'hash-type') bad = copyActionDeposit(live, hashType: 99);
        if (defect == 'key-limit') {
          bad = copyActionDeposit(live, keySize: htlcPreimageDefaultLength - 1);
        }
        if (defect == 'hash-lock') {
          bad = copyActionDeposit(live, lock: List<int>.filled(32, 8));
        }
        fixture.seedDeposit(
          bad,
          token: defect == 'token' ? fixture.token : fixture.receiving,
          timestamp: fixture.now - 10,
        );
        fixture.deposits[swap.initialHtlcId] = bad;
        final SwapActionResult result = await fixture.complete(swap);
        expect(result.status, SwapActionStatus.refused);
        expect(fixture.publications, 0);
        expect(fixture.marker.preparations, 0);
      },
    );
  }

  for (final String defect in <String>[
    'missing-key',
    'wrong-key',
    'missing-counter-id',
    'wrong-chain',
    'creation-absent',
    'creation-ABI',
  ]) {
    test('Complete $defect refuses before publication', () async {
      final ActionFixture fixture = _proof();
      HtlcSwap swap = fixture.seedSwap(
        direction: defect == 'missing-counter-id'
            ? P2pSwapDirection.outgoing
            : P2pSwapDirection.incoming,
      );
      final String id = swap.direction == P2pSwapDirection.incoming
          ? swap.initialHtlcId
          : swap.counterHtlcId!;
      if (defect == 'missing-key') swap.preimage = null;
      if (defect == 'wrong-key') swap.preimage = '00';
      if (defect == 'missing-counter-id') swap.counterHtlcId = null;
      if (defect == 'wrong-chain') {
        swap = HtlcSwap.fromJson(<String, dynamic>{
          ...swap.toJson(),
          'chainId': 322,
        });
      }
      if (defect == 'creation-absent') fixture.creations[id] = null;
      if (defect == 'creation-ABI') {
        fixture.creations[id]!.data = fixture.builder
            .reclaim(Hash.parse(id))
            .data;
      }
      expect((await fixture.complete(swap)).status, SwapActionStatus.refused);
      expect(fixture.publications, 0);
    });
  }

  for (final int time in <int>[0, -1]) {
    test('Complete and Reclaim reject nonpositive chain time $time', () async {
      final ActionFixture complete = _proof();
      final HtlcSwap swap = complete.seedSwap();
      complete.now = time;
      expect((await complete.complete(swap)).status, SwapActionStatus.refused);
      expect(complete.publications, 0);
      final ActionFixture reclaim = _proof();
      final HtlcSwap saved = reclaim.seedSwap();
      reclaim.now = time;
      expect(
        (await reclaim.reclaim(Hash.parse(saved.counterHtlcId!))).status,
        SwapActionStatus.refused,
      );
      expect(reclaim.publications, 0);
    });
  }

  test(
    'Complete refreshes time '
    'and refuses backward or newly unsafe publication clocks',
    () async {
      for (final bool backwards in <bool>[false, true]) {
        final ActionFixture fixture = _proof();
        final HtlcSwap swap = fixture.seedSwap();
        final int first = fixture.now;
        fixture.timeRead = () async => fixture.timeReads == 1
            ? first
            : backwards
            ? first - 1
            : swap.initialHtlcExpirationTime -
                  kMinSafeTimeToCompleteSwap.inSeconds;
        expect((await fixture.complete(swap)).status, SwapActionStatus.refused);
        expect(fixture.publications, 0);
      }
    },
  );

  test(
    'a captured nonselected recipient completes '
    'without changing original selection',
    () async {
      final ActionFixture fixture = _proof();
      fixture
        ..selected = actionAddress(3)
        ..members = <String>[fixture.owner, fixture.selected!];
      final HtlcSwap swap = fixture.seedSwap();
      expect((await fixture.complete(swap)).status, SwapActionStatus.submitted);
      expect(fixture.sent!.address.toString(), fixture.owner);
      expect(fixture.selected, actionAddress(3));
    },
  );

  for (final bool reclaim in <bool>[false, true]) {
    test(
      'missing live ${reclaim ? 'Reclaim' : 'Complete'} data '
      'preserves its original error without publication',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcSwap swap = fixture.seedSwap();
        final Object failure = StateError(
          'Synthetic unavailable withdrawal deposit',
        );
        fixture.htlcRead = (_) => Future<HtlcInfo>.error(failure);
        final SwapActionResult result = await (reclaim
            ? fixture.reclaim(Hash.parse(swap.counterHtlcId!))
            : fixture.complete(swap));
        expect(result.status, SwapActionStatus.refused);
        expect(result.error, same(failure));
        expect(fixture.publications, 0);
        expect(fixture.marker.preparations, 0);
        expect(fixture.store.writes, 0);
      },
    );
  }

  test(
    'a pending original Complete is retained '
    'across source replacement and repeated clicks',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcSwap swap = fixture.seedSwap();
      final Completer<AccountBlockTemplate> reply = fixture
          .ownCompleter<AccountBlockTemplate>();
      fixture.publicationReply = reply.future;
      final Future<SwapActionResult> original = fixture.complete(swap);
      await microtasksUntil(() => fixture.publications == 1);
      expect(fixture.complete(swap), same(original));
      fixture.current = false;
      reply.complete(fixture.sent!);
      final SwapActionResult result = await original;
      expect(result.status, SwapActionStatus.submitted);
      expect(result.publication, same(reply.future));
      expect(result.persistence, same(fixture.store.original));
      expect(result.swap!.state, P2pSwapState.active);
      expect(fixture.publications, 1);
    },
  );

  for (final String defect in <String>[
    'hash',
    'chain',
    'owner',
    'destination',
    'type',
    'amount',
    'token',
    'data',
  ]) {
    test(
      'returned Complete $defect mismatch remains unknown and held',
      () async {
        final ActionFixture fixture = _proof();
        final HtlcSwap swap = fixture.seedSwap();
        fixture.onPublish = () {
          final AccountBlockTemplate response = fixture.sent!;
          if (defect == 'hash') response.hash = emptyHash;
          if (defect == 'chain') response.chainIdentifier++;
          if (defect == 'owner') {
            response.address = Address.parse(actionAddress(9));
          }
          if (defect == 'destination') response.toAddress = emptyAddress;
          if (defect == 'type') {
            response.blockType = BlockTypeEnum.userReceive.index;
          }
          if (defect == 'amount') response.amount = BigInt.one;
          if (defect == 'token') {
            response.tokenStandard = fixture.receiving.tokenStandard;
          }
          if (defect == 'data') {
            response.data = fixture.builder
                .reclaim(Hash.parse(swap.initialHtlcId))
                .data;
          }
        };
        final Future<SwapActionResult> original = fixture.complete(swap);
        final SwapActionResult result = await original;
        expect(result.status, SwapActionStatus.unknown);
        expect(fixture.complete(swap), same(original));
        expect(fixture.publications, 1);
        expect(fixture.store.writes, 0);
        expect(fixture.marker.unknowns, 1);
      },
    );
  }

  test(
    'Reclaim at exact positive expiry publishes its exact ID '
    'without inventing terminal history',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcSwap swap = fixture.seedSwap();
      final String id = swap.counterHtlcId!;
      fixture.now = fixture.deposits[id]!.expirationTime;
      final SwapActionResult result = await fixture.reclaim(Hash.parse(id));
      expect(result.status, SwapActionStatus.submitted);
      expect(result.swap, isNull);
      expect(fixture.history.single.state, P2pSwapState.active);
      expect(fixture.storeReservations, 0);
      expect(fixture.store.writes, 0);
      expect(fixture.markerKeys.single, ('reclaim', id, fixture.owner));
      final BlockData data = AccountBlockUtils.getDecodedBlockData(
        Definitions.htlc,
        fixture.sent!.data,
      )!;
      expect(data.function, 'Reclaim');
      expect(data.params['id'].toString(), id);
      expect(fixture.creationReads, <String>[id]);
    },
  );

  for (final String defect in <String>[
    'not-expired',
    'id',
    'timelock-owner',
    'creation-absent',
    'creation-chain',
    'creation-ABI',
  ]) {
    test('Reclaim $defect cannot establish an owned expired deposit', () async {
      final ActionFixture fixture = _proof();
      final HtlcSwap swap = fixture.seedSwap();
      final String id = swap.counterHtlcId!;
      fixture.now = fixture.deposits[id]!.expirationTime;
      if (defect == 'not-expired') fixture.now--;
      if (defect == 'id') {
        fixture.deposits[id] = copyActionDeposit(
          fixture.deposits[id]!,
          id: Hash.parse(actionHash(999)),
        );
      }
      if (defect == 'timelock-owner') {
        fixture.deposits[id] = copyActionDeposit(
          fixture.deposits[id]!,
          sender: Address.parse(actionAddress(9)),
        );
      }
      if (defect == 'creation-absent') fixture.creations[id] = null;
      if (defect == 'creation-chain') fixture.creations[id]!.chainIdentifier++;
      if (defect == 'creation-ABI') {
        fixture.creations[id]!.data = fixture.builder
            .unlock(Hash.parse(id), List<int>.filled(32, 7))
            .data;
      }
      expect(
        (await fixture.reclaim(Hash.parse(id))).status,
        SwapActionStatus.refused,
      );
      expect(fixture.publications, 0);
      expect(fixture.marker.preparations, 0);
    });
  }

  test(
    'unknown original Reclaim retains its exact error, Future '
    'and one signer handoff',
    () async {
      final ActionFixture fixture = _proof();
      final HtlcSwap swap = fixture.seedSwap();
      final Hash id = Hash.parse(swap.counterHtlcId!);
      fixture.now = fixture.deposits[id.toString()]!.expirationTime;
      final Completer<AccountBlockTemplate> reply = fixture
          .ownCompleter<AccountBlockTemplate>();
      fixture.publicationReply = reply.future;
      final Future<SwapActionResult> original = fixture.reclaim(id);
      await microtasksUntil(() => fixture.publications == 1);
      final Object failure = StateError('Synthetic original Reclaim');
      final StackTrace trace = StackTrace.current;
      reply.completeError(failure, trace);
      final SwapActionResult result = await original;
      expect(result.status, SwapActionStatus.unknown);
      expect(result.error, same(failure));
      expect(result.stackTrace, same(trace));
      expect(result.publication, same(reply.future));
      expect(fixture.reclaim(id), same(original));
      expect(fixture.publications, 1);
      expect(fixture.history.single.state, P2pSwapState.active);
    },
  );
}
