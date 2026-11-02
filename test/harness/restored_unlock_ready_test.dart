import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_card.dart';

import '../../harness/app/agent.dart';
import '../../harness/bin/harness.dart' as cli;

// Field readiness uses the genuine LockCard and agent input path. Only the
// route/lock policy reply is a fixture; no wallet, server or files are opened.
class _UnlockInstance extends cli.Instance {
  _UnlockInstance(this.agent, this.isUnlocked) : super('synthetic-field-ready');

  final HarnessAgent agent;
  final bool Function() isUnlocked;
  final List<String> commands = <String>[];

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final String name = command['cmd']! as String;
    commands.add(name);
    if (name == 'state') {
      return <String, dynamic>{
        'ok': true,
        'tab': isUnlocked() ? 'dashboard' : 'lock',
        'walletUnlocked': isUnlocked(),
      };
    }
    try {
      return <String, dynamic>{
        ...await agent.commandForTest(Map<String, dynamic>.from(command)),
        'ok': true,
      };
    } on HarnessError {
      return <String, dynamic>{'ok': false, 'error': 'synthetic-input-refused'};
    }
  }
}

class _PendingFilmBundle extends CachingAssetBundle {
  final Completer<ByteData> bytes = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => bytes.future;
}

Widget _host(
  ValueNotifier<int> stage,
  TextEditingController password,
  VoidCallback submit,
) => MaterialApp(
  locale: const Locale('en'),
  theme: AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  home: Scaffold(
    body: DefaultAssetBundle(
      bundle: _PendingFilmBundle(),
      child: ValueListenableBuilder<int>(
        valueListenable: stage,
        builder: (_, int value, _) => value == 0
            ? const SizedBox.expand()
            : IgnorePointer(
                ignoring: value == 2,
                child: LockCard(
                  walletName: 'Qualification wallet',
                  passwordController: password,
                  onUnlock: submit,
                  busy: value == 1,
                  canUnlock: value >= 2,
                ),
              ),
      ),
    ),
  ),
);

Future<void> _settle(
  WidgetTester tester,
  EntryCaptureCompletion completion,
) async {
  for (int i = 0; i < 300 &&
      completion.status == EntryCaptureStatus.pending; i++) {
    // The original agent uses Stopwatch as well as frame/timer Futures.
    // Advance wall time and the test clock without replacing either wait.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(completion.status, isNot(EntryCaptureStatus.pending));
}

void main() {
  const MethodChannel window = MethodChannel('window_manager');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(window, (MethodCall _) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(window, null);
  });

  testWidgets('unlock waits for the actual reachable lock field before input',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ValueNotifier<int> stage = ValueNotifier<int>(0);
    final TextEditingController password = TextEditingController();
    int submissions = 0;
    final _UnlockInstance instance = _UnlockInstance(
      HarnessAgent.forTest(), () => submissions == 1,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      password.dispose();
      stage.dispose();
    });
    await tester.pumpWidget(_host(stage, password, () => submissions++));
    final EntryCaptureCompletion original = EntryCaptureCompletion(
      cli.unlock(instance, 'synthetic-private-password'),
    );
    for (final int value in <int>[0, 1, 2]) {
      stage.value = value;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(original.status, EntryCaptureStatus.pending,
          reason: 'absent, disabled and covered fields must wait');
      expect(instance.commands, <String>['state', 'wait']);
      expect(password.text, isEmpty);
      expect(submissions, 0);
    }
    stage.value = 3;
    await tester.pump();
    await _settle(tester, original);
    expect(original.status, EntryCaptureStatus.succeeded);
    expect(instance.commands, <String>[
      'state', 'wait', 'type', 'tap', 'state',
    ]);
    expect(password.text, 'synthetic-private-password');
    expect(submissions, 1);
  });

  testWidgets('ready wait refuses a covered field without changing its value',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ValueNotifier<int> stage = ValueNotifier<int>(2);
    final TextEditingController password = TextEditingController();
    int submissions = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      password.dispose();
      stage.dispose();
    });
    await tester.pumpWidget(_host(stage, password, () => submissions++));
    await tester.pump();
    final HarnessAgent agent = HarnessAgent.forTest();
    // Existing presence waits retain their meaning for a mounted field.
    await agent.commandForTest(<String, dynamic>{
      'cmd': 'wait', 'key': 'wallet_password_field', 'kind': 'field',
      'timeoutMs': 0,
    });
    final EntryCaptureCompletion refused = EntryCaptureCompletion(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'wait', 'key': 'wallet_password_field', 'kind': 'field',
        'ready': true, 'timeoutMs': 150,
      }),
    );
    await _settle(tester, refused);
    expect(refused.status, EntryCaptureStatus.failed);
    expect(refused.error, isA<HarnessError>());
    expect(password.text, isEmpty);
    expect(submissions, 0);
  });
}
