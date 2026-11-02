import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/logical_capture.dart';
import '../../harness/app/readonly_shot_layout.dart';

void main() {
  for (final double ratio in <double>[1, 1.25, 1.5, 2, 3]) {
    testWidgets(
      'complete 1x capture and logical pointer targets at DPR $ratio',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = Size(1280 * ratio, 780 * ratio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final List<int> taps = <int>[0, 0, 0];
        const List<Rect> targets = <Rect>[
          Rect.fromLTWH(0, 0, 80, 60),
          Rect.fromLTWH(600, 360, 80, 60),
          Rect.fromLTWH(1200, 720, 80, 60),
        ];
        const List<Color> colors = <Color>[
          Color(0xFFFF0000),
          Color(0xFF00FF00),
          Color(0xFF0000FF),
        ];
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: Stack(
                children: <Widget>[
                  for (int i = 0; i < targets.length; i++)
                    Positioned.fromRect(
                      rect: targets[i],
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          taps[i]++;
                        },
                        child: ColoredBox(
                          key: ValueKey<int>(i),
                          color: colors[i],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        for (int i = 0; i < targets.length; i++) {
          final RenderBox box = tester.renderObject<RenderBox>(
            find.byKey(ValueKey<int>(i)),
          );
          final Rect actual = logicalClientRect(box);
          expect(actual, targets[i]);
          await tester.tapAt(actual.center);
          await tester.pump();
          expect(taps[i], 1);
        }
        final RenderView view = tester.binding.renderViews.single;
        expect(view.size, const Size(1280, 780));
        final OffsetLayer layer = view.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final ui.Image image = await captureLogicalView(view, layer);
          try {
            expect(image.width, 1280);
            expect(image.height, 780);
            final ByteData? data = await image.toByteData();
            expect(data, isNotNull);
            for (int i = 0; i < targets.length; i++) {
              final Offset center = targets[i].center;
              final int offset =
                  (center.dy.toInt() * 1280 + center.dx.toInt()) * 4;
              final List<int> rgba = data!.buffer.asUint8List(
                data.offsetInBytes + offset,
                4,
              );
              expect(rgba, <int>[
                if (i == 0) 255 else 0,
                if (i == 1) 255 else 0,
                if (i == 2) 255 else 0,
                255,
              ]);
            }
          } finally {
            image.dispose();
          }
        });

        // Exercise the caption offset and retained nested page layers too.
        // Existing direct capture and logical pointer assertions stay above.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const Column(
                    children: <Widget>[
                      SizedBox(height: 32),
                      Expanded(
                        child: ClipRRect(
                          key: ValueKey<String>('window-body'),
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                          child: RepaintBoundary(
                            child: Stack(
                              children: <Widget>[
                                Positioned(
                                  left: 8, top: 4, width: 80, height: 16,
                                  child: ColoredBox(
                                    key: ValueKey<String>('home_send'),
                                    color: Color(0xFFFF0000),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned.fill(
                    child: Overlay.wrap(
                      child: const Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          key: ValueKey<String>('window-caption'),
                          height: 32, width: 1280,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        final List<Map<String, Object?>> before = observeReadonlyShotLayout(
          tester.binding.rootElement,
        );
        Map<String, Object?> row(String key) => before.singleWhere(
          (Map<String, Object?> value) => value['key'] == key,
        );
        expect(row('window-caption')['rect'], <int>[0, 0, 1280, 32]);
        expect(row('window-body')['rect'], <int>[0, 32, 1280, 780]);
        expect(row('home_send')['rect'], <int>[8, 36, 88, 52]);
        final RenderView nestedView = tester.binding.renderViews.single;
        final OffsetLayer nestedLayer = nestedView.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final ui.Image image = await captureLogicalView(
            nestedView, nestedLayer,
          );
          try {
            expect(image.width, 1280);
            expect(image.height, 780);
            final ByteData? rgba = await image.toByteData();
            expect(rgba, isNotNull);
            List<int> pixel(int y) => rgba!.buffer.asUint8List(
              rgba.offsetInBytes + (y * 1280 + 48) * 4, 4,
            );
            expect(pixel(44), <int>[255, 0, 0, 255]);
            expect(pixel(12), <int>[0, 0, 0, 255]);
          } finally {
            image.dispose();
          }
        });
        final List<Map<String, Object?>> after = observeReadonlyShotLayout(
          tester.binding.rootElement,
        );
        expect(pairReadonlyShotLayout(before, after)['unchanged'], isTrue);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < 2; i++)
                  const SizedBox(
                    width: 20, height: 20,
                    child: ColoredBox(
                      key: ValueKey<String>('home_send'),
                      color: Color(0xFFFF0000),
                    ),
                  ),
                const Offstage(
                  child: SizedBox(
                    key: ValueKey<String>('node_settings_add'),
                    child: Text('Synthetic private sentinel'),
                  ),
                ),
                const SizedBox(key: ValueKey<String>('Synthetic private key')),
              ],
            ),
          ),
        );
        final List<Map<String, Object?>> changed = observeReadonlyShotLayout(
          tester.binding.rootElement,
        );
        expect(changed.singleWhere((Map<String, Object?> row) =>
            row['key'] == 'home_send'), <String, Object?>{
          'key': 'home_send', 'status': 'DUPLICATE',
        });
        expect(changed.singleWhere((Map<String, Object?> row) =>
            row['key'] == 'node_settings_add'), <String, Object?>{
          'key': 'node_settings_add', 'status': 'MISSING',
        });
        expect(jsonEncode(changed), isNot(contains('Synthetic private')));
        expect(pairReadonlyShotLayout(before, changed)['unchanged'], isFalse);
      },
    );
  }
}
