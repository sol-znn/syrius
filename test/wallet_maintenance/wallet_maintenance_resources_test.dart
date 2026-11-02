import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart';

void main() {
  test('a nested observed loss survives the restored outer proof', () {
    final Object original = Object();
    final List<Object?> identities = <Object?>[original];
    const List<Object?> values = <Object?>['selected.enc', 321];
    late final WalletMaintenanceResources resources;
    bool nested = false;
    bool? nestedCurrent;
    resources = WalletMaintenanceResources(
      originalIdentities: identities,
      originalValues: values,
      identities: () {
        if (!nested) {
          nested = true;
          identities[0] = Object();
          nestedCurrent = resources.isCurrent;
          identities[0] = original;
        }
        return identities;
      },
      values: () => values,
      ready: () => true,
    );
    expect(resources.isCurrent, isFalse);
    expect(nestedCurrent, isFalse);
    expect(identities.single, same(original));
    expect(resources.originalValues, values);
    expect(resources.isCurrent, isFalse);
    expect(resources.isCurrent, isFalse);
  });

  test(
    'capture copies originals rather than adopting reentrant replacements',
    () {
      final Object original = Object();
      final List<Object?> identities = <Object?>[original];
      final List<Object?> values = <Object?>['selected.enc', 321];
      final WalletMaintenanceResources resources = WalletMaintenanceResources(
        originalIdentities: identities,
        originalValues: values,
        identities: () => identities,
        values: () => values,
        ready: () => true,
      );
      expect(resources.isCurrent, isTrue);
      identities[0] = Object();
      expect(resources.isCurrent, isFalse);
      identities[0] = original;
      expect(resources.isCurrent, isFalse);
      expect(resources.originalIdentities.single, same(original));
      expect(resources.originalIdentities.clear, throwsUnsupportedError);
    },
  );

  for (final int scalar in <int>[0, 1, 2, 3]) {
    test('changed captured scalar $scalar cannot revive after return', () {
      final Object original = Object();
      final List<Object?> values = <Object?>[
        'selected.enc',
        'original-node',
        321,
        'original-api',
      ];
      final WalletMaintenanceResources resources = WalletMaintenanceResources(
        originalIdentities: <Object?>[original],
        originalValues: values,
        identities: () => <Object?>[original],
        values: () => values,
        ready: () => true,
      );
      final Object? saved = values[scalar];
      values[scalar] = 'replacement';
      expect(resources.isCurrent, isFalse);
      values[scalar] = saved;
      expect(resources.isCurrent, isFalse);
      expect(resources.originalValues[scalar], saved);
    });
  }
}
