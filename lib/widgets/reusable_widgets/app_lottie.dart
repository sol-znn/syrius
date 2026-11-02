import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:cryptography/dart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hex/hex.dart';
import 'package:lottie/lottie.dart';
import 'package:zenon_syrius_wallet_flutter/utils/reference_artwork_source.dart';

/// The animations the wallet ships, and every Lottie the wallet draws.
///
/// `Lottie.asset` parses the file on the UI isolate, then decodes its images
/// one after another, and draws nothing until the last is done. Three of
/// these files are slide shows of 1000 px frames, megabytes of base64 each:
/// opening Tokens parsed 3.5 MB between two frames and decoded 184 MB of
/// pixels for a coin 64 px wide, and that coin, a frame sampled at a
/// sixteenth of its size, came out as noise.
///
/// So every call site goes through [AppLottie], which
///
///  * parses in [Isolate.run] and decodes the frames together, so the page
///    that asks for an animation never waits on it;
///  * keeps what it loaded, so a second visit draws on its first frame, and
///    [AppLottie.preload] makes the first visit a second one;
///  * picks the file built for the size it is drawn at
///    (`tool/lottie_reencode.py` writes a small and a full one from each
///    master), and draws it with mipmaps, so shrinking averages the pixels
///    it drops instead of skipping them;
///  * gives back the big ones when the last widget showing them goes. The
///    launch animation alone is 826 MB decoded, and the package's own cache
///    held on to it for the life of the process.
enum AppLottieAsset {
  /// The globe turning on Welcome.
  globe('ic_anim_welcome'),

  /// The ZTS coin.
  zts('ic_anim_zts', smallEdge: 128),

  /// The pillar.
  pillar('ic_anim_pillar', smallEdge: 208),

  /// The sentinel.
  sentinel('ic_anim_sentinel', smallEdge: 208),

  /// The eye on a card whose content is hidden. A vector, on every page
  /// that has cards.
  eye('ic_anim_eye', keep: true),

  /// The empty box where there is nothing to show. A vector.
  noData('ic_anim_no_data', keep: true),

  /// The map at the end of onboarding. A vector.
  map('ic_anim_map'),

  /// The bolt tracing its outline: the status strip's mark while plasma is
  /// generated. A vector of 4 KB, kept so each generation starts drawn.
  plasmaGeneration('ic_anim_plasma_generation', keep: true),

  /// The launch animation: 56 frames of 2560 x 1440.
  splash('ic_anim_splash');

  const AppLottieAsset(this._name, {this.smallEdge, this.keep = false});

  final String _name;

  /// The edge, in pixels, of the composition in this animation's `_small`
  /// file; null when it has one file only. The same numbers as `VARIANTS`
  /// in `tool/lottie_reencode.py`.
  final int? smallEdge;

  /// Whether the file stays loaded when nothing shows it. True for what is
  /// small and on the main pages; the small files are always kept.
  final bool keep;

  /// The small file is used up to this much enlargement. Past it the full
  /// one is sharper and worth its memory.
  static const double _kSmallStretch = 1.3;

  /// The file to draw at [edge] logical pixels on a display of
  /// [devicePixelRatio]. The full file when [edge] is null. The 48 px strip
  /// always uses the small file, including on a high-density display.
  String path(double? edge, double devicePixelRatio) {
    final int? small = smallEdge;
    final bool fits =
        small != null &&
        edge != null &&
        (edge <= 48 || edge * devicePixelRatio <= small * _kSmallStretch);
    return 'assets/lottie/$_name${fits ? '_small' : ''}.json';
  }

  bool _keeps(String path) => keep || path.endsWith('_small.json');

  bool get _isObject => this == zts || this == pillar || this == sentinel;

  bool get _loops => this == globe || this == map || this == plasmaGeneration;
}

/// One of the wallet's animations, on its own layer.
///
/// Until the file is loaded it is an empty box of the same size, so nothing
/// round it moves when the first frame arrives.
class AppLottie extends StatelessWidget {
  /// Draws [asset] in a square of [size], or as large as its parent allows
  /// when [size] is null.
  const AppLottie(
    this.asset, {
    this.size,
    this.controller,
    this.repeat = true,
    this.fit,
    this.onLoaded,
    super.key,
  });

  /// Which animation.
  final AppLottieAsset asset;

