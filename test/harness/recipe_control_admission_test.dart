import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../harness/app/recipe_control_admission.dart';
import '../welcome/support.dart';

void main() {
  const Map<String, String?> cases = <String, String?>{
    'unchanged': null,
    'replacement': 'wallet-recipe-original-control-replaced',
    'movement': 'wallet-recipe-original-control-moved',
    'subpixel': 'wallet-recipe-original-control-moved-subpixel',
    'resize': 'wallet-recipe-original-control-resized',
  };
  for (final MapEntry<String, String?> entry in cases.entries) {
    testWidgets('original control geometry labels ${entry.key}', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      bool changed = false;
      bool armed = false;
      int taps = 0;
      await tester.pumpWidget(welcomeHost(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(80),
          child: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) =>
                  MouseRegion(
                    onEnter: (_) {
                      if (armed && !changed) {
                        setState(() => changed = true);
                      }
                    },
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        !changed ? 0 : switch (entry.key) {
                          'movement' => 8,
                          'subpixel' => 0.125,
                          _ => 0,
                        },
                      ),
                      child: KeyedSubtree(
                        key: ValueKey<bool>(
                          changed && entry.key == 'replacement',
                        ),
                        child: SizedBox(
                          width: 320,
                          height: changed && entry.key == 'resize' ? 64 : 44,
                          child: Material(
                            child: InkWell(
                              key: const Key('node_settings_chain_toggle'),
                              onTap: () => taps++,
                              child: const Center(child: Text('Client chain')),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      )));
      final Finder control = find.byKey(
        const Key('node_settings_chain_toggle'),
      );
      final Element original = tester.element(control);
      final Rect originalRect = tester.getRect(control);
      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      armed = true;
      await mouse.moveTo(originalRect.center);
      await tester.pump();
      expect(changed, isTrue);
      final Element current = tester.element(control);
      final Rect currentRect = tester.getRect(control);
      expect(identical(current, original), entry.key != 'replacement');
      expect(recipeControlChange(
        original: original,
        current: current,
        originalRect: originalRect,
        currentRect: currentRect,
      ), entry.value);
      // Reading the original render geometry does not dispatch input.
      expect(taps, 0);
      if (entry.value == null) {
        await tester.tap(control);
        expect(taps, 1);
      }
      await mouse.removePointer();
    });
  }
}
