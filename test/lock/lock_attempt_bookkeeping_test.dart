import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_tab_child.dart';

void main() {
  test(
    'a failed notice persists a refused password before exhaustion',
    () async {
      int count = 2;
      int writes = 0;
      bool persisted = false;
      await recordLockFailure(
        incorrectPassword: true,
        notify: () async => throw StateError('Optional notice unavailable'),
        recordFailedAttempt: () async {
          writes += 1;
          count += 1;
          persisted = true;
        },
      );
      expect(count, 3);
      expect(writes, 1);
      expect(persisted, isTrue);
      // The owner can now apply its unchanged global exhaustion comparison.
      expect(count == 3, isTrue);
    },
  );

  test(
    'a synchronous notice failure cannot skip attempt persistence',
    () async {
      int writes = 0;
      await recordLockFailure(
        incorrectPassword: true,
        notify: () => throw StateError('Optional notice unavailable'),
        recordFailedAttempt: () async {
          writes += 1;
        },
      );
      expect(writes, 1);
    },
  );

  test(
    'a non-password refusal never consumes an attempt when its notice fails',
    () async {
      int writes = 0;
      await recordLockFailure(
        incorrectPassword: false,
        notify: () async => throw StateError('Optional notice unavailable'),
        recordFailedAttempt: () async {
          writes += 1;
        },
      );
      expect(writes, 0);
    },
  );

  test(
    'failure completion waits for the attempt write, without a second write',
    () async {
      final Completer<void> writeStarted = Completer<void>();
      final Completer<void> writeFinished = Completer<void>();
      int writes = 0;
      bool completed = false;
      final Future<void> operation = recordLockFailure(
        incorrectPassword: true,
        notify: () async {},
        recordFailedAttempt: () async {
          writes += 1;
          writeStarted.complete();
          await writeFinished.future;
        },
      );
      unawaited(
        operation.then<void>((_) {
          completed = true;
        }),
      );
      await writeStarted.future;
      expect(completed, isFalse);
      expect(writes, 1);
      writeFinished.complete();
      await operation;
      expect(completed, isTrue);
      expect(writes, 1);
    },
  );

  test(
    'a write failure survives a failed optional notice',
    () async {
      final StateError failure = StateError('Attempt storage unavailable');
      int writes = 0;
      await expectLater(
        recordLockFailure(
          incorrectPassword: true,
          notify: () async => throw StateError('Optional notice unavailable'),
          recordFailedAttempt: () async {
            writes += 1;
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      expect(writes, 1);
    },
  );

  test(
    'a successful reset is persisted before the session becomes available',
    () async {
      final Completer<void> writeStarted = Completer<void>();
      final Completer<void> writeFinished = Completer<void>();
      final List<String> order = <String>[];
      int count = 2;
      final Future<void> operation = unlockAfterLockReset(
        persistReset: () async {
          writeStarted.complete();
          await writeFinished.future;
          count = 0;
          order.add('saved');
        },
        exposeSession: () async => order.add('unlocked'),
      );
      await writeStarted.future;
      expect(count, 2);
      expect(order, isEmpty);
      writeFinished.complete();
      await operation;
      expect(count, 0);
      expect(order, <String>['saved', 'unlocked']);
    },
  );

  test(
    'a failed reset neither exposes the session nor retries the write',
    () async {
      final StateError failure = StateError('Attempt storage unavailable');
      int count = 2;
      int writes = 0;
      int unlocked = 0;
      await expectLater(
        unlockAfterLockReset(
          persistReset: () async {
            writes += 1;
            throw failure;
          },
          exposeSession: () async {
            count = 0;
            unlocked += 1;
          },
        ),
        throwsA(same(failure)),
      );
      expect(count, 2);
      expect(writes, 1);
      expect(unlocked, 0);
    },
  );

  test(
    'the existing callback failure survives without retrying a committed reset',
    () async {
      final StateError failure = StateError('Session unavailable');
      int writes = 0;
      int callbacks = 0;
      await expectLater(
        unlockAfterLockReset(
          persistReset: () async {
            writes += 1;
          },
          exposeSession: () async {
            callbacks += 1;
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      expect(writes, 1);
      expect(callbacks, 1);
    },
  );
}
