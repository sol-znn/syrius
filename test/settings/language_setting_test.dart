import 'dart:io';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/notifiers.dart';
import 'package:zenon_syrius_wallet_flutter/utils/widget_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/display.dart';

const Key _menu = Key('display_language_menu');

/// The app as `main.dart` and `main_dev.dart` build it, down to the parts
/// the language goes through: the notifier started from what is saved, and
/// a `MaterialApp` given its locale, the resolution callback and the
/// generated delegates. The Display panel is its only screen.
///
/// Each call is a start of the app: a new key, so new notifiers.
Widget _app() => MultiProvider(
  key: UniqueKey(),
  providers: <ChangeNotifierProvider<ChangeNotifier>>[
    ChangeNotifierProvider<AppThemeNotifier>(create: (_) => AppThemeNotifier()),
    ChangeNotifierProvider<TextScalingNotifier>(
      create: (_) => TextScalingNotifier(),
    ),
    ChangeNotifierProvider<LocaleNotifier>(
      create: (_) => LocaleNotifier(WidgetUtils.savedLanguage()),
    ),
  ],
  child: Consumer<LocaleNotifier>(
    builder: (_, LocaleNotifier localeNotifier, _) => MaterialApp(
      theme: AppTheme.darkTheme,
      locale: localeNotifier.locale,
      localeListResolutionCallback: resolveAppLocale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: DisplayWidget()),
    ),
  ),
);

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(DisplayWidget));

Locale _locale(WidgetTester tester) => Localizations.localeOf(_context(tester));

TextDirection _direction(WidgetTester tester) =>
    Directionality.of(_context(tester));

/// What the closed menu reads.
String _shown(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(of: find.byKey(_menu), matching: find.byType(TextField)),
    )
    .controller!
    .text;

/// Opens the Language menu and picks [language] by its own name.
Future<void> _pick(WidgetTester tester, AppLanguage language) async {
  await tester.tap(find.byKey(_menu));
  await tester.pumpAndSettle();
  // The menu lays its entries out a second time, unseen, to size itself;
  // the ones on screen come last.
  await tester.tap(
    find.widgetWithText(MenuItemButton, language.nativeName).last,
  );
  await tester.pumpAndSettle();
}

