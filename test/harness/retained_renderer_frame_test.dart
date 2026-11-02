import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/capture_protocol.dart';
import '../../harness/app/retained_png.dart';
import '../../harness/app/retained_renderer_frame.dart';

void main() {
  Future<void> paint(WidgetTester tester, Color color) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(color: color),
    ),
  );

  void size(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(64, 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('actual held raster survives later live paints', (
    WidgetTester tester,
  ) async {
    size(tester);
    await paint(tester, const Color(0xFFFF0000));
    final RenderView view = tester.binding.renderViews.single;
    final RetainedRendererFrame? frame = await tester.runAsync(
      () => RetainedRendererFrame.capture(
        view: view,
        expectedSize: const Size(64, 48),
        sourceCurrent: () => true,
      ),
    );
    expect(frame, isNotNull);
    await paint(tester, const Color(0xFF0000FF));
    expect(frame!.isCurrent, isTrue);
    await tester.runAsync(() async {
      final Future<Uint8List> encoding = frame.encodePng();
      expect(frame.encodePng(), same(encoding));
      final Uint8List png = await encoding;
      expect(frame.originalEncoding, isNotNull);
      final ui.Codec codec = await ui.instantiateImageCodec(png);
      try {
        final ui.FrameInfo decoded = await codec.getNextFrame();
        try {
          expect(decoded.image.width, 64);
          expect(decoded.image.height, 48);
          final ByteData? pixels = await decoded.image.toByteData();
          expect(pixels!.buffer.asUint8List(pixels.offsetInBytes, 4), <int>[
            255,
            0,
            0,
            255,
          ]);
        } finally {
          decoded.image.dispose();
        }
      } finally {
        codec.dispose();
        final Future<void> release = frame.release();
        expect(frame.release(), same(release));
        await release;
      }
    });
    expect(frame.released, isTrue);
    expect(frame.isCurrent, isFalse);
  });

  testWidgets('source loss stays refused after the source returns', (
    WidgetTester tester,
  ) async {
    size(tester);
    await paint(tester, const Color(0xFF000000));
    bool current = true;
    final RetainedRendererFrame? frame = await tester.runAsync(
      () => RetainedRendererFrame.capture(
        view: tester.binding.renderViews.single,
        expectedSize: const Size(64, 48),
        sourceCurrent: () => current,
      ),
    );
    current = false;
    expect(frame!.isCurrent, isFalse);
    current = true;
    expect(frame.isCurrent, isFalse);
    await tester.runAsync(() async {
      await expectLater(frame.encodePng(), throwsA(isA<CaptureRefused>()));
      expect(frame.originalEncoding, isNull);
      await frame.release();
    });
    expect(frame.released, isTrue);
  });

  testWidgets('unexpected client size refuses before raster readback', (
    WidgetTester tester,
  ) async {
    size(tester);
    await paint(tester, const Color(0xFF000000));
    await tester.runAsync(() async {
      await expectLater(
        RetainedRendererFrame.capture(
          view: tester.binding.renderViews.single,
          expectedSize: const Size(1280, 780),
          sourceCurrent: () => true,
        ),
        throwsA(isA<CaptureRefused>()),
      );
    });
  });

  Future<Uint8List> decodedRgba(Uint8List png) async {
    final ui.Codec codec = await ui.instantiateImageCodec(png);
    try {
      final ui.FrameInfo frame = await codec.getNextFrame();
      try {
        final ByteData? rgba = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        expect(rgba, isNotNull);
        return Uint8List.fromList(
          rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  testWidgets('PNG keeps offset RGBA channels and straight alpha', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      const List<int> pixels = <int>[
        255, 0, 0, 255,
        0, 255, 0, 255,
        17, 23, 253, 255,
        255, 0, 255, 128,
        0, 255, 255, 64,
        0, 0, 0, 0,
      ];
      final Uint8List storage = Uint8List(32)
        ..fillRange(0, 32, 91)
        ..setRange(4, 28, pixels);
      final Uint8List png = await encodeRetainedRgba(
        ByteData.view(storage.buffer, 4, 24),
        width: 3,
        height: 2,
      );
      expect(await decodedRgba(png), pixels);
    });
  });

  testWidgets('the worker owns bytes before caller mutation', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      const List<int> expected = <int>[255, 0, 0, 255, 0, 255, 0, 255];
      final Uint8List pixels = Uint8List.fromList(expected);
      final Future<Uint8List> encoding = encodeRetainedRgba(
        ByteData.sublistView(pixels),
        width: 2,
        height: 1,
      );
      pixels.fillRange(0, pixels.length, 0);
      expect(await decodedRgba(await encoding), expected);
    });
  });

  test('invalid retained frames refuse before worker startup', () {
    const List<List<int>> cases = <List<int>>[
      <int>[0, 1, 0],
      <int>[-1, 1, 0],
      <int>[1, 0, 0],
      <int>[4097, 1, 0],
      <int>[4001, 4000, 0],
      <int>[1, 1, 3],
      <int>[1, 1, 5],
    ];
    for (final List<int> sample in cases) {
      expect(
        () => encodeRetainedRgba(
          ByteData(sample[2]),
          width: sample[0],
          height: sample[1],
        ),
        throwsFormatException,
      );
    }
  });

  testWidgets('source loss during raw readback cannot start PNG work', (
    WidgetTester tester,
  ) async {
    size(tester);
    await paint(tester, const Color(0xFF000000));
    bool current = true;
    final RetainedRendererFrame? captured = await tester.runAsync(
      () => RetainedRendererFrame.capture(
        view: tester.binding.renderViews.single,
        expectedSize: const Size(64, 48),
        sourceCurrent: () => current,
      ),
    );
    expect(captured, isNotNull);
    final RetainedRendererFrame frame = captured!;
    await tester.runAsync(() async {
      final Future<Uint8List> encoding = frame.encodePng();
      expect(frame.originalEncoding, isNotNull);
      current = false;
      await expectLater(encoding, throwsA(isA<CaptureRefused>()));
      expect(frame.originalPngEncoding, isNull);
      current = true;
      expect(frame.isCurrent, isFalse);
      expect(frame.encodePng(), same(encoding));
      await frame.release();
    });
    expect(frame.released, isTrue);
  });

  testWidgets('release waits for the original raw readback refusal', (
    WidgetTester tester,
  ) async {
    size(tester);
    await paint(tester, const Color(0xFF000000));
    final RetainedRendererFrame? captured = await tester.runAsync(
      () => RetainedRendererFrame.capture(
        view: tester.binding.renderViews.single,
        expectedSize: const Size(64, 48),
        sourceCurrent: () => true,
      ),
    );
    expect(captured, isNotNull);
    final RetainedRendererFrame frame = captured!;
    await tester.runAsync(() async {
      final Future<Uint8List> encoding = frame.encodePng();
      final Future<void> refused = expectLater(
        encoding,
        throwsA(isA<CaptureRefused>()),
      );
      final Future<void> release = frame.release();
      expect(frame.released, isFalse);
      await refused;
      await release;
      expect(frame.release(), same(release));
      expect(frame.encodePng(), same(encoding));
    });
    expect(frame.released, isTrue);
    expect(frame.isCurrent, isFalse);
  });
}
