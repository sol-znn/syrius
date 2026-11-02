import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';

// Every capability here is inert. No wallet factory, Box, cipher, socket,
// native worker, filesystem, credential or SDK service is constructed.
class _Fixture {
  final Object identity = Object();
  final Object file = Object();
  final Object connection = Object();
  final Object startup = Object();
  final List<String> events = <String>[];
  bool current = true;
  bool Function()? currentProof;
  bool finish = true;
  bool activate = true;
  bool publish = true;
  Object? receiptOwner;
  bool connected = true;
  int? receiptChain = 1;
  WalletInitializationNetworkState networkState =
      WalletInitializationNetworkState.compatible;
  bool transportUncertain = false;
  WalletInitializationConnection? admittedConnection;
  Object? publishedFile;
  WalletInitializationData? publishedData;
  List<int>? observedMarkers;
  void Function(String)? entering;
  Completer<void>? prepareGate;
  Completer<void>? persistGate;
  Completer<void>? connectGate;
  Future<WalletInitializationData> Function(Object, WalletInitializationRun)?
  prepare;
  Future<void> Function(
    Object,
    WalletInitializationData,
    WalletInitializationRun,
  )?
  persist;
  Future<void> Function(Object, Future<void> Function())? protect;
  Future<WalletInitializationConnection> Function(WalletInitializationRun)?
  connectionStep;
  WalletInitializationData data = WalletInitializationData(
    path: 'fixture-source',
    members: <String>['member-a'],
    labels: <String, String>{'member-a': 'Address 1'},
    selected: 'member-a',
    chainId: 1,
  );

  void enter(String name) {
    events.add(name);
    entering?.call(name);
  }

  late final WalletInitializationBinding binding = WalletInitializationBinding(
    identity: identity,
    connectionOwner: connection,
    startupAdmission: startup,
    isCurrent: () => currentProof?.call() ?? current,
    begin: () => enter('begin'),
    protect: (Object original, Future<void> Function() action) {
      enter('protect');
      return protect?.call(original, action) ?? action();
    },
    prepare: (Object original, WalletInitializationRun run) async {
      enter('prepare');
      if (prepareGate != null) await prepareGate!.future;
      return prepare == null ? data : await prepare!(original, run);
    },
    persist:
        (
          Object original,
          WalletInitializationData prepared,
          List<int> markers,
          WalletInitializationRun run,
        ) async {
          enter('persist');
          observedMarkers = markers;
          if (persistGate != null) await persistGate!.future;
          await persist?.call(original, prepared, run);
        },
    connect: (WalletInitializationRun run) async {
      enter('connect');
      if (connectGate != null) await connectGate!.future;
      if (connectionStep != null) return connectionStep!(run);
      return WalletInitializationConnection(
        owner: receiptOwner ?? connection,
        connected: connected,
        chainId: receiptChain,
        state: networkState,
        transportUncertain: transportUncertain,
      );
    },
    admitLocal: (WalletInitializationConnection connection) {
      enter('finish');
      admittedConnection = connection;
      return finish;
    },
    activate: () {
      enter('activate');
      return activate;
    },
    publish: (Object original, WalletInitializationData prepared) {
      enter('publish');
      publishedFile = original;
      publishedData = prepared;
      return publish;
    },
  );
  WalletInitializationRun start({
    Future<Object>? creation,
    List<int> markers = const <int>[],
  }) => binding.start(
    create: () {
      enter('file');
      return creation ?? Future<Object>.value(file);
    },
    cipherKey: markers,
  );
}

Future<void> _turns() async {
  // A finite microtask budget inspects pending work without elapsed timers.
  for (int index = 0; index < 24; index++) {
    await Future<void>.value();
  }
}

