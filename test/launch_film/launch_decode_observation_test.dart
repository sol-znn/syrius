import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';

const String _asset = 'test/launch_film/fixtures/film.webp';
const String _ending = 'test/launch_film/fixtures/film_end.webp';

class _FilmBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

class _EndingBundle extends _FilmBundle {
  final List<String> requested = <String>[];
  Completer<ByteData>? pending;
  String? replacement;

  @override
  Future<ByteData> load(String key) {
    requested.add(key);
    if (key == _ending) {
      final Completer<ByteData>? held = pending;
      if (held != null) return held.future;
      return super.load(replacement ?? key);
    }
    return super.load(key);
  }
}

Widget _host(
  LaunchFilmController controller,
  _EndingBundle bundle, {
  VoidCallback? onDone,
}) =>
    DefaultAssetBundle(
      bundle: bundle,
      child: SizedBox(
        width: 160,
        height: 90,
        child: LaunchFilm(
          asset: _asset,
          lastFrameAsset: _ending,
          controller: controller,
          onDone: onDone,
        ),
      ),
    );

Future<void> _until(WidgetTester tester, bool Function() observed) async {
  for (int frame = 0; frame < 200 && !observed(); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(observed(), isTrue);
}

void main() {
  testWidgets('decode observation never advances or replaces its codec', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _FilmBundle(),
        child: SizedBox(
          width: 160,
          height: 90,
          child: LaunchFilm(
            asset: _asset,
            autoplay: false,
            controller: controller,
          ),
        ),
      ),
    );
    final LaunchFilmCleanup original = controller.cleanup!;
    expect(controller.decodingFrameIndex, isNull);
    expect(controller.frameCount, 0);
    controller.play();
    expect(controller.decodingFrameIndex, isNull);
    await _until(tester, () => controller.frame >= 0);
    final int index = controller.decodingFrameIndex!;
    expect(
      index,
      inInclusiveRange(controller.frame, controller.frameCount - 1),
    );
    for (int read = 0; read < 5; read++) {
      expect(controller.decodingFrameIndex, index);
      expect(controller.cleanup, same(original));
    }
    controller.skipToEnd();
    expect(controller.decodingFrameIndex, index);
    expect(controller.cleanup, same(original));
    await _until(tester, () => controller.isDone);
    expect(controller.frameCount, 8);
    expect(controller.decodingFrameIndex, 7);
    expect(controller.frame, 7);
    controller.play();
    expect(controller.decodingFrameIndex, isNull);
    expect(controller.cleanup, same(original));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.decodingFrameIndex, isNull);
    expect(controller.cleanup, same(original));
    await _until(tester, () => original.completion.succeeded);
    expect(original.stateDisposed, isTrue);
  });

  testWidgets('a skip reads the same ending and keeps the original owner', (
    WidgetTester tester,
  ) async {
    final _EndingBundle bundle = _EndingBundle();
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, bundle));
    final LaunchFilmCleanup original = controller.cleanup!;
    await _until(tester, () => controller.frame == 0);
    final int pendingIndex = controller.decodingFrameIndex!;
    controller.skipToEnd();
    expect(controller.decodingFrameIndex, pendingIndex);
    expect(bundle.requested, <String>[_asset]);
    await _until(tester, () => controller.isDone);
    expect(controller.frameCount, 8);
    expect(controller.frame, 7);
    expect(controller.decodingFrameIndex, 7);
    expect(controller.cleanup, same(original));
    expect(bundle.requested, <String>[_asset, _ending]);
    final ui.Image image = tester
        .widget<RawImage>(find.byType(RawImage)).image!;
    final ByteData? pixels = await tester.runAsync<ByteData?>(image.toByteData);
    expect((image.width, image.height), (16, 9));
    expect(pixels!.getUint32(0), 0xFFFFFFFF);
    await tester.pumpWidget(const SizedBox.shrink());
    await _until(tester, () => original.completion.succeeded);
    expect(original.stateDisposed, isTrue);
    expect(original.error, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('natural playback ignores the ending and preserves every frame', (
    WidgetTester tester,
  ) async {
    final _EndingBundle bundle = _EndingBundle()..replacement = _asset;
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    final List<int> frames = <int>[];
    controller.addListener(() {
      if (controller.frame >= 0 &&
          (frames.isEmpty || frames.last != controller.frame)) {
        frames.add(controller.frame);
      }
    });
    await tester.pumpWidget(_host(controller, bundle));
    await _until(tester, () => controller.isDone);
    expect(frames, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(bundle.requested, <String>[_asset]);
    final LaunchFilmCleanup original = controller.cleanup!;
    await tester.pumpWidget(const SizedBox.shrink());
    await _until(tester, () => original.completion.succeeded);
    expect(tester.takeException(), isNull);
  });

  for (final bool failure in <bool>[false, true]) {
    testWidgets('a pending ending retains its ${failure ? 'error' : 'result'} '
        'after disposal', (WidgetTester tester) async {
      final Completer<ByteData> pending = Completer<ByteData>();
      final _EndingBundle bundle = _EndingBundle()..pending = pending;
      final LaunchFilmController controller = LaunchFilmController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(
        controller,
        bundle,
        onDone: () => fail('A disposed ending cannot complete startup'),
      ));
      await _until(tester, () => controller.frame == 0);
      final LaunchFilmCleanup original = controller.cleanup!;
      controller.skipToEnd();
      await _until(tester, () => bundle.requested.contains(_ending));
      expect(controller.decodeStage, LaunchFilmDecodeStage.asset);
      expect(controller.isDone, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(original.stateDisposed, isTrue);
      expect(original.decoder!.status, EntryCaptureStatus.pending);
      expect(original.completion.status, EntryCaptureStatus.pending);
      final Future<dynamic> decoder = original.decoder!.original;
      final StateError error = StateError('Synthetic ending source failure');
      final StackTrace stack = StackTrace.current;
      if (failure) {
        pending.completeError(error, stack);
      } else {
        pending.complete(ByteData.sublistView(File(_ending).readAsBytesSync()));
      }
      await _until(tester, () =>
          original.completion.status != EntryCaptureStatus.pending);
      expect(original.decoder!.original, same(decoder));
      expect(original.completion.status, failure
          ? EntryCaptureStatus.failed : EntryCaptureStatus.succeeded);
      expect(original.error, failure ? same(error) : isNull);
      if (failure) expect(original.stackTrace, same(stack));
      expect(controller.cleanup, same(original));
      expect(controller.isDone, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('animated or differently sized endings cannot qualify cleanup', (
    WidgetTester tester,
  ) async {
    for (final String replacement in <String>[
      _asset, LaunchFilm.defaultLastFrameAsset,
    ]) {
      final _EndingBundle bundle = _EndingBundle()..replacement = replacement;
      final LaunchFilmController controller = LaunchFilmController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller, bundle));
      await _until(tester, () => controller.frame == 0);
      final LaunchFilmCleanup original = controller.cleanup!;
      controller.skipToEnd();
      await _until(tester, () => controller.isDone);
      expect(tester.takeException(), isStateError);
      expect(original.error, isStateError);
      expect(controller.frame, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await _until(tester, () =>
          original.completion.status == EntryCaptureStatus.failed);
    }
  });
}
