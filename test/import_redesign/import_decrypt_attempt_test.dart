import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_decrypt_attempt.dart';

class _EncryptedFixture {}

class _WrongPassword implements Exception {}

void main() {
  test(
    'one original result waits for its original access release before Ready',
    () async {
      final Object source = Object();
      final _EncryptedFixture encrypted = _EncryptedFixture();
      final Completer<_EncryptedFixture> decrypt =
          Completer<_EncryptedFixture>();
      final Completer<String> seed = Completer<String>();
      final Completer<void> release = Completer<void>();
      final Completer<void> opened = Completer<void>();
      late Future<String> ownedAccess;
      bool released = false;
      int decryptions = 0;
      final ImportDecryptAttempt<_EncryptedFixture> attempt =
          ImportDecryptAttempt<_EncryptedFixture>(
            path: 'fixture.backup',
            source: source,
            decrypt: (String path, String password) {
              expect(path, 'fixture.backup');
              expect(password, 'fixture input');
              decryptions++;
              return decrypt.future;
            },
            accessOriginal: (_EncryptedFixture original) {
              expect(identical(original, encrypted), isTrue);
              return ownedAccess = () async {
                opened.complete();
                try {
                  return await seed.future;
                } finally {
                  await release.future;
                  released = true;
                }
              }();
            },
            isCurrent: () => true,
            validateSeed: (String value) => value == 'fixture result',
            isIncorrectPassword: (_) => false,
          );
      final Future<ImportDecryptOutcome> result = attempt.start(
        'fixture input',
      );
      expect(identical(attempt.start('replacement input'), result), isTrue);
      expect(identical(attempt.decryption, decrypt.future), isTrue);
      decrypt.complete(encrypted);
      await opened.future;
      expect(identical(attempt.original, encrypted), isTrue);
      expect(identical(attempt.access, ownedAccess), isTrue);
      seed.complete('fixture result');
      await Future<void>.value();
      expect(released, isFalse);
      release.complete();
      final ImportDecryptOutcome outcome = await result;
      expect(outcome.status, ImportDecryptStatus.ready);
      expect(outcome.seed, 'fixture result');
      expect(released, isTrue);
      expect(decryptions, 1);
    },
  );

  test('an invalidated decrypt keeps its result and never opens it', () async {
    bool current = true;
    int opens = 0;
    final _EncryptedFixture encrypted = _EncryptedFixture();
    final Completer<_EncryptedFixture> original =
        Completer<_EncryptedFixture>();
    final ImportDecryptAttempt<_EncryptedFixture> attempt =
        ImportDecryptAttempt<_EncryptedFixture>(
          path: 'fixture-no-extension',
          source: Object(),
          decrypt: (_, _) => original.future,
          accessOriginal: (_) async {
            opens++;
            return 'unused';
          },
          isCurrent: () => current,
          validateSeed: (_) => true,
          isIncorrectPassword: (_) => false,
        );
    final Future<ImportDecryptOutcome> result = attempt.start('fixture input');
    current = false;
    original.complete(encrypted);
    final ImportDecryptOutcome outcome = await result;
    expect(outcome.status, ImportDecryptStatus.stale);
    expect(outcome.seed, isNull);
    expect(identical(attempt.original, encrypted), isTrue);
    expect(opens, 0);
  });

  test(
    'coverage during access awaits its original release and emits no seed',
    () async {
      bool current = true;
      bool released = false;
      final Completer<void> opened = Completer<void>();
      final Completer<void> release = Completer<void>();
      final ImportDecryptAttempt<_EncryptedFixture> attempt =
          ImportDecryptAttempt<_EncryptedFixture>(
            path: 'fixture.data',
            source: Object(),
            decrypt: (_, _) async => _EncryptedFixture(),
            accessOriginal: (_) async {
              opened.complete();
              try {
                return 'fixture result';
              } finally {
                await release.future;
                released = true;
              }
            },
            isCurrent: () => current,
            validateSeed: (_) => true,
            isIncorrectPassword: (_) => false,
          );
      final Future<ImportDecryptOutcome> result = attempt.start(
        'fixture input',
      );
      await opened.future;
      current = false;
      expect(released, isFalse);
      release.complete();
      final ImportDecryptOutcome outcome = await result;
      expect(released, isTrue);
      expect(outcome.status, ImportDecryptStatus.stale);
      expect(outcome.seed, isNull);
    },
  );

  test(
    'path, source and decryptor replacement cannot redirect an owned future',
    () async {
      final Object capturedSource = Object();
      Object liveSource = capturedSource;
      String livePath = 'fixture.original';
      int replacements = 0;
      final Completer<_EncryptedFixture> original =
          Completer<_EncryptedFixture>();
      Future<_EncryptedFixture> Function(String, String) decryptor =
          (String path, String _) {
            expect(path, 'fixture.original');
            return original.future;
          };
      final ImportDecryptAttempt<_EncryptedFixture> attempt =
          ImportDecryptAttempt<_EncryptedFixture>(
            path: livePath,
            source: capturedSource,
            decrypt: decryptor,
            accessOriginal: (_) async => 'fixture result',
            isCurrent: () => identical(capturedSource, liveSource),
            validateSeed: (_) => true,
            isIncorrectPassword: (_) => false,
          );
      final Future<ImportDecryptOutcome> result = attempt.start(
        'fixture input',
      );
      livePath = 'fixture.replacement';
      liveSource = Object();
      decryptor = (_, _) async {
        replacements++;
        return _EncryptedFixture();
      };
      original.complete(_EncryptedFixture());
      expect((await result).status, ImportDecryptStatus.stale);
      expect(attempt.path, 'fixture.original');
      expect(identical(attempt.source, capturedSource), isTrue);
      expect(identical(attempt.decryption, original.future), isTrue);
      expect(replacements, 0);
      expect(livePath, 'fixture.replacement');
    },
  );

  test(
    'an original release error is retained and cannot produce a ready seed',
    () async {
      final StateError failure = StateError('Synthetic release failure');
      Future<void> releaseOriginal() => Future<void>.error(failure);
      final ImportDecryptAttempt<_EncryptedFixture> attempt =
          ImportDecryptAttempt<_EncryptedFixture>(
            path: 'fixture.file',
            source: Object(),
            decrypt: (_, _) async => _EncryptedFixture(),
            accessOriginal: (_) async {
              try {
                return 'fixture result';
              } finally {
                await releaseOriginal();
              }
            },
            isCurrent: () => true,
            validateSeed: (_) => true,
            isIncorrectPassword: (_) => false,
          );
      final ImportDecryptOutcome outcome = await attempt.start('fixture input');
      expect(outcome.status, ImportDecryptStatus.failed);
      expect(outcome.seed, isNull);
      expect(identical(attempt.failure, failure), isTrue);
    },
  );

  test(
    'the original password failure is classified without exposing its text',
    () async {
      final _WrongPassword failure = _WrongPassword();
      final ImportDecryptAttempt<_EncryptedFixture> attempt =
          ImportDecryptAttempt<_EncryptedFixture>(
            path: 'fixture.file',
            source: Object(),
            decrypt: (_, _) async => throw failure,
            accessOriginal: (_) async => throw StateError('Unexpected access'),
            isCurrent: () => true,
            validateSeed: (_) => true,
            isIncorrectPassword: (Object value) => value is _WrongPassword,
          );
      final ImportDecryptOutcome outcome = await attempt.start('fixture input');
      expect(outcome.status, ImportDecryptStatus.incorrectPassword);
      expect(outcome.seed, isNull);
      expect(identical(attempt.failure, failure), isTrue);
    },
  );

  test(
    'a released seed still requires membership and checksum admission',
    () async {
      final ImportDecryptAttempt<_EncryptedFixture> attempt =
          ImportDecryptAttempt<_EncryptedFixture>(
            path: 'fixture.file',
            source: Object(),
            decrypt: (_, _) async => _EncryptedFixture(),
            accessOriginal: (_) async => 'invalid fixture result',
            isCurrent: () => true,
            validateSeed: (_) => false,
            isIncorrectPassword: (_) => false,
          );
      final ImportDecryptOutcome outcome = await attempt.start('fixture input');
      expect(outcome.status, ImportDecryptStatus.failed);
      expect(outcome.seed, isNull);
    },
  );

  test(
    'synchronous reentry receives the reserved original completion',
    () async {
      late ImportDecryptAttempt<_EncryptedFixture> attempt;
      Future<ImportDecryptOutcome>? nested;
      int decryptions = 0;
      attempt = ImportDecryptAttempt<_EncryptedFixture>(
        path: 'fixture.file',
        source: Object(),
        decrypt: (_, _) {
          decryptions++;
          nested = attempt.start('replacement input');
          return Future<_EncryptedFixture>.value(_EncryptedFixture());
        },
        accessOriginal: (_) async => 'fixture result',
        isCurrent: () => true,
        validateSeed: (_) => true,
        isIncorrectPassword: (_) => false,
      );
      final Future<ImportDecryptOutcome> original = attempt.start(
        'fixture input',
      );
      expect(identical(original, nested), isTrue);
      expect((await original).status, ImportDecryptStatus.ready);
      expect(decryptions, 1);
    },
  );

  test('an already stale owner never starts a decrypt operation', () async {
    int decryptions = 0;
    final ImportDecryptAttempt<_EncryptedFixture> attempt =
        ImportDecryptAttempt<_EncryptedFixture>(
          path: 'fixture.file',
          source: Object(),
          decrypt: (_, _) async {
            decryptions++;
            return _EncryptedFixture();
          },
          accessOriginal: (_) async => 'fixture result',
          isCurrent: () => false,
          validateSeed: (_) => true,
          isIncorrectPassword: (_) => false,
        );
    expect(
      (await attempt.start('fixture input')).status,
      ImportDecryptStatus.stale,
    );
    expect(decryptions, 0);
    expect(attempt.decryption, isNull);
  });
}
