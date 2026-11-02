import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_lock.dart';

class _LockFixture {
  final Object box = Object();
  Object wallet = Object();
  Object preferences = Object();
  Object client = Object();
  String path = 'selected.enc';
  int revision = 1;
  int count = 2;
  int stored = 2;
  bool visible = true;
  int epoch = 0;
  int writes = 0;
  int notices = 0;
  int displayed = 0;
  double? limit = 3;
  final Completer<void> notice = Completer<void>();
  final Completer<void> write = Completer<void>();

  WalletLockAttempt? capture() {
    final Object originalWallet = wallet;
    final Object originalPreferences = preferences;
    final Object originalClient = client;
    final String originalPath = path;
    final int originalRevision = revision;
    final int originalCount = count;
    final int originalEpoch = epoch;
    return WalletLockAttempt.bind(
      counterOwner: box,
      path: originalPath,
      originalCount: originalCount,
      limit: limit,
      ownsResources: () =>
          identical(wallet, originalWallet) &&
          identical(preferences, originalPreferences) &&
          identical(client, originalClient) &&
          path == originalPath &&
          revision == originalRevision,
      sourceIsCurrent: () => visible && epoch == originalEpoch,
      ownsCounter: (int? admitted) =>
          count == originalCount && stored == (admitted ?? originalCount),
      writeCounter: (int value) {
        writes++;
        stored = value;
        return write.future;
      },
      commitCounter: (int value) => count = value,
      createNotice: (Object error, String title) => error,
      writeNotice: (Object event) {
        notices++;
        return notice.future;
      },
      displayNotice: (Object event) => displayed++,
    );
  }
}

Future<void> _until(bool Function() done) async {
  for (int step = 0; step < 20 && !done(); step++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'the owned microtasks settle in twenty steps');
}

WalletLockAttempt _proofAttempt(
  bool Function() ownsResources, {
  bool Function()? sourceIsCurrent,
}) => WalletLockAttempt.bind(
  counterOwner: Object(),
  path: 'selected.enc',
  originalCount: 0,
  limit: 3,
  ownsResources: ownsResources,
  sourceIsCurrent: sourceIsCurrent ?? () => true,
  ownsCounter: (int? _) => true,
  writeCounter: (int _) => throw StateError('Unexpected counter write'),
  commitCounter: (int _) => throw StateError('Unexpected counter commit'),
  createNotice: (Object _, String _) => throw StateError('Unexpected notice'),
)!;

