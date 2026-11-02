// What the animations look like at the sizes the pages draw them, and what
// loading one costs the UI isolate, before and after.
//
// "Before" is the master in tool/lottie_masters, drawn the way the call
// sites drew it: `Lottie` with the package's defaults, loaded by the
// package's own provider. "After" is the bundled file through [AppLottie].
// Both write PNGs to a fresh test-owned temporary directory: a test can count
// pixels, but whether a coin looks like a coin is for an eye.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

const String _masters = 'tool/lottie_masters';
final String _out = Directory.systemTemp.createTempSync('syrius-lottie-').path;

/// A dark panel, lighter than the coin's rim so the rim's edge shows.
const Color _backdrop = Color(0xFF2A2A2A);

/// The frame-sequence animations and the small slot each is drawn in.
const List<(AppLottieAsset, String, double)> _cases =
    <(AppLottieAsset, String, double)>[
      (AppLottieAsset.zts, 'zts', 64),
      (AppLottieAsset.pillar, 'pillar', 104),
      (AppLottieAsset.sentinel, 'sentinel', 104),
    ];

/// The longest the calling isolate went without running a timer during
/// [work]. As in test/background_crypto.
Future<(Duration, Duration)> _timed(Future<void> Function() work) async {
  final Stopwatch clock = Stopwatch()..start();
  Duration last = Duration.zero;
  Duration longest = Duration.zero;
  final Timer timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
    final Duration now = clock.elapsed;
    if (now - last > longest) longest = now - last;
    last = now;
  });
  // Let the timer settle, so the stall is the work's and not the start's.
  await Future<void>.delayed(const Duration(milliseconds: 40));
  longest = Duration.zero;
  last = clock.elapsed;
  final Duration start = clock.elapsed;
  await work();
  final Duration end = clock.elapsed;
  if (end - last > longest) longest = end - last;
  timer.cancel();
  return (end - start, longest);
}

Future<LottieComposition> _master(String name) {
  Lottie.cache.clear();
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  return FileLottie(File('$_masters/ic_anim_$name.json')).load();
}

final GlobalKey _shot = GlobalKey();

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _shot,
      child: ColoredBox(color: _backdrop, child: child),
    ),
  ),
);

Future<ui.Image> _capture(WidgetTester tester, double dpr) async {
  final RenderRepaintBoundary boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: dpr),
  ))!;
  addTearDown(image.dispose);
  return image;
}

Future<void> _save(WidgetTester tester, ui.Image image, String path) async {
  await tester.runAsync(() async {
    final ByteData png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!;
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png.buffer.asUint8List());
  });
}

Future<Uint8List> _rgba(WidgetTester tester, ui.Image image) async =>
    (await tester.runAsync(
      () => image.toByteData(),
    ))!.buffer.asUint8List();

void _setDpr(WidgetTester tester, double dpr) {
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = Size(800 * dpr, 600 * dpr);
  addTearDown(tester.view.reset);
}

