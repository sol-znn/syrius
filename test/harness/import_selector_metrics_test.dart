import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

const Key _tabular = ValueKey<String>('tabular_track');
const Key _proportional = ValueKey<String>('proportional_track');
const Key _compensated = ValueKey<String>('compensated_track');

Widget _selector(AppTokens tokens, {required bool tabular,
  bool compensated = false, ValueChanged<int>? onChanged}) => Segment<int>(
  key: compensated ? _compensated : tabular ? _tabular : _proportional,
  keyPrefix: compensated ? 'compensated' : tabular ? 'tabular' : 'proportional',
  pillPadding: compensated ? tokens.importWordChoicePadding : null,
  items: <SegmentItem<int>>[
    for (final int count in <int>[12, 24]) SegmentItem<int>(
      value: count,
      label: '$count words',
      labelStyle: tabular ? tokens.compactText : tokens.compactText.copyWith(
        // A diagnostic fixture only. Product numbers retain tabular figures.
        fontFeatures: const <FontFeature>[FontFeature('tnum', 0)],
      ),
    ),
  ],
  selected: 12,
  onChanged: onChanged ??
      (_) => throw StateError('Layout measurement must not select'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final FontLoader fonts = FontLoader(kSansFontFamily)
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Regular.ttf'));
    await fonts.load();
  });

  testWidgets('original font isolates the numeric selector width difference',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    for (final bool light in <bool>[false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Scaffold(body: Builder(
          builder: (BuildContext context) {
            final AppTokens tokens = AppTokens.of(context);
            expect(tokens.compactText.fontFeatures,
                const <FontFeature>[FontFeature.tabularFigures()]);
            return Align(
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _selector(tokens, tabular: true),
                  _selector(tokens, tabular: false),
                ],
              ),
            );
          },
        )),
      ));
      await tester.pump();
      final double tabular = tester.getSize(find.byKey(_tabular)).width;
      final double proportional =
          tester.getSize(find.byKey(_proportional)).width;
      // Raw font-table advances predict 3.003 px before shaping. The
      // genuine font and Segment are measured here, with kerning allowed.
      expect(tabular - proportional, inExclusiveRange(2.5, 3.5));
      for (final String prefix in <String>['tabular', 'proportional']) {
        final double cells = <int>[12, 24].fold<double>(0,
          (double sum, int count) => sum + tester.getSize(
            find.byKey(Segment.keyOf(prefix, count)),
          ).width,
        );
        expect(prefix == 'tabular' ? tabular : proportional,
            closeTo(cells + 8, 0.01));
      }
      expect(tester.takeException(), isNull);
    }
  });

  test('bundled font preserves width and height with CSS half-leading', () {
    final List<Map<String, num>> samples = <Map<String, num>>[];
    addTearDown(() {
      // Only fixed fixture metrics reach the controller's numeric allowlist.
      // ignore: avoid_print
      print('CI_BUNDLED_FONT_METRICS:${jsonEncode(<String, Object>{
        'schema': 1, 'font': 'bundled_interface', 'samples': samples,
      })}');
    });
    const double baselineTolerance = 1;
    bool distinctReferenceObserved = false;
    for (final double size in <double>[12, 14, 28, 56]) {
      // The product's height is close to this font's natural height. A taller
      // fixture distinguishes the two distributions without changing the UI.
      for (final double height in <double>[
        AppTokens.dark.bodyText.height!, 2,
      ]) {
        final TextStyle style = AppTokens.dark.bodyText.copyWith(
          fontSize: size, height: height,
        );
        TextPainter painter(TextStyle value) => TextPainter(
          text: TextSpan(text: 'Welcome to Syrius 123', style: value),
          textDirection: TextDirection.ltr,
        )..layout();
        final TextPainter natural = painter(style.copyWith(
          height: ui.kTextHeightNone,
        ));
        final TextPainter even = painter(style);
        final TextStyle proportionalStyle = style.copyWith(
          leadingDistribution: TextLeadingDistribution.proportional,
        );
        final TextPainter proportional = painter(proportionalStyle);
        try {
          expect(even.width, closeTo(proportional.width, 0.001));
          expect(even.height, closeTo(proportional.height, 0.001));
          final ui.LineMetrics font = natural.computeLineMetrics().single;
          final double targetHeight = size * style.height!;
          final double halfLeading =
              (targetHeight - font.ascent - font.descent) / 2;
          final double baseline = even.computeLineMetrics().single.baseline;
          final ui.LineMetrics evenLine = even.computeLineMetrics().single;
          samples.add(<String, num>{
            'size': size, 'height': height, 'width': even.width,
            'line_height': even.height, 'natural_ascent': font.ascent,
            'natural_descent': font.descent, 'even_baseline': baseline,
            'proportional_baseline':
                proportional.computeLineMetrics().single.baseline,
            'even_ascent': evenLine.ascent, 'even_descent': evenLine.descent,
            'even_mode': style.leadingDistribution!.index,
            'proportional_mode': proportionalStyle.leadingDistribution!.index,
          });
          expect(even.width, greaterThan(0));
          expect(font.ascent + font.descent, greaterThan(0));
          // Engine line-box rounding may shift the first baseline by a pixel.
          expect(baseline,
              closeTo(font.ascent + halfLeading, baselineTolerance));
          // API modes can share a baseline on a renderer. The independent
          // proportional reference uses this font's measured ascent ratio.
          final double proportionalReference = targetHeight * font.ascent /
              (font.ascent + font.descent);
          if ((font.ascent + halfLeading - proportionalReference).abs() >
              2 * baselineTolerance) {
            distinctReferenceObserved = true;
          }
        } finally {
          natural.dispose();
          even.dispose();
          proportional.dispose();
        }
      }
    }
    expect(distinctReferenceObserved, isTrue);
  });


  test('caption wordmark measures original glyph ink and tracking', () async {
    final List<Map<String, num>> samples = <Map<String, num>>[];
    addTearDown(() {
      // The fixed wordmark produces numeric bounds, never captured UI text.
      // ignore: avoid_print
      print('CI_CAPTION_WORDMARK_METRICS:${jsonEncode(<String, Object>{
        'schema': 1, 'samples': samples,
      })}');
    });
    for (final (int theme, AppTokens tokens) in <(int, AppTokens)>[
      (0, AppTokens.dark), (1, AppTokens.light),
    ]) {
      final TextStyle style = tokens.windowTitleText.copyWith(
        color: Colors.white,
      );
      final List<int> leftEdges = <int>[];
      for (final int variant in <int>[0, 1]) {
        final TextPainter text = TextPainter(
          text: TextSpan(text: 'SYRIUS', style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        final double x = tokens.windowCaptionPadding.left +
            tokens.windowWordmarkPaintOffset.dx -
            (variant == 1 ? style.letterSpacing! / 2 : 0);
        final double y = (tokens.windowCaptionHeight - text.height) / 2 +
            tokens.windowWordmarkPaintOffset.dy;
        text.paint(canvas, Offset(x, y));
        final ui.Picture picture = recorder.endRecording();
        ui.Image? image;
        try {
          image = await picture.toImage(128, 32);
          final ByteData? bytes = await image.toByteData();
          expect(bytes, isNotNull);
          int left = 127;
          int top = 31;
          int right = 0;
          int bottom = 0;
          int pixels = 0;
          for (int py = 0; py < 32; py++) {
            for (int px = 0; px < 128; px++) {
              if (bytes!.getUint8((py * 128 + px) * 4 + 3) < 32) continue;
              if (px < left) left = px;
              if (py < top) top = py;
              if (px > right) right = px;
              if (py > bottom) bottom = py;
              pixels++;
            }
          }
          samples.add(<String, num>{
            'theme': theme, 'variant': variant,
            'font_size': style.fontSize!, 'tracking': style.letterSpacing!,
            'line_height': text.height, 'line_width': text.width,
            'baseline': text.computeLineMetrics().single.baseline,
            'origin_x': x, 'origin_y': y,
            'ink_left': pixels == 0 ? 0 : left,
            'ink_top': pixels == 0 ? 0 : top,
            'ink_right': right, 'ink_bottom': bottom, 'ink_pixels': pixels,
            'image_width': 128, 'image_height': 32,
          });
          expect(pixels, greaterThan(0));
          expect(right, lessThan(128));
          expect(bottom, lessThan(32));
          leftEdges.add(left);
        } finally {
          image?.dispose();
          picture.dispose();
          text.dispose();
        }
      }
      // A paint-only diagnostic variant cannot alter the original line metrics.
      expect(leftEdges[0] - leftEdges[1], inInclusiveRange(1, 3));
      final List<Map<String, num>> pair = samples.sublist(samples.length - 2);
      for (final String key in <String>[
        'line_height', 'line_width', 'baseline', 'origin_y',
      ]) {
        expect(pair[0][key], pair[1][key]);
      }
    }
  });

  testWidgets('tabular word choices retain controlled RTL selection', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    for (final bool light in <bool>[false, true]) {
      for (final TextDirection direction in TextDirection.values) {
        final List<int> picks = <int>[];
        await tester.pumpWidget(MaterialApp(
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Scaffold(body: Builder(builder: (BuildContext context) {
            final AppTokens tokens = AppTokens.of(context);
            return Directionality(textDirection: direction, child: Align(
              alignment: Alignment.topLeft,
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _selector(tokens, tabular: true),
                  _selector(tokens, tabular: false),
                  _selector(tokens, tabular: true, compensated: true,
                      onChanged: picks.add),
                ],
              ),
            ));
          })),
        ));
        await tester.pump();
        final double width = tester.getSize(find.byKey(_compensated)).width;
        final double reference =
            tester.getSize(find.byKey(_proportional)).width;
        expect(width, closeTo(reference, 0.6));
        final Segment<int> product = tester.widget<Segment<int>>(
          find.byKey(_compensated),
        );
        for (final SegmentItem<int> item in product.items) {
          expect(item.labelStyle!.fontFeatures,
              const <FontFeature>[FontFeature.tabularFigures()]);
        }
        await tester.tap(find.byKey(Segment.keyOf('compensated', 24)));
        await tester.pump();
        expect(picks, <int>[24]);
        expect(tester.widget<Segment<int>>(
          find.byKey(_compensated),
        ).selected, 12);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
