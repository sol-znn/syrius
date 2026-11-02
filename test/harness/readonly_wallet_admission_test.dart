import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/native_window_owner.dart';
import '../../harness/app/readonly_native_mode.dart';
import '../../harness/app/readonly_wallet_admission.dart';
import '../../harness/app/readonly_wallet_binding.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  test('the exact pending frame is retained and observed once', () async {
    final Completer<void> original = Completer<void>();
    int calls = 0;
    bool finished = false;
    final Future<ReadonlyWalletAdmission> pending =
        ReadonlyWalletAdmission.seal(
      ownersCurrent: () => true,
      observeFrame: () {
        calls++;
        return original.future;
      },
    );
    unawaited(pending.then<void>((_) => finished = true));
    await Future<void>.value();
    expect(finished, isFalse);
    expect(calls, 1);
    original.complete();
    final ReadonlyWalletAdmission admission = await pending;
    expect(admission.originalFrame, same(original.future));
    admission.requireCurrent();
    expect(calls, 1);
  });

  test('missing owners refuse before any native observation', () async {
    int calls = 0;
    await expectLater(
      ReadonlyWalletAdmission.seal(
        ownersCurrent: () => false,
        observeFrame: () async {
          calls++;
        },
      ),
      throwsA(isA<ReadonlyWalletAdmissionRefused>()),
    );
    expect(calls, 0);
  });

  test('owner loss during the original frame cannot yield a receipt',
      () async {
    final Completer<void> original = Completer<void>();
    bool current = true;
    final Future<void> refused = expectLater(
      ReadonlyWalletAdmission.seal(
        ownersCurrent: () => current,
        observeFrame: () => original.future,
      ),
      throwsA(isA<ReadonlyWalletAdmissionRefused>()),
    );
    current = false;
    original.complete();
    await refused;
  });

  test('a synchronous owner loss still observes a late original failure',
      () async {
    final Completer<void> original = Completer<void>();
    bool current = true;
    await expectLater(
      ReadonlyWalletAdmission.seal(
        ownersCurrent: () => current,
        observeFrame: () {
          current = false;
          return original.future;
        },
      ),
      throwsA(isA<ReadonlyWalletAdmissionRefused>()),
    );
    original.completeError(StateError('Synthetic late native failure'));
    await Future<void>.value();
  });

  test('the original native error and stack trace remain exact', () async {
    final StateError error = StateError('Synthetic original native failure');
    final StackTrace trace = StackTrace.current;
    Object? seen;
    StackTrace? seenTrace;
    await ReadonlyWalletAdmission.seal(
      ownersCurrent: () => true,
      observeFrame: () => Future<void>.error(error, trace),
    ).then<void>(
      (_) => fail('A failed original supplies no wallet receipt'),
      onError: (Object value, StackTrace originalTrace) {
        seen = value;
        seenTrace = originalTrace;
      },
    );
    expect(seen, same(error));
    expect(seenTrace, same(trace));
  });

  test('restoring an observed lost owner never revives the session',
      () async {
    bool current = true;
    final ReadonlyWalletAdmission admission =
        await ReadonlyWalletAdmission.seal(
      ownersCurrent: () => current,
      observeFrame: () async {},
    );
    current = false;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlyWalletAdmissionRefused>()));
    current = true;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlyWalletAdmissionRefused>()));
  });

  test('caught owner-check reentry also refuses the outer observation',
      () async {
    late ReadonlyWalletAdmission admission;
    bool reenter = false;
    admission = await ReadonlyWalletAdmission.seal(
      ownersCurrent: () {
        if (reenter) {
          expect(admission.requireCurrent,
              throwsA(isA<ReadonlyWalletAdmissionRefused>()));
        }
        return true;
      },
      observeFrame: () async {},
    );
    reenter = true;
    expect(admission.requireCurrent,
        throwsA(isA<ReadonlyWalletAdmissionRefused>()));
  });

  test('the actual adapter refuses an absent wallet before native dispatch',
      () async {
    const MethodChannel channel =
        MethodChannel('readonly-wallet-absent-source-test');
    int calls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      throw StateError('No native call is admitted');
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await expectLater(
      Future<ReadonlyWalletAdmission>.sync(() => bindReadonlyNativeWallet(
        window: NativeWindowOwner(channel: channel),
        readView: () => throw StateError('No renderer is admitted'),
      )),
      throwsA(isA<ReadonlyWalletAdmissionRefused>()),
    );
    expect(calls, 0);
    expect(readonlyNativeRefusalCode(
        const ReadonlyWalletAdmissionRefused()),
        'READONLY_NATIVE_WALLET_REFUSED');
  });
}
