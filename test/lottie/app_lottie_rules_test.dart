import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// A small vector fixture keeps playback checks separate from image decode
/// costs. Every requested asset has the same two-second composition.
class _Bundle extends CachingAssetBundle {
  final List<String> paths = <String>[];

  @override
  Future<ByteData> load(String key) async {
    paths.add(key);
    final Uint8List bytes = utf8.encode(
      jsonEncode(<String, Object>{
        'v': '5.7.4',
        'fr': 60,
        'ip': 0,
        'op': 120,
        'w': 64,
        'h': 64,
        'nm': 'Playback fixture',
        'ddd': 0,
        'assets': <Object>[],
        'layers': <Object>[],
      }),
    );
    return ByteData.sublistView(bytes);
  }
}

Widget _host(
  _Bundle bundle,
  Widget child, {
  bool enabled = true,
  bool disableAnimations = false,
  double devicePixelRatio = 1,
}) => DefaultAssetBundle(
  bundle: bundle,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(
        devicePixelRatio: devicePixelRatio,
        disableAnimations: disableAnimations,
      ),
      child: TickerMode(
        enabled: enabled,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  ),
);

Future<void> _loaded(WidgetTester tester) async {
  for (int i = 0; i < 200 && find.byType(Lottie).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(find.byType(Lottie), findsOneWidget);
  await tester.pump();
}

Animation<double> _clock(WidgetTester tester) =>
    tester.widget<Lottie>(find.byType(Lottie)).controller!;

void main() {
  tearDown(AppLottie.debugClear);

  for (final AppLottieAsset asset in <AppLottieAsset>[
    AppLottieAsset.zts,
    AppLottieAsset.pillar,
    AppLottieAsset.sentinel,
    AppLottieAsset.eye,
    AppLottieAsset.noData,
    AppLottieAsset.splash,
  ]) {
    testWidgets('${asset.name} plays once and holds its last frame', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_Bundle(), AppLottie(asset, size: 48)));
      await _loaded(tester);
      expect(_clock(tester).value, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_clock(tester).value, closeTo(0.25, 0.001));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_clock(tester).value, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(_clock(tester).value, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final AppLottieAsset asset in <AppLottieAsset>[
    AppLottieAsset.globe,
    AppLottieAsset.map,
    AppLottieAsset.plasmaGeneration,
  ]) {
    testWidgets('${asset.name} is an allowed loop', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(_Bundle(), AppLottie(asset, size: 48)));
      await _loaded(tester);
      await tester.pump(const Duration(milliseconds: 2500));
      expect(_clock(tester).value, closeTo(0.25, 0.001));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('an allowed loop can be requested only once', (
    WidgetTester tester,
  ) async {
    final _Bundle bundle = _Bundle();
    await tester.pumpWidget(
      _host(
        bundle,
        const AppLottie(AppLottieAsset.map, size: 48, repeat: false),
      ),
    );
    await _loaded(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_clock(tester).value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an object replays once on mouse entry and keeps its box', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(_Bundle(), const AppLottie(AppLottieAsset.pillar, size: 48)),
    );
    await _loaded(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_clock(tester).value, 1);
    expect(tester.getSize(find.byType(AppLottie)), const Size(48, 48));

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(200, 200));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(AppLottie)));
    await tester.pump();
    expect(_clock(tester).value, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clock(tester).value, closeTo(0.25, 0.001));
    await mouse.moveBy(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clock(tester).value, closeTo(0.5, 0.001));
    await tester.pump(const Duration(seconds: 2));
    expect(_clock(tester).value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final bool disabled in <bool>[false, true]) {
    testWidgets('uses the full composition with OS animations off: $disabled', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: disabled);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        _host(
          _Bundle(),
          const AppLottie(AppLottieAsset.sentinel, size: 48),
          disableAnimations: disabled,
        ),
      );
      await _loaded(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_clock(tester).value, closeTo(0.5, 0.001));
      await tester.pump(const Duration(milliseconds: 999));
      expect(_clock(tester).value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(_clock(tester).value, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a rebuild keeps playback and a hidden page pauses it', (
    WidgetTester tester,
  ) async {
    final _Bundle bundle = _Bundle();
    Widget host({bool enabled = true}) => _host(
      bundle,
      const AppLottie(AppLottieAsset.zts, size: 48),
      enabled: enabled,
    );
    await tester.pumpWidget(host());
    await _loaded(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(host());
    expect(_clock(tester).value, closeTo(0.25, 0.001));
    await tester.pumpWidget(host(enabled: false));
    await tester.pump(const Duration(seconds: 8));
    expect(_clock(tester).value, closeTo(0.25, 0.001));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clock(tester).value, closeTo(0.5, 0.001));
    expect(bundle.paths, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a page mounted hidden defers loading until it appears', (
    WidgetTester tester,
  ) async {
    final _Bundle bundle = _Bundle();
    const Widget object = AppLottie(AppLottieAsset.pillar, size: 48);
    await tester.pumpWidget(_host(bundle, object, enabled: false));
    await tester.pump(const Duration(seconds: 8));
    expect(bundle.paths, isEmpty);
    expect(find.byType(Lottie), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(bundle, object));
    await _loaded(tester);
    expect(_clock(tester).value, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clock(tester).value, closeTo(0.25, 0.001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background lifecycle pauses an automatic loop', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      _host(_Bundle(), const AppLottie(AppLottieAsset.globe, size: 48)),
    );
    await _loaded(tester);
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 8));
    expect(_clock(tester).value, closeTo(0.25, 0.001));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clock(tester).value, closeTo(0.5, 0.001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a caller retains control of eye frames and its controller', (
    WidgetTester tester,
  ) async {
    final AnimationController controller = AnimationController(vsync: tester)
      ..value = 0.6;
    await tester.pumpWidget(
      _host(
        _Bundle(),
        AppLottie(AppLottieAsset.eye, size: 16, controller: controller),
      ),
    );
    await _loaded(tester);
    expect(_clock(tester), same(controller));
    await tester.pump(const Duration(seconds: 5));
    expect(_clock(tester).value, 0.6);
    controller.value = 0.2;
    await tester.pump();
    expect(_clock(tester).value, 0.2);
    await tester.pumpWidget(const SizedBox());
    controller
      ..value = 0.9
      ..dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('resuming draws a cached object mounted in the background', (
    WidgetTester tester,
  ) async {
    final _Bundle bundle = _Bundle();
    const Widget object = AppLottie(AppLottieAsset.pillar, size: 48);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(_host(bundle, object));
    await _loaded(tester);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(_host(bundle, object));
    expect(find.byType(Lottie), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(Lottie), findsOneWidget);
    expect(_clock(tester).value, 0);
    expect(bundle.paths, hasLength(1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_clock(tester).value, closeTo(0.25, 0.001));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('small object suppression follows the actual slot', (
    WidgetTester tester,
  ) async {
    final _Bundle bundle = _Bundle();
    for (final AppLottieAsset asset in <AppLottieAsset>[
      AppLottieAsset.zts,
      AppLottieAsset.pillar,
      AppLottieAsset.sentinel,
    ]) {
      await tester.pumpWidget(
        _host(
          bundle,
          SizedBox(width: 32, height: 32, child: AppLottie(asset, size: 48)),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(Lottie), findsNothing);
      expect(bundle.paths, isEmpty);
      expect(tester.getSize(find.byType(AppLottie)), const Size(32, 32));
    }
    await tester.pumpWidget(
      _host(bundle, const AppLottie(AppLottieAsset.zts, size: 40)),
    );
    await _loaded(tester);
    expect(bundle.paths.single, 'assets/lottie/ic_anim_zts_small.json');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 48 px strip uses the small file at high pixel density', (
    WidgetTester tester,
  ) async {
    final _Bundle bundle = _Bundle();
    await tester.pumpWidget(
      _host(
        bundle,
        const AppLottie(AppLottieAsset.zts, size: 48),
        devicePixelRatio: 4,
      ),
    );
    await _loaded(tester);
    expect(bundle.paths.single, 'assets/lottie/ic_anim_zts_small.json');
    expect(
      tester.widget<Lottie>(find.byType(Lottie)).filterQuality,
      FilterQuality.medium,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
