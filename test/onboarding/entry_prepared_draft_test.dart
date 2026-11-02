import 'dart:async';
import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/access_wallet_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_file_picker.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
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
            '"nm":"Draft receipt fixture","ddd":0,"assets":[],"layers":[]}',
          ),
        ),
      );
    }
    return rootBundle.load(key);
  }
}

// Only this startup is a policy fixture. Welcome, Import, their routes,
// controllers, input callbacks and disposal Futures are the genuine widgets.
class _Startup extends StatefulWidget {
  const _Startup({required this.reserved});

  final Completer<MaterialPageRoute<void>> reserved;

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  final Object _source = Object();
  final Object _startupOwner = Object();
  final Completer<void> _detached = Completer<void>();
  final Completer<void> _cleanup = Completer<void>();
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_attached) return;
    _attached = true;
    final ModalRoute<dynamic> route = ModalRoute.of(context)!;
    final EntryStartupReceipt receipt = EntryCaptureRegistry.instance
        .attachStartup(
          owner: this,
          source: _source,
          route: route,
          startupOwner: _startupOwner,
          detached: _detached.future,
          cleanup: _cleanup.future,
          current: () => mounted && route.isCurrent,
        )!
        ..beginInitialization();
    final Future<void> initialization = Future<void>.value();
    receipt
      ..initializing(initialization)
      ..retainSplashOperation(initialization);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      receipt.requestingWelcome();
      final MaterialPageRoute<void> original = MaterialPageRoute<void>(
        settings: RouteSettings(
          name: AccessWalletScreen.route,
          arguments: receipt,
        ),
        builder: (_) => const AccessWalletScreen(),
      );
      widget.reserved.complete(original);
      Navigator.of(context).pushReplacement<void, void>(original);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {
    super.dispose();
    _detached.complete();
    _cleanup.complete();
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

Future<EntryImportReceipt> _open(WidgetTester tester) async {
  tester.widget<WelcomeSurface>(find.byType(WelcomeSurface)).onSelected(
    WelcomeDestination.importWallet,
  );
  await tester.pump();
  final EntryImportReceipt receipt =
      EntryCaptureRegistry.instance.latestImport!;
  await _finishRoute(tester, receipt.route);
  expect(receipt.ready, isTrue);
  return receipt;
}

EntryImportDraftReceipt _prepare(EntryImportReceipt original) {
  expect(original.ready, isTrue);
  final EntryImportDraftReceipt? prepared = original.prepareIncompleteDraft();
  expect(prepared, isNotNull);
  return prepared!;
}

Future<void> _type(WidgetTester tester, String text) async {
  final Finder editable = find.descendant(
    of: find.byKey(const Key('import_seed_field')),
    matching: find.byType(EditableText),
  );
  final EditableTextState original = tester.state<EditableTextState>(editable)
    ..userUpdateTextEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
      SelectionChangedCause.keyboard,
    );
  await tester.pump();
  expect(tester.state<EditableTextState>(editable), same(original));
}

Future<void> _back(WidgetTester tester, EntryImportReceipt imported) async {
  tester.widget<ImportSurface>(find.byType(ImportSurface)).onBack();
  await tester.pump();
  final EntryWelcomeReceipt welcome = EntryCaptureRegistry.instance.welcome!;
  await _finishRoute(tester, welcome.route);
  await imported.navigation!.completion;
  await imported.routeCompleted.completion;
  await imported.controllerDisposed!.completion;
  expect(imported.cleaned, isTrue);
  expect(welcome.restoredAfter(imported), isTrue);
  expect(welcome.ready, isTrue);
}

