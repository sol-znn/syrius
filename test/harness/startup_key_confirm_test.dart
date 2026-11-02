import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' show getChainIdentifier;

import '../../harness/app/agent.dart' show HarnessError;
import 'startup_key_support.dart';

class _DecodeBundle extends CachingAssetBundle {
  final List<Completer<ByteData>> reads = <Completer<ByteData>>[];

  @override
  Future<ByteData> load(String key) {
    final Completer<ByteData> original = Completer<ByteData>();
    reads.add(original);
    return original.future;
  }
}

Widget _decodeHost(
  _DecodeBundle bundle,
  LaunchFilmController controller,
  VoidCallback onDone,
) => Center(child: SizedBox(width: 160, height: 90, child: LaunchFilm(
  asset: 'decode-stage-fixture', bundle: bundle,
  controller: controller, onDone: onDone,
)));

Future<void> _decodeUntil(WidgetTester tester, bool Function() ready) async {
  for (int turn = 0; turn < 120 && !ready(); turn++) {
    await tester.runAsync(() =>
      Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

void _decodeCleanup(
  WidgetTester tester,
  _DecodeBundle bundle,
  LaunchFilmController controller,
  ByteData bytes,
) {
  addTearDown(() async {
    for (final Completer<ByteData> read in bundle.reads) {
      if (!read.isCompleted) read.complete(bytes);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _decodeUntil(tester, () =>
      controller.cleanup?.completion.succeeded ?? false);
    controller.dispose();
  });
}

void main() {
  testWidgets('startup recipe acknowledges its original film skip effect',
      (WidgetTester tester) async {
    final StartupKeyFixture fixture = StartupKeyFixture();
    await fixture.mount(tester);
    expect(fixture.session.film.skipRequested, isFalse);
    expect(fixture.done, 0);
    // The original initializer restores this known chain after launch.
    // Its original Skip must neither sign nor apply the preference itself.
    final Box<dynamic> preferences = Hive.box<dynamic>(kSharedPrefsBox);
    final int originalChain = getChainIdentifier();
    expect(originalChain, 1);
    final Map<String, Object?> original = await fixture.observe();
    await preferences.put(kChainIdKey, 321);
    final Map<String, Object?> copied = await fixture.observe();
    expect(copied['owner'], original['owner']);
    expect(copied['revision'], original['revision']);
    expect(copied['hasError'], isFalse);
    expect(copied['signingPolicyReady'], isTrue);
    expect(copied['signingChainId'], originalChain);
    expect(copied['savedSigningChainId'], 321);
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'owner': (copied['owner']! as int) + 1},
      <String, Object?>{'revision': (copied['revision']! as int) + 1},
    ]) {
      await expectLater(fixture.agent.commandForTest(<String, dynamic>{
        'cmd': 'wallet-recipe', 'action': 'key', 'key': 'launch_skip_hint',
        'owner': copied['owner'], 'revision': copied['revision'], ...change,
      }), throwsA(isA<HarnessError>().having(
        (HarnessError value) => value.message,
        'stale startup owner', 'wallet-recipe-original-owner-changed',
      )));
    }
    final SharedPrefsService? originalPreferences = app.sharedPrefsService;
    try {
      app.sharedPrefsService = null;
      await expectLater(fixture.press(), throwsA(
        isA<HarnessError>().having((HarnessError value) => value.message,
          'unknown preference', 'wallet-recipe-original-owner-changed'),
      ));
    } finally {
      app.sharedPrefsService = originalPreferences;
    }
    expect(fixture.session.film.skipRequested, isFalse);
    expect(fixture.done, 0);
    expect(getChainIdentifier(), originalChain);
    expect(preferences.get(kChainIdKey), 321);
    final Map<String, Object?> reply = await fixture.press();
    expect(reply['acted'], isTrue);
    expect(getChainIdentifier(), originalChain);
    expect(preferences.get(kChainIdKey), 321);
    expect(fixture.session.film.skipRequested, isTrue);
    expect(fixture.session.film.clockTicking, isTrue);
    expect(fixture.session.film.framePending, isFalse);
    expect(fixture.done, 0);
    await fixture.finish(tester);
    expect(fixture.session.film.clockTicking, isFalse);
    expect((await fixture.observe())['startupFilmState'], 'ended');
  });

  testWidgets('decode stages observe the original asset and skip completion',
      (WidgetTester tester) async {
    final _DecodeBundle bundle = _DecodeBundle();
    final LaunchFilmController controller = LaunchFilmController();
    final ByteData bytes = ByteData.sublistView(
      File('test/launch_film/fixtures/film.webp').readAsBytesSync(),
    );
    _decodeCleanup(tester, bundle, controller, bytes);
    int done = 0;
    await tester.pumpWidget(_decodeHost(bundle, controller, () => done++));
    await tester.pump();
    expect(bundle.reads, hasLength(1));
    expect(controller.decodeStage, LaunchFilmDecodeStage.asset);
    expect(controller.isDone, isFalse);
    expect(controller.frame, -1);
    controller.skipToEnd();
    expect(controller.decodeStage, LaunchFilmDecodeStage.asset);
    expect(done, 0);
    bundle.reads.single.complete(bytes);
    await _decodeUntil(tester, () => controller.isDone &&
      controller.decodeStage == LaunchFilmDecodeStage.complete);
    expect(controller.frame, 7);
    expect(done, 1);
    expect(controller.clockTicking, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new decoder wait cannot be overwritten by its predecessor',
      (WidgetTester tester) async {
    final _DecodeBundle bundle = _DecodeBundle();
    final LaunchFilmController controller = LaunchFilmController();
    final ByteData bytes = ByteData.sublistView(
      File('test/launch_film/fixtures/film.webp').readAsBytesSync(),
    );
    _decodeCleanup(tester, bundle, controller, bytes);
    int done = 0;
    await tester.pumpWidget(_decodeHost(bundle, controller, () => done++));
    await tester.pump();
    expect(bundle.reads, hasLength(1));
    controller.play();
    expect(controller.decodeStage, LaunchFilmDecodeStage.previous);
    await tester.pump();
    expect(bundle.reads, hasLength(1));
    expect(done, 0);
    bundle.reads.first.complete(bytes);
    await _decodeUntil(tester, () => bundle.reads.length == 2);
    expect(controller.decodeStage, LaunchFilmDecodeStage.asset);
    expect(controller.frame, -1);
    bundle.reads.last.complete(bytes);
    controller.skipToEnd();
    await _decodeUntil(tester, () => controller.isDone &&
      controller.decodeStage == LaunchFilmDecodeStage.complete);
    expect(controller.frame, 7);
    expect(done, 1);
    expect(controller.cleanupOwnerReplaced, isFalse);
    expect(tester.takeException(), isNull);
  });
}
