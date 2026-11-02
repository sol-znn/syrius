import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

HtlcFixture _outgoing(int number) {
  final HtlcFixture fixture = HtlcFixture(number);
  fixture
    ..record = htlcRecord(number, direction: P2pSwapDirection.outgoing)
    ..seedRecord(fixture.record);
  return fixture;
}

void _chain(HtlcFixture fixture, int count) {
  String previous = emptyHash.toString();
  for (int height = 1; height <= count; height++) {
    final AccountBlock block = htlcBlock(
      height: height,
      previous: previous,
      timestamp: 200 + height,
    );
    fixture.blocks.add(block);
    previous = block.hash.toString();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HtlcSwapsHandler handlerFor(
    HtlcFixture fixture, {
    int maxBlocks = 1000,
    AutoUnlockHtlcWorker? worker,
  }) {
    final HtlcSwapsHandler handler = HtlcSwapsHandler(
      captureOrigin: fixture.capture,
      unlockWorker: worker,
      maxBlocksPerCycle: maxBlocks,
    );
    addTearDown(() async {
      await handler.pauseAndDrain();
    });
    return handler;
  }

  test(
    'a complete exact contiguous scan commits chain height and hash together',
    () async {
      final HtlcFixture fixture = _outgoing(301);
      _chain(fixture, 101);
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await handler.runOnce();
      expect(fixture.pages, <(int, int)>[(1, 100), (101, 1)]);
      expect(fixture.store.readCursor().height, 101);
      expect(
        fixture.store.readCursor().hash,
        fixture.blocks.last.hash.toString(),
      );
      expect((await handler.pauseAndDrain()).completed, isTrue);
    },
  );

  test(
    'a bounded positive prefix commits only scanned blocks and defers expiry',
    () async {
      final HtlcFixture fixture = _outgoing(302);
      _chain(fixture, 3);
      fixture.timeRead = () async => 6000;
      final HtlcSwapsHandler handler = handlerFor(fixture, maxBlocks: 2);
      await handler.runOnce();
      expect(fixture.store.readCursor().height, 2);
      expect(fixture.liveReads, isEmpty);
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.active,
      );
      await handler.runOnce();
      expect(fixture.pages, <(int, int)>[(1, 2), (2, 1), (3, 1)]);
      expect(fixture.store.readCursor().height, 3);
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.reclaimable,
      );
    },
  );

  for (final String incomplete in <String>[
    'null',
    'empty',
    'short',
    'out-of-order',
    'wrong-chain',
    'unconfirmed',
  ]) {
    test(
      '$incomplete source never advances an unproven cursor '
      'or expires a record',
      () async {
        final HtlcFixture fixture = _outgoing(
          310 +
              <String>[
                'null',
                'empty',
                'short',
                'out-of-order',
                'wrong-chain',
                'unconfirmed',
              ].indexOf(incomplete),
        );
        _chain(fixture, 2);
        fixture.pageRead = (int _, int _) async {
          if (incomplete == 'null') return null;
          if (incomplete == 'empty') return <AccountBlock>[];
          if (incomplete == 'short') {
            return <AccountBlock>[fixture.blocks.first];
          }
          if (incomplete == 'out-of-order') {
            return fixture.blocks.reversed.toList();
          }
          if (incomplete == 'wrong-chain') {
            fixture.blocks.first.chainIdentifier = htlcChain + 1;
          }
          if (incomplete == 'unconfirmed') {
            fixture.blocks.first.confirmationDetail!.numConfirmations = 0;
          }
          return fixture.blocks;
        };
        final HtlcSwapsHandler handler = handlerFor(fixture);
        await expectLater(
          handler.runOnce(),
          throwsA(isA<HtlcOwnershipRefused>()),
        );
        expect(fixture.store.readCursor().height, 0);
        expect(fixture.liveReads, isEmpty);
        expect(
          fixture.store.getSwapById(fixture.record.id)!.state,
          P2pSwapState.active,
        );
        expect((await handler.pauseAndDrain()).completed, isFalse);
      },
    );
  }

  test(
    'an incomplete later page preserves only its independently proven prefix',
    () async {
      final HtlcFixture fixture = _outgoing(320);
      _chain(fixture, 101);
      fixture.pageRead = (int height, int count) async =>
          height == 1 ? fixture.blocks.take(count).toList() : null;
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await expectLater(
        handler.runOnce(),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(fixture.store.readCursor().height, 100);
      expect(
        fixture.store.readCursor().hash,
        fixture.blocks[99].hash.toString(),
      );
      expect(fixture.liveReads, isEmpty);
    },
  );

  test('an uncertain frontier is never a positive empty account', () async {
    final HtlcFixture fixture = _outgoing(321);
    final HtlcSwapsHandler handler = handlerFor(fixture);
    await expectLater(handler.runOnce(), throwsA(isA<HtlcOwnershipRefused>()));
    expect(fixture.store.readCursor().height, 0);
    expect(
      fixture.store.getSwapById(fixture.record.id)!.state,
      P2pSwapState.active,
    );
  });

  test(
    'a moving frontier defers current expiry until an exact caught-up cycle',
    () async {
      final HtlcFixture fixture = _outgoing(322);
      _chain(fixture, 2);
      int frontierReads = 0;
      fixture.frontierRead = () async =>
          fixture.blocks[frontierReads++ == 0 ? 0 : 1];
      fixture.timeRead = () async => 6000;
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await handler.runOnce();
      expect(fixture.store.readCursor().height, 1);
      expect(fixture.liveReads, isEmpty);
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.active,
      );
    },
  );

  test(
    'a missing live read after scanning never infers spent or expired state',
    () async {
      final HtlcFixture fixture = _outgoing(323);
      _chain(fixture, 1);
      final Object failure = StateError('Synthetic getById uncertainty');
      fixture
        ..liveRead = ((String _) => Future<HtlcInfo>.error(failure))
        ..timeRead = () async => 6000;
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await expectLater(handler.runOnce(), throwsA(same(failure)));
      expect(fixture.store.readCursor().height, 1);
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.active,
      );
      expect((await handler.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'only a positive matching live deposit and chain clock '
    'prove reclaimability',
    () async {
      final HtlcFixture fixture = _outgoing(324);
      _chain(fixture, 1);
      fixture.timeRead = () async => fixture.record.initialHtlcExpirationTime;
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await handler.runOnce();
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.reclaimable,
      );
      expect(fixture.signers, isEmpty);
    },
  );

  test(
    'a confirmed exact Unlock output establishes persisted terminal history',
    () async {
      final HtlcFixture fixture = _outgoing(325);
      fixture.blocks.add(
        htlcTerminal(fixture.record, unlock: true, initial: false),
      );
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await handler.runOnce();
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.completed,
      );
      expect(fixture.liveReads, isEmpty);
      expect(fixture.blockReads, <String>[fixture.record.counterHtlcId!]);
    },
  );

  test(
    'a confirmed exact Reclaim output establishes unsuccessful history',
    () async {
      final HtlcFixture fixture = _outgoing(326);
      fixture.blocks.add(
        htlcTerminal(fixture.record, unlock: false, initial: true),
      );
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await handler.runOnce();
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.unsuccessful,
      );
      expect(fixture.liveReads, isEmpty);
    },
  );

  test(
    'a mismatched original Create cannot authorize terminal mutation',
    () async {
      final HtlcFixture fixture = _outgoing(327);
      fixture.blocks.add(
        htlcTerminal(fixture.record, unlock: true, initial: false),
      );
      fixture.blockRead = (_) async =>
          htlcCreate(fixture.record, initial: false)
            ..address = Address.parse(htlcOwner(9));
      final HtlcSwapsHandler handler = handlerFor(fixture);
      await expectLater(
        handler.runOnce(),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.active,
      );
      expect(fixture.store.readCursor().height, 0);
    },
  );

  test(
    'pause awaits all admitted sync and original wake-lock release futures',
    () async {
      final HtlcFixture fixture = HtlcFixture(328);
      fixture.record.preimage = null;
      fixture.seedRecord(fixture.record);
      _chain(fixture, 1);
      final Completer<SyncInfo> sync = Completer<SyncInfo>();
      final Completer<void> wake = Completer<void>();
      fixture
        ..syncRead = (() => sync.future)
        ..wakeDisable = () => wake.future;
      final HtlcSwapsHandler handler = handlerFor(fixture);
      final HtlcOutcome<void> cycle = HtlcOutcome<void>(handler.runOnce());
      await htlcMicrotasks();
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        handler.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(pause.completed, isFalse);
      sync.complete(fixture.synced());
      await cycle.future;
      await htlcMicrotasks();
      expect(fixture.wakeDisables, 1);
      expect(pause.completed, isFalse);
      wake.complete();
      final HtlcDrainReceipt receipt = await pause.future;
      expect(receipt.owner, same(handler));
      expect(receipt.completed, isTrue);
    },
  );

  test(
    'handler drain waits for the worker original send and notification',
    () async {
      final HtlcFixture fixture = HtlcFixture(329);
      _chain(fixture, 1);
      final Completer<void> notification = Completer<void>();
      fixture.notification = (_) => notification.future;
      final AutoUnlockHtlcWorker worker = AutoUnlockHtlcWorker(
        captureOrigin: fixture.capture,
      );
      addTearDown(() async {
        await worker.pauseAndDrain();
        worker.dispose();
      });
      final HtlcSwapsHandler handler = handlerFor(fixture, worker: worker);
      final HtlcOutcome<void> cycle = HtlcOutcome<void>(handler.runOnce());
      await htlcMicrotasks();
      expect(fixture.notifications.length, 1);
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        handler.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(pause.completed, isFalse);
      notification.complete();
      await cycle.future;
      expect((await pause.future).completed, isTrue);
      expect((await worker.pauseAndDrain()).completed, isTrue);
      expect((await fixture.service.pauseAndDrain()).completed, isTrue);
    },
  );

  testWidgets('terminal pause cancels only its owned five second timer', (
    WidgetTester tester,
  ) async {
    final HtlcFixture fixture = HtlcFixture(330);
    fixture.swaps.entries.clear();
    int captures = 0;
    final HtlcSwapsHandler handler = HtlcSwapsHandler(
      captureOrigin: () {
        captures++;
        return fixture.capture();
      },
    )..start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(captures, 2);
    expect((await handler.pauseAndDrain()).completed, isTrue);
    await tester.pump(const Duration(seconds: 20));
    expect(captures, 2);
    expect(handler.isPaused, isTrue);
    await expectLater(handler.runOnce(), throwsA(isA<HtlcOwnershipRefused>()));
  });

  test(
    'a null pre-RPC origin admits no scan '
    'and preserves incoming lock protection',
    () async {
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () => null,
      );
      await handler.runOnce();
      expect(handler.hasActiveIncomingSwaps, isTrue);
      final HtlcOperationReceipt refusal = handler.operations.single;
      expect(refusal.name, 'handler-origin-unavailable-no-admission');
      expect(refusal.original, isNull);
      expect(refusal.completed, isTrue);
      expect((await handler.pauseAndDrain()).completed, isTrue);
    },
  );
}
