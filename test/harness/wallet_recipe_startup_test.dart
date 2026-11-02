import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';

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

class _ReceiptHost extends StatefulWidget {
  const _ReceiptHost(this.session);

  final StartupStageSession session;

  @override
  State<_ReceiptHost> createState() => _ReceiptHostState();
}

class _ReceiptHostState extends State<_ReceiptHost> {
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
      owner: this,
      source: _source,
      route: route,
      startupOwner: widget.session,
      detached: widget.session.detached,
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

void main() {
  testWidgets('only the registered startup hint shares its original receiver', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    EntryCaptureRegistry.instance.observeHarnessEntry();
    final _PendingFilm bundle = _PendingFilm();
    final ByteData bytes = ByteData.sublistView(
      File('test/launch_film/fixtures/film.webp').readAsBytesSync(),
    );
    int done = 0;
    final StartupStageSession session = StartupStageSession(
      bundle: bundle,
      onDone: () => done++,
      authBuilder: (_, StartupStageSession _) => const SizedBox.shrink(),
    );
    addTearDown(() async {
      if (!bundle.bytes.isCompleted) bundle.bytes.complete(bytes);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
    });
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    final Widget host = welcomeHost(_ReceiptHost(session));
    await tester.pumpWidget(TickerMode(enabled: true, child: host));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    Future<Map<String, Object?>> observation() => agent.commandForTest(
      <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
    );
    Future<bool> available() async {
      final Map<String, Object?> view = await observation();
      final List<Map<String, Object?>> controls =
          view['controls']! as List<Map<String, Object?>>;
      return controls.any(
        (Map<String, Object?> row) => row['key'] == 'launch_skip_hint',
      );
    }
    expect(await available(), isTrue);
    expect((await observation())['startupFilmState'], 'opening');
    final Map<String, Object?> opening = <String, Object?>{
      'frames': 0, 'shown': -1, 'decoding': null, 'stage': 'asset',
      'skip': false, 'pending': false, 'ticking': true, 'done': false,
    };
    final Object? originalFilm = session.film.cleanup?.owner;
    for (int read = 0; read < 5; read++) {
      expect((await observation())['startupFilmProgress'], opening);
      expect(session.film.cleanup?.owner, same(originalFilm));
      expect(bundle.bytes.isCompleted, isFalse);
    }
    await tester.pumpWidget(TickerMode(enabled: false, child: host));
    expect((await observation())['startupFilmState'], 'ticker-muted');
    await tester.pumpWidget(TickerMode(enabled: true, child: host));
    expect((await observation())['startupFilmState'], 'opening');
    expect(done, 0);
    final BuildContext context = tester.element(find.byType(_ReceiptHost));
    final OverlayEntry foreign = OverlayEntry(
      opaque: true,
      builder: (_) => const Focus(
        child: Center(child: Text(
          'Synthetic foreign hint',
          key: ValueKey<String>('launch_skip_hint'),
        )),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(foreign);
    await tester.pump();
    expect(await available(), isFalse);
    expect(done, 0);
    foreign
      ..remove()
      ..dispose();
    await tester.pump();
    expect(await available(), isTrue);
    final Map<String, Object?> key = await agent.commandForTest(
      <String, dynamic>{'cmd': 'key', 'key': 'space', 'settleMs': 0},
    );
    expect(key['handled'], isTrue);
    bundle.bytes.complete(bytes);
    for (int frame = 0; frame < 120 && done == 0; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, 1);
    expect(session.film.isDone, isTrue);
    expect(await available(), isFalse);
    expect((await observation())['startupFilmState'], 'ended');
    expect((await observation())['startupFilmProgress'], <String, Object?>{
      'frames': 8, 'shown': 7, 'decoding': 7, 'stage': 'complete',
      'skip': true, 'pending': false, 'ticking': false, 'done': true,
    });
    session.dispose();
    expect((await observation()).containsKey('startupFilmState'), isFalse);
    expect((await observation()).containsKey('startupFilmProgress'), isFalse);
  });
}
