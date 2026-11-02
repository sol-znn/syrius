import 'dart:typed_data';
import 'dart:ui' as ui;

/// The caller owns this image, including after its decoder is disposed.
class LaunchFilmFrame {
  /// Keeps the caller's decoded image and its original display duration.
  const LaunchFilmFrame(this._image, this._duration);

  final ui.Image _image;
  final Duration _duration;

  /// The caller disposes this handle after its last use.
  ui.Image get image => _image;
  /// The duration recorded in the original container.
  Duration get duration => _duration;
}

/// One original forward-only film, with no playback clock or skipped frames.
abstract class LaunchFilmDecoder {
  /// The number of frames in the original film.
  int get frameCount;
  /// Repeats after the first run, or minus one for an infinite loop.
  int get repetitionCount;

  /// Whether this decoder preserves opaque WebP rectangles on its own canvas.
  bool get usesFrameRectangles;

  /// Decodes the next original frame and transfers its image to the caller.
  Future<LaunchFilmFrame> getNextFrame();

  /// Called only after the original getNextFrame Future has returned.
  void dispose();

  /// Opens original asset data without changing its byte range.
  static Future<LaunchFilmDecoder> fromData(
    ByteData data, {
    int? targetWidth,
  }) => fromBytes(Uint8List.sublistView(data), targetWidth: targetWidth);

  /// Selects rectangle composition only for the supported opaque subset.
  static Future<LaunchFilmDecoder> fromBytes(
    Uint8List bytes, {
    int? targetWidth,
  }) async {
    final LaunchWebpFrames? frames = LaunchWebpFrames.tryParse(bytes);
    if (frames != null) return _RectangleDecoder(frames);
    return fromBuffer(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      targetWidth: targetWidth,
    );
  }

  /// Opens an owned immutable buffer with the original engine codec.
  static Future<LaunchFilmDecoder> fromBuffer(
    ui.ImmutableBuffer buffer, {
    int? targetWidth,
  }) async => _EngineDecoder(
    await ui.instantiateImageCodecFromBuffer(
      buffer,
      targetWidth: targetWidth,
      allowUpscaling: false,
    ),
  );
}

class _EngineDecoder extends LaunchFilmDecoder {
  _EngineDecoder(this._codec);

  final ui.Codec _codec;

  @override
  int get frameCount => _codec.frameCount;

  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  bool get usesFrameRectangles => false;

  @override
  Future<LaunchFilmFrame> getNextFrame() async {
    final ui.FrameInfo frame = await _codec.getNextFrame();
    return LaunchFilmFrame(frame.image, frame.duration);
  }

  @override
  void dispose() => _codec.dispose();
}

/// The closed WebP subset used by the shipped films.
///
/// Each frame is an opaque VP8 key frame, replaces its rectangle without
/// disposal, and retains everything outside that rectangle. The first frame
/// covers the canvas. Other containers keep the engine's original decoder.
/// Encoded VP8 bytes and millisecond durations are copied without re-encoding.
class LaunchWebpFrames {
  LaunchWebpFrames._(
    this._bytes,
    this._width,
    this._height,
    this._repetitionCount,
    List<LaunchWebpFrame> frames,
  ) : _frames = List<LaunchWebpFrame>.unmodifiable(frames);

  final Uint8List _bytes;
  final int _width;
  final int _height;
  final int _repetitionCount;
  final List<LaunchWebpFrame> _frames;

  /// The original canvas or rectangle width in pixels.
  int get width => _width;
  /// The original canvas or rectangle height in pixels.
  int get height => _height;
  /// Repeats after the first run, or minus one for an infinite loop.
  int get repetitionCount => _repetitionCount;
  /// Validated immutable frame metadata in the container's original order.
  List<LaunchWebpFrame> get frames => _frames;

  static int _u16(Uint8List b, int p) => b[p] | b[p + 1] << 8;
  static int _u24(Uint8List b, int p) => _u16(b, p) | b[p + 2] << 16;
  static int _u32(Uint8List b, int p) => _u24(b, p) | b[p + 3] << 24;

  static bool _tag(Uint8List b, int p, String expected) =>
      b[p] == expected.codeUnitAt(0) &&
      b[p + 1] == expected.codeUnitAt(1) &&
      b[p + 2] == expected.codeUnitAt(2) &&
      b[p + 3] == expected.codeUnitAt(3);

