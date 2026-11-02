import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/widgets/token_create_frame.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/step_switcher.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

void main() {
  for (final TextDirection direction in TextDirection.values) {
    testWidgets(
      'rapid reversal retains bodies and the full 300 ms gate in $direction',
      (WidgetTester tester) async {
        final ValueNotifier<int> step = ValueNotifier<int>(0);
        final List<int> activations = <int>[];
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: SizedBox(
                    width: 640,
                    height: 400,
                    child: ValueListenableBuilder<int>(
                      valueListenable: step,
                      builder: (_, int selected, _) => StepSwitcher.retained(
                        step: selected,
                        layoutBuilder: (_, List<Widget> entries) => Stack(
                          fit: StackFit.expand,
                          children: entries,
                        ),
                        children: <Widget>[
                          for (int i = 0; i < 2; i++)
                            TokenCreateFrame(
                              key: ValueKey<String>('frame_$i'),
                              active: selected == i,
                              onSubmit: () => activations.add(i),
                              label: 'Continue $i',
                              body: TextField(key: ValueKey<String>('body_$i')),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 1));
          final State original = tester.state(
            find.byKey(const ValueKey<String>('body_0')),
          );
          await tester.enterText(
            find.byKey(const ValueKey<String>('body_0')),
            'Retained draft',
          );
          step.value = 1;
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 149));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(activations, isEmpty);
          step.value = 0;
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 299));
          final BuildContext fields = tester.element(
            find.byKey(const ValueKey<String>('body_0')),
          );
          expect(StepInteraction.of(fields), isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(activations, isEmpty);
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 1));
          expect(StepInteraction.of(fields), isTrue);
          expect(
            tester.state(find.byKey(const ValueKey<String>('body_0'))),
            same(original),
          );
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.byKey(const ValueKey<String>('body_0')),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            'Retained draft',
          );
          await tester.tap(find.text('Continue 0'));
          expect(activations, <int>[0]);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          step.dispose();
        }
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
