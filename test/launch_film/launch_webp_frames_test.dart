import 'dart:io';
import 'dart:typed_data' as typed;

import 'package:flutter/foundation.dart' as foundation show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film_decoder.dart';

void main() {
  test('opaque films keep original timelines and owned bytes', () {
    const List<({String path, int width, int height})> files =
        <({String path, int width, int height})>[
      (path: 'assets/images/launch.webp', width: 2560, height: 1440),
      (path: 'assets/images/launch_well.webp', width: 640, height: 360),
    ];
    for (final ({String path, int width, int height}) file in files) {
      final typed.Uint8List bytes = File(file.path).readAsBytesSync();
      final LaunchWebpFrames film = LaunchWebpFrames.tryParse(bytes)!;
      expect((film.width, film.height), (file.width, file.height));
      expect(film.repetitionCount, 0);
      expect(film.frames, hasLength(56));
      int total = 0;
      for (int index = 0; index < film.frames.length; index += 1) {
        final LaunchWebpFrame frame = film.frames[index];
        final int milliseconds = ((index + 1) * 1000 / 30).round() -
            (index * 1000 / 30).round();
        expect(frame.milliseconds, milliseconds);
        expect(frame.x + frame.width, lessThanOrEqualTo(file.width));
        expect(frame.y + frame.height, lessThanOrEqualTo(file.height));
        total += frame.milliseconds;
        final typed.Uint8List still = film.frameBytes(index);
        expect(String.fromCharCodes(still.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(still.sublist(8, 16)), 'WEBPVP8 ');
        expect(
          typed.ByteData.sublistView(still)
              .getUint32(4, typed.Endian.little),
          still.length - 8,
        );
      }
      expect(total, 1867);
      final typed.Uint8List ownedFirst = film.frameBytes(0);
      bytes.fillRange(0, bytes.length, 0);
      expect(foundation.listEquals(film.frameBytes(0), ownedFirst), isTrue);
      expect(film.frames.clear, throwsUnsupportedError);
    }
  });

  test('unsupported frames retain the engine fallback', () {
    final typed.Uint8List source =
        File('assets/images/launch.webp').readAsBytesSync();
    expect(String.fromCharCodes(source.sublist(44, 48)), 'ANMF');
    expect(String.fromCharCodes(source.sublist(68, 72)), 'VP8 ');
    final Map<String, void Function(typed.Uint8List)> changes =
        <String, void Function(typed.Uint8List)>{
      'riff size': (typed.Uint8List b) => b[4] ^= 1,
      'non-animated extended flags': (typed.Uint8List b) => b[20] = 0,
      'alpha flag': (typed.Uint8List b) => b[20] |= 0x10,
      'reserved extended flag': (typed.Uint8List b) => b[21] = 1,
      'animation chunk': (typed.Uint8List b) => b[30] = 0,
      'canvas cap': (typed.Uint8List b) => b[26] = 1,
      'unknown frame chunk': (typed.Uint8List b) => b[44] = 0,
      'out-of-range frame chunk': (typed.Uint8List b) => b[51] = 0x7f,
      'cropped first canvas': (typed.Uint8List b) => b[52] = 1,
      'disposal': (typed.Uint8List b) => b[67] = 3,
      'blend': (typed.Uint8List b) => b[67] = 0,
      'reserved frame flags': (typed.Uint8List b) => b[67] = 6,
      'short duration': (typed.Uint8List b) => b[64] = 10,
      'lossless chunk': (typed.Uint8List b) => b[71] = 76,
      'out-of-range bitstream': (typed.Uint8List b) => b[75] = 0x7f,
      'non-key frame': (typed.Uint8List b) => b[76] |= 1,
      'key frame signature': (typed.Uint8List b) => b[79] = 0,
      'different coded width': (typed.Uint8List b) => b[82] ^= 1,
      'different coded height': (typed.Uint8List b) => b[84] ^= 1,
    };
    for (final MapEntry<String, void Function(typed.Uint8List)> item
        in changes.entries) {
      final typed.Uint8List changed = typed.Uint8List.fromList(source);
      item.value(changed);
      expect(LaunchWebpFrames.tryParse(changed), isNull, reason: item.key);
    }
    for (final int length in <int>[0, 11, 30, 43, 67, 68, source.length - 1]) {
      expect(
        LaunchWebpFrames.tryParse(
          typed.Uint8List.sublistView(source, 0, length),
        ),
        isNull,
      );
    }
    expect(
      LaunchWebpFrames.tryParse(
        typed.Uint8List.fromList(<int>[...source, 0, 0]),
      ),
      isNull,
    );
  });
}
