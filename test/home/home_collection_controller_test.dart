import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_collection_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';

class _Publisher extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

AccountBlockTemplate _response(int index) =>
    AccountBlockTemplate(blockType: BlockTypeEnum.userSend.index)
      ..hash = Hash.parse(
        List<String>.filled(64, index.toRadixString(16)).join(),
      )
      ..address = emptyAddress
      ..chainIdentifier = 321;

HomeSnapshot _snapshot() => HomeSnapshot(
  znn: BigInt.zero,
  qsr: BigInt.zero,
  tokens: const <BalanceInfoListItem>[],
  currentPlasma: 0,
  maxPlasma: 0,
  fusedQsr: BigInt.zero,
  rewards: <String, UncollectedReward>{
    for (final String source in <String>['Delegation', 'Sentinel', 'Staking'])
      source: UncollectedReward.fromJson(<String, dynamic>{
        'address': emptyAddress.toString(),
        'znnAmount': '9007199254740993',
        'qsrAmount': '1',
      }),
  },
);

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(emptyAddress);
  });

  late _Publisher publisher;
  late _Balances balances;
  late SendTransactionBloc sender;
  late InFlightBlocks flight;
  late HomeCollectionController owner;
  late HomeCollectionSession session;
  late List<AccountBlockTemplate> submitted;
  late List<Completer<AccountBlockTemplate>> gates;
  late Future<AccountBlockTemplate> Function(int index) answer;
  late bool current;
  late bool confirmed;
  late Map<HomeRewardSource, AccountBlockTemplate> templates;
  bool ownerDisposed = false;

  setUp(() {
    publisher = _Publisher();
    balances = _Balances();
    submitted = <AccountBlockTemplate>[];
    gates = <Completer<AccountBlockTemplate>>[];
    current = true;
    confirmed = false;
    ownerDisposed = false;
    answer = (int index) async => _response(index + 1);
    when(() => balances.refreshBalance()).thenAnswer((_) {});
    when(
      () => publisher.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
      ),
    ).thenAnswer((Invocation call) {
      submitted.add(call.positionalArguments.first as AccountBlockTemplate);
      return answer(submitted.length - 1);
    });
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: publisher,
      zenonAddressUtils: balances,
    );
    flight = InFlightBlocks(lookup: (_) async => confirmed);
    owner = HomeCollectionController(
      sender: sender,
      flight: flight,
      address: emptyAddress.toString(),
      chainId: 321,
    );
    templates = <HomeRewardSource, AccountBlockTemplate>{
      for (final HomeRewardSource source in HomeRewardSource.values)
        source: AccountBlockTemplate(blockType: 1),
    };
    session = HomeCollectionSession(
      address: emptyAddress.toString(),
      chainId: 321,
      isCurrent: () => current,
      buildBlock: (HomeRewardSource source) => templates[source]!,
    );
  });

  tearDown(() async {
    if (!ownerDisposed) owner.dispose();
    for (final Completer<AccountBlockTemplate> gate in gates) {
      if (!gate.isCompleted) gate.complete(_response(9));
    }
    await sender.close();
    flight.dispose();
  });

  test(
    'collects each actual source once and retains exact partial responses',
    () async {
      await owner.collect(snapshot: _snapshot(), session: session);
      expect(
        submitted,
        HomeRewardSource.values.map((HomeRewardSource s) => templates[s]),
      );
      expect(owner.accepted.map((AccountBlockTemplate b) => b.hash), <Hash>[
        _response(1).hash,
        _response(2).hash,
        _response(3).hash,
      ]);
      expect(
        flight.value.map((InFlightBlock b) => b.hash),
        owner.accepted.map((AccountBlockTemplate b) => b.hash),
      );
      expect(owner.busy, isFalse);
      expect(sender.busy.value, isFalse);
      expect(owner.canCollect(_snapshot()), isFalse);
    },
  );

  test(
    'only exact confirmation followed by a fresh read permits collection',
    () async {
      final HomeSnapshot consumed = _snapshot();
      await owner.collect(snapshot: consumed, session: session);
      final HomeCollectionRead oldRead = owner.beginRead();
      final HomeSnapshot fresh = _snapshot();
      confirmed = true;
      await flight.check();
      owner.completeRead(oldRead, isCurrent: true, snapshot: fresh);
      expect(owner.canCollect(_snapshot()), isFalse);
      final HomeCollectionRead freshRead = owner.beginRead();
      owner.completeRead(freshRead, isCurrent: false, snapshot: fresh);
      expect(owner.canCollect(_snapshot()), isFalse);
      owner.completeRead(freshRead, isCurrent: true, snapshot: fresh);
      expect(owner.canCollect(consumed), isFalse);
      expect(owner.canCollect(_snapshot()), isFalse);
      expect(owner.canCollect(fresh), isTrue);
      expect(owner.accepted, hasLength(3));
    },
  );

  test('absence or tracker clearing never establishes confirmation', () async {
    await owner.collect(snapshot: _snapshot(), session: session);
    flight.clear();
    owner.completeRead(
      owner.beginRead(),
      isCurrent: true,
      snapshot: _snapshot(),
    );
    expect(owner.canCollect(_snapshot()), isFalse);
    owner.invalidate();
    expect(flight.value, hasLength(3));
  });

  test(
    'context invalidation revokes prior positive evidence and old reads',
    () async {
      await owner.collect(snapshot: _snapshot(), session: session);
      confirmed = true;
      await flight.check();
      final HomeCollectionRead read = owner.beginRead();
      owner
        ..invalidate()
        ..completeRead(read, isCurrent: true, snapshot: _snapshot());
      expect(owner.canCollect(_snapshot()), isFalse);
      expect(flight.value, hasLength(3));
      expect(flight.hasConfirmed(_response(1).hash), isFalse);
      await flight.check();
      final HomeSnapshot fresh = _snapshot();
      owner.completeRead(owner.beginRead(), isCurrent: true, snapshot: fresh);
      expect(owner.canCollect(fresh), isTrue);
    },
  );

  for (final bool restore in <bool>[false, true]) {
    test(
      'a revoked batch stops remaining sources, restore=$restore',
      () async {
        final Completer<AccountBlockTemplate> first =
            Completer<AccountBlockTemplate>();
        gates.add(first);
        answer = (_) => first.future;
        final Future<void> collecting = owner.collect(
          snapshot: _snapshot(),
          session: session,
        );
        await Future<void>.delayed(Duration.zero);
        expect(submitted, hasLength(1));
        current = false;
        owner.invalidate();
        current = restore;
        first.complete(_response(1));
        await collecting;
        expect(submitted, hasLength(1));
        expect(owner.accepted.single.hash, _response(1).hash);
        expect(owner.unresolved, isNull);
        expect(sender.busy.value, isFalse);
      },
    );
  }

  test(
    'an unknown result retains its original attempt without implicit retry',
    () async {
      final StateError original = StateError(
        'Fixture transport outcome unknown',
      );
      answer = (_) => Future<AccountBlockTemplate>.error(original);
      await owner.collect(snapshot: _snapshot(), session: session);
      final HomeCollectionAttempt attempt = owner.unresolved!;
      expect(attempt.error, same(original));
      expect(attempt.source, HomeRewardSource.pillar);
      owner.completeRead(
        owner.beginRead(),
        isCurrent: true,
        snapshot: _snapshot(),
      );
      owner.invalidate();
      await owner.collect(snapshot: _snapshot(), session: session);
      expect(owner.unresolved, same(attempt));
      expect(submitted, hasLength(1));
      expect(owner.accepted, isEmpty);
    },
  );

  test(
    'a later failure retains accepted hashes and stops before source three',
    () async {
      final StateError original = StateError('Second fixture outcome unknown');
      answer = (int index) async {
        if (index == 1) throw original;
        return _response(index + 1);
      };
      await owner.collect(snapshot: _snapshot(), session: session);
      expect(submitted, hasLength(2));
      expect(owner.accepted.single.hash, _response(1).hash);
      expect(flight.value.single.hash, _response(1).hash);
      expect(owner.unresolved!.source, HomeRewardSource.sentinel);
      expect(owner.unresolved!.error, same(original));
      expect(owner.canCollect(_snapshot()), isFalse);
    },
  );

  test(
    'a mismatched returned chain is retained without enabling another request',
    () async {
      final AccountBlockTemplate original = _response(1)..chainIdentifier = 999;
      answer = (_) async => original;
      await owner.collect(snapshot: _snapshot(), session: session);
      expect(owner.unresolved!.block, same(original));
      expect(submitted, hasLength(1));
      expect(owner.canCollect(_snapshot()), isFalse);
      expect(flight.value, isEmpty);
    },
  );

  test('a stale context refuses before reserving or publishing', () async {
    current = false;
    await owner.collect(snapshot: _snapshot(), session: session);
    expect(submitted, isEmpty);
    expect(sender.busy.value, isFalse);
  });

  test('another address or chain cannot borrow the retained owner', () async {
    for (final bool wrongChain in <bool>[false, true]) {
      final HomeCollectionSession other = HomeCollectionSession(
        address: wrongChain ? emptyAddress.toString() : 'another address',
        chainId: wrongChain ? 999 : 321,
        isCurrent: () => true,
        buildBlock: (_) => throw StateError('Must refuse before preparation'),
      );
      await owner.collect(snapshot: _snapshot(), session: other);
      expect(submitted, isEmpty);
      expect(sender.busy.value, isFalse);
    }
  });

  test(
    'disposing the view owner preserves an original in-flight result',
    () async {
      final Completer<AccountBlockTemplate> first =
          Completer<AccountBlockTemplate>();
      gates.add(first);
      answer = (_) => first.future;
      final Future<void> collecting = owner.collect(
        snapshot: _snapshot(),
        session: session,
      );
      await Future<void>.delayed(Duration.zero);
      owner.dispose();
      ownerDisposed = true;
      first.complete(_response(1));
      await collecting;
      expect(submitted, hasLength(1));
      expect(owner.accepted.single.hash, _response(1).hash);
      expect(sender.busy.value, isFalse);
    },
  );

  test(
    'template failure publishes nothing and a fresh read can rearm it',
    () async {
      final FlutterExceptionHandler? previous = FlutterError.onError;
      final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      try {
        session = HomeCollectionSession(
          address: emptyAddress.toString(),
          chainId: 321,
          isCurrent: () => true,
          buildBlock: (_) => throw StateError('Fixture preparation failure'),
        );
        final HomeSnapshot snapshot = _snapshot();
        await owner.collect(snapshot: snapshot, session: session);
        expect(errors, hasLength(1));
        expect(submitted, isEmpty);
        expect(owner.unresolved, isNull);
        expect(owner.canCollect(snapshot), isFalse);
        final HomeSnapshot fresh = _snapshot();
        expect(owner.canCollect(fresh), isFalse);
        owner.completeRead(owner.beginRead(), isCurrent: true, snapshot: fresh);
        expect(owner.canCollect(snapshot), isFalse);
        expect(owner.canCollect(fresh), isTrue);
      } finally {
        FlutterError.onError = previous;
      }
    },
  );
}
