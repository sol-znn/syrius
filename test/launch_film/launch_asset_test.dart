// The launch files the wallet ships, opened by the engine's own codec.
//
// tool/lottie_reencode.py writes their containers by hand. The full film
// and the well store changed rectangles without blending or disposal, and
// their still endings are six frames of one pixel.
// Pillow reads that back correctly, but Pillow is not what plays it. A
// decoder that cleared the canvas between frames, or blended, or dropped a
// one pixel frame, would show black, stale boxes or a film that ends early,
// and only in the wallet. So each file is decoded here from first frame to
// last and held against the master's own pictures. Every composited frame
// also has to equal the original engine codec, at every RGBA pixel.
//
// The references are fixtures/launch_NN.rgb, written from the master's JPEGs
// by fixtures/make_launch_refs.py: 64 by 36, each value the mean of one
// block of the frame. Neighbouring frames of the film differ by 30 to 250
// in their worst block wherever anything moves, and the codec's loss moves
// a block's mean by one or two, so a wrong frame cannot pass for the right
// one.

import 'dart:io';
import 'dart:typed_data' as typed;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as foundation show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film_decoder.dart';

const String _fixtures = 'test/launch_film/fixtures';

const int _frameCount = 56;

/// The master runs at 30 frames a second.
const int _rate = 30;

/// The frames held against the master. As in make_launch_refs.py.
const List<int> _checked = <int>[0, 1, 27, 49, 50, 55];

const int _gridWidth = 64;
const int _gridHeight = 36;

/// How far a block's mean may be from the master's, out of 255, in the
/// worst block and on average. Measured: 2 and 0.19 at 2560, 6 and 0.54 at
/// 640, where a block is 100 pixels and not 1600 and the Lanczos reduction
/// moves its mean a little as well.
const int _worstAllowed = 10;
const double _meanAllowed = 0.8;

/// Frame [index]'s time on screen: from its rounded start to its rounded
/// end, the rule the tool writes by.
int _milliseconds(int index) =>
    ((index + 1) * 1000 / _rate).round() - (index * 1000 / _rate).round();

/// The mean of each block of [image], as [_gridWidth] by [_gridHeight] RGB.
Future<typed.Uint8List> _blockMeans(ui.Image image) async {
  final typed.ByteData data = (await image.toByteData())!;
  final int block = image.width ~/ _gridWidth;
  expect(block * _gridWidth, image.width);
  expect(block * _gridHeight, image.height);
  final typed.Uint32List sums = typed.Uint32List(_gridWidth * _gridHeight * 3);
  final typed.Uint8List bytes = data.buffer.asUint8List();
  int at = 0;
  for (int y = 0; y < image.height; y++) {
    final int row = (y ~/ block) * _gridWidth;
    for (int x = 0; x < image.width; x++) {
      final int cell = (row + x ~/ block) * 3;
      sums[cell] += bytes[at];
      sums[cell + 1] += bytes[at + 1];
      sums[cell + 2] += bytes[at + 2];
      at += 4;
    }
  }
  final typed.Uint8List means = typed.Uint8List(sums.length);
  final int area = block * block;
  for (int i = 0; i < sums.length; i++) {
    means[i] = (sums[i] + area ~/ 2) ~/ area;
  }
  return means;
}

/// The worst and the mean distance between two grids.
({int worst, double mean}) _distance(typed.Uint8List a, typed.Uint8List b) {
  expect(a.length, b.length);
  int worst = 0;
  int sum = 0;
  for (int i = 0; i < a.length; i++) {
    final int d = (a[i] - b[i]).abs();
    sum += d;
    if (d > worst) {
      worst = d;
    }
  }
  return (worst: worst, mean: sum / a.length);
}

