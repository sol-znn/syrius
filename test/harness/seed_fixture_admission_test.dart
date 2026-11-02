import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/fixtures/fixture_cleanup.dart';
import '../../harness/app/fixtures/seed_commands.dart';
import '../../harness/app/fixtures/seed_deposit_entry.dart';
import '../../harness/app/fixtures/seed_deposit_presentation.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../../harness/seed_preparation_failure.dart';

class _PrivatePreparationError implements Exception {
  @override
  String toString() =>
      throw StateError('Private preparation errors cannot be formatted');
}

String _hash(int value) => value.toRadixString(16).padLeft(64, '0');

Future<void> _turns() async {
  for (int turn = 0; turn < 8; turn++) {
    await Future<void>.value();
  }
}

Matcher _refused(String code) => throwsA(
  isA<SeedRefused>().having((SeedRefused error) => error.code, 'code', code),
);

Map<String, Object?> _target() => <String, Object?>{
  'target': <String, Object?>{'ref': 7, 'enabled': true},
};

Future<Map<String, Object?>> _run(
  SeedCommands commands,
  String action, {
  Future<Map<String, Object?>> Function(Map<String, dynamic>)? ui,
  Future<Map<String, Object?>> Function(
    Map<String, dynamic>,
    void Function(),
  )?
  tap,
}) => commands.run(
  <String, dynamic>{
    'action': action,
    if (action == 'prepare')
      'selector': <String>['--key', 'staking_stake_button'],
  },
  booted: false,
  ui: ui ?? (_) async => throw StateError('Unexpected UI access'),
  tap: tap ?? (_, _) async => throw StateError('Unexpected pointer access'),
);

class _Original implements SeedOriginal {
  @override
  final Object identity = Object();
  @override
  bool get settled => true;
  @override
  bool get failed => false;
  @override
  bool get releaseFailed => false;
  @override
  String get acceptedHash => _hash(9);
}

class _Journal implements SeedJournal {
  int claims = 0;
  String? acceptedHash;
  String? confirmedHash;

  @override
  void requireAvailable(String recipe) {
    if (claims != 0) throw const SeedRefused('original-attempt-held');
  }

  @override
  void claim(String recipe) {
    requireAvailable(recipe);
    claims++;
  }

  @override
  void accepted(String recipe, String hash) => acceptedHash = hash;

  @override
  void confirmed(String recipe, String hash) => confirmedHash = hash;
}

/// Policy inputs are synthetic values, without an SDK, wallet or transport.
class _Source implements SeedSource {
  @override
  final SeedEnvironment environment = SeedEnvironment(
    profile: 'fixture-policy',
    isolated: true,
    unlocked: true,
    initialized: true,
    booted: true,
    ws: seedWsOrigin,
    http: seedHttpOrigin,
    nodeChain: 321,
    signingChain: 321,
    selectedIndex: 1,
    owner: 'owner',
    members: <String>['producer', 'owner'],
  );
  @override
  bool isCurrent = true;
  int reads = 0;
  int confirmations = 0;
  int _wsHeight = 10;
  int _httpHeight = 10;
  void Function()? onRead;
  final List<SeedOriginal> operations = <SeedOriginal>[];

  Future<void> delay(Duration _) async {}

  SeedFrontier _frontier(int height) {
    reads++;
    onRead?.call();
    return SeedFrontier(
      chain: 321,
      height: height,
      timestamp: height + 100,
      hash: _hash(height),
    );
  }

  @override
  Future<SeedFrontier> wsFrontier() async => _frontier(++_wsHeight);
  @override
  Future<SeedFrontier> httpFrontier() async => _frontier(++_httpHeight);
  @override
  Future<bool> sameMomentum(SeedFrontier _) async => true;
  @override
  Future<SeedFunding> funding() async => SeedFunding(BigInt.one, BigInt.one);
  @override
  SeedFunding minimum(String _) => SeedFunding(BigInt.one, BigInt.one);
  @override
  List<SeedOriginal> originals() => List<SeedOriginal>.unmodifiable(operations);
  @override
  Future<SeedConfirmed?> confirmed(String recipe, String hash) async {
    confirmations++;
    return SeedConfirmed(
      hash: hash,
      owner: environment.owner,
      chain: 321,
      positiveConfirmation: true,
      matchesRecipe: true,
    );
  }

