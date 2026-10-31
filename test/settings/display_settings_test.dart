import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/app_theme_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/locale_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/text_scaling_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/display.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';

void main() {
  late Directory scratch;
  late RailCollapse rail;
  late BalanceVisibility balances;
  late PriceFeed prices;
  late AppThemeNotifier theme;
  late TextScalingNotifier scale;
  late LocaleNotifier language;
  late SharedPrefsService? previousPrefs;
  late int? previousChain;
  int requests = 0;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('syrius-display-');
    Hive.init(scratch.path);
    await Hive.openBox<dynamic>(kSharedPrefsBox, bytes: Uint8List(0));
    previousPrefs = app.sharedPrefsService;
    app.sharedPrefsService = await SharedPrefsService.getInstance();
    previousChain = kNodeChainId;
    kNodeChainId = 1;
    rail = RailCollapse();
    balances = BalanceVisibility();
    requests = 0;
    prices = PriceFeed(
      request: (_) async {
        requests++;
        return '{}';
      },
    );
    theme = AppThemeNotifier();
    scale = TextScalingNotifier();
    language = LocaleNotifier(AppLanguage.english);
  });

  tearDown(() async {
    rail.dispose();
    balances.dispose();
    prices.dispose();
    theme.dispose();
    scale.dispose();
    language.dispose();
    await Hive.close();
    app.sharedPrefsService = previousPrefs;
    kNodeChainId = previousChain;
    scratch.deleteSync(recursive: true);
  });

  Widget host({double textScale = 1}) => MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<AppThemeNotifier>.value(value: theme),
      ChangeNotifierProvider<TextScalingNotifier>.value(value: scale),
      ChangeNotifierProvider<LocaleNotifier>.value(value: language),
    ],
    child: Consumer2<AppThemeNotifier, LocaleNotifier>(
      builder: (_, AppThemeNotifier choice, LocaleNotifier locale, _) =>
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: choice.currentThemeMode,
            locale: locale.locale,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: DisplayWidget(
                railCollapse: rail,
                balanceVisibility: balances,
                priceFeed: prices,
              ),
            ),
          ),
    ),
  );

  Future<void> show(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(textScale: textScale));
    await tester.pumpAndSettle();
  }

  SettingsSwitch control(WidgetTester tester, String key) =>
      tester.widget<SettingsSwitch>(find.byKey(Key(key)));

  testWidgets('seven rows use shared choices without starting price requests', (
    WidgetTester tester,
  ) async {
    await show(tester);
    expect(find.byType(SettingRow), findsNWidgets(7));
    expect(find.textContaining('Confirm'), findsNothing);
    expect(control(tester, 'display_dollar_values').value, isTrue);
    expect(control(tester, 'display_hide_balances').value, isFalse);
    expect(requests, 0);
    await tester.tap(find.byKey(const Key('display_dollar_values')));
    await tester.pumpAndSettle();
    expect(prices.enabled, isFalse);
    expect(app.sharedPrefsService!.get(kDollarValuesKey), isFalse);
    await tester.tap(find.byKey(const Key('display_dollar_values')));
    await tester.pumpAndSettle();
    expect(prices.enabled, isTrue);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Display follows the rail and shared eye in both directions', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('display_menu_labels')));
    await tester.pumpAndSettle();
    expect(rail.value, isFalse);
    expect(app.sharedPrefsService!.get(kRailCollapsedKey), isFalse);
    rail.toggle();
    balances.toggle();
    await tester.pumpAndSettle();
    expect(control(tester, 'display_hide_balances').value, isTrue);
    await tester.tap(find.byKey(const Key('display_hide_balances')));
    await tester.pumpAndSettle();
    expect(balances.hidden, isFalse);
    expect(app.sharedPrefsService!.get(kBalancesHiddenKey), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('theme and size apply and save when selected', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await tester.tap(
      find.byKey(Segment.keyOf('display_theme', ThemeMode.light)),
    );
    await tester.pumpAndSettle();
    expect(theme.currentThemeMode, ThemeMode.light);
    expect(app.sharedPrefsService!.get(kThemeModeKey), 'ThemeMode.light');
    await tester.tap(
      find.byKey(Segment.keyOf('display_scale', TextScaling.large)),
    );
    await tester.pumpAndSettle();
    expect(scale.currentTextScaling, TextScaling.large);
    expect(app.sharedPrefsService!.get(kTextScalingKey), 'TextScaling.large');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explorer has no active provider on an unsupported chain', (
    WidgetTester tester,
  ) async {
    await show(tester);
    DropdownMenu<String> menu() => tester.widget<DropdownMenu<String>>(
      find.byKey(const Key('display_explorer')),
    );
    expect(menu().enabled, isTrue);
    kNodeChainId = 321;
    NodeChange.announce();
    await tester.pumpAndSettle();
    expect(menu().enabled, isFalse);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('the real language menu changes direction, light $light', (
      WidgetTester tester,
    ) async {
      theme.changeThemeMode(light ? ThemeMode.light : ThemeMode.dark);
      await show(tester);
      for (final AppLanguage next in <AppLanguage>[
        AppLanguage.arabic, AppLanguage.english,
      ]) {
        await tester.tap(find.byKey(const Key('display_language_menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(next.nativeName).last);
        await tester.pumpAndSettle();
        expect(language.currentLanguage, next);
        expect(Directionality.of(tester.element(find.byType(DisplayWidget))),
            next == AppLanguage.arabic ? TextDirection.rtl : TextDirection.ltr);
        expect(app.sharedPrefsService!.get(kLanguageKey), next.toString());
        expect(tester.takeException(), isNull);
      }
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('large Arabic controls scroll without overflow, light $light', (
      WidgetTester tester,
    ) async {
      theme.changeThemeMode(light ? ThemeMode.light : ThemeMode.dark);
      language.changeLanguage(AppLanguage.arabic);
      scale.changeTextScaling(TextScaling.huge);
      await show(tester, textScale: 2);
      expect(
        Directionality.of(tester.element(find.byType(DisplayWidget))),
        TextDirection.rtl,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('display_explorer')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