void main() {
  // The package keeps every composition it loads, frames and all, and the
  // masters are 800 MB of frames between them: left in, the later tests
  // measure the collector.
  tearDown(() {
    AppLottie.debugClear();
    Lottie.cache.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  group('renders diagnostic captures', () {
    for (final (AppLottieAsset asset, String name, double slot) in _cases) {
      for (final double dpr in <double>[1, 1.5, 2]) {
        // The last frame is where an animation that plays once rests, so it
        // is what the page shows nearly all the time. The other is mid-turn.
        for (final (String at, double progress) in <(String, double)>[
          ('end', 1),
          ('mid', 0.6),
        ]) {
          final String file = '${name}_${slot.toInt()}_${dpr}x_$at.png';

          testWidgets('before/$file', (WidgetTester tester) async {
            _setDpr(tester, dpr);
            final LottieComposition composition = (await tester.runAsync(
              () => _master(name),
            ))!;
            await tester.pumpWidget(
              _host(
                Lottie(
                  composition: composition,
                  controller: AlwaysStoppedAnimation<double>(progress),
                  width: slot,
                  height: slot,
                ),
              ),
            );
            await _save(
              tester,
              await _capture(tester, dpr),
              '$_out/before/$file',
            );
          });

          testWidgets('after/$file', (WidgetTester tester) async {
            _setDpr(tester, dpr);
            final String path = asset.path(slot, dpr);
            expect(path, endsWith('_small.json'));
            await tester.runAsync(() => AppLottie.debugLoad(path));
            await tester.pumpWidget(
              _host(
                AppLottie(
                  asset,
                  size: slot,
                  controller: AlwaysStoppedAnimation<double>(progress),
                ),
              ),
            );
            // Loaded already, so it is there on the first frame.
            expect(find.byType(Lottie), findsOneWidget);
            await _save(
              tester,
              await _capture(tester, dpr),
              '$_out/after/$file',
            );
          });
        }
      }
    }
  });

  group('the re-encoded files are the same animation', () {
    for (final (AppLottieAsset asset, String name, double slot) in _cases) {
      testWidgets('$name: timing', (WidgetTester tester) async {
        final LottieComposition master = (await tester.runAsync(
          () => _master(name),
        ))!;
        for (final String path in <String>[
          asset.path(null, 1),
          asset.path(slot, 1),
        ]) {
          final LottieComposition ours = (await tester.runAsync(
            () => AppLottie.debugLoad(path),
          ))!;
          expect(ours.frameRate, master.frameRate, reason: path);
          expect(ours.startFrame, master.startFrame, reason: path);
          expect(ours.endFrame, master.endFrame, reason: path);
          expect(ours.duration, master.duration, reason: path);
          expect(ours.images.length, master.images.length, reason: path);
          expect(
            ours.images.values.every(
              (LottieImageAsset i) => i.loadedImage != null,
            ),
            isTrue,
            reason: '$path: a frame did not decode',
          );
        }
      });

      // The full file at 400 px against the master at 400 px, both drawn
      // with mipmaps so only the files differ. The artwork must land on
      // the same pixels.
      testWidgets('$name: lands where the master did', (
        WidgetTester tester,
      ) async {
        _setDpr(tester, 1);
        const double size = 400;
        const Animation<double> at = AlwaysStoppedAnimation<double>(0.6);

        final LottieComposition master = (await tester.runAsync(
          () => _master(name),
        ))!;
        await tester.pumpWidget(
          _host(
            Lottie(
              composition: master,
              controller: at,
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
        final ui.Image before = await _capture(tester, 1);
        await _save(tester, before, '$_out/before/${name}_400_1x_mid.png');
        final Uint8List a = await _rgba(tester, before);

        final String path = asset.path(null, 1);
        expect(path, isNot(endsWith('_small.json')));
        await tester.runAsync(() => AppLottie.debugLoad(path));
        await tester.pumpWidget(
          _host(AppLottie(asset, size: size, controller: at)),
        );
        final ui.Image after = await _capture(tester, 1);
        await _save(tester, after, '$_out/after/${name}_400_1x_mid.png');
        final Uint8List b = await _rgba(tester, after);

        expect(b.length, a.length);
        int total = 0;
        int far = 0;
        for (int i = 0; i < a.length; i += 4) {
          final int d =
              (a[i] - b[i]).abs() +
              (a[i + 1] - b[i + 1]).abs() +
              (a[i + 2] - b[i + 2]).abs();
          total += d;
          if (d > 96) far += 1;
        }
        final double mean = total / (a.length / 4) / 3;
        final double farShare = far / (a.length / 4);
        // The numbers are the point of the run.
        // ignore: avoid_print
        print(
          '$name: mean difference ${mean.toStringAsFixed(2)}/255, '
          '${(farShare * 100).toStringAsFixed(2)} % of pixels far off',
        );
        // A shift of the artwork by two pixels fails both of these.
        expect(mean, lessThan(2.5));
        expect(farShare, lessThan(0.005));
      });
    }
  });

  group('loading', () {
    // Not a pass or fail on the old way: its numbers are printed beside the
    // new ones. The new way is held to the bound.
    for (final (AppLottieAsset asset, String name, double slot) in _cases) {
      testWidgets('$name: no stall, and less time', (
        WidgetTester tester,
      ) async {
        final (Duration, Duration) before = (await tester.runAsync(
          () => _timed(() => _master(name)),
        ))!;
        final (Duration, Duration) small = (await tester.runAsync(
          () => _timed(() => AppLottie.debugLoad(asset.path(slot, 1))),
        ))!;
        final (Duration, Duration) full = (await tester.runAsync(
          () => _timed(() => AppLottie.debugLoad(asset.path(null, 1))),
        ))!;
        // The numbers are the point of the run.
        // ignore: avoid_print
        print(
          '$name  ready/longest stall, ms:  '
          'before ${before.$1.inMilliseconds}/${before.$2.inMilliseconds}  '
          'small ${small.$1.inMilliseconds}/${small.$2.inMilliseconds}  '
          'full ${full.$1.inMilliseconds}/${full.$2.inMilliseconds}',
        );
        // Three frames at 60 Hz. The old way held the isolate for the
        // whole parse.
        expect(small.$2, lessThan(const Duration(milliseconds: 50)));
        expect(full.$2, lessThan(const Duration(milliseconds: 50)));
        expect(small.$1, lessThan(before.$1));
      });
    }

    for (final AppLottieAsset asset in <AppLottieAsset>[
      AppLottieAsset.eye,
      AppLottieAsset.noData,
      AppLottieAsset.map,
      AppLottieAsset.splash,
    ]) {
      testWidgets('${asset.name}: loads without a stall', (
        WidgetTester tester,
      ) async {
        final String path = asset.path(null, 1);
        // The package's way, on the same file.
        final (Duration, Duration) before = (await tester.runAsync(
          () => _timed(() => AssetLottie(path).load()),
        ))!;
        Lottie.cache.clear();
        late LottieComposition composition;
        final (Duration, Duration) took = (await tester.runAsync(
          () => _timed(() async {
            composition = await AppLottie.debugLoad(path);
          }),
        ))!;
        // The numbers are the point of the run.
        // ignore: avoid_print
        print(
          '${asset.name}  ready/longest stall, ms:  '
          'before ${before.$1.inMilliseconds}/${before.$2.inMilliseconds}  '
          'after ${took.$1.inMilliseconds}/${took.$2.inMilliseconds}',
        );
        expect(composition.duration, greaterThan(Duration.zero));
        expect(took.$2, lessThan(const Duration(milliseconds: 50)));
      });
    }
  });

  // The page's own view of it: the real widget, nothing loaded, and every
  // frame from the one that asks for the file to the ones that play it.
  // The longest of those frames is the longest the page stood still.
  group('a first visit holds no frame', () {
    for (final (AppLottieAsset asset, double? size)
        in <(AppLottieAsset, double?)>[
          (AppLottieAsset.zts, 64),
          (AppLottieAsset.pillar, 104),
          (AppLottieAsset.sentinel, 104),
          (AppLottieAsset.zts, 400),
          (AppLottieAsset.pillar, 400),
          (AppLottieAsset.sentinel, 400),
          (AppLottieAsset.eye, null),
          (AppLottieAsset.noData, 32),
          (AppLottieAsset.map, null),
          (AppLottieAsset.splash, null),
        ]) {
      testWidgets('${asset.name} at ${size ?? 'full size'}', (
        WidgetTester tester,
      ) async {
        _setDpr(tester, 1);
        final String path = asset.path(size, 1);
        expect(AppLottie.isLoaded(path), isFalse, reason: 'not a first visit');

        // The first frame a test pumps pays for the test's own start.
        await tester.pumpWidget(_host(const SizedBox(width: 8, height: 8)));

        final Stopwatch clock = Stopwatch();
        Duration longest = Duration.zero;
        String longestWas = '';
        Future<void> frame(String what, Future<void> Function() pump) async {
          clock
            ..reset()
            ..start();
          await pump();
          clock.stop();
          if (clock.elapsed > longest) {
            longest = clock.elapsed;
            longestWas = what;
          }
        }

        await frame(
          'the frame that asked',
          () => tester.pumpWidget(
            _host(
              SizedBox(
                width: size ?? 400,
                height: size ?? 300,
                child: AppLottie(asset, size: size, repeat: false),
              ),
            ),
          ),
        );
        expect(find.byType(Lottie), findsNothing);

        // The load began in the test's fake clock; its steps finish in
        // real time and each is picked up by the next frame.
        for (
          int i = 0;
          i < 1000 && find.byType(Lottie).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)),
          );
          await frame('loading, or the first frame drawn', tester.pump);
        }
        expect(find.byType(Lottie), findsOneWidget);
        for (int i = 0; i < 12; i++) {
          await frame(
            'a frame of the animation',
            () => tester.pump(const Duration(milliseconds: 33)),
          );
        }
        // The numbers are the point of the run.
        // ignore: avoid_print
        print(
          '${asset.name} at ${size ?? 'full'}: longest frame '
          '${longest.inMilliseconds} ms ($longestWas)',
        );
        // The map is 2 MB of paths, and the package builds what it draws
        // them with inside the first frame that shows it: over 100 ms
        // here, as it was before, and not something a loader can move.
        // It is on the last screen of onboarding and nowhere else.
        if (asset != AppLottieAsset.map) {
          expect(longest, lessThan(const Duration(milliseconds: 50)));
        }
        await tester.pumpWidget(const SizedBox());
      });
    }

    // What the pages meet once [AppLottie.preload] has run: the file is
    // there, so the animation is built in the frame that asks for it.
    testWidgets('nor does the first visit after the preload', (
      WidgetTester tester,
    ) async {
      _setDpr(tester, 1);
      await tester.pumpWidget(_host(const SizedBox(width: 8, height: 8)));
      await tester.runAsync(AppLottie.preload);
      for (final (AppLottieAsset asset, String _, double slot) in _cases) {
        expect(AppLottie.isLoaded(asset.path(slot, 1)), isTrue);
        Duration longest = Duration.zero;
        final Stopwatch clock = Stopwatch()..start();
        await tester.pumpWidget(
          _host(AppLottie(asset, size: slot, repeat: false)),
        );
        longest = clock.elapsed;
        expect(find.byType(Lottie), findsOneWidget);
        for (int i = 0; i < 12; i++) {
          clock.reset();
          await tester.pump(const Duration(milliseconds: 33));
          if (clock.elapsed > longest) longest = clock.elapsed;
        }
        // The numbers are the point of the run.
        // ignore: avoid_print
        print(
          '${asset.name} after preload: longest frame '
          '${longest.inMilliseconds} ms',
        );
        expect(longest, lessThan(const Duration(milliseconds: 50)));
        await tester.pumpWidget(_host(const SizedBox(width: 8, height: 8)));
      }
    });
  });

  group('AppLottie', () {
    testWidgets('holds its box while loading, then draws and calls back', (
      WidgetTester tester,
    ) async {
      _setDpr(tester, 1);
      int loaded = 0;
      await tester.pumpWidget(
        _host(
          AppLottie(
            AppLottieAsset.noData,
            size: 32,
            onLoaded: (_) => loaded += 1,
          ),
        ),
      );
      expect(find.byType(Lottie), findsNothing);
      expect(tester.getSize(find.byType(AppLottie)), const Size(32, 32));

      // The load began in the test's fake clock; its steps finish in real
      // time and are picked up by a pump.
      for (int i = 0; i < 200 && find.byType(Lottie).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(Lottie), findsOneWidget);
      expect(tester.getSize(find.byType(AppLottie)), const Size(32, 32));
      expect(loaded, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('picks the file for the size and the display', (
      WidgetTester tester,
    ) async {
      const AppLottieAsset zts = AppLottieAsset.zts;
      expect(zts.path(64, 1), 'assets/lottie/ic_anim_zts_small.json');
      expect(zts.path(64, 2), 'assets/lottie/ic_anim_zts_small.json');
      expect(zts.path(64, 3), 'assets/lottie/ic_anim_zts.json');
      expect(zts.path(400, 1), 'assets/lottie/ic_anim_zts.json');
      expect(zts.path(null, 1), 'assets/lottie/ic_anim_zts.json');
      expect(
        AppLottieAsset.pillar.path(104, 2),
        'assets/lottie/ic_anim_pillar_small.json',
      );
      expect(AppLottieAsset.eye.path(64, 1), 'assets/lottie/ic_anim_eye.json');
    });

    testWidgets('gives a big file back when the last widget goes', (
      WidgetTester tester,
    ) async {
      _setDpr(tester, 1);
      final String full = AppLottieAsset.sentinel.path(null, 1);
      final String small = AppLottieAsset.sentinel.path(104, 1);
      await tester.runAsync(() async {
        await AppLottie.preload();
        await AppLottie.debugLoad(full);
      });
      AppLottie.debugClear();
      expect(AppLottie.isLoaded(full), isFalse);

      await tester.runAsync(AppLottie.preload);
      expect(AppLottie.isLoaded(small), isTrue);

      // A widget on the full file, loaded in real time.
      await tester.pumpWidget(
        _host(const AppLottie(AppLottieAsset.sentinel, repeat: false)),
      );
      for (int i = 0; i < 400 && !AppLottie.isLoaded(full); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(AppLottie.isLoaded(full), isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(AppLottie.isLoaded(full), isFalse);
      // What the pages draw stays.
      expect(AppLottie.isLoaded(small), isTrue);
    });
  });
}
