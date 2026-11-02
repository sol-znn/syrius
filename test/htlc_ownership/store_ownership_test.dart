import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';

import 'support.dart';

void main() {
  test(
    'an admitted unresolved original keeps its terminal drain pending',
    () async {
      final Object owner = Object();
      final HtlcOwnedWork work = HtlcOwnedWork(owner);
      final Completer<int> backend = Completer<int>();
      final HtlcOutcome<int> original = HtlcOutcome<int>(
        work.admit<int>('read', () => backend.future),
      );
      final HtlcOutcome<HtlcDrainReceipt> drain = HtlcOutcome<HtlcDrainReceipt>(
        work.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(drain.completed, isFalse);
      expect(work.operations.single.original, same(backend.future));
      expect(
        () => work.reserve('replacement'),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      backend.complete(42);
      expect(await original.future, 42);
      final HtlcDrainReceipt receipt = await drain.future;
      expect(receipt.owner, same(owner));
      expect(receipt.completed, isTrue);
      expect(receipt.operations.single.result, 42);
    },
  );

  test('original errors and traces prevent a positive drain', () async {
    final HtlcOwnedWork work = HtlcOwnedWork(Object());
    final Completer<void> backend = Completer<void>();
    final Object failure = StateError('Synthetic original failure');
    final StackTrace trace = StackTrace.current;
    final HtlcOutcome<void> original = HtlcOutcome<void>(
      work.admit<void>('write', () => backend.future),
    );
    final Future<HtlcDrainReceipt> drain = work.pauseAndDrain();
    backend.completeError(failure, trace);
    await htlcMicrotasks();
    expect(original.error, same(failure));
    expect(work.operations.single.error, same(failure));
    expect(work.operations.single.stackTrace, same(trace));
    expect((await drain).completed, isFalse);
  });

  test('a pre-RPC reservation must settle before cleanup passes', () async {
    final HtlcFixture fixture = HtlcFixture(11);
    final HtlcStoreWriteRequest reserved = fixture.store.reserveWrite();
    final HtlcOutcome<void> close = HtlcOutcome<void>(
      fixture.service.closeBoxes(),
    );
    await htlcMicrotasks();
    expect(close.completed, isFalse);
    expect(fixture.swaps.calls, isEmpty);
    reserved.refuse();
    await close.future;
    expect(fixture.swaps.open, isFalse);
    expect(fixture.cursor.open, isFalse);
  });

  test('an admitted original write survives terminal admission stop', () async {
    final HtlcFixture fixture = HtlcFixture(12);
    final HtlcStoreWriteRequest reserved = fixture.store.reserveWrite();
    final HtlcOutcome<void> close = HtlcOutcome<void>(
      fixture.service.closeBoxes(),
    );
    final HtlcSwap accepted = HtlcSwap.fromJson(fixture.record.toJson())
      ..state = P2pSwapState.completed;
    await reserved.storeSwap(accepted);
    await close.future;
    expect(
      HtlcSwap.fromJson(
        jsonDecode(fixture.swaps.entries[accepted.id] as String),
      ).state,
      P2pSwapState.completed,
    );
    expect(reserved.receipt.completed, isTrue);
  });

  test(
    'writes freeze encoding before awaiting and share one original lane',
    () async {
      final HtlcFixture fixture = HtlcFixture(13);
      fixture.swaps.deferred.add('put');
      final HtlcSwap first = HtlcSwap.fromJson(fixture.record.toJson());
      final HtlcOutcome<void> write1 = HtlcOutcome<void>(
        fixture.store.storeSwap(first),
      );
      first.state = P2pSwapState.completed;
      final HtlcOutcome<void> write2 = HtlcOutcome<void>(
        fixture.store.storeSwap(htlcRecord(14)),
      );
      await htlcMicrotasks();
      expect(
        fixture.swaps.calls.map((MemoryHtlcOperation value) => value.kind),
        <String>['put'],
      );
      final MemoryHtlcOperation original = fixture.swaps.calls.single;
      expect(
        fixture.service.operations
            .firstWhere(
              (HtlcOperationReceipt value) => value.name == 'put-swap',
            )
            .original,
        same(original.reply.future),
      );
      original.complete();
      await htlcMicrotasks();
      expect(write1.completed, isTrue);
      expect(write2.completed, isFalse);
      expect(
        fixture.swaps.calls.map((MemoryHtlcOperation value) => value.kind),
        <String>['put', 'flush', 'put'],
      );
      fixture.swaps.calls.last.complete();
      await write2.future;
      expect(fixture.store.getSwapById(first.id)!.state, P2pSwapState.active);
    },
  );

  test(
    'optimistic cache updates never substitute for the actual flush',
    () async {
      final HtlcFixture fixture = HtlcFixture(15);
      fixture.swaps.optimistic = true;
      fixture.swaps.deferred.add('flush');
      final HtlcOutcome<void> write = HtlcOutcome<void>(
        fixture.store.storeSwap(fixture.record),
      );
      final HtlcOutcome<HtlcDrainReceipt> drain = HtlcOutcome<HtlcDrainReceipt>(
        fixture.service.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(write.completed, isFalse);
      expect(drain.completed, isFalse);
      fixture.swaps.calls
          .singleWhere((MemoryHtlcOperation value) => value.kind == 'flush')
          .complete();
      await write.future;
      expect((await drain.future).completed, isTrue);
    },
  );

  test(
    'a replaced backend receives no continuation or substitute write',
    () async {
      final HtlcFixture fixture = HtlcFixture(16);
      fixture.swaps.deferred.add('put');
      final HtlcOutcome<void> write = HtlcOutcome<void>(
        fixture.store.storeSwap(fixture.record),
      );
      await htlcMicrotasks();
      fixture.owned.remove(fixture.swaps);
      final MemoryHtlcBox replacement = MemoryHtlcBox('replacement-swaps');
      fixture.owned.add(replacement);
      fixture.swaps.calls.single.complete();
      await htlcMicrotasks();
      expect(write.error, isA<HtlcOwnershipRefused>());
      expect(replacement.calls, isEmpty);
      expect(fixture.swaps.calls.length, 1);
      fixture.owned.add(fixture.swaps);
      expect(
        fixture.store.ownsStore,
        isFalse,
        reason: 'Observed replacement cannot be healed by ABA',
      );
      expect((await fixture.service.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'a failed original backend is retained and cannot be closed as clean',
    () async {
      final HtlcFixture fixture = HtlcFixture(17);
      fixture.swaps.deferred.add('put');
      final HtlcOutcome<void> write = HtlcOutcome<void>(
        fixture.store.storeSwap(fixture.record),
      );
      await htlcMicrotasks();
      final Object failure = StateError('Synthetic put failure');
      fixture.swaps.calls.single.fail(failure);
      await htlcMicrotasks();
      expect(write.error, same(failure));
      final HtlcDrainReceipt drain = await fixture.service.pauseAndDrain();
      expect(drain.completed, isFalse);
      expect(
        drain.operations.any(
          (HtlcOperationReceipt value) => identical(value.error, failure),
        ),
        isTrue,
      );
      await expectLater(fixture.service.closeBoxes(), throwsA(same(failure)));
      expect(fixture.swaps.open, isTrue);
    },
  );

  test('a reserved model cannot overwrite a changed original row', () async {
    final HtlcFixture fixture = HtlcFixture(18);
    final HtlcStoreWriteRequest reserved = fixture.store.reserveWrite();
    final HtlcSwap changed = HtlcSwap.fromJson(fixture.record.toJson())
      ..state = P2pSwapState.completed;
    await fixture.store.replaceSwap(fixture.record, changed);
    final int before = fixture.swaps.calls.length;
    await expectLater(
      reserved.storeSwap(fixture.record),
      throwsA(isA<HtlcOwnershipRefused>()),
    );
    expect(fixture.swaps.calls.length, before);
    expect(
      fixture.store.getSwapById(fixture.record.id)!.state,
      P2pSwapState.completed,
    );
  });

  test(
    'positive absence is chain scoped and never rewrites a legacy cursor',
    () async {
      final HtlcFixture fixture = HtlcFixture(19);
      fixture.cursor.entries[kLastCheckedHtlcBlockKey] = 99;
      expect(fixture.store.readCursor().height, 0);
      await expectLater(
        fixture.store.storeCursor(2, htlcHash(300)),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      await fixture.store.storeCursor(1, htlcHash(301));
      expect(fixture.store.readCursor().hash, htlcHash(301));
      expect(fixture.cursor.entries[kLastCheckedHtlcBlockKey], 99);
      expect(
        fixture.service
            .captureStore(chainId: htlcChain + 1)!
            .readCursor()
            .height,
        0,
      );
      await expectLater(
        fixture.store.storeCursor(1, htlcHash(302)),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
    },
  );

  test('an uncertain cursor read cannot become an unscanned zero', () {
    final HtlcFixture fixture = HtlcFixture(20);
    final Object failure = StateError('Synthetic cursor read');
    fixture.cursor.readError = failure;
    expect(fixture.store.readCursor, throwsA(same(failure)));
  });

  test(
    'malformed existing cursor data refuses instead of replaying from zero',
    () {
      final HtlcFixture fixture = HtlcFixture(21);
      fixture.cursor.entries['$kLastCheckedHtlcBlockKey:v2:$htlcChain'] =
          <String, dynamic>{
            'height': 5,
            'chain': htlcChain + 1,
            'hash': htlcHash(1),
          };
      expect(fixture.store.readCursor, throwsA(isA<HtlcOwnershipRefused>()));
    },
  );

  test(
    'delete admission protects the exact terminal record in its serial lane',
    () async {
      final HtlcFixture fixture = HtlcFixture(22);
      fixture.record.state = P2pSwapState.completed;
      fixture.seedRecord(fixture.record);
      fixture.swaps.deferred.add('put');
      final HtlcSwap replacement = HtlcSwap.fromJson(fixture.record.toJson())
        ..state = P2pSwapState.active;
      final HtlcOutcome<void> write = HtlcOutcome<void>(
        fixture.store.storeSwap(replacement),
      );
      final HtlcOutcome<void> deletion = HtlcOutcome<void>(
        fixture.store.deleteIds(<String>[fixture.record.id]),
      );
      await htlcMicrotasks();
      fixture.swaps.calls.single.complete();
      await write.future;
      await htlcMicrotasks();
      expect(deletion.error, isA<HtlcOwnershipRefused>());
      expect(
        fixture.swaps.calls.any(
          (MemoryHtlcOperation value) => value.kind == 'deleteAll',
        ),
        isFalse,
      );
    },
  );

  test(
    'cipher migration refuses before opening or destructive migration',
    () async {
      int opens = 0;
      final HtlcSwapsService service = HtlcSwapsService(
        openBox: (String _, List<int> _) async {
          opens++;
          return MemoryHtlcBox('never-opened');
        },
        ownsBox: (_) => true,
      );
      await expectLater(
        service.openBoxes(
          'synthetic',
          List<int>.filled(32, 1),
          newCipherKey: List<int>.filled(32, 2),
        ),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(opens, 0);
      expect((await service.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'close awaits the exact admitted opening backends and actual closes',
    () async {
      final MemoryHtlcBox swaps = MemoryHtlcBox('synthetic-swaps');
      final MemoryHtlcBox cursor = MemoryHtlcBox('synthetic-cursor');
      final Completer<MemoryHtlcBox> opening = Completer<MemoryHtlcBox>();
      int opens = 0;
      final HtlcSwapsService service = HtlcSwapsService(
        openBox: (String _, List<int> _) {
          return opens++ == 0
              ? opening.future
              : Future<MemoryHtlcBox>.value(cursor);
        },
        ownsBox: (dynamic box) =>
            identical(box, swaps) || identical(box, cursor),
      );
      final HtlcOutcome<void> open = HtlcOutcome<void>(
        service.openBoxes('synthetic', List<int>.filled(32, 1)),
      );
      final HtlcOutcome<void> close = HtlcOutcome<void>(service.closeBoxes());
      await htlcMicrotasks();
      expect(close.completed, isFalse);
      swaps.deferred.add('close');
      opening.complete(swaps);
      await open.future;
      await htlcMicrotasks();
      expect(close.completed, isFalse);
      expect(cursor.open, isTrue);
      swaps.calls
          .singleWhere((MemoryHtlcOperation value) => value.kind == 'close')
          .complete();
      await close.future;
      expect(swaps.open, isFalse);
      expect(cursor.open, isFalse);
    },
  );
}
