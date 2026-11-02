import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';

import '../../harness/app/readonly_sdk_admission.dart';

void main() {
  test('the original preference write completes before readiness',
      () async {
    final Object sdk = Object();
    final Completer<void> write = Completer<void>();
    final Completer<void> writing = Completer<void>();
    addTearDown(() {
      if (!write.isCompleted) write.complete();
    });
    bool disabled = false;
    int writes = 0;
    final Future<ReadonlySdkAdmission> pending = ReadonlySdkAdmission.seal(
      sdkOwner: sdk,
      ownersCurrent: () => true,
      automaticDisabled: () => disabled,
      disableAutomatic: () {
        writes++;
        writing.complete();
        return write.future;
      },
    );
    await writing.future;
    expect(writes, 1);
    disabled = true;
    write.complete();
    final ReadonlySdkAdmission admission = await pending;
    admission.requireCurrent();
    int calls = 0;
    expect(
      () => OriginalPublications.run<void>(sdk, (_) async {
        calls++;
      }),
      throwsA(isA<OriginalPublicationRefused>()),
    );
    expect(calls, 0);
    expect(OriginalPublications.snapshot(sdk), isEmpty);
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
  });

  test('existing originals keep their exact Future and result', () async {
    final Object sdk = Object();
    final Object accepted = Object();
    final Completer<Object> reply = Completer<Object>();
    addTearDown(() {
      if (!reply.isCompleted) reply.complete(accepted);
    });
    final Future<Object> original = OriginalPublications.run<Object>(
      sdk,
      (_) => reply.future,
    );
    int writes = 0;
    await expectLater(
      ReadonlySdkAdmission.seal(
        sdkOwner: sdk,
        ownersCurrent: () => true,
        automaticDisabled: () => true,
        disableAutomatic: () async {
          writes++;
        },
      ),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    expect(writes, 0);
    expect(OriginalPublications.snapshot(sdk).single.future, same(original));
    reply.complete(accepted);
    expect(await original, same(accepted));
    expect((await OriginalPublications.pauseAndDrain(sdk)).completed, isTrue);
  });

  test('replacement during the original preference Future refuses readiness',
      () async {
    final Object sdk = Object();
    final Completer<void> write = Completer<void>();
    final Completer<void> writing = Completer<void>();
    addTearDown(() {
      if (!write.isCompleted) write.complete();
    });
    bool current = true;
    final Future<ReadonlySdkAdmission> pending = ReadonlySdkAdmission.seal(
      sdkOwner: sdk,
      ownersCurrent: () => current,
      automaticDisabled: () => true,
      disableAutomatic: () {
        writing.complete();
        return write.future;
      },
    );
    final Future<void> refused = expectLater(
      pending,
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    await writing.future;
    current = false;
    write.complete();
    await refused;
    int calls = 0;
    expect(
      () => OriginalPublications.run<void>(sdk, (_) async {
        calls++;
      }),
      throwsA(isA<OriginalPublicationRefused>()),
    );
    expect(calls, 0);
  });

  test('an original preference failure keeps its error and trace', () async {
    final Object sdk = Object();
    final StateError error = StateError('Synthetic preference failure');
    final StackTrace trace = StackTrace.current;
    final Completer<void> write = Completer<void>();
    final Completer<void> writing = Completer<void>();
    addTearDown(() {
      if (!write.isCompleted) write.complete();
    });
    final Future<ReadonlySdkAdmission> pending = ReadonlySdkAdmission.seal(
      sdkOwner: sdk,
      ownersCurrent: () => true,
      automaticDisabled: () => true,
      disableAutomatic: () {
        writing.complete();
        return write.future;
      },
    );
    Object? observed;
    StackTrace? observedTrace;
    final Future<void> observation = pending.then<void>(
      (_) => fail('The failed preference write cannot admit a native profile'),
      onError: (Object value, StackTrace originalTrace) {
        observed = value;
        observedTrace = originalTrace;
      },
    );
    await writing.future;
    write.completeError(error, trace);
    await observation;
    expect(observed, same(error));
    expect(observedTrace, same(trace));
    expect(OriginalPublications.snapshot(sdk), isEmpty);
    int repeatedWrites = 0;
    await expectLater(
      ReadonlySdkAdmission.seal(
        sdkOwner: sdk,
        ownersCurrent: () => true,
        automaticDisabled: () => true,
        disableAutomatic: () async {
          repeatedWrites++;
        },
      ),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    expect(repeatedWrites, 0);
  });

  test('an unchanged enabled preference cannot supply readiness', () async {
    int writes = 0;
    await expectLater(
      ReadonlySdkAdmission.seal(
        sdkOwner: Object(),
        ownersCurrent: () => true,
        automaticDisabled: () => false,
        disableAutomatic: () async {
          writes++;
        },
      ),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    expect(writes, 1);
  });

  test('observed replacement stays revoked after the owner is restored',
      () async {
    bool current = true;
    final ReadonlySdkAdmission admission = await ReadonlySdkAdmission.seal(
      sdkOwner: Object(),
      ownersCurrent: () => current,
      automaticDisabled: () => true,
      disableAutomatic: () async {},
    );
    current = false;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    current = true;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
  });

  test('a throwing owner observation preserves its error and revokes admission',
      () async {
    final StateError error = StateError('Synthetic owner failure');
    bool throwing = false;
    final ReadonlySdkAdmission admission = await ReadonlySdkAdmission.seal(
      sdkOwner: Object(),
      ownersCurrent: () {
        if (throwing) throw error;
        return true;
      },
      automaticDisabled: () => true,
      disableAutomatic: () async {},
    );
    throwing = true;
    expect(admission.requireCurrent, throwsA(same(error)));
    throwing = false;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
  });

  test('a caught SDK attempt during preference writing cannot look idle',
      () async {
    final Object sdk = Object();
    int calls = 0;
    int refused = 0;
    await expectLater(
      ReadonlySdkAdmission.seal(
        sdkOwner: sdk,
        ownersCurrent: () => true,
        automaticDisabled: () => true,
        disableAutomatic: () async {
          try {
            await OriginalPublications.run<void>(sdk, (_) async {
              calls++;
            });
          } on OriginalPublicationRefused {
            refused++;
          }
        },
      ),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    expect(calls, 0);
    expect(refused, 1);
    expect(OriginalPublications.hasRefusedAdmission(sdk), isTrue);
    expect(OriginalPublications.snapshot(sdk), isEmpty);
  });

  test('a new automatic preference enablement permanently revokes readiness',
      () async {
    bool disabled = true;
    final ReadonlySdkAdmission admission = await ReadonlySdkAdmission.seal(
      sdkOwner: Object(),
      ownersCurrent: () => true,
      automaticDisabled: () => disabled,
      disableAutomatic: () async {},
    );
    disabled = false;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    disabled = true;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
  });

  test('a second seal cannot repeat the original preference write', () async {
    final Object sdk = Object();
    int writes = 0;
    final ReadonlySdkAdmission original = await ReadonlySdkAdmission.seal(
      sdkOwner: sdk,
      ownersCurrent: () => true,
      automaticDisabled: () => true,
      disableAutomatic: () async {
        writes++;
      },
    );
    await expectLater(
      ReadonlySdkAdmission.seal(
        sdkOwner: sdk,
        ownersCurrent: () => true,
        automaticDisabled: () => true,
        disableAutomatic: () async {
          writes++;
        },
      ),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    expect(writes, 1);
    original.requireCurrent();
  });
}
