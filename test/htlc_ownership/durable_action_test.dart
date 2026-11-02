import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  test(
    'prepublication recovery is frozen privately '
    'and flushed before prepare returns',
    () async {
      final HtlcFixture fixture = HtlcFixture(101);
      fixture.journal.deferred.add('flush');
      final Map<String, dynamic> recovery = htlcRecovery(fixture.record);
      final String originalValue = recovery['preimage'] as String;
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'start',
        targetId: 'new',
        owner: fixture.record.selfAddress,
      );
      final HtlcOutcome<void> prepared = HtlcOutcome<void>(
        request.prepare(recovery: recovery),
      );
      recovery['preimage'] = 'changed';
      await htlcMicrotasks();
      expect(prepared.completed, isFalse);
      final Map<dynamic, dynamic> marker =
          fixture.markers.values.single as Map<dynamic, dynamic>;
      expect(
        (marker['recovery'] as Map<dynamic, dynamic>)['preimage'],
        originalValue,
      );
      fixture.journal.calls.last.complete();
      await prepared.future;
      fixture.journal.deferred.clear();
      await request.refuseBeforePublication();
      expect(fixture.markers, isEmpty);
    },
  );

  test(
    'an existing publishing marker survives remount '
    'and refuses another signer call',
    () async {
      final HtlcFixture fixture = HtlcFixture(102);
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'join',
        targetId: fixture.record.initialHtlcId,
        owner: fixture.record.selfAddress,
      );
      await request.prepare();
      final Object originalError = StateError('Synthetic unknown publication');
      request.retainUnknown(originalError, StackTrace.current);
      await htlcMicrotasks();
      expect(request.receipt.error, same(originalError));
      final HtlcSwapsService remounted = HtlcSwapsService.bound(
        swaps: fixture.swaps,
        cursor: fixture.cursor,
        ownsBox: fixture.owned.contains,
      );
      final HtlcActionWriteRequest retry = remounted
          .captureStore(chainId: htlcChain)!
          .reserveAction(
            kind: 'join',
            targetId: fixture.record.initialHtlcId,
            owner: fixture.record.selfAddress,
          );
      await expectLater(retry.prepare(), throwsA(isA<HtlcOwnershipRefused>()));
      await retry.refuseBeforePublication();
      expect(
        (fixture.markers.values.single as Map<dynamic, dynamic>)['status'],
        'publishing',
      );
      expect((await fixture.service.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'accepted exact hashes retain the original marker '
    'and reject clearing as refusal',
    () async {
      final HtlcFixture fixture = HtlcFixture(103);
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'complete',
        targetId: fixture.record.initialHtlcId,
        owner: fixture.record.selfAddress,
      );
      await request.prepare();
      await request.accepted(htlcHash(333));
      final Map<dynamic, dynamic> marker =
          fixture.markers.values.single as Map<dynamic, dynamic>;
      expect(marker['hash'], htlcHash(333));
      expect(marker['status'], 'accepted');
      await expectLater(
        request.refuseBeforePublication(),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(fixture.markers.values.single, equals(marker));
    },
  );

  test(
    'known prepublication refusal waits for actual prepare and clear futures',
    () async {
      final HtlcFixture fixture = HtlcFixture(104);
      fixture.journal.deferred.add('put');
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'recover',
        targetId: fixture.record.initialHtlcId,
        owner: fixture.record.selfAddress,
      );
      final HtlcOutcome<void> preparation = HtlcOutcome<void>(
        request.prepare(),
      );
      final HtlcOutcome<void> refusal = HtlcOutcome<void>(
        request.refuseBeforePublication(),
      );
      final HtlcOutcome<HtlcDrainReceipt> drain = HtlcOutcome<HtlcDrainReceipt>(
        fixture.service.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(refusal.completed, isFalse);
      expect(drain.completed, isFalse);
      fixture.journal.calls.single.complete();
      await preparation.future;
      await refusal.future;
      expect((await drain.future).completed, isTrue);
      expect(fixture.markers, isEmpty);
    },
  );

  test(
    'unknown retention during a pending prepare cannot claim an early drain',
    () async {
      final HtlcFixture fixture = HtlcFixture(105);
      fixture.journal.deferred.add('put');
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'reclaim',
        targetId: fixture.record.initialHtlcId,
        owner: fixture.record.selfAddress,
      );
      final HtlcOutcome<void> preparation = HtlcOutcome<void>(
        request.prepare(),
      );
      final Object failure = StateError('Synthetic retained uncertainty');
      request.retainUnknown(failure, StackTrace.current);
      final HtlcOutcome<HtlcDrainReceipt> drain = HtlcOutcome<HtlcDrainReceipt>(
        fixture.service.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(drain.completed, isFalse);
      fixture.journal.calls.single.complete();
      await preparation.future;
      final HtlcDrainReceipt receipt = await drain.future;
      expect(receipt.completed, isFalse);
      expect(request.receipt.error, same(failure));
      expect(
        (fixture.markers.values.single as Map<dynamic, dynamic>)['status'],
        'publishing',
      );
    },
  );

  test(
    'failed original prepare remains unproven '
    'even with optimistic marker visibility',
    () async {
      final HtlcFixture fixture = HtlcFixture(106);
      fixture.journal.optimistic = true;
      fixture.journal.deferred.add('put');
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'start',
        targetId: 'new',
        owner: fixture.record.selfAddress,
      );
      final HtlcOutcome<void> preparation = HtlcOutcome<void>(
        request.prepare(recovery: htlcRecovery(fixture.record)),
      );
      await htlcMicrotasks();
      final Object failure = StateError('Synthetic durable write failure');
      fixture.journal.calls.single.fail(failure);
      await htlcMicrotasks();
      expect(preparation.error, same(failure));
      await expectLater(
        request.refuseBeforePublication(),
        throwsA(same(failure)),
      );
      expect(fixture.markers, isNotEmpty);
      expect((await fixture.service.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'a replaced publishing marker is never overwritten with acceptance',
    () async {
      final HtlcFixture fixture = HtlcFixture(107);
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'join',
        targetId: fixture.record.initialHtlcId,
        owner: fixture.record.selfAddress,
      );
      await request.prepare();
      final dynamic key = fixture.markers.keys.single;
      final String replacement = jsonEncode(<dynamic, dynamic>{
        ...(fixture.markers[key] as Map<dynamic, dynamic>),
        'claim': 'replacement',
      });
      fixture.journal.entries[key] = replacement;
      await expectLater(
        request.accepted(htlcHash(400)),
        throwsA(isA<HtlcOwnershipRefused>()),
      );
      expect(fixture.journal.entries[key], replacement);
    },
  );

  test(
    'new deposit requires the exact saved accepted original '
    'and works after it is spent',
    () async {
      final HtlcFixture fixture = HtlcFixture(108);
      fixture
        ..record = htlcRecord(
          108,
          direction: P2pSwapDirection.outgoing,
          state: P2pSwapState.completed,
        )
        ..seedRecord(fixture.record);
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'start',
        targetId: 'new',
        owner: fixture.record.selfAddress,
      );
      await request.prepare(recovery: htlcRecovery(fixture.record));
      await request.accepted(fixture.record.initialHtlcId);
      expect(
        () => fixture.store.deleteIds(<String>[fixture.record.id]),
        throwsA(isA<HtlcOwnershipRefused>()),
        reason: 'The original recovery anchor must remain available',
      );
      expect(
        await fixture.store.rearmStart(
          owner: fixture.record.selfAddress,
          creation: htlcCreate(fixture.record, initial: true),
        ),
        isTrue,
      );
      expect(fixture.markers, isEmpty);
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.completed,
      );
      await fixture.store.deleteIds(<String>[fixture.record.id]);
      expect(fixture.store.readAll(), isEmpty);
    },
  );

  test(
    'only typed private metadata is omitted from a complete history catalogue',
    () async {
      final HtlcFixture fixture = HtlcFixture(112);
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'start',
        targetId: 'new',
        owner: fixture.record.selfAddress,
      );
      await request.prepare(recovery: htlcRecovery(fixture.record));
      expect(fixture.swaps.length, 2);
      expect(fixture.store.readAll().single.id, fixture.record.id);
      final dynamic key = fixture.markers.keys.single;
      expect(
        fixture.store.isHistoryEntry(key as String, fixture.swaps.entries[key]),
        isFalse,
      );
      expect(
        fixture.cursor.entries,
        isEmpty,
        reason: 'Disposable checkpoint cache cannot contain private recovery',
      );
      await request.refuseBeforePublication();
      fixture.swaps.entries['_htlc-private:v1:unknown'] = jsonEncode(
        <String, dynamic>{'kind': 'unknown'},
      );
      expect(fixture.store.readAll, throwsA(isA<HtlcOwnershipRefused>()));
    },
  );

  test(
    'absence, wrong exact hash and mismatched optional live proof '
    'leave start held',
    () async {
      final HtlcFixture fixture = HtlcFixture(109);
      fixture
        ..record = htlcRecord(109, direction: P2pSwapDirection.outgoing)
        ..seedRecord(fixture.record);
      final HtlcActionWriteRequest request = fixture.store.reserveAction(
        kind: 'start',
        targetId: 'new',
        owner: fixture.record.selfAddress,
      );
      await request.prepare(recovery: htlcRecovery(fixture.record));
      await request.accepted(fixture.record.initialHtlcId);
      final AccountBlock wrong = htlcCreate(fixture.record, initial: true)
        ..hash = Hash.parse(htlcHash(999));
      expect(
        await fixture.store.rearmStart(
          owner: fixture.record.selfAddress,
          creation: wrong,
        ),
        isFalse,
      );
      final HtlcInfo mismatch = htlcLive(
        fixture.record,
        initial: true,
        keySize: 1,
      );
      expect(
        await fixture.store.rearmStart(
          owner: fixture.record.selfAddress,
          creation: htlcCreate(fixture.record, initial: true),
          deposit: mismatch,
        ),
        isFalse,
      );
      fixture.swaps.entries.remove(fixture.record.id);
      expect(
        await fixture.store.rearmStart(
          owner: fixture.record.selfAddress,
          creation: htlcCreate(fixture.record, initial: true),
        ),
        isFalse,
      );
      expect(fixture.markers, isNotEmpty);
    },
  );

  test(
    'a durable unlock hold has no time release and survives a new store owner',
    () async {
      final HtlcFixture fixture = HtlcFixture(110);
      final HtlcUnlockWriteRequest request = fixture.store.reserveUnlock(
        fixture.record.initialHtlcId,
        fixture.record.selfAddress,
      );
      expect(await request.claim(), isTrue);
      await request.accept(htlcHash(900));
      final HtlcSwapsService replacement = HtlcSwapsService.bound(
        swaps: fixture.swaps,
        cursor: fixture.cursor,
        ownsBox: fixture.owned.contains,
      );
      final HtlcStoreCapture captured = replacement.captureStore(
        chainId: htlcChain,
      )!;
      expect(
        captured.hasUnlockHold(
          fixture.record.initialHtlcId,
          fixture.record.selfAddress,
        ),
        isTrue,
      );
      final HtlcUnlockWriteRequest retry = captured.reserveUnlock(
        fixture.record.initialHtlcId,
        fixture.record.selfAddress,
      );
      expect(await retry.claim(), isFalse);
      retry.refuse();
      expect(
        (fixture.markers.values.single as Map<dynamic, dynamic>)['hash'],
        htlcHash(900),
      );
    },
  );

  test(
    'manual withdrawal cannot bypass an automatic publishing hold',
    () async {
      final HtlcFixture fixture = HtlcFixture(113);
      final HtlcUnlockWriteRequest automatic = fixture.store.reserveUnlock(
        fixture.record.initialHtlcId,
        fixture.record.selfAddress,
      );
      expect(await automatic.claim(), isTrue);
      automatic.retainUnknown(
        StateError('Synthetic unknown automatic publication'),
        StackTrace.current,
      );
      final HtlcActionWriteRequest manual = fixture.store.reserveAction(
        kind: 'complete',
        targetId: fixture.record.initialHtlcId,
        owner: fixture.record.selfAddress,
      );
      await expectLater(manual.prepare(), throwsA(isA<HtlcOwnershipRefused>()));
      await manual.refuseBeforePublication();
      expect(fixture.markers.length, 1);
      expect(
        (fixture.markers.values.single as Map<dynamic, dynamic>)['status'],
        'publishing',
      );
    },
  );

  test('automatic withdrawal cannot bypass an accepted manual claim', () async {
    final HtlcFixture fixture = HtlcFixture(114);
    final HtlcActionWriteRequest manual = fixture.store.reserveAction(
      kind: 'complete',
      targetId: fixture.record.initialHtlcId,
      owner: fixture.record.selfAddress,
    );
    await manual.prepare();
    await manual.accepted(htlcHash(911));
    final HtlcUnlockWriteRequest automatic = fixture.store.reserveUnlock(
      fixture.record.initialHtlcId,
      fixture.record.selfAddress,
    );
    expect(await automatic.claim(), isFalse);
    automatic.refuse();
    expect(fixture.markers.length, 1);
    expect(
      (fixture.markers.values.single as Map<dynamic, dynamic>)['hash'],
      htlcHash(911),
    );
  });

  test(
    'pending unlock claim retains its actual future before an unknown drain',
    () async {
      final HtlcFixture fixture = HtlcFixture(111);
      fixture.journal.deferred.add('flush');
      final HtlcUnlockWriteRequest request = fixture.store.reserveUnlock(
        fixture.record.initialHtlcId,
        fixture.record.selfAddress,
      );
      final HtlcOutcome<bool> claim = HtlcOutcome<bool>(request.claim());
      request.retainUnknown(
        StateError('Synthetic unlock uncertainty'),
        StackTrace.current,
      );
      final HtlcOutcome<HtlcDrainReceipt> drain = HtlcOutcome<HtlcDrainReceipt>(
        fixture.service.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(drain.completed, isFalse);
      fixture.journal.calls.last.complete();
      expect(await claim.future, isTrue);
      expect((await drain.future).completed, isFalse);
      expect(
        fixture.store.hasUnlockHold(
          fixture.record.initialHtlcId,
          fixture.record.selfAddress,
        ),
        isTrue,
      );
    },
  );
}
