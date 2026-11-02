import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film_decoder.dart';

/// The original decoder's current wait, without asset or frame payloads.
enum LaunchFilmDecodeStage {
  /// No run has started.
  idle,

  /// A replacement run still awaits its original predecessor.
  previous,

  /// The original asset buffer has not returned.
  asset,

  /// The original codec has not opened.
  codec,

  /// The selected decoder's original frame Future has not returned.
  frame,

  /// The original frame's smaller image has not returned.
  resize,

  /// The original display acknowledgement has not returned.
  display,

  /// The original codec is being disposed.
  disposing,

  /// The original decoder's final cleanup has returned.
  complete,
}

/// The launch animation, played from one animated image a frame at a time.
///
/// It was a Lottie file: 56 JPEG frames of 2560 x 1440 in JSON, every one
/// decoded before the first was drawn and all held until the last, 826 MB
/// for two seconds of a wordmark. The same pictures as an animated WebP are
/// a tenth of the size on disk. Its opaque changed rectangles are decoded
/// individually and placed on the retained canvas; other containers use the
/// engine's original animated codec. [Image] would also play that file, but
/// it loops by the file's count, cannot start part way in or jump to the end,
/// and stops on the platform's reduced-motion flag.
///
/// So the launch goes through [LaunchFilm], which
///
///  * keeps the displayed image and a retained composition canvas, with a
///    temporary rectangle and replacement while the next image is composed.
///    Replaced images and the decoder are disposed, leaving the last frame;
///  * keeps the file's own clock. A frame stays for its own duration; one
///    that decodes late is shown when it is ready, and nothing is dropped
///    to catch up;
///  * stops on the last frame, whatever loop count the file carries;
///  * always moves. Nothing here reads the reduced-motion setting; see
///    `lib/utils/motion_binding.dart`.
///
/// A codec only goes forwards. Starting at frame n means decoding the frames
/// before it. A verified [lastFrameAsset] lets a skip open that same ending
/// directly, after the original pending frame has returned.
class LaunchFilm extends StatefulWidget {
  /// Plays [asset] in all the room its parent gives it.
  const LaunchFilm({
    this.asset = defaultAsset,
    this.bundle,
    this.decodeWidth,
    this.lastFrameAsset,
    this.fit = BoxFit.contain,
    this.autoplay = true,
    this.onDone,
    this.controller,
    super.key,
  });

  /// The launch animation as the wallet ships it.
  static const String defaultAsset = 'assets/images/launch.webp';

  /// The shipped film's independently stored, pixel-identical last frame.
  static const String defaultLastFrameAsset = 'assets/images/launch_end.webp';

  /// The animated image to play. Read again at the start of every run, so
  /// its bytes are not held between two.
  final String asset;

  /// Where [asset] is read from; the [DefaultAssetBundle] when null.
  final AssetBundle? bundle;

  /// The width, in pixels, of the frames it keeps; null keeps them as they
  /// are in the file. For the well on the lock card, which is a few hundred
  /// pixels wide and holds its last frame for as long as the card is up.
  ///
  /// Rectangle composition keeps the file's original canvas dimensions.
  /// The engine fallback also ignores target width for animated images,
  /// so each completed frame is drawn down to this width afterwards.
  /// During that draw, the whole frame and its smaller copy both exist,
  /// beside the one on screen.
  final int? decodeWidth;

  /// A verified still of this film's last frame, used only for a skip.
  ///
  /// Without it the original forward-only codec decodes the remaining frames.
  /// Natural playback never reads it. A pending frame always returns before
  /// its codec is disposed and this still is opened by the same decoder run.
  final String? lastFrameAsset;

  /// How a frame fills the box.
  final BoxFit fit;

  /// Whether it plays from the first frame as soon as it is built. When
  /// false it stays black until the [controller] is told to play.
  final bool autoplay;

  /// Called once for each run that reaches its end: when the last frame has
  /// had its time, at once after [LaunchFilmController.skipToEnd], or when
  /// the file could not be read, so that whoever waits on it is not left
  /// waiting on a black window.
  final VoidCallback? onDone;

  /// Starts it, skips it, and says where it is.
  final LaunchFilmController? controller;

