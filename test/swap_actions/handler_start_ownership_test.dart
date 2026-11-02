import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../htlc_ownership/support.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reservation does not tick '
    'and activation waits for the caller synchronous commit',
    () async {
      final HtlcFixture fixture = HtlcFixture(401)..swaps.entries.clear();
      bool committed = false;
      int captures = 0;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          expect(committed, isTrue);
          return fixture.capture();
        },
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => true,
      )!;
      expect(reservation.identity, same(handler));
      expect(reservation.canActivate, isTrue);
      expect(captures, 0);
      expect(handler.hasStarted, isFalse);
      expect(handler.reserveStart(isCurrent: () => true), isNull);
      expect(reservation.activate(), isTrue);
      expect(captures, 0);
      expect(handler.hasStarted, isTrue);
      expect(reservation.startup!.completed, isFalse);
      committed = true;
      await microtasksUntil(() => reservation.startup!.completed);
      expect(captures, 1);
      expect(reservation.startup!.error, isNull);
      expect(reservation.activate(), isFalse);
      expect((await handler.pauseAndDrain()).completed, isTrue);
    },
  );

  test(
    'an observed startup source departure cannot be revived by ABA',
    () async {
      bool current = true;
      int captures = 0;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          return null;
        },
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => current,
      )!;
      current = false;
      expect(reservation.canActivate, isFalse);
      current = true;
      expect(reservation.activate(), isFalse);
      expect(handler.hasStarted, isFalse);
      expect(captures, 0);
      expect((await handler.pauseAndDrain()).completed, isTrue);
    },
  );

  test(
    'activation consumes before a source callback can reenter the same token',
    () async {
      final HtlcFixture fixture = HtlcFixture(405)..swaps.entries.clear();
      int captures = 0;
      bool reenter = false;
      final List<bool> nested = <bool>[];
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          return fixture.capture();
        },
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      late final HtlcHandlerStart reservation;
      reservation = handler.reserveStart(
        isCurrent: () {
          if (reenter) {
            reenter = false;
            nested.add(reservation.activate());
          }
          return true;
        },
      )!;
      reenter = true;
      expect(reservation.activate(), isTrue);
      expect(nested, <bool>[false]);
      expect(captures, 0);
      expect(reservation.canActivate, isFalse);
      await microtasksUntil(() => reservation.startup!.completed);
      expect(captures, 1);
      expect(
        handler.operations
            .where(
              (HtlcOperationReceipt operation) =>
                  operation.name == 'handler-cycle',
            )
            .length,
        1,
      );
      expect(reservation.activate(), isFalse);
      expect((await handler.pauseAndDrain()).completed, isTrue);
    },
  );

  test('a returning startup proof cannot erase nested refusal', () async {
    bool current = true;
    bool reenter = false;
    int captures = 0;
    final List<bool> nested = <bool>[];
    final HtlcSwapsHandler handler = HtlcSwapsHandler(
      captureOrigin: () {
        captures++;
        return null;
      },
    );
    addTearDown(() async {
      await handler.pauseAndDrain();
    });
    late final HtlcHandlerStart reservation;
    reservation = handler.reserveStart(
      isCurrent: () {
        final bool accepted = current;
        if (reenter) {
          reenter = false;
          current = false;
          nested.add(reservation.canActivate);
          current = true;
        }
        return accepted;
      },
    )!;
    expect(reservation.canActivate, isTrue);
    reenter = true;
    expect(reservation.canActivate, isFalse);
    expect(nested, <bool>[false]);
    expect(current, isTrue);
    expect(reservation.canActivate, isFalse);
    expect(reservation.activate(), isFalse);
    expect(handler.hasStarted, isFalse);
    expect(handler.operations, isEmpty);
    expect(captures, 0);
    expect((await handler.pauseAndDrain()).completed, isTrue);
  });

  test(
    'terminal pause before the deferred first tick never dispatches',
    () async {
      int captures = 0;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          return null;
        },
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => true,
      )!;
      expect(reservation.activate(), isTrue);
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        handler.pauseAndDrain(),
      );
      expect(reservation.startup!.completed, isFalse);
      await htlcMicrotasks();
      expect(captures, 0);
      expect(reservation.startup!.error, isA<HtlcOwnershipRefused>());
      expect((await pause.future).completed, isFalse);
      expect(handler.reserveStart(isCurrent: () => true), isNull);
    },
  );

  test(
    'loss during the synchronous commit retains deferred startup uncertainty',
    () async {
      bool current = true;
      int captures = 0;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          return null;
        },
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => current,
      )!;
      expect(reservation.activate(), isTrue);
      current = false;
      await microtasksUntil(() => reservation.startup!.completed);
      expect(captures, 0);
      expect(reservation.error, isA<HtlcOwnershipRefused>());
      expect((await handler.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'a thrown original startup has its exact error and trace in the drain',
    () async {
      final Object failure = StateError('Synthetic original startup');
      final StackTrace trace = StackTrace.current;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          Error.throwWithStackTrace(failure, trace);
        },
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => true,
      )!;
      expect(reservation.activate(), isTrue);
      await microtasksUntil(() => reservation.startup!.completed);
      expect(reservation.error, same(failure));
      expect(reservation.stackTrace, same(trace));
      final HtlcDrainReceipt drain = await handler.pauseAndDrain();
      expect(drain.completed, isFalse);
      expect(drain.error, same(failure));
    },
  );

  testWidgets(
    'a null first origin admits no scan '
    'and the same wallet later starts its ordinary cycle',
    (WidgetTester tester) async {
      final HtlcFixture fixture = HtlcFixture(406);
      fixture
        ..record = htlcRecord(406, direction: P2pSwapDirection.outgoing)
        ..seedRecord(fixture.record)
        ..blocks.add(htlcBlock());
      bool available = false;
      int captures = 0;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          return available ? fixture.capture() : null;
        },
      );
      try {
        final HtlcHandlerStart reservation = handler.reserveStart(
          isCurrent: () => true,
        )!;
        expect(reservation.activate(), isTrue);
        await tester.pump();
        await pumpHtlcUntil(tester, () => reservation.startup!.completed);
        expect(captures, 1);
        expect(reservation.startup!.completed, isTrue);
        expect(reservation.startup!.error, isNull);
        expect(handler.hasActiveIncomingSwaps, isTrue);
        expect(fixture.syncCalls, 0);
        expect(fixture.pages, isEmpty);
        expect(fixture.store.readCursor().height, 0);
        expect(fixture.cursor.calls, isEmpty);
        expect(fixture.swaps.calls, isEmpty);
        final HtlcOperationReceipt unavailable = handler.operations.singleWhere(
          (HtlcOperationReceipt operation) =>
              operation.name == 'handler-origin-unavailable-no-admission',
        );
        expect(unavailable.original, isNull);
        expect(unavailable.completed, isTrue);
        expect(
          handler.operations.where(
            (HtlcOperationReceipt operation) =>
                operation.name == 'handler-cycle',
          ),
          isEmpty,
        );
        available = true;
        await tester.pump(const Duration(seconds: 5));
        await pumpHtlcUntil(
          tester,
          () => handler.operations.any(
            (HtlcOperationReceipt operation) =>
                operation.name == 'handler-cycle' && operation.completed,
          ),
        );
        expect(captures, 2);
        expect(fixture.syncCalls, 1);
        expect(fixture.pages, <(int, int)>[(1, 1)]);
        expect(fixture.store.readCursor().height, 1);
        expect(handler.hasActiveIncomingSwaps, isFalse);
        expect(
          handler.operations
              .where(
                (HtlcOperationReceipt operation) =>
                    operation.name == 'handler-cycle',
              )
              .length,
          1,
        );
      } finally {
        final HtlcOutcome<HtlcDrainReceipt> pause =
            HtlcOutcome<HtlcDrainReceipt>(
              handler.pauseAndDrain(),
            );
        await pumpHtlcUntil(tester, () => pause.completed);
        expect(pause.error, isNull);
        expect(pause.result!.owner, same(handler));
        expect(pause.result!.completed, isTrue);
      }
    },
  );

  test(
    'a known null-origin refusal restores protection '
    'without poisoning terminal drain',
    () async {
      final HtlcFixture fixture = HtlcFixture(407)..swaps.entries.clear();
      bool available = true;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () => available ? fixture.capture() : null,
      );
      addTearDown(() async {
        await handler.pauseAndDrain();
      });
      await handler.runOnce();
      expect(handler.hasActiveIncomingSwaps, isFalse);
      available = false;
      await handler.runOnce();
      expect(handler.hasActiveIncomingSwaps, isTrue);
      expect(fixture.syncCalls, 0);
      expect(fixture.cursor.calls, isEmpty);
      expect(fixture.swaps.calls, isEmpty);
      final HtlcDrainReceipt drain = await handler.pauseAndDrain();
      expect(drain.completed, isTrue);
      expect(
        drain.operations
            .where(
              (HtlcOperationReceipt operation) =>
                  operation.name == 'handler-origin-unavailable-no-admission',
            )
            .single
            .original,
        isNull,
      );
    },
  );

  testWidgets(
    'a real original RPC failure after a null first origin '
    'remains a failed drain',
    (WidgetTester tester) async {
      final HtlcFixture fixture = HtlcFixture(408);
      fixture
        ..record = htlcRecord(408, direction: P2pSwapDirection.outgoing)
        ..seedRecord(fixture.record);
      final Object failure = StateError('Synthetic original admitted sync');
      final StackTrace trace = StackTrace.current;
      fixture.syncRead = () => Future<SyncInfo>.error(failure, trace);
      bool available = false;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () => available ? fixture.capture() : null,
      );
      try {
        final HtlcHandlerStart reservation = handler.reserveStart(
          isCurrent: () => true,
        )!;
        expect(reservation.activate(), isTrue);
        await tester.pump();
        await pumpHtlcUntil(tester, () => reservation.startup!.completed);
        expect(fixture.syncCalls, 0);
        available = true;
        await tester.pump(const Duration(seconds: 5));
        await pumpHtlcUntil(
          tester,
          () => handler.operations.any(
            (HtlcOperationReceipt operation) =>
                operation.name == 'handler-cycle' && operation.completed,
          ),
        );
        expect(fixture.syncCalls, 1);
        expect(fixture.store.readCursor().height, 0);
      } finally {
        final HtlcOutcome<HtlcDrainReceipt> pause =
            HtlcOutcome<HtlcDrainReceipt>(
              handler.pauseAndDrain(),
            );
        await pumpHtlcUntil(tester, () => pause.completed);
        expect(pause.error, isNull);
        final HtlcDrainReceipt drain = pause.result!;
        expect(drain.owner, same(handler));
        expect(drain.completed, isFalse);
        expect(drain.error, same(failure));
        expect(drain.stackTrace, same(trace));
      }
    },
  );

  test(
    'the actual first-cycle Future holds terminal drain '
    'until its original read settles',
    () async {
      final ActionFixture leases = ActionFixture();
      final HtlcFixture fixture = HtlcFixture(402);
      fixture
        ..record = htlcRecord(402, direction: P2pSwapDirection.outgoing)
        ..seedRecord(fixture.record)
        ..blocks.add(htlcBlock());
      final Completer<SyncInfo> read = leases.ownCompleter<SyncInfo>();
      fixture.syncRead = () => read.future;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: fixture.capture,
      );
      addTearDown(() async {
        await leases.close();
        await handler.pauseAndDrain();
      });
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => true,
      )!;
      expect(reservation.activate(), isTrue);
      await microtasksUntil(() => fixture.syncCalls == 1);
      expect(reservation.startup!.original, same(handler.runOnce()));
      final HtlcOutcome<HtlcDrainReceipt> pause = HtlcOutcome<HtlcDrainReceipt>(
        handler.pauseAndDrain(),
      );
      await htlcMicrotasks();
      expect(pause.completed, isFalse);
      read.complete(fixture.synced());
      expect((await pause.future).completed, isTrue);
      expect(reservation.startup!.completed, isTrue);
    },
  );

  test(
    'manual cycles, an already started owner '
    'and a paused owner are not pristine',
    () async {
      final HtlcFixture fixture = HtlcFixture(403)..swaps.entries.clear();
      final HtlcSwapsHandler cycled = HtlcSwapsHandler(
        captureOrigin: fixture.capture,
      );
      addTearDown(() async {
        await cycled.pauseAndDrain();
      });
      await cycled.runOnce();
      expect(cycled.hasStarted, isFalse);
      expect(cycled.reserveStart(isCurrent: () => true), isNull);
      await cycled.pauseAndDrain();
      final HtlcSwapsHandler started = HtlcSwapsHandler(
        captureOrigin: fixture.capture,
      );
      addTearDown(() async {
        await started.pauseAndDrain();
      });
      started.start();
      expect(started.reserveStart(isCurrent: () => true), isNull);
      await started.pauseAndDrain();
      final HtlcSwapsHandler paused = HtlcSwapsHandler();
      await paused.pauseAndDrain();
      expect(paused.reserveStart(isCurrent: () => true), isNull);
    },
  );

  testWidgets(
    'the original five-second timer stops admitting '
    'after its reserved wallet source departs',
    (WidgetTester tester) async {
      final HtlcFixture fixture = HtlcFixture(404)..swaps.entries.clear();
      bool current = true;
      int captures = 0;
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          captures++;
          return fixture.capture();
        },
      );
      try {
        final HtlcHandlerStart reservation = handler.reserveStart(
          isCurrent: () => current,
        )!;
        expect(reservation.activate(), isTrue);
        await tester.pump();
        await pumpHtlcUntil(tester, () => reservation.startup!.completed);
        expect(reservation.startup!.completed, isTrue);
        expect(captures, 1);
        current = false;
        await tester.pump(const Duration(seconds: 5));
        expect(captures, 1);
        current = true;
        final HtlcOutcome<void> refused = HtlcOutcome<void>(handler.runOnce());
        await pumpHtlcUntil(tester, () => refused.completed);
        expect(refused.error, isA<HtlcOwnershipRefused>());
        expect(captures, 1);
      } finally {
        final HtlcOutcome<HtlcDrainReceipt> pause =
            HtlcOutcome<HtlcDrainReceipt>(
              handler.pauseAndDrain(),
            );
        await pumpHtlcUntil(tester, () => pause.completed);
        expect(pause.error, isNull);
        expect(pause.result!.owner, same(handler));
        expect(pause.result!.completed, isTrue);
      }
    },
  );
}