  @override
  Future<bool> effect(String recipe, String hash) async => true;
}

class _Fixture {
  _Fixture() {
    cleanup
      ..open(routeCompleted: route.future, push: () => popped.future)
      ..attach(owner);
  }

  final Completer<void> route = Completer<void>();
  final Completer<void> popped = Completer<void>();
  final Completer<void> close = Completer<void>();
  final Object owner = Object();
  final FixtureCleanup cleanup = FixtureCleanup(name: 'sentinel');
  int disposals = 0;
  int closes = 0;

  void retire() {
    cleanup.dispose(
      owner: owner,
      dispose: <void Function()>[],
      close: <Future<void> Function()>[_close],
      stateDisposed: _disposed,
    );
    route.complete();
    popped.complete();
  }

  Future<void> allow() async {
    retire();
    close.complete();
    await _turns();
    expect(cleanup.heldName, isNull);
  }

  void holdAgain() {
    expect(() => cleanup.attach(Object()), throwsStateError);
    expect(cleanup.heldName, 'sentinel');
  }

  Future<void> _close() {
    closes++;
    return close.future;
  }

  void _disposed() => disposals++;
}

void main() {
  for (final String phase in <String>['active', 'pending', 'failed']) {
    test(
      '$phase fixture refuses every mutating seed action before UI or binding',
      () async {
        final _Fixture fixture = _Fixture();
        final _Source source = _Source();
        final _Journal journal = _Journal();
        final SeedGuard guard = SeedGuard(
          source: source,
          journal: journal,
          delay: source.delay,
        );
        final SeedCommands commands = SeedCommands.withFixtureAdmission(
          fixture: fixture.cleanup,
          guard: guard,
          recipe: 'stake',
        );
        if (phase != 'active') fixture.retire();
        if (phase == 'failed') {
          fixture.close.completeError(
            StateError('Synthetic original cleanup failure'),
            StackTrace.current,
          );
        }
        await _turns();
        for (final String action in <String>[
          'begin',
          'fixture',
          'prepare',
          'publish',
        ]) {
          await expectLater(
            _run(commands, action),
            _refused('close-current-fixture-first'),
          );
        }
        expect(source.reads, 0);
        expect(journal.claims, 0);
        expect(guard.acceptedHash, isNull);
        expect(guard.requirePreparation, returnsNormally);
        expect(await _run(commands, 'check'), <String, Object?>{
          'current': true,
        });
        await expectLater(
          _run(commands, 'finish'),
          _refused('exact-confirmation-required'),
        );
        expect(commands.fixtureName, 'sentinel');
        if (phase == 'active') fixture.retire();
        if (!fixture.close.isCompleted) fixture.close.complete();
        await _turns();
        expect(fixture.disposals, 1);
        expect(fixture.closes, 1);
      },
    );
  }

  test(
    'successful original cleanup permits the retained unattempted recipe',
    () async {
      final _Fixture fixture = _Fixture();
      await fixture.allow();
      final _Source source = _Source();
      final _Journal journal = _Journal();
      final SeedGuard guard = SeedGuard(
        source: source,
        journal: journal,
        delay: source.delay,
      );
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture.cleanup,
        guard: guard,
        recipe: 'stake',
      );
      int effects = 0;
      expect(
        await _run(
          commands,
          'prepare',
          ui: (_) async => _target(),
          tap: (_, void Function() admission) async {
            admission();
            effects++;
            admission();
            return <String, Object?>{};
          },
        ),
        <String, Object?>{'prepared': true},
      );
      expect(effects, 1);
      expect(source.reads, 0);
      expect(journal.claims, 0);
      expect(guard.requirePreparation, returnsNormally);
      expect(
        await _run(
          commands,
          'publish',
          ui: (_) async => _target(),
          tap: (_, void Function() admission) async {
            admission();
            effects++;
            source.operations.add(_Original());
            admission();
            return <String, Object?>{};
          },
        ),
        <String, Object?>{
          'confirmed': true,
          'recipe': 'stake',
          'hash': _hash(9),
        },
      );
      expect(effects, 2);
      expect(journal.claims, 1);
      expect(guard.acceptedHash, _hash(9));
      expect(await _run(commands, 'finish'), <String, Object?>{
        'confirmed': true,
        'recipe': 'stake',
        'hash': _hash(9),
      });
      await expectLater(
        _run(commands, 'prepare'),
        _refused('original-attempt-held'),
      );
      await expectLater(
        _run(commands, 'publish'),
        _refused('seed-command-refused'),
      );
      expect(journal.claims, 1);
      expect(source.operations, hasLength(1));
    },
  );

  test('held cleanup leaves the original confirmed hash readable', () async {
    final _Source source = _Source();
    final _Journal journal = _Journal();
    final SeedGuard guard = SeedGuard(
      source: source,
      journal: journal,
      delay: source.delay,
    );
    final String originalHash = await guard.publish('stake', () async {
      source.operations.add(_Original());
    });
    final _Fixture fixture = _Fixture()..retire();
    final SeedCommands commands = SeedCommands.withFixtureAdmission(
      fixture: fixture.cleanup,
      guard: guard,
      recipe: 'stake',
      confirmed: true,
    );
    final int originalReads = source.reads;
    for (int observation = 0; observation < 2; observation++) {
      if (observation == 1) {
        fixture.close.completeError(
          StateError('Synthetic late original cleanup failure'),
          StackTrace.current,
        );
        await _turns();
      }
      expect(await _run(commands, 'check'), <String, Object?>{'current': true});
      expect(await _run(commands, 'finish'), <String, Object?>{
        'confirmed': true,
        'recipe': 'stake',
        'hash': originalHash,
      });
      await expectLater(
        _run(commands, 'publish'),
        _refused('close-current-fixture-first'),
      );
      expect(guard.acceptedHash, originalHash);
      expect(journal.acceptedHash, originalHash);
      expect(journal.confirmedHash, originalHash);
      expect(journal.claims, 1);
      expect(source.reads, originalReads);
      expect(source.operations, hasLength(1));
    }
  });

  for (final String action in <String>['prepare', 'publish']) {
    test(
      '$action rechecks fixture admission after its original UI assertion',
      () async {
        final _Fixture fixture = _Fixture();
        await fixture.allow();
        final _Source source = _Source();
        final _Journal journal = _Journal();
        final SeedGuard guard = SeedGuard(
          source: source,
          journal: journal,
          delay: source.delay,
        );
        final SeedCommands commands = SeedCommands.withFixtureAdmission(
          fixture: fixture.cleanup,
          guard: guard,
          recipe: 'stake',
        );
        int taps = 0;
        await expectLater(
          _run(
            commands,
            action,
            ui: (_) async {
              fixture.holdAgain();
              return _target();
            },
            tap: (_, _) async {
              taps++;
              return <String, Object?>{};
            },
          ),
          _refused('close-current-fixture-first'),
        );
        expect(taps, 0);
        expect(source.reads, 0);
        expect(journal.claims, 0);
        expect(guard.requirePreparation, returnsNormally);
      },
    );

    test(
      '$action rechecks held admission in the original pointer callback',
      () async {
        final _Fixture fixture = _Fixture();
        await fixture.allow();
        final _Source source = _Source();
        final _Journal journal = _Journal();
        final SeedGuard guard = SeedGuard(
          source: source,
          journal: journal,
          delay: source.delay,
        );
        final SeedCommands commands = SeedCommands.withFixtureAdmission(
          fixture: fixture.cleanup,
          guard: guard,
          recipe: 'stake',
        );
        int taps = 0;
        int effects = 0;
        await expectLater(
          _run(
            commands,
            action,
            ui: (_) async => _target(),
            tap: (_, void Function() admission) async {
              taps++;
              admission();
              fixture.holdAgain();
              admission();
              effects++;
              return <String, Object?>{};
            },
          ),
          _refused('close-current-fixture-first'),
        );
        expect(taps, 1);
        expect(effects, 0);
        expect(journal.claims, action == 'publish' ? 1 : 0);
        if (action == 'publish') {
          expect(guard.requirePreparation, _refused('original-attempt-held'));
        } else {
          expect(guard.requirePreparation, returnsNormally);
        }
        expect(source.operations, isEmpty);
        expect(guard.acceptedHash, isNull);
        expect(await _run(commands, 'check'), <String, Object?>{
          'current': true,
        });
      },
    );
  }

  test(
    'publication refuses a late held fixture before invoking its original tap',
    () async {
      final _Fixture fixture = _Fixture();
      await fixture.allow();
      final _Source source = _Source();
      source.onRead = () {
        source.onRead = null;
        fixture.holdAgain();
      };
      final _Journal journal = _Journal();
      final SeedGuard guard = SeedGuard(
        source: source,
        journal: journal,
        delay: source.delay,
      );
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture.cleanup,
        guard: guard,
        recipe: 'stake',
      );
      int taps = 0;
      await expectLater(
        _run(
          commands,
          'publish',
          ui: (_) async => _target(),
          tap: (_, _) async {
            taps++;
            return <String, Object?>{};
          },
        ),
        _refused('close-current-fixture-first'),
      );
      expect(taps, 0);
      expect(journal.claims, 1);
      expect(guard.requirePreparation, _refused('original-attempt-held'));
      expect(guard.acceptedHash, isNull);
      expect(source.confirmations, 0);
      await expectLater(
        _run(commands, 'publish'),
        _refused('close-current-fixture-first'),
      );
      expect(journal.claims, 1);
    },
  );

  test(
    'read-only results still require the original wallet policy context',
    () async {
      final _Fixture fixture = _Fixture();
      final _Source source = _Source();
      final SeedGuard guard = SeedGuard(
        source: source,
        journal: _Journal(),
        delay: source.delay,
      );
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture.cleanup,
        guard: guard,
        recipe: 'stake',
        confirmed: true,
      );
      source.isCurrent = false;
      await expectLater(
        _run(commands, 'check'),
        _refused('original-context-changed'),
      );
      await expectLater(
        _run(commands, 'finish'),
        _refused('original-context-changed'),
      );
      fixture.retire();
      fixture.close.complete();
      await _turns();
    },
  );

  test(
    'Deposit warning preparation observes one owner without SDK or publication',
    () async {
      final _Fixture fixture = _Fixture();
      await fixture.allow();
      final _Source source = _Source();
      final _Journal journal = _Journal();
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture.cleanup,
        guard: SeedGuard(source: source, journal: journal, delay: source.delay),
        recipe: 'deposit',
      );
      int captures = 0;
      int pointers = 0;
      Future<Map<String, Object?>> prepare() => commands.run(
        <String, dynamic>{'action': 'prepare',
          'selector': <String>['--key', 'p2p_warning_continue']},
        booted: false,
        ui: (_) async => throw StateError('No generic UI request'),
        tap: (_, _) async => throw StateError('No generic pointer'),
        captureDepositEntry: (String owner) {
          captures++;
          expect(owner, source.environment.owner);
          return SeedDepositEntry.warning(originalCurrent: () => true,
            tapOriginalContinue: (void Function() admission) async {
              admission(); pointers++; admission();
            },
          );
        },
      );
      expect(await prepare(), <String, Object?>{'prepared': true});
      await expectLater(prepare(), _refused('original-deposit-entry-held'));
      expect(captures, 1);
      expect(pointers, 1);
      expect(source.reads, 0);
      expect(source.confirmations, 0);
      expect(journal.claims, 0);
      expect(source.operations, isEmpty);
    },
  );

  test(
    'Deposit entry refuses context replacement during its observation',
    () async {
      final _Fixture fixture = _Fixture();
      await fixture.allow();
      final _Source source = _Source();
      final _Journal journal = _Journal();
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture.cleanup,
        guard: SeedGuard(source: source, journal: journal, delay: source.delay),
        recipe: 'deposit',
      );
      int captures = 0;
      int pointers = 0;
      Future<Map<String, Object?>> prepare() => commands.run(
        <String, dynamic>{'action': 'prepare',
          'selector': <String>['--key', 'p2p_warning_continue']},
        booted: false,
        ui: (_) async => throw StateError('No generic UI request'),
        tap: (_, _) async => throw StateError('No generic pointer'),
        captureDepositEntry: (_) {
          captures++;
          source.isCurrent = false;
          return SeedDepositEntry.warning(originalCurrent: () => true,
            tapOriginalContinue: (_) async { pointers++; });
        },
      );
      await expectLater(prepare(), _refused('original-context-changed'));
      source.isCurrent = true;
      await expectLater(prepare(), _refused('original-context-changed'));
      expect(captures, 1);
      expect(pointers, 0);
      expect(source.reads, 0);
      expect(journal.claims, 0);
    },
  );

  test('Deposit capture precedes its original exclusive publication',
      () async {
    for (final String phase in <String>['missing', 'replaced', 'captured']) {
      final _Fixture fixture = _Fixture();
      await fixture.allow();
      final _Source source = _Source();
      final _Journal journal = _Journal();
      final SeedGuard guard = SeedGuard(
        source: source, journal: journal, delay: source.delay,
      );
      final SeedCommands commands = SeedCommands.withFixtureAdmission(
        fixture: fixture.cleanup, guard: guard, recipe: 'deposit',
      );
      int captures = 0;
      int publications = 0;
      int exits = 0;
      final Completer<Object?> route = Completer<Object?>();
      final SeedDepositPresentation presentation = SeedDepositPresentation(
        originalCurrent: () => phase != 'replaced',
        submittedCurrent: (String hash) => hash == _hash(9),
        originalRouteCompleted: route.future,
        tapOriginalExit: (void Function() admission) async {
          admission();
          exits++;
          route.complete(null);
        },
      );
      Future<Map<String, Object?>> publish() => commands.run(
        <String, dynamic>{'action': 'publish'}, booted: false,
        ui: (Map<String, dynamic> request) async {
          expect(request, <String, dynamic>{
            'cmd': 'assert', 'key': 'swap_create_deposit',
            'kind': 'button', 'exact': true,
          });
          return _target();
        },
        tap: (Map<String, dynamic> request, void Function() admission) async {
          expect(request, <String, dynamic>{'cmd': 'tap', 'ref': 7});
          admission();
          publications++;
          source.operations.add(_Original());
          return <String, Object?>{};
        },
        captureDepositPresentation: phase == 'missing' ? null
            : (int reference, String owner) {
                captures++;
                expect(reference, 7);
                expect(owner, source.environment.owner);
                return presentation;
              },
      );
      if (phase != 'captured') {
        await expectLater(publish(), throwsA(isA<SeedRefused>()));
        expect(journal.claims, 0);
        expect(publications, 0);
        expect(exits, 0);
        continue;
      }
      final Map<String, Object?> receipt = await publish();
      expect(captures, 1);
      expect(publications, 1);
      expect(exits, 0);
      final int reads = source.reads;
      final int confirmations = source.confirmations;
      expect(await _run(commands, 'finish'), receipt);
      expect(presentation.closed, isTrue);
      expect(exits, 1);
      expect(source.reads, reads);
      expect(source.confirmations, confirmations);
      await expectLater(publish(), throwsA(isA<SeedRefused>()));
      expect(captures, 1);
      expect(publications, 1);
    }
  });

  test('Deposit finish needs confirmation and preserves fixture admission',
      () async {
    final _Fixture fixture = _Fixture();
    final _Source source = _Source();
    final SeedGuard guard = SeedGuard(
      source: source, journal: _Journal(), delay: source.delay,
    );
    await guard.publish('deposit', () async {
      source.operations.add(_Original());
    });
    int exits = 0;
    final Completer<Object?> route = Completer<Object?>();
    final SeedDepositPresentation presentation = SeedDepositPresentation(
      originalCurrent: () => true,
      submittedCurrent: (String hash) => hash == _hash(9),
      originalRouteCompleted: route.future,
      tapOriginalExit: (void Function() admission) async {
        admission(); exits++; route.complete(null);
      },
    );
    SeedCommands commands({required bool confirmed}) =>
        SeedCommands.withFixtureAdmission(
      fixture: fixture.cleanup, guard: guard, recipe: 'deposit',
      confirmed: confirmed, depositPresentation: presentation,
    );
    await expectLater(_run(commands(confirmed: false), 'finish'),
        _refused('exact-confirmation-required'));
    final SeedCommands original = commands(confirmed: true);
    await expectLater(_run(original, 'finish'),
        _refused('close-current-fixture-first'));
    expect(exits, 0);
    await fixture.allow();
    final int reads = source.reads;
    final int confirmations = source.confirmations;
    final Map<String, Object?> receipt = await _run(original, 'finish');
    fixture.holdAgain();
    expect(await _run(original, 'finish'), receipt);
    expect(exits, 1);
    expect(source.reads, reads);
    expect(source.confirmations, confirmations);
  });

  test('Deposit completion retains a changed owner before pointer release',
      () async {
    final _Fixture fixture = _Fixture();
    await fixture.allow();
    final _Source source = _Source();
    final SeedGuard guard = SeedGuard(
      source: source, journal: _Journal(), delay: source.delay,
    );
    await guard.publish('deposit', () async {
      source.operations.add(_Original());
    });
    int exits = 0;
    final SeedDepositPresentation presentation = SeedDepositPresentation(
      originalCurrent: () => true,
      submittedCurrent: (String hash) => hash == _hash(9),
      originalRouteCompleted: Future<Object?>.value(),
      tapOriginalExit: (void Function() admission) async {
        admission();
        source.isCurrent = false;
        admission();
        exits++;
      },
    );
    final SeedCommands commands = SeedCommands.withFixtureAdmission(
      fixture: fixture.cleanup, guard: guard, recipe: 'deposit',
      confirmed: true, depositPresentation: presentation,
    );
    final int reads = source.reads;
    await expectLater(_run(commands, 'finish'),
        _refused('original-context-changed'));
    source.isCurrent = true;
    await expectLater(_run(commands, 'finish'),
        _refused('original-context-changed'));
    expect(exits, 0);
    expect(source.reads, reads);
    expect(presentation.closed, isFalse);
  });

  test('a held fixture refuses Deposit entry before its observation', () async {
    final _Fixture fixture = _Fixture();
    final _Source source = _Source();
    final _Journal journal = _Journal();
    final SeedCommands commands = SeedCommands.withFixtureAdmission(
      fixture: fixture.cleanup,
      guard: SeedGuard(source: source, journal: journal, delay: source.delay),
      recipe: 'deposit',
    );
    int captures = 0;
    await expectLater(commands.run(
      <String, dynamic>{'action': 'prepare',
        'selector': <String>['--key', 'p2p_warning_continue']},
      booted: false,
      ui: (_) async => throw StateError('No generic UI request'),
      tap: (_, _) async => throw StateError('No generic pointer'),
      captureDepositEntry: (_) {
        captures++;
        return SeedDepositEntry.ready(originalCurrent: () => true);
      },
    ), _refused('close-current-fixture-first'));
    expect(captures, 0);
    expect(source.reads, 0);
    expect(journal.claims, 0);
    fixture.retire();
    fixture.close.complete();
    await _turns();
  });

  test('preparation labels accept only exact source messages', () {
    const Map<String, String> labels = <String, String>{
      'nothing matches': 'seed-preparation-target-missing',
      'disabled': 'seed-preparation-target-disabled',
      'covered by something else': 'seed-preparation-target-covered',
      'assert target is covered': 'seed-preparation-target-covered',
      'error widget on screen': 'seed-preparation-error-widget',
    };
    for (final MapEntry<String, String> entry in labels.entries) {
      expect(seedPreparationUiFailureCode(entry.key), entry.value);
    }
    expect(labels.values.toSet(), seedPreparationUiFailureCodes);
    for (final Object? value in <Object?>[
      null, true, 1, '', 'private', 'disabled\n', 'disabled private',
      _PrivatePreparationError(),
    ]) {
      expect(seedPreparationUiFailureCode(value), isNull);
    }
  });

  test('successful preparation calls the original once without inspection',
      () async {
    final Completer<Object> answer = Completer<Object>();
    final Object original = Object();
    int calls = 0;
    int classifications = 0;
    final Future<Object> observed = observeSeedPreparation(
      preparation: true,
      original: () {
        calls++;
        return answer.future;
      },
      classify: (_) {
        classifications++;
        throw StateError('A successful result cannot inspect a failure');
      },
    );
    await _turns();
    expect(calls, 1);
    expect(classifications, 0);
    answer.complete(original);
    expect(await observed, same(original));
    expect(calls, 1);
    expect(classifications, 0);
  });

  test('a failed original preparation exposes only a finite label once',
      () async {
    for (final String label in seedPreparationUiFailureCodes) {
      final _PrivatePreparationError original = _PrivatePreparationError();
      final Completer<Object> answer = Completer<Object>();
      int calls = 0;
      int classifications = 0;
      final Future<Object> observed = observeSeedPreparation(
        preparation: true,
        original: () {
          calls++;
          return answer.future;
        },
        classify: (Object error) {
          classifications++;
          expect(error, same(original));
          return label;
        },
      );
      final Future<void> refused = expectLater(observed, _refused(label));
      answer.completeError(original);
      await refused;
      expect(calls, 1);
      expect(classifications, 1);
    }
  });

  test('other actions and existing guards preserve the original error',
      () async {
    for (final bool preparation in <bool>[false, true]) {
      final Object original = preparation
          ? const SeedRefused('original-context-changed')
          : _PrivatePreparationError();
      int calls = 0;
      int classifications = 0;
      final Future<Object> observed = observeSeedPreparation(
        preparation: preparation,
        original: () {
          calls++;
          return Future<Object>.error(original);
        },
        classify: (_) {
          classifications++;
          return 'seed-preparation-target-covered';
        },
      );
      await expectLater(observed, throwsA(same(original)));
      expect(calls, 1);
      expect(classifications, 0);
    }
  });

  test('private or failing classifiers preserve the original failure',
      () async {
    final Object throwing = Object();
    for (final Object? label in <Object?>[
      null, true, 1, '', 'private', 'seed-preparation-target-covered ',
      _PrivatePreparationError(), throwing,
    ]) {
      final _PrivatePreparationError original = _PrivatePreparationError();
      int calls = 0;
      int classifications = 0;
      final Future<Object> observed = observeSeedPreparation(
        preparation: true,
        original: () {
          calls++;
          return Future<Object>.error(original);
        },
        classify: (Object error) {
          classifications++;
          expect(error, same(original));
          if (identical(label, throwing)) {
            throw StateError('Synthetic classifier failure');
          }
          return label;
        },
      );
      await expectLater(observed, throwsA(same(original)));
      expect(calls, 1);
      expect(classifications, 1);
    }
  });
}
