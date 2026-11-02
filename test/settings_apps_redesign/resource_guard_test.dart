import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';

import 'support.dart';

void main() {
  test('an outer Apps proof cannot erase a nested original refusal', () async {
    final AppsFixture source = AppsFixture();
    addTearDown(source.close);
    final AppsSettingsBinding binding = source.bind();
    int proofs = 0;
    source.resourceProof = () {
      proofs++;
      source.ready = false;
      expect(binding.isCurrent, isFalse);
      source.ready = true;
      return true;
    };
    expect(binding.isCurrent, isFalse);
    expect(binding.isCurrent, isFalse);
    expect(proofs, 1);
    expect(binding.read().connections, isEmpty);
    final AppsActionOutcome outcome = await binding.setEnabled(
      enabled: false,
      visible: source.captureView(),
    );
    expect(outcome.status, AppsActionStatus.refused);
    expect(source.writes, isEmpty);
    expect(source.actions, isEmpty);
    expect(proofs, 1);
  });
}
