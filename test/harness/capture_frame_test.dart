import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/capture_frame.dart';

Future<void> _turns() async {
  for (int turn = 0; turn < 8; turn++) {
    await Future<void>.value();
  }
}

Matcher _agentRefusal() => throwsA(
  isA<HarnessError>().having(
    (HarnessError error) => error.message,
    'message',
    'the original capture frame is unavailable',
  ),
);

Map<String, dynamic> _shot() => <String, dynamic>{
  'cmd': 'shot',
  'expect': <String, Object?>{'key': 'synthetic_capture_marker'},
  'theme': 'dark',
  'width': 1280,
  'height': 780,
};

void main() {
  test('pending frame reserves admission before any readback', () async {
    final Completer<void> frame = Completer<void>();
    final Completer<void> deadline = Completer<void>();
    int waits = 0;
    int readbacks = 0;
    final CaptureFrameGate gate = CaptureFrameGate(
      waitForFrame: () {
        waits++;
        return frame.future;
      },
      waitUntilDeadline: () => deadline.future,
    );
    final Future<String> capture = gate.capture<String>(() async {
      readbacks++;
      return 'original pixels';
    });
    final CaptureFrameReceipt receipt = gate.receipt!;
    bool completed = false;
    unawaited(receipt.completion.then<void>((_) => completed = true));
    await _turns();
    expect(receipt.original, same(frame.future));
    expect(receipt.status, CaptureFrameStatus.pending);
    expect(receipt.outcome, isNull);
    expect(completed, isFalse);
    expect(readbacks, 0);
    expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
    await expectLater(
      gate.capture<String>(() async {
        readbacks++;
        return 'replacement pixels';
      }),
      throwsA(isA<CaptureFrameRefused>()),
    );
    expect(gate.receipt, same(receipt));
    expect(waits, 1);
    frame.complete();
    expect(await capture, 'original pixels');
    expect(await receipt.admission, isTrue);
    final CaptureFrameOutcome outcome = await receipt.completion;
    expect(outcome.completed, isTrue);
    expect(outcome.error, isNull);
    expect(outcome.stackTrace, isNull);
    expect(receipt.status, CaptureFrameStatus.ready);
    expect(readbacks, 1);
    expect(gate.requireIdle, returnsNormally);
    deadline.complete();
    await _turns();
    expect(receipt.timedOut, isFalse);
    expect(gate.heldUnknown, isFalse);
  });

  testWidgets('the actual 250 ms deadline never completes the frame', (
    WidgetTester tester,
  ) async {
    final Completer<void> frame = Completer<void>();
    int readbacks = 0;
    final CaptureFrameGate gate = CaptureFrameGate(
      waitForFrame: () => frame.future,
    );
    final Future<void> refusal = expectLater(
      gate.capture<void>(() async {
        readbacks++;
      }),
      throwsA(isA<CaptureFrameRefused>()),
    );
    final CaptureFrameReceipt receipt = gate.receipt!;
    await tester.pump(const Duration(milliseconds: 249));
    expect(receipt.status, CaptureFrameStatus.pending);
    expect(receipt.timedOut, isFalse);
    expect(receipt.outcome, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    await refusal;
    expect(receipt.status, CaptureFrameStatus.held);
    expect(receipt.timedOut, isTrue);
    expect(receipt.outcome, isNull);
    expect(readbacks, 0);
    frame.complete();
    await tester.pump();
    expect((await receipt.completion).completed, isTrue);
    expect(receipt.status, CaptureFrameStatus.held);
    expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
    expect(readbacks, 0);
  });

  for (final bool lateFailure in <bool>[false, true]) {
    test('timeout retains the late original, failure $lateFailure', () async {
      final Completer<void> frame = Completer<void>();
      final Completer<void> deadline = Completer<void>();
      final Object failure = StateError('Synthetic original frame failed');
      final StackTrace trace = StackTrace.current;
      Object? receivedError;
      StackTrace? receivedTrace;
      unawaited(
        frame.future.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            receivedError = error;
            receivedTrace = stack;
          },
        ),
      );
      int readbacks = 0;
      final CaptureFrameGate gate = CaptureFrameGate(
        waitForFrame: () => frame.future,
        waitUntilDeadline: () => deadline.future,
      );
      final Future<void> refusal = expectLater(
        gate.capture<String>(() async {
          readbacks++;
          return 'unadmitted pixels';
        }),
        throwsA(isA<CaptureFrameRefused>()),
      );
      final CaptureFrameReceipt receipt = gate.receipt!;
      final Future<CaptureFrameOutcome> completion = receipt.completion;
      deadline.complete();
      await refusal;
      expect(await receipt.admission, isFalse);
      expect(receipt.original, same(frame.future));
      expect(receipt.status, CaptureFrameStatus.held);
      expect(receipt.timedOut, isTrue);
      expect(receipt.outcome, isNull);
      expect(gate.heldUnknown, isTrue);
      expect(readbacks, 0);
      if (lateFailure) {
        frame.completeError(failure, trace);
      } else {
        frame.complete();
      }
      final CaptureFrameOutcome outcome = await completion;
      expect(outcome.completed, !lateFailure);
      if (lateFailure) {
        expect(outcome.error, same(failure));
        expect(outcome.error, same(receivedError));
        expect(outcome.stackTrace, same(receivedTrace));
        expect(outcome.stackTrace.toString(), trace.toString());
      } else {
        expect(outcome.error, isNull);
        expect(outcome.stackTrace, isNull);
      }
      expect(receipt.outcome, same(outcome));
      expect(receipt.completion, same(completion));
      expect(receipt.status, CaptureFrameStatus.held);
      expect(await receipt.admission, isFalse);
      await expectLater(
        gate.capture<String>(() async => 'replacement pixels'),
        throwsA(isA<CaptureFrameRefused>()),
      );
      expect(gate.receipt, same(receipt));
      expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
      expect(readbacks, 0);
    });
  }

  test(
    'original failure holds before the deadline with its exact trace',
    () async {
      final Completer<void> frame = Completer<void>();
      final Completer<void> deadline = Completer<void>();
      final Object failure = StateError('Synthetic frame completion failed');
      final StackTrace trace = StackTrace.current;
      final CaptureFrameGate gate = CaptureFrameGate(
        waitForFrame: () => frame.future,
        waitUntilDeadline: () => deadline.future,
      );
      final Future<void> refusal = expectLater(
        gate.capture<void>(() async => fail('Readback was admitted')),
        throwsA(isA<CaptureFrameRefused>()),
      );
      final CaptureFrameReceipt receipt = gate.receipt!;
      frame.completeError(failure, trace);
      await refusal;
      final CaptureFrameOutcome outcome = await receipt.completion;
      expect(outcome.completed, isFalse);
      expect(outcome.error, same(failure));
      expect(outcome.stackTrace.toString(), trace.toString());
      expect(receipt.timedOut, isFalse);
      expect(gate.heldUnknown, isTrue);
      deadline.complete();
      await _turns();
      expect(receipt.outcome, same(outcome));
      expect(receipt.timedOut, isFalse);
      expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
    },
  );

  test(
    'synchronous frame throw retains no manufactured original Future',
    () async {
      final Object failure = StateError('Synthetic frame callback failed');
      final StackTrace trace = StackTrace.current;
      int deadlines = 0;
      final CaptureFrameGate gate = CaptureFrameGate(
        waitForFrame: () => Error.throwWithStackTrace(failure, trace),
        waitUntilDeadline: () {
          deadlines++;
          return Future<void>.value();
        },
      );
      await expectLater(
        gate.capture<void>(() async => fail('Readback was admitted')),
        throwsA(isA<CaptureFrameRefused>()),
      );
      final CaptureFrameReceipt receipt = gate.receipt!;
      final CaptureFrameOutcome outcome = await receipt.completion;
      expect(receipt.original, isNull);
      expect(outcome.completed, isFalse);
      expect(outcome.error, same(failure));
      expect(outcome.stackTrace.toString(), trace.toString());
      expect(deadlines, 0);
      expect(gate.heldUnknown, isTrue);
    },
  );

  for (final bool synchronous in <bool>[false, true]) {
    test('failed admission clock holds, synchronous $synchronous', () async {
      final Completer<void> frame = Completer<void>();
      final Completer<void> deadline = Completer<void>();
      final Object failure = StateError('Synthetic admission clock failed');
      final StackTrace trace = StackTrace.current;
      final CaptureFrameGate gate = CaptureFrameGate(
        waitForFrame: () => frame.future,
        waitUntilDeadline: () {
          if (synchronous) {
            Error.throwWithStackTrace(failure, trace);
          }
          return deadline.future;
        },
      );
      final Future<void> refusal = expectLater(
        gate.capture<void>(() async => fail('Readback was admitted')),
        throwsA(isA<CaptureFrameRefused>()),
      );
      final CaptureFrameReceipt receipt = gate.receipt!;
      if (!synchronous) {
        deadline.completeError(failure, trace);
      }
      await refusal;
      expect(receipt.original, same(frame.future));
      expect(receipt.outcome, isNull);
      expect(receipt.admissionError, same(failure));
      expect(receipt.admissionStackTrace.toString(), trace.toString());
      expect(receipt.timedOut, isFalse);
      frame.complete();
      expect((await receipt.completion).completed, isTrue);
      expect(receipt.status, CaptureFrameStatus.held);
      expect(gate.heldUnknown, isTrue);
      expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
    });
  }

  test('reentrant frame callback cannot reserve a second original', () async {
    final Completer<void> frame = Completer<void>();
    final Completer<void> deadline = Completer<void>();
    late final CaptureFrameGate gate;
    Future<void>? nested;
    Object? nestedError;
    int waits = 0;
    int readbacks = 0;
    gate = CaptureFrameGate(
      waitForFrame: () {
        waits++;
        expect(gate.receipt, isNotNull);
        expect(gate.receipt!.original, isNull);
        nested = gate
            .capture<void>(() async {
              fail('Nested readback was admitted');
            })
            .then<void>(
              (_) => fail('Nested capture was admitted'),
              onError: (Object error, StackTrace _) {
                nestedError = error;
              },
            );
        return frame.future;
      },
      waitUntilDeadline: () => deadline.future,
    );
    final Future<String> capture = gate.capture<String>(() async {
      readbacks++;
      return 'original pixels';
    });
    await nested;
    expect(nestedError, isA<CaptureFrameRefused>());
    expect(waits, 1);
    expect(readbacks, 0);
    frame.complete();
    expect(await capture, 'original pixels');
    expect(readbacks, 1);
    deadline.complete();
    await _turns();
    expect(gate.heldUnknown, isFalse);
  });

  test(
    'positive frame keeps admission busy through original readback',
    () async {
      final Completer<void> frame = Completer<void>();
      final Completer<void> deadline = Completer<void>();
      final Completer<String> pixels = Completer<String>();
      int readbacks = 0;
      final CaptureFrameGate gate = CaptureFrameGate(
        waitForFrame: () => frame.future,
        waitUntilDeadline: () => deadline.future,
      );
      final Future<String> capture = gate.capture<String>(() {
        readbacks++;
        expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
        return pixels.future;
      });
      final CaptureFrameReceipt receipt = gate.receipt!;
      frame.complete();
      await _turns();
      expect((await receipt.completion).completed, isTrue);
      expect(readbacks, 1);
      expect(gate.requireIdle, throwsA(isA<CaptureFrameRefused>()));
      await expectLater(
        gate.capture<String>(() async => 'replacement pixels'),
        throwsA(isA<CaptureFrameRefused>()),
      );
      pixels.complete('original pixels');
      expect(await capture, 'original pixels');
      expect(gate.requireIdle, returnsNormally);
      deadline.complete();
    },
  );

  test(
    'a prior positive receipt cannot hold the next frame admission',
    () async {
      final List<Completer<void>> frames = <Completer<void>>[
        Completer<void>(),
        Completer<void>(),
      ];
      final List<Completer<void>> deadlines = <Completer<void>>[
        Completer<void>(),
        Completer<void>(),
      ];
      int calls = 0;
      final CaptureFrameGate gate = CaptureFrameGate(
        waitForFrame: () => frames[calls++].future,
        waitUntilDeadline: () => deadlines[calls - 1].future,
      );
      final Future<String> first = gate.capture<String>(
        () async => 'first original pixels',
      );
      final CaptureFrameReceipt previous = gate.receipt!;
      frames.first.complete();
      expect(await first, 'first original pixels');
      final Future<String> second = gate.capture<String>(
        () async => 'second original pixels',
      );
      final CaptureFrameReceipt current = gate.receipt!;
      expect(current, isNot(same(previous)));
      deadlines.first.complete();
      await _turns();
      expect(current.status, CaptureFrameStatus.pending);
      expect(gate.heldUnknown, isFalse);
      frames.last.complete();
      expect(await second, 'second original pixels');
      expect(previous.original, same(frames.first.future));
      expect(previous.outcome!.completed, isTrue);
      expect(current.original, same(frames.last.future));
      expect(current.outcome!.completed, isTrue);
      expect(gate.requireIdle, returnsNormally);
      deadlines.last.complete();
    },
  );

  for (final bool lateFailure in <bool>[false, true]) {
    test(
      'agent blocks readback and theme after timeout, error $lateFailure',
      () async {
        final Completer<void> frame = Completer<void>();
        final Completer<void> deadline = Completer<void>();
        final Object failure = StateError('Synthetic late frame failure');
        final StackTrace trace = StackTrace.current;
        int waits = 0;
        final HarnessAgent agent = HarnessAgent.forTest(
          waitForCaptureFrame: () {
            waits++;
            return frame.future;
          },
          waitForCaptureFrameDeadline: () => deadline.future,
        );
        final Future<void> refusal = expectLater(
          agent.commandForTest(_shot()),
          _agentRefusal(),
        );
        final CaptureFrameReceipt receipt = agent.captureFrameForTest!;
        for (final Map<String, dynamic> command in <Map<String, dynamic>>[
          _shot(),
          <String, dynamic>{'cmd': 'shot'},
          <String, dynamic>{'cmd': 'theme', 'mode': 'light'},
          <String, dynamic>{
            'cmd': 'theme',
            'restore': <String, Object?>{'mode': 'dark'},
          },
        ]) {
          await expectLater(agent.commandForTest(command), _agentRefusal());
        }
        expect(waits, 1);
        expect(receipt.outcome, isNull);
        deadline.complete();
        await refusal;
        expect(receipt.status, CaptureFrameStatus.held);
        expect(receipt.outcome, isNull);
        if (lateFailure) {
          frame.completeError(failure, trace);
        } else {
          frame.complete();
        }
        final CaptureFrameOutcome outcome = await receipt.completion;
        expect(outcome.completed, !lateFailure);
        if (lateFailure) {
          expect(outcome.error, same(failure));
          expect(outcome.stackTrace.toString(), trace.toString());
        } else {
          expect(outcome.error, isNull);
        }
        await expectLater(agent.commandForTest(_shot()), _agentRefusal());
        await expectLater(
          agent.commandForTest(<String, dynamic>{
            'cmd': 'theme',
            'mode': 'light',
          }),
          _agentRefusal(),
        );
        expect(agent.captureFrameForTest, same(receipt));
        expect(receipt.original, same(frame.future));
        expect(receipt.status, CaptureFrameStatus.held);
        expect(waits, 1);
      },
    );
  }
}
