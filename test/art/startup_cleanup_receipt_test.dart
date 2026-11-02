import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';

const String _asset = 'test/launch_film/fixtures/film.webp';

class _DeferredBundle extends CachingAssetBundle {
  final Completer<ByteData> bytes = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => bytes.future;
}

class _StageHost extends StatefulWidget {
  const _StageHost(this.session);

  final StartupStageSession session;

  @override
  State<_StageHost> createState() => _StageHostState();
}

class _StageHostState extends State<_StageHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.show(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();

  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }
}

StartupStageSession _session(_DeferredBundle bundle) => StartupStageSession(
  asset: _asset,
  bundle: bundle,
  authBuilder: (_, _) => const SizedBox.shrink(),
  onDone: () => fail('A disposed original film must not finish startup'),
);

Future<void> _show(WidgetTester tester, StartupStageSession session) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _StageHost(session),
    ),
  );
  await tester.pump();
}

Future<void> _settleDecoder(
  WidgetTester tester,
  EntryCaptureCompletion completion,
) async {
  for (
    int turn = 0;
    turn < 100 && completion.status == EntryCaptureStatus.pending;
    turn++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(completion.status, isNot(EntryCaptureStatus.pending));
}

void main() {
  testWidgets('two detach frames cannot complete a pending original decoder', (
    WidgetTester tester,
  ) async {
    final _DeferredBundle bundle = _DeferredBundle();
    final StartupStageSession session = _session(bundle);
    await _show(tester, session);
    final Object originalState = tester.state(find.byType(LaunchFilm));
    final LaunchFilmCleanup film = session.film.cleanup!;
    expect(film.owner, same(originalState));
    final Future<void> originalCleanup = session.cleanup;
    session.dispose();
    expect(session.isClosed, isTrue);
    expect(session.originalFilmCleanup, same(film));
    expect(session.detachedReceipt.status, EntryCaptureStatus.pending);
    expect(session.cleanupReceipt.status, EntryCaptureStatus.pending);
    await tester.pump();
    expect(film.stateDisposed, isTrue);
    expect(film.decoder!.status, EntryCaptureStatus.pending);
    final Future<dynamic> originalDecoder = film.decoder!.original;
    await tester.pump();
    await tester.pump();
    expect(session.detachedReceipt.succeeded, isTrue);
    expect(session.cleanupReceipt.status, EntryCaptureStatus.pending);
    expect(film.completion.status, EntryCaptureStatus.pending);
    expect(find.byType(LaunchFilm), findsNothing);
    session.dispose();
    expect(session.cleanup, same(originalCleanup));
    expect(film.decoder!.original, same(originalDecoder));
    await tester.runAsync(() async {
      bundle.bytes.complete(
        ByteData.sublistView(await File(_asset).readAsBytes()),
      );
    });
    await _settleDecoder(tester, session.cleanupReceipt);
    expect(film.decoder!.succeeded, isTrue);
    expect(film.completion.succeeded, isTrue);
    expect(session.cleanupReceipt.succeeded, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a late original decoder error remains failed after real detach',
    (
      WidgetTester tester,
    ) async {
      final _DeferredBundle bundle = _DeferredBundle();
      final StartupStageSession session = _session(bundle);
      await _show(tester, session);
      session.dispose();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final LaunchFilmCleanup film = session.originalFilmCleanup!;
      expect(session.detachedReceipt.succeeded, isTrue);
      expect(session.cleanupReceipt.status, EntryCaptureStatus.pending);
      final StateError failure = StateError(
        'Synthetic original decoder failure',
      );
      final StackTrace stack = StackTrace.current;
      bundle.bytes.completeError(failure, stack);
      await _settleDecoder(tester, session.cleanupReceipt);
      expect(film.error, same(failure));
      expect(film.stackTrace, same(stack));
      expect(film.completion.status, EntryCaptureStatus.failed);
      expect(session.cleanupReceipt.status, EntryCaptureStatus.failed);
      expect(session.cleanupReceipt.error, same(failure));
      expect(session.cleanupReceipt.stackTrace, same(stack));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a later film cannot replace the first State cleanup receipt', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      LaunchFilm(controller: controller, autoplay: false),
    );
    final LaunchFilmCleanup original = controller.cleanup!;
    expect(original.owner, same(tester.state(find.byType(LaunchFilm))));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(original.completion.succeeded, isTrue);
    await tester.pumpWidget(
      LaunchFilm(controller: controller, autoplay: false),
    );
    expect(controller.cleanup, same(original));
    expect(controller.cleanupOwnerReplaced, isTrue);
    expect(
      tester.state(find.byType(LaunchFilm)),
      isNot(same(original.owner)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
