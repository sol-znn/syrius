import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/access_wallet_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_file_picker.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_wallet_seed_choice_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_step_route.dart';
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

Future<EntryImportReceipt> _openImport(WidgetTester tester) async {
  final WelcomeSurface welcome = tester.widget<WelcomeSurface>(
    find.byType(WelcomeSurface),
  );
  welcome.onSelected(WelcomeDestination.importWallet);
  await tester.pump();
  final EntryImportReceipt original =
      EntryCaptureRegistry.instance.latestImport!;
  await _finishRoute(tester, original.route);
  return original;
}

Future<void> _back(WidgetTester tester) async {
  tester.widget<ImportSurface>(find.byType(ImportSurface)).onBack();
  await tester.pump();
  await _finishRoute(tester, EntryCaptureRegistry.instance.welcome!.route);
}

void main() {
  test(
    'observation retains the original pending Future and exact failure',
    () async {
      final Completer<void> original = Completer<void>();
      final EntryCaptureCompletion receipt = EntryCaptureCompletion(
        original.future,
      );
      expect(receipt.original, same(original.future));
      expect(receipt.status, EntryCaptureStatus.pending);
      await Future<void>.value();
      expect(receipt.status, EntryCaptureStatus.pending);
      final StateError error = StateError(
        'Synthetic retained original failure',
      );
      final StackTrace stack = StackTrace.current;
      original.completeError(error, stack);
      await receipt.completion;
      expect(receipt.status, EntryCaptureStatus.failed);
      expect(receipt.succeeded, isFalse);
      expect(receipt.error, same(error));
      expect(receipt.stackTrace, same(stack));
      expect(receipt.original, same(original.future));
    },
  );

  test(
    'positive observation requires the original operation to finish',
    () async {
      final Completer<void> original = Completer<void>();
      final EntryCaptureCompletion receipt = EntryCaptureCompletion(
        original.future,
      );
      expect(receipt.succeeded, isFalse);
      original.complete();
      await receipt.completion;
      expect(receipt.succeeded, isTrue);
      expect(receipt.error, isNull);
    },
  );

  testWidgets(
    'genuine entry routes retain original owners, cleanup and invalid sources',
    (WidgetTester tester) async {
      final EntryCaptureRegistry registry = EntryCaptureRegistry.instance
        ..observeHarnessEntry();
      expect(registry.observingHarnessEntry, isTrue);
      expect(registry.held, isFalse);
      tester.view.physicalSize = const Size(1280, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.reset();
      });
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      final _PushObserver observer = _PushObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
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
      await _finishRoute(tester, registry.welcome!.route);
      final EntryWelcomeReceipt welcome = registry.welcome!;
      final Object welcomeOwner = tester.state(find.byType(AccessWalletScreen));
      final Object welcomeSource = tester
          .widget<WelcomeSurface>(
            find.byType(WelcomeSurface),
          )
          .source;
      expect(welcome.owner, same(welcomeOwner));
      expect(welcome.source, same(welcomeSource));
      expect(welcome.isCurrent, isTrue);
      expect(welcome.isAttached, isTrue);
      expect(welcome.startup, isNull);
      expect(
        welcome.ready,
        isFalse,
        reason: 'No genuine Splash was initialized',
      );

      final EntryImportReceipt first = await _openImport(tester);
      final ImportSurface firstView = tester.widget<ImportSurface>(
        find.byType(ImportSurface),
      );
      expect(
        first.owner,
        same(tester.state(find.byType(ImportWalletSeedChoiceScreen))),
      );
      expect(first.controllerOwner, same(firstView.seedController));
      expect(first.route, isNot(isA<OnboardingStepRoute<void>>()));
      expect(first.routeCompleted.original, same(first.route.completed));
      expect(first.navigation!.original, same(first.route.popped));
      expect(first.isCurrent, isTrue);
      expect(first.empty, isTrue);
      expect(first.noOfferedFile, isTrue);
      expect(first.noPendingPickerOrProbe, isTrue);
      expect(welcome.isAttached, isTrue);
      expect(welcome.isCurrent, isFalse);
      expect(welcome.restoredAfter(first), isFalse);
      firstView.onBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(first.navigation!.succeeded, isTrue);
      expect(first.routeCompleted.status, EntryCaptureStatus.pending);
      expect(first.controllerDisposed!.status, EntryCaptureStatus.pending);
      expect(first.cleaned, isFalse);
      expect(welcome.restoredAfter(first), isFalse);
      await _finishRoute(tester, welcome.route);
      expect(first.cleaned, isTrue);
      expect(first.isCurrent, isFalse);
      expect(welcome.restoredAfter(first), isTrue);
      expect(tester.state(find.byType(AccessWalletScreen)), same(welcomeOwner));
      expect(
        tester.widget<WelcomeSurface>(find.byType(WelcomeSurface)).source,
        same(welcomeSource),
      );
      expect(
        () => firstView.seedController.addListener(() {}),
        throwsFlutterError,
      );

      final EntryImportReceipt changed = await _openImport(tester);
      final Object originalSource = changed.source!;
      tester
          .widget<ImportSurface>(find.byType(ImportSurface))
          .onWordCountChanged(24);
      await tester.pump();
      expect(changed.isCurrent, isFalse);
      expect(changed.empty, isFalse);
      tester
          .widget<ImportSurface>(find.byType(ImportSurface))
          .onWordCountChanged(12);
      await tester.pump();
      expect(changed.source, same(originalSource));
      expect(changed.isCurrent, isFalse);
      expect(changed.empty, isFalse);
      await _back(tester);
      expect(changed.cleaned, isTrue);
      expect(welcome.restoredAfter(changed), isTrue);

      final EntryImportReceipt browsed = await _openImport(tester);
      final ImportFilePicker picker = tester.widget<ImportFilePicker>(
        find.byType(ImportFilePicker),
      );
      int requests = 0;
      final ImportSurface browseView =
          picker.builder(
                tester.element(find.byType(ImportFilePicker)),
                () {
                  expect(browsed.noPendingPickerOrProbe, isFalse);
                  requests++;
                },
                (Widget child) => child,
              )
              as ImportSurface;
      browseView.onBrowse();
      expect(requests, 1);
      expect(browsed.empty, isTrue);
      expect(browsed.noPendingPickerOrProbe, isFalse);
      await _back(tester);
      expect(browsed.cleaned, isTrue);

      final EntryImportReceipt edited = await _openImport(tester);
      final ImportSurface editedView = tester.widget<ImportSurface>(
        find.byType(ImportSurface),
      );
      editedView.seedController.text = 'Synthetic edited input';
      editedView.seedController.clear();
      expect(editedView.seedController.text, isEmpty);
      expect(edited.empty, isFalse);
      expect(edited.noOfferedFile, isTrue);
      expect(edited.noPendingPickerOrProbe, isTrue);
      await _back(tester);
      expect(edited.cleaned, isTrue);
      expect(registry.imports, <EntryImportReceipt>[
        first,
        changed,
        browsed,
        edited,
      ]);
      expect(registry.held, isFalse);

      // A replacement genuine Welcome cannot overwrite the retained original.
      final MaterialPageRoute<void> replacement = MaterialPageRoute<void>(
        builder: (_) => const AccessWalletScreen(),
      );
      navigator.currentState!.pushReplacement<void, void>(replacement);
      await tester.pump();
      await _finishRoute(tester, replacement);
      expect(registry.welcome, same(welcome));
      expect(registry.held, isTrue);
      registry.observeHarnessEntry();
      expect(registry.welcome, same(welcome));
      expect(registry.held, isTrue);
      expect(welcome.isAttached, isFalse);
      expect(welcome.disposed.succeeded, isTrue);
      expect(welcome.restoredAfter(edited), isFalse);
      expect(find.byType(AccessWalletScreen), findsOneWidget);
      observer.reset();
      tester
          .widget<WelcomeSurface>(find.byType(WelcomeSurface))
          .onSelected(
            WelcomeDestination.importWallet,
          );
      expect(observer.routes, hasLength(1));
      expect(observer.previous.single, same(replacement));
      final Route<dynamic> imported = observer.routes.single;
      expect(imported, isA<MaterialPageRoute<void>>());
      await tester.pump();
      await _finishRoute(tester, imported as ModalRoute<dynamic>);
      expect(find.byType(ImportWalletSeedChoiceScreen), findsOneWidget);
      expect(registry.latestImport, same(edited));
      expect(registry.imports, hasLength(4));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
