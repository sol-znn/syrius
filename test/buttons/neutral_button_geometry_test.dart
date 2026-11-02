import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/loading_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

enum _Kind { quiet, secondary, card, step }

const Timeout _caseTimeout = Timeout(Duration(seconds: 20));
const Map<_Kind, double> _height = <_Kind, double>{
  _Kind.quiet: 38,
  _Kind.secondary: 38,
  _Kind.card: 30,
  _Kind.step: 38,
};

Key _key(_Kind kind) => ValueKey<String>('neutral_${kind.name}');
Finder _button(_Kind kind) => find.byKey(_key(kind));
Finder _surface(Finder button) =>
    find.descendant(of: button, matching: find.byType(Material));

ButtonStyle _style(BuildContext context, _Kind kind) => switch (kind) {
  _Kind.quiet => quietButtonStyle(context),
  _Kind.secondary => secondaryButtonStyle(context),
  _Kind.card => cardSecondaryButtonStyle(context),
  _Kind.step => stepSecondaryButtonStyle(context),
};

Widget _control(
  BuildContext context,
  _Kind kind, {
  required VoidCallback? onPressed,
  String? label,
  ButtonStyle? style,
  FocusNode? focusNode,
  WidgetStatesController? states,
}) {
  if (kind == _Kind.quiet) {
    return TextButton(
      key: _key(kind),
      style: style ?? _style(context, kind),
      onPressed: onPressed,
      focusNode: focusNode,
      statesController: states,
      child: Text(label ?? kind.name),
    );
  }
  return OutlinedButton(
    key: _key(kind),
    style: style ?? _style(context, kind),
    onPressed: onPressed,
    focusNode: focusNode,
    statesController: states,
    child: Text(label ?? kind.name),
  );
}

Widget _host(
  WidgetBuilder builder, {
  required bool light,
  double scale = 1,
}) => MaterialApp(
  theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  ),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Center(child: Builder(builder: builder)),
    ),
  ),
);

