import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/app_theme_notifier.dart';

import '../../harness/app/theme_control.dart';

void main() {
  late Directory scratch;
  late SharedPrefsService prefs;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('syrius-harness-theme-');
    Hive.init(scratch.path);
    prefs = (await SharedPrefsService.getInstance())!;
  });

  tearDown(() async {
    await Hive.close();
    scratch.deleteSync(recursive: true);
  });

  Future<HarnessThemeControl> mount(
    WidgetTester tester, {
    ThemeMode? initial = ThemeMode.dark,
    bool followNotifier = true,
    bool failSave = false,
  }) async {
    final AppThemeNotifier notifier = AppThemeNotifier()
      ..changeThemeMode(initial);
    BuildContext? themed;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppThemeNotifier>.value(
        value: notifier,
        child: Consumer<AppThemeNotifier>(
          builder: (_, AppThemeNotifier value, _) => MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: followNotifier ? value.currentThemeMode : ThemeMode.dark,
            home: Builder(
              builder: (BuildContext context) {
                themed = context;
                return const Scaffold(body: Text('Theme marker'));
              },
            ),
          ),
        ),
      ),
    );
    addTearDown(notifier.dispose);
    return HarnessThemeControl(
      context: () => themed!,
      readPreference: () => prefs.get(kThemeModeKey),
      savePreference: (Object? value) async {
        if (failSave) throw StateError('preference write refused');
        await tester.runAsync(() => prefs.put(kThemeModeKey, value));
      },
      settle: () async {
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'changes existing notifier, effective theme and real preference',
    (WidgetTester tester) async {
      final HarnessThemeControl control = await mount(tester);
      for (final String mode in <String>['light', 'dark']) {
        final Map<String, Object?> state = await control.change(mode);
        expect(state['mode'], mode);
        expect(state['brightness'], mode);
        expect(state['savedMode'], 'ThemeMode.$mode');
        await tester.runAsync(() async {
          await prefs.close();
          prefs = (await SharedPrefsService.getInstance())!;
        });
        expect(prefs.get(kThemeModeKey), 'ThemeMode.$mode');
      }
    },
  );

  testWidgets('restores original system mode and its stored preference', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.runAsync(
      () => prefs.put(kThemeModeKey, ThemeMode.system.toString()),
    );
    final HarnessThemeControl control = await mount(
      tester,
      initial: ThemeMode.system,
    );
    final Map<String, Object?> original = control.snapshot();
    await control.change('light');
    final Map<String, Object?> restored = await control.restore(original);
    expect(restored, original);
  });

  testWidgets('restores the absence/default meaning of an unset preference', (
    WidgetTester tester,
  ) async {
    final HarnessThemeControl control = await mount(tester);
    final Map<String, Object?> original = control.snapshot();
    expect(original['savedMode'], isNull);
    await control.change('light');
    expect(await control.restore(original), original);
    expect(prefs.get(kThemeModeKey), isNull);
  });

  testWidgets('a failed preference write leaves the notifier unchanged', (
    WidgetTester tester,
  ) async {
    final HarnessThemeControl control = await mount(tester, failSave: true);
    final Map<String, Object?> original = control.snapshot();
    await expectLater(control.change('light'), throwsStateError);
    expect(control.snapshot(), original);
  });

  testWidgets('rejects invalid mode and a theme the app did not render', (
    WidgetTester tester,
  ) async {
    final HarnessThemeControl control = await mount(
      tester,
      followNotifier: false,
    );
    await expectLater(control.change('system'), throwsArgumentError);
    expect(prefs.get(kThemeModeKey), isNull);
    await expectLater(control.change('light'), throwsStateError);
    expect(control.snapshot()['brightness'], 'dark');
  });
}
