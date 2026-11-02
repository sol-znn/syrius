import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/settings/general_stats_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/general_stats.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Zenon extends Mock implements Zenon {}

class _Ledger extends Mock implements LedgerApi {}

class _Stats extends Mock implements StatsApi {}

class _Socket extends Mock implements WsClient {}

class _Momentum extends Fake implements Momentum {}

class _Process extends Fake implements ProcessInfo {}

class _Network extends Fake implements NetworkInfo {}

class _Os extends Fake implements OsInfo {}

const List<String> _readOrder = <String>[
  'frontier',
  'process',
  'network',
  'os',
];

// No SDK transport is constructed. Widget tests advance the real Dart Timer
// through their controlled clock; every SDK answer belongs to these mocks.
class _Fixture {
  _Fixture({String? pause}) {
    if (pause != null) hold(pause);
    when(() => node.ledger).thenReturn(ledger);
    when(() => node.stats).thenReturn(stats);
    when(() => node.wsClient).thenReturn(socket);
    when(socket.isClosed).thenReturn(false);
    when(() => socket.restartedStreamController).thenReturn(restarts);
    when(ledger.getFrontierMomentum).thenAnswer(
      (_) => _answer<Momentum>('frontier', momentum),
    );
    when(stats.processInfo).thenAnswer(
      (_) => _answer<ProcessInfo>('process', process),
    );
    when(stats.networkInfo).thenAnswer(
      (_) => _answer<NetworkInfo>('network', network),
    );
    when(stats.osInfo).thenAnswer(
      (_) => _answer<OsInfo>('os', os),
    );
    app.zenon = node;
    bloc = GeneralStatsBloc();
    _subscription = bloc.stream.listen(
      events.add,
      onError: errors.add,
      onDone: () => streamDone = true,
    );
    addTearDown(close);
  }

  final Zenon? _previous = app.zenon;
  final _Zenon node = _Zenon();
  final _Ledger ledger = _Ledger();
  final _Stats stats = _Stats();
  final _Socket socket = _Socket();
  final Momentum momentum = _Momentum();
  final ProcessInfo process = _Process();
  final NetworkInfo network = _Network();
  final OsInfo os = _Os();
  final StreamController<bool> restarts = StreamController<bool>.broadcast(
    sync: true,
  );
  final List<String> calls = <String>[];
  final List<GeneralStats> events = <GeneralStats>[];
  final List<Object> errors = <Object>[];
  late final GeneralStatsBloc bloc;
  late final StreamSubscription<GeneralStats> _subscription;
  String? _pausedRead;
  Completer<void>? _pending;
  bool streamDone = false;

  Completer<void> hold(String read) {
    _pausedRead = read;
    return _pending = Completer<void>();
  }

  Completer<void> get pending => _pending!;

  Future<T> _answer<T>(String read, T result) async {
    calls.add(read);
    final Completer<void>? original = read == _pausedRead ? _pending : null;
    if (original != null) await original.future;
    return result;
  }

  void expectOriginal(GeneralStats value) {
    expect(value.frontierMomentum, same(momentum));
    expect(value.processInfo, same(process));
    expect(value.networkInfo, same(network));
    expect(value.osInfo, same(os));
  }

  Future<void> close() async {
    bloc.dispose();
    await _subscription.cancel();
    await restarts.close();
    app.zenon = _previous;
  }
}

