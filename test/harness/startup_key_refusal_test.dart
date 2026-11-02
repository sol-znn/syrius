import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

import '../../harness/app/agent.dart';
import 'startup_key_support.dart';

void main() {
  testWidgets('an early keyboard handler cannot confirm another film action',
      (WidgetTester tester) async {
    final StartupKeyFixture fixture = StartupKeyFixture();
    await fixture.mount(tester);
    await Hive.box<dynamic>(kSharedPrefsBox).put(kChainIdKey, 321);
    final Map<String, Object?> view = await fixture.observe();
    expect(view['signingPolicyReady'], isTrue);
    expect(view['signingChainId'], 1);
    expect(view['savedSigningChainId'], 321);
    for (final Map<String, Object?> command in <Map<String, Object?>>[
      <String, Object?>{'action': 'tap', 'key': 'welcome_import'},
      <String, Object?>{
        'action': 'type', 'key': 'import_seed_field', 'value': 'fixture',
      },
      <String, Object?>{'action': 'scroll', 'dy': 300},
    ]) {
      await expectLater(fixture.agent.commandForTest(<String, dynamic>{
        'cmd': 'wallet-recipe', 'owner': view['owner'],
        'revision': view['revision'], ...command,
      }), throwsA(isA<HarnessError>().having(
        (HarnessError value) => value.message,
        'pending signing policy', 'wallet-recipe-original-owner-changed',
      )));
    }
    int intercepted = 0;
    KeyEventResult foreign(KeyEvent event) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        intercepted++;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    FocusManager.instance.addEarlyKeyEventHandler(foreign);
    addTearDown(() =>
      FocusManager.instance.removeEarlyKeyEventHandler(foreign));
    await expectLater(fixture.press(), throwsA(
      isA<HarnessError>().having((HarnessError value) => value.message,
        'original effect', 'wallet-recipe-startup-key-unconfirmed'),
    ));
    expect(intercepted, greaterThanOrEqualTo(2));
    expect(fixture.session.film.skipRequested, isFalse);
    expect(fixture.done, 0);
    expect(HardwareKeyboard.instance.physicalKeysPressed,
      isNot(contains(PhysicalKeyboardKey.space)));
  });
}
