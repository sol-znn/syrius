import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_binding.dart';

void main() {
  test('original receipts reject reentrant replacement at capture', () {
    final Object originalPreferences = Object();
    final Object originalBox = Object();
    final Object replacementPreferences = Object();
    final Object replacementBox = Object();
    final WalletSettingsResources resources = WalletSettingsResources(
      originalIdentities: <Object?>[originalPreferences, originalBox],
      originalValues: <Object?>[5, 'original-endpoint'],
      identities: () => <Object?>[replacementPreferences, replacementBox],
      values: () => <Object?>[5, 'original-endpoint'],
      ready: () => true,
    );
    expect(resources.isCurrent, isFalse);
  });

  for (final int field in <int>[0, 1, 2, 3]) {
    test('independent API/client identity $field cannot be rebound', () {
      final List<Object?> current = List<Object>.generate(
        4,
        (_) => Object(),
      );
      final WalletSettingsResources resources = WalletSettingsResources(
        identities: () => current,
        values: () => <Object?>['ledger-url', 'stats-url', 321],
        ready: () => true,
      );
      expect(resources.isCurrent, isTrue);
      final Object? original = current[field];
      current[field] = Object();
      expect(resources.isCurrent, isFalse);
      current[field] = original;
      expect(resources.isCurrent, isFalse);
    });
  }

  test('URLs, ordered accounts and monotonic revision remain exact', () {
    final List<Object?> values = <Object?>[
      'fixture-path',
      'first-account',
      'second-account',
      'ledger-url',
      'stats-url',
      321,
      4,
    ];
    final WalletSettingsResources resources = WalletSettingsResources(
      identities: () => const <Object?>[],
      values: () => values,
      ready: () => true,
    );
    expect(resources.isCurrent, isTrue);
    values
      ..[1] = 'second-account'
      ..[2] = 'first-account';
    expect(resources.isCurrent, isFalse);
    values
      ..[1] = 'first-account'
      ..[2] = 'second-account';
    expect(resources.isCurrent, isFalse);
  });
}