  /// Its width and height, in logical pixels.
  final double? size;

  /// Drives the animation when given; it plays by itself otherwise. The
  /// caller owns a supplied controller, including its timing and lifetime.
  final Animation<double>? controller;

  /// Whether a loop starts again when it ends. Only the globe, map and
  /// plasma-generation bolt can loop. Objects play once and replay on
  /// hover, so an assembly never keeps moving beside an amount. Ignored
  /// with a [controller].
  final bool repeat;

  /// How it fills its box.
  final BoxFit? fit;

  /// Called once, when the animation is ready to draw.
  final ValueChanged<LottieComposition>? onLoaded;

  /// Loads, in the background, what the main pages draw: the coin and the
  /// two nodes at their small size, and the eye. A megabyte of files and
  /// about 20 MB of pixels, kept from then on.
  static Future<void> preload({AssetBundle? bundle}) async {
    for (final AppLottieAsset asset in const <AppLottieAsset>[
      AppLottieAsset.zts,
      AppLottieAsset.pillar,
      AppLottieAsset.sentinel,
      AppLottieAsset.eye,
    ]) {
      // One at a time: each is an isolate and a burst of decodes, and
      // nothing is waiting for the last of them.
      final String path = asset.path(0, 1);
      try {
        await _Entry.of(path, bundle ?? rootBundle, keep: true).future;
      } on Object {
        // The page that needs it will ask again and report it.
      }
    }
  }

  /// Loads [path] and keeps it, as [preload] does for its four.
  @visibleForTesting
  static Future<LottieComposition> debugLoad(String path) =>
      _Entry.of(path, rootBundle, keep: true).future;

  /// Whether [path] is loaded and can be drawn without waiting.
  @visibleForTesting
  static bool isLoaded(String path) => _Entry._all[path]?.composition != null;

  /// Forgets every file not in use, kept or not.
  @visibleForTesting
  static void debugClear() {
    for (final _Entry entry in _Entry._all.values.toList()) {
      entry
        ..keep = false
        .._releaseIfUnused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Read the space the parent actually grants: a 48 px request in
          // a 24 px slot is still too small to show an assembling object.
          final double? edge;
          if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
            edge = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
          } else if (constraints.hasBoundedWidth) {
            edge = constraints.maxWidth;
          } else if (constraints.hasBoundedHeight) {
            edge = constraints.maxHeight;
          } else {
            edge = null;
          }
          // The eye and no-data mark are functional at smaller sizes. The
          // assembling objects become noise below this edge, so do not
          // load or decode them just to paint that noise.
          if (asset._isObject && edge != null && edge < 40) {
            return const SizedBox();
          }
          return _Player(configuration: this, edge: edge);
        },
      ),
    );
  }
}

class _Player extends StatefulWidget {
  const _Player({required this.configuration, required this.edge});

  final AppLottie configuration;
  final double? edge;

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements ReferenceArtworkSource {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // The composition keeps its own length even when platform animation
    // effects are off. Motion is how the wallet reports a state change.
    animationBehavior: AnimationBehavior.preserve,
  );
  _Entry? _entry;
  LottieComposition? _composition;
  bool _pageEnabled = false;
  bool _foreground = true;
  bool _looping = false;
  ReferenceArtworkFrame? _referenceFrame;
  Animation<double>? _referenceProgress;
  Animation<double>? _paintedController;
  int _referenceEpoch = 0;

  @override
  ReferenceArtworkKind get referenceArtworkKind =>
      ReferenceArtworkKind.welcomeGlobe;

  @override
  Object get referenceArtworkGeneration => _entry ?? this;

  @override
  Future<Object?>? get referenceArtworkReadiness => _entry?.future;

