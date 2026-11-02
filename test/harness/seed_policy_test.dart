import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/fixtures/fixture_cleanup.dart';
import '../../harness/app/fixtures/seed_commands.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../../harness/app/fixtures/seed_project_presentation.dart';
import '../../harness/app/fixtures/seed_token_presentation.dart';

String _hash(int id) => id.toRadixString(16).padLeft(64, '0');
SeedEnvironment _environment({
  String profile = 'lab-fixture',
  bool isolated = true,
  bool unlocked = true,
  String ws = seedWsOrigin,
  String http = seedHttpOrigin,
  int nodeChain = 321,
  int signingChain = 321,
  int index = 1,
  List<String> members = const <String>['producer', 'owner', 'recipient'],
}) => SeedEnvironment(
  profile: profile,
  isolated: isolated,
  unlocked: unlocked,
  initialized: true,
  booted: true,
  ws: ws,
  http: http,
  nodeChain: nodeChain,
  signingChain: signingChain,
  selectedIndex: index,
  owner: 'owner',
  members: members,
);

class _Original implements SeedOriginal {
  @override
  final Object identity = Object();
  @override
  bool settled = true;
  @override
  bool failed = false;
  @override
  bool releaseFailed = false;
  @override
  String? acceptedHash = _hash(9);
}

class _Journal implements SeedJournal {
  final Set<String> attempts = <String>{};
  final Map<String, String> acceptedHashes = <String, String>{};
  final Map<String, String> confirmedHashes = <String, String>{};
  @override
  void requireAvailable(String recipe) {
    if (attempts.contains(recipe) ||
        attempts.any((String id) => !confirmedHashes.containsKey(id))) {
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
    final String? original = acceptedHashes[recipe];
    if (original != null && original != hash) {
      throw const SeedRefused('original-hash-changed');
    }
    acceptedHashes[recipe] = hash;
  }

  @override
  void confirmed(String recipe, String hash) => confirmedHashes[recipe] = hash;
}

class _Source implements SeedSource {
  _Source({SeedEnvironment? environment})
    : environment = environment ?? _environment();
  @override
  final SeedEnvironment environment;
  @override
  bool isCurrent = true;
  bool advancingWs = true;
  bool advancingHttp = true;
  bool agreement = true;
  bool effectPresent = true;
  bool positiveConfirmation = true;
  Future<SeedConfirmed?> Function()? onConfirmation;
  Future<bool> Function()? onEffect;
  bool targetMatches = true;
  int wsReads = 0;
  int httpReads = 0;
  int confirmationReads = 0;
  int effectReads = 0;
  int delays = 0;
  String? receiptHash;
  String receiptOwner = 'owner';
  int receiptChain = 321;
  SeedFunding balance = SeedFunding(BigInt.from(100), BigInt.from(100));
  final List<SeedOriginal> operations = <SeedOriginal>[];
  Future<void> Function()? onWs;
  Future<void> delay(Duration duration) async {
    delays++;
  }

  @override
  Future<SeedFrontier> wsFrontier() async {
    wsReads++;
    await onWs?.call();
    return SeedFrontier(
      chain: 321,
      height: advancingWs ? wsReads + 10 : 10,
      timestamp: advancingWs ? wsReads + 100 : 100,
      hash: _hash(advancingWs ? wsReads + 10 : 10),
    );
  }

  @override
  Future<SeedFrontier> httpFrontier() async {
    httpReads++;
    return SeedFrontier(
      chain: 321,
      height: advancingHttp ? httpReads + 10 : 10,
      timestamp: advancingHttp ? httpReads + 100 : 100,
      hash: _hash(advancingHttp ? httpReads + 10 : 10),
    );
  }

  @override
  Future<bool> sameMomentum(SeedFrontier http) async => agreement;
  @override
  Future<SeedFunding> funding() async => balance;
  @override
  SeedFunding minimum(String recipe) => SeedFunding(BigInt.one, BigInt.one);
  @override
  List<SeedOriginal> originals() => List<SeedOriginal>.unmodifiable(operations);
  @override
  Future<SeedConfirmed?> confirmed(String recipe, String hash) async {
    confirmationReads++;
    if (onConfirmation != null) return onConfirmation!();
    return SeedConfirmed(
      hash: receiptHash ?? hash,
      owner: receiptOwner,
      chain: receiptChain,
      positiveConfirmation: positiveConfirmation,
      matchesRecipe: targetMatches,
    );
  }

