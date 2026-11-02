import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_worker_origin.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

AccountBlockTemplate _accepted(
  AccountBlockTemplate block,
  String owner,
  int number,
) => AccountBlockTemplate.fromJson(block.toJson())
  ..address = Address.parse(owner)
  ..hash = Hash.parse(htlcHash(number));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AutoUnlockHtlcWorker workerFor(HtlcFixture fixture) {
    final AutoUnlockHtlcWorker worker = AutoUnlockHtlcWorker(
      captureOrigin: fixture.capture,
    );
    addTearDown(() async {
      await worker.pauseAndDrain();
      worker.dispose();
    });
    return worker;
  }

  test(
    'an original nonselected owned recipient signs without changing selection',
    () async {
      final HtlcFixture fixture = HtlcFixture(201);
      final String originalSelected = fixture.selected;
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      await worker.autoUnlock();
      expect(fixture.signers, <String>[fixture.record.selfAddress]);
      expect(fixture.selected, originalSelected);
      expect(fixture.notifications.length, 1);
      expect(
        fixture.store.hasUnlockHold(
          fixture.record.initialHtlcId,
          fixture.record.selfAddress,
        ),
        isTrue,
      );
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        fixture.record.state,
        reason: 'Publication acceptance does not infer chain completion',
      );
      final HtlcDrainReceipt receipt = await worker.pauseAndDrain();
      expect(receipt.owner, same(worker));
      expect(receipt.completed, isTrue);
    },
  );

  test(
    'a pending original synchronization read keeps terminal pause pending',
    () async {
      final HtlcFixture fixture = HtlcFixture(202);
      final Completer<SyncInfo> sync = Completer<SyncInfo>();
      fixture.syncRead = () => sync.future;
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      final HtlcOutcome<void> enqueue = HtlcOutcome<void>(
        worker.addHash(Hash.parse(fixture.record.initialHtlcId)),
      );
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        worker.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(pause.completed, isFalse);
      sync.complete(fixture.synced());
      await enqueue.future;
      expect((await pause.future).completed, isTrue);
      expect(worker.pool, isEmpty);
      expect(fixture.signers, isEmpty);
      expect((await fixture.service.pauseAndDrain()).completed, isTrue);
    },
  );

  test(
    'known queued work is refused at terminal pause without invoking a signer',
    () async {
      final HtlcFixture fixture = HtlcFixture(203);
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      expect(worker.pool.length, 1);
      expect((await worker.pauseAndDrain()).completed, isTrue);
      await worker.autoUnlock();
      expect(fixture.signers, isEmpty);
      expect((await fixture.service.pauseAndDrain()).completed, isTrue);
    },
  );

  test(
    'fresh source replacement revokes dispatch and retains the original read',
    () async {
      final HtlcFixture fixture = HtlcFixture(204);
      final Completer<HtlcInfo> read = Completer<HtlcInfo>();
      fixture.liveRead = (_) => read.future;
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      final HtlcOutcome<void> operation = HtlcOutcome<void>(
        worker.autoUnlock(),
      );
      await htlcMicrotasks();
      fixture.revision++;
      read.complete(htlcLive(fixture.record, initial: true));
      await htlcMicrotasks();
      expect(operation.error, isA<HtlcOwnershipRefused>());
      expect(fixture.signers, isEmpty);
      final HtlcOperationReceipt original = worker.operations.firstWhere(
        (HtlcOperationReceipt value) => value.name == 'unlock-live-deposit',
      );
      expect(original.original, same(read.future));
      expect(original.result, isA<HtlcInfo>());
      expect((await worker.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'an original RPC failure is retained instead of treated as a spent deposit',
    () async {
      final HtlcFixture fixture = HtlcFixture(205);
      final Completer<HtlcInfo> read = Completer<HtlcInfo>();
      fixture.liveRead = (_) => read.future;
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      final HtlcOutcome<void> operation = HtlcOutcome<void>(
        worker.autoUnlock(),
      );
      await htlcMicrotasks();
      final Object failure = StateError('Synthetic fresh deposit failure');
      read.completeError(failure, StackTrace.current);
      await htlcMicrotasks();
      expect(operation.error, same(failure));
      expect(fixture.signers, isEmpty);
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        fixture.record.state,
      );
      expect((await worker.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'a row replaced during fresh proof '
    'cannot reach the durable claim or signer',
    () async {
      final HtlcFixture fixture = HtlcFixture(206);
      final Completer<int> time = Completer<int>();
      fixture.timeRead = () => time.future;
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      final HtlcOutcome<void> operation = HtlcOutcome<void>(
        worker.autoUnlock(),
      );
      await htlcMicrotasks();
      final HtlcSwap changed = HtlcSwap.fromJson(fixture.record.toJson())
        ..state = P2pSwapState.completed;
      await fixture.store.replaceSwap(fixture.record, changed);
      time.complete(1000);
      await htlcMicrotasks();
      expect(operation.error, isA<HtlcOwnershipRefused>());
      expect(fixture.signers, isEmpty);
      expect(fixture.markers, isEmpty);
    },
  );

  for (final String mismatch in <String>[
    'recipient',
    'lock',
    'key-size',
    'preimage',
  ]) {
    test('fresh $mismatch mismatch refuses before the signer', () async {
      final HtlcFixture fixture = HtlcFixture(
        210 +
            <String>[
              'recipient',
              'lock',
              'key-size',
              'preimage',
            ].indexOf(mismatch),
      );
      if (mismatch == 'preimage') {
        fixture.record.preimage = '00';
        fixture.seedRecord(fixture.record);
      } else {
        fixture.liveRead = (String _) async {
          final HtlcInfo original = htlcLive(fixture.record, initial: true);
          return HtlcInfo(
            id: original.id,
            timeLocked: original.timeLocked,
            hashLocked: mismatch == 'recipient'
                ? Address.parse(htlcOwner(9))
                : original.hashLocked,
            tokenStandard: original.tokenStandard,
            amount: original.amount,
            expirationTime: original.expirationTime,
            hashType: original.hashType,
            keyMaxSize: mismatch == 'key-size' ? 1 : original.keyMaxSize,
            hashLock: mismatch == 'lock'
                ? List<int>.filled(32, 0)
                : original.hashLock,
          );
        };
      }
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      await expectLater(
        worker.autoUnlock(),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(fixture.signers, isEmpty);
      expect(fixture.markers, isEmpty);
    });
  }

  test(
    'an accepted original persists by exact hash after UI source replacement',
    () async {
      final HtlcFixture fixture = HtlcFixture(220);
      final Completer<AccountBlockTemplate> send =
          Completer<AccountBlockTemplate>();
      AccountBlockTemplate? intended;
      String? signer;
      fixture.publication = (AccountBlockTemplate block, String target) {
        intended = block;
        signer = target;
        return send.future;
      };
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      final HtlcOutcome<void> operation = HtlcOutcome<void>(
        worker.autoUnlock(),
      );
      await htlcMicrotasks();
      expect(fixture.signers.length, 1);
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        worker.pauseAndDrain(),
      );
      fixture.revision++;
      final AccountBlockTemplate response = _accepted(
        intended!,
        signer!,
        22220,
      );
      send.complete(response);
      await operation.future;
      expect((await pause.future).completed, isTrue);
      expect(
        (fixture.markers.values.single as Map<dynamic, dynamic>)['hash'],
        htlcHash(22220),
      );
      expect(
        worker.operations
            .firstWhere(
              (HtlcOperationReceipt value) =>
                  value.name == 'unlock-publication',
            )
            .result,
        same(response),
      );
    },
  );

  test(
    'terminal pause awaits notification persistence after acceptance',
    () async {
      final HtlcFixture fixture = HtlcFixture(221);
      final Completer<void> notification = Completer<void>();
      fixture.notification = (_) => notification.future;
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      final HtlcOutcome<void> operation = HtlcOutcome<void>(
        worker.autoUnlock(),
      );
      await htlcMicrotasks();
      expect(fixture.notifications.length, 1);
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        worker.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(pause.completed, isFalse);
      notification.complete();
      await operation.future;
      expect((await pause.future).completed, isTrue);
    },
  );

  test(
    'the exact accepted hash is copied before an asynchronous journal write',
    () async {
      final HtlcFixture fixture = HtlcFixture(225);
      AccountBlockTemplate? response;
      fixture.publication = (AccountBlockTemplate block, String target) async {
        fixture.journal.deferred.add('flush');
        return response = _accepted(block, target, 22225);
      };
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      final HtlcOutcome<void> operation = HtlcOutcome<void>(
        worker.autoUnlock(),
      );
      await htlcMicrotasks();
      expect(response, isNotNull);
      expect(fixture.notifications, isEmpty);
      response!.hash = Hash.parse(htlcHash(99999));
      fixture.journal.calls.last.complete();
      await operation.future;
      expect(
        (fixture.markers.values.single as Map<dynamic, dynamic>)['hash'],
        htlcHash(22225),
      );
      expect(fixture.notifications.single.transactionHash, htlcHash(22225));
    },
  );

  testWidgets(
    'unknown publication never releases on the old two minute interval',
    (WidgetTester tester) async {
      final HtlcFixture fixture = HtlcFixture(222);
      final Object failure = StateError('Synthetic unknown SDK outcome');
      fixture.publication = (_, _) =>
          Future<AccountBlockTemplate>.error(failure);
      final AutoUnlockHtlcWorker worker = AutoUnlockHtlcWorker(
        captureOrigin: fixture.capture,
      );
      AutoUnlockHtlcWorker? remounted;
      try {
        final HtlcOutcome<void> enqueue = HtlcOutcome<void>(
          worker.addHash(Hash.parse(fixture.record.initialHtlcId)),
        );
        await pumpHtlcUntil(tester, () => enqueue.completed);
        expect(enqueue.error, isNull);
        final HtlcOutcome<void> publication = HtlcOutcome<void>(
          worker.autoUnlock(),
        );
        await pumpHtlcUntil(tester, () => publication.completed);
        expect(publication.error, same(failure));
        final int originalSyncs = fixture.syncCalls;
        await tester.pump(const Duration(minutes: 3));
        final AutoUnlockHtlcWorker replacement = AutoUnlockHtlcWorker(
          captureOrigin: fixture.capture,
        );
        remounted = replacement;
        final HtlcOutcome<void> reenqueue = HtlcOutcome<void>(
          replacement.addHash(Hash.parse(fixture.record.initialHtlcId)),
        );
        await pumpHtlcUntil(tester, () => reenqueue.completed);
        expect(reenqueue.error, isNull);
        final HtlcOutcome<void> redrain = HtlcOutcome<void>(
          replacement.autoUnlock(),
        );
        await pumpHtlcUntil(tester, () => redrain.completed);
        expect(redrain.error, isNull);
        expect(fixture.signers.length, 1);
        expect(fixture.syncCalls, originalSyncs);
        expect(
          (fixture.markers.values.single as Map<dynamic, dynamic>)['status'],
          'publishing',
        );
      } finally {
        final HtlcOutcome<HtlcDrainReceipt> pause =
            HtlcOutcome<HtlcDrainReceipt>(
              worker.pauseAndDrain(),
            );
        final AutoUnlockHtlcWorker? replacement = remounted;
        final HtlcOutcome<HtlcDrainReceipt>? remountedPause =
            replacement == null
            ? null
            : HtlcOutcome<HtlcDrainReceipt>(replacement.pauseAndDrain());
        try {
          await pumpHtlcUntil(
            tester,
            () => pause.completed && (remountedPause?.completed ?? true),
          );
          expect(pause.error, isNull);
          expect(pause.result!.owner, same(worker));
          expect(pause.result!.completed, isFalse);
          expect(pause.result!.error, same(failure));
          if (remountedPause != null) {
            expect(remountedPause.error, isNull);
            expect(remountedPause.result!.owner, same(replacement));
            expect(remountedPause.result!.completed, isTrue);
          }
        } finally {
          worker.dispose();
          replacement?.dispose();
        }
      }
    },
  );

  test(
    'durable acceptance alone suppresses an automatic remount retry',
    () async {
      final HtlcFixture fixture = HtlcFixture(223);
      final HtlcUnlockWriteRequest reservation = fixture.store.reserveUnlock(
        fixture.record.initialHtlcId,
        fixture.record.selfAddress,
      );
      expect(await reservation.claim(), isTrue);
      await reservation.accept(htlcHash(888));
      final AutoUnlockHtlcWorker worker = workerFor(fixture);
      await worker.addHash(Hash.parse(fixture.record.initialHtlcId));
      await worker.autoUnlock();
      expect(fixture.syncCalls, 0);
      expect(fixture.signers, isEmpty);
    },
  );

  test(
    'an absent injected capability cannot fall back to current globals',
    () async {
      final AutoUnlockHtlcWorker worker = AutoUnlockHtlcWorker(
        captureOrigin: () => null,
      );
      addTearDown(worker.dispose);
      await expectLater(
        worker.addHash(Hash.parse(htlcHash(224))),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(worker.operations, isEmpty);
      expect((await worker.pauseAndDrain()).completed, isTrue);
    },
  );

  test('a returning worker proof retains nested revocation before work', () {
    final HtlcFixture fixture = HtlcFixture(240);
    bool current = true;
    bool reenter = false;
    final List<bool> nested = <bool>[];
    late final HtlcWorkerOrigin origin;
    origin = fixture.capture(
      sourceIsCurrent: () {
        final bool accepted = current;
        if (reenter) {
          reenter = false;
          current = false;
          nested.add(origin.isCurrent);
          current = true;
        }
        return accepted;
      },
    );
    expect(origin.isCurrent, isTrue);
    reenter = true;
    expect(origin.isCurrent, isFalse);
    expect(nested, <bool>[false]);
    expect(current, isTrue);
    expect(origin.isCurrent, isFalse);
    expect(origin.requireCurrent, throwsA(isA<HtlcOwnershipRefused>()));
    expect(fixture.syncCalls, 0);
    expect(fixture.liveReads, isEmpty);
    expect(fixture.blockReads, isEmpty);
    expect(fixture.signers, isEmpty);
    expect(fixture.swaps.calls, isEmpty);
    expect(fixture.cursor.calls, isEmpty);
  });

  for (final String axis in <String>[
    'wallet',
    'api',
    'transport',
    'path',
    'url',
    'revision',
    'selected',
    'members',
  ]) {
    test('observed $axis replacement cannot recover by ABA', () {
      final HtlcFixture fixture = HtlcFixture(
        230 +
            <String>[
              'wallet',
              'api',
              'transport',
              'path',
              'url',
              'revision',
              'selected',
              'members',
            ].indexOf(axis),
      );
      final HtlcWorkerOrigin original = fixture.capture();
      final Object wallet = fixture.wallet;
      final Object api = fixture.api;
      final Object transport = fixture.transport;
      final String path = fixture.path;
      final String url = fixture.url;
      final String selected = fixture.selected;
      final int revision = fixture.revision;
      if (axis == 'wallet') fixture.wallet = Object();
      if (axis == 'api') fixture.api = Object();
      if (axis == 'transport') fixture.transport = Object();
      if (axis == 'path') fixture.path = 'replacement';
      if (axis == 'url') fixture.url = 'replacement';
      if (axis == 'revision') fixture.revision++;
      if (axis == 'selected') fixture.selected = htlcOwner(1);
      if (axis == 'members') fixture.members.removeLast();
      expect(original.isCurrent, isFalse);
      fixture
        ..wallet = wallet
        ..api = api
        ..transport = transport
        ..path = path
        ..url = url
        ..selected = selected
        ..revision = revision
        ..members.clear()
        ..members.addAll(<String>[htlcOwner(1), htlcOwner(3)]);
      expect(original.isCurrent, isFalse);
      expect(fixture.syncCalls, 0);
    });
  }
}