void _expectHeight(WidgetTester tester, _Kind kind, double height) {
  expect(_surface(_button(kind)), findsOneWidget);
  expect(tester.getSize(_surface(_button(kind))).height, height);
  expect(tester.getSize(_button(kind)).height, height);
}

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'neutral geometry and original callbacks, light $light',
      (WidgetTester tester) async {
        final List<int> calls = List<int>.filled(_Kind.values.length, 0);
        final List<VoidCallback> callbacks = List<VoidCallback>.generate(
          _Kind.values.length,
          (int index) => () {
            calls[index]++;
          },
        );
        await tester.pumpWidget(
          _host(
            (BuildContext context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final _Kind kind in _Kind.values)
                  _control(
                    context,
                    kind,
                    onPressed: callbacks[kind.index],
                  ),
              ],
            ),
            light: light,
          ),
        );
        for (final _Kind kind in _Kind.values) {
          _expectHeight(tester, kind, _height[kind]!);
          final ButtonStyleButton button = tester.widget<ButtonStyleButton>(
            _button(kind),
          );
          final ButtonStyle style = button.style!;
          expect(style.visualDensity, VisualDensity.standard);
          expect(style.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
          expect(identical(button.onPressed, callbacks[kind.index]), isTrue);
          final TextStyle text = style.textStyle!.resolve(<WidgetState>{})!;
          expect(text.fontSize, kind == _Kind.card ? 13 : 14);
          expect(
            text.fontWeight,
            kind == _Kind.card ? FontWeight.w500 : FontWeight.w600,
          );
          expect(
            style.padding!.resolve(<WidgetState>{})!.resolve(TextDirection.ltr),
            EdgeInsets.symmetric(horizontal: kind == _Kind.card ? 12 : 16),
          );
          await tester.tap(_button(kind));
        }
        expect(calls, <int>[1, 1, 1, 1]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: _caseTimeout,
    );

    for (final _Kind kind in _Kind.values) {
      testWidgets(
        '${kind.name} hover, focus and disabled geometry, light $light',
        (WidgetTester tester) async {
          final WidgetStatesController states = WidgetStatesController();
          final FocusNode focus = FocusNode();
          final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
          final TestGesture mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          int calls = 0;
          await mouse.addPointer();
          try {
            await tester.pumpWidget(
              _host(
                (BuildContext context) => ValueListenableBuilder<bool>(
                  valueListenable: enabled,
                  builder: (_, bool active, _) => _control(
                    context,
                    kind,
                    onPressed: active ? () => calls++ : null,
                    focusNode: focus,
                    states: states,
                  ),
                ),
                light: light,
              ),
            );
            _expectHeight(tester, kind, _height[kind]!);
            await mouse.moveTo(tester.getCenter(_button(kind)));
            await tester.pump(const Duration(milliseconds: 250));
            expect(states.value, contains(WidgetState.hovered));
            if (kind == _Kind.quiet) {
              expect(
                tester
                    .widget<Material>(_surface(_button(kind)))
                    .textStyle!
                    .color,
                Theme.of(
                  tester.element(_button(kind)),
                ).textTheme.bodyLarge!.color,
              );
            }
            _expectHeight(tester, kind, _height[kind]!);
            await mouse.moveTo(Offset.zero);
            focus.requestFocus();
            await tester.pump(const Duration(milliseconds: 250));
            expect(states.value, contains(WidgetState.focused));
            _expectHeight(tester, kind, _height[kind]!);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(calls, 1);
            enabled.value = false;
            await tester.pump(const Duration(milliseconds: 250));
            expect(states.value, contains(WidgetState.disabled));
            if (kind == _Kind.quiet || kind == _Kind.secondary) {
              expect(
                tester
                    .widget<Material>(_surface(_button(kind)))
                    .textStyle!
                    .color,
                AppColors.faint,
              );
            }
            expect(
              tester.widget<ButtonStyleButton>(_button(kind)).onPressed,
              isNull,
            );
            _expectHeight(tester, kind, _height[kind]!);
            await tester.tap(_button(kind));
            await tester.pump();
            expect(calls, 1);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await mouse.removePointer();
            enabled.dispose();
            focus.dispose();
            states.dispose();
          }
        },
        timeout: _caseTimeout,
      );
    }

    testWidgets(
      'neutral content grows above its minimum, light $light',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _host(
            (BuildContext context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final _Kind kind in _Kind.values)
                  _control(
                    context,
                    kind,
                    label: 'A longer action',
                    onPressed: () {},
                  ),
              ],
            ),
            light: light,
            scale: 3,
          ),
        );
        for (final _Kind kind in _Kind.values) {
          expect(
            tester.getSize(_surface(_button(kind))).height,
            greaterThan(_height[kind]!),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: _caseTimeout,
    );

    testWidgets(
      'caller minimum and tight parent stay authoritative, light $light',
      (WidgetTester tester) async {
        int calls = 0;
        await tester.pumpWidget(
          _host(
            (BuildContext context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _control(
                  context,
                  _Kind.card,
                  style: cardSecondaryButtonStyle(context).copyWith(
                    minimumSize: const WidgetStatePropertyAll<Size>(
                      Size(180, 46),
                    ),
                  ),
                  onPressed: () => calls++,
                ),
                SizedBox(
                  height: 24,
                  child: _control(
                    context,
                    _Kind.quiet,
                    onPressed: () => calls++,
                  ),
                ),
              ],
            ),
            light: light,
          ),
        );
        _expectHeight(tester, _Kind.card, 46);
        expect(
          tester.getSize(_button(_Kind.card)).width,
          greaterThanOrEqualTo(180),
        );
        _expectHeight(tester, _Kind.quiet, 24);
        await tester.tap(_button(_Kind.card));
        await tester.tap(_button(_Kind.quiet));
        expect(calls, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: _caseTimeout,
    );

    testWidgets(
      'legacy LoadingButton keeps its authored 40 minimum, light $light',
      (WidgetTester tester) async {
        int calls = 0;
        await tester.pumpWidget(
          _host(
            (BuildContext _) => CardSecondaryButtons(
              child: LoadingButton(
                key: const Key('legacy_explicit_minimum'),
                text: 'Undelegate',
                onPressed: () => calls++,
              ),
            ),
            light: light,
          ),
        );
        final Finder button = find.byType(OutlinedButton);
        expect(button, findsOneWidget);
        final ButtonStyle style = tester.widget<OutlinedButton>(button).style!;
        expect(style.minimumSize!.resolve(<WidgetState>{})!.height, 40);
        expect(
          OutlinedButtonTheme.of(tester.element(button)).style!.visualDensity,
          VisualDensity.standard,
        );
        expect(tester.getSize(_surface(button)).height, 40);
        expect(tester.getSize(button).height, 40);
        await tester.tap(button);
        expect(calls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: _caseTimeout,
    );
  }
}
