import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/entry_field.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_card_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

const MethodChannel _window = MethodChannel('window_manager');
const Size _size = Size(1280, 780);
const Key _clipFrame = Key('entry_field_clip_frame');

Widget _host({
  Widget child = const EntryField(),
  bool light = false,
  bool enabled = true,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TickerMode(
    enabled: enabled,
    child: MediaQuery(
      data: MediaQueryData(
        size: _size,
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(body: child),
    ),
  ),
);

void _prepare(WidgetTester tester) {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.reset();
  });
}

Future<Uint8List> _pixels(WidgetTester tester, {Finder? surface}) async {
  final Finder target =
      surface ??
      find.descendant(
        of: find.byType(EntryField),
        matching: find.byType(RepaintBoundary),
      );
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(target);
  return (await tester.runAsync<Uint8List>(() async {
    final ui.Image image = await boundary.toImage();
    try {
      expect(image.width, _size.width);
      expect(image.height, _size.height);
      final ByteData? data = await image.toByteData();
      if (data == null) {
        throw StateError('The original pixels are unavailable');
      }
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

List<int> _rgba(Uint8List pixels, int x, int y) {
  final int offset = (y * _size.width.toInt() + x) * 4;
  return pixels.sublist(offset, offset + 4);
}

void _expectBackground(Uint8List pixels, bool light) {
  final Color background = light
      ? AppTokens.light.background
      : AppTokens.dark.background;
  final List<int> expected = <int>[
    (background.r * 255).round(),
    (background.g * 255).round(),
    (background.b * 255).round(),
  ];
  final List<int> corner = _rgba(pixels, 4, 775);
  for (int channel = 0; channel < 3; channel++) {
    expect(corner[channel], closeTo(expected[channel], 2));
  }
  expect(corner[3], 255);
}

void _expectBand(
  Uint8List pixels,
  int x,
  int y,
  List<List<int>> bands,
) {
  final List<int> pixel = _rgba(pixels, x, y);
  for (int channel = 0; channel < 3; channel++) {
    expect(
      pixel[channel],
      inInclusiveRange(bands[channel][0], bands[channel][1]),
      reason: 'Reference entry wash at $x,$y, channel $channel',
    );
  }
  expect(pixel[3], 255);
}

void _expectEntryWash(Uint8List pixels, bool light) {
  // Independent colour envelopes at the CSS field's initial light centres.
  // They allow blur/raster rounding, but reject a card base, a flat fallback
  // and gradients composited without the reference's grouped .35 opacity.
  _expectBand(
    pixels,
    230,
    205,
    light
        ? <List<int>>[
            <int>[200, 216],
            <int>[222, 237],
            <int>[197, 216],
          ]
        : <List<int>>[
            <int>[20, 31],
            <int>[45, 57],
            <int>[20, 38],
          ],
  );
  _expectBand(
    pixels,
    945,
    532,
    light
        ? <List<int>>[
            <int>[197, 218],
            <int>[211, 231],
            <int>[228, 238],
          ]
        : <List<int>>[
            <int>[19, 31],
            <int>[31, 43],
            <int>[47, 61],
          ],
  );
  _expectBand(
    pixels,
    676,
    41,
    light
        ? <List<int>>[
            <int>[232, 242],
            <int>[210, 225],
            <int>[217, 233],
          ]
        : <List<int>>[
            <int>[39, 56],
            <int>[22, 37],
            <int>[31, 45],
          ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (MethodCall call) async {
          if (call.method == 'isFocused') {
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    expect(FrostHold.count.value, 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
  });

  for (final bool light in <bool>[false, true]) {
    final String name = light ? 'light' : 'dark';

    testWidgets('$name pixels keep the window base and restrained entry wash', (
      WidgetTester tester,
    ) async {
      _prepare(tester);
      await tester.pumpWidget(_host(light: light));
      await tester.pump();
      final Uint8List pixels = await _pixels(tester);
      _expectBackground(pixels, light);
      _expectEntryWash(pixels, light);
    });

    testWidgets(
      '$name painted drift alternates at 20 seconds and repeats at 40',
      (
        WidgetTester tester,
      ) async {
        _prepare(tester);
        await tester.pumpWidget(_host(light: light));
        await tester.pump();
        final Uint8List start = await _pixels(tester);
        await tester.pump(const Duration(seconds: 20));
        final Uint8List end = await _pixels(tester);
        _expectBackground(end, light);
        expect(end, isNot(orderedEquals(start)));
        await tester.pump(const Duration(seconds: 20));
        expect(await _pixels(tester), orderedEquals(start));
      },
    );

    testWidgets('$name Welcome and entry card paint the real shared field', (
      WidgetTester tester,
    ) async {
      _prepare(tester);
      final List<WelcomeDestination> destinations = <WelcomeDestination>[];
      await tester.pumpWidget(
        _host(
          light: light,
          child: WelcomeSurface(
            source: Object(),
            onSelected: destinations.add,
            wrapImportDrop: (Widget child) => child,
            // Art/drop fixtures are inert; the backdrop is production.
            globe: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 401));
      expect(find.byType(EntryField), findsOneWidget);
      _expectBackground(await _pixels(tester), light);
      await tester.tap(find.byKey(const Key('welcome_import')));
      expect(destinations, <WelcomeDestination>[
        WelcomeDestination.importWallet,
      ]);
      expect(
        find.text('A seed, or a wallet file dropped here'),
        findsOneWidget,
      );
      expect(find.textContaining('dropped here'), findsOneWidget);

      int back = 0;
      await tester.pumpWidget(
        _host(
          light: light,
          child: EntryCardSurface(
            title: 'Import your wallet',
            steps: const <String>['Seed or file', 'Password', 'Ready'],
            step: 0,
            onBack: () => back++,
            marker: const Key('fixture_entry_card'),
            child: const Text('Seed or file'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(EntryField), findsOneWidget);
      _expectBackground(await _pixels(tester), light);
      await tester.tap(find.byKey(const Key('entry_back')));
      expect(back, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'OS animation flags keep the real field moving on its own clock',
    (
      WidgetTester tester,
    ) async {
      _prepare(tester);
      await tester.pumpWidget(_host(disableAnimations: true));
      await tester.pump();
      final Uint8List start = await _pixels(tester);
      await tester.pump(const Duration(seconds: 10));
      final Uint8List middle = await _pixels(tester);
      expect(middle, isNot(orderedEquals(start)));
      await tester.pump(const Duration(seconds: 20));
      expect(await _pixels(tester), orderedEquals(middle));
    },
  );

  testWidgets('hidden, inactive and covered time never advances the field', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    final Uint8List before = await _pixels(tester);

    await tester.pumpWidget(_host(enabled: false));
    await tester.pump(const Duration(seconds: 30));
    expect(await _pixels(tester), orderedEquals(before));
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(await _pixels(tester), orderedEquals(before));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 30));
    expect(await _pixels(tester), orderedEquals(before));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(await _pixels(tester), orderedEquals(before));

    FrostHold.acquire();
    FrostHold.acquire();
    try {
      await tester.pump(const Duration(seconds: 30));
      expect(await _pixels(tester), orderedEquals(before));
      FrostHold.release();
      await tester.pump(const Duration(seconds: 30));
      expect(await _pixels(tester), orderedEquals(before));
    } finally {
      FrostHold.release();
      FrostHold.release();
    }
    await tester.pump();
    expect(await _pixels(tester), orderedEquals(before));
    await tester.pump(const Duration(seconds: 5));
    expect(await _pixels(tester), isNot(orderedEquals(before)));
  });

  testWidgets(
    'a live theme change repaints the window base without a card flash',
    (
      WidgetTester tester,
    ) async {
      _prepare(tester);
      await tester.pumpWidget(_host());
      await tester.pump();
      _expectBackground(await _pixels(tester), false);
      await tester.pumpWidget(_host(light: true));
      await tester.pump(const Duration(milliseconds: 300));
      _expectBackground(await _pixels(tester), true);
      await tester.pumpWidget(_host());
      await tester.pump(const Duration(milliseconds: 300));
      _expectBackground(await _pixels(tester), false);
      expect(find.byType(EntryField), findsOneWidget);
    },
  );

  testWidgets(
    'the blurred paint stays clipped to its actual client rectangle',
    (
      WidgetTester tester,
    ) async {
      _prepare(tester);
      const Color outside = Color(0xFF9B743D);
      await tester.pumpWidget(
        _host(
          child: const RepaintBoundary(
            key: _clipFrame,
            child: ColoredBox(
              color: outside,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 200,
                    top: 100,
                    width: 700,
                    height: 500,
                    child: EntryField(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final Uint8List pixels = await _pixels(
        tester,
        surface: find.byKey(_clipFrame),
      );
      for (final Offset point in const <Offset>[
        Offset(199, 350),
        Offset(900, 350),
        Offset(550, 99),
        Offset(550, 600),
      ]) {
        expect(_rgba(pixels, point.dx.toInt(), point.dy.toInt()), <int>[
          155,
          116,
          61,
          255,
        ]);
      }
      expect(_rgba(pixels, 550, 350), isNot(<int>[155, 116, 61, 255]));
    },
  );

  testWidgets('disposal leaves no clock callbacks or delayed painting', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 40));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
