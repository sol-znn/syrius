import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_actions.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

/// One in-memory preference store, never a Hive box or application singleton.
class SecurityStoreFixture {
  /// Operations recorded at real synthetic suspension boundaries.
  final List<String> calls = <String>[];

  /// The two existing positive defaults.
  final Map<SecurityPreference, int> saved = <SecurityPreference, int>{
    SecurityPreference.lockMinutes: 15,
    SecurityPreference.wrongPasswords: 3,
  };

  /// Application effects stay separate from the saved preference.
  final Map<SecurityPreference, int> applied = <SecurityPreference, int>{
    SecurityPreference.lockMinutes: 15,
    SecurityPreference.wrongPasswords: 3,
  };
}

/// Explicit captured policy actions with finite, test-owned gates.
class SecurityPolicyFixture implements SecurityPolicySession {
  /// Sharing the same store exercises the production presenter's shared lane.
  SecurityPolicyFixture({SecurityStoreFixture? store})
    : target = store ?? SecurityStoreFixture();

  /// Identity of the original in-memory store.
  final SecurityStoreFixture target;

  /// Visible authority and resource ownership are independent.
  bool visible = true;

  /// Replacing the original store refuses publication into its replacement.
  bool owned = true;

  /// A write that has already started can finish after the surface leaves.
  Completer<void>? putGate;

  /// The original timer callback remains awaited.
  Completer<void>? effectGate;

  /// Tests observe exact admission without guessing elapsed time.
  final Completer<void> putStarted = Completer<void>();

  /// Original callback admission.
  final Completer<void> effectStarted = Completer<void>();

  /// Failure before a saved value exists.
  bool failPut = false;

  /// A callback failure does not erase a persisted, applied policy.
  bool failEffect = false;

  /// A notification failure likewise does not reverse the original commit.
  bool failNotice = false;

  /// Optional synchronous observation can close a presenter reentrantly.
  void Function()? onApply;

  @override
  Object get store => target;

  @override
  bool get isCurrent => visible && owned;

  @override
  bool get ownsStore => owned;

  @override
  Future<void> persist(SecurityPreference preference, int value) async {
    target.calls.add('put:${preference.name}:$value');
    if (!putStarted.isCompleted) {
      putStarted.complete();
    }
    await putGate?.future;
    if (failPut) {
      throw StateError('synthetic put refused');
    }
    target.saved[preference] = value;
    target.calls.add('saved:${preference.name}:$value');
  }

  @override
  void apply(SecurityPreference preference, int value) {
    if (!owned || target.saved[preference] != value) {
      throw const SecuritySettingsRefused();
    }
    target.applied[preference] = value;
    target.calls.add('apply:${preference.name}:$value');
    onApply?.call();
  }

  @override
  Future<void> effect(SecurityPreference preference) async {
    target.calls.add('effect:${preference.name}');
    if (!effectStarted.isCompleted) {
      effectStarted.complete();
    }
    await effectGate?.future;
    if (failEffect) {
      throw StateError('synthetic effect refused');
    }
  }

  @override
  Future<void> notify(SecurityPreference preference) async {
    if (!visible) {
      throw const SecuritySettingsRefused();
    }
    target.calls.add('notice:${preference.name}');
    if (failNotice) {
      throw StateError('synthetic notice refused');
    }
  }
}

/// Pure policy state with no production capture fallback.
SecuritySettingsPresenter securityPresenter(SecurityPolicyFixture source) =>
    SecuritySettingsPresenter(
      initial: const SecuritySettingsState(lockMinutes: 15, wrongPasswords: 3),
      capture: () => source,
    );

/// Synthetic acquisition; its finally releases only this original resource.
class SeedResourceFixture implements SettingsSeedResource {
  /// A label, rather than any real wallet mnemonic.
  SeedResourceFixture(this.label);

  /// A visible receipt label used by these tests only.
  final String label;

  /// Test-owned asynchronous acquisition.
  Completer<void>? gate;

  /// Number of original acquisitions admitted.
  int opened = 0;

  /// Number of original acquisitions released.
  int closed = 0;

  @override
  Future<T> access<T>(Future<T> Function(String mnemonic) read) async {
    opened++;
    try {
      await gate?.future;
      return await read(label);
    } finally {
      closed++;
    }
  }
}

/// Only in-memory values cross this backend; no picker, file or crypto opens.
class VaultBackendFixture implements SettingsVaultBackend {
  /// Ordered capture, encryption and original write observations.
  final List<String> calls = <String>[];

  /// A cancellation can be represented without inventing a file receipt.
  Object? destination = Object();

  /// Each gate is completed explicitly by the test that owns it.
  Completer<void>? pickGate;