  @override
  Future<bool> effect(String recipe, String hash) async {
    effectReads++;
    if (onEffect != null) return onEffect!();
    return effectPresent;
  }
}

void main() {
  late _Source source;
  late _Journal journal;
  late SeedGuard guard;
  setUp(() {
    source = _Source();
    journal = _Journal();
    guard = SeedGuard(source: source, journal: journal, delay: source.delay);
  });

  test('only an explicit isolated unlocked profile can admit', () async {
    for (final SeedEnvironment environment in <SeedEnvironment>[
      _environment(profile: 'default'),
      _environment(isolated: false),
      _environment(unlocked: false),
    ]) {
      final _Source other = _Source(environment: environment);
      final SeedGuard scoped = SeedGuard(
        source: other,
        journal: _Journal(),
        delay: other.delay,
      );
      await expectLater(scoped.admit('stake'), throwsA(isA<SeedRefused>()));
      expect(other.wsReads, 0);
    }
  });

  test(
    'exact loopback origins and both chain identifiers are required',
    () async {
      for (final SeedEnvironment environment in <SeedEnvironment>[
        _environment(ws: 'ws://localhost:45998'),
        _environment(ws: '$seedWsOrigin/'),
        _environment(http: 'http://127.0.0.1:35997'),
        _environment(http: 'https://example.test'),
        _environment(nodeChain: 1),
        _environment(signingChain: 69),
      ]) {
        final _Source other = _Source(environment: environment);
        await expectLater(
          SeedGuard(
            source: other,
            journal: _Journal(),
            delay: other.delay,
          ).admit('stake'),
          throwsA(isA<SeedRefused>()),
        );
        expect(other.wsReads, 0);
      }
    },
  );

  test(
    'selected index and immutable exact membership are independent '
    'requirements',
    () {
      final List<String> members = <String>['producer', 'owner', 'recipient'];
      final SeedEnvironment captured = _environment(members: members);
      members[1] = 'replacement';
      expect(captured.members[1], 'owner');
      expect(captured.requireLab, returnsNormally);
      expect(_environment(index: 0).requireLab, throwsA(isA<SeedRefused>()));
      expect(
        _environment(members: <String>['owner', 'owner']).requireLab,
        throwsA(isA<SeedRefused>()),
      );
    },
  );

  test(
    'both frontiers must positively advance within six bounded polls',
    () async {
      for (final (bool, bool) endpoints in <(bool, bool)>[
        (true, false), (false, true), (false, false),
      ]) {
        source
          ..advancingWs = endpoints.$1
          ..advancingHttp = endpoints.$2
          ..wsReads = 0
          ..httpReads = 0
          ..delays = 0;
        SeedRefused? refusal;
        try {
          await guard.admit('stake');
        } on SeedRefused catch (error) {
          refusal = error;
        }
        expect(refusal?.code, 'advancing-momentum-required');
        final Map<String, Object> facts = refusal!.frontier!.public;
        expect(facts, <String, Object>{
          'polls': 6,
          'ws_first_height': endpoints.$1 ? 11 : 10,
          'ws_last_height': endpoints.$1 ? 17 : 10,
          'ws_first_timestamp': endpoints.$1 ? 101 : 100,
          'ws_last_timestamp': endpoints.$1 ? 107 : 100,
          'ws_hash_changed': endpoints.$1,
          'http_first_height': endpoints.$2 ? 11 : 10,
          'http_last_height': endpoints.$2 ? 17 : 10,
          'http_first_timestamp': endpoints.$2 ? 101 : 100,
          'http_last_timestamp': endpoints.$2 ? 107 : 100,
          'http_hash_changed': endpoints.$2,
        });
        expect(() => facts['polls'] = 0, throwsUnsupportedError);
        expect(source.wsReads, 7);
        expect(source.httpReads, 7);
        expect(source.delays, 6);
        expect(source.confirmationReads, 0);
        expect(source.effectReads, 0);
        expect(journal.attempts, isEmpty);
      }
    },
  );

  test(
    'same chain labels cannot replace exact cross-endpoint momentum agreement',
    () async {
      source.agreement = false;
      await expectLater(guard.admit('stake'), throwsA(isA<SeedRefused>()));
      expect(source.wsReads, 1);
      expect(journal.attempts, isEmpty);
    },
  );

  test('funding zero refuses before the UI publication control', () async {
    source.balance = SeedFunding(BigInt.zero, BigInt.from(100));
    int taps = 0;
    await expectLater(
      guard.publish('stake', () async {
        taps++;
      }),
      throwsA(isA<SeedRefused>()),
    );
    expect(taps, 0);
    expect(journal.attempts, isEmpty);
  });

  test(
    'revocation during a frontier read never recaptures a replacement source',
    () async {
      source.onWs = () async {
        source.isCurrent = false;
      };
      await expectLater(guard.admit('stake'), throwsA(isA<SeedRefused>()));
      source.isCurrent = true;
      expect(guard.requireCurrent, throwsA(isA<SeedRefused>()));
      expect(journal.attempts, isEmpty);
    },
  );

  test(
    'an earlier pending, failed or unreleased original prevents another tap',
    () async {
      for (int kind = 0; kind < 3; kind++) {
        final _Original operation = _Original();
        if (kind == 0) operation.settled = false;
        if (kind == 1) operation.failed = true;
        if (kind == 2) operation.releaseFailed = true;
        source.operations
          ..clear()
          ..add(operation);
        await expectLater(guard.admit('stake'), throwsA(isA<SeedRefused>()));
      }
      expect(journal.attempts, isEmpty);
    },
  );

  test(
    'one tap retains the original accepted hash and requires exact '
    'effect proof',
    () async {
      int taps = 0;
      final String hash = await guard.publish('stake', () async {
        taps++;
        source.operations.add(_Original());
      });
      expect(hash, _hash(9));
      expect(taps, 1);
      expect(journal.confirmedHashes['stake'], hash);
      expect(source.confirmationReads, 1);
      expect(source.effectReads, 1);
    },
  );

  test(
    'multiple new originals are ambiguous and are never selected '
    'by resemblance',
    () async {
      await expectLater(
        guard.publish('stake', () async {
          source.operations.addAll(<SeedOriginal>[_Original(), _Original()]);
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(source.confirmationReads, 0);
      expect(journal.attempts, contains('stake'));
      expect(journal.confirmedHashes, isEmpty);
    },
  );

  test(
    'a tap exception holds its original attempt without a second tap',
    () async {
      int taps = 0;
      Future<void> tap() async {
        taps++;
        throw StateError('synthetic pointer failure');
      }

      await expectLater(
        guard.publish('stake', tap),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        guard.publish('stake', tap),
        throwsA(isA<SeedRefused>()),
      );
      expect(taps, 1);
      expect(journal.attempts, contains('stake'));
    },
  );
  test('preparation cannot continue after a claimed pointer failure', () async {
    expect(guard.requirePreparation, returnsNormally);
    await expectLater(
      guard.publish('stake', () async {
        expect(journal.attempts, <String>{'stake'});
        expect(
          guard.requirePreparation,
          throwsA(
            isA<SeedRefused>().having(
              (SeedRefused error) => error.code,
              'code',
              'original-attempt-held',
            ),
          ),
        );
        throw StateError('synthetic pointer failure');
      }),
      throwsA(isA<StateError>()),
    );
    expect(
      guard.requirePreparation,
      throwsA(
        isA<SeedRefused>().having(
          (SeedRefused error) => error.code,
          'code',
          'original-attempt-held',
        ),
      ),
    );
    expect(journal.attempts, <String>{'stake'});
    expect(journal.acceptedHashes, isEmpty);
    expect(journal.confirmedHashes, isEmpty);
    expect(source.operations, isEmpty);
    expect(source.confirmationReads, 0);
    expect(source.effectReads, 0);
  });
  test('preparation latches original context revocation before any input', () {
    source.isCurrent = false;
    expect(
      guard.requirePreparation,
      throwsA(
        isA<SeedRefused>().having(
          (SeedRefused error) => error.code,
          'code',
          'original-context-changed',
        ),
      ),
    );
    source.isCurrent = true;
    expect(guard.requirePreparation, throwsA(isA<SeedRefused>()));
    expect(journal.attempts, isEmpty);
    expect(source.wsReads, 0);
    expect(source.httpReads, 0);
  });

  test(
    'an accepted hash stays retained when the original release fails',
    () async {
      final _Original operation = _Original()..releaseFailed = true;
      await expectLater(
        guard.publish('stake', () async {
          source.operations.add(operation);
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(guard.acceptedHash, _hash(9));
      expect(journal.acceptedHashes['stake'], _hash(9));
      expect(journal.confirmedHashes, isEmpty);
    },
  );

  test(
    'a toast or elapsed polls cannot establish chain confirmation',
    () async {
      source.positiveConfirmation = false;
      await expectLater(
        guard.publish('stake', () async {
          source.operations.add(_Original());
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(source.confirmationReads, 18);
      expect(source.effectReads, 0);
      expect(journal.confirmedHashes, isEmpty);
    },
  );

  test(
    'confirmed account send alone cannot establish a contract effect',
    () async {
      source.effectPresent = false;
      await expectLater(
        guard.publish('stake', () async {
          source.operations.add(_Original());
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(source.effectReads, 18);
      expect(journal.confirmedHashes, isEmpty);
    },
  );

  test(
    'changed hash, owner, chain or recipe receipt refuses the exact original',
    () async {
      for (int mismatch = 0; mismatch < 4; mismatch++) {
        final _Source other = _Source();
        if (mismatch == 0) other.receiptHash = _hash(10);
        if (mismatch == 1) other.receiptOwner = 'replacement';
        if (mismatch == 2) other.receiptChain = 1;
        if (mismatch == 3) other.targetMatches = false;
        final _Journal records = _Journal();
        final SeedGuard scoped = SeedGuard(
          source: other,
          journal: records,
          delay: other.delay,
        );
        await expectLater(
          scoped.publish('stake', () async {
            other.operations.add(_Original());
          }),
          throwsA(isA<SeedRefused>()),
        );
        expect(records.confirmedHashes, isEmpty);
      }
    },
  );

  test(
    'a context change after acceptance keeps the hash without stale '
    'confirmation',
    () async {
      await expectLater(
        guard.publish('stake', () async {
          source.operations.add(_Original());
          source.isCurrent = false;
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(guard.acceptedHash, _hash(9));
      expect(source.confirmationReads, 0);
      expect(journal.confirmedHashes, isEmpty);
    },
  );

  test(
    'an unsettled original remains held after a finite outcome window',
    () async {
      final _Original operation = _Original()
        ..settled = false
        ..acceptedHash = null;
      int taps = 0;
      await expectLater(
        guard.publish('stake', () async {
          taps++;
          source.operations.add(operation);
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(source.delays, 61);
      await expectLater(
        SeedGuard(
          source: source,
          journal: journal,
          delay: source.delay,
        ).publish('fuse', () async {
          taps++;
        }),
        throwsA(isA<SeedRefused>()),
      );
      expect(taps, 1);
    },
  );

  test('eighteen absent seed reads retain one held original attempt', () async {
    source.onConfirmation = () async => null;
    int taps = 0;
    Future<void> tap() async {
      taps++;
      source.operations.add(_Original());
    }
    SeedRefused? refusal;
    try {
      await guard.publish('fuse', tap);
    } on SeedRefused catch (error) {
      refusal = error;
    }
    expect(refusal?.code, 'exact-confirmation-or-effect-pending');
    expect(refusal?.confirmation?.public, <String, Object>{
      'polls': 18, 'absent': 18, 'unconfirmed': 0,
      'effect_pending': 0, 'last': 'absent',
    });
    expect(source.confirmationReads, 18);
    expect(source.effectReads, 0);
    expect(source.delays, 19);
    expect(taps, 1);
    expect(journal.acceptedHashes, <String, String>{'fuse': _hash(9)});
    expect(journal.confirmedHashes, isEmpty);
    await expectLater(guard.publish('fuse', tap),
        throwsA(isA<SeedRefused>()));
    expect(taps, 1);
    expect(source.confirmationReads, 18);
  });

  test('completed seed rounds distinguish absence confirmation and effect',
      () async {
    source
      ..effectPresent = false
      ..onConfirmation = () async {
        if (source.confirmationReads <= 6) return null;
        return SeedConfirmed(
          hash: _hash(9), owner: 'owner', chain: 321, matchesRecipe: true,
          positiveConfirmation: source.confirmationReads > 12,
        );
      };
    SeedRefused? refusal;
    try {
      await guard.publish('fuse', () async {
        source.operations.add(_Original());
      });
    } on SeedRefused catch (error) {
      refusal = error;
    }
    final Map<String, Object> observed = refusal!.confirmation!.public;
    expect(observed, <String, Object>{
      'polls': 18, 'absent': 6, 'unconfirmed': 6,
      'effect_pending': 6, 'last': 'effect_pending',
    });
    expect(() => observed['polls'] = 0, throwsUnsupportedError);
    expect(source.confirmationReads, 18);
    expect(source.effectReads, 6);
    expect(source.delays, 19);
    expect(journal.confirmedHashes, isEmpty);
  });

  test('a positive last seed round keeps its exact original success', () async {
    source.onConfirmation = () async => source.confirmationReads == 18
        ? SeedConfirmed(hash: _hash(9), owner: 'owner', chain: 321,
            positiveConfirmation: true, matchesRecipe: true)
        : null;
    expect(await guard.publish('fuse', () async {
      source.operations.add(_Original());
    }), _hash(9));
    expect(source.confirmationReads, 18);
    expect(source.effectReads, 1);
    expect(source.delays, 18);
    expect(journal.confirmedHashes, <String, String>{'fuse': _hash(9)});
  });

  test('an incomplete last effect never produces exhausted seed counts',
      () async {
    final Completer<bool> late = Completer<bool>();
    source.onEffect = () => source.effectReads == 18
        ? late.future : Future<bool>.value(false);
    final SeedGuard bounded = SeedGuard(source: source, journal: journal,
      delay: source.delay, readTimeout: const Duration(milliseconds: 1));
    await expectLater(bounded.publish('fuse', () async {
      source.operations.add(_Original());
    }), throwsA(isA<TimeoutException>()));
    expect(source.confirmationReads, 18);
    expect(source.effectReads, 18);
    expect(source.delays, 18);
    expect(journal.confirmedHashes, isEmpty);
    late.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(journal.confirmedHashes, isEmpty);
    expect(source.effectReads, 18);
    await expectLater(bounded.publish('fuse', () async {
      fail('An incomplete original must not be retried');
    }), throwsA(isA<SeedRefused>()));
    expect(source.effectReads, 18);
  });

  test('seed count projections retain bounded immutable completed rounds', () {
    for (final String last in <String>[
      'absent', 'unconfirmed', 'effect_pending',
    ]) {
      final Map<String, Object> offered = <String, Object>{
        'polls': 18, 'absent': 6, 'unconfirmed': 6,
        'effect_pending': 6, 'last': last,
      };
      final Map<String, Object> observed =
          seedConfirmationProjection(offered)!;
      expect(observed, offered);
      offered['absent'] = 0;
      expect(observed['absent'], 6);
      expect(() => observed['polls'] = 0, throwsUnsupportedError);
    }
  });

  test('seed count projections refuse coerced private and impossible data', () {
    const Map<String, Object> valid = <String, Object>{
      'polls': 18, 'absent': 6, 'unconfirmed': 6,
      'effect_pending': 6, 'last': 'effect_pending',
    };
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'polls': true}, <String, Object?>{'polls': 17},
      <String, Object?>{'absent': -1}, <String, Object?>{'absent': 19},
      <String, Object?>{'unconfirmed': 6.0},
      <String, Object?>{'effect_pending': null},
      <String, Object?>{'effect_pending': 5},
      <String, Object?>{'last': 'synthetic-private-value'},
      <String, Object?>{'hash': 'synthetic-private-value'},
    ]) {
      expect(seedConfirmationProjection(<String, Object?>{
        ...valid, ...change,
      }), isNull);
    }
    for (final String missing in valid.keys) {
      expect(seedConfirmationProjection(<String, Object>{
        for (final String key in valid.keys)
          if (key != missing) key: valid[key]!,
      }), isNull);
    }
    for (final Object? value in <Object?>[null, true, <Object>[], 'private']) {
      expect(seedConfirmationProjection(value), isNull);
    }
  });

  test('seed projections require a possible last result without authority', () {
    expect(seedConfirmationProjection(<String, Object>{
      'polls': 18, 'absent': 18, 'unconfirmed': 0,
      'effect_pending': 0, 'last': 'effect_pending',
    }), isNull);
    final Map<String, Object> observed = seedConfirmationProjection(
      <String, Object>{
        'polls': 18, 'absent': 0, 'unconfirmed': 0,
        'effect_pending': 18, 'last': 'effect_pending',
      },
    )!;
    for (final String key in <String>[
      'confirmed', 'complete', 'hash', 'retry', 'success', 'address',
    ]) {
      expect(observed.containsKey(key), isFalse);
    }
    expect(seedConfirmationProjection(null), isNull);
  });

  test('confirmed Project finish closes once and retains fixture admission',
      () async {
    expect(await guard.publish('project', () async {
      source.operations.add(_Original());
    }), _hash(9));
    expect(journal.confirmedHashes, <String, String>{'project': _hash(9)});
    final List<int> reads = <int>[
      source.wsReads, source.httpReads,
      source.confirmationReads, source.effectReads,
    ];
    final FixtureCleanup fixture = FixtureCleanup(name: 'sentinel');
    final Completer<Object?> route = Completer<Object?>();
    bool visible = true;
    int exits = 0;
    final SeedProjectPresentation presentation = SeedProjectPresentation(
      originalCurrent: () => visible,
      submittedCurrent: (String hash) => visible && hash == _hash(9),
      originalRouteCompleted: route.future,
      tapOriginalExit: (void Function() admission) async {
        admission();
        exits++;
        admission();
        visible = false;
        route.complete(null);
      },
    );
    SeedCommands commands({required bool confirmed}) =>
        SeedCommands.withFixtureAdmission(
      fixture: fixture, guard: guard, recipe: 'project',
      confirmed: confirmed, projectPresentation: presentation,
    );
    Future<Map<String, Object?>> finish(SeedCommands original) => original.run(
      <String, dynamic>{'action': 'finish'}, booted: false,
      ui: (_) async => throw StateError('Unexpected generic UI query'),
      tap: (_, _) async => throw StateError('Unexpected generic pointer'),
    );
    await expectLater(finish(commands(confirmed: false)),
      throwsA(isA<SeedRefused>()
        .having((SeedRefused error) => error.code,
            'code', 'exact-confirmation-required')));
    final SeedCommands original = commands(confirmed: true);
    await expectLater(finish(original), throwsA(isA<SeedRefused>()
        .having((SeedRefused error) => error.code,
            'code', 'close-current-fixture-first')));
    expect(exits, 0);
    expect(presentation.closed, isFalse);
    final Object fixtureOwner = Object();
    fixture
      ..open(routeCompleted: Future<void>.value(),
          push: Future<void>.value)
      ..attach(fixtureOwner)
      ..dispose(owner: fixtureOwner, dispose: <void Function()>[],
          close: <Future<void> Function()>[], stateDisposed: () {});
    await Future<void>.delayed(Duration.zero);
    expect(fixture.heldName, isNull);
    final Map<String, Object?> receipt = await finish(original);
    expect(receipt, <String, Object?>{
      'confirmed': true, 'recipe': 'project', 'hash': _hash(9),
    });
    expect(presentation.closed, isTrue);
    expect(exits, 1);
    expect(() => fixture.attach(Object()), throwsStateError);
    expect(fixture.heldName, 'sentinel');
    expect(await finish(original), receipt);
    expect(exits, 1);
    expect(source.operations, hasLength(1));
    expect(<int>[source.wsReads, source.httpReads,
      source.confirmationReads, source.effectReads], reads);
    expect(journal.acceptedHashes, <String, String>{'project': _hash(9)});
    expect(journal.confirmedHashes, <String, String>{'project': _hash(9)});
  });

  test('Project capture precedes only its original exclusive publication',
      () async {
    for (final String phase in <String>['missing', 'replaced', 'captured']) {
      final _Source original = _Source();
      final _Journal ledger = _Journal();
      final SeedGuard scoped = SeedGuard(
        source: original, journal: ledger, delay: original.delay,
      );
      final FixtureCleanup fixture = FixtureCleanup(name: 'sentinel');
      final Object fixtureOwner = Object();
      fixture
        ..open(routeCompleted: Future<void>.value(),
            push: Future<void>.value)
        ..attach(fixtureOwner)
        ..dispose(owner: fixtureOwner, dispose: <void Function()>[],
            close: <Future<void> Function()>[], stateDisposed: () {});
      await Future<void>.delayed(Duration.zero);
      expect(fixture.heldName, isNull);
      bool live = phase != 'replaced';
      int captures = 0;
      int publications = 0;
      int exits = 0;
      final Completer<Object?> route = Completer<Object?>();
      final SeedProjectPresentation presentation = SeedProjectPresentation(
        originalCurrent: () => live,
        submittedCurrent: (String hash) => live && hash == _hash(9),
        originalRouteCompleted: route.future,
        tapOriginalExit: (void Function() admission) async {
          admission();
          exits++;
          admission();
          route.complete(null);
        },
      );
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture, guard: scoped, recipe: 'project',
      );
      Future<Map<String, Object?>> publish() => commands.run(
        <String, dynamic>{'action': 'publish'}, booted: false,
        ui: (Map<String, dynamic> request) async {
          expect(request, <String, dynamic>{
            'cmd': 'assert', 'text': 'Submit',
            'kind': 'button', 'exact': true,
          });
          return <String, Object?>{
            'target': <String, Object?>{'ref': 7},
          };
        },
        tap: (Map<String, dynamic> request,
            void Function() admission) async {
          admission();
          admission();
          expect(request, <String, dynamic>{'cmd': 'tap', 'ref': 7});
          publications++;
          original.operations.add(_Original());
          return <String, Object?>{};
        },
        captureProjectPresentation: phase == 'missing' ? null : (int ref) {
          captures++;
          expect(ref, 7);
          expect(original.operations, isEmpty);
          expect(original.wsReads, 0);
          expect(original.httpReads, 0);
          expect(ledger.attempts, isEmpty);
          return presentation;
        },
      );
      if (phase != 'captured') {
        await expectLater(publish(), throwsA(isA<SeedRefused>()));
        expect(captures, phase == 'missing' ? 0 : 1);
        expect(publications, 0);
        expect(exits, 0);
        expect(original.operations, isEmpty);
        expect(ledger.attempts, isEmpty);
        expect(original.wsReads, 0);
        if (phase == 'replaced') {
          live = true;
          await expectLater(publish(), throwsA(isA<SeedRefused>()));
          expect(captures, 1);
          expect(publications, 0);
        }
        route.complete(null);
        continue;
      }
      final Map<String, Object?> receipt = await publish();
      expect(receipt, <String, Object?>{
        'confirmed': true, 'recipe': 'project', 'hash': _hash(9),
      });
      expect(captures, 1);
      expect(publications, 1);
      expect(exits, 0);
      final Map<String, Object?> finished = await commands.run(
        <String, dynamic>{'action': 'finish'}, booted: false,
        ui: (_) async => throw StateError('Unexpected generic UI query'),
        tap: (_, _) async => throw StateError('Unexpected generic pointer'),
      );
      expect(finished, receipt);
      expect(presentation.closed, isTrue);
      expect(exits, 1);
      await expectLater(publish(), throwsA(isA<SeedRefused>()));
      expect(captures, 1);
      expect(publications, 1);
      expect(original.operations, hasLength(1));
      expect(ledger.confirmedHashes,
          <String, String>{'project': _hash(9)});
    }
  });
  test('confirmed Token finish closes once and retains fixture admission',
      () async {
    expect(await guard.publish('token', () async {
      source.operations.add(_Original());
    }), _hash(9));
    expect(journal.confirmedHashes, <String, String>{'token': _hash(9)});
    final List<int> reads = <int>[
      source.wsReads, source.httpReads,
      source.confirmationReads, source.effectReads,
    ];
    final FixtureCleanup fixture = FixtureCleanup(name: 'sentinel');
    final Completer<Object?> route = Completer<Object?>();
    bool visible = true;
    int exits = 0;
    final SeedTokenPresentation presentation = SeedTokenPresentation(
      originalCurrent: () => visible,
      submittedCurrent: (String hash) => visible && hash == _hash(9),
      originalRouteCompleted: route.future,
      tapOriginalExit: (void Function() admission) async {
        admission();
        exits++;
        admission();
        visible = false;
        route.complete(null);
      },
    );
    SeedCommands commands({required bool confirmed}) =>
        SeedCommands.withFixtureAdmission(
      fixture: fixture, guard: guard, recipe: 'token',
      confirmed: confirmed, tokenPresentation: presentation,
    );
    Future<Map<String, Object?>> finish(SeedCommands original) => original.run(
      <String, dynamic>{'action': 'finish'}, booted: false,
      ui: (_) async => throw StateError('Unexpected generic UI query'),
      tap: (_, _) async => throw StateError('Unexpected generic pointer'),
    );
    await expectLater(finish(commands(confirmed: false)),
      throwsA(isA<SeedRefused>()
        .having((SeedRefused error) => error.code,
            'code', 'exact-confirmation-required')));
    final SeedCommands original = commands(confirmed: true);
    await expectLater(finish(original), throwsA(isA<SeedRefused>()
        .having((SeedRefused error) => error.code,
            'code', 'close-current-fixture-first')));
    expect(exits, 0);
    expect(presentation.closed, isFalse);
    final Object fixtureOwner = Object();
    fixture
      ..open(routeCompleted: Future<void>.value(),
          push: Future<void>.value)
      ..attach(fixtureOwner)
      ..dispose(owner: fixtureOwner, dispose: <void Function()>[],
          close: <Future<void> Function()>[], stateDisposed: () {});
    await Future<void>.delayed(Duration.zero);
    expect(fixture.heldName, isNull);
    final Map<String, Object?> receipt = await finish(original);
    expect(receipt, <String, Object?>{
      'confirmed': true, 'recipe': 'token', 'hash': _hash(9),
    });
    expect(presentation.closed, isTrue);
    expect(exits, 1);
    expect(() => fixture.attach(Object()), throwsStateError);
    expect(fixture.heldName, 'sentinel');
    expect(await finish(original), receipt);
    expect(exits, 1);
    expect(source.operations, hasLength(1));
    expect(<int>[source.wsReads, source.httpReads,
      source.confirmationReads, source.effectReads], reads);
    expect(journal.acceptedHashes, <String, String>{'token': _hash(9)});
    expect(journal.confirmedHashes, <String, String>{'token': _hash(9)});
  });

  test('Token capture precedes only its original exclusive publication',
      () async {
    for (final String phase in <String>['missing', 'replaced', 'captured']) {
      final _Source original = _Source();
      final _Journal ledger = _Journal();
      final SeedGuard scoped = SeedGuard(
        source: original, journal: ledger, delay: original.delay,
      );
      final FixtureCleanup fixture = FixtureCleanup(name: 'sentinel');
      final Object fixtureOwner = Object();
      fixture
        ..open(routeCompleted: Future<void>.value(),
            push: Future<void>.value)
        ..attach(fixtureOwner)
        ..dispose(owner: fixtureOwner, dispose: <void Function()>[],
            close: <Future<void> Function()>[], stateDisposed: () {});
      await Future<void>.delayed(Duration.zero);
      expect(fixture.heldName, isNull);
      bool live = phase != 'replaced';
      int captures = 0;
      int publications = 0;
      int exits = 0;
      final Completer<Object?> route = Completer<Object?>();
      final SeedTokenPresentation presentation = SeedTokenPresentation(
        originalCurrent: () => live,
        submittedCurrent: (String hash) => live && hash == _hash(9),
        originalRouteCompleted: route.future,
        tapOriginalExit: (void Function() admission) async {
          admission();
          exits++;
          admission();
          route.complete(null);
        },
      );
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture, guard: scoped, recipe: 'token',
      );
      Future<Map<String, Object?>> publish() => commands.run(
        <String, dynamic>{'action': 'publish'}, booted: false,
        ui: (Map<String, dynamic> request) async {
          expect(request, <String, dynamic>{
            'cmd': 'assert', 'key': 'token_create_continue',
            'kind': 'button', 'exact': true,
          });
          return <String, Object?>{
            'target': <String, Object?>{'ref': 7},
          };
        },
        tap: (Map<String, dynamic> request,
            void Function() admission) async {
          admission();
          admission();
          expect(request, <String, dynamic>{'cmd': 'tap', 'ref': 7});
          publications++;
          original.operations.add(_Original());
          return <String, Object?>{};
        },
        captureTokenPresentation: phase == 'missing'
            ? null : (int ref, String owner) {
          expect(owner, 'owner');
          captures++;
          expect(ref, 7);
          expect(original.operations, isEmpty);
          expect(original.wsReads, 0);
          expect(original.httpReads, 0);
          expect(ledger.attempts, isEmpty);
          return presentation;
        },
      );
      if (phase != 'captured') {
        await expectLater(publish(), throwsA(isA<SeedRefused>()));
        expect(captures, phase == 'missing' ? 0 : 1);
        expect(publications, 0);
        expect(exits, 0);
        expect(original.operations, isEmpty);
        expect(ledger.attempts, isEmpty);
        expect(original.wsReads, 0);
        if (phase == 'replaced') {
          live = true;
          await expectLater(publish(), throwsA(isA<SeedRefused>()));
          expect(captures, 1);
          expect(publications, 0);
        }
        route.complete(null);
        continue;
      }
      final Map<String, Object?> receipt = await publish();
      expect(receipt, <String, Object?>{
        'confirmed': true, 'recipe': 'token', 'hash': _hash(9),
      });
      expect(captures, 1);
      expect(publications, 1);
      expect(exits, 0);
      final Map<String, Object?> finished = await commands.run(
        <String, dynamic>{'action': 'finish'}, booted: false,
        ui: (_) async => throw StateError('Unexpected generic UI query'),
        tap: (_, _) async => throw StateError('Unexpected generic pointer'),
      );
      expect(finished, receipt);
      expect(presentation.closed, isTrue);
      expect(exits, 1);
      await expectLater(publish(), throwsA(isA<SeedRefused>()));
      expect(captures, 1);
      expect(publications, 1);
      expect(original.operations, hasLength(1));
      expect(ledger.confirmedHashes,
          <String, String>{'token': _hash(9)});
    }
  });
}
