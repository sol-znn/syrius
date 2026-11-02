import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/agent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ordinary test agent cannot invent native entry availability', () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    expect(
      await agent.commandForTest(<String, dynamic>{'cmd': 'entry-state'}),
      <String, Object?>{'available': false},
    );
  });

  for (final String command in <String>['entry-check', 'entry-capture']) {
    test('$command refuses without an original native entry owner', () async {
      final HarnessAgent agent = HarnessAgent.forTest();
      await expectLater(
        agent.commandForTest(<String, dynamic>{
          'cmd': command,
          if (command == 'entry-capture') ...<String, Object?>{
            'screen': 'welcome',
            'theme': 'dark',
          },
        }),
        throwsA(
          isA<HarnessError>().having(
            (HarnessError error) => error.message,
            'refusal',
            'native entry capture is unavailable',
          ),
        ),
      );
      expect(agent.captureFrameForTest, isNull);
    });
  }
}