  /// Refuses unsupported composition before opening any codec or image.
  static LaunchWebpFrames? tryParse(Uint8List bytes) {
    if (bytes.length < 68 || bytes.length > 4 * 1024 * 1024 ||
        !_tag(bytes, 0, 'RIFF') || !_tag(bytes, 8, 'WEBP') ||
        _u32(bytes, 4) != bytes.length - 8) {
      return null;
    }
    if (!_tag(bytes, 12, 'VP8X') || _u32(bytes, 16) != 10 ||
        bytes[20] != 2 || bytes[21] != 0 || bytes[22] != 0 ||
        bytes[23] != 0 || !_tag(bytes, 30, 'ANIM') ||
        _u32(bytes, 34) != 6) {
      return null;
    }
    final int width = _u24(bytes, 24) + 1;
    final int height = _u24(bytes, 27) + 1;
    if (width > 4096 || height > 4096) return null;
    final int loops = _u16(bytes, 42);
    final List<LaunchWebpFrame> frames = <LaunchWebpFrame>[];
    int at = 44;
    while (at < bytes.length) {
      if (frames.length == 256 || at + 8 > bytes.length ||
          !_tag(bytes, at, 'ANMF')) {
        return null;
      }
      final int length = _u32(bytes, at + 4);
      final int start = at + 8;
      final int end = start + length;
      final int next = end + (length & 1);
      if (length < 34 || next > bytes.length ||
          (length.isOdd && bytes[end] != 0) || bytes[start + 15] != 2) {
        return null;
      }
      final int x = _u24(bytes, start) * 2;
      final int y = _u24(bytes, start + 3) * 2;
      final int w = _u24(bytes, start + 6) + 1;
      final int h = _u24(bytes, start + 9) + 1;
      final int ms = _u24(bytes, start + 12);
      if (x + w > width || y + h > height || ms < 11 || ms > 60000 ||
          (frames.isEmpty && (x != 0 || y != 0 || w != width || h != height))) {
        return null;
      }
      final int chunk = start + 16;
      if (!_tag(bytes, chunk, 'VP8 ')) return null;
      final int codedLength = _u32(bytes, chunk + 4);
      final int coded = chunk + 8;
      if (codedLength < 10 || coded + codedLength + (codedLength & 1) != end ||
          (codedLength.isOdd && bytes[end - 1] != 0)) {
        return null;
      }
      // Every stored WebP picture is a VP8 key frame at its declared size.
      if ((bytes[coded] & 1) != 0 || bytes[coded + 3] != 0x9d ||
          bytes[coded + 4] != 0x01 || bytes[coded + 5] != 0x2a ||
          _u16(bytes, coded + 6) != w || _u16(bytes, coded + 8) != h) {
        return null;
      }
      frames.add(LaunchWebpFrame._(x, y, w, h, ms, chunk, end - chunk));
      at = next;
    }
    if (at != bytes.length || frames.length < 2) return null;
    // A caller cannot change bytes after validation or while decoding awaits.
    return LaunchWebpFrames._(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      width,
      height,
      loops == 0 ? -1 : loops - 1,
      frames,
    );
  }

  /// A standalone RIFF wrapper around the original compressed frame chunk.
  Uint8List frameBytes(int index) {
    final LaunchWebpFrame frame = frames[index];
    final int length = 12 + frame._length;
    final Uint8List result = Uint8List(length)
      ..setRange(0, 4, const <int>[82, 73, 70, 70])
      ..setRange(8, 12, const <int>[87, 69, 66, 80])
      ..setRange(12, length, _bytes, frame._offset);
    ByteData.sublistView(result).setUint32(4, length - 8, Endian.little);
    return result;
  }
}

/// One original opaque rectangle and its unmodified display duration.
class LaunchWebpFrame {
  const LaunchWebpFrame._(
    this._x, this._y, this._width, this._height, this._milliseconds,
    this._offset, this._length,
  );

  final int _x;
  final int _y;
  final int _width;
  final int _height;
  final int _milliseconds;
  final int _offset;
  final int _length;

  /// The original horizontal canvas offset in pixels.
  int get x => _x;
  /// The original vertical canvas offset in pixels.
  int get y => _y;
  /// The original canvas or rectangle width in pixels.
  int get width => _width;
  /// The original canvas or rectangle height in pixels.
  int get height => _height;
  /// The original display duration in milliseconds.
  int get milliseconds => _milliseconds;
}

class _RectangleDecoder extends LaunchFilmDecoder {
  _RectangleDecoder(LaunchWebpFrames frames)
      : _frames = frames,
        _frameCount = frames.frames.length,
        _repetitionCount = frames.repetitionCount;

  LaunchWebpFrames? _frames;
  final int _frameCount;
  final int _repetitionCount;
  ui.Image? _canvas;
  int _next = 0;
  bool _pending = false;
  bool _disposed = false;

  @override
  int get frameCount => _frameCount;

  @override
  /// Repeats after the first run, or minus one for an infinite loop.
  int get repetitionCount => _repetitionCount;

  @override
  bool get usesFrameRectangles => true;

  @override
  Future<LaunchFilmFrame> getNextFrame() async {
    final LaunchWebpFrames? frames = _frames;
    if (_disposed || _pending || frames == null) {
      throw StateError('The film decoder is unavailable');
    }
    _pending = true;
    ui.Codec? codec;
    ui.Image? patch;
    ui.Picture? picture;
    try {
      final LaunchWebpFrame frame = frames.frames[_next];
      codec = await ui.instantiateImageCodec(frames.frameBytes(_next));
      if (codec.frameCount != 1) {
        throw StateError('A film rectangle must be still');
      }
      patch = (await codec.getNextFrame()).image;
      if (patch.width != frame.width || patch.height != frame.height) {
        throw StateError('The film rectangle dimensions changed');
      }
      final ui.Image output;
      if (frame.x == 0 && frame.y == 0 &&
          frame.width == frames.width && frame.height == frames.height) {
        output = patch;
        patch = null;
      } else {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..drawImage(_canvas!, ui.Offset.zero, ui.Paint())
          ..drawImage(
            patch,
            ui.Offset(frame.x.toDouble(), frame.y.toDouble()),
            ui.Paint()..blendMode = ui.BlendMode.src,
          );
        picture = recorder.endRecording();
        output = await picture.toImage(frames.width, frames.height);
      }
      _canvas?.dispose();
      _canvas = output;
      _next = (_next + 1) % frameCount;
      return LaunchFilmFrame(
        output.clone(),
        Duration(milliseconds: frame.milliseconds),
      );
    } finally {
      picture?.dispose();
      patch?.dispose();
      codec?.dispose();
      _pending = false;
    }
  }

  @override
  void dispose() {
    if (_pending) throw StateError('A pending film frame still has its owner');
    if (_disposed) return;
    _disposed = true;
    _canvas?.dispose();
    _canvas = null;
    _frames = null;
  }
}
