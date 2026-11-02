import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/access_wallet_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_wallet_seed_choice_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';

class _EntryBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.startsWith('assets/lottie/')) {
      return Future<ByteData>.value(
        ByteData.sublistView(
          utf8.encode(
            '{"v":"5.7.4","fr":30,"ip":0,"op":1,"w":16,"h":16,'
            '"nm":"Receipt fixture","ddd":0,"assets":[],"layers":[]}',
          ),
        ),
      );
    }
    return rootBundle.load(key);
  }
}

class _PushObserver extends NavigatorObserver {
  final List<Route<dynamic>> routes = <Route<dynamic>>[];
  final List<Route<dynamic>?> previous = <Route<dynamic>?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    previous.add(previousRoute);
  }

  void reset() {
    routes.clear();
    previous.clear();
  }
}

void _expectNoRetainedOwners(EntryCaptureRegistry registry) {
  expect(registry.observingHarnessEntry, isFalse);
  expect(registry.startup, isNull);
  expect(registry.welcome, isNull);
  expect(registry.imports, isEmpty);
  expect(registry.latestImport, isNull);
}

Future<void> _finishRoute(
  WidgetTester tester,
  ModalRoute<dynamic> route,
) async {
  for (int frame = 0; frame < 120 && !entryRouteReady(route); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(entryRouteReady(route), isTrue);
  await tester.pump();
}

void main() {
  testWidgets(
    'ordinary entry retains no owners and a late harness cannot adopt them',
    (WidgetTester tester) async {
      final EntryCaptureRegistry registry = EntryCaptureRegistry.instance;
      _expectNoRetainedOwners(registry);
      expect(registry.held, isFalse);
      tester.view.physicalSize = const Size(1280, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.reset();
      });
      final _PushObserver observer = _PushObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          theme: AppTheme.darkTheme,
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: AccessWalletScreen.route,
          routes: <String, WidgetBuilder>{
            AccessWalletScreen.route: (_) => const AccessWalletScreen(),
          },
          builder: (BuildContext context, Widget? child) => DefaultAssetBundle(
            bundle: _EntryBundle(),
            child: child!,
          ),
        ),
      );
      final ModalRoute<dynamic> welcome = ModalRoute.of(
        tester.element(find.byType(AccessWalletScreen)),
      )!;
      await _finishRoute(tester, welcome);
      _expectNoRetainedOwners(registry);
      expect(registry.held, isFalse);

      registry.observeHarnessEntry();
      expect(registry.held, isTrue);
      _expectNoRetainedOwners(registry);
      observer.reset();
      tester
          .widget<WelcomeSurface>(find.byType(WelcomeSurface))
          .onSelected(
            WelcomeDestination.importWallet,
          );
      expect(observer.routes, hasLength(1));
      expect(observer.previous.single, same(welcome));
      final Route<dynamic> imported = observer.routes.single;
      expect(imported, isA<MaterialPageRoute<void>>());
      await tester.pump();
      await _finishRoute(tester, imported as ModalRoute<dynamic>);
      expect(find.byType(ImportWalletSeedChoiceScreen), findsOneWidget);
      _expectNoRetainedOwners(registry);
      final ImportSurface importer = tester.widget<ImportSurface>(
        find.byType(ImportSurface),
      );
      importer.seedController.text = 'Synthetic ordinary draft';
      _expectNoRetainedOwners(registry);
      importer.onBack();
      await tester.pump();
      await _finishRoute(tester, welcome);
      expect(find.byType(AccessWalletScreen), findsOneWidget);
      expect(find.byType(ImportWalletSeedChoiceScreen), findsNothing);
      expect(
        () => importer.seedController.addListener(() {}),
        throwsFlutterError,
      );
      _expectNoRetainedOwners(registry);
      registry.observeHarnessEntry();
      expect(registry.held, isTrue);
      _expectNoRetainedOwners(registry);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
