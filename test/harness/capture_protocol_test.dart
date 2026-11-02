import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/capture_protocol.dart';

class _Fixture {
  final Object identity = Object();
  final Object originalRoute = Object();
  final Object preparedRoute = Object();
  final Object renderer = Object();
  final Object asset = Object();
  final List<String> calls = <String>[];
  final List<Future<Object?>> originals = <Future<Object?>>[];
  bool current = true;
  bool restorationValid = true;
  bool returnRestoration = true;
  bool changeAfterShot = false;
  String? changedObservation;
  CaptureToken? preparedToken;
  Object? preparedSource;
  int observations = 0;
  int captures = 0;
  bool Function()? currentProof;
  bool Function()? restorationProof;
  void Function()? preparing;
  void Function()? shooting;
  Completer<CapturePrepared?>? preparation;
  Completer<String>? shot;
  Completer<CaptureRestored?>? restoration;

  CaptureFrameSpec get frame => CaptureFrameSpec(
    renderer: renderer,
    asset: asset,
    decodedIndex: 17,
    phase: .5,
  );

  CapturePlan plan({String theme = 'dark'}) => CapturePlan(
    screen: 'fixture-screen',
    theme: theme,
    mode: CaptureMode.presentation,
    frame: frame,
  );

  Future<V> _retain<V>(Future<V> original) {
    originals.add(original);
    return original;
  }

  CaptureSource<String> capture(CapturePlan _) {
    captures++;
    return CaptureSource<String>(
      identity: identity,
      originalRoute: originalRoute,
      isCurrent: () => currentProof?.call() ?? current,
      prepare: (CaptureToken token) {
        calls.add('prepare');
        preparing?.call();
        return _retain<CapturePrepared?>(
          preparation?.future ??
              Future<CapturePrepared?>.value(
                CapturePrepared(
                  token: preparedToken ?? token,
                  source: preparedSource ?? identity,
                  route: preparedRoute,
                ),
              ),
        );
      },
      observe: (CaptureToken token) {
        calls.add('observe');
        observations++;
        return _retain<CaptureObservedFrame?>(
          Future<CaptureObservedFrame?>.value(
            CaptureObservedFrame(
              token: token,
              source: changedObservation == 'source' ? Object() : identity,
              route: changedObservation == 'route' ? Object() : preparedRoute,
              frame: changedObservation != null
                  ? CaptureFrameSpec(
                      renderer: changedObservation == 'renderer'
                          ? Object()
                          : renderer,
                      asset: changedObservation == 'asset' ? Object() : asset,
                      decodedIndex: 17,
                      phase: changedObservation == 'phase' ? .6 : .5,
                    )
                  : changeAfterShot && observations == 2
                  ? CaptureFrameSpec(
                      renderer: renderer,
                      asset: asset,
                      decodedIndex: 18,
                      phase: .5,
                    )
                  : frame,
            ),
          ),
        );
      },
      shot: (CaptureToken _) {
        calls.add('shot');
        shooting?.call();
        return _retain<String>(
          shot?.future ?? Future<String>.value('original pixels'),
        );
      },
      restore: (CaptureToken token) {
        calls.add('restore');
        return _retain<CaptureRestored?>(
          restoration?.future ??
              Future<CaptureRestored?>.value(
                returnRestoration
                    ? CaptureRestored(
                        token: token,
                        source: identity,
                        originalRoute: originalRoute,
                      )
                    : null,
              ),
        );
      },
      isRestored: (CaptureRestored _) =>
          restorationProof?.call() ?? restorationValid,
    );
  }
}

Future<void> _turns() async {
  for (int turn = 0; turn < 16; turn++) {
    await Future<void>.value();
  }
}

