import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Only the pure view is imported. No onboarding owner is constructed here.
WelcomeSurface welcomeFixture({
  required Object source,
  required ValueChanged<WelcomeDestination> onSelected,
}) => WelcomeSurface(
  source: source,
  onSelected: onSelected,
  wrapImportDrop: (Widget child) => child,
  globe: const SizedBox.expand(key: Key('fixture_globe')),
  background: const SizedBox.expand(key: Key('fixture_field')),
);

/// Every source, destination and artwork path stays in memory.
Widget welcomeHost(
  Widget child, {
  GlobalKey<NavigatorState>? navigatorKey,
  bool light = false,
  bool rtl = false,
  bool enabled = true,
  bool disableAnimations = false,
  double scale = 1,
  Size size = const Size(1280, 780),
}) => MaterialApp(
  navigatorKey: navigatorKey,
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TickerMode(
    enabled: enabled,
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(scale),
        disableAnimations: disableAnimations,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child,
      ),
    ),
  ),
);

/// The host has one fixed logical viewport and leaves no mounted observer.
void prepareWelcomeViewport(
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

/// The original row callback is retained to check stale-source refusal.
VoidCallback savedWelcomeAction(WidgetTester tester, String action) =>
    tester.widget<InkWell>(find.byKey(Key('welcome_$action'))).onTap!;

/// No fixture has an endless animation, platform wait or chain dependency.
Future<void> finishWelcomeEntrance(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 401));