/// Decodes all of [path] and checks every frame's size and duration, and
/// the frames in [_checked] against the master.
Future<void> _decode(String path, int width, int height) async {
  final typed.Uint8List bytes = File(path).readAsBytesSync();
  final Map<int, typed.Uint8List> references = <int, typed.Uint8List>{
    for (final int index in _checked)
      index: File(
        '$_fixtures/launch_${index.toString().padLeft(2, '0')}.rgb',
      ).readAsBytesSync(),
  };

  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final LaunchFilmDecoder rectangles = await LaunchFilmDecoder.fromBytes(bytes);
  ui.Image? heldEnding;
  bool rectanglesClosed = false;
  try {
    expect(rectangles.usesFrameRectangles, isTrue);
    expect(codec.frameCount, _frameCount);
    // The file's loop count is 1, and the engine reports the repeats after
    // the first run. LaunchFilm stops on the last frame whatever this says;
    // it is checked so that a change in the container is noticed.
    expect(codec.repetitionCount, 0);

    int total = 0;
    final Stopwatch decoding = Stopwatch();
    final Map<int, typed.Uint8List> decoded = <int, typed.Uint8List>{};
    for (int index = 0; index < _frameCount; index++) {
      decoding.start();
      final ui.FrameInfo info = await codec.getNextFrame();
      decoding.stop();
      final ui.Image image = info.image;
      final LaunchFilmFrame rectangle = await rectangles.getNextFrame();
      try {
        expect(
          (rectangle.image.width, rectangle.image.height),
          (width, height),
        );
        expect(
          rectangle.duration,
          info.duration,
          reason: 'frame $index duration',
        );
        if (index == _frameCount - 1) heldEnding = rectangle.image.clone();
        final typed.ByteData original = (await image.toByteData())!;
        final typed.ByteData composed = (await rectangle.image.toByteData())!;
        expect(
          foundation.listEquals(
            original.buffer.asUint8List(),
            composed.buffer.asUint8List(),
          ),
          isTrue,
          reason: 'Every pixel of original frame $index must remain unchanged',
        );
      } finally {
        rectangle.image.dispose();
      }
      // A frame stored as a box, or as one pixel, still comes back as the
      // whole canvas.
      expect(image.width, width, reason: 'frame $index');
      expect(image.height, height, reason: 'frame $index');
      expect(
        info.duration.inMilliseconds,
        _milliseconds(index),
        reason: 'frame $index',
      );
      total += info.duration.inMilliseconds;
      if (references.containsKey(index)) {
        decoded[index] = await _blockMeans(image);
      }
      if (path == 'assets/images/launch.webp' && index == _frameCount - 1) {
        final ui.Codec ending = await ui.instantiateImageCodec(
          File('assets/images/launch_end.webp').readAsBytesSync(),
        );
        try {
          expect(ending.frameCount, 1);
          final ui.Image still = (await ending.getNextFrame()).image;
          try {
            expect((still.width, still.height), (width, height));
            final typed.ByteData originalPixels = (await image.toByteData())!;
            final typed.ByteData endingPixels = (await still.toByteData())!;
            expect(
              foundation.listEquals(
                originalPixels.buffer.asUint8List(),
                endingPixels.buffer.asUint8List(),
              ),
              isTrue,
              reason: 'Skip must show the original final pixels exactly',
            );
          } finally {
            still.dispose();
          }
        } finally {
          ending.dispose();
        }
      }
      image.dispose();
    }
    expect(total, 1867);

    for (final int index in _checked) {
      final ({int worst, double mean}) d = _distance(
        decoded[index]!,
        references[index]!,
      );
      // Shown on every run: these are the numbers the tolerances came from.
      // ignore: avoid_print
      print('$path frame $index: worst block ${d.worst}, mean ${d.mean}');
      expect(d.worst, lessThanOrEqualTo(_worstAllowed), reason: 'frame $index');
      expect(d.mean, lessThan(_meanAllowed), reason: 'frame $index');
    }
    // The comparison has to be able to fail. Frame 1 is frame 0 with a box
    // laid over it and frame 50 is frame 49 with one: had the decoder left
    // the frame before on the canvas, these two would be zero.
    expect(_distance(decoded[1]!, references[0]!).worst, greaterThan(30));
    expect(_distance(decoded[50]!, references[49]!).worst, greaterThan(30));
    // The still ending: six frames of one pixel leave the picture alone.
    expect(_distance(decoded[55]!, decoded[50]!).worst, 0);

    // What a frame costs to decode is why the well has a file of its own.
    // ignore: avoid_print
    print(
      '$path: ${decoding.elapsedMilliseconds / _frameCount} ms a frame, '
      '${decoding.elapsedMilliseconds} ms for all $_frameCount',
    );
    rectangles.dispose();
    rectanglesClosed = true;
    final ui.Image retainedEnding = heldEnding!;
    expect((retainedEnding.width, retainedEnding.height), (width, height));
    expect(await retainedEnding.toByteData(), isNotNull);
  } finally {
    if (!rectanglesClosed) rectangles.dispose();
    heldEnding?.dispose();
    codec.dispose();
  }
}

void main() {
  // The codec answers in real time, on the engine's threads, which a widget
  // test only lets run inside runAsync.
  testWidgets('launch.webp decodes to the master, frame for frame', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => _decode('assets/images/launch.webp', 2560, 1440),
    );
  });

  testWidgets('launch_well.webp is the same film at 640 by 360', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(
      () => _decode('assets/images/launch_well.webp', 640, 360),
    );
  });
}
