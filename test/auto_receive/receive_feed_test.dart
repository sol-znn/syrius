import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/receive_feed.dart';

const String _hash =
    '1111111111111111111111111111111111111111111111111111111111111111';

class _Origin {
  bool active = true;
}

class _Fixture {
  _Fixture() {
    feed = ReceiveFeed<_Origin>(
      prepare: (bool Function() current) async {
        final _Origin captured = origin;
        await preparation?.future;
        return current() ? captured : null;
      },
      isOriginCurrent: (_Origin captured) => captured.active,
      ownsAddress: (_, String address) => address == 'member',
      scan: (_Origin captured) async {
        scans.add(captured);
        await scanGate?.future;
      },
      enqueue: (_Origin captured, String hash, String address) async {
        queued.add((captured, hash, address));
      },
      drain: (_Origin captured) async => drains.add(captured),
      hasPending: () => pending,
      notifySyncing: (_Origin captured) async => notices.add(captured),
    );
  }

  _Origin origin = _Origin();
  bool connected = true;
  bool pending = true;
  int momentumCalls = 0;
  int blockCalls = 0;
  Completer<void>? preparation;
  Completer<void>? scanGate;
  Completer<String?>? momentumGate;
  Completer<String?>? blocksGate;
  Completer<void>? cancellation;
  void Function()? onCancellation;
  bool failSubscriptions = false;
  final List<_Origin> scans = <_Origin>[];
  final List<_Origin> drains = <_Origin>[];
  final List<_Origin> notices = <_Origin>[];
  final List<(_Origin, String, String)> queued = <(_Origin, String, String)>[];
  final List<StreamController<Map<String, dynamic>?>> streams =
      <StreamController<Map<String, dynamic>?>>[];
  late final ReceiveFeed<_Origin> feed;

  ReceiveFeedConnection connection() {
    final Completer<void>? originalCancellation = cancellation;
    final StreamController<Map<String, dynamic>?> stream =
        originalCancellation == null
        ? StreamController<Map<String, dynamic>?>.broadcast()
        : StreamController<Map<String, dynamic>?>(
            onCancel: () {
              onCancellation?.call();
              return originalCancellation.future;
            },
          );
    streams.add(stream);
    return ReceiveFeedConnection(
      messages: stream.stream,
      isCurrent: () => connected,
      subscribeMomentums: () async {
        momentumCalls++;
        if (failSubscriptions) throw StateError('Original momentum refusal');
        return momentumGate == null ? 'momentums' : momentumGate!.future;
      },
      subscribeAccountBlocks: () async {
        blockCalls++;
        if (failSubscriptions) throw StateError('Original block refusal');
        return blocksGate == null ? 'blocks' : blocksGate!.future;
      },
    );
  }

  void event(Object? result, {String id = 'blocks', int stream = 0}) {
    streams[stream].add(<String, dynamic>{
      'method': 'ledger.subscription',
      'params': <String, dynamic>{'subscription': id, 'result': result},
    });
  }

  Future<void> close() async {
    await feed.close();
    for (final StreamController<Map<String, dynamic>?> stream in streams) {
      await stream.close();
    }
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (int frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _settleOriginal(
  WidgetTester tester,
  Future<void> original,
) async {
  bool completed = false;
  Object? failure;
  StackTrace? failureTrace;
  unawaited(
    original.then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace trace) {
        failure = error;
        failureTrace = trace;
        completed = true;
      },
    ),
  );
  for (int turn = 0; turn < 8 && !completed; turn++) {
    // Subscription cancellation can return the SDK's shared root-zone Future.
    // Yield that zone while observing the same original, without a real timer.
    await tester.runAsync<void>(() async {
      await Future<void>.value();
    });
    await tester.pump();
  }
  expect(completed, isTrue, reason: 'original completes within eight turns');
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureTrace!);
  }
}

