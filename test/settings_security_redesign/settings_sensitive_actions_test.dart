import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_actions.dart';

import 'support.dart';

void main() {
  late SeedResourceFixture original;
  late SeedResourceFixture decrypted;
  late VaultBackendFixture vault;
  late SettingsSensitiveActions actions;
  late bool visible;
  late int decrypts;

  setUp(() {
    original = SeedResourceFixture('original seed label');
    decrypted = SeedResourceFixture('decrypted seed label');
    vault = VaultBackendFixture();
    visible = true;
    decrypts = 0;
    actions = SettingsSensitiveActions(
      isCurrent: () => visible,
      isHardwareWallet: false,
      unlocked: original,
      decrypt: (String _) async {
        decrypts++;
        return decrypted;
      },
      vault: vault,
    );
  });

  test('construction does not acquire decrypt encrypt pick or write', () {
    expect(original.opened, 0);
    expect(decrypts, 0);
    expect(vault.calls, isEmpty);
  });

  test(
    'seed reveal releases only its original authenticated acquisition',
    () async {
      expect(
        await actions.revealSeed('synthetic password', isCurrent: () => true),
        <String>['decrypted', 'seed', 'label'],
      );
      expect(decrypted.opened, 1);
      expect(decrypted.closed, 1);
      expect(original.opened, 0);
      expect(original.closed, 0);
    },
  );

  test(
    'waited acquisition refuses stale result and releases original',
    () async {
      final Completer<void> gate = Completer<void>();
      decrypted.gate = gate;
      final Future<List<String>> result = actions.revealSeed(
        'password',
        isCurrent: () => true,
      );
      final Future<void> refused = expectLater(
        result,
        throwsA(isA<SecuritySettingsRefused>()),
      );
      await Future<void>.delayed(Duration.zero);
      visible = false;
      gate.complete();
      await refused;
      expect(decrypted.closed, 1);
      expect(original.closed, 0);
    },
  );

  test(
    'an acquired export seed releases its exact original resource',
    () async {
      expect(
        await actions.readExportSeed(isCurrent: () => true),
        'original seed label',
      );
      expect(original.opened, 1);
      expect(original.closed, 1);
      expect(decrypted.opened, 0);
    },
  );

  test(
    'hardware refusal precedes every secret and native dependency',
    () async {
      final SettingsSensitiveActions hardware = SettingsSensitiveActions(
        isCurrent: () => true,
        isHardwareWallet: true,
        unlocked: original,
        decrypt: (String _) async {
          decrypts++;
          return decrypted;
        },
        vault: vault,
      );
      await expectLater(
        hardware.revealSeed('password', isCurrent: () => true),
        throwsA(isA<SecuritySettingsRefused>()),
      );
      await expectLater(
        hardware.readExportSeed(isCurrent: () => true),
        throwsA(isA<SecuritySettingsRefused>()),
      );
      await expectLater(
        hardware.exportVault(
          seed: 'label',
          password: 'password',
          isCurrent: () => true,
        ),
        throwsA(isA<SecuritySettingsRefused>()),
      );
      expect(decrypts, 0);
      expect(original.opened, 0);
      expect(vault.calls, isEmpty);
    },
  );

  test('once observed stale source cannot revive after returning', () async {
    visible = false;
    expect(actions.isCurrent, isFalse);
    visible = true;
    await expectLater(
      actions.readExportSeed(isCurrent: () => true),
      throwsA(isA<SecuritySettingsRefused>()),
    );
    expect(original.opened, 0);
  });

  test('picker cancellation admits no crypto or file write', () async {
    vault.destination = null;
    expect(
      await actions.exportVault(
        seed: 'seed',
        password: 'password',
        isCurrent: () => true,
      ),
      isFalse,
    );
    expect(vault.calls, <String>['pick']);
    expect(actions.outcome, SettingsVaultOutcome.cancelled);
  });

  for (final String phase in <String>['pick', 'encrypt']) {
    test(
      'revocation during $phase refuses before the original write',
      () async {
        final Completer<void> gate = Completer<void>();
        if (phase == 'pick') {
          vault.pickGate = gate;
        } else {
          vault.encryptGate = gate;
        }
        final Future<bool> result = actions.exportVault(
          seed: 'seed',
          password: 'password',
          isCurrent: () => true,
        );
        final Future<void> refused = expectLater(
          result,
          throwsA(isA<SecuritySettingsRefused>()),
        );
        await Future<void>.delayed(Duration.zero);
        visible = false;
        gate.complete();
        await refused;
        expect(vault.calls, isNot(contains('write')));
        expect(actions.outcome, SettingsVaultOutcome.refused);
      },
    );
  }

  test('child-only revocation refuses before the original write', () async {
    bool child = true;
    final Completer<void> gate = Completer<void>();
    vault.encryptGate = gate;
    final Future<bool> result = actions.exportVault(
      seed: 'seed',
      password: 'password',
      isCurrent: () => child,
    );
    final Future<void> refused = expectLater(
      result,
      throwsA(isA<SecuritySettingsRefused>()),
    );
    await Future<void>.delayed(Duration.zero);
    child = false;
    gate.complete();
    await refused;
    expect(vault.calls, isNot(contains('write')));
  });

  test(
    'successful export uses immutable original inputs and exact order',
    () async {
      expect(
        await actions.exportVault(
          seed: 'original label',
          password: 'original password',
          isCurrent: () => true,
        ),
        isTrue,
      );
      expect(vault.seed, 'original label');
      expect(vault.password, 'original password');
      expect(vault.calls, <String>['pick', 'encrypt', 'write', 'written']);
      expect(actions.outcome, SettingsVaultOutcome.completed);
    },
  );

  test(
    'admitted original write retains completion after UI disposal',
    () async {
      final Completer<void> gate = Completer<void>();
      vault.writeGate = gate;
      final Future<bool> result = actions.exportVault(
        seed: 'seed',
        password: 'password',
        isCurrent: () => true,
      );
      await vault.writing.future;
      visible = false;
      gate.complete();
      expect(await result, isTrue);
      expect(actions.outcome, SettingsVaultOutcome.completed);
      expect(vault.calls.where((String call) => call == 'write'), hasLength(1));
    },
  );

  test('duplicate callback cannot admit a second pending export', () async {
    final Completer<void> gate = Completer<void>();
    vault.writeGate = gate;
    final Future<bool> result = actions.exportVault(
      seed: 'seed',
      password: 'password',
      isCurrent: () => true,
    );
    await vault.writing.future;
    await expectLater(
      actions.exportVault(
        seed: 'replacement',
        password: 'replacement',
        isCurrent: () => true,
      ),
      throwsA(isA<SecuritySettingsRefused>()),
    );
    gate.complete();
    expect(await result, isTrue);
    expect(vault.password, 'password');
  });

  test('uncertain original write is retained and cannot be retried', () async {
    vault.failWrite = true;
    await expectLater(
      actions.exportVault(
        seed: 'seed',
        password: 'password',
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(actions.outcome, SettingsVaultOutcome.uncertain);
    await expectLater(
      actions.exportVault(seed: 'new', password: 'new', isCurrent: () => true),
      throwsA(isA<SecuritySettingsRefused>()),
    );
    expect(vault.calls.where((String call) => call == 'write'), hasLength(1));
  });
}
