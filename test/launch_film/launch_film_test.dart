// What LaunchFilm shows, and when, read from a real animated WebP through
// the engine's own codec: fixtures/film.webp, eight frames of 16 by 9, each
// one solid colour, written by fixtures/make_film.py.
//
// Two clocks are in play. The codec answers in real time, on the engine's
// threads, so every decode is waited for inside `tester.runAsync`. The
// ticker reads the test's own clock, which only `tester.pump` moves. A test
// therefore says exactly how long each frame has been up, and can leave a
// decode unfinished for as long as it likes by not running real time: the
// body of a widget test runs inside one turn of the real event loop, and a
// frame from the codec is delivered on another.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';

const String _film = 'test/launch_film/fixtures/film.webp';

/// The frames' colours as 0xRRGGBB. The same list as in make_film.py.
const List<int> _colours = <int>[
  0xFF0000,
  0x00FF00,
  0x0000FF,
  0xFFFF00,
  0x00FFFF,
  0xFF00FF,
  0xFF8000,
  0xFFFFFF,
];

/// How long each frame is shown, in milliseconds. As in make_film.py.
const List<int> _durations = <int>[40, 40, 40, 120, 40, 40, 40, 80];

const int _last = 7;

/// Serves files from the repository by their path, so the fixture needs no
/// entry in pubspec.yaml.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final File file = File(key);
    if (!file.existsSync()) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(file.readAsBytesSync());
  }
}

Widget _host(Widget film) => DefaultAssetBundle(
  bundle: _FileBundle(),
  child: Center(child: SizedBox(width: 160, height: 90, child: film)),
);

/// Real time for the codec, long enough for a frame this small on a busy
/// machine, then [by] on the ticker's clock.
Future<void> _step(WidgetTester tester, [Duration by = Duration.zero]) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump(by);
}

/// Steps until [done] holds, moving the ticker [by] each time.
Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration by = Duration.zero,
}) async {
  for (int tries = 0; tries < 200 && !done(); tries += 1) {
    await _step(tester, by);
  }
  expect(done(), isTrue, reason: 'the film never got there');
}

ui.Image? _shown(WidgetTester tester) =>
    tester.widget<RawImage>(find.byType(RawImage)).image;

/// The colour in the middle of the frame on screen, as 0xRRGGBB.
Future<int> _colour(WidgetTester tester) async {
  final ui.Image image = _shown(tester)!;
  final ByteData? pixels = await tester.runAsync<ByteData?>(
    image.toByteData,
  );
  final int offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  return pixels!.getUint32(offset) >> 8;
}

/// The frames the controller reported, in order, for as long as it lives.
List<int> _record(LaunchFilmController controller) {
  final List<int> frames = <int>[];
  controller.addListener(() {
    // It also speaks when the frame count is known and when a run ends.
    final int frame = controller.frame;
    if (frame >= 0 && (frames.isEmpty || frames.last != frame)) {
      frames.add(frame);
    }
  });
  return frames;
}