void main() {
  testWidgets('reentrant close retains the already reserved cancellation', (
    WidgetTester tester,
  ) async {
    final Completer<void> cancellation = Completer<void>();
    final _Fixture fixture = _Fixture()..cancellation = cancellation;
    Future<void>? reentrant;
    fixture.onCancellation = () {
      reentrant = fixture.feed.close();
    };
    try {
      fixture.feed.connect(fixture.connection());
      await _frames(tester);
      expect(fixture.scans, hasLength(1));
      fixture.feed.revoke();
      final Future<void> original = reentrant!;
      final Future<void> repeated = fixture.feed.close();
      expect(repeated, same(original));
      bool closed = false;
      unawaited(original.then<void>((_) => closed = true));
      await _frames(tester);
      expect(closed, isFalse);
      cancellation.complete();
      await _settleOriginal(tester, original);
      expect(closed, isTrue);
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      await _settleOriginal(tester, fixture.close());
    }
  });

  testWidgets(
    'closing a feed waits for its original subscription cancellation',
    (WidgetTester tester) async {
      final Completer<void> cancellation = Completer<void>();
      final _Fixture fixture = _Fixture()..cancellation = cancellation;
      try {
        fixture.feed.connect(fixture.connection());
        await _frames(tester);
        expect(fixture.scans, hasLength(1));
        final Future<void> original = fixture.feed.close();
        bool closed = false;
        unawaited(original.then<void>((_) => closed = true));
        await _frames(tester);
        expect(closed, isFalse);
        cancellation.complete();
        await _settleOriginal(tester, original);
        expect(closed, isTrue);
        fixture.feed.rearm();
        await _frames(tester);
        expect(fixture.scans, hasLength(1));
      } finally {
        if (!cancellation.isCompleted) cancellation.complete();
        await _settleOriginal(tester, fixture.close());
      }
    },
  );

  testWidgets('locks refuse preparation and cannot admit subscriptions', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture()..connected = false;
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    expect(fixture.momentumCalls, 0);
    expect(fixture.blockCalls, 0);
    expect(fixture.scans, isEmpty);
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('same connection retains pending admission across rearm', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture()
      ..momentumGate = Completer<String?>()
      ..blocksGate = Completer<String?>();
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    fixture.feed.rearm();
    await _frames(tester);
    expect(fixture.momentumCalls, 1);
    expect(fixture.blockCalls, 1);
    fixture.momentumGate!.complete('momentums');
    fixture.blocksGate!.complete('blocks');
    await _frames(tester);
    expect(fixture.scans, <_Origin>[fixture.origin]);
    expect(fixture.drains, <_Origin>[fixture.origin]);
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('uncertain subscriptions are held until a fresh connection', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture()..failSubscriptions = true;
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    fixture.failSubscriptions = false;
    fixture.feed.rearm();
    await _frames(tester);
    expect(fixture.momentumCalls, 1);
    expect(fixture.blockCalls, 1);
    fixture.event(<Object>[
      <String, dynamic>{'hash': _hash, 'toAddress': 'member'},
    ]);
    await _frames(tester);
    expect(fixture.queued, isEmpty);
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    expect(fixture.momentumCalls, 2);
    expect(fixture.blockCalls, 2);
    fixture.event(<Object>[
      <String, dynamic>{'hash': _hash, 'toAddress': 'member'},
    ], stream: 1);
    await _frames(tester);
    expect(fixture.queued.single, (fixture.origin, _hash, 'member'));
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('revoked preparation cannot recapture a replacement origin', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture()..preparation = Completer<void>();
    fixture.feed.connect(fixture.connection());
    final _Origin original = fixture.origin;
    fixture.feed.revoke();
    fixture.origin = _Origin();
    fixture.preparation!.complete();
    await _frames(tester);
    expect(fixture.momentumCalls, 0);
    expect(fixture.scans, isEmpty);
    expect(original, isNot(same(fixture.origin)));
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('stale scan settles without draining a replacement session', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture()..scanGate = Completer<void>();
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    fixture
      ..scans.single.active = false
      ..origin = _Origin()
      ..scanGate!.complete();
    await _frames(tester);
    expect(fixture.drains, isEmpty);
    await tester.pump(const Duration(seconds: 31));
    expect(fixture.notices, isEmpty);
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('empty, malformed and foreign notifications enqueue nothing', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    fixture.streams.single
      ..add(null)
      ..add(<String, dynamic>{'method': 'other'})
      ..add(<String, dynamic>{
        'method': 'ledger.subscription',
        'params': 'invalid',
      });
    fixture
      ..event(null)
      ..event(<Object>[])
      ..event(<Object>[false])
      ..event(<Object>[
        <String, dynamic>{'hash': 'short', 'toAddress': 'member'},
        <String, dynamic>{'hash': _hash, 'toAddress': 'foreign'},
      ])
      ..event(<Object>[
        <String, dynamic>{'hash': _hash, 'toAddress': 'member'},
      ], id: 'foreign-subscription');
    await _frames(tester);
    expect(fixture.queued, isEmpty);
    expect(tester.takeException(), isNull);
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('only exact owned account events pass the captured origin', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    final _Origin original = fixture.origin;
    fixture.event(<Object>[
      <String, dynamic>{'hash': _hash, 'toAddress': 'member'},
    ]);
    await _frames(tester);
    expect(fixture.queued.single, (original, _hash, 'member'));
    fixture
      ..feed.revoke()
      ..origin = _Origin()
      ..event(<Object>[
        <String, dynamic>{'hash': _hash, 'toAddress': 'member'},
      ]);
    await _frames(tester);
    expect(fixture.queued.length, 1);
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('momentum heights belong to each exact connection', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    fixture.event(<Object>[
      <String, dynamic>{'height': 12},
      <String, dynamic>{'height': 12},
      <String, dynamic>{'height': 11},
      <String, dynamic>{'height': '13'},
    ], id: 'momentums');
    await _frames(tester);
    expect(fixture.drains.length, 2);
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    fixture.event(
      <Object>[
        <String, dynamic>{'height': 1},
      ],
      id: 'momentums',
      stream: 1,
    );
    await _frames(tester);
    expect(fixture.drains.length, 4);
    await _settleOriginal(tester, fixture.close());
  });

  testWidgets('closed owners have no delayed notice or retained listener', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    fixture.feed.connect(fixture.connection());
    await _frames(tester);
    await _settleOriginal(tester, fixture.feed.close());
    fixture.event(<Object>[
      <String, dynamic>{'hash': _hash, 'toAddress': 'member'},
    ]);
    await tester.pump(const Duration(seconds: 31));
    expect(fixture.notices, isEmpty);
    expect(fixture.queued, isEmpty);
    expect(fixture.streams.single.hasListener, isFalse);
    await _settleOriginal(tester, fixture.close());
  });
}
