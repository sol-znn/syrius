import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' show getChainIdentifier;

import '../../harness/app/agent.dart';
import '../welcome/support.dart';

class _PendingFilm extends CachingAssetBundle {
  final Completer<ByteData> bytes = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) {
    if (key == LaunchFilm.defaultLastFrameAsset) {
      return Future<ByteData>.value(ByteData.sublistView(
        File('test/launch_film/fixtures/film_end.webp').readAsBytesSync(),
      ));
    }
    return bytes.future;
  }
}

class _StartupHost extends StatefulWidget {
  const _StartupHost(this.session);

  final StartupStageSession session;

  @override
  State<_StartupHost> createState() => _StartupHostState();
}

class _StartupHostState extends State<_StartupHost> {
  final Object _source = Object();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.show(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic> route = ModalRoute.of(context)!;
    EntryCaptureRegistry.instance.attachStartup(
      owner: this, source: _source, route: route,
      startupOwner: widget.session, detached: widget.session.detached,
      cleanup: widget.session.cleanup,
      current: () => mounted && route.isCurrent,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }
}

/// One original registered stage per test-file isolate; no owner reset exists.
class StartupKeyFixture {
  final _PendingFilm _bundle = _PendingFilm();
  int _done = 0;

  /// Drives the same recipe command that the native entry uses.
  final HarnessAgent agent = HarnessAgent.forTest()..booted = true;

  /// The actual original stage and decoder, retained for the whole case.
  late final StartupStageSession session = StartupStageSession(
    bundle: _bundle, onDone: () => _done++,
    authBuilder: (_, StartupStageSession _) => const SizedBox.shrink(),
  );

  /// Counts the original film's ordinary completion callback.
  int get done => _done;

  /// Mounts the original focus receiver with its input image still pending.
  Future<void> mount(WidgetTester tester) async {
    prepareWelcomeViewport(tester);
    final SharedPrefsService? previousPreferences = app.sharedPrefsService;
    expect(Hive.isBoxOpen(kSharedPrefsBox), isFalse);
    Hive.init('startup-key-preferences');
    final Box<dynamic> preferences = await Hive.openBox<dynamic>(
      kSharedPrefsBox,
      bytes: Uint8List(0),
    );
    addTearDown(() async {
      try {
        await preferences.close();
      } finally {
        app.sharedPrefsService = previousPreferences;
      }
    });
    await preferences.put(kChainIdKey, getChainIdentifier());
    app.sharedPrefsService = await SharedPrefsService.getInstance();
    EntryCaptureRegistry.instance.observeHarnessEntry();
    addTearDown(() async {
      releaseBytes();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
      for (int turn = 0; turn < 120 &&
          !session.cleanupReceipt.succeeded; turn++) {
        await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(session.detachedReceipt.succeeded, isTrue);
      expect(session.cleanupReceipt.succeeded, isTrue);
    });
    await tester.pumpWidget(welcomeHost(_StartupHost(session)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final Map<String, Object?> view = await observe();
    expect(view['signingPolicyReady'], isTrue);
    expect(view['savedSigningChainId'], view['signingChainId']);
  }

  /// Supplies the existing tiny fixture to the same pending decoder.
  void releaseBytes() {
    if (!_bundle.bytes.isCompleted) {
      _bundle.bytes.complete(ByteData.sublistView(
        File('test/launch_film/fixtures/film.webp').readAsBytesSync(),
      ));
    }
  }

  /// Reads only the existing finite recipe observation.
  Future<Map<String, Object?>> observe() => agent.commandForTest(
    <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
  );

  /// Emits one original Space pair through the real authenticated recipe path.
  Future<Map<String, Object?>> press() async {
    final Map<String, Object?> view = await observe();
    return agent.commandForTest(<String, dynamic>{
      'cmd': 'wallet-recipe', 'action': 'key', 'key': 'launch_skip_hint',
      'owner': view['owner'], 'revision': view['revision'],
    });
  }

  /// Waits on the original codec while ordinary frames advance.
  Future<void> finish(WidgetTester tester) async {
    releaseBytes();
    for (int frame = 0; frame < 120 && done == 0; frame++) {
      await tester.runAsync(() =>
        Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, 1);
    expect(session.film.isDone, isTrue);
  }
}
