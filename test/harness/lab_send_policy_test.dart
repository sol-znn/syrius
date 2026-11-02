import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/fixtures/lab_send_policy.dart';
import '../../harness/app/fixtures/seed_policy.dart';

String _hash(int value) => value.toRadixString(16).padLeft(64, '0');

final class _Original implements SeedOriginal {
  @override
  Object identity = Object();
  @override
  bool settled = false;
  @override
  bool failed = false;
  @override
  bool releaseFailed = false;
  @override
  String? acceptedHash;
}

final class _Journal implements SeedJournal {
  final Set<String> attempts = <String>{};
  final Map<String, String> hashes = <String, String>{};
  final Map<String, String> confirmations = <String, String>{};
  @override
  void requireAvailable(String recipe) {
    if (attempts.contains(recipe) ||
        attempts.any((String id) => !confirmations.containsKey(id))) {
      throw const SeedRefused('earlier-seed-attempt-held');
    }
  }

  @override
  void claim(String recipe) {
    requireAvailable(recipe);
    attempts.add(recipe);
  }

  @override
  void accepted(String recipe, String hash) {
    if (hashes[recipe] != null && hashes[recipe] != hash) {
      throw const SeedRefused('original-hash-changed');
    }
    hashes[recipe] = hash;
  }

  @override
  void confirmed(String recipe, String hash) => confirmations[recipe] = hash;
}

final class _Source implements SeedSource {
  @override
  final SeedEnvironment environment = SeedEnvironment(
    profile: 'lab-send-fixture', isolated: true, unlocked: true,
    initialized: true, booted: true, ws: seedWsOrigin, http: seedHttpOrigin,
    nodeChain: 321, signingChain: 321, selectedIndex: 1,
    owner: 'owner', members: <String>['recipient', 'owner'],
  );
  @override
  bool isCurrent = true;
  bool advancing = true;
  bool positive = true;
  bool matches = true;
  bool funded = true;
  int reads = 0;
  int confirmations = 0;
  int effects = 0;
  String? returnedHash;
  String returnedOwner = 'owner';
  int returnedChain = 321;
  void Function()? onDelay;
  Future<SeedConfirmed?> Function(String hash)? onConfirmation;
  final List<SeedOriginal> publications = <SeedOriginal>[];

  final List<Duration> delays = <Duration>[];
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    onDelay?.call();
  }
  @override
  Future<SeedFrontier> wsFrontier() async {
    reads++;
    return SeedFrontier(chain: 321, height: advancing ? reads : 1,
      timestamp: advancing ? reads : 1, hash: _hash(advancing ? reads : 1));
  }

  @override
  Future<SeedFrontier> httpFrontier() => wsFrontier();
  @override
  Future<bool> sameMomentum(SeedFrontier value) async => true;
  @override
  Future<SeedFunding> funding() async =>
      SeedFunding(funded ? BigInt.from(100000000) : BigInt.zero, BigInt.zero);
  @override
  SeedFunding minimum(String recipe) => SeedFunding(BigInt.one, BigInt.zero);
  @override
  List<SeedOriginal> originals() => List<SeedOriginal>.of(publications);
  SeedConfirmed receipt(String hash) => SeedConfirmed(
    hash: returnedHash ?? hash, owner: returnedOwner, chain: returnedChain,
    positiveConfirmation: positive, matchesRecipe: matches,
  );
  @override
  Future<SeedConfirmed?> confirmed(String recipe, String hash) async {
    expect(recipe, labSendRecipeId);
    confirmations++;
    if (onConfirmation != null) return onConfirmation!(hash);
    return receipt(hash);
  }

  @override
  Future<bool> effect(String recipe, String hash) async {
    effects++;
    throw StateError('P09 does not substitute an F06 seed effect');
  }
}

final class _Case {
  _Case() {
    guard = LabSendGuard(source: source, journal: journal, delay: source.delay,
      readTimeout: const Duration(milliseconds: 10));
  }
  final _Source source = _Source();
  final _Journal journal = _Journal();
  final _Original original = _Original();
  late final LabSendGuard guard;
  int taps = 0;
  int readyChecks = 0;
  void ready() => readyChecks++;
  Future<void> complete(void Function() admission) async {
    expect(journal.attempts, contains(labSendRecipeId));
    admission();
    admission();
    taps++;
    original
      ..acceptedHash = _hash(9)
      ..settled = true;
  }

  Future<String> run({Future<void> Function(void Function())? tap}) =>
      guard.publish(
    original: original, requireOriginalReady: ready, tapOnce: tap ?? complete,
  );
}