  @override
  State<LaunchFilm> createState() => _LaunchFilmState();
}

/// Drives one [LaunchFilm] and reports where it is. Listeners are told when
/// the frame on screen changes, when the frame count is known, and when a
/// run starts or ends.
class LaunchFilmController extends ChangeNotifier {
  _LaunchFilmState? _state;
  LaunchFilmCleanup? _cleanup;
  bool _cleanupOwnerReplaced = false;

  /// The first actual film State's cleanup, retained after controller detach.
  LaunchFilmCleanup? get cleanup => _cleanup;

  /// A new film cannot erase uncertainty about the first owner's decoder.
  bool get cleanupOwnerReplaced => _cleanupOwnerReplaced;

  /// What was asked for before a [LaunchFilm] held this controller; the
  /// last request only, and it takes the place of autoplay.
  void Function(_LaunchFilmState state)? _asked;

  /// A takeover reports the frame before applying a queued request. A
  /// listener can make a newer request during that report; it must win.
  int _requests = 0;

  int _frame = -1;
  int _frameCount = 0;
  bool _isDone = false;

  /// The index of the frame on screen; -1 before the first is drawn. During
  /// a run started with [play] it is still the old frame's until the first
  /// wanted frame replaces it.
  int get frame => _frame;

  /// How many frames the file has; 0 until a run has opened it.
  int get frameCount => _frameCount;

  /// Whether the last run has ended and nothing more will change until
  /// [play] is called again.
  bool get isDone => _isDone;

  /// Whether the attached original decoder has accepted a skip request.
  bool get skipRequested => _state?._skipping ?? false;

  /// Whether the original decoder has a frame waiting for its display tick.
  bool get framePending => _state?._next != null;

  /// Reads the attached decoder's latched wait without advancing any clock.
  LaunchFilmDecodeStage? get decodeStage => _state?._decodeStage;

  /// Film index whose image is awaited, without requesting another image.
  /// A direct ending decode reports the film's last index.
  int? get decodingFrameIndex => _state?._decodingFrameIndex;

  /// Reads an already-created original ticker without creating or starting it.
  bool get clockTicking {
    final _LaunchFilmState? state = _state;
    return state != null && state._tickerReady && state._ticker.isTicking;
  }

  /// Plays from frame [from] to the end, in place of any run under way.
  ///
  /// The frames before [from] are decoded and thrown away unseen, and the
  /// frame already on screen stays there until frame [from] is ready. A
  /// [from] past the end is the last frame.
  void play({int from = 0}) {
    assert(from >= 0, 'A film has no frame $from.');
    _ask((_LaunchFilmState state) => state._play(from));
  }

  /// Goes to the last frame and holds it, without waiting out the frames
  /// between. With [LaunchFilm.lastFrameAsset] the same last picture is
  /// decoded directly; otherwise the remaining frames are decoded unseen.
  /// Starts a run if none is under way;
  /// does nothing once the attached film has finished. A new film can be
  /// skipped even when this controller still reports a previous one's end.
  void skipToEnd() {
    _ask((_LaunchFilmState state) => state._skipToEnd());
  }

  void _ask(void Function(_LaunchFilmState state) request) {
    _requests += 1;
    final _LaunchFilmState? state = _state;
    if (state == null) {
      _asked = request;
    } else {
      request(state);
    }
  }

  void _report({int? frame, int? frameCount, bool? isDone}) {
    final bool changed =
        (frame != null && frame != _frame) ||
        (frameCount != null && frameCount != _frameCount) ||
        (isDone != null && isDone != _isDone);
    _frame = frame ?? _frame;
    _frameCount = frameCount ?? _frameCount;
    _isDone = isDone ?? _isDone;
    if (changed) {
      notifyListeners();
    }
  }
}

/// Resource cleanup of one actual film State, separate from playback's end.
class LaunchFilmCleanup {
  LaunchFilmCleanup._(this.owner) {
    completion = EntryCaptureCompletion(_finished.future);
  }

  /// Identity of the original State, never a replacement decoder or image.
  final Object owner;
  final Completer<void> _finished = Completer<void>();

