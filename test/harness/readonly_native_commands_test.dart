import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';

import '../../harness/app/readonly_native_commands.dart';
import '../../harness/app/readonly_sdk_admission.dart';
import '../../harness/app/readonly_wallet_admission.dart';

class _Lane {
  _Lane({Future<ReadonlyWalletAdmission> Function()? bindWallet}) {
    commands = ReadonlyNativeCommands(
      isBooted: () => booted,
      bindWallet: bindWallet,
      processId: 42,
      original: (Map<String, dynamic> command) {
        calls++;
        return action(command);
      },
    );
  }

  final Object sdk = Object();
  bool booted = false;
  bool current = true;
  bool disabled = false;
  int calls = 0;
  late final ReadonlyNativeCommands commands;
  Future<Map<String, Object?>> Function(
    Map<String, dynamic> command,
  ) action =
      (Map<String, dynamic> command) async =>
          <String, Object?>{'original': true};

  Future<ReadonlySdkAdmission> seal() => ReadonlySdkAdmission.seal(
    sdkOwner: sdk,
    ownersCurrent: () => current,
    automaticDisabled: () => disabled,
    disableAutomatic: () async {
      disabled = true;
    },
  );

  Future<void> open() async {
    commands.attach(await seal());
    booted = true;
  }

  Future<Map<String, Object?>> receipt() =>
      commands.run(<String, dynamic>{'cmd': 'readonly-state'});
}