void main() {
  test('nested resource loss cannot be cleared by the outer lock proof', () {
    late final WalletLockAttempt original;
    bool installed = false;
    bool nested = false;
    bool current = true;
    bool? nestedCurrent;
    original = _proofAttempt(() {
      if (installed && !nested) {
        nested = true;
        current = false;
        nestedCurrent = original.ownsResources;
        current = true;
      }
      return current;
    });
    installed = true;
    expect(original.ownsResources, isFalse);
    expect(nestedCurrent, isFalse);
    expect(current, isTrue);
    expect(original.ownsResources, isFalse);
    expect(original.isCurrent, isFalse);
  });

  test('an original lock proof error still escapes unchanged', () {
    final StateError failure = StateError('Original proof failed');
    bool throwing = false;
    final WalletLockAttempt original = _proofAttempt(
      () => throwing ? throw failure : true,
    );
    throwing = true;
    expect(() => original.ownsResources, throwsA(same(failure)));
    throwing = false;
    expect(original.ownsResources, isTrue);
  });

  test('nested source loss cannot be cleared by the outer lock proof', () {
    late final WalletLockAttempt original;
    bool installed = false;
    bool nested = false;
    bool current = true;
    bool? nestedCurrent;
    original = _proofAttempt(
      () => true,
      sourceIsCurrent: () {
        if (installed && !nested) {
          nested = true;
          current = false;
          nestedCurrent = original.isCurrent;
          current = true;
        }
        return current;
      },
    );
    installed = true;
    expect(original.isCurrent, isFalse);
    expect(nestedCurrent, isFalse);
    expect(current, isTrue);
    expect(original.ownsResources, isTrue);
    expect(original.isCurrent, isFalse);
  });

  test('the outer source proof retains a nested resource refusal', () {
    late final WalletLockAttempt original;
    bool installed = false;
    bool nested = false;
    bool resourceCurrent = true;
    bool? nestedCurrent;
    int writes = 0;
    original = WalletLockAttempt.bind(
      counterOwner: Object(),
      path: 'selected.enc',
      originalCount: 0,
      limit: 3,
      ownsResources: () => resourceCurrent,
      sourceIsCurrent: () {
        if (installed && !nested) {
          nested = true;
          resourceCurrent = false;
          nestedCurrent = original.ownsResources;
          resourceCurrent = true;
        }
        return true;
      },
      ownsCounter: (int? _) => true,
      writeCounter: (int _) {
        writes++;
        throw StateError('Unexpected counter write');
      },
      commitCounter: (int _) => throw StateError('Unexpected counter commit'),
      createNotice: (Object _, String _) =>
          throw StateError('Unexpected notice'),
    )!;
    installed = true;
    expect(original.isCurrent, isFalse);
    expect(nestedCurrent, isFalse);
    expect(resourceCurrent, isTrue);
    expect(original.ownsResources, isFalse);
    expect(original.isCurrent, isFalse);
    expect(writes, 0);
  });

  test('an original lock source error still escapes unchanged', () {
    final StateError failure = StateError('Original source proof failed');
    bool throwing = false;
    final WalletLockAttempt original = _proofAttempt(
      () => true,
      sourceIsCurrent: () => throwing ? throw failure : true,
    );
    throwing = true;
    expect(() => original.isCurrent, throwsA(same(failure)));
    throwing = false;
    expect(original.isCurrent, isTrue);
  });

  test(
    'original decrypt, notice and counter retain exact Futures and errors',
    () async {
      final _LockFixture source = _LockFixture();
      final WalletLockAttempt original = source.capture()!;
      expect(source.capture(), isNull);
      final Completer<int> decrypt = Completer<int>();
      final Future<int> admitted = original.decrypt<int>((String originalPath) {
        expect(originalPath, 'selected.enc');
        return decrypt.future;
      });
      expect(admitted, same(decrypt.future));
      final StateError wrongPassword = StateError('Original password refused');
      final Future<void> observed = expectLater(
        admitted,
        throwsA(
          same(wrongPassword),
        ),
      );
      decrypt.completeError(wrongPassword);
      await observed;
      final Future<WalletLockAttemptOutcome> result = original.fail(
        wrongPassword,
        'Unlock failed',
        incorrectPassword: true,
      );
      expect(
        original.fail(wrongPassword, 'Unlock failed', incorrectPassword: true),
        same(result),
      );
      expect(source.notices, 1);
      expect(source.writes, 0);
      final StateError noticeFailure = StateError('Original notice failed');
      source.notice.completeError(noticeFailure);
      await _until(() => source.writes == 1);
      expect(source.count, 2);
      source.write.complete();
      final WalletLockAttemptOutcome outcome = await result;
      expect(outcome.originalError, same(wrongPassword));
      expect(outcome.decryption, same(decrypt.future));
      expect(outcome.notice!.future, same(source.notice.future));
      expect(outcome.notice!.error, same(noticeFailure));
      expect(outcome.noticeError, same(noticeFailure));
      expect(outcome.counter!.future, same(source.write.future));
      expect(outcome.committed, isTrue);
      expect(outcome.exhausted, isTrue);
      expect(source.count, 3);
      expect(source.displayed, 0);
      expect(original.outcomes.single, same(outcome));
      expect(original.outcomes.clear, throwsUnsupportedError);
      expect(source.capture(), isNull);
    },
  );

  for (final String replacement in <String>[
    'wallet',
    'preferences',
    'client',
    'path',
    'revision',
  ]) {
    test(
      'late failure cannot consume replacement $replacement attempts',
      () async {
        final _LockFixture source = _LockFixture();
        final WalletLockAttempt original = source.capture()!;
        final Object originalError = Object();
        final Future<WalletLockAttemptOutcome> result = original.fail(
          originalError,
          'Unlock failed',
          incorrectPassword: true,
        );
        switch (replacement) {
          case 'wallet':
            source.wallet = Object();
          case 'preferences':
            source.preferences = Object();
          case 'client':
            source.client = Object();
          case 'path':
            source.path = 'replacement.enc';
          case 'revision':
            source.revision++;
        }
        source.notice.complete();
        final WalletLockAttemptOutcome outcome = await result;
        expect(outcome.originalError, same(originalError));
        expect(outcome.committed, isFalse);
        expect(outcome.exhausted, isFalse);
        expect(source.count, 2);
        expect(source.writes, 0);
        expect(source.displayed, 0);
        expect(outcome.error, isA<WalletMaintenanceRefused>());
      },
    );
  }

  test(
    'admitted original write is observed after disposal without stale UI',
    () async {
      final _LockFixture source = _LockFixture();
      final WalletLockAttempt original = source.capture()!;
      final Future<WalletLockAttemptOutcome> result = original.fail(
        Object(),
        'Unlock failed',
        incorrectPassword: true,
      );
      source.visible = false;
      source.epoch++;
      source.notice.complete();
      await _until(() => source.writes == 1);
      source.write.complete();
      final WalletLockAttemptOutcome outcome = await result;
      expect(outcome.committed, isTrue);
      expect(outcome.exhausted, isTrue);
      expect(outcome.counter!.future, same(source.write.future));
      expect(source.count, 3);
      expect(source.displayed, 0);
      source.visible = true;
      expect(original.isCurrent, isFalse);
      expect(original.resetRequest, isNull);
    },
  );

  test(
    'counter error remains identical and holds the original Box lane',
    () async {
      final _LockFixture source = _LockFixture();
      final WalletLockAttempt original = source.capture()!;
      final Future<WalletLockAttemptOutcome> result = original
          .resetAfterDecrypt();
      expect(source.writes, 1);
      final StateError failure = StateError('Original counter write uncertain');
      source.write.completeError(failure);
      final WalletLockAttemptOutcome outcome = await result;
      expect(outcome.error, same(failure));
      expect(outcome.counter!.error, same(failure));
      expect(outcome.counter!.future, same(source.write.future));
      expect(outcome.committed, isFalse);
      expect(source.count, 2);
      expect(source.capture(), isNull);
      expect(original.resetAfterDecrypt(), same(result));
      expect(source.writes, 1);
    },
  );

  test(
    'a correct password is not exposed before the original reset commits',
    () async {
      final _LockFixture source = _LockFixture();
      final WalletLockAttempt original = source.capture()!;
      final Future<WalletLockAttemptOutcome> result = original
          .resetAfterDecrypt();
      expect(source.count, 2);
      expect(source.writes, 1);
      expect(source.notices, 0);
      source.write.complete();
      final WalletLockAttemptOutcome outcome = await result;
      expect(outcome.committed, isTrue);
      expect(outcome.exhausted, isFalse);
      expect(source.count, 0);
      expect(outcome.counter!.future, same(source.write.future));
    },
  );

  for (final int count in <int>[3, 4]) {
    test('a count at or beyond the known limit $count refuses admission', () {
      final _LockFixture source = _LockFixture()
        ..count = count
        ..stored = count;
      expect(source.capture(), isNull);
      expect(source.writes, 0);
      expect(source.notices, 0);
    });
  }

  for (final double? limit in <double?>[
    null,
    0,
    -1,
    double.infinity,
    double.nan,
    2.5,
  ]) {
    test(
      'nonpositive or unknown policy $limit cannot manufacture exhaustion',
      () async {
        final _LockFixture source = _LockFixture()..limit = limit;
        final WalletLockAttempt original = source.capture()!;
        final Future<WalletLockAttemptOutcome> result = original.fail(
          Object(),
          'Unlock failed',
          incorrectPassword: true,
        );
        source.notice.complete();
        await _until(() => source.writes == 1);
        source.write.complete();
        expect((await result).exhausted, isFalse);
        expect(source.count, 3);
      },
    );
  }

  test(
    'a non-password failure cannot consume a counter despite notice error',
    () async {
      final _LockFixture source = _LockFixture();
      final WalletLockAttempt original = source.capture()!;
      final Object originalError = Object();
      final Future<WalletLockAttemptOutcome> result = original.fail(
        originalError,
        'Unlock failed',
        incorrectPassword: false,
      );
      final StateError noticeFailure = StateError(
        'Original notice unavailable',
      );
      source.notice.completeError(noticeFailure);
      final WalletLockAttemptOutcome outcome = await result;
      expect(outcome.originalError, same(originalError));
      expect(outcome.noticeError, same(noticeFailure));
      expect(outcome.counter, isNull);
      expect(source.writes, 0);
      expect(source.count, 2);
    },
  );
}