void main() {
  testWidgets('is plain black before the first frame', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: controller)),
    );

    expect(_shown(tester), isNull);
    expect(controller.frame, -1);
    expect(controller.isDone, isFalse);
    final ColoredBox ground = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(LaunchFilm),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(ground.color, const Color(0xFF000000));
    expect(
      find.descendant(
        of: find.byType(LaunchFilm),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );

    // The first frame is up as soon as it is decoded, with no wait.
    await _until(tester, () => controller.frame == 0);
    expect(await _colour(tester), _colours[0]);
    expect(controller.frameCount, _colours.length);
  });

  testWidgets('plays to the end, holds the last frame, calls onDone once', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    final List<int> frames = _record(controller);
    int done = 0;
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: _film,
          controller: controller,
          onDone: () => done += 1,
        ),
      ),
    );

    await _until(
      tester,
      () => controller.isDone,
      by: const Duration(milliseconds: 20),
    );
    expect(frames, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(done, 1);
    expect(controller.frame, _last);
    expect(await _colour(tester), _colours[_last]);

    // The file says to loop for ever. Another two seconds, with every
    // chance for the codec to hand over its first frame again.
    for (int i = 0; i < 10; i += 1) {
      await _step(tester, const Duration(milliseconds: 200));
    }
    expect(frames, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(done, 1);
    expect(controller.isDone, isTrue);
    expect(await _colour(tester), _colours[_last]);
  });

  testWidgets('shows each frame for its own duration', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    int clock = 0;
    final Map<int, int> shownAt = <int, int>{};
    int? doneAt;
    controller.addListener(() {
      shownAt.putIfAbsent(controller.frame, () => clock);
    });
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: _film,
          controller: controller,
          onDone: () => doneAt = clock,
        ),
      ),
    );

    const int tick = 20;
    for (int i = 0; i < 100 && doneAt == null; i += 1) {
      clock += tick;
      await _step(tester, const Duration(milliseconds: tick));
    }
    expect(doneAt, isNotNull);
    for (int index = 0; index < _last; index += 1) {
      expect(
        shownAt[index + 1]! - shownAt[index]!,
        _durations[index],
        reason: 'frame $index',
      );
    }
    // The last frame has its time too before the run is called done.
    expect(doneAt! - shownAt[_last]!, _durations[_last]);
  });

  testWidgets('a late decode shows the next frame, and skips none', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    final List<int> frames = _record(controller);
    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: controller)),
    );
    await _until(tester, () => controller.frame == 0);

    // Half a second on the ticker with no real time for the codec: frame 1
    // is asked for and has not come back.
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.frame, 0);

    // It is shown the moment it arrives, not dropped for the one the clock
    // would be on by now.
    await _step(tester);
    expect(controller.frame, 1);
    expect(await _colour(tester), _colours[1]);

    // And it gets its own time from then: the clock starts again from it.
    await _step(tester, const Duration(milliseconds: 20));
    expect(controller.frame, 1);
    await _step(tester, const Duration(milliseconds: 20));
    expect(controller.frame, 2);
    expect(frames, <int>[0, 1, 2]);
  });

  testWidgets('play(from: n) shows frame n first', (WidgetTester tester) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    final List<int> frames = _record(controller);
    int done = 0;
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: _film,
          autoplay: false,
          controller: controller,
          onDone: () => done += 1,
        ),
      ),
    );

    // Without autoplay nothing is read and nothing is drawn.
    await _step(tester, const Duration(milliseconds: 200));
    expect(_shown(tester), isNull);
    expect(controller.frameCount, 0);

    controller.play(from: 5);
    await _until(tester, () => controller.frame >= 0);
    expect(controller.frame, 5);
    expect(await _colour(tester), _colours[5]);

    await _until(
      tester,
      () => controller.isDone,
      by: const Duration(milliseconds: 20),
    );
    expect(frames, <int>[5, 6, 7]);
    expect(done, 1);
  });

  testWidgets('a replay keeps the frame on screen until its first is ready', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    int done = 0;
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: _film,
          controller: controller,
          onDone: () => done += 1,
        ),
      ),
    );
    await _until(
      tester,
      () => controller.isDone,
      by: const Duration(milliseconds: 20),
    );
    final List<int> frames = _record(controller);

    controller.play(from: 3);
    expect(controller.isDone, isFalse);
    // No real time yet, so the new run has decoded nothing: the wordmark
    // stays up, it does not go black.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.frame, _last);
    expect(await _colour(tester), _colours[_last]);

    await _until(tester, () => controller.frame != _last);
    expect(controller.frame, 3);
    expect(await _colour(tester), _colours[3]);

    await _until(
      tester,
      () => controller.isDone,
      by: const Duration(milliseconds: 20),
    );
    // The wordmark first: it was still up when the run began.
    expect(frames, <int>[_last, 3, 4, 5, 6, 7]);
    // Once for each run.
    expect(done, 2);
  });

  testWidgets('play(from:) past the end is the last frame', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController()
      ..play(from: 99);
    addTearDown(controller.dispose);
    final List<int> frames = _record(controller);
    // Asked before the widget existed: it takes the place of autoplay.
    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: controller)),
    );
    await _until(
      tester,
      () => controller.isDone,
      by: const Duration(milliseconds: 20),
    );
    expect(frames, <int>[_last]);
    expect(await _colour(tester), _colours[_last]);
  });

  testWidgets('skipToEnd jumps to the last frame and holds it', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    final List<int> frames = _record(controller);
    int done = 0;
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: _film,
          controller: controller,
          onDone: () => done += 1,
        ),
      ),
    );
    await _until(
      tester,
      () => controller.frame == 1,
      by: const Duration(milliseconds: 20),
    );

    controller.skipToEnd();
    // No time passes on the ticker: the frames between are not waited out.
    await _until(tester, () => controller.isDone);
    expect(frames, <int>[0, 1, _last]);
    expect(done, 1);
    expect(await _colour(tester), _colours[_last]);

    // A second skip, and more time, change nothing.
    controller.skipToEnd();
    for (int i = 0; i < 5; i += 1) {
      await _step(tester, const Duration(milliseconds: 200));
    }
    expect(frames, <int>[0, 1, _last]);
    expect(done, 1);
    expect(controller.isDone, isTrue);
  });

  testWidgets('skipToEnd before anything played goes straight to the end', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    final List<int> frames = _record(controller);
    int done = 0;
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: _film,
          autoplay: false,
          controller: controller,
          onDone: () => done += 1,
        ),
      ),
    );

    controller.skipToEnd();
    await _until(tester, () => controller.isDone);
    expect(frames, <int>[_last]);
    expect(done, 1);
    expect(await _colour(tester), _colours[_last]);
  });

  testWidgets('disposing mid-run does not throw', (WidgetTester tester) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    int done = 0;
    final Widget film = _host(
      LaunchFilm(
        asset: _film,
        controller: controller,
        onDone: () => done += 1,
      ),
    );

    // Gone before the first frame has come back from the codec.
    await tester.pumpWidget(film);
    await tester.pumpWidget(const SizedBox());
    await _step(tester, const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // Gone with a frame on screen and the next one being decoded.
    await tester.pumpWidget(film);
    await _until(tester, () => controller.frame == 0);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(const SizedBox());
    await _step(tester, const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // Gone with a frame on screen and the next decoded and waiting.
    await tester.pumpWidget(film);
    await _until(tester, () => controller.frame == 0);
    await _step(tester);
    await tester.pumpWidget(const SizedBox());
    await _step(tester, const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // A film that is gone finishes nothing, and its controller is free
    // for the next one and harmless without one.
    expect(done, 0);
    controller
      ..play()
      ..skipToEnd();
    await _step(tester, const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('decodeWidth gives a smaller image', (WidgetTester tester) async {
    final LaunchFilmController full = LaunchFilmController();
    final LaunchFilmController small = LaunchFilmController();
    addTearDown(full.dispose);
    addTearDown(small.dispose);
    final _FileBundle bundle = _FileBundle();
    await tester.pumpWidget(
      Row(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          SizedBox(
            width: 160,
            height: 90,
            // Given its bundle directly here, with none above it but the
            // root's, which does not have the file.
            child: LaunchFilm(asset: _film, bundle: bundle, controller: full),
          ),
          SizedBox(
            width: 160,
            height: 90,
            child: LaunchFilm(
              asset: _film,
              bundle: bundle,
              decodeWidth: 8,
              controller: small,
            ),
          ),
        ],
      ),
    );
    await _until(
      tester,
      () => full.isDone && small.isDone,
      by: const Duration(milliseconds: 20),
    );

    final List<ui.Image> images = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .map((RawImage raw) => raw.image!)
        .toList();
    expect((images[0].width, images[0].height), (16, 9));
    expect(images[1].width, 8);
    expect(images[1].height, lessThan(9));

    // The same picture, only smaller.
    final ByteData? pixels = await tester.runAsync<ByteData?>(
      images[1].toByteData,
    );
    expect(pixels!.getUint32(0) >> 8, _colours[_last]);
    expect(small.frameCount, _colours.length);
  });

  testWidgets('a width wider than the file leaves the frames as they are', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        LaunchFilm(asset: _film, decodeWidth: 4096, controller: controller),
      ),
    );
    await _until(tester, () => controller.frame == 0);
    expect(_shown(tester)!.width, 16);
  });

  testWidgets('a file that cannot be read ends the run, on black', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController();
    addTearDown(controller.dispose);
    int done = 0;
    await tester.pumpWidget(
      _host(
        LaunchFilm(
          asset: 'test/launch_film/fixtures/no_such.webp',
          controller: controller,
          onDone: () => done += 1,
        ),
      ),
    );
    await _until(tester, () => controller.isDone);

    // Reported, so it is in the log, and whoever waits on the launch is
    // let through.
    expect(tester.takeException(), isFlutterError);
    expect(done, 1);
    expect(_shown(tester), isNull);
    expect(controller.frame, -1);

    controller.skipToEnd();
    await _step(tester);
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a controller swapped in mid-run takes the film over', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController first = LaunchFilmController();
    final LaunchFilmController second = LaunchFilmController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(_host(LaunchFilm(asset: _film, controller: first)));
    await _until(tester, () => first.frame == 0);

    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: second)),
    );
    expect(second.frame, 0);
    expect(second.frameCount, _colours.length);

    second.skipToEnd();
    await _until(tester, () => second.isDone);
    expect(second.frame, _last);
    // The one let go heard nothing more.
    expect(first.frame, 0);
    expect(first.isDone, isFalse);
  });

  testWidgets('a queued play takes over and cancels the previous run', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController first = LaunchFilmController();
    final LaunchFilmController second = LaunchFilmController()..play(from: 5);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final List<int> frames = _record(second);
    await tester.pumpWidget(_host(LaunchFilm(asset: _film, controller: first)));
    await _until(tester, () => first.frame == 0);

    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: second)),
    );
    expect(second.frame, 0);
    await _until(tester, () => second.frame != 0);
    expect(second.frame, 5);
    expect(await _colour(tester), _colours[5]);
    await _until(
      tester,
      () => second.isDone,
      by: const Duration(milliseconds: 20),
    );
    expect(frames, <int>[0, 5, 6, 7]);
    expect(first.frame, 0);

    // The pending command was consumed. Reattaching that controller to
    // the finished film must not replay it a second time.
    await tester.pumpWidget(_host(LaunchFilm(asset: _film, controller: first)));
    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: second)),
    );
    await _step(tester, const Duration(milliseconds: 500));
    expect(second.isDone, isTrue);
    expect(frames, <int>[0, 5, 6, 7]);
  });

  testWidgets('a queued skip is applied when a controller takes over', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController first = LaunchFilmController();
    final LaunchFilmController second = LaunchFilmController()..skipToEnd();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final List<int> frames = _record(second);
    await tester.pumpWidget(_host(LaunchFilm(asset: _film, controller: first)));
    await _until(
      tester,
      () => first.frame == 1,
      by: const Duration(milliseconds: 20),
    );

    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: second)),
    );
    // The skip does not wait for the remaining frames' display durations.
    await _until(tester, () => second.isDone);
    expect(frames, <int>[1, _last]);
    expect(await _colour(tester), _colours[_last]);
    expect(first.frame, 1);
  });

  testWidgets('a newer takeover listener request replaces the queued one', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController first = LaunchFilmController();
    final LaunchFilmController second = LaunchFilmController()..play(from: 5);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    bool requested = false;
    second.addListener(() {
      if (!requested && second.frame == 0) {
        requested = true;
        second.play(from: 3);
      }
    });
    await tester.pumpWidget(_host(LaunchFilm(asset: _film, controller: first)));
    await _until(tester, () => first.frame == 0);

    await tester.pumpWidget(
      _host(LaunchFilm(asset: _film, controller: second)),
    );
    await _until(tester, () => second.frame != 0);
    expect(requested, isTrue);
    expect(second.frame, 3);
    expect(await _colour(tester), _colours[3]);
    await tester.pumpWidget(const SizedBox());
    await _step(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reused completed controller can skip a new film', (
    WidgetTester tester,
  ) async {
    final LaunchFilmController controller = LaunchFilmController()..skipToEnd();
    addTearDown(controller.dispose);
    int done = 0;
    Widget film() => _host(
      LaunchFilm(
        asset: _film,
        autoplay: false,
        controller: controller,
        onDone: () => done += 1,
      ),
    );
    await tester.pumpWidget(film());
    await _until(tester, () => controller.isDone);
    expect(await _colour(tester), _colours[_last]);
    await tester.pumpWidget(const SizedBox());

    controller.skipToEnd();
    await tester.pumpWidget(film());
    expect(controller.isDone, isFalse);
    await _until(tester, () => controller.isDone);
    expect(controller.frame, _last);
    expect(await _colour(tester), _colours[_last]);
    expect(done, 2);
  });
}