void main() {
  test(
    'production refuses every unimplemented preparation without effects',
    () async {
      final CaptureProtocol<String> protocol =
          CaptureProtocol<String>.unavailable();
      for (final CaptureMode mode in CaptureMode.values) {
        final CaptureRun<String> run = protocol.start(
          CapturePlan(
            screen: 'fixture-screen',
            theme: 'dark',
            mode: mode,
            frame: const CaptureFrameSpec(renderer: Object()),
          ),
        );
        final CaptureOutcome<String> outcome = await run.completion;
        expect(outcome.status, CaptureStatus.refused);
        expect(outcome.error, isA<CaptureRefused>());
        expect(outcome.restorationVerified, isFalse);
        expect(run.operations, isEmpty);
      }
      expect(protocol.heldUnknown, isFalse);
    },
  );

  test(
    'one run retains exact originals and positively restores before reuse',
    () async {
      final _Fixture fixture = _Fixture();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CapturePlan plan = fixture.plan();
      final CaptureRun<String> run = protocol.start(plan);
      final CaptureOutcome<String> outcome = await run.completion;
      expect(outcome.status, CaptureStatus.captured);
      expect(outcome.result, 'original pixels');
      expect(outcome.error, isNull);
      expect(outcome.restorationVerified, isTrue);
      expect(run.plan, same(plan));
      expect(run.token.plan, same(plan));
      expect(run.operations.map((CaptureOperation op) => op.name), <String>[
        'prepare',
        'frame-before',
        'shot',
        'frame-after',
        'restore',
      ]);
      expect(run.operations, hasLength(fixture.originals.length));
      for (int index = 0; index < run.operations.length; index++) {
        expect(run.operations[index].original, same(fixture.originals[index]));
        expect(run.operations[index].isSettled, isTrue);
      }
      final CaptureRun<String> next = protocol.start(
        fixture.plan(theme: 'light'),
      );
      expect((await next.completion).status, CaptureStatus.captured);
      expect(next.token, isNot(same(run.token)));
      expect(run.plan.theme, 'dark');
      expect(next.plan.theme, 'light');
      expect(protocol.runs, <CaptureRun<String>>[run, next]);
    },
  );

  test(
    'a pending original blocks a second screen or theme without retry',
    () async {
      final _Fixture fixture = _Fixture()
        ..preparation = Completer<CapturePrepared?>();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureRun<String> first = protocol.start(fixture.plan());
      expect(first.operations.single.isSettled, isFalse);
      final CaptureRun<String> second = protocol.start(
        fixture.plan(theme: 'light'),
      );
      expect((await second.completion).status, CaptureStatus.refused);
      expect(second.operations, isEmpty);
      expect(fixture.captures, 1);
      expect(fixture.calls, <String>['prepare']);
      fixture.preparation!.complete(
        CapturePrepared(
          token: first.token,
          source: fixture.identity,
          route: fixture.preparedRoute,
        ),
      );
      expect((await first.completion).status, CaptureStatus.captured);
      expect(fixture.calls, <String>[
        'prepare',
        'observe',
        'shot',
        'observe',
        'restore',
      ]);
    },
  );

  test('reentrant proof retirement survives an outer true result', () async {
    final _Fixture fixture = _Fixture();
    final CaptureProtocol<String> protocol = CaptureProtocol<String>(
      capture: fixture.capture,
    );
    fixture.currentProof = () {
      protocol.revoke();
      return true;
    };
    final CaptureRun<String> run = protocol.start(fixture.plan());
    expect((await run.completion).status, CaptureStatus.heldUnknown);
    fixture.currentProof = () => true;
    expect(protocol.heldUnknown, isTrue);
    expect(run.operations, isEmpty);
    expect(fixture.calls, isEmpty);
    expect(
      (await protocol.start(fixture.plan(theme: 'light')).completion).status,
      CaptureStatus.refused,
    );
    expect(fixture.captures, 1);
  });

  test(
    'revocation inside a callback waits for the exact original result',
    () async {
      final _Fixture fixture = _Fixture()..shot = Completer<String>();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      fixture.shooting = protocol.revoke;
      final CaptureRun<String> run = protocol.start(fixture.plan());
      await _turns();
      expect(fixture.calls, <String>['prepare', 'observe', 'shot']);
      final CaptureOperation original = run.operations.last;
      expect(original.original, same(fixture.shot!.future));
      expect(original.isSettled, isFalse);
      bool completed = false;
      unawaited(
        run.completion.then<void>(
          (CaptureOutcome<String> _) => completed = true,
        ),
      );
      await _turns();
      expect(completed, isFalse);
      expect(run.heldUnknown, isTrue);
      fixture.shot!.complete('late original pixels');
      final CaptureOutcome<String> outcome = await run.completion;
      expect(outcome.status, CaptureStatus.heldUnknown);
      expect(outcome.result, 'late original pixels');
      expect(original.value, 'late original pixels');
      expect(outcome.restorationVerified, isFalse);
      expect(fixture.calls, <String>['prepare', 'observe', 'shot']);
      expect(
        (await protocol.start(fixture.plan(theme: 'light')).completion).status,
        CaptureStatus.refused,
      );
      expect(fixture.captures, 1);
    },
  );

  test('stale failure retains its original error and trace', () async {
    final _Fixture fixture = _Fixture()..shot = Completer<String>();
    final CaptureProtocol<String> protocol = CaptureProtocol<String>(
      capture: fixture.capture,
    );
    final CaptureRun<String> run = protocol.start(fixture.plan());
    await _turns();
    expect(run.operations.last.name, 'shot');
    protocol.revoke();
    final Object failure = StateError('Synthetic original shot failure');
    final StackTrace trace = StackTrace.current;
    fixture.shot!.completeError(failure, trace);
    final CaptureOutcome<String> outcome = await run.completion;
    expect(outcome.status, CaptureStatus.heldUnknown);
    expect(outcome.error, same(failure));
    expect(outcome.stackTrace, same(run.operations.last.stackTrace));
    expect(run.operations.last.error, same(failure));
    expect(run.operations.last.stackTrace.toString(), trace.toString());
    expect(run.operations.last.original, same(fixture.shot!.future));
    expect(fixture.calls, <String>['prepare', 'observe', 'shot']);
  });

  test(
    'source loss during prepare cannot be repaired by equal later state',
    () async {
      final _Fixture fixture = _Fixture()
        ..preparation = Completer<CapturePrepared?>();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureRun<String> run = protocol.start(fixture.plan());
      fixture.current = false;
      fixture.preparation!.complete(
        CapturePrepared(
          token: run.token,
          source: fixture.identity,
          route: fixture.preparedRoute,
        ),
      );
      final CaptureOutcome<String> outcome = await run.completion;
      fixture.current = true;
      expect(outcome.status, CaptureStatus.heldUnknown);
      expect(outcome.restorationVerified, isFalse);
      expect(fixture.calls, <String>['prepare']);
      expect(run.operations.single.isSettled, isTrue);
      expect(protocol.heldUnknown, isTrue);
      expect(
        (await protocol.start(fixture.plan(theme: 'light')).completion).status,
        CaptureStatus.refused,
      );
      expect(fixture.captures, 1);
    },
  );

  test('a changed observed frame cannot qualify the original shot', () async {
    final _Fixture fixture = _Fixture()..changeAfterShot = true;
    final CaptureProtocol<String> protocol = CaptureProtocol<String>(
      capture: fixture.capture,
    );
    final CaptureRun<String> run = protocol.start(fixture.plan());
    final CaptureOutcome<String> outcome = await run.completion;
    expect(outcome.status, CaptureStatus.failed);
    expect(outcome.result, 'original pixels');
    expect(outcome.restorationVerified, isTrue);
    expect(outcome.error, isA<CaptureRefused>());
    expect(protocol.heldUnknown, isFalse);
    expect(run.operations, hasLength(5));
  });

  for (final bool foreignToken in <bool>[false, true]) {
    test('foreign preparation refuses, token=$foreignToken', () async {
      final _Fixture fixture = _Fixture();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureRun<String> first = protocol.start(fixture.plan());
      expect((await first.completion).status, CaptureStatus.captured);
      if (foreignToken) {
        fixture.preparedToken = first.token;
      } else {
        fixture.preparedSource = Object();
      }
      final CaptureRun<String> second = protocol.start(
        fixture.plan(theme: 'light'),
      );
      final CaptureOutcome<String> outcome = await second.completion;
      expect(outcome.status, CaptureStatus.failed);
      expect(outcome.restorationVerified, isTrue);
      expect(outcome.result, isNull);
      expect(second.operations.map((CaptureOperation op) => op.name), <String>[
        'prepare',
        'restore',
      ]);
      expect(
        fixture.calls.where((String call) => call == 'shot'),
        hasLength(1),
      );
    });
  }

  for (final String field in <String>[
    'source',
    'route',
    'renderer',
    'asset',
    'phase',
  ]) {
    test('a different observed $field refuses before the shot', () async {
      final _Fixture fixture = _Fixture()..changedObservation = field;
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureOutcome<String> outcome = await protocol
          .start(
            fixture.plan(),
          )
          .completion;
      expect(outcome.status, CaptureStatus.failed);
      expect(outcome.result, isNull);
      expect(outcome.restorationVerified, isTrue);
      expect(fixture.calls, <String>['prepare', 'observe', 'restore']);
    });
  }

  test(
    'a synchronous original throw retains its trace and verified restore',
    () async {
      final _Fixture fixture = _Fixture();
      final Object failure = StateError('Synthetic original preparation');
      final StackTrace trace = StackTrace.current;
      fixture.preparing = () => Error.throwWithStackTrace(failure, trace);
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureRun<String> run = protocol.start(fixture.plan());
      final CaptureOutcome<String> outcome = await run.completion;
      expect(outcome.status, CaptureStatus.failed);
      expect(outcome.error, same(failure));
      expect(outcome.stackTrace, same(run.operations.first.stackTrace));
      expect(outcome.restorationVerified, isTrue);
      expect(run.operations.first.original, isNull);
      expect(run.operations.first.error, same(failure));
      expect(run.operations.first.stackTrace.toString(), trace.toString());
      expect(fixture.calls, <String>['prepare', 'restore']);
    },
  );

  for (final bool receiptMissing in <bool>[false, true]) {
    test('unproved restoration stays held, missing=$receiptMissing', () async {
      final _Fixture fixture = _Fixture()
        ..returnRestoration = !receiptMissing
        ..restorationValid = receiptMissing;
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureRun<String> run = protocol.start(fixture.plan());
      final CaptureOutcome<String> outcome = await run.completion;
      expect(outcome.status, CaptureStatus.heldUnknown);
      expect(outcome.restorationVerified, isFalse);
      fixture
        ..returnRestoration = true
        ..restorationValid = true;
      expect(
        (await protocol.start(fixture.plan(theme: 'light')).completion).status,
        CaptureStatus.refused,
      );
      expect(fixture.captures, 1);
      expect(fixture.calls, <String>[
        'prepare',
        'observe',
        'shot',
        'observe',
        'restore',
      ]);
    });
  }

  test(
    'the pending original restore is never replaced by visible success',
    () async {
      final _Fixture fixture = _Fixture()
        ..restoration = Completer<CaptureRestored?>();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      final CaptureRun<String> run = protocol.start(fixture.plan());
      await _turns();
      expect(run.operations.last.name, 'restore');
      expect(run.operations.last.original, same(fixture.restoration!.future));
      expect(run.operations.last.isSettled, isFalse);
      expect(
        (await protocol.start(fixture.plan(theme: 'light')).completion).status,
        CaptureStatus.refused,
      );
      final Object failure = StateError('Synthetic original restore failure');
      final StackTrace trace = StackTrace.current;
      fixture.restoration!.completeError(failure, trace);
      final CaptureOutcome<String> outcome = await run.completion;
      expect(outcome.status, CaptureStatus.heldUnknown);
      expect(outcome.error, same(failure));
      expect(outcome.stackTrace, same(run.operations.last.stackTrace));
      expect(run.operations.last.stackTrace.toString(), trace.toString());
      expect(outcome.restorationVerified, isFalse);
      expect(fixture.captures, 1);
    },
  );

  test(
    'restoration proof cannot revoke then return an admitting true',
    () async {
      final _Fixture fixture = _Fixture();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      fixture.restorationProof = () {
        protocol.revoke();
        return true;
      };
      final CaptureOutcome<String> outcome = await protocol
          .start(
            fixture.plan(),
          )
          .completion;
      expect(outcome.status, CaptureStatus.heldUnknown);
      expect(outcome.restorationVerified, isFalse);
      expect(protocol.heldUnknown, isTrue);
    },
  );

  test('invalid frame requests refuse before source capture', () async {
    final _Fixture fixture = _Fixture();
    final CaptureProtocol<String> protocol = CaptureProtocol<String>(
      capture: fixture.capture,
    );
    for (final CaptureFrameSpec frame in <CaptureFrameSpec>[
      const CaptureFrameSpec(renderer: Object(), decodedIndex: 1),
      const CaptureFrameSpec(
        renderer: Object(),
        asset: Object(),
        decodedIndex: -1,
      ),
      const CaptureFrameSpec(renderer: Object(), phase: double.nan),
      const CaptureFrameSpec(renderer: Object(), phase: 1.1),
    ]) {
      final CaptureRun<String> run = protocol.start(
        CapturePlan(
          screen: 'fixture-screen',
          theme: 'dark',
          mode: CaptureMode.presentation,
          frame: frame,
        ),
      );
      expect((await run.completion).status, CaptureStatus.refused);
      expect(run.operations, isEmpty);
    }
    expect(fixture.captures, 0);
    expect(protocol.runs, isEmpty);
  });

  test(
    'retained scope capacity refuses before another original is captured',
    () async {
      final _Fixture fixture = _Fixture();
      final CaptureProtocol<String> protocol = CaptureProtocol<String>(
        capture: fixture.capture,
      );
      for (int index = 0; index < CaptureProtocol.maxRuns; index++) {
        expect(
          (await protocol.start(fixture.plan()).completion).status,
          CaptureStatus.captured,
        );
      }
      final CaptureRun<String> refused = protocol.start(fixture.plan());
      expect((await refused.completion).status, CaptureStatus.refused);
      expect(refused.operations, isEmpty);
      expect(protocol.runs, hasLength(CaptureProtocol.maxRuns));
      expect(fixture.captures, CaptureProtocol.maxRuns);
    },
  );
}
