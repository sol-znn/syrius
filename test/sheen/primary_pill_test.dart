import 'package:flutter/foundation.dart' as foundation show TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/widgets/send_button.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

Widget _app(Widget child, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: child)),
);

Widget _desktopApp(
  Widget child,
  ThemeData theme, {
  VisualDensity density = VisualDensity.compact,
}) => MaterialApp(
  theme: theme.copyWith(
    platform: foundation.TargetPlatform.windows,
    visualDensity: density,
  ),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: Center(child: child)),
);

Finder get _gradient => find.descendant(
  of: find.byType(PrimaryPill),
  matching: find.byWidgetPredicate(
    (Widget widget) =>
        widget is DecoratedBox &&
        widget.decoration is ShapeDecoration &&
        (widget.decoration as ShapeDecoration).gradient != null,
  ),
);

void main() {
  for (final ThemeData theme in <ThemeData>[
    AppTheme.darkTheme,
    AppTheme.lightTheme,
  ]) {
    testWidgets('primary plasma fill in ${theme.brightness.name}', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(PrimaryPill(onPressed: () {}, child: const Text('Stake')), theme),
      );
      final AppTokens tokens = theme.extension<AppTokens>()!;
      expect(_gradient, findsOneWidget);
      final ShapeDecoration decoration =
          tester.widget<DecoratedBox>(_gradient).decoration as ShapeDecoration;
      expect(decoration.gradient, tokens.plasma);
      expect(decoration.shape, const StadiumBorder());
      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(
        button.style!.backgroundColor!.resolve(<WidgetState>{}),
        Colors.transparent,
      );
      expect(
        button.style!.foregroundColor!.resolve(<WidgetState>{}),
        tokens.primaryButtonForeground,
      );
    });

    testWidgets(
      'requested heights survive desktop density in ${theme.brightness.name}',
      (WidgetTester tester) async {
        for (final VisualDensity density in const <VisualDensity>[
          VisualDensity.standard,
          VisualDensity.compact,
        ]) {
          for (final double height in const <double>[26, 30, 38, 42, 46, 58]) {
            await tester.pumpWidget(
              _desktopApp(
                PrimaryPill(
                  onPressed: () {},
                  style: height == 38
                      ? null
                      : ButtonStyle(
                          minimumSize: WidgetStatePropertyAll<Size>(
                            Size(0, height),
                          ),
                        ),
                  icon: const Icon(Icons.add, size: 18),
                  child: const Text('Continue'),
                ),
                theme,
                density: density,
              ),
            );
            expect(
              Theme.of(tester.element(find.byType(PrimaryPill))).visualDensity,
              density,
            );
            expect(tester.getSize(find.byType(PrimaryPill)).height, height);
            expect(tester.getSize(find.byType(OutlinedButton)).height, height);
            expect(tester.takeException(), isNull);
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'explicit caller density and fixed size survive in '
      '${theme.brightness.name}',
      (WidgetTester tester) async {
        for (final bool compact in const <bool>[false, true]) {
          await tester.pumpWidget(
            _desktopApp(
              PrimaryPill(
                onPressed: () {},
                style: ButtonStyle(
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  minimumSize: const WidgetStatePropertyAll<Size>(
                    Size(140, 38),
                  ),
                ),
                child: const Text('Continue'),
              ),
              theme,
            ),
          );
          expect(
            tester.getSize(find.byType(OutlinedButton)).height,
            compact ? 30 : 38,
          );
        }
        await tester.pumpWidget(
          _desktopApp(
            PrimaryPill(
              onPressed: () {},
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                fixedSize: WidgetStatePropertyAll<Size>(Size(140, 46)),
              ),
              child: const Text('Continue'),
            ),
            theme,
          ),
        );
        expect(tester.getSize(find.byType(PrimaryPill)), const Size(140, 46));
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'tight Send and Lock constraints stay 46 in ${theme.brightness.name}',
      (WidgetTester tester) async {
        final AppTokens tokens = theme.extension<AppTokens>()!;
        const Key sendKey = Key('fixture_send');
        const Key lockKey = Key('fixture_lock');
        int sends = 0;
        int unlocks = 0;
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await tester.pumpWidget(
          _desktopApp(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SendButton(
                  key: sendKey,
                  onPressed: () => sends++,
                  text: 'Send',
                ),
                // LockCard gives its pill this same direct height constraint.
                SizedBox(
                  height: tokens.lockActionHeight,
                  child: PrimaryPill(
                    key: lockKey,
                    onPressed: () => unlocks++,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      minimumSize: WidgetStatePropertyAll<Size>(
                        Size(0, tokens.lockActionHeight),
                      ),
                    ),
                    icon: const Icon(Icons.lock_outline, size: 18),
                    child: const Text('Unlock'),
                  ),
                ),
              ],
            ),
            theme,
          ),
        );
        final Finder sendPill = find.descendant(
          of: find.byKey(sendKey),
          matching: find.byType(PrimaryPill),
        );
        for (final Finder pill in <Finder>[sendPill, find.byKey(lockKey)]) {
          expect(tester.getSize(pill).height, 46);
          expect(
            tester
                .getSize(
                  find.descendant(
                    of: pill,
                    matching: find.byType(OutlinedButton),
                  ),
                )
                .height,
            46,
          );
        }
        await tester.tap(sendPill);
        await tester.tap(find.byKey(lockKey));
        await tester.pump();
        expect(sends, 1);
        expect(unlocks, 1);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'desktop Send preserves keyboard, busy and repeat behavior in '
      '${theme.brightness.name}',
      (WidgetTester tester) async {
        final GlobalKey<SendButtonState> key = GlobalKey<SendButtonState>();
        int presses = 0;
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await tester.pumpWidget(
          _desktopApp(
            SendButton(
              key: key,
              onPressed: () => presses++,
              text: 'Send',
            ),
            theme,
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 2);
        key.currentState!.animateForward();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.getSize(find.byType(PrimaryPill)).height, 46);
        await tester.tap(find.byType(OutlinedButton));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 2);
        key.currentState!.animateReverse();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 3);
        await tester.tap(find.byType(OutlinedButton));
        await tester.pump();
        expect(presses, 4);
        expect(tester.getSize(find.byType(PrimaryPill)).height, 46);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets('disabled action dims its fill without changing geometry', (
    WidgetTester tester,
  ) async {
    const AppTokens tokens = AppTokens.dark;
    await tester.pumpWidget(
      _app(
        PrimaryPill(onPressed: () {}, child: const Text('Stake')),
        AppTheme.darkTheme,
      ),
    );
    final Size enabledSize = tester.getSize(find.byType(PrimaryPill));
    await tester.pumpWidget(
      _app(
        const PrimaryPill(onPressed: null, child: Text('Stake')),
        AppTheme.darkTheme,
      ),
    );
    expect(_gradient, findsOneWidget);
    expect(tester.getSize(find.byType(PrimaryPill)), enabledSize);
    final Finder opacity = find.descendant(
      of: find.byType(PrimaryPill),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, tokens.disabledOpacity);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('keyboard activation and caller sizing survive decoration', (
    WidgetTester tester,
  ) async {
    int presses = 0;
    await tester.pumpWidget(
      _app(
        PrimaryPill(
          onPressed: () => presses++,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll<Size>(Size(180, 48)),
          ),
          icon: const Icon(Icons.add),
          child: const Text('Stake'),
        ),
        AppTheme.darkTheme,
      ),
    );
    final Finder button = find.byType(OutlinedButton);
    expect(tester.getSize(button).width, greaterThanOrEqualTo(180));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    final Icon icon = tester.widget<Icon>(find.byIcon(Icons.add));
    expect(
      IconTheme.of(tester.element(find.byWidget(icon))).color,
      AppTokens.dark.primaryButtonForeground,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });
}