void main() {
  testWidgets(
    'original incomplete input retains its transition '
    'and never adopts a replacement',
    (WidgetTester tester) async {
      final EntryCaptureRegistry registry = EntryCaptureRegistry.instance
        ..observeHarnessEntry();
      tester.view.physicalSize = const Size(1280, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.reset();
      });
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      final Completer<MaterialPageRoute<void>> welcomeRoute =
          Completer<MaterialPageRoute<void>>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.darkTheme,
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _Startup(reserved: welcomeRoute),
          builder: (BuildContext context, Widget? child) => DefaultAssetBundle(
            bundle: _EntryBundle(),
            child: child!,
          ),
        ),
      );
      final MaterialPageRoute<void> originalWelcome = await welcomeRoute.future;
      await tester.pump();
      await _finishRoute(tester, originalWelcome);
      expect(registry.startup?.ready, isTrue);
      expect(registry.welcome?.ready, isTrue);
      expect(registry.welcome!.route, same(originalWelcome));
      final Object welcomeOwner = registry.welcome!.owner;

      final EntryImportReceipt imported = await _open(tester);
      final Object originalSource = imported.source!;
      final Object originalController = imported.controllerOwner!;
      final EntryImportDraftReceipt draft = _prepare(imported);
      expect(draft.awaitingInput, isTrue);
      expect(draft.isCurrent, isFalse);
      expect(draft.canRestore, isTrue);
      await _type(tester, EntryImportDraftReceipt.sample);
      final ImportSurface view = tester.widget<ImportSurface>(
        find.byType(ImportSurface),
      );
      expect(draft.isCurrent, isTrue);
      expect(draft.canRestore, isTrue);
      expect(draft.awaitingInput, isFalse);
      expect(draft.sourceBefore, same(originalSource));
      expect(draft.sourceAfter, isNot(same(originalSource)));
      expect(imported.source, same(originalSource));
      expect(imported.controllerOwner, same(originalController));
      expect(imported.isCurrent, isFalse);
      expect(imported.empty, isFalse);
      expect(imported.ready, isFalse);
      expect(view.draft.words, hasLength(8));
      expect(view.draft.expectedWords, 12);
      expect(view.draft.valid, isFalse);
      expect(view.onContinue, isNull);
      final RenderEditable seed = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('import_seed_field')),
          matching: find.byType(EditableText),
        ),
      ).renderEditable;
      expect(seed.text!.style!.fontFamily, kSansFontFamily);
      expect(seed.text!.style!.letterSpacing, 0);
      final Finder counterLabel = find.text('8 of 12');
      expect(
        tester.getBottomLeft(counterLabel).dy,
        closeTo(
          tester.getBottomLeft(
            find.byKey(const Key('import_seed_panel')),
          ).dy - AppTokens.dark.transferFieldPadding.bottom - 1,
          0.01,
        ),
      );
      await _back(tester, imported);
      expect(draft.isCurrent, isFalse);
      expect(registry.welcome!.owner, same(welcomeOwner));
      expect(() => view.seedController.addListener(() {}), throwsFlutterError);

      final EntryImportReceipt direct = await _open(tester);
      final EntryImportDraftReceipt directDraft = _prepare(direct);
      tester
          .widget<ImportSurface>(find.byType(ImportSurface))
          .seedController
          .text = EntryImportDraftReceipt.sample;
      await tester.pump();
      expect(directDraft.sourceAfter, isNull);
      expect(directDraft.isCurrent, isFalse);
      expect(directDraft.canRestore, isFalse);
      expect(direct.empty, isFalse);
      await _back(tester, direct);

      final EntryImportReceipt wrong = await _open(tester);
      final EntryImportDraftReceipt wrongDraft = _prepare(wrong);
      await _type(tester, 'Synthetic unrelated incomplete input');
      expect(wrongDraft.isCurrent, isFalse);
      expect(wrongDraft.sourceAfter, isNull);
      expect(wrongDraft.canRestore, isFalse);
      await _back(tester, wrong);

      final EntryImportReceipt edited = await _open(tester);
      final EntryImportDraftReceipt editedDraft = _prepare(edited);
      await _type(tester, EntryImportDraftReceipt.sample);
      expect(editedDraft.isCurrent, isTrue);
      final Object retainedAfter = editedDraft.sourceAfter!;
      await _type(tester, '${EntryImportDraftReceipt.sample} extra');
      await _type(tester, EntryImportDraftReceipt.sample);
      expect(editedDraft.sourceAfter, same(retainedAfter));
      expect(editedDraft.isCurrent, isFalse);
      expect(editedDraft.canRestore, isFalse);
      expect(edited.empty, isFalse);
      await _back(tester, edited);

      final EntryImportReceipt covered = await _open(tester);
      final EntryImportDraftReceipt coveredDraft = _prepare(covered);
      await _type(tester, EntryImportDraftReceipt.sample);
      expect(coveredDraft.isCurrent, isTrue);
      final MaterialPageRoute<void> cover = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      navigator.currentState!.push<void>(cover);
      await tester.pump();
      await _finishRoute(tester, cover);
      // No intermediate receipt read is needed to invalidate the original
      // action generation. Returning to equal text cannot recapture a lease.
      navigator.currentState!.pop<void>();
      await tester.pump();
      await _finishRoute(tester, covered.route);
      expect(coveredDraft.isCurrent, isFalse);
      expect(coveredDraft.canRestore, isFalse);
      await _back(tester, covered);

      final EntryImportReceipt beforeInput = await _open(tester);
      final EntryImportDraftReceipt beforeDraft = _prepare(beforeInput);
      final MaterialPageRoute<void> beforeCover = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      navigator.currentState!.push<void>(beforeCover);
      await tester.pump();
      await _finishRoute(tester, beforeCover);
      navigator.currentState!.pop<void>();
      await tester.pump();
      await _finishRoute(tester, beforeInput.route);
      expect(beforeInput.empty, isTrue);
      expect(beforeDraft.sourceAfter, isNull);
      expect(beforeDraft.awaitingInput, isFalse);
      expect(beforeDraft.canRestore, isFalse);
      await _back(tester, beforeInput);

      final EntryImportReceipt browsed = await _open(tester);
      final EntryImportDraftReceipt browseDraft = _prepare(browsed);
      await _type(tester, EntryImportDraftReceipt.sample);
      expect(browseDraft.isCurrent, isTrue);
      final ImportFilePicker picker = tester.widget<ImportFilePicker>(
        find.byType(ImportFilePicker),
      );
      int requests = 0;
      final ImportSurface browseView = picker.builder(
        tester.element(find.byType(ImportFilePicker)),
        () => requests++,
        (Widget child) => child,
      ) as ImportSurface;
      browseView.onBrowse();
      expect(requests, 1);
      expect(browsed.noPendingPickerOrProbe, isFalse);
      expect(browseDraft.isCurrent, isFalse);
      await _back(tester, browsed);

      final EntryImportReceipt count = await _open(tester);
      final EntryImportDraftReceipt countDraft = _prepare(count);
      await _type(tester, EntryImportDraftReceipt.sample);
      expect(countDraft.isCurrent, isTrue);
      tester
          .widget<ImportSurface>(find.byType(ImportSurface))
          .onWordCountChanged(24);
      await tester.pump();
      tester
          .widget<ImportSurface>(find.byType(ImportSurface))
          .onWordCountChanged(12);
      await tester.pump();
      expect(countDraft.isCurrent, isFalse);
      expect(countDraft.canRestore, isFalse);
      await _back(tester, count);

      final EntryImportReceipt late = await _open(tester);
      await _type(tester, EntryImportDraftReceipt.sample);
      expect(late.prepareIncompleteDraft(), isNull);
      expect(registry.held, isTrue);
      expect(late.source, isNotNull);
      expect(
        tester.widget<ImportSurface>(find.byType(ImportSurface)).onContinue,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
