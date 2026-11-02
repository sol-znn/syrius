import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_lock.dart';

// Ports are plain objects and in-memory counters. Nothing opens a wallet,
// creates a replacement service, reads a Box or requests a connection.
class _Fixture {
  final Object counter = Object();
  final Object initializationOwner = Object();
  final Object connection = Object();
  final Object file = Object();
  Object service = Object();
  int count = 0;
  int stored = 0;
  int captures = 0;
  int begins = 0;
  int persists = 0;
  int publishes = 0;
  int factories = 0;
  Object? startup;

  WalletLockAttempt capture() {
    captures++;
    final Object originalService = service;
    final int originalCount = count;
    final WalletInitializationBinding initialization =
        WalletInitializationBinding(
          identity: initializationOwner,
          connectionOwner: connection,
          startupAdmissionReceipt: () => startup,
          isCurrent: () => identical(service, originalService),
          begin: () {
            begins++;
            startup = Object();
          },
          prepare: (_, _) async => WalletInitializationData(
            path: 'fixture.enc',
            members: <String>['fixture-member'],
            labels: <String, String>{'fixture-member': 'Address 1'},
            selected: 'fixture-member',
            chainId: 1,
          ),
          persist: (_, _, _, _) async {
            persists++;
          },
          connect: (_) async => WalletInitializationConnection(
            owner: connection,
            connected: true,
            chainId: 1,
            state: WalletInitializationNetworkState.compatible,
          ),
          admitLocal: (_) => true,
          activate: () => true,
          publish: (_, _) {
            publishes++;
            return true;
          },
        );
    return WalletLockAttempt.bind(
      counterOwner: counter,
      path: 'fixture.enc',
      originalCount: originalCount,
      limit: 3,
      initialization: initialization,
      ownsResources: () => true,
      sourceIsCurrent: () => true,
      ownsCounter: (int? admitted) =>
          count == originalCount && stored == (admitted ?? originalCount),
      writeCounter: (int value) {
        stored = value;
        return Future<void>.value();
      },
      commitCounter: (int value) => count = value,
      createNotice: (Object error, String _) => error,
    )!;
  }

  WalletInitializationRun initialize(
    WalletLockAttempt attempt,
    Object original,
  ) => attempt.initialization!.start(
    create: () {
      factories++;
      return Future<Object>.value(original);
    },
    cipherKey: const <int>[],
  );
}

void main() {
  test(
    'replacement during decrypt cannot be recaptured for initialization',
    () async {
      final _Fixture fixture = _Fixture();
      final WalletLockAttempt attempt = fixture.capture();
      final WalletInitializationBinding captured = attempt.initialization!;
      final Completer<Object> decrypt = Completer<Object>();
      final Future<Object> original = attempt.decrypt<Object>(
        (_) => decrypt.future,
      );
      fixture.service = Object();
      decrypt.complete(fixture.file);
      final Object file = await original;
      expect(
        attempt.isCurrent,
        isTrue,
        reason: 'the counter resources did not change with this startup owner',
      );
      expect(attempt.initialization, same(captured));
      final WalletInitializationOutcome outcome = await fixture
          .initialize(attempt, file)
          .completion;
      expect(attempt.decryption, same(decrypt.future));
      expect(file, same(fixture.file));
      expect(outcome.error, isA<WalletInitializationRefused>());
      expect(outcome.published, isFalse);
      expect(fixture.captures, 1);
      expect(fixture.factories, 0);
      expect(fixture.begins, 0);
      expect(fixture.persists, 0);
      expect(fixture.publishes, 0);
    },
  );

  test(
    'correct decrypt retains its original file and begin-time admission',
    () async {
      final _Fixture fixture = _Fixture();
      final WalletLockAttempt attempt = fixture.capture();
      expect(fixture.begins, 0);
      expect(fixture.startup, isNull);
      final Object file = await attempt.decrypt<Object>(
        (_) => Future<Object>.value(fixture.file),
      );
      expect((await attempt.resetAfterDecrypt()).committed, isTrue);
      final WalletInitializationRun run = fixture.initialize(attempt, file);
      final WalletInitializationOutcome outcome = await run.completion;
      expect(outcome.initialized, isTrue);
      expect(outcome.file, same(file));
      expect(outcome.startupAdmission, same(fixture.startup));
      expect(fixture.begins, 1);
      expect(fixture.persists, 1);
      expect(fixture.publishes, 1);
      expect(fixture.initialize(attempt, Object()), same(run));
      expect(fixture.factories, 1);
    },
  );

  test(
    'wrong password leaves startup admission available to a later attempt',
    () async {
      final _Fixture fixture = _Fixture();
      final WalletLockAttempt wrong = fixture.capture();
      final Object error = StateError('Fixture wrong password');
      await expectLater(
        wrong.decrypt<Object>((_) => Future<Object>.error(error)),
        throwsA(same(error)),
      );
      expect(
        (await wrong.fail(
          error,
          'Unlock failed',
          incorrectPassword: true,
        )).committed,
        isTrue,
      );
      expect(fixture.begins, 0);
      expect(fixture.startup, isNull);
      final WalletLockAttempt correct = fixture.capture();
      final Object file = await correct.decrypt<Object>(
        (_) => Future<Object>.value(fixture.file),
      );
      expect((await correct.resetAfterDecrypt()).committed, isTrue);
      expect(
        (await fixture.initialize(correct, file).completion).initialized,
        isTrue,
      );
      expect(fixture.begins, 1);
      expect(fixture.factories, 1);
    },
  );
}
