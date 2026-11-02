import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encodes an owned snapshot of straight sRGB RGBA bytes without a UI handle.
/// Only the declared byte range is transferred to the one PNG worker.
Future<Uint8List> encodeRetainedRgba(
  ByteData rgba, {
  required int width,
  required int height,
}) {
  if (width <= 0 ||
      height <= 0 ||
      width > 4096 ||
      height > 4096 ||
      width * height > 16000000 ||
      rgba.lengthInBytes != width * height * 4) {
    throw const FormatException('Invalid retained RGBA frame');
  }
  final TransferableTypedData pixels = TransferableTypedData.fromList(
    <TypedData>[
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
    ],
  );
  return Isolate.run<Uint8List>(
    _pngWork(pixels, width, height),
    debugName: 'retained-png',
  );
}

// This closure is created outside the renderer's scope. It captures no image,
// layer, widget, client, socket or other application owner.
Uint8List Function() _pngWork(
  TransferableTypedData pixels,
  int width,
  int height,
) => () {
  final img.Image image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.materialize(),
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodePng(image);
};
