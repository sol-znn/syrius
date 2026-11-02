import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
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
import 'package:znn_sdk_dart/znn_sdk_dart.dart'
    show keyStoreWalletType, walletTypeKey;

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

// Only the open file handle is a bounded memory fixture. The production
// structural probe, DropTarget callback, Welcome/Import owners, navigation,
// controller disposal and capture refusal are the genuine implementations.
class _MemoryFile extends Fake implements File {
  _MemoryFile(this._path, this._open);

  final String _path;
  final _MemoryHandle Function() _open;

  @override
  String get path => _path;

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    expect(mode, FileMode.read);
    return _open();
  }
}

class _MemoryHandle extends Fake implements RandomAccessFile {
  _MemoryHandle(this.bytes, this.onClose);

  final Uint8List bytes;
  final VoidCallback onClose;

  @override
  int lengthSync() => bytes.length;

  @override
  Uint8List readSync(int count) {
    expect(count, 1024 * 1024 + 1);
    return bytes;
  }

  @override
  void closeSync() => onClose();
}

DropTarget _dropTarget(WidgetTester tester) => tester.widget<DropTarget>(
  find.ancestor(
    of: find.byKey(const Key('welcome_import')),
    matching: find.byType(DropTarget),
  ),
);

void main() {
  testWidgets('Welcome drop retains real import ownership and capture refusal',
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
    final Completer<MaterialPageRoute<void>> reserved =
        Completer<MaterialPageRoute<void>>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Startup(reserved: reserved),
      builder: (_, Widget? child) => DefaultAssetBundle(
        bundle: _EntryBundle(), child: child!,
      ),
    ));
    final MaterialPageRoute<void> welcomeRoute = await reserved.future;
    await tester.pump();
    await _finishRoute(tester, welcomeRoute);
    final EntryWelcomeReceipt welcome = registry.welcome!;
    expect(welcome.ready, isTrue);
    final Object owner = welcome.owner;
    final Object view = tester.element(find.byType(WelcomeSurface));
    expect(find.byType(ImportFilePicker), findsOneWidget);
    expect(find.byType(DropTarget), findsOneWidget);
    for (final String action in <String>['create', 'hardware']) {
      expect(find.ancestor(
        of: find.byKey(Key('welcome_$action')),
        matching: find.byType(DropTarget),
      ), findsNothing);
    }
    final OnDragDoneCallback stale = _dropTarget(tester).onDragDone!;
    int opens = 0;
    int closes = 0;
    const String path = 'synthetic-private-renamed-wallet.backup';
    Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(
      <String, dynamic>{
        walletTypeKey: keyStoreWalletType, 'version': 1,
        'crypto': <String, dynamic>{
          'argon2Params': <String, dynamic>{'salt': '0x01'},
          'cipherData': '0x02', 'cipherName': 'aes-256-gcm',
          'kdf': 'argon2.IDKey', 'nonce': '0x03',
        },
      },
    )));
    void offer(OnDragDoneCallback callback, {int files = 1}) {
      IOOverrides.runZoned<void>(() {
        callback(DropDoneDetails(
          files: List<DropItem>.generate(files, (_) => DropItemFile(path)),
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ));
      }, createFile: (String requested) {
        expect(requested, path);
        return _MemoryFile(requested, () {
          opens++;
          return _MemoryHandle(bytes, () => closes++);
        });
      });
    }
    final MaterialPageRoute<void> cover = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Cover fixture')),
    );
    final Future<void> covered = navigator.currentState!.push<void>(cover);
    await tester.pump();
    await _finishRoute(tester, cover);
    offer(stale);
    expect(opens, 0);
    expect(registry.latestImport, isNull);
    navigator.currentState!.pop();
    await tester.pump();
    await _finishRoute(tester, welcomeRoute);
    await covered;
    await cover.completed;
    offer(stale);
    expect(opens, 0);
    expect(registry.latestImport, isNull);
    expect(tester.element(find.byType(WelcomeSurface)), same(view));

    for (final String outcome in <String>['accepted', 'refused', 'multiple']) {
      if (outcome == 'refused') bytes = Uint8List.fromList(utf8.encode('{}'));
      final int before = opens;
      offer(_dropTarget(tester).onDragDone!,
          files: outcome == 'multiple' ? 2 : 1);
      expect(opens, before + (outcome == 'multiple' ? 0 : 1));
      expect(closes, opens);
      await tester.pump();
      final EntryImportReceipt imported = registry.latestImport!;
      await _finishRoute(tester, imported.route);
      final ImportSurface importedView = tester.widget<ImportSurface>(
        find.byType(ImportSurface),
      );
      expect(imported.noOfferedFile, isFalse);
      expect(imported.ready, isFalse);
      expect(importedView.seedController.text, isEmpty);
      expect(importedView.fileSelected, outcome == 'accepted');
      expect(importedView.fileRefused, outcome != 'accepted');
      expect(importedView.onContinue != null, outcome == 'accepted');
      expect(find.textContaining(path), findsNothing);
      // No Continue is invoked: a structural probe cannot authenticate data.
      importedView.onBack();
      await tester.pump();
      await _finishRoute(tester, welcomeRoute);
      await imported.navigation!.completion;
      await imported.routeCompleted.completion;
      await imported.controllerDisposed!.completion;
      expect(imported.cleaned, isTrue);
      expect(welcome.restoredAfter(imported), isTrue);
      expect(registry.welcome!.owner, same(owner));
      expect(tester.element(find.byType(WelcomeSurface)), same(view));
      expect(welcome.ready, isTrue);
      expect(() => importedView.seedController.addListener(() {}),
          throwsFlutterError);
    }
    expect(opens, 2);
    expect(closes, 2);
  });
}