  @override
  ReferenceArtworkFrame? captureReferenceArtwork() {
    final _Entry? entry = _entry;
    final LottieComposition? composition = _composition;
    if (!mounted || !_active || !_clock.isAnimating || entry == null ||
        composition == null || _referenceFrame != null ||
        _configuration.asset != AppLottieAsset.globe ||
        _configuration.controller != null) {
      return null;
    }
    // The parser subtracts .01 from op. Match lottie-web's integer frame,
    // then avoid the default composition-rate rounding during this sample.
    final double duration = composition.durationFrames;
    if (!duration.isFinite || duration <= 0) return null;
    final int count = (duration + 0.01).floor();
    final int index = (count * 0.4).floor();
    final double progress = index / duration;
    if (count <= 0 || count > 1000000 ||
        !progress.isFinite || progress < 0 || progress > 1) {
      return null;
    }
    final AnimationController original = _clock;
    final int epoch = _referenceEpoch;
    final Animation<double> sample = AlwaysStoppedAnimation<double>(progress);
    bool originalCurrent() => mounted && _active &&
        _referenceEpoch == epoch &&
        identical(_entry, entry) && identical(_composition, composition) &&
        identical(_clock, original) && _configuration.controller == null &&
        _configuration.asset == AppLottieAsset.globe;
    late final ReferenceArtworkFrame frame;
    frame = ReferenceArtworkFrame(
      owner: this, generation: entry, kind: referenceArtworkKind,
      observation: <String, Object>{
        'kind': 'welcome_globe', 'frame': index, 'frame_count': count,
      },
      current: () => originalCurrent() && original.isAnimating &&
          identical(_referenceFrame, frame) &&
          identical(_referenceProgress, sample),
      observed: () => identical(_paintedController, sample),
      restore: () => setState(() {
        _referenceFrame = null;
        _referenceProgress = null;
      }),
      restoration: () => originalCurrent() && _referenceFrame == null &&
          _referenceProgress == null &&
          identical(_paintedController, original),
    );
    setState(() {
      _referenceFrame = frame;
      _referenceProgress = sample;
    });
    return frame;
  }

  AppLottie get _configuration => widget.configuration;

  bool get _active => _pageEnabled && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageEnabled = TickerMode.valuesOf(context).enabled;
    if (_active) {
      _resolve();
    }
    _followPlayback();
  }

  @override
  void didUpdateWidget(_Player oldWidget) {
    super.didUpdateWidget(oldWidget);
    final AppLottie old = oldWidget.configuration;
    if (old.asset != _configuration.asset ||
        !identical(old.controller, _configuration.controller)) {
      _referenceEpoch++;
      _referenceFrame = null;
      _referenceProgress = null;
      _clock
        ..stop()
        ..value = 0;
      _looping = false;
    }
    if (_active) {
      _resolve();
    }
    _followPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_active) {
      // A widget mounted on a hidden page does not start loading until
      // that page appears. A resumed one keeps the frame it had reached.
      // A cached composition can resolve synchronously; lifecycle changes
      // do not otherwise rebuild the placeholder that was showing.
      setState(_resolve);
    }
    _followPlayback();
  }

  void _resolve() {
    final String path = _configuration.asset.path(
      widget.edge,
      MediaQuery.devicePixelRatioOf(context),
    );
    if (_entry?.path == path) {
      return;
    }
    final _Entry entry = _Entry.of(
      path,
      DefaultAssetBundle.of(context),
      keep: _configuration.asset._keeps(path),
    )..users += 1;
    _entry?.release();
    _entry = entry;
    _composition = entry.composition;
    if (_composition != null) {
      _followPlayback();
      // Not from inside a build: what it calls may rebuild its caller.
      WidgetsBinding.instance.addPostFrameCallback((_) => _announce(entry));
      return;
    }
    unawaited(
      entry.future.then((LottieComposition composition) {
        if (mounted && identical(_entry, entry)) {
          setState(() => _composition = composition);
          _followPlayback();
          _announce(entry);
        }
      }, onError: (Object _) {}),
    );
  }

  void _announce(_Entry entry) {
    final LottieComposition? composition = entry.composition;
    if (mounted && identical(_entry, entry) && composition != null) {
      _configuration.onLoaded?.call(composition);
    }
  }

  void _followPlayback() {
    final LottieComposition? composition = _composition;
    if (!_active || composition == null || _configuration.controller != null) {
      _clock.stop();
      return;
    }
    _clock.duration = composition.duration;
    final bool loop = _configuration.repeat && _configuration.asset._loops;
    if (loop) {
      if (!_clock.isAnimating || !_looping) {
        _clock.repeat();
      }
    } else if (_clock.value < 1 && (!_clock.isAnimating || _looping)) {
      _clock.forward();
    }
    _looping = loop;
  }

  void _replay() {
    if (_active && _composition != null && _configuration.controller == null) {
      _clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    _entry?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LottieComposition? composition = _composition;
    if (composition == null) {
      return SizedBox(
        width: _configuration.size,
        height: _configuration.size,
      );
    }
    // Lottie puts a RepaintBoundary round itself, so a frame of the
    // animation repaints this box and not the page.
    final Animation<double> paintedController =
        _referenceProgress ?? _configuration.controller ?? _clock;
    _paintedController = paintedController;
    final Widget animation = Lottie(
      composition: composition,
      controller: paintedController,
      frameRate: _referenceProgress == null ? null : FrameRate.max,
      width: _configuration.size,
      height: _configuration.size,
      // Playback belongs to the preserving clock above. A second internal
      // controller would hide its duration and keep ticking while hidden.
      animate: false,
      repeat: false,
      fit: _configuration.fit,
      // Medium is the one setting that samples a mipmap. Low takes four
      // texels wherever the pixel lands, and high is a bicubic for
      // enlarging: both alias when the frame is drawn smaller than it is.
      filterQuality: FilterQuality.medium,
    );
    if (_configuration.asset._isObject && _configuration.controller == null) {
      return MouseRegion(
        opaque: false,
        onEnter: (_) => _replay(),
        child: animation,
      );
    }
    return animation;
  }
}