void main() {
  testWidgets('live refresh preserves the four SDK answers and interval', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    await tester.pump();
    expect(fixture.calls, _readOrder);
    expect(fixture.events, hasLength(1));
    fixture.expectOriginal(fixture.events.single);
    await tester.pump(
      kIntervalBetweenMomentums - const Duration(milliseconds: 1),
    );
    expect(fixture.calls, _readOrder);
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.calls, <String>[..._readOrder, ..._readOrder]);
    expect(fixture.events, hasLength(2));
    fixture.expectOriginal(fixture.events.last);
    fixture.bloc.dispose();
    await tester.pump();
    expect(fixture.errors, isEmpty);
    expect(fixture.streamDone, isTrue);
  });

  for (final String stage in _readOrder) {
    testWidgets('disposal during the original $stage read cannot rearm', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(pause: stage);
      await tester.pump();
      expect(
        fixture.calls,
        _readOrder.take(_readOrder.indexOf(stage) + 1).toList(),
      );
      fixture.bloc
        ..dispose()
        ..dispose();
      await tester.pump();
      expect(fixture.restarts.hasListener, isFalse);
      fixture.pending.complete();
      await tester.pump();
      expect(fixture.calls, _readOrder);
      await tester.pump(kIntervalBetweenMomentums * 4);
      expect(fixture.calls, _readOrder);
      expect(fixture.events, isEmpty);
      expect(fixture.errors, isEmpty);
      expect(fixture.streamDone, isTrue);
    });
  }

  testWidgets('a fired refresh retains its read but cannot schedule another', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    await tester.pump();
    final Completer<void> original = fixture.hold('frontier');
    await tester.pump(kIntervalBetweenMomentums);
    expect(fixture.calls, <String>[..._readOrder, 'frontier']);
    fixture.bloc.dispose();
    original.complete();
    await tester.pump();
    await tester.pump(kIntervalBetweenMomentums * 4);
    expect(fixture.calls, <String>[..._readOrder, ..._readOrder]);
    expect(fixture.events, hasLength(1));
    expect(fixture.errors, isEmpty);
  });

  testWidgets('repeated disposal cancels active timer and reconnect polling', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    await tester.pump();
    expect(fixture.restarts.hasListener, isTrue);
    fixture.bloc
      ..dispose()
      ..dispose();
    fixture.restarts.add(true);
    await tester.pump(kIntervalBetweenMomentums * 4);
    fixture.bloc.dispose();
    expect(fixture.calls, _readOrder);
    expect(fixture.events, hasLength(1));
    expect(fixture.errors, isEmpty);
    expect(fixture.restarts.hasListener, isFalse);
    expect(fixture.restarts.isClosed, isFalse);
  });

  testWidgets('an already queued original timer callback remains revoked', (
    WidgetTester tester,
  ) async {
    final List<void Function()> callbacks = <void Function()>[];
    final _Fixture fixture = runZoned<_Fixture>(
      _Fixture.new,
      zoneSpecification: ZoneSpecification(
        createTimer:
            (
              Zone self,
              ZoneDelegate parent,
              Zone zone,
              Duration duration,
              void Function() callback,
            ) {
              if (duration == kIntervalBetweenMomentums) {
                callbacks.add(callback);
              }
              return parent.createTimer(zone, duration, callback);
            },
      ),
    );
    await tester.pump();
    expect(callbacks, hasLength(1));
    fixture.bloc.dispose();
    // Deliver the same captured closure after cancellation, as if dispatch
    // had already queued it. No replacement timer or SDK request is supplied.
    callbacks.single();
    await tester.pump(kIntervalBetweenMomentums * 4);
    expect(fixture.calls, _readOrder);
    expect(callbacks, hasLength(1));
    expect(fixture.events, hasLength(1));
    expect(fixture.errors, isEmpty);
  });

  testWidgets('the original direct read still returns its late SDK objects', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture(pause: 'frontier');
    GeneralStats? observed;
    final Future<GeneralStats> original = fixture.bloc.getDataAsync();
    unawaited(
      original.then<void>((GeneralStats value) {
        observed = value;
      }),
    );
    fixture.bloc.dispose();
    fixture.pending.complete();
    await tester.pump();
    expect(observed, isNotNull);
    fixture.expectOriginal(observed!);
    expect(
      fixture.calls.where((String read) => read == 'frontier'),
      hasLength(2),
    );
    expect(fixture.calls, hasLength(8));
    await tester.pump(kIntervalBetweenMomentums * 4);
    expect(fixture.calls, hasLength(8));
    expect(fixture.events, isEmpty);
    expect(fixture.errors, isEmpty);
  });

  testWidgets('a late original SDK failure is preserved without a retry', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture(pause: 'os');
    await tester.pump();
    final Object failure = StateError('original-sdk-failure');
    Object? observed;
    final Future<GeneralStats> original = fixture.bloc.getDataAsync();
    unawaited(
      original.then<void>(
        (_) => fail('The original SDK failure must remain a failure'),
        onError: (Object error, StackTrace stack) {
          observed = error;
        },
      ),
    );
    await tester.pump();
    expect(fixture.calls, hasLength(8));
    fixture.bloc.dispose();
    fixture.pending.completeError(failure, StackTrace.current);
    await tester.pump();
    expect(observed, same(failure));
    await tester.pump(kIntervalBetweenMomentums * 4);
    expect(fixture.calls, hasLength(8));
    expect(fixture.events, isEmpty);
    expect(fixture.errors, isEmpty);
  });
}
