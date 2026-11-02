import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/presentation_close.dart';

Future<void> _turns() async {
  for (int turn = 0; turn < 8; turn++) {
    await Future<void>.value();
  }
}

void main() {
  test(
    'queued acknowledgement retains delay and proves no close or exit',
    () async {
      final Completer<void> delay = Completer<void>();
      final Completer<void> original = Completer<void>();
      int waits = 0;
      int guards = 0;
      int closes = 0;
      final PresentationCloseAttempt attempt = PresentationCloseAttempt(
        waitUntilAdmission: () {
          waits++;
          return delay.future;
        },
        requireCurrent: () => guards++,
        close: () {
          closes++;
          return original.future;
        },
      );
      final Future<void> admission = attempt.admission;
      final Future<PresentationCloseOutcome> completion = attempt.completion;
      bool admissionSettled = false;
      bool completed = false;
      unawaited(admission.then<void>((_) => admissionSettled = true));
      unawaited(completion.then<void>((_) => completed = true));
      await _turns();
      expect(attempt.originalAdmission, same(delay.future));
      expect(attempt.originalClose, isNull);
      expect(attempt.snapshot(), <String, Object?>{
        'status': 'queued',
        'queued': true,
        'admitted': false,
        'completed': false,
        'exitProved': false,
      });
      expect(waits, 1);
      expect(guards, 0);
      expect(closes, 0);
      expect(admissionSettled, isFalse);
      expect(completed, isFalse);
      delay.complete();
      await admission;
      expect(attempt.status, PresentationCloseStatus.admitted);
      expect(attempt.originalClose, same(original.future));
      expect(guards, 1);
      expect(closes, 1);
      expect(completed, isFalse);
      expect(attempt.admission, same(admission));
      expect(attempt.completion, same(completion));
      original.complete();
      final PresentationCloseOutcome outcome = await completion;
      expect(outcome.status, PresentationCloseStatus.completed);
      expect(outcome.error, isNull);
      expect(outcome.stackTrace, isNull);
      expect(attempt.snapshot()['completed'], isTrue);
      expect(attempt.snapshot()['exitProved'], isFalse);
      expect(closes, 1);
    },
  );

  test('retirement during delay refuses before native admission', () async {
    final Completer<void> delay = Completer<void>();
    final StateError failure = StateError('Synthetic original host retired');
    bool current = true;
    int closes = 0;
    final PresentationCloseAttempt attempt = PresentationCloseAttempt(
      waitUntilAdmission: () => delay.future,
      requireCurrent: () {
        if (!current) {
          throw failure;
        }
      },
      close: () {
        closes++;
        return Future<void>.value();
      },
    );
    current = false;
    delay.complete();
    final PresentationCloseOutcome outcome = await attempt.completion;
    expect(outcome.status, PresentationCloseStatus.refused);
    expect(outcome.error, same(failure));
    expect(outcome.stackTrace, isNotNull);
    expect(attempt.originalClose, isNull);
    expect(attempt.snapshot()['admitted'], isFalse);
    expect(closes, 0);
    current = true;
    await attempt.admission;
    await _turns();
    expect(await attempt.completion, same(outcome));
    expect(attempt.status, PresentationCloseStatus.refused);
    expect(closes, 0);
  });

  test(
    'late original failure survives owner departure without another close',
    () async {
      final Completer<void> delay = Completer<void>();
      final Completer<void> original = Completer<void>();
      final Object failure = StateError('Synthetic original close failed');
      final StackTrace supplied = StackTrace.current;
      Object? receivedError;
      StackTrace? receivedTrace;
      unawaited(
        original.future.then<void>(
          (_) => fail('The original close must fail'),
          onError: (Object error, StackTrace trace) {
            receivedError = error;
            receivedTrace = trace;
          },
        ),
      );
      bool current = true;
      int guards = 0;
      int closes = 0;
      final PresentationCloseAttempt attempt = PresentationCloseAttempt(
        waitUntilAdmission: () => delay.future,
        requireCurrent: () {
          guards++;
          if (!current) {
            throw StateError('Synthetic host retired');
          }
        },
        close: () {
          closes++;
          return original.future;
        },
      );
      delay.complete();
      await attempt.admission;
      expect(attempt.originalClose, same(original.future));
      current = false;
      original.completeError(failure, supplied);
      final PresentationCloseOutcome outcome = await attempt.completion;
      expect(outcome.status, PresentationCloseStatus.failed);
      expect(outcome.error, same(failure));
      expect(outcome.error, same(receivedError));
      expect(outcome.stackTrace, same(receivedTrace));
      expect(outcome.stackTrace.toString(), supplied.toString());
      expect(attempt.snapshot(), <String, Object?>{
        'status': 'failed',
        'queued': false,
        'admitted': true,
        'completed': false,
        'exitProved': false,
      });
      expect(guards, 1);
      expect(closes, 1);
    },
  );

  test('synchronous native throw has no invented original Future', () async {
    final Completer<void> delay = Completer<void>();
    final StateError failure = StateError(
      'Synthetic synchronous native failure',
    );
    int closes = 0;
    final PresentationCloseAttempt attempt = PresentationCloseAttempt(
      waitUntilAdmission: () => delay.future,
      requireCurrent: () {},
      close: () {
        closes++;
        throw failure;
      },
    );
    delay.complete();
    final PresentationCloseOutcome outcome = await attempt.completion;
    await attempt.admission;
    expect(outcome.status, PresentationCloseStatus.failed);
    expect(outcome.error, same(failure));
    expect(outcome.stackTrace, isNotNull);
    expect(attempt.originalClose, isNull);
    expect(attempt.snapshot()['admitted'], isTrue);
    expect(closes, 1);
  });

  test('wait failure never checks ownership or closes', () async {
    final Completer<void> delay = Completer<void>();
    final Object failure = StateError('Synthetic admission delay failed');
    final StackTrace trace = StackTrace.current;
    int guards = 0;
    int closes = 0;
    final PresentationCloseAttempt attempt = PresentationCloseAttempt(
      waitUntilAdmission: () => delay.future,
      requireCurrent: () => guards++,
      close: () {
        closes++;
        return Future<void>.value();
      },
    );
    delay.completeError(failure, trace);
    final PresentationCloseOutcome outcome = await attempt.completion;
    await attempt.admission;
    expect(attempt.originalAdmission, same(delay.future));
    expect(outcome.status, PresentationCloseStatus.failed);
    expect(outcome.error, same(failure));
    expect(outcome.stackTrace.toString(), trace.toString());
    expect(attempt.originalClose, isNull);
    expect(guards, 0);
    expect(closes, 0);
  });

  test('synchronous wait failure settles both reserved receipts', () async {
    final StateError failure = StateError('Synthetic wait callback failed');
    int closes = 0;
    final PresentationCloseAttempt attempt = PresentationCloseAttempt(
      waitUntilAdmission: () => throw failure,
      requireCurrent: () => fail('Admission must not run'),
      close: () {
        closes++;
        return Future<void>.value();
      },
    );
    final PresentationCloseOutcome outcome = await attempt.completion;
    await attempt.admission;
    expect(outcome.status, PresentationCloseStatus.failed);
    expect(outcome.error, same(failure));
    expect(outcome.stackTrace, isNotNull);
    expect(attempt.originalAdmission, isNull);
    expect(attempt.originalClose, isNull);
    expect(closes, 0);
  });

  test(
    'reentrant acknowledgement cannot create another native invocation',
    () async {
      final Completer<void> delay = Completer<void>();
      final Completer<void> original = Completer<void>();
      int closes = 0;
      Map<String, Object?>? atInvocation;
      Future<PresentationCloseOutcome>? retained;
      late final PresentationCloseAttempt attempt;
      attempt = PresentationCloseAttempt(
        waitUntilAdmission: () => delay.future,
        requireCurrent: () {},
        close: () {
          closes++;
          atInvocation = attempt.snapshot();
          retained = attempt.completion;
          return original.future;
        },
      );
      delay.complete();
      await attempt.admission;
      expect(atInvocation?['status'], 'admitted');
      expect(atInvocation?['completed'], isFalse);
      expect(retained, same(attempt.completion));
      expect(closes, 1);
      expect(
        () => attempt.snapshot()['status'] = 'completed',
        throwsUnsupportedError,
      );
      final Future<PresentationCloseOutcome> again = attempt.completion;
      original.complete();
      final PresentationCloseOutcome outcome = await again;
      expect(await retained, same(outcome));
      expect(await attempt.completion, same(outcome));
      expect(attempt.originalClose, same(original.future));
      expect(closes, 1);
    },
  );
}