const String _welcomePath = 'assets/lottie/ic_anim_welcome.json';
const String _welcomeOriginalSha =
    'cb655bfa87969f8c91fd45f57fb03e1c592cc524f7e11bced97b03f4b69114af';

bool _welcomeShapeTypes(List<dynamic> items, List<String> expected) {
  if (items.length != expected.length) return false;
  for (int index = 0; index < items.length; index++) {
    final Object? item = items[index];
    if (item is! Map<String, dynamic> || item['ty'] != expected[index]) {
      return false;
    }
  }
  return true;
}

bool _welcomeIdentity(Map<String, dynamic> value) {
  if (value['ty'] != 'tr') return false;
  const Map<String, Object> identity = <String, Object>{
    'p': <int>[0, 0], 'a': <int>[0, 0], 's': <int>[100, 100],
    'r': 0, 'o': 100, 'sk': 0, 'sa': 0,
  };
  for (final MapEntry<String, Object> part in identity.entries) {
    final Object? channel = value[part.key];
    if (channel is! Map<String, dynamic> || channel['a'] != 0) return false;
    final Object? actual = channel['k'];
    final Object expected = part.value;
    if (actual is List<Object?> && expected is List<Object?>) {
      if (actual.length != expected.length) return false;
      for (int index = 0; index < actual.length; index++) {
        if (actual[index] != expected[index]) return false;
      }
    } else if (actual != expected) {
      return false;
    }
  }
  return true;
}