void main() {
  test('exhausted original reads expose only immutable finite counts',
      () async {
    for (final int mode in <int>[0, 18, 7, -9]) {
      final _Case value = _Case();
      value.source.positive = false;
      expect(value.guard.pendingConfirmationObservation, isNull);
      value.source.onConfirmation = (String hash) async {
        expect(value.guard.pendingConfirmationObservation, isNull);
        final int poll = value.source.confirmations;
        final bool absent = mode < 0 ? poll.isEven : poll <= mode;
        return absent ? null : value.source.receipt(hash);
      };
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      final int absent = mode < 0 ? 9 : mode;
      final Map<String, Object> expected = <String, Object>{
        'polls': 18, 'absent': absent, 'unconfirmed': 18 - absent,
        'last': mode < 0 || mode == 18 ? 'absent' : 'unconfirmed',
      };
      final Map<String, Object> observed =
          value.guard.pendingConfirmationObservation!;
      expect(observed, expected);
      expect(() => observed['polls'] = 0, throwsUnsupportedError);
      expect(value.source.confirmations, 18);
      expect(value.source.delays.where((Duration value) =>
          value == const Duration(seconds: 2)), hasLength(18));
      expect(value.guard.original, same(value.original));
      expect(value.guard.acceptedHash, _hash(9));
      expect(value.journal.confirmations, isEmpty);
      final int reads = value.source.reads;
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      expect(value.source.reads, reads);
      expect(value.source.confirmations, 18);
      expect(value.source.effects, 0);
      expect(value.taps, 1);
      expect(value.guard.pendingConfirmationObservation, expected);
    }
  });

  test('a positive last original read does not export pending counts',
      () async {
    final _Case value = _Case();
    value.source.onConfirmation = (String hash) async {
      expect(value.guard.pendingConfirmationObservation, isNull);
      return value.source.confirmations == 18
          ? value.source.receipt(hash) : null;
    };
    expect(await value.run(), _hash(9));
    expect(value.source.confirmations, 18);
    expect(value.source.delays.where((Duration value) =>
        value == const Duration(seconds: 2)), hasLength(17));
    expect(value.guard.pendingConfirmationObservation, isNull);
    expect(value.journal.confirmations[labSendRecipeId], _hash(9));
    expect(value.taps, 1);
  });

  test('a refused last read cannot be counted as completed exhaustion',
      () async {
    for (final String failure in <String>['owner', 'receipt', 'original']) {
      final _Case value = _Case();
      value.source.onConfirmation = (String hash) async {
        if (value.source.confirmations < 18) return null;
        if (failure == 'owner') value.source.isCurrent = false;
        if (failure == 'receipt') value.source.returnedHash = _hash(10);
        if (failure == 'original') value.original.failed = true;
        return value.source.receipt(hash);
      };
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      expect(value.source.confirmations, 18);
      expect(value.guard.pendingConfirmationObservation, isNull);
      expect(value.journal.confirmations, isEmpty);
      expect(value.guard.acceptedHash, _hash(9));
      expect(value.taps, 1);
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      expect(value.source.confirmations, 18);
    }
  });

  test('a timed out last read and its late answer add no completed sample',
      () async {
    final _Case value = _Case();
    final Completer<SeedConfirmed?> answer = Completer<SeedConfirmed?>();
    value.source.onConfirmation = (String hash) async {
      if (value.source.confirmations < 18) return null;
      return answer.future;
    };
    await expectLater(value.run(), throwsA(isA<TimeoutException>()));
    expect(value.source.confirmations, 18);
    expect(value.guard.pendingConfirmationObservation, isNull);
    answer.complete(value.source.receipt(_hash(9)));
    await Future<void>.delayed(Duration.zero);
    expect(value.guard.pendingConfirmationObservation, isNull);
    expect(value.journal.confirmations, isEmpty);
    expect(value.guard.acceptedHash, _hash(9));
    await expectLater(value.run(), throwsA(isA<SeedRefused>()));
    expect(value.taps, 1);
    expect(value.source.confirmations, 18);
  });

  test('the fixed P09 purpose cannot use generic F06 publication', () async {
    final _Case value = _Case();
    final SeedGuard ordinary = SeedGuard(
      source: value.source, journal: value.journal,
      delay: value.source.delay);
    final SeedGuard p09 = SeedGuard.forLabSend(source: value.source,
      journal: value.journal, delay: value.source.delay);
    await expectLater(
      ordinary.admit(labSendRecipeId), throwsA(isA<SeedRefused>()),
    );
    await expectLater(p09.admit('stake'), throwsA(isA<SeedRefused>()));
    await expectLater(p09.publish(labSendRecipeId, () async { value.taps++; }),
      throwsA(isA<SeedRefused>()));
    expect(value.source.reads, 0);
    expect(value.taps, 0);
    expect(seedRecipeIds, hasLength(6));
    expect(seedRecipeIds, isNot(contains(labSendRecipeId)));
  });

  test(
    'one original confirmation has one claim, input and exact confirmed hash',
    () async {
      final _Case value = _Case();
      expect(await value.run(), _hash(9));
      expect(value.taps, 1);
      expect(value.readyChecks, 4);
      expect(value.guard.original, same(value.original));
      expect(value.journal.hashes[labSendRecipeId], _hash(9));
      expect(value.journal.confirmations[labSendRecipeId], _hash(9));
      expect(value.source.effects, 0);
    },
  );

  test(
    'unrelated receives after admission cannot replace the target request',
    () async {
      final _Case value = _Case();
      expect(await value.run(tap: (void Function() admission) async {
        await value.complete(admission);
        value.source.publications.add(_Original()..failed = true);
      }), _hash(9));
      expect(value.taps, 1);
      expect(value.guard.original, same(value.original));
    },
  );

  test(
    'an earlier unresolved publication refuses before the input claim',
    () async {
      final _Case value = _Case();
      value.source.publications.add(_Original());
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      expect(value.taps, 0);
      expect(value.journal.attempts, isEmpty);
    },
  );

  test(
    'a request changed during frontier admission never receives input',
    () async {
      final _Case value = _Case();
      value.source.onDelay = () => value.original.identity = Object();
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      expect(value.taps, 0);
      expect(value.journal.attempts, isEmpty);
    },
  );

  test(
    'unfunded or nonadvancing endpoints refuse before UI publication',
    () async {
      for (final bool funded in <bool>[false, true]) {
        final _Case value = _Case();
        value.source
          ..funded = funded
          ..advancing = !funded;
        await expectLater(value.run(), throwsA(isA<SeedRefused>()));
        expect(value.taps, 0);
        expect(value.journal.attempts, isEmpty);
      }
    },
  );

  test(
    'a pointer failure retains the original hash and cannot be retried',
    () async {
      final _Case value = _Case();
      final StateError originalError = StateError('original-pointer-failure');
      await expectLater(value.run(tap: (void Function() admission) async {
        await value.complete(admission);
        throw originalError;
      }), throwsA(same(originalError)));
      expect(value.guard.failures.single, same(originalError));
      expect(value.guard.acceptedHash, _hash(9));
      expect(value.journal.hashes[labSendRecipeId], _hash(9));
      await expectLater(value.run(), throwsA(isA<SeedRefused>()));
      expect(value.taps, 1);
    },
  );

  test(
    'failure or release uncertainty preserves accepted identity '
    'without confirmation',
    () async {
      for (final bool release in <bool>[false, true]) {
        final _Case value = _Case();
        await expectLater(value.run(tap: (void Function() admission) async {
          await value.complete(admission);
          value.original
            ..failed = !release
            ..releaseFailed = release;
        }), throwsA(isA<SeedRefused>()));
        expect(value.guard.acceptedHash, _hash(9));
        expect(value.journal.confirmations, isEmpty);
        expect(value.taps, 1);
      }
    },
  );

  test(
    'owner loss retains a late original answer and cannot be revived',
    () async {
      final _Case value = _Case();
      await expectLater(value.run(tap: (void Function() admission) async {
        await value.complete(admission);
        value.source.isCurrent = false;
      }), throwsA(isA<SeedRefused>()));
      expect(value.guard.acceptedHash, _hash(9));
      value.source.isCurrent = true;
      expect(value.guard.requireCurrent, throwsA(isA<SeedRefused>()));
      expect(value.journal.confirmations, isEmpty);
    },
  );

  test(
    'a changed original hash cannot overwrite the first accepted answer',
    () async {
      for (final String? changed in <String?>[null, _hash(10)]) {
        final _Case value = _Case();
        value.source.onConfirmation = (String hash) async {
          value.original.acceptedHash = changed;
          return value.source.receipt(hash);
        };
        await expectLater(value.run(), throwsA(isA<SeedRefused>()));
        expect(value.guard.acceptedHash, _hash(9));
        expect(value.journal.hashes[labSendRecipeId], _hash(9));
        expect(value.journal.confirmations, isEmpty);
      }
    },
  );

  test(
    'hash, owner, chain or exact transfer mismatch cannot confirm',
    () async {
      for (int field = 0; field < 4; field++) {
        final _Case value = _Case();
        if (field == 0) value.source.returnedHash = _hash(10);
        if (field == 1) value.source.returnedOwner = 'replacement';
        if (field == 2) value.source.returnedChain = 1;
        if (field == 3) value.source.matches = false;
        await expectLater(value.run(), throwsA(isA<SeedRefused>()));
        expect(value.journal.confirmations, isEmpty);
        expect(value.taps, 1);
      }
    },
  );

  test('an unconfirmed answer stays held without another input', () async {
    final _Case value = _Case();
    value.source.positive = false;
    await expectLater(value.run(), throwsA(isA<SeedRefused>()));
    expect(value.source.confirmations, 18);
    expect(value.journal.confirmations, isEmpty);
    await expectLater(value.run(), throwsA(isA<SeedRefused>()));
    expect(value.taps, 1);
  });

  test('a late read cannot revive a timed-out original attempt', () async {
    final _Case value = _Case();
    final Completer<SeedConfirmed?> answer = Completer<SeedConfirmed?>();
    value.source.onConfirmation = (_) => answer.future;
    await expectLater(value.run(), throwsA(isA<TimeoutException>()));
    answer.complete(value.source.receipt(_hash(9)));
    await Future<void>.delayed(Duration.zero);
    expect(value.guard.acceptedHash, _hash(9));
    expect(value.journal.confirmations, isEmpty);
    await expectLater(value.run(), throwsA(isA<SeedRefused>()));
    expect(value.taps, 1);
  });
}
