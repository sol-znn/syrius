import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

Widget entryHost(
  Widget child, {
  GlobalKey<NavigatorState>? navigator,
  bool light = false,
  bool rtl = false,
  double scale = 1,
  bool enabled = true,
  Size size = const Size(1280, 780),
}) => MaterialApp(
  navigatorKey: navigator,
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TickerMode(
    enabled: enabled,
    child: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child,
      ),
    ),
  ),
);

void prepareEntryViewport(
  WidgetTester tester, {
  Size size = const Size(1280, 780),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.reset();
  });
}

void disposeEntryControllers(
  WidgetTester tester,
  List<TextEditingController> controllers,
) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final TextEditingController controller in controllers) {
      controller.dispose();
    }
  });
}
