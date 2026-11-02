import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cryptography/dart.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/shaders/shader_clock.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/entry_field.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/reference_artwork_source.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/window_frame.dart';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith('assets/lottie/')) return rootBundle.load(key);
    return ByteData.sublistView(utf8.encode(
      '{"v":"5.7.4","fr":60,"ip":0,"op":120,"w":64,"h":64,'
      '"nm":"Artwork owner fixture","ddd":0,"assets":[],"layers":[]}',
    ));
  }
}

Widget _host(Widget child) => DefaultAssetBundle(
  bundle: _Bundle(),
  child: MaterialApp(theme: AppTheme.darkTheme, home: child),
);

ReferenceArtworkSource _source(WidgetTester tester) =>
    tester.allStates.whereType<ReferenceArtworkSource>().single;

Future<void> _loaded(WidgetTester tester) async {
  final Future<Object?>? original = _source(tester).referenceArtworkReadiness;
  expect(original, isNotNull);
  final EntryCaptureCompletion observed = EntryCaptureCompletion(original!);
  for (int frame = 0; frame < 200 &&
      observed.status == EntryCaptureStatus.pending; frame++) {
    await tester.runAsync<void>(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(observed.status, EntryCaptureStatus.succeeded);
  await tester.pump();
  expect(find.byType(Lottie), findsOneWidget);
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final Finder painter = find.descendant(
    of: find.byType(EntryField), matching: find.byType(RepaintBoundary),
  );
  final RenderRepaintBoundary original =
      tester.renderObject<RenderRepaintBoundary>(painter);
  return (await tester.runAsync<Uint8List>(() async {
    final ui.Image image = await original.toImage();
    try {
      final ByteData? data = await image.toByteData();
      if (data == null) throw StateError('Original artwork pixels unavailable');
      return Uint8List.fromList(data.buffer.asUint8List(
        data.offsetInBytes, data.lengthInBytes,
      ));
    } finally {
      image.dispose();
    }
  }))!;
}

const String _trimAsset = 'assets/lottie/ic_anim_welcome.json';
const String _trimSha =
    'cb655bfa87969f8c91fd45f57fb03e1c592cc524f7e11bced97b03f4b69114af';
const int _trimEdge = 470;
const int _trimFrame = 720;

String _trimHash(Uint8List bytes) =>
    HEX.encode(const DartSha256().hashSync(bytes).bytes);

Future<Uint8List> _trimRender(LottieComposition composition) async {
  final LottieDrawable drawable = LottieDrawable(
    composition, frameRate: FrameRate.max,
  )
    ..filterQuality = ui.FilterQuality.medium
    ..setProgress(_trimFrame / composition.durationFrames);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder)
    ..clipRect(const ui.Rect.fromLTWH(0, 0, 470, 470))
    ..translate(-(836 - 470) / 2, 0);
  drawable.draw(canvas, const ui.Rect.fromLTWH(0, 0, 836, 470),
      fit: BoxFit.contain, alignment: Alignment.center);
  final ui.Picture picture = recorder.endRecording();
  try {
    final ui.Image image = await picture.toImage(_trimEdge, _trimEdge);
    try {
      final ByteData data = (await image.toByteData())!;
      return Uint8List.fromList(data.buffer.asUint8List(
        data.offsetInBytes, data.lengthInBytes,
      ));
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _trimReference(String theme) async {
  final File original = File(
    'mockups/redesign/shots/44-welcome-$theme.png',
  );
  expect(await original.length(), lessThan(1024 * 1024));
  final Uint8List encoded = await original.readAsBytes();
  expect(_trimHash(encoded), theme == 'dark'
      ? '4ffec4db314a53d10ea672cc57e7f7e931b0824bea34ca410522811b679c2181'
      : '4698832240fb65ae6880c1b0a38bbfd777e3670721239828a1738bbf6d91b08c');
  final ui.Codec codec = await ui.instantiateImageCodec(encoded);
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      expect(image.width, 1280);
      expect(image.height, 780);
      final ByteData data = (await image.toByteData())!;
      final Uint8List rgba = data.buffer.asUint8List(
        data.offsetInBytes, data.lengthInBytes,
      );
      // The original 906 px row is centred in 1280 px. Its 470 px globe
      // viewport is centred in the 748 px body beneath the 32 px caption.
      final Uint8List crop = Uint8List(_trimEdge * _trimEdge * 4);
      for (int y = 0; y < _trimEdge; y++) {
        final int offset = ((171 + y) * 1280 + 187) * 4;
        crop.setRange(y * _trimEdge * 4, (y + 1) * _trimEdge * 4,
            rgba, offset);
      }
      return crop;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

List<bool> _trimGreen(Uint8List rgba, int threshold) => <bool>[
  for (int offset = 0; offset < rgba.length; offset += 4)
    rgba[offset + 3] > 0 && rgba[offset + 1] >= threshold &&
        rgba[offset + 1] > rgba[offset] + 20 &&
        rgba[offset + 1] > rgba[offset + 2] + 20,
];

Map<String, int> _trimOverlap(List<bool> actual, List<bool> reference) {
  int present = 0;
  int expected = 0;
  int overlap = 0;
  for (int index = 0; index < actual.length; index++) {
    if (actual[index]) present++;
    if (reference[index]) expected++;
    if (actual[index] && reference[index]) overlap++;
  }
  return <String, int>{'present': present, 'expected': expected,
    'overlap': overlap, 'extra': present - overlap,
    'missing': expected - overlap};
}

const List<String> _pathModes = <String>[
  'channels', 'nested', 'flattened', 'flattened_sorted',
];

void _pathIdentity(Map<String, dynamic> value) {
  expect(value['ty'], 'tr');
  final Map<String, Object> identity = <String, Object>{
    'p': <int>[0, 0], 'a': <int>[0, 0], 's': <int>[100, 100],
    'r': 0, 'o': 100, 'sk': 0, 'sa': 0,
  };
  for (final MapEntry<String, Object> part in identity.entries) {
    final Map<String, dynamic> channel =
        value[part.key] as Map<String, dynamic>;
    expect(channel['a'], 0);
    expect(channel['k'], part.value);
  }
}

LottieComposition _pathVariant(Uint8List bytes, String mode) {
  expect(_pathModes, contains(mode));
  final Map<String, dynamic> value =
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final List<dynamic> layers = value['layers'] as List<dynamic>;
  int promoted = 0;
  int flattened = 0;
  int swapped = 0;
  for (int layerIndex = 0; layerIndex < 2; layerIndex++) {
    final Map<String, dynamic> layer =
        layers[layerIndex] as Map<String, dynamic>;
    final List<dynamic> shapes = layer['shapes'] as List<dynamic>;
    final Map<String, dynamic> target =
        shapes[layerIndex == 0 ? 1 : 0] as Map<String, dynamic>;
    expect(target['nm'], 'animatred line');
    final List<dynamic> outer = target['it'] as List<dynamic>;
    expect(
      outer.map((dynamic item) => (item as Map<String, dynamic>)['ty']),
      <String>['gr', 'gr', 'st', 'tr'],
    );
    final Map<String, dynamic> stroke = outer[2] as Map<String, dynamic>;
    for (int index = 0; index < 2; index++) {
      final Map<String, dynamic> group = outer[index] as Map<String, dynamic>;
      final List<dynamic> items = group['it'] as List<dynamic>;
      expect(
        items.map((dynamic item) => (item as Map<String, dynamic>)['ty']),
        <String>['gr', 'tm', 'tr'],
      );
      final Map<String, dynamic> trim = items[1] as Map<String, dynamic>;
      expect(trim['m'], 2);
      if (mode == 'channels' || mode == 'flattened_sorted') {
        final dynamic start = trim['s'];
        trim['s'] = trim['e'];
        trim['e'] = start;
        swapped++;
      }
      if (mode != 'channels') {
        final Map<String, dynamic> inner =
            items[0] as Map<String, dynamic>;
        final List<dynamic> paths = inner['it'] as List<dynamic>;
        expect(
          paths.map((dynamic item) => (item as Map<String, dynamic>)['ty']),
          <String>['el', 'el', 'tr'],
        );
        _pathIdentity(paths[2] as Map<String, dynamic>);
        _pathIdentity(items[2] as Map<String, dynamic>);
        final bool flatten = mode != 'nested';
        group['it'] = <dynamic>[
          if (flatten) ...paths.take(2) else items[0],
          trim, jsonDecode(jsonEncode(stroke)), items[2],
        ];
        promoted++;
        if (flatten) flattened++;
      }
    }
    if (mode != 'channels') {
      target['it'] = <dynamic>[outer[0], outer[1], outer[3]];
    }
  }
  expect(promoted, mode == 'channels' ? 0 : 4);
  expect(flattened, mode == 'flattened' || mode == 'flattened_sorted' ? 4 : 0);
  expect(swapped, mode == 'channels' || mode == 'flattened_sorted' ? 4 : 0);
  return LottieComposition.parseJsonBytes(utf8.encode(jsonEncode(value)));
}

int _pathPixelDifference(Uint8List before, Uint8List after) {
  expect(before.length, _trimEdge * _trimEdge * 4);
  expect(after.length, before.length);
  int changed = 0;
  for (int offset = 0; offset < before.length; offset += 4) {
    if (before[offset] != after[offset] ||
        before[offset + 1] != after[offset + 1] ||
        before[offset + 2] != after[offset + 2] ||
        before[offset + 3] != after[offset + 3]) {
      changed++;
    }
  }
  return changed;
}

int _pathMaskDifference(List<bool> before, List<bool> after) {
  expect(before.length, _trimEdge * _trimEdge);
  expect(after.length, before.length);
  int changed = 0;
  for (int index = 0; index < before.length; index++) {
    if (before[index] != after[index]) changed++;
  }
  return changed;
}

const ValueKey<String> _captionSnapshot =
    ValueKey<String>('original-entry-caption-snapshot');
const TargetPlatformVariant _captionWindows = TargetPlatformVariant(
  <TargetPlatform>{TargetPlatform.windows},
);

Widget _captionHost(Widget child, {ThemeData? theme}) => RepaintBoundary(
  key: _captionSnapshot,
  child: MaterialApp(
    theme: theme ?? AppTheme.darkTheme, locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    builder: (BuildContext context, Widget? original) =>
        AppWindowFrame(child: original!),
    home: child,
  ),
);

Future<Uint8List> _captionPixels(WidgetTester tester) async {
  final RenderRepaintBoundary original = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_captionSnapshot));
  return (await tester.runAsync<Uint8List>(() async {
    final ui.Image image = await original.toImage();
    try {
      final ByteData? data = await image.toByteData();
      if (data == null) throw StateError('Original caption pixels unavailable');
      return Uint8List.fromList(data.buffer.asUint8List(
        data.offsetInBytes, data.lengthInBytes,
      ));
    } finally {
      image.dispose();
    }
  }))!;
}

List<int> _captionRgb(Uint8List rgba, int width, int x, int y) {
  final int offset = (y * width + x) * 4;
  expect(rgba[offset + 3], 255);
  return <int>[rgba[offset], rgba[offset + 1], rgba[offset + 2]];
}

void _continuousCaption(Uint8List rgba, int width) {
  for (final int x in <int>[0, width ~/ 4, width ~/ 2, width * 3 ~/ 4]) {
    final List<int> top = _captionRgb(rgba, width, x, 31);
    final List<int> body = _captionRgb(rgba, width, x, 32);
    for (int channel = 0; channel < 3; channel++) {
      expect((top[channel] - body[channel]).abs(), lessThanOrEqualTo(2));
    }
  }
  expect(_captionRgb(rgba, width, 0, 31),
      isNot(_captionRgb(rgba, width, width ~/ 2, 31)));
}

void _baseCaption(WidgetTester tester, Uint8List rgba, int width) {
  final AppTokens tokens = AppTokens.of(
    tester.element(find.byType(AppWindowFrame)),
  );
  final int argb = tokens.windowCaptionBackground.toARGB32();
  final List<int> expected = <int>[
    (argb >> 16) & 255, (argb >> 8) & 255, argb & 255,
  ];
  expect(_captionRgb(rgba, width, width ~/ 2, 16), expected);
}

void main() {
  const MethodChannel window = MethodChannel('window_manager');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(window, (MethodCall call) async =>
            switch (call.method) {
              'isFocused' => true,
              'isMaximized' || 'isFullScreen' => false,
              _ => null,
            });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(window, null);
  });

  void prepare(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(256, 160)
      ..devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.reset();
    });
  }

  for (final Brightness brightness in <Brightness>[
    Brightness.dark, Brightness.light,
  ]) {
    testWidgets('original caption and body share the ${brightness.name} field',
        (WidgetTester tester) async {
      prepare(tester);
      tester.view.physicalSize = const Size(1280, 780);
      await tester.pumpWidget(_captionHost(const EntryField(),
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme : AppTheme.lightTheme));
      await tester.pump(const Duration(milliseconds: 400));
      final ReferenceArtworkSource source = _source(tester);
      final ShaderClock clock =
          source.referenceArtworkGeneration as ShaderClock;
      final AppWindowFrameState caption = tester
          .state<AppWindowFrameState>(find.byType(AppWindowFrame));
      expect(caption.hasClientCaption, isTrue);
      expect(caption.windowStatus?.queryPending, isFalse);
      expect(caption.windowStatus?.queryFailed, isFalse);
      expect(caption.windowStatus?.maximized, isFalse);
      final Finder maximize = find.descendant(
        of: find.byKey(const ValueKey<String>('window-maximize')),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(maximize).onPressed, isNotNull);
      // The original native reply enables the control during the first pump.
      // Let its existing style transition finish before sampling any pixels.
      await tester.pump(const Duration(milliseconds: 400));
      final ReferenceArtworkFrame frame = source.captureReferenceArtwork()!;
      expect(frame.observed, isFalse);
      await tester.pump();
      expect(frame.observed, isTrue);
      final Uint8List first = await _captionPixels(tester);
      expect(first.length, 1280 * 780 * 4);
      _continuousCaption(first, 1280);
      final String bodyHash = _trimHash(await _pixels(tester));
      final String captionHash = _trimHash(
        Uint8List.sublistView(first, 0, 1280 * 32 * 4),
      );
      final double before = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, greaterThan(before));
      expect(clock.isRunning, isTrue);
      expect(_source(tester), same(source));
      expect(source.referenceArtworkGeneration, same(clock));
      expect(_trimHash(await _pixels(tester)), bodyHash);
      final Uint8List held = await _captionPixels(tester);
      expect(_trimHash(Uint8List.sublistView(held, 0, 1280 * 32 * 4)),
        captionHash);
      expect(frame.restore(), isTrue);
      expect(frame.restored, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(frame.restored, isTrue);
      expect(_trimHash(await _pixels(tester)), isNot(bodyHash));
      _continuousCaption(await _captionPixels(tester), 1280);
      expect(tester.state(find.byType(AppWindowFrame)), same(caption));
      expect(source.referenceArtworkGeneration, same(clock));
    }, variant: _captionWindows);
  }

  testWidgets('caption geometry follows its field and retires replacement',
      (WidgetTester tester) async {
    prepare(tester);
    tester.view.physicalSize = const Size(1280, 780);
    await tester.pumpWidget(_captionHost(
      const EntryField(key: ValueKey<String>('original-entry-field')),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    final ReferenceArtworkSource source = _source(tester);
    final ReferenceArtworkFrame frame = source.captureReferenceArtwork()!;
    final AppWindowFrameState caption = tester
        .state<AppWindowFrameState>(find.byType(AppWindowFrame));
    await tester.pump();
    expect(frame.observed, isTrue);
    tester.view.physicalSize = const Size(1200, 600);
    await tester.pump();
    expect(frame.observed, isTrue);
    expect(_source(tester), same(source));
    expect(source.referenceArtworkGeneration, same(frame.generation));
    final Uint8List resized = await _captionPixels(tester);
    expect(resized.length, 1200 * 600 * 4);
    _continuousCaption(resized, 1200);
    await tester.pumpWidget(_captionHost(
      const EntryField(key: ValueKey<String>('replacement-entry-field')),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(frame.isCurrent, isFalse);
    expect(frame.restore(), isFalse);
    expect(frame.restored, isFalse);
    expect(_source(tester), isNot(same(source)));
    expect(_source(tester).referenceArtworkGeneration,
      isNot(same(frame.generation)));
    expect(tester.state(find.byType(AppWindowFrame)), same(caption));
    await tester.pumpWidget(_captionHost(const SizedBox.expand()));
    await tester.pump(const Duration(milliseconds: 400));
    _baseCaption(tester, await _captionPixels(tester), 1200);
    expect(tester.allStates.whereType<ReferenceArtworkSource>(), isEmpty);
    expect(frame.restore(), isFalse);
  }, variant: _captionWindows);

  testWidgets('ambiguous fields cannot sample or revive an old caption',
      (WidgetTester tester) async {
    prepare(tester);
    tester.view.physicalSize = const Size(1280, 780);
    Widget fields({required bool duplicate}) => Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const EntryField(key: ValueKey<String>('original-entry-field')),
        if (duplicate) const EntryField(
          key: ValueKey<String>('other-original-entry-field'),
        ),
      ],
    );
    await tester.pumpWidget(_captionHost(fields(duplicate: false)));
    await tester.pump(const Duration(milliseconds: 400));
    final ReferenceArtworkSource source = _source(tester);
    final ReferenceArtworkFrame frame = source.captureReferenceArtwork()!;
    await tester.pump();
    expect(frame.observed, isTrue);
    await tester.pumpWidget(_captionHost(fields(duplicate: true)));
    await tester.pump(const Duration(milliseconds: 400));
    final List<ReferenceArtworkSource> ambiguous = tester.allStates
        .whereType<ReferenceArtworkSource>().toList(growable: false);
    expect(ambiguous, hasLength(2));
    for (final ReferenceArtworkSource original in ambiguous) {
      expect(original.captureReferenceArtwork(), isNull);
    }
    _baseCaption(tester, await _captionPixels(tester), 1280);
    expect(frame.isCurrent, isFalse);
    expect(frame.restore(), isFalse);
    await tester.pumpWidget(_captionHost(fields(duplicate: false)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_source(tester), same(source));
    expect(source.referenceArtworkGeneration, same(frame.generation));
    expect(frame.isCurrent, isFalse);
    expect(frame.restore(), isFalse);
    expect(frame.restored, isFalse);
    expect(source.captureReferenceArtwork(), isNull);
  }, variant: _captionWindows);

  testWidgets('globe sampling preserves its original clock and Future', (
    WidgetTester tester,
  ) async {
    prepare(tester);
    await tester.pumpWidget(_host(const AppLottie(
      AppLottieAsset.globe, size: 64,
    )));
    await _loaded(tester);
    final ReferenceArtworkSource source = _source(tester);
    final Lottie before = tester.widget<Lottie>(find.byType(Lottie));
    final Object renderer = tester.state(find.byType(Lottie));
    final AnimationController clock = before.controller! as AnimationController;
    bool completed = false;
    bool canceled = false;
    unawaited(clock.forward(from: 0).orCancel.then<void>(
      (_) { completed = true; },
      onError: (Object _) { canceled = true; },
    ));
    // Give the original forward ticker its first frame before measuring it.
    await tester.pump();
    final ReferenceArtworkFrame frame = source.captureReferenceArtwork()!;
    expect(frame.observed, isFalse);
    await tester.pump(const Duration(milliseconds: 250));
    expect(frame.observed, isTrue);
    expect(frame.observation, <String, Object>{
      'kind': 'welcome_globe', 'frame': 48, 'frame_count': 120,
    });
    final Lottie sampled = tester.widget<Lottie>(find.byType(Lottie));
    expect(sampled.composition, same(before.composition));
    expect(tester.state(find.byType(Lottie)), same(renderer));
    expect(sampled.controller!.value, closeTo(48 / 119.99, 0.0000001));
    expect(sampled.frameRate, FrameRate.max);
    expect(clock.isAnimating, isTrue);
    expect(clock.value, greaterThan(0));
    expect(completed || canceled, isFalse);
    expect(frame.restore(), isTrue);
    expect(frame.restored, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    expect(frame.restored, isTrue);
    final Lottie restored = tester.widget<Lottie>(find.byType(Lottie));
    expect(restored.controller, same(clock));
    expect(restored.composition, same(before.composition));
    expect(restored.frameRate, before.frameRate);
    expect(tester.state(find.byType(Lottie)), same(renderer));
    await tester.pump(const Duration(seconds: 3));
    expect(completed, isTrue);
    expect(canceled, isFalse);
  });

  testWidgets('asset replacement permanently retires an earlier sample', (
    WidgetTester tester,
  ) async {
    prepare(tester);
    await tester.pumpWidget(_host(const AppLottie(
      AppLottieAsset.globe, size: 64,
    )));
    await _loaded(tester);
    final ReferenceArtworkFrame frame =
        _source(tester).captureReferenceArtwork()!;
    await tester.pump();
    expect(frame.observed, isTrue);
    await tester.pumpWidget(_host(const AppLottie(
      AppLottieAsset.zts, size: 64,
    )));
    await _loaded(tester);
    expect(frame.isCurrent, isFalse);
    expect(frame.restore(), isFalse);
    expect(frame.restored, isFalse);
    expect(_source(tester).captureReferenceArtwork(), isNull);
  });

  testWidgets('field sampling holds pixels while its original clock advances', (
    WidgetTester tester,
  ) async {
    prepare(tester);
    await tester.pumpWidget(_host(const EntryField()));
    await tester.pump(const Duration(milliseconds: 16));
    final ReferenceArtworkSource source = _source(tester);
    final ShaderClock clock = source.referenceArtworkGeneration as ShaderClock;
    final ReferenceArtworkFrame frame = source.captureReferenceArtwork()!;
    expect(frame.observed, isFalse);
    await tester.pump();
    expect(frame.observed, isTrue);
    final Uint8List first = await _pixels(tester);
    final double before = clock.value;
    await tester.pump(const Duration(seconds: 1));
    expect(clock.value, greaterThan(before));
    expect(clock.isRunning, isTrue);
    expect(await _pixels(tester), orderedEquals(first));
    expect(frame.restore(), isTrue);
    expect(frame.restored, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(frame.restored, isTrue);
    expect(await _pixels(tester), isNot(orderedEquals(first)));
    expect(_source(tester), same(source));
    expect(source.referenceArtworkGeneration, same(clock));
    expect(clock.value, greaterThan(before));
  });

  testWidgets('a disposed field cannot restore through a replacement owner', (
    WidgetTester tester,
  ) async {
    prepare(tester);
    await tester.pumpWidget(_host(const EntryField()));
    await tester.pump(const Duration(milliseconds: 16));
    final ReferenceArtworkFrame frame =
        _source(tester).captureReferenceArtwork()!;
    await tester.pump();
    expect(frame.observed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(const EntryField()));
    expect(frame.isCurrent, isFalse);
    expect(frame.restore(), isFalse);
    expect(frame.restored, isFalse);
    expect(_source(tester).referenceArtworkGeneration,
      isNot(same(frame.generation)));
  });
  testWidgets('original Welcome trim bounds have a bounded renderer probe', (
    WidgetTester tester,
  ) async {
    final ByteData asset = await rootBundle.load(_trimAsset);
    final Uint8List bytes = asset.buffer.asUint8List(
      asset.offsetInBytes, asset.lengthInBytes,
    );
    expect(bytes.length, 2189249);
    expect(_trimHash(bytes), _trimSha);
    final Map<String, dynamic> variant =
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final List<dynamic> layers = variant['layers'] as List<dynamic>;
    expect(layers.length, 9);
    final Map<String, dynamic> first = layers.first as Map<String, dynamic>;
    expect(first['nm'], 'moving line');
    int swaps = 0;
    void visit(dynamic value) {
      if (value is Map<String, dynamic>) {
        if (value['ty'] == 'tm' && value['m'] == 2) {
          final dynamic start = value['s'];
          value['s'] = value['e'];
          value['e'] = start;
          swaps++;
        }
        value.values.forEach(visit);
      } else if (value is List<dynamic>) {
        value.forEach(visit);
      }
    }
    // This variant exists only in test memory. Swapping entire channels
    // keeps their original keyframe timing and the independent offset.
    visit(first);
    expect(swaps, 2);
    final LottieComposition original = LottieComposition.parseJsonBytes(bytes);
    final LottieComposition sorted = LottieComposition.parseJsonBytes(
      utf8.encode(jsonEncode(variant)),
    );
    expect(original.bounds, sorted.bounds);
    expect(original.durationFrames, sorted.durationFrames);
    expect(original.durationFrames, closeTo(1799.99, .00001));
    final List<Map<String, Object>> samples = <Map<String, Object>>[];
    final List<Uint8List> rendered = (await tester.runAsync(() async =>
        <Uint8List>[await _trimRender(original), await _trimRender(sorted)]))!;
    for (final String theme in <String>['dark', 'light']) {
      final Uint8List reference = (await tester.runAsync(
        () => _trimReference(theme),
      ))!;
      for (final int threshold in <int>[96, 160]) {
        final List<bool> mask = _trimGreen(reference, threshold);
        final Map<String, int> before = _trimOverlap(
          _trimGreen(rendered[0], threshold), mask,
        );
        final Map<String, int> after = _trimOverlap(
          _trimGreen(rendered[1], threshold), mask,
        );
        samples.add(<String, Object>{'theme': theme,
          'threshold': threshold, 'original': before, 'sorted': after});
      }
    }
    expect(_trimHash(bytes), _trimSha);
    // Numeric diagnostics cannot grant a visual match or establish the
    // normal application's animation-clock behaviour.
    // ignore: avoid_print
    print('CI_WELCOME_TRIM_METRICS:${jsonEncode(<String, Object>{
      'schema': 1, 'frame': _trimFrame, 'frame_count': 1800,
      'edge': _trimEdge, 'swapped_channels': swaps, 'samples': samples,
    })}');
    for (final Map<String, Object> sample in samples) {
      final Map<String, int> before = sample['original']! as Map<String, int>;
      final Map<String, int> after = sample['sorted']! as Map<String, int>;
      expect(before['present'], greaterThan(0));
      expect(before['expected'], greaterThan(0));
      expect(after['present'], greaterThan(0));
    }
  });
  testWidgets('nested Welcome trim variants retain bounded pixel differences', (
    WidgetTester tester,
  ) async {
    final ByteData asset = await rootBundle.load(_trimAsset);
    final Uint8List bytes = asset.buffer.asUint8List(
      asset.offsetInBytes, asset.lengthInBytes,
    );
    expect(_trimHash(bytes), _trimSha);
    final LottieComposition original = LottieComposition.parseJsonBytes(bytes);
    final Map<String, LottieComposition> variants = <String, LottieComposition>{
      for (final String mode in _pathModes) mode: _pathVariant(bytes, mode),
    };
    for (final LottieComposition variant in variants.values) {
      expect(variant.bounds, original.bounds);
      expect(variant.durationFrames, original.durationFrames);
    }
    final Map<String, Uint8List> rendered = (await tester.runAsync(() async =>
        <String, Uint8List>{
          'original': await _trimRender(original),
          for (final String mode in _pathModes)
            mode: await _trimRender(variants[mode]!),
        }))!;
    final Map<String, int> changed = <String, int>{
      for (final String mode in _pathModes)
        mode: _pathPixelDifference(rendered['original']!, rendered[mode]!),
    };
    final List<Map<String, Object>> samples = <Map<String, Object>>[];
    for (final String theme in <String>['dark', 'light']) {
      final Uint8List reference = (await tester.runAsync(
        () => _trimReference(theme),
      ))!;
      for (final int threshold in <int>[32, 64, 96, 160]) {
        final List<bool> mask = _trimGreen(reference, threshold);
        final List<bool> originalMask =
            _trimGreen(rendered['original']!, threshold);
        final Map<String, Object> measurements = <String, Object>{};
        for (final String mode in _pathModes) {
          final List<bool> variantMask = _trimGreen(rendered[mode]!, threshold);
          measurements[mode] = <String, int>{
            ..._trimOverlap(variantMask, mask),
            'changed_mask': _pathMaskDifference(originalMask, variantMask),
          };
        }
        samples.add(<String, Object>{
          'theme': theme, 'threshold': threshold,
          'original': _trimOverlap(originalMask, mask),
          'variants': measurements,
        });
      }
    }
    expect(_trimHash(bytes), _trimSha);
    // This is a renderer experiment, without production-clock or match claims.
    // ignore: avoid_print
    print('CI_WELCOME_PATH_METRICS:${jsonEncode(<String, Object>{
      'schema': 1, 'frame': _trimFrame, 'frame_count': 1800, 'edge': _trimEdge,
      'changed_pixels': changed, 'samples': samples,
    })}');
    for (final Map<String, Object> sample in samples) {
      final Map<String, int> before = sample['original']! as Map<String, int>;
      expect(before['present'], greaterThan(0));
      expect(before['expected'], greaterThan(0));
    }
  });
  testWidgets('production Welcome retains its qualified paths and owner', (
    WidgetTester tester,
  ) async {
    prepare(tester);
    AppLottie.debugClear();
    addTearDown(AppLottie.debugClear);
    final ByteData asset = await rootBundle.load(_trimAsset);
    final Uint8List bytes = asset.buffer.asUint8List(
      asset.offsetInBytes, asset.lengthInBytes,
    );
    expect(_trimHash(bytes), _trimSha);
    late final Future<LottieComposition> originalFuture;
    final LottieComposition loaded = (await tester.runAsync(() async {
      originalFuture = AppLottie.debugLoad(_trimAsset);
      expect(AppLottie.debugLoad(_trimAsset), same(originalFuture));
      return originalFuture;
    }))!;
    final LottieComposition original = LottieComposition.parseJsonBytes(bytes);
    final LottieComposition measured = _pathVariant(bytes, 'flattened_sorted');
    expect(loaded.bounds, original.bounds);
    expect(loaded.durationFrames, original.durationFrames);
    final List<Uint8List> rendered =
        (await tester.runAsync(() async => <Uint8List>[
      await _trimRender(original), await _trimRender(measured),
      await _trimRender(loaded),
    ]))!;
    expect(_pathPixelDifference(rendered[1], rendered[2]), 0);
    expect(_pathPixelDifference(rendered[0], rendered[2]), 6519);
    for (final String theme in <String>['dark', 'light']) {
      final Uint8List reference = (await tester.runAsync(
        () => _trimReference(theme),
      ))!;
      for (final int threshold in <int>[32, 64, 96, 160]) {
        final List<bool> mask = _trimGreen(reference, threshold);
        final Map<String, int> before = _trimOverlap(
          _trimGreen(rendered[0], threshold), mask,
        );
        final Map<String, int> after = _trimOverlap(
          _trimGreen(rendered[2], threshold), mask,
        );
        expect(after['extra']! + after['missing']!,
            lessThan(before['extra']! + before['missing']!));
      }
    }
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme,
      home: const AppLottie(AppLottieAsset.globe, size: 128)));
    await _loaded(tester);
    final ReferenceArtworkSource source = _source(tester);
    final Lottie before = tester.widget<Lottie>(find.byType(Lottie));
    final AnimationController clock = before.controller! as AnimationController;
    expect(before.composition, same(loaded));
    expect(source.referenceArtworkReadiness, same(originalFuture));
    expect(clock.isAnimating, isTrue);
    final ReferenceArtworkFrame sampled = source.captureReferenceArtwork()!;
    await tester.pump(const Duration(milliseconds: 250));
    expect(sampled.observed, isTrue);
    expect(sampled.restore(), isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    expect(sampled.restored, isTrue);
    final Lottie restored = tester.widget<Lottie>(find.byType(Lottie));
    expect(restored.composition, same(loaded));
    expect(restored.controller, same(clock));
    expect(source.referenceArtworkReadiness, same(originalFuture));
    expect(clock.isAnimating, isTrue);
    expect(_trimHash(bytes), _trimSha);
  });
}
