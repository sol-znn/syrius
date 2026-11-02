import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';

import 'support.dart';

const SecurityPreference _lock = SecurityPreference.lockMinutes;
const SecurityPreference _limit = SecurityPreference.wrongPasswords;

Future<void> _turn() => Future<void>.delayed(Duration.zero);

class _PolicyObserver extends BlocObserver {
  void Function(BlocBase<dynamic> bloc, Change<dynamic> change)? changed;
  bool throwError = false;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    changed?.call(bloc, change);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    if (throwError) {
      throw StateError('synthetic diagnostic observer');
    }
  }
}

void main() {
  late SecurityPolicyFixture source;
  late SecuritySettingsPresenter presenter;

  setUp(() {
    source = SecurityPolicyFixture();
    presenter = securityPresenter(source);
  });
  tearDown(() async {
    if (!presenter.isClosed) {
      await presenter.close();
    }
  });

  test('construction and close have no persistence or policy effects', () {
    expect(source.target.calls, isEmpty);
    expect(presenter.state.lockMinutes, 15);
    expect(presenter.state.wrongPasswords, 3);
  });

  test('only absent preferences use the established positive defaults', () {
    expect(securityPositivePreference(null, exists: false, fallback: 15), 15);
    expect(securityPositivePreference(null, exists: false, fallback: 3), 3);
    expect(
      securityPositivePreference(null, exists: true, fallback: 15),
      isNull,
    );
  });

  test('malformed policies stay unknown rather than selecting defaults', () {
    for (final Object? value in <Object?>[
      null,
      0,
      -1,
      3.5,
      double.infinity,
      '3',
      true,
    ]) {
      expect(
        securityPositivePreference(value, exists: true, fallback: 15),
        isNull,
      );
    }
  });

  test('positive custom int and whole legacy double values are retained', () {
    expect(securityPositivePreference(7, exists: true, fallback: 15), 7);
    expect(securityPositivePreference(4.0, exists: true, fallback: 3), 4);
  });

  test(
    'successful choice persists before policy and awaited notification',
    () async {
      expect(await presenter.choose(_lock, 5, epoch: presenter.epoch), isTrue);
      expect(source.target.calls, <String>[
        'put:lockMinutes:5',
        'saved:lockMinutes:5',
        'apply:lockMinutes:5',
        'effect:lockMinutes',
        'notice:lockMinutes',
      ]);
      expect(presenter.state.lockMinutes, 5);
      expect(presenter.state.busy, isFalse);
    },
  );

  test('wrong-password policy keeps its positive exact saved value', () async {
    expect(await presenter.choose(_limit, 10, epoch: presenter.epoch), isTrue);
    expect(source.target.saved[_limit], 10);
    expect(source.target.applied[_limit], 10);
    expect(presenter.state.wrongPasswords, 10);
  });

  test('zero negative and unchanged choices admit no dependency', () async {
    for (final int value in <int>[0, -1, 15]) {
      expect(
        await presenter.choose(_lock, value, epoch: presenter.epoch),
        isFalse,
      );
    }
    expect(source.target.calls, isEmpty);
  });

  test(
    'unknown values remain unselected until an explicit positive choice',
    () async {
      final SecuritySettingsPresenter unknown = SecuritySettingsPresenter(
        initial: const SecuritySettingsState(
          lockMinutes: null,
          wrongPasswords: null,
        ),
        capture: () => source,
      );
      expect(unknown.state.lockMinutes, isNull);
      expect(unknown.state.wrongPasswords, isNull);
      expect(await unknown.choose(_lock, 15, epoch: unknown.epoch), isTrue);
      expect(unknown.state.lockMinutes, 15);
      expect(unknown.state.wrongPasswords, isNull);
      await unknown.close();
    },
  );

  test(
    'unobserved visibility round trip cannot revive a saved callback',
    () async {
      final int old = presenter.epoch;
      presenter
        ..setVisible(visible: false)
        ..setVisible(visible: true);
      expect(await presenter.choose(_lock, 5, epoch: old), isFalse);
      expect(source.target.calls, isEmpty);
    },
  );

  test(
    'a retained callback refuses before invoking its capture factory',
    () async {
      int captures = 0;
      final SecuritySettingsPresenter original = SecuritySettingsPresenter(
        initial: presenter.state,
        capture: () {
          captures++;
          return source;
        },
      );
      final int epoch = original.epoch;
      await original.close();
      expect(await original.choose(_lock, 5, epoch: epoch), isFalse);
      expect(captures, 0);
    },
  );

  test('duplicate saved callback cannot begin a second write', () async {
    final Completer<void> gate = Completer<void>();
    source.putGate = gate;
    final Future<bool> first = presenter.choose(
      _lock,
      5,
      epoch: presenter.epoch,
    );
    await source.putStarted.future;
    expect(await presenter.choose(_lock, 60, epoch: presenter.epoch), isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(
      source.target.calls.where((String e) => e.startsWith('put:')),
      <String>['put:lockMinutes:5'],
    );
  });

  test(
    'admitted write finishes its original policy after section leaves',
    () async {
      final Completer<void> gate = Completer<void>();
      source.putGate = gate;
      final Future<bool> original = presenter.choose(
        _lock,
        5,
        epoch: presenter.epoch,
      );
      await source.putStarted.future;
      source.visible = false;
      presenter.setVisible(visible: false);
      gate.complete();
      expect(await original, isTrue);
      expect(source.target.saved[_lock], 5);
      expect(source.target.applied[_lock], 5);
      expect(presenter.state.lockMinutes, 5);
      expect(source.target.calls, isNot(contains('notice:lockMinutes')));
    },
  );

  test('admitted write retains completion after presenter disposal', () async {
    final Completer<void> gate = Completer<void>();
    source.putGate = gate;
    final Future<bool> original = presenter.choose(
      _lock,
      60,
      epoch: presenter.epoch,
    );
    await source.putStarted.future;
    source.visible = false;
    await presenter.close();
    gate.complete();
    expect(await original, isTrue);
    expect(source.target.saved[_lock], 60);
    expect(source.target.applied[_lock], 60);
    expect(source.target.calls, isNot(contains('notice:lockMinutes')));
  });

  test(
    'replacement store cannot receive the original global policy effect',
    () async {
      final Completer<void> gate = Completer<void>();
      source.putGate = gate;
      final Future<bool> original = presenter.choose(
        _lock,
        5,
        epoch: presenter.epoch,
      );
      await source.putStarted.future;
      source.owned = false;
      gate.complete();
      expect(await original, isFalse);
      expect(source.target.applied[_lock], 15);
      expect(source.target.calls, isNot(contains('effect:lockMinutes')));
    },
  );

  test(
    'write failure leaves the original saved and active policies intact',
    () async {
      source.failPut = true;
      expect(await presenter.choose(_lock, 5, epoch: presenter.epoch), isFalse);
      expect(source.target.saved[_lock], 15);
      expect(source.target.applied[_lock], 15);
      expect(presenter.state.failed, isTrue);
    },
  );

  test(
    'an awaited callback failure retains the completed original commit',
    () async {
      source.failEffect = true;
      expect(await presenter.choose(_lock, 5, epoch: presenter.epoch), isTrue);
      expect(source.target.saved[_lock], 5);
      expect(presenter.state.lockMinutes, 5);
      expect(presenter.state.failed, isFalse);
    },
  );

  test(
    'notification failure cannot reverse the original saved policy',
    () async {
      source.failNotice = true;
      expect(await presenter.choose(_limit, 5, epoch: presenter.epoch), isTrue);
      expect(presenter.state.wrongPasswords, 5);
      expect(presenter.state.failed, isFalse);
    },
  );

  test(
    'same exact store and key serialize through the original callback',
    () async {
      final Completer<void> callback = Completer<void>();
      source.effectGate = callback;
      final SecurityPolicyFixture next = SecurityPolicyFixture(
        store: source.target,
      );
      final SecuritySettingsPresenter other = securityPresenter(next);
      final Future<bool> first = presenter.choose(
        _lock,
        5,
        epoch: presenter.epoch,
      );
      await source.effectStarted.future;
      final Future<bool> second = other.choose(_lock, 60, epoch: other.epoch);
      await _turn();
      expect(next.putStarted.isCompleted, isFalse);
      callback.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(source.target.saved[_lock], 60);
      expect(source.target.applied[_lock], 60);
      await other.close();
    },
  );

  test(
    'queued hidden successor refuses before writing after lane release',
    () async {
      final Completer<void> gate = Completer<void>();
      source.putGate = gate;
      final SecurityPolicyFixture next = SecurityPolicyFixture(
        store: source.target,
      );
      final SecuritySettingsPresenter other = securityPresenter(next);
      final Future<bool> first = presenter.choose(
        _lock,
        5,
        epoch: presenter.epoch,
      );
      await source.putStarted.future;
      final Future<bool> second = other.choose(_lock, 60, epoch: other.epoch);
      other.setVisible(visible: false);
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(next.putStarted.isCompleted, isFalse);
      await other.close();
    },
  );

  test('different original keys do not block each other', () async {
    final Completer<void> gate = Completer<void>();
    source.putGate = gate;
    final SecurityPolicyFixture next = SecurityPolicyFixture(
      store: source.target,
    );
    final SecuritySettingsPresenter other = securityPresenter(next);
    final Future<bool> first = presenter.choose(
      _lock,
      5,
      epoch: presenter.epoch,
    );
    await source.putStarted.future;
    expect(await other.choose(_limit, 5, epoch: other.epoch), isTrue);
    gate.complete();
    expect(await first, isTrue);
    await other.close();
  });

  test(
    'reentrant disposal during apply retains original resource completion',
    () async {
      source.onApply = () => unawaited(presenter.close());
      expect(await presenter.choose(_lock, 5, epoch: presenter.epoch), isTrue);
      expect(source.target.applied[_lock], 5);
      expect(source.target.calls, contains('effect:lockMinutes'));
      expect(source.target.calls, isNot(contains('notice:lockMinutes')));
    },
  );

  test('synchronous busy observer cannot reenter original operation', () async {
    final BlocObserver previous = Bloc.observer;
    await presenter.close();
    Future<bool>? duplicate;
    bool entered = false;
    Bloc.observer = _PolicyObserver()
      ..changed =
          (
            BlocBase<dynamic> bloc,
            Change<dynamic> change,
          ) {
            if (identical(bloc, presenter) && !entered) {
              entered = true;
              duplicate = presenter.choose(_lock, 60, epoch: presenter.epoch);
            }
          };
    presenter = securityPresenter(source);
    try {
      expect(await presenter.choose(_lock, 5, epoch: presenter.epoch), isTrue);
      expect(await duplicate, isFalse);
      expect(
        source.target.calls.where((String call) => call.startsWith('put:')),
        <String>['put:lockMinutes:5'],
      );
    } finally {
      Bloc.observer = previous;
    }
  });

  test(
    'shared lane exists before a synchronous observer admits another owner',
    () async {
      final SecurityPolicyFixture next = SecurityPolicyFixture(
        store: source.target,
      );
      final SecuritySettingsPresenter other = securityPresenter(next);
      final BlocObserver previous = Bloc.observer;
      await presenter.close();
      Future<bool>? successor;
      bool entered = false;
      Bloc.observer = _PolicyObserver()
        ..changed =
            (
              BlocBase<dynamic> bloc,
              Change<dynamic> change,
            ) {
              if (identical(bloc, presenter) && !entered) {
                entered = true;
                successor = other.choose(_lock, 60, epoch: other.epoch);
              }
            };
      presenter = securityPresenter(source);
      try {
        expect(
          await presenter.choose(_lock, 5, epoch: presenter.epoch),
          isTrue,
        );
        expect(await successor, isTrue);
        expect(
          source.target.calls.where((String call) => call.startsWith('put:')),
          <String>['put:lockMinutes:5', 'put:lockMinutes:60'],
        );
        expect(source.target.saved[_lock], 60);
      } finally {
        Bloc.observer = previous;
        await other.close();
      }
    },
  );

  test(
    'throwing change and error observers preserve actual state and stream',
    () async {
      final BlocObserver previous = Bloc.observer;
      await presenter.close();
      final List<SecuritySettingsState> delivered = <SecuritySettingsState>[];
      Bloc.observer = _PolicyObserver()
        ..throwError = true
        ..changed = (BlocBase<dynamic> _, Change<dynamic> _) {
          throw StateError('synthetic change observer');
        };
      presenter = securityPresenter(source);
      final StreamSubscription<SecuritySettingsState> subscription = presenter
          .stream
          .listen(delivered.add);
      try {
        expect(
          await presenter.choose(_lock, 5, epoch: presenter.epoch),
          isTrue,
        );
        await _turn();
        expect(source.target.calls, contains('effect:lockMinutes'));
        expect(presenter.state.lockMinutes, 5);
        expect(presenter.state.busy, isFalse);
        expect(delivered.last.lockMinutes, 5);
        expect(delivered.last.busy, isFalse);
        expect(
          delivered.any((SecuritySettingsState state) => state.busy),
          isTrue,
        );
        expect(presenter.error, isNull);
        expect(presenter.observationError, isA<StateError>());
      } finally {
        Bloc.observer = previous;
        await subscription.cancel();
      }
    },
  );

  test(
    'observer failures do not replace an original failed put result',
    () async {
      source.failPut = true;
      final BlocObserver previous = Bloc.observer;
      await presenter.close();
      Bloc.observer = _PolicyObserver()
        ..throwError = true
        ..changed = (BlocBase<dynamic> _, Change<dynamic> _) {
          throw StateError('synthetic change observer');
        };
      presenter = securityPresenter(source);
      try {
        expect(
          await presenter.choose(_lock, 5, epoch: presenter.epoch),
          isFalse,
        );
        expect(presenter.error.toString(), contains('synthetic put refused'));
        expect(presenter.state.failed, isTrue);
        expect(presenter.state.lockMinutes, 15);
        expect(source.target.saved[_lock], 15);
        expect(source.target.calls, isNot(contains('effect:lockMinutes')));
      } finally {
        Bloc.observer = previous;
      }
    },
  );

  test(
    'effect and observer failures retain original persisted success',
    () async {
      source.failEffect = true;
      final BlocObserver previous = Bloc.observer;
      await presenter.close();
      Bloc.observer = _PolicyObserver()
        ..throwError = true
        ..changed = (BlocBase<dynamic> _, Change<dynamic> _) {
          throw StateError('synthetic change observer');
        };
      presenter = securityPresenter(source);
      try {
        expect(
          await presenter.choose(_lock, 5, epoch: presenter.epoch),
          isTrue,
        );
        expect(
          presenter.error.toString(),
          contains('synthetic effect refused'),
        );
        expect(presenter.state.failed, isFalse);
        expect(presenter.state.lockMinutes, 5);
        expect(source.target.saved[_lock], 5);
        expect(source.target.applied[_lock], 5);
        expect(
          source.target.calls.where(
            (String call) => call == 'effect:lockMinutes',
          ),
          hasLength(1),
        );
      } finally {
        Bloc.observer = previous;
      }
    },
  );
}