void main() {
  test('pending startup exposes no private action or SDK receipt', () async {
    final _Lane lane = _Lane();
    final Map<String, Object?> pending =
        await lane.commands.run(<String, dynamic>{'cmd': 'ping'});
    expect(pending['booted'], isFalse);
    expect(pending['readonlyAdmission'], <String, Object>{
      'schema': 1,
      'scope': 'readonly_native_sdk_admission',
      'status': 'PENDING',
    });
    for (final String command in <String>['state', 'type', 'readonly-state']) {
      await expectLater(
        lane.commands.run(<String, dynamic>{'cmd': command}),
        throwsA(isA<ReadonlyNativeCommandRefused>()),
      );
    }
    expect(lane.calls, 0);
  });

  test('booted startup cannot attach an SDK after exposing readiness',
      () async {
    final _Lane lane = _Lane();
    final ReadonlySdkAdmission sdk = await lane.seal();
    lane.booted = true;
    expect(() => lane.commands.attach(sdk),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    lane.booted = false;
    expect(() => lane.commands.attach(sdk),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(lane.calls, 0);
  });

  test('an admitted action retains its original result and fixed scope',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    final Object original = Object();
    lane.action = (_) async => <String, Object?>{'value': original};
    final Map<String, Object?> result =
        await lane.commands.run(<String, dynamic>{'cmd': 'state'});
    expect(result['value'], same(original));
    expect(result['harnessMode'], 'readonly-native');
    expect(result['readOnly'], isTrue);
    expect(result['readonlyAdmission'], <String, Object>{
      'schema': 1,
      'scope': 'readonly_native_sdk_admission',
      'status': 'CURRENT',
      'publicationAdmissionPaused': true,
      'automaticReceiveDisabled': true,
    });
    await lane.receipt();
    expect(lane.calls, 1);
  });

  test('a second attachment permanently holds the original lane', () async {
    final _Lane lane = _Lane();
    final ReadonlySdkAdmission sdk = await lane.seal();
    lane.commands.attach(sdk);
    expect(() => lane.commands.attach(sdk),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    lane.booted = true;
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(lane.calls, 0);
  });

  test('owner replacement during an original await prevents a positive reply',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    final Completer<Map<String, Object?>> original =
        Completer<Map<String, Object?>>();
    addTearDown(() {
      if (!original.isCompleted) original.complete(<String, Object?>{});
    });
    lane.action = (_) => original.future;
    final Future<void> refused = expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'tap'}),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    lane.current = false;
    original.complete(<String, Object?>{'original': true});
    await refused;
    lane.current = true;
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(lane.calls, 1);
  });

  test('automatic enablement during an await cannot be restored into success',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    final Completer<Map<String, Object?>> original =
        Completer<Map<String, Object?>>();
    addTearDown(() {
      if (!original.isCompleted) original.complete(<String, Object?>{});
    });
    lane.action = (_) => original.future;
    final Future<void> refused = expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'wait'}),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    lane.disabled = false;
    original.complete(<String, Object?>{});
    await refused;
    lane.disabled = true;
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(lane.calls, 1);
  });

  test('an original SDK refusal stays exact and cannot yield later readiness',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    int publicationCalls = 0;
    lane.action = (_) async {
      await OriginalPublications.run<void>(lane.sdk, (_) async {
        publicationCalls++;
      });
      return <String, Object?>{};
    };
    await expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'tap'}),
      throwsA(isA<OriginalPublicationRefused>()),
    );
    expect(publicationCalls, 0);
    expect(OriginalPublications.hasRefusedAdmission(lane.sdk), isTrue);
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
  });

  test('an original UI refusal preserves its error and trace without replay',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    final StateError error = StateError('Synthetic disabled UI response');
    final StackTrace trace = StackTrace.current;
    lane.action = (_) => Future<Map<String, Object?>>.error(error, trace);
    Object? seen;
    StackTrace? seenTrace;
    await lane.commands.run(<String, dynamic>{'cmd': 'tap'}).then<void>(
      (_) => fail('An original refusal cannot supply action success'),
      onError: (Object original, StackTrace originalTrace) {
        seen = original;
        seenTrace = originalTrace;
      },
    );
    expect(seen, same(error));
    expect(seenTrace, same(trace));
    expect(lane.calls, 1);
    expect((await lane.receipt())['booted'], isTrue);
    expect(lane.calls, 1);
  });

  test('a post-error owner failure never replaces the original error',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    final StateError error = StateError('Synthetic original action failure');
    final StackTrace trace = StackTrace.current;
    lane.action = (_) {
      lane.current = false;
      return Future<Map<String, Object?>>.error(error, trace);
    };
    Object? seen;
    StackTrace? seenTrace;
    await lane.commands.run(<String, dynamic>{'cmd': 'tap'}).then<void>(
      (_) => fail('The original failure must remain a failure'),
      onError: (Object original, StackTrace originalTrace) {
        seen = original;
        seenTrace = originalTrace;
      },
    );
    expect(seen, same(error));
    expect(seenTrace, same(trace));
    lane.current = true;
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(lane.calls, 1);
  });

  test('a caught reentrant query cannot admit the outer positive response',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    lane.action = (_) async {
      await expectLater(lane.receipt(),
          throwsA(isA<ReadonlyNativeCommandRefused>()));
      return <String, Object?>{'original': true};
    };
    await expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'state'}),
      throwsA(isA<ReadonlyNativeCommandRefused>()),
    );
    expect(lane.calls, 1);
  });

  test('the original callback receives an immutable command snapshot',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    final Map<String, dynamic> command = <String, dynamic>{'cmd': 'state'};
    lane.action = (Map<String, dynamic> retained) async {
      command['cmd'] = 'lab-send';
      expect(retained['cmd'], 'state');
      expect(() => retained['cmd'] = 'seed', throwsUnsupportedError);
      return <String, Object?>{};
    };
    await lane.commands.run(command);
    expect(command['cmd'], 'lab-send');
    expect(lane.calls, 1);
  });

  test('financial and unsupported commands never reach an original callback',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    for (final String name in <String>[
      'seed', 'lab-send', 'lab-quiesce', 'lab-reopen-observe',
      'wallet-recipe', 'clipboard', 'unknown',
    ]) {
      await expectLater(
        lane.commands.run(<String, dynamic>{'cmd': name}),
        throwsA(isA<ReadonlyNativeCommandRefused>()),
      );
    }
    expect(lane.calls, 0);
    expect(OriginalPublications.hasRefusedAdmission(lane.sdk), isFalse);
    await lane.receipt();
    expect(lane.calls, 0);
  });

  test('one actual wallet observation attaches a separate finite receipt',
      () async {
    int calls = 0;
    final _Lane lane = _Lane(bindWallet: () {
      calls++;
      return ReadonlyWalletAdmission.seal(
        ownersCurrent: () => true,
        observeFrame: () async {},
      );
    });
    await lane.open();
    expect((await lane.receipt()).containsKey('readonlyWallet'), isFalse);
    final Map<String, Object?> result = await lane.commands.run(
      <String, dynamic>{'cmd': 'readonly-wallet-bind'},
    );
    expect(result['pid'], 42);
    expect(result['readonlyWallet'], <String, Object>{
      'schema': 1,
      'scope': 'readonly_native_wallet_admission',
      'status': 'CURRENT',
      'chain': 321,
      'selectedIndex': 1,
      'nativeFrameObserved': true,
    });
    expect(calls, 1);
    expect(lane.calls, 0);
    await expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'readonly-wallet-bind'}),
      throwsA(isA<ReadonlyNativeCommandRefused>()),
    );
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(calls, 1);
  });

  test('wallet loss during an original UI await permanently holds the lane',
      () async {
    bool current = true;
    final _Lane lane = _Lane(bindWallet: () => ReadonlyWalletAdmission.seal(
      ownersCurrent: () => current,
      observeFrame: () async {},
    ));
    await lane.open();
    await lane.commands.run(<String, dynamic>{'cmd': 'readonly-wallet-bind'});
    final Completer<Map<String, Object?>> original =
        Completer<Map<String, Object?>>();
    lane.action = (_) => original.future;
    final Future<void> refused = expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'tap'}),
      throwsA(isA<ReadonlyWalletAdmissionRefused>()),
    );
    current = false;
    original.complete(<String, Object?>{'acted': true});
    await refused;
    current = true;
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(lane.calls, 1);
  });

  test('failed wallet binding retains its exact original error and trace',
      () async {
    final StateError error = StateError('Synthetic opened-wallet failure');
    final StackTrace trace = StackTrace.current;
    int calls = 0;
    final _Lane lane = _Lane(bindWallet: () {
      calls++;
      return Future<ReadonlyWalletAdmission>.error(error, trace);
    });
    await lane.open();
    Object? seen;
    StackTrace? seenTrace;
    await lane.commands.run(
      <String, dynamic>{'cmd': 'readonly-wallet-bind'},
    ).then<void>(
      (_) => fail('A failed wallet cannot be bound'),
      onError: (Object value, StackTrace originalTrace) {
        seen = value;
        seenTrace = originalTrace;
      },
    );
    expect(seen, same(error));
    expect(seenTrace, same(trace));
    await expectLater(lane.receipt(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(calls, 1);
  });

  test('caught reentry while binding cannot admit the outer wallet receipt',
      () async {
    late _Lane lane;
    lane = _Lane(bindWallet: () async {
      await expectLater(lane.receipt(),
          throwsA(isA<ReadonlyNativeCommandRefused>()));
      return ReadonlyWalletAdmission.seal(
        ownersCurrent: () => true,
        observeFrame: () async {},
      );
    });
    await lane.open();
    await expectLater(
      lane.commands.run(<String, dynamic>{'cmd': 'readonly-wallet-bind'}),
      throwsA(isA<ReadonlyNativeCommandRefused>()),
    );
    expect(lane.calls, 0);
  });

  test('inspection entry uses one immutable original and keeps SDK admission',
      () async {
    final _Lane lane = _Lane();
    await lane.open();
    lane.action = (Map<String, dynamic> command) async {
      expect(command['cmd'], 'readonly-entry');
      expect(command['action'], 'observe');
      expect(() => command['cmd'] = 'wallet-recipe', throwsUnsupportedError);
      return <String, Object?>{'owner': 7};
    };
    final Map<String, Object?> result = await lane.commands.run(
      <String, dynamic>{'cmd': 'readonly-entry', 'action': 'observe'},
    );
    expect(result['owner'], 7);
    expect(result['harnessMode'], 'readonly-native');
    expect(result['booted'], isTrue);
    expect(result['pid'], 42);
    expect(lane.calls, 1);
    expect(OriginalPublications.snapshot(lane.sdk), isEmpty);
  });
}
