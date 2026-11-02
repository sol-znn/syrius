import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/fixtures/fixture_cleanup.dart';

Future<void> _turns() async {
  for (int turn = 0; turn < 8; turn++) {
    await Future<void>.value();
  }
}

FixtureCleanup _opened({
  required Completer<void> route,
  required Completer<void> popped,
}) =>
    FixtureCleanup(name: 'sentinel')
      ..open(routeCompleted: route.future, push: () => popped.future);

class _OwnedFixture extends StatefulWidget {
  const _OwnedFixture({
    required this.cleanup,
    required this.close,
    required this.disposed,
  });

  final FixtureCleanup cleanup;
  final Future<void> Function() close;
  final void Function() disposed;

  @override
  State<_OwnedFixture> createState() => _OwnedFixtureState();
}

class _OwnedFixtureState extends State<_OwnedFixture> {
  late final FixtureCleanup _cleanup;
  late final Future<void> Function() _close;
  late final void Function() _disposed;

  @override
  void initState() {
    super.initState();
    _cleanup = widget.cleanup;
    _close = widget.close;
    _disposed = widget.disposed;
    _cleanup.attach(this);
  }

  @override
  void dispose() {
    _cleanup.dispose(
      owner: this,
      dispose: <void Function()>[_disposed],
      close: <Future<void> Function()>[_close],
      stateDisposed: () => super.dispose(),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  testWidgets(
    'actual route disposal retains a pending original fixture close',
    (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      final Completer<void> close = Completer<void>();
      final FixtureCleanup cleanup = FixtureCleanup(name: 'sentinel');
      int disposals = 0;
      int closes = 0;
      bool popped = false;
      bool completed = false;
      Future<void>? originalPop;
      final MaterialPageRoute<void> route = MaterialPageRoute<void>(
        builder: (_) => _OwnedFixture(
          cleanup: cleanup,
          close: () {
            closes++;
            return close.future;
          },
          disposed: () => disposals++,
        ),
      );
      final Future<void> originalCompletion = route.completed;
      unawaited(originalCompletion.then<void>((_) => completed = true));
      try {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox.expand(),
          ),
        );
        cleanup.open(
          routeCompleted: originalCompletion,
          push: () {
            final Future<void> original = navigatorKey.currentState!.push<void>(
              route,
            );
            originalPop = original;
            unawaited(original.then<void>((_) => popped = true));
            return original;
          },
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(_OwnedFixture), findsOneWidget);
        expect(route.isActive, isTrue);
        expect(popped, isFalse);
        expect(completed, isFalse);
        expect(disposals, 0);
        navigatorKey.currentState!.pop();
        await tester.pump();
        expect(popped, isTrue);
        expect(route.isActive, isFalse);
        expect(completed, isFalse);
        expect(disposals, 0);
        expect(closes, 0);
        expect(cleanup.heldName, 'sentinel');
        expect(cleanup.receipts[0].original, same(originalCompletion));
        expect(cleanup.receipts[1].original, same(originalPop));
        await tester.pump(const Duration(milliseconds: 100));
        expect(completed, isFalse);
        expect(disposals, 0);
        for (int frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(completed, isTrue);
        expect(find.byType(_OwnedFixture), findsNothing);
        expect(disposals, 1);
        expect(closes, 1);
        expect(cleanup.receipts[3].original, same(close.future));
        expect(cleanup.receipts[3].status, FixtureCleanupStatus.pending);
        expect(cleanup.heldName, 'sentinel');
        close.complete();
        await tester.pump();
        expect(cleanup.heldName, isNull);
        expect(disposals, 1);
        expect(closes, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!close.isCompleted) {
          close.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  test('a pop and inactive route do not release fixture admission', () async {
    final Completer<void> route = Completer<void>();
    final Completer<void> popped = Completer<void>();
    final Completer<void> close = Completer<void>();
    final Object owner = Object();
    final FixtureCleanup cleanup = _opened(route: route, popped: popped)
      ..attach(owner);
    final List<String> calls = <String>[];
    popped.complete();
    await _turns();
    expect(cleanup.heldName, 'sentinel');
    expect(cleanup.receipts[0].original, same(route.future));
    expect(cleanup.receipts[1].original, same(popped.future));
    cleanup.dispose(
      owner: owner,
      dispose: <void Function()>[() => calls.add('dispose')],
      close: <Future<void> Function()>[
        () {
          calls.add('close');
          return close.future;
        },
      ],
      stateDisposed: () => calls.add('state-disposed'),
    );
    expect(calls, <String>['dispose', 'close', 'state-disposed']);
    expect(cleanup.receipts[3].original, same(close.future));
    route.complete();
    await _turns();
    expect(cleanup.heldName, 'sentinel');
    expect(cleanup.receipts[3].status, FixtureCleanupStatus.pending);
    close.complete();
    await _turns();
    expect(cleanup.heldName, isNull);
    expect(
      cleanup.receipts.map((FixtureCleanupReceipt receipt) => receipt.status),
      everyElement(FixtureCleanupStatus.succeeded),
    );
    expect(calls, <String>['dispose', 'close', 'state-disposed']);
    expect(() => cleanup.receipts.clear(), throwsUnsupportedError);
  });

  test('successful closes still wait for original route completion', () async {
    final Completer<void> route = Completer<void>();
    final Completer<void> popped = Completer<void>();
    final Object owner = Object();
    final FixtureCleanup cleanup = _opened(route: route, popped: popped)
      ..attach(owner)
      ..dispose(
        owner: owner,
        dispose: <void Function()>[],
        close: <Future<void> Function()>[Future<void>.value],
        stateDisposed: () {},
      );
    popped.complete();
    await _turns();
    expect(cleanup.heldName, 'sentinel');
    route.complete();
    await _turns();
    expect(cleanup.heldName, isNull);
  });

  test('unseen or still mounted owners cannot establish disposal', () async {
    final Completer<void> route = Completer<void>();
    final Completer<void> popped = Completer<void>();
    final FixtureCleanup cleanup = _opened(route: route, popped: popped);
    route.complete();
    popped.complete();
    await _turns();
    expect(cleanup.heldName, 'sentinel');
    cleanup.attach(Object());
    await _turns();
    expect(cleanup.heldName, 'sentinel');
  });

  test(
    'a late original close failure retains admission and exact error',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Completer<void> close = Completer<void>();
      final Object failure = StateError('Synthetic original close failed');
      final StackTrace supplied = StackTrace.current;
      Object? receivedError;
      StackTrace? receivedTrace;
      unawaited(
        close.future.then<void>(
          (_) => fail('The original close must fail'),
          onError: (Object error, StackTrace trace) {
            receivedError = error;
            receivedTrace = trace;
          },
        ),
      );
      final Object owner = Object();
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner)
        ..dispose(
          owner: owner,
          dispose: <void Function()>[],
          close: <Future<void> Function()>[() => close.future],
          stateDisposed: () {},
        );
      route.complete();
      popped.complete();
      await _turns();
      expect(cleanup.heldName, 'sentinel');
      close.completeError(failure, supplied);
      await _turns();
      final FixtureCleanupReceipt receipt = cleanup.receipts[2];
      expect(receipt.status, FixtureCleanupStatus.failed);
      expect(receipt.original, same(close.future));
      expect(receipt.error, same(failure));
      expect(receipt.error, same(receivedError));
      expect(receipt.stackTrace, same(receivedTrace));
      expect(receipt.stackTrace.toString(), supplied.toString());
      expect(cleanup.heldName, 'sentinel');
    },
  );

  test(
    'synchronous disposal failure does not skip other original cleanup',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Completer<void> close = Completer<void>();
      final Object failure = StateError('Synthetic original disposal failed');
      final StackTrace trace = StackTrace.current;
      final Object owner = Object();
      final List<String> calls = <String>[];
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner)
        ..dispose(
          owner: owner,
          dispose: <void Function()>[
            () {
              calls.add('first');
              Error.throwWithStackTrace(failure, trace);
            },
            () => calls.add('second'),
          ],
          close: <Future<void> Function()>[
            () {
              calls.add('close');
              return close.future;
            },
          ],
          stateDisposed: () => calls.add('state-disposed'),
        );
      route.complete();
      popped.complete();
      close.complete();
      await _turns();
      expect(calls, <String>['first', 'second', 'close', 'state-disposed']);
      expect(cleanup.receipts[2].error, same(failure));
      expect(cleanup.receipts[2].stackTrace.toString(), trace.toString());
      expect(cleanup.receipts[2].original, isNull);
      expect(cleanup.receipts[4].original, same(close.future));
      expect(cleanup.heldName, 'sentinel');
    },
  );

  test(
    'synchronous close failure does not replace or retry another close',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Completer<void> close = Completer<void>();
      final Object failure = StateError('Synthetic synchronous close failed');
      final StackTrace trace = StackTrace.current;
      final Object owner = Object();
      int failedCloses = 0;
      int pendingCloses = 0;
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner)
        ..dispose(
          owner: owner,
          dispose: <void Function()>[],
          close: <Future<void> Function()>[
            () {
              failedCloses++;
              Error.throwWithStackTrace(failure, trace);
            },
            () {
              pendingCloses++;
              return close.future;
            },
          ],
          stateDisposed: () {},
        );
      route.complete();
      popped.complete();
      close.complete();
      await _turns();
      expect(cleanup.receipts[2].error, same(failure));
      expect(cleanup.receipts[2].stackTrace.toString(), trace.toString());
      expect(cleanup.receipts[2].original, isNull);
      expect(cleanup.receipts[3].original, same(close.future));
      expect(failedCloses, 1);
      expect(pendingCloses, 1);
      expect(cleanup.heldName, 'sentinel');
    },
  );

  test(
    'route failure stays distinct from successful fixture disposal',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Object failure = StateError('Synthetic original route failed');
      final StackTrace trace = StackTrace.current;
      final Object owner = Object();
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner)
        ..dispose(
          owner: owner,
          dispose: <void Function()>[],
          close: <Future<void> Function()>[],
          stateDisposed: () {},
        );
      route.completeError(failure, trace);
      popped.complete();
      await _turns();
      expect(cleanup.receipts[0].original, same(route.future));
      expect(cleanup.receipts[0].error, same(failure));
      expect(cleanup.receipts[0].stackTrace.toString(), trace.toString());
      expect(cleanup.receipts.last.status, FixtureCleanupStatus.succeeded);
      expect(cleanup.heldName, 'sentinel');
    },
  );

  test(
    'a synchronous push failure retains its actual error and hold',
    () async {
      final Completer<void> route = Completer<void>();
      final Object failure = StateError('Synthetic original push failed');
      final StackTrace trace = StackTrace.current;
      final FixtureCleanup cleanup = FixtureCleanup(name: 'sentinel');
      Object? receivedError;
      StackTrace? receivedTrace;
      try {
        cleanup.open(
          routeCompleted: route.future,
          push: () => Error.throwWithStackTrace(failure, trace),
        );
      } on Object catch (error, stackTrace) {
        receivedError = error;
        receivedTrace = stackTrace;
      }
      route.complete();
      await _turns();
      expect(receivedError, same(failure));
      expect(receivedTrace.toString(), trace.toString());
      expect(cleanup.receipts[1].original, isNull);
      expect(cleanup.receipts[1].error, same(failure));
      expect(cleanup.receipts[1].stackTrace.toString(), trace.toString());
      expect(cleanup.heldName, 'sentinel');
    },
  );

  test('a failed State.dispose cannot establish fixture cleanup', () async {
    final Completer<void> route = Completer<void>();
    final Completer<void> popped = Completer<void>();
    final Object failure = StateError(
      'Synthetic original State.dispose failed',
    );
    final StackTrace trace = StackTrace.current;
    final Object owner = Object();
    final FixtureCleanup cleanup = _opened(route: route, popped: popped)
      ..attach(owner)
      ..dispose(
        owner: owner,
        dispose: <void Function()>[],
        close: <Future<void> Function()>[],
        stateDisposed: () => Error.throwWithStackTrace(failure, trace),
      );
    route.complete();
    popped.complete();
    await _turns();
    expect(cleanup.receipts.last.error, same(failure));
    expect(cleanup.receipts.last.stackTrace.toString(), trace.toString());
    expect(cleanup.heldName, 'sentinel');
  });

  test(
    'a remounted owner cannot replace the original disposal witness',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Object owner = Object();
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner);
      expect(() => cleanup.attach(Object()), throwsStateError);
      cleanup.dispose(
        owner: owner,
        dispose: <void Function()>[],
        close: <Future<void> Function()>[],
        stateDisposed: () {},
      );
      route.complete();
      popped.complete();
      await _turns();
      expect(cleanup.heldName, 'sentinel');
      expect(cleanup.receipts[2].status, FixtureCleanupStatus.failed);
    },
  );

  test(
    'reentrant disposal neither retries original owners nor releases admission',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Completer<void> close = Completer<void>();
      final Object owner = Object();
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner);
      int closes = 0;
      int stateDisposals = 0;
      cleanup.dispose(
        owner: owner,
        dispose: <void Function()>[],
        close: <Future<void> Function()>[
          () {
            closes++;
            cleanup.dispose(
              owner: owner,
              dispose: <void Function()>[() => fail('Do not dispose twice')],
              close: <Future<void> Function()>[
                () => throw StateError('Do not close twice'),
              ],
              stateDisposed: () => fail('Do not dispose State twice'),
            );
            return close.future;
          },
        ],
        stateDisposed: () => stateDisposals++,
      );
      route.complete();
      popped.complete();
      close.complete();
      await _turns();
      expect(closes, 1);
      expect(stateDisposals, 1);
      expect(cleanup.heldName, 'sentinel');
      expect(
        cleanup.receipts.where(
          (FixtureCleanupReceipt receipt) => receipt.original == close.future,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a foreign disposal cannot invoke or replace original cleanup',
    () async {
      final Completer<void> route = Completer<void>();
      final Completer<void> popped = Completer<void>();
      final Object owner = Object();
      final FixtureCleanup cleanup = _opened(route: route, popped: popped)
        ..attach(owner)
        ..dispose(
          owner: Object(),
          dispose: <void Function()>[() => fail('Wrong owner must refuse')],
          close: <Future<void> Function()>[
            () => throw StateError('Wrong owner must refuse'),
          ],
          stateDisposed: () => fail('Wrong owner must refuse'),
        );
      int disposals = 0;
      cleanup.dispose(
        owner: owner,
        dispose: <void Function()>[],
        close: <Future<void> Function()>[],
        stateDisposed: () => disposals++,
      );
      route.complete();
      popped.complete();
      await _turns();
      expect(disposals, 1);
      expect(cleanup.heldName, 'sentinel');
    },
  );
}