/// The system's languages, most wanted first, as the OS reports them.
void _systemLocales(WidgetTester tester, List<Locale> locales) {
  tester.platformDispatcher.localesTestValue = locales;
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

/// The smallest window the wallet allows.
void _smallestWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Preferences kept in memory, for the tests that pick in the menu.
///
/// The row saves as it applies, from a frame callback, so under the test's
/// fake clock. A write to a file begun there never finishes, and closing
/// the preferences afterwards waits for it for ever.
Future<void> _preferencesInMemory() async {
  await Hive.openBox<dynamic>(kSharedPrefsBox, bytes: Uint8List(0));
  sharedPrefsService = await SharedPrefsService.getInstance();
}

/// Preferences in a file, as the wallet has them.
Future<void> _preferencesInFile() async {
  sharedPrefsService = await SharedPrefsService.getInstance();
}

/// Saves [stored] as the language, in real time, so that it reaches the file.
Future<void> _save(WidgetTester tester, String stored) =>
    tester.runAsync(() => sharedPrefsService!.put(kLanguageKey, stored));

/// Closes the preferences and opens them again from the file, which is
/// what quitting and starting the wallet does to them.
Future<void> _reopenPreferences(WidgetTester tester) => tester.runAsync(
  () async {
    await sharedPrefsService!.close();
    await sharedPrefsService!.checkIfBoxIsOpen();
  },
);

void main() {
  late Directory dir;

  // Whatever a test opens lands in a folder of its own, never in the
  // wallet's. Each group then opens the preferences in memory or in a file.
  setUp(() {
    dir = Directory.systemTemp.createTempSync('syrius_language_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('five languages, English first', () {
    expect(AppLocalizations.supportedLocales, const <Locale>[
      Locale('en'),
      Locale('ar'),
      Locale('es'),
      Locale('hi'),
      Locale('zh'),
    ]);
    expect(AppLanguage.values.map((AppLanguage l) => l.nativeName), <String>[
      'System',
      'English',
      '中文',
      'हिन्दी',
      'Español',
      'العربية',
    ]);
    expect(kDefaultAppLanguage, AppLanguage.system);
  });

  group('picking a language', () {
    setUp(_preferencesInMemory);

    testWidgets('applies it and saves it', (WidgetTester tester) async {
      _smallestWindow(tester);
      await tester.pumpWidget(_app());
      expect(_shown(tester), 'System');
      expect(_locale(tester), const Locale('en'));

      for (final AppLanguage language in <AppLanguage>[
        AppLanguage.chinese,
        AppLanguage.hindi,
        AppLanguage.spanish,
        AppLanguage.arabic,
        AppLanguage.english,
      ]) {
        await _pick(tester, language);

        expect(_locale(tester), language.locale, reason: '$language');
        expect(
          _direction(tester),
          language == AppLanguage.arabic
              ? TextDirection.rtl
              : TextDirection.ltr,
          reason: '$language',
        );
        expect(_shown(tester), language.nativeName);
        expect(sharedPrefsService!.get(kLanguageKey), language.toString());
        // The wallet's own strings load for it, English until translated.
        expect(AppLocalizations.of(_context(tester)), isNotNull);
        // The framework's strings are in the language, not English.
        expect(
          MaterialLocalizations.of(_context(tester)).cancelButtonLabel,
          language == AppLanguage.english ? 'Cancel' : isNot('Cancel'),
          reason: '$language',
        );
      }
    });

    testWidgets('Arabic lays the row out right to left', (
      WidgetTester tester,
    ) async {
      _smallestWindow(tester);
      await tester.pumpWidget(_app());
      double label() => tester.getCenter(find.text('Language')).dx;
      double menu() => tester.getCenter(find.byKey(_menu)).dx;
      expect(label(), lessThan(menu()));

      await _pick(tester, AppLanguage.arabic);
      expect(_direction(tester), TextDirection.rtl);
      expect(label(), greaterThan(menu()));
    });

    testWidgets('System goes back to the OS language', (
      WidgetTester tester,
    ) async {
      _smallestWindow(tester);
      _systemLocales(tester, const <Locale>[Locale('zh', 'TW')]);
      await tester.pumpWidget(_app());

      await _pick(tester, AppLanguage.arabic);
      expect(_locale(tester), const Locale('ar'));

      await _pick(tester, AppLanguage.system);
      expect(_locale(tester), const Locale('zh'));
      expect(_direction(tester), TextDirection.ltr);
      expect(sharedPrefsService!.get(kLanguageKey), 'AppLanguage.system');
    });

    testWidgets('the next start opens in it', (WidgetTester tester) async {
      _smallestWindow(tester);
      await tester.pumpWidget(_app());
      await _pick(tester, AppLanguage.arabic);

      // One frame of a new app, and only the notifier's start has set it.
      await tester.pumpWidget(_app());
      expect(_locale(tester), const Locale('ar'));
      expect(_direction(tester), TextDirection.rtl);
      expect(_shown(tester), 'العربية');
    });
  });

  group('System follows the OS', () {
    setUp(_preferencesInMemory);

    Future<Locale> resolved(WidgetTester tester, List<Locale> os) async {
      _systemLocales(tester, os);
      await tester.pumpWidget(_app());
      expect(_shown(tester), 'System');
      return _locale(tester);
    }

    testWidgets('zh_TW is zh', (WidgetTester tester) async {
      expect(
        await resolved(tester, const <Locale>[Locale('zh', 'TW')]),
        const Locale('zh'),
      );
    });

    testWidgets('zh_Hans_CN is zh', (WidgetTester tester) async {
      expect(
        await resolved(tester, const <Locale>[
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'CN',
          ),
        ]),
        const Locale('zh'),
      );
    });

    testWidgets('fr_FR is en', (WidgetTester tester) async {
      expect(
        await resolved(tester, const <Locale>[Locale('fr', 'FR')]),
        const Locale('en'),
      );
      expect(_direction(tester), TextDirection.ltr);
    });

    testWidgets('ar_EG is ar, right to left', (WidgetTester tester) async {
      expect(
        await resolved(tester, const <Locale>[Locale('ar', 'EG')]),
        const Locale('ar'),
      );
      expect(_direction(tester), TextDirection.rtl);
    });

    testWidgets('the first language the wallet has wins', (
      WidgetTester tester,
    ) async {
      expect(
        await resolved(tester, const <Locale>[
          Locale('fr', 'FR'),
          Locale('es', 'MX'),
          Locale('hi', 'IN'),
        ]),
        const Locale('es'),
      );
    });
  });

  group('the choice survives a restart', () {
    setUp(_preferencesInFile);

    testWidgets('the first frame is in the language read from the file', (
      WidgetTester tester,
    ) async {
      _smallestWindow(tester);
      // What the row saves when Arabic is picked (asserted above).
      await _save(tester, AppLanguage.arabic.toString());
      await _reopenPreferences(tester);
      expect(sharedPrefsService!.get(kLanguageKey), 'AppLanguage.arabic');

      await tester.pumpWidget(_app());
      expect(_locale(tester), const Locale('ar'));
      expect(_direction(tester), TextDirection.rtl);
      expect(_shown(tester), 'العربية');
    });

    testWidgets('InitUtils.initApp reads it back, as it does the theme', (
      WidgetTester tester,
    ) async {
      await _save(tester, AppLanguage.hindi.toString());
      await _reopenPreferences(tester);
      final LocaleNotifier notifier = LocaleNotifier();
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleNotifier>.value(
          value: notifier,
          child: const SizedBox.shrink(),
        ),
      );
      expect(notifier.currentLanguage, AppLanguage.system);

      WidgetUtils.setLanguage(tester.element(find.byType(SizedBox)));
      expect(notifier.currentLanguage, AppLanguage.hindi);
      expect(notifier.locale, const Locale('hi'));
    });

    testWidgets('nothing saved, or something unknown, is System', (
      WidgetTester tester,
    ) async {
      expect(WidgetUtils.savedLanguage(), AppLanguage.system);
      await _save(tester, 'AppLanguage.klingon');
      await _reopenPreferences(tester);
      expect(WidgetUtils.savedLanguage(), AppLanguage.system);

      await tester.pumpWidget(_app());
      expect(_shown(tester), 'System');
      expect(_locale(tester), const Locale('en'));
    });
  });

  // Neither entry point can be pumped here: both start the window, the tray
  // and the node. Their wiring is a few lines each, and it is those lines
  // that `_app` above stands in for.
  test('main.dart and main_dev.dart are wired alike', () {
    final RegExp whitespace = RegExp(r'\s+');
    for (final String entry in <String>['lib/main.dart', 'lib/main_dev.dart']) {
      final String source = File(
        entry,
      ).readAsStringSync().replaceAll(whitespace, '');
      for (final String line in <String>[
        'create: (_) => LocaleNotifier(WidgetUtils.savedLanguage()),',
        'Consumer2<AppThemeNotifier, LocaleNotifier>(',
        'locale: localeNotifier.locale,',
        'localeListResolutionCallback: resolveAppLocale,',
        'localizationsDelegates: appLocalizationsDelegates,',
        'supportedLocales: AppLocalizations.supportedLocales,',
      ]) {
        expect(
          source,
          contains(line.replaceAll(whitespace, '')),
          reason: entry,
        );
      }
    }
    // material_ui's delegates, not the generated list's: see
    // `appLocalizationsDelegates`.
    expect(
      appLocalizationsDelegates,
      containsAll(<LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ]),
    );
  });
}