  /// Encryption gate.
  Completer<void>? encryptGate;

  /// Original admitted write gate.
  Completer<void>? writeGate;

  /// Actual admitted write observation.
  final Completer<void> writing = Completer<void>();

  /// Throws only after an original write was admitted.
  bool failWrite = false;

  /// The original immutable input recorded before the encryption await.
  String? password;

  /// The original immutable seed label.
  String? seed;

  @override
  Future<Object?> chooseDestination() async {
    calls.add('pick');
    await pickGate?.future;
    return destination;
  }

  @override
  Future<Object> encrypt(String seed, String password) async {
    this.seed = seed;
    this.password = password;
    calls.add('encrypt');
    await encryptGate?.future;
    return 'synthetic envelope';
  }

  @override
  Future<void> write(Object destination, Object envelope) async {
    calls.add('write');
    if (!writing.isCompleted) {
      writing.complete();
    }
    await writeGate?.future;
    if (failWrite) {
      throw StateError('synthetic uncertain write');
    }
    calls.add('written');
  }
}

/// Entirely synthetic high-level source for screen presentation tests.
class SensitiveSessionFixture implements SettingsSensitiveSession {
  /// Tests may revoke the exact original source.
  bool current = true;

  /// Hardware seed denial is also tested through direct callbacks.
  bool hardware = false;

  /// Counts only admitted original secret reads.
  int reveals = 0;

  /// Counts explicit exports, not fake native or SDK work.
  int exports = 0;

  /// Retains the original submitted input for snapshot assertions.
  String? password;

  /// An explicit fake reveal result, containing no wallet seed.
  Completer<List<String>>? revealGate;

  /// A retained fake export result.
  Completer<bool>? exportGate;

  @override
  bool get isCurrent => current;

  @override
  bool get isHardwareWallet => hardware;

  @override
  Future<List<String>> revealSeed(
    String password, {
    required bool Function() isCurrent,
  }) async {
    if (!current || hardware || !isCurrent()) {
      throw const SecuritySettingsRefused();
    }
    reveals++;
    this.password = password;
    return revealGate?.future ??
        Future<List<String>>.value(List<String>.filled(24, 'synthetic'));
  }

  @override
  Future<String> readExportSeed({required bool Function() isCurrent}) async {
    if (!current || hardware || !isCurrent()) {
      throw const SecuritySettingsRefused();
    }
    return 'synthetic seed';
  }

  @override
  Future<bool> exportVault({
    required String seed,
    required String password,
    required bool Function() isCurrent,
  }) async {
    if (!current || hardware || !isCurrent()) {
      throw const SecuritySettingsRefused();
    }
    exports++;
    this.password = password;
    return exportGate?.future ?? Future<bool>.value(true);
  }
}

/// No message, file or clipboard API is reached by this fixture.
class CryptoSessionFixture implements SecurityCryptoSession {
  /// Explicit synthetic current state.
  bool current = true;

  /// All calls carry their original immutable input strings.
  final List<String> calls = <String>[];

  /// Finite result gate completed only by its owning test.
  Completer<SecuritySignature>? signGate;

  /// Finite verification gate.
  Completer<bool>? verifyGate;

  /// Finite external-input gate.
  Completer<String?>? inputGate;

  @override
  bool get isCurrent => current;

  @override
  Future<SecuritySignature> signText(String message) async {
    calls.add('text:$message');
    return signGate?.future ??
        Future<SecuritySignature>.value(
          const SecuritySignature(signature: 'signed text', publicKey: 'key'),
        );
  }

  @override
  Future<SecuritySignature> signFile(String path) async {
    calls.add('file:$path');
    return signGate?.future ??
        Future<SecuritySignature>.value(
          const SecuritySignature(signature: 'signed file', publicKey: 'key'),
        );
  }

  @override
  Future<bool> verifyText(
    String message,
    String signature,
    String publicKey,
  ) async {
    calls.add('verify:$message:$signature:$publicKey');
    return verifyGate?.future ?? Future<bool>.value(true);
  }

  @override
  Future<bool> verifyFile(
    String path,
    String signature,
    String publicKey,
  ) async {
    calls.add('verifyFile:$path:$signature:$publicKey');
    return verifyGate?.future ?? Future<bool>.value(true);
  }

  @override
  Future<String?> pickFile() async {
    calls.add('pick');
    return inputGate?.future ?? Future<String?>.value('sample.txt');
  }

  @override
  Future<String?> paste() async {
    calls.add('paste');
    return inputGate?.future ?? Future<String?>.value('pasted');
  }

  @override
  Future<void> copy(String value) async => calls.add('copy:$value');
}