// The Dart renderer ignores these nested individual trims without a sibling
// stroke. Scope compatibility to the exact bundled original. Its bytes, image
// data, keyframe curves, duration and application playback owner stay intact.
Uint8List _welcomeTrimCompatibility(Uint8List bytes, String path) {
  if (path != _welcomePath || bytes.length != 2189249 ||
      HEX.encode(const DartSha256().hashSync(bytes).bytes) !=
          _welcomeOriginalSha) {
    return bytes;
  }
  final Map<String, dynamic> value =
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final List<dynamic> layers = value['layers'] as List<dynamic>;
  for (int layerIndex = 0; layerIndex < 2; layerIndex++) {
    final Map<String, dynamic> layer =
        layers[layerIndex] as Map<String, dynamic>;
    final List<dynamic> shapes = layer['shapes'] as List<dynamic>;
    final Map<String, dynamic> target =
        shapes[layerIndex == 0 ? 1 : 0] as Map<String, dynamic>;
    if (target['nm'] != 'animatred line') return bytes;
    final List<dynamic> outer = target['it'] as List<dynamic>;
    if (!_welcomeShapeTypes(outer, <String>['gr', 'gr', 'st', 'tr'])) {
      return bytes;
    }
    final Map<String, dynamic> stroke = outer[2] as Map<String, dynamic>;
    for (int index = 0; index < 2; index++) {
      final Map<String, dynamic> group = outer[index] as Map<String, dynamic>;
      final List<dynamic> items = group['it'] as List<dynamic>;
      if (!_welcomeShapeTypes(items, <String>['gr', 'tm', 'tr'])) return bytes;
      final Map<String, dynamic> inner = items[0] as Map<String, dynamic>;
      final List<dynamic> paths = inner['it'] as List<dynamic>;
      if (!_welcomeShapeTypes(paths, <String>['el', 'el', 'tr']) ||
          !_welcomeIdentity(paths[2] as Map<String, dynamic>) ||
          !_welcomeIdentity(items[2] as Map<String, dynamic>)) {
        return bytes;
      }
      final Map<String, dynamic> trim = items[1] as Map<String, dynamic>;
      if (trim['m'] != 2) return bytes;
      final dynamic start = trim['s'];
      trim['s'] = trim['e'];
      trim['e'] = start;
      group['it'] = <dynamic>[
        ...paths.take(2), trim, jsonDecode(jsonEncode(stroke)), items[2],
      ];
    }
    target['it'] = <dynamic>[outer[0], outer[1], outer[3]];
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

/// One loaded file and who is showing it.
class _Entry {
  _Entry._(this.path, this.keep, AssetBundle bundle) {
    future = _load(path, bundle).then((LottieComposition loaded) {
      composition = loaded;
      // Nobody waited for it.
      _releaseIfUnused();
      return loaded;
    });
    // A file that fails is asked for again by the next widget.
    unawaited(
      future.then<void>((_) {}, onError: (Object _) => _all.remove(path)),
    );
  }

  /// The entry for [path], loading it if nothing has yet. Kept from then
  /// on if any caller asks for that.
  factory _Entry.of(String path, AssetBundle bundle, {required bool keep}) {
    final _Entry entry = _all[path] ??= _Entry._(path, keep, bundle);
    return entry..keep = entry.keep || keep;
  }

  static final Map<String, _Entry> _all = <String, _Entry>{};

  final String path;
  bool keep;
  int users = 0;
  late final Future<LottieComposition> future;
  LottieComposition? composition;

  void release() {
    users -= 1;
    _releaseIfUnused();
  }

  void _releaseIfUnused() {
    final LottieComposition? loaded = composition;
    if (keep || users > 0 || loaded == null) {
      return;
    }
    _all.remove(path);
    // The frames already painted hold their own reference; this lets go of
    // ours now, not when the collector comes round to it.
    for (final LottieImageAsset image in loaded.images.values) {
      image.loadedImage?.dispose();
      image.loadedImage = null;
    }
  }

  static Future<LottieComposition> _load(
    String path,
    AssetBundle bundle,
  ) async {
    final ByteData data = await bundle.load(path);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final (LottieComposition composition, Map<String, Uint8List> frames) =
        await Isolate.run(_parser(bytes, path), debugName: 'lottie-parse');
    // The engine decodes on its own threads, several at a time; waiting for
    // each before asking for the next made 46 frames take 46 turns.
    await Future.wait(<Future<void>>[
      for (final MapEntry<String, Uint8List> frame in frames.entries)
        _decode(frame.value).then((ui.Image? image) {
          composition.images[frame.key]?.loadedImage = image;
        }),
    ]);
    return composition;
  }

  // Built here, not inline in [_load], so the closure sent to the isolate
  // holds the bytes and their original asset path, and nothing else.
  static (LottieComposition, Map<String, Uint8List>) Function() _parser(
    Uint8List bytes, String path,
  ) =>
      () => _parse(bytes, path);

  /// The composition, and its embedded images as bytes. The images go into
  /// the composition without their base64 text, which is otherwise kept, a
  /// third larger than the image, for as long as the composition is.
  static (LottieComposition, Map<String, Uint8List>) _parse(
    Uint8List bytes, String path,
  ) {
    final LottieComposition composition = LottieComposition.parseJsonBytes(
      _welcomeTrimCompatibility(bytes, path),
    );
    final Map<String, Uint8List> frames = <String, Uint8List>{};
    for (final LottieImageAsset image in composition.images.values.toList()) {
      final String uri = image.fileName;
      final int comma = uri.indexOf(',');
      if (!uri.startsWith('data:') || comma < 0) {
        continue;
      }
      frames[image.id] = base64.decode(uri.substring(comma + 1));
      composition.images[image.id] = LottieImageAsset(
        width: image.width,
        height: image.height,
        id: image.id,
        fileName: '',
        dirName: '',
      );
    }
    return (composition, frames);
  }

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Object {
      // A frame that will not decode is a frame not drawn.
      return null;
    }
  }
}
