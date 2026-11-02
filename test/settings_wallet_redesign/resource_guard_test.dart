import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';

import 'support.dart';

void main() {
  for (final String callback in <String>['identities', 'ready', 'values']) {
    test('nested $callback refusal remains latched after restoration', () {
      final Object original = Object();
      final List<String> calls = <String>[];
      bool ready = true;
      bool armed = false;
      bool nested = false;
      late final WalletSettingsResources resources;
      void reenter(String stage) {
        if (!armed || nested || callback != stage) {
          return;
        }
        nested = true;
        ready = false;
        expect(resources.isCurrent, isFalse);
        ready = true;
      }

      resources = WalletSettingsResources(
        identities: () {
          calls.add('identities');
          reenter('identities');
          return <Object?>[original];
        },
        values: () {
          calls.add('values');
          reenter('values');
          return <Object?>[321];
        },
        ready: () {
          calls.add('ready');
          reenter('ready');
          return ready;
        },
      );
      calls.clear();
      armed = true;
      expect(resources.isCurrent, isFalse);
      final List<String> expected = switch (callback) {
        'identities' => <String>[
          'identities',
          'identities',
          'ready',
          'ready',
          'values',
        ],
        'ready' => <String>[
          'identities',
          'ready',
          'identities',
          'ready',
          'values',
        ],
        _ => <String>[
          'identities',
          'ready',
          'values',
          'identities',
          'ready',
        ],
      };
      expect(calls, expected);
      expect(ready, isTrue);
      expect(resources.isCurrent, isFalse);
      expect(calls, expected);
    });
  }

  test('binding retains nested refusal without another write', () async {
    final MemoryPreferenceStore store = MemoryPreferenceStore();
    bool ready = true;
    bool nested = false;
    int proofs = 0;
    late final WalletSettingsBinding binding;
    binding = WalletSettingsBinding(
      store: store,
      ownsResources: () {
        proofs++;
        if (!nested) {
          nested = true;
          ready = false;
          expect(binding.ownsResources, isFalse);
          ready = true;
        }
        return ready;
      },
      apply:
          (
            WalletPreference _, {
            required bool value,
            required bool Function() ownsResources,
          }) async => null,
    );
    expect(binding.ownsResources, isFalse);
    expect(binding.ownsResources, isFalse);
    expect(ready, isTrue);
    expect(proofs, 2);
    final WalletPreferenceOutcome outcome = await binding.change(
      WalletPreference.clipboard,
      value: true,
      isCurrent: () => true,
    );
    expect(outcome.status, WalletPreferenceStatus.refused);
    expect(store.writes, isEmpty);
  });

  test('binding ownership forwards the original thrown proof unchanged', () {
    final Object failure = StateError('Synthetic original ownership failure');
    final WalletSettingsBinding binding = WalletSettingsBinding(
      store: MemoryPreferenceStore(),
      ownsResources: () => Error.throwWithStackTrace(
        failure,
        StackTrace.current,
      ),
      apply:
          (
            WalletPreference _, {
            required bool value,
            required bool Function() ownsResources,
          }) async => null,
    );
    expect(() => binding.ownsResources, throwsA(same(failure)));
  });
}