void main() {
  test('an outer binding proof cannot erase nested retirement', () async {
    final _Fixture fixture = _Fixture();
    int proofs = 0;
    fixture.currentProof = () {
      proofs++;
      if (proofs == 1) {
        fixture.current = false;
        expect(fixture.binding.isCurrent, isFalse);
        fixture.current = true;
        return true;
      }
      return fixture.current;
    };
    expect(fixture.binding.isCurrent, isFalse);
    expect(fixture.binding.isCurrent, isFalse);
    expect(
      fixture.binding.requireCurrent,
      throwsA(isA<WalletInitializationRefused>()),
    );
    int factories = 0;
    final WalletInitializationOutcome outcome = await fixture.binding
        .start(
          create: () {
            factories++;
            return Future<Object>.value(fixture.file);
          },
          cipherKey: const <int>[],
        )
        .completion;
    expect(outcome.error, isA<WalletInitializationRefused>());
    expect(outcome.published, isFalse);
    expect(outcome.file, isNull);
    expect(factories, 0);
    expect(fixture.events, isEmpty);
    expect(proofs, 2);
  });

  test(
    'original positive receipts precede synchronous admission and publication',
    () async {
      final _Fixture fixture = _Fixture();
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(fixture.events, <String>[
        'begin',
        'file',
        'protect',
        'prepare',
        'persist',
        'connect',
        'finish',
        'activate',
        'publish',
      ]);
      expect(
        outcome.published && outcome.initialized && outcome.startupAdmitted,
        isTrue,
      );
      expect(outcome.startupAdmission, same(fixture.startup));
      expect(outcome.file, same(fixture.file));
      expect(fixture.publishedFile, same(fixture.file));
      expect(fixture.publishedData, same(outcome.data));
    },
  );

  test(
    'one backend identity coalesces duplicate and remounted requests',
    () async {
      final _Fixture fixture = _Fixture();
      final Completer<Object> creation = Completer<Object>();
      final WalletInitializationRun first = fixture.start(
        creation: creation.future,
      );
      final WalletInitializationRun duplicate = fixture.start();
      bool replacementCalled = false;
      final WalletInitializationBinding replacement =
          WalletInitializationBinding(
            identity: fixture.identity,
            connectionOwner: Object(),
            isCurrent: () => true,
            begin: () => fail('replacement began'),
            prepare: (_, _) async => throw StateError('replacement'),
            persist: (_, _, _, _) async => fail('replacement persisted'),
            connect: (_) async => throw StateError('replacement'),
            admitLocal: (_) => false,
            activate: () => false,
            publish: (_, _) => false,
          );
      final WalletInitializationRun remounted = replacement.start(
        create: () {
          replacementCalled = true;
          return Future<Object>.value(Object());
        },
        cipherKey: const <int>[],
      );
      expect(duplicate, same(first));
      expect(remounted, same(first));
      creation.complete(fixture.file);
      await first.completion;
      expect(replacementCalled, isFalse);
      expect(
        fixture.events.where((String value) => value == 'file'),
        hasLength(1),
      );
    },
  );

  test(
    'stale creation keeps the exact returned file and original Future',
    () async {
      final _Fixture fixture = _Fixture();
      final Completer<Object> creation = Completer<Object>();
      final WalletInitializationRun run = fixture.start(
        creation: creation.future,
      );
      fixture.current = false;
      creation.complete(fixture.file);
      final WalletInitializationOutcome outcome = await run.completion;
      expect(outcome.file, same(fixture.file));
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) => item.name == 'file',
            )
            .original,
        same(creation.future),
      );
      expect(outcome.published, isFalse);
      expect(fixture.events.contains('prepare'), isFalse);
      fixture.current = true;
      expect(fixture.binding.isCurrent, isFalse);
      expect(fixture.start(), same(run));
    },
  );

  test(
    'factory error keeps its identity without creating a replacement',
    () async {
      final _Fixture fixture = _Fixture();
      final Object error = StateError('fixture failure');
      final Completer<Object> creation = Completer<Object>();
      final WalletInitializationRun run = fixture.start(
        creation: creation.future,
      );
      creation.completeError(error, StackTrace.empty);
      final WalletInitializationOutcome outcome = await run.completion;
      expect(outcome.error, same(error));
      expect(outcome.file, isNull);
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) => item.name == 'file',
            )
            .error,
        same(error),
      );
      expect(fixture.start(), same(run));
      expect(fixture.events.contains('persist'), isFalse);
    },
  );

  for (final String stage in <String>[
    'begin',
    'prepare',
    'persist',
    'connect',
    'finish',
    'activate',
  ]) {
    test('source departure at $stage prevents publication', () async {
      final _Fixture fixture = _Fixture();
      fixture.entering = (String entered) {
        if (entered == stage) fixture.current = false;
      };
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.published, isFalse);
      expect(outcome.initialized, isFalse);
      expect(fixture.events.contains('publish'), isFalse);
      if (stage == 'activate') expect(outcome.startupAdmitted, isTrue);
    });
  }

  for (final String stage in <String>['prepare', 'persist', 'connect']) {
    test(
      '$stage pending original survives route disposal and is awaited',
      () async {
        final _Fixture fixture = _Fixture();
        final Completer<void> gate = Completer<void>();
        if (stage == 'prepare') fixture.prepareGate = gate;
        if (stage == 'persist') fixture.persistGate = gate;
        if (stage == 'connect') fixture.connectGate = gate;
        final WalletInitializationRun run = fixture.start();
        await _turns();
        expect(fixture.events.last, stage);
        expect(run.outcome, isNull);
        fixture.current = false;
        gate.complete();
        final WalletInitializationOutcome outcome = await run.completion;
        expect(outcome.file, same(fixture.file));
        expect(outcome.published, isFalse);
        expect(
          outcome.operations.every(
            (WalletInitializationOperation value) => value.completed,
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'admitted operation error is retained unchanged after source departure',
    () async {
      final _Fixture fixture = _Fixture();
      final Completer<void> write = Completer<void>();
      final Object failure = StateError('fixture write');
      fixture.persist = (_, _, WalletInitializationRun run) =>
          run.observe<void>('exact-write', () => write.future);
      final WalletInitializationRun run = fixture.start();
      await _turns();
      fixture.current = false;
      write.completeError(failure, StackTrace.empty);
      final WalletInitializationOutcome outcome = await run.completion;
      final WalletInitializationOperation operation = outcome.operations
          .singleWhere(
            (WalletInitializationOperation item) => item.name == 'exact-write',
          );
      expect(operation.original, same(write.future));
      expect(operation.error, same(failure));
      expect(outcome.error, same(failure));
      expect(outcome.published, isFalse);
    },
  );

  test(
    'acquisition and release stay distinct and release is awaited',
    () async {
      final _Fixture fixture = _Fixture();
      final Object acquired = Object();
      final Completer<void> release = Completer<void>();
      fixture.prepare = (_, WalletInitializationRun run) async {
        await run.observe<Object>(
          'exact-acquire',
          () => Future<Object>.value(acquired),
        );
        try {
          return fixture.data;
        } finally {
          await run.observe<void>('exact-release', () => release.future);
        }
      };
      final WalletInitializationRun run = fixture.start();
      await _turns();
      expect(run.outcome, isNull);
      expect(fixture.events.contains('persist'), isFalse);
      fixture.current = false;
      release.complete();
      final WalletInitializationOutcome outcome = await run.completion;
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) =>
                  item.name == 'exact-acquire',
            )
            .result,
        same(acquired),
      );
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) =>
                  item.name == 'exact-release',
            )
            .original,
        same(release.future),
      );
      expect(outcome.published, isFalse);
    },
  );

  test(
    'release failure preserves the result and both original operation errors',
    () async {
      final _Fixture fixture = _Fixture();
      final Object acquisition = Object();
      final Object deriveError = StateError('fixture derive');
      final Object releaseError = StateError('fixture release');
      fixture.prepare = (_, WalletInitializationRun run) async {
        await run.observe<Object>(
          'exact-acquire',
          () => Future<Object>.value(acquisition),
        );
        try {
          await run.observe<void>(
            'exact-derive',
            () => Future<void>.error(deriveError, StackTrace.empty),
          );
          return fixture.data;
        } finally {
          await run.observe<void>(
            'exact-release',
            () => Future<void>.error(releaseError, StackTrace.empty),
          );
        }
      };
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.file, same(fixture.file));
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) =>
                  item.name == 'exact-acquire',
            )
            .result,
        same(acquisition),
      );
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) =>
                  item.name == 'exact-derive',
            )
            .error,
        same(deriveError),
      );
      expect(
        outcome.operations
            .singleWhere(
              (WalletInitializationOperation item) =>
                  item.name == 'exact-release',
            )
            .error,
        same(releaseError),
      );
      expect(outcome.error, same(releaseError));
      expect(outcome.published, isFalse);
      expect(fixture.events.contains('persist'), isFalse);
    },
  );

  test(
    'protected initialization retains the original file and whole completion',
    () async {
      final _Fixture fixture = _Fixture();
      final Completer<void> release = Completer<void>();
      Object? protectedFile;
      fixture.protect = (Object file, Future<void> Function() action) async {
        protectedFile = file;
        await action();
        await release.future;
      };
      final WalletInitializationRun run = fixture.start();
      await _turns();
      expect(protectedFile, same(fixture.file));
      expect(fixture.events.last, 'publish');
      expect(run.outcome, isNull);
      release.complete();
      expect((await run.completion).published, isTrue);
    },
  );

  test(
    'late protection error retains publication but refuses initialized success',
    () async {
      final _Fixture fixture = _Fixture();
      final StateError error = StateError('fixture protection');
      fixture.protect = (_, Future<void> Function() action) async {
        await action();
        throw error;
      };
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.published, isTrue);
      expect(outcome.file, same(fixture.file));
      expect(outcome.initialized, isFalse);
      expect(outcome.error, same(error));
    },
  );

  test(
    'caller marker mutation cannot replace captured persistence inputs',
    () async {
      final _Fixture fixture = _Fixture();
      final Completer<Object> creation = Completer<Object>();
      // These are inert protocol markers, never encryption material.
      final List<int> markers = <int>[1];
      final WalletInitializationRun run = fixture.start(
        creation: creation.future,
        markers: markers,
      );
      markers[0] = 2;
      creation.complete(fixture.file);
      await run.completion;
      expect(fixture.observedMarkers, <int>[1]);
      expect(() => fixture.observedMarkers!.add(3), throwsUnsupportedError);
    },
  );

  for (final String invalid in <String>[
    'empty',
    'duplicate',
    'selected',
    'chain',
    'path',
  ]) {
    test(
      'invalid $invalid membership data refuses before persistence',
      () async {
        final _Fixture fixture = _Fixture()
          ..data = WalletInitializationData(
            path: invalid == 'path' ? '' : 'fixture-source',
            members: invalid == 'empty'
                ? <String>[]
                : invalid == 'duplicate'
                ? <String>['member-a', 'member-a']
                : <String>['member-a'],
            labels: <String, String>{},
            selected: invalid == 'selected' ? 'member-b' : 'member-a',
            chainId: invalid == 'chain' ? 0 : 1,
          );
        final WalletInitializationOutcome outcome = await fixture
            .start()
            .completion;
        expect(outcome.published, isFalse);
        expect(fixture.events.contains('persist'), isFalse);
      },
    );
  }

  for (final String invalid in <String>[
    'owner',
    'disconnected',
    'chain',
    'finish',
    'activation',
    'publication',
  ]) {
    test('missing $invalid receipt cannot establish initialization', () async {
      final _Fixture fixture = _Fixture();
      if (invalid == 'owner') fixture.receiptOwner = Object();
      if (invalid == 'disconnected') fixture.connected = false;
      if (invalid == 'chain') fixture.receiptChain = 2;
      if (invalid == 'finish') fixture.finish = false;
      if (invalid == 'activation') fixture.activate = false;
      if (invalid == 'publication') fixture.publish = false;
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.initialized, isFalse);
      expect(outcome.published, isFalse);
      expect(outcome.file, same(fixture.file));
    });
  }

  test(
    'positive connection read alone cannot prove a successful worker cycle',
    () async {
      final _Fixture fixture = _Fixture();
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.startupAdmitted, isTrue);
      expect(outcome.startupAdmission, same(fixture.startup));
      expect(
        outcome.operations.any(
          (WalletInitializationOperation item) => item.name == 'worker-rpc',
        ),
        isFalse,
      );
    },
  );

  test(
    'known mismatch admits setup and keeps the observed chain and consent',
    () async {
      final _Fixture fixture = _Fixture()
        ..networkState = WalletInitializationNetworkState.knownMismatch
        ..receiptChain = 321;
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.initialized, isTrue);
      expect(outcome.published, isTrue);
      expect(
        outcome.connection!.state,
        WalletInitializationNetworkState.knownMismatch,
      );
      expect(outcome.connection!.chainId, 321);
      expect(outcome.data!.chainId, 1);
      expect(outcome.connection, same(fixture.admittedConnection));
      expect(outcome.canShowQuarantinedReady, isFalse);
    },
  );

  test(
    'unavailable transport admits local receipts while retaining quarantine',
    () async {
      final _Fixture fixture = _Fixture()
        ..networkState = WalletInitializationNetworkState.unavailable
        ..connected = false
        ..receiptChain = null
        ..transportUncertain = true;
      final WalletInitializationOutcome outcome = await fixture
          .start()
          .completion;
      expect(outcome.initialized, isTrue);
      expect(outcome.published, isTrue);
      expect(outcome.connection!.connected, isFalse);
      expect(outcome.connection!.chainId, isNull);
      expect(outcome.connection!.transportUncertain, isTrue);
      expect(outcome.canShowQuarantinedReady, isTrue);
      expect(
        outcome.connection!.state,
        WalletInitializationNetworkState.unavailable,
      );
    },
  );

  test(
    'failed frontier read stays private while local setup observes Unknown',
    () async {
      final _Fixture fixture = _Fixture();
      final Object failure = StateError('fixture frontier');
      final Completer<Object> frontier = Completer<Object>();
      fixture.connectionStep = (WalletInitializationRun run) async {
        try {
          await run.observe<Object>('exact-frontier', () => frontier.future);
        } on Object {
          return WalletInitializationConnection(
            owner: fixture.connection,
            connected: true,
            chainId: null,
            state: WalletInitializationNetworkState.unavailable,
          );
        }
        throw StateError('fixture should fail');
      };
      final WalletInitializationRun run = fixture.start();
      await _turns();
      frontier.completeError(failure, StackTrace.empty);
      final WalletInitializationOutcome outcome = await run.completion;
      final WalletInitializationOperation operation = outcome.operations
          .singleWhere(
            (WalletInitializationOperation item) =>
                item.name == 'exact-frontier',
          );
      expect(operation.original, same(frontier.future));
      expect(operation.error, same(failure));
      expect(outcome.initialized, isTrue);
      expect(outcome.connection!.chainId, isNull);
      expect(outcome.connection!.connected, isTrue);
      expect(outcome.canShowQuarantinedReady, isFalse);
      expect(outcome.error, isNull);
    },
  );

  for (final String claim in <String>[
    'mismatch-disconnected',
    'unavailable-chain',
    'unavailable-connected-uncertain',
    'compatible-unknown',
    'compatible-uncertain',
  ]) {
    test(
      'inconsistent $claim receipt cannot establish local admission',
      () async {
        final _Fixture fixture = _Fixture();
        if (claim == 'mismatch-disconnected') {
          fixture
            ..networkState = WalletInitializationNetworkState.knownMismatch
            ..connected = false
            ..receiptChain = 321;
        }
        if (claim == 'unavailable-chain') {
          fixture.networkState = WalletInitializationNetworkState.unavailable;
        }
        if (claim == 'unavailable-connected-uncertain') {
          fixture
            ..networkState = WalletInitializationNetworkState.unavailable
            ..receiptChain = null
            ..transportUncertain = true;
        }
        if (claim == 'compatible-unknown') fixture.receiptChain = null;
        if (claim == 'compatible-uncertain') fixture.transportUncertain = true;
        final WalletInitializationOutcome outcome = await fixture
            .start()
            .completion;
        expect(outcome.initialized, isFalse);
        expect(outcome.published, isFalse);
        expect(fixture.admittedConnection, isNull);
      },
    );
  }

  test('startup data copies membership and labels once', () {
    final List<String> members = <String>['member-a'];
    final Map<String, String> labels = <String, String>{
      'member-a': 'Address 1',
    };
    final WalletInitializationData data = WalletInitializationData(
      path: 'fixture-source',
      members: members,
      labels: labels,
      selected: 'member-a',
      chainId: 1,
    );
    members[0] = 'member-b';
    labels.clear();
    expect(data.members, <String>['member-a']);
    expect(data.labels, <String, String>{'member-a': 'Address 1'});
    expect(() => data.members.add('member-b'), throwsUnsupportedError);
    expect(data.labels.clear, throwsUnsupportedError);
  });

  test(
    'operation refuses reuse without replacing its original positive result',
    () async {
      final WalletInitializationOperation operation =
          WalletInitializationOperation('fixture');
      final Object original = Object();
      final Future<Object> future = Future<Object>.value(original);
      await operation.run<Object>(() => future);
      await expectLater(
        operation.run<Object>(() => Future<Object>.value(Object())),
        throwsA(isA<WalletInitializationRefused>()),
      );
      expect(operation.original, same(future));
      expect(operation.result, same(original));
    },
  );
}