  /// Settles only after synchronous image release and the original decoder.
  late final EntryCaptureCompletion completion;
  EntryCaptureCompletion? _decoder;
  Object? _error;
  StackTrace? _stack;
  bool _stateDisposed = false;

  /// Captured before State.dispose invalidates the run or releases a frame.
  EntryCaptureCompletion? get decoder => _decoder;

  /// True only after synchronous image release and State.dispose return.
  bool get stateDisposed => _stateDisposed;

  /// Decoder failures remain private diagnostic identities, even after detach.
  Object? get error => _error ?? _decoder?.error;

  /// Original private stack for the retained cleanup failure.
  StackTrace? get stackTrace => _stack ?? _decoder?.stackTrace;

  void _failed(Object error, StackTrace stack) {
    _error ??= error;
    _stack ??= stack;
  }

  Future<void> _finish() async {
    await _decoder!.completion;
    final Object? failure = error;
    if (failure != null) {
      _finished.completeError(failure, stackTrace);
    } else if (_stateDisposed) {
      _finished.complete();
    }
  }
}

/// A decoded frame waiting for its turn.
class _Frame {
  const _Frame(this.index, this.image, this.duration, {required this.last});

  final int index;
  final ui.Image image;
  final Duration duration;
  final bool last;
}

class _LaunchFilmState extends State<LaunchFilm>
    with SingleTickerProviderStateMixin<LaunchFilm> {
  late final Ticker _ticker = createTicker(_tick);
  late final LaunchFilmCleanup _cleanup = LaunchFilmCleanup._(this);

  /// Used when the widget is given no controller, so the rest of the state
  /// reports to one place either way.
  LaunchFilmController? _ownController;

  LaunchFilmController get _controller =>
      widget.controller ?? (_ownController ??= LaunchFilmController());

  /// The frame on screen.
  ui.Image? _shown;

  /// The frame decoded and not yet shown. There is never a second: the
  /// decoder waits on [_taken] before it asks the codec for another.
  _Frame? _next;
  Completer<void>? _taken;

  /// Counts runs. A decode that comes back to a later number belongs to a
  /// run that was replaced, or to a widget that is gone.
  int _run = 0;

  /// The decoder of the last run started. The next run waits for it, so
  /// there is one codec at a time and its frame in flight is not a third.
  Future<void> _decoder = Future<void>.value();
  LaunchFilmDecodeStage _decodeStage = LaunchFilmDecodeStage.idle;
  int? _decodingFrameIndex;

  bool _started = false;
  bool _running = false;
  bool _tickerReady = false;
  bool _skipping = false;
  bool _onLast = false;

  /// When the frame on screen has had its time, on the ticker's clock.
  /// Null at the start of a run: its first frame waits for nothing.
  Duration? _due;

  @override
  void initState() {
    super.initState();
    _attach(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    // Here and not in initState: a run looks up the asset bundle.
    _started = true;
    final void Function(_LaunchFilmState state)? asked = _controller._asked;
    _controller._asked = null;
    if (asked != null) {
      asked(this);
    } else if (widget.autoplay) {
      _play(0);
    }
  }

  @override
  void didUpdateWidget(LaunchFilm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new asset, bundle or width is picked up by the next run; the one
    // under way plays out the file it opened.
    if (!identical(oldWidget.controller, widget.controller)) {
      final LaunchFilmController old = (oldWidget.controller ?? _ownController!)
        .._state = null;
      final LaunchFilmController next = _controller;
      final void Function(_LaunchFilmState state)? asked = next._asked;
      final int requests = next._requests;
      next._asked = null;
      _attach(next);
      // Told where the film is, as if it had been listening all along.
      next._report(
        frame: old.frame,
        frameCount: old.frameCount,
        isDone: old.isDone,
      );
      // A request made before takeover has the same effect as one made
      // before the first mount, unless a listener has since replaced it.
      if (asked != null && next._requests == requests) {
        asked(this);
      }
    }
  }

  void _attach(LaunchFilmController controller) {
    assert(
      controller._state == null,
      'A LaunchFilmController drives one LaunchFilm.',
    );
    if (controller._cleanup == null) {
      controller._cleanup = _cleanup;
    } else if (!identical(controller._cleanup, _cleanup)) {
      controller._cleanupOwnerReplaced = true;
    }
    controller._state = this;
  }

  void _play(int from, {bool skip = false}) {
    final int run = _run += 1;
    _decodingFrameIndex = null;
    _dropNext();
    _running = true;
    _skipping = skip;
    _onLast = false;
    _due = null;
    _controller._report(isDone: false);
    // Stopped and started, so each run reads its time from zero.
    _ticker
      ..stop()
      ..start();
    _tickerReady = true;
    _decoder = _decode(
      run,
      from,
      widget.bundle ?? DefaultAssetBundle.of(context),
      widget.asset,
      widget.decodeWidth,
      widget.lastFrameAsset,
      _decoder,
    );
  }

  void _skipToEnd() {
    if (!_running) {
      if (_run == 0 || !_controller.isDone) {
        _play(0, skip: true);
      }
      return;
    }
    _skipping = true;
    // A frame waiting for its time is one of those skipped, unless it is
    // the last, which the next tick shows.
    if (_next?.last == false) {
      _dropNext();
    }
  }

  /// Throws away the frame not yet shown and lets the decoder go on.
  void _dropNext() {
    _next?.image.dispose();
    _next = null;
    final Completer<void>? taken = _taken;
    _taken = null;
    if (taken != null && !taken.isCompleted) {
      taken.complete();
    }
  }

  Future<T> _observeDecode<T>(
    int run,
    LaunchFilmDecodeStage stage,
    Future<T> original,
  ) {
    if (run == _run) _decodeStage = stage;
    return original;
  }

  Future<void> _decode(
    int run,
    int from,
    AssetBundle bundle,
    String asset,
    int? width,
    String? lastFrameAsset,
    Future<void> before,
  ) async {
    await _observeDecode(run, LaunchFilmDecodeStage.previous, before);
    if (run != _run) {
      return;
    }
    LaunchFilmDecoder? codec;
    try {
      final LaunchFilmDecoder filmCodec =
          await _observeDecode<LaunchFilmDecoder>(
            run,
            LaunchFilmDecodeStage.codec,
            LaunchFilmDecoder.fromData(
              await _observeDecode(
                run,
                LaunchFilmDecodeStage.asset,
                bundle.load(asset),
              ),
              // Keep the original canvas until the existing shrink.
              targetWidth: width,
            ),
          );
      codec = filmCodec;
      final int count = filmCodec.frameCount;
      final int first = math.min(from, count - 1);
      if (run == _run) {
        _controller._report(frameCount: count);
      }
      // The codec starts again from its first frame after its last, so the
      // count ends the run here, not the codec.
      for (int index = 0; index < count && run == _run; index += 1) {
        _decodingFrameIndex = index;
        // Never disposed with this pending: the engine then leaves the
        // future uncompleted and the frame it was decoding with no owner.
        final LaunchFilmFrame info = await _observeDecode(
          run, LaunchFilmDecodeStage.frame, filmCodec.getNextFrame(),
        );
        bool last = index == count - 1;
        ui.Image image = info.image;
        if (run == _run && _skipping && !last && lastFrameAsset != null) {
          final int fullWidth = image.width;
          final int fullHeight = image.height;
          image.dispose();
          // getNextFrame has actually returned. Disposing earlier leaves
          // that engine Future pending and would lose its cleanup owner.
          filmCodec.dispose();
          codec = null;
          _decodingFrameIndex = count - 1;
          codec = await _observeDecode<LaunchFilmDecoder>(
            run, LaunchFilmDecodeStage.codec,
            LaunchFilmDecoder.fromBuffer(
              await _observeDecode(
                run, LaunchFilmDecodeStage.asset,
                bundle.loadBuffer(lastFrameAsset),
              ),
              // Keep the full source dimensions for the identity check;
              // the existing shrink below still owns the displayed size.
            ),
          );
          if (codec.frameCount != 1) {
            throw StateError('The launch ending must be one still frame');
          }
          final LaunchFilmFrame ending = await _observeDecode(
            run, LaunchFilmDecodeStage.frame, codec.getNextFrame(),
          );
          image = ending.image;
          if (image.width != fullWidth || image.height != fullHeight) {
            image.dispose();
            throw StateError('The launch ending dimensions changed');
          }
          index = count - 1;
          last = true;
        }
        if (_unwanted(run, index, first, last: last)) {
          image.dispose();
          continue;
        }
        if (width != null && image.width > width) {
          image = await _observeDecode(
            run, LaunchFilmDecodeStage.resize, _shrink(image, width),
          );
          // The skip may have come while it was being drawn down.
          if (_unwanted(run, index, first, last: last)) {
            image.dispose();
            continue;
          }
        }
        final Completer<void> taken = Completer<void>();
        _next = _Frame(index, image, info.duration, last: last);
        _taken = taken;
        await _observeDecode(run, LaunchFilmDecodeStage.display, taken.future);
      }
    } on Object catch (error, stack) {
      _cleanup._failed(error, stack);
      if (run == _run) {
        _fail(error, stack, asset);
      }
    } finally {
      if (run == _run) _decodeStage = LaunchFilmDecodeStage.disposing;
      codec?.dispose();
      if (run == _run) _decodeStage = LaunchFilmDecodeStage.complete;
    }
  }

  bool _unwanted(int run, int index, int first, {required bool last}) =>
      run != _run || (!last && (index < first || _skipping));

  /// [image] at [width] pixels wide, and [image] disposed. Medium samples a
  /// mipmap, so the pixels dropped are averaged and not skipped.
  static Future<ui.Image> _shrink(ui.Image image, int width) async {
    final int height = math.max(
      1,
      (image.height * width / image.width).round(),
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final ui.Picture picture = recorder.endRecording();
    try {
      // Not toImageSync: that one draws when it is first used, and keeps
      // the whole frame alive until then.
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
      image.dispose();
    }
  }

  void _tick(Duration elapsed) {
    final _Frame? next = _next;
    final Duration? due = _due;
    if (next != null && (due == null || _skipping || elapsed >= due)) {
      // A frame up to its own length late keeps the file's clock, so the
      // wait for a vsync is not added to every frame after it. One later
      // than that was held up by its decode, and the clock starts again
      // from it: there is nothing decoded ahead to catch up with.
      final bool onTime = due != null && elapsed - due <= next.duration;
      _due = (onTime ? due : elapsed) + next.duration;
      _onLast = next.last;
      _next = null;
      // The render object holds its own handle on the old frame until this
      // build replaces it, so ours can go now.
      setState(() {
        _shown?.dispose();
        _shown = next.image;
      });
      _controller._report(frame: next.index);
      _taken?.complete();
      _taken = null;
    }
    if (_onLast && (_skipping || elapsed >= _due!)) {
      _end();
    }
  }

  void _end() {
    _running = false;
    _onLast = false;
    _ticker.stop();
    _controller._report(isDone: true);
    widget.onDone?.call();
  }

  /// A file that cannot be read or decoded ends the run where it stands:
  /// the launch is a wait before the wallet, not a reason to keep it shut.
  void _fail(Object error, StackTrace stack, String asset) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'launch film',
        context: ErrorDescription('while playing $asset'),
      ),
    );
    _end();
  }

  @override
  void dispose() {
    // The decoder sees the new number when its frame comes back, disposes
    // that frame and its codec, and stops.
    _cleanup._decoder = EntryCaptureCompletion(_decoder);
    try {
      _run += 1;
      _dropNext();
      _ticker.dispose();
      _shown?.dispose();
      _shown = null;
      _controller._state = null;
      _ownController?.dispose();
      super.dispose();
      _cleanup._stateDisposed = true;
    } on Object catch (error, stack) {
      _cleanup._failed(error, stack);
      rethrow;
    } finally {
      unawaited(_cleanup._finish());
    }
  }

  @override
  Widget build(BuildContext context) {
    // The frames are drawn on black in both themes, so the box is black
    // before the first of them and round one that does not fill it.
    return RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: SizedBox.expand(
          child: RawImage(
            image: _shown,
            // Drawn with RawImage's own filter, medium: the one that
            // averages when a frame is drawn smaller than it is.
            fit: widget.fit,
          ),
        ),
      ),
    );
  }
}
