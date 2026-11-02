import 'dart:ui' show ImageFilter;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/dialogs.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

/// The frost: the blurred, tinted barrier behind dialogs and the Go to
/// palette. What is checked is that the blur follows the route in and out,
/// that the barrier still dismisses exactly when the route says so, and that
/// the shared helpers answer as they did before they were switched to it.
Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  home: Scaffold(body: child),
);

/// A button that opens a frosted dialog saying "inside".
Widget _opener({bool dismissible = true, List<Object?>? answers}) => Builder(
  builder: (BuildContext context) => TextButton(
    onPressed: () async {
      final Object? answer = await showFrostedDialog<String>(
        context: context,
        barrierDismissible: dismissible,
        builder: (BuildContext context) => Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context, 'done'),
            child: const Text('inside'),
          ),
        ),
      );
      answers?.add(answer);
    },
    child: const Text('open'),
  ),
);

BackdropFilter _filter(WidgetTester tester) => tester.widget<BackdropFilter>(
  find.descendant(
    of: find.byType(FrostedBarrier),
    matching: find.byType(BackdropFilter),
  ),
);

FrostedBarrier _barrier(WidgetTester tester) =>
    tester.widget<FrostedBarrier>(find.byType(FrostedBarrier));

ImageFilter _blur(double sigma) =>
    ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);

Color _tint(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(
        of: find.byType(FrostedBarrier),
        matching: find.byType(ColoredBox),
      ),
    )
    .color;

void main() {
  testWidgets('the helper pushes a frosted route with one clipped blur', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_opener()));
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final BuildContext inside = tester.element(find.text('inside'));
    expect(ModalRoute.of(inside), isA<FrostedDialogRoute<String>>());
    // One blur for the whole window, and it is the barrier's.
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FrostedBarrier),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.descendant(
          of: find.byType(FrostedBarrier),
          matching: find.byType(ClipRect),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the blur and the tint grow with the route and reverse on pop', (
    WidgetTester tester,
  ) async {
    final List<Object?> answers = <Object?>[];
    await tester.pumpWidget(_app(_opener(answers: answers)));

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(_barrier(tester).animation.value, 0);
    expect(_filter(tester).filter, _blur(0));
    expect(_filter(tester).enabled, isFalse);
    expect(_tint(tester).a, 0);

    // Half of the route's 150 ms.
    await tester.pump(const Duration(milliseconds: 75));
    final double rising = _barrier(tester).animation.value;
    expect(rising, greaterThan(0));
    expect(rising, lessThan(1));
    expect(_filter(tester).filter, _blur(kFrostSigma * rising));
    expect(_filter(tester).enabled, isTrue);
    expect(_tint(tester).a, closeTo(kFrostTintOpacity * rising, 1e-6));

    await tester.pumpAndSettle();
    expect(_filter(tester).filter, _blur(kFrostSigma));
    expect(_tint(tester).a, closeTo(kFrostTintOpacity, 1e-6));

    await tester.tap(find.text('inside'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final double falling = _barrier(tester).animation.value;
    expect(falling, greaterThan(0));
    expect(falling, lessThan(1));
    expect(_filter(tester).filter, _blur(kFrostSigma * falling));

    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(answers, <Object?>['done']);
  });

  testWidgets('a tap on the barrier dismisses when the route allows it', (
    WidgetTester tester,
  ) async {
    final List<Object?> answers = <Object?>[];
    await tester.pumpWidget(_app(_opener(answers: answers)));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('inside'), findsNothing);
    expect(answers, <Object?>[null]);
  });

  testWidgets('a tap on the barrier does nothing when the route forbids it', (
    WidgetTester tester,
  ) async {
    final List<Object?> answers = <Object?>[];
    await tester.pumpWidget(
      _app(_opener(dismissible: false, answers: answers)),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('inside'), findsOneWidget);
    expect(answers, isEmpty);
    // The page underneath is still out of reach.
    await tester.tap(find.text('open'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('the tint is the scrim at the same strength in both themes', (
    WidgetTester tester,
  ) async {
    for (final ThemeData theme in <ThemeData>[
      AppTheme.darkTheme,
      AppTheme.lightTheme,
    ]) {
      await tester.pumpWidget(_app(_opener(), theme: theme));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        _tint(tester),
        theme.colorScheme.scrim.withValues(alpha: kFrostTintOpacity),
      );

      await tester.tap(find.text('inside'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a frosted route is counted while it covers the page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(_opener()));
    expect(FrostHold.count.value, 0);

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(FrostHold.count.value, 1);
    await tester.pumpAndSettle();
    expect(FrostHold.count.value, 1);

    // Released as the pop starts, so what is underneath moves again while
    // the blur clears.
    await tester.tap(find.text('inside'));
    await tester.pump();
    expect(FrostHold.count.value, 0);
    await tester.pumpAndSettle();
    expect(FrostHold.count.value, 0);
  });

  testWidgets('a bare barrier follows the animation it is given', (
    WidgetTester tester,
  ) async {
    final AnimationController controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 240),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const Text('page'),
            Positioned.fill(
              child: FrostedBarrier(
                animation: controller,
                sigma: 12,
                tint: const Color(0x80112233),
              ),
            ),
          ],
        ),
      ),
    );
    expect(_filter(tester).filter, _blur(0));
    expect(tester.getSize(find.byType(FrostedBarrier)), const Size(800, 600));

    controller.value = 0.5;
    await tester.pump();
    expect(_filter(tester).filter, _blur(6));
    expect(_tint(tester).a, closeTo(0x80 / 255 / 2, 1e-6));

    controller.value = 1;
    await tester.pump();
    expect(_filter(tester).filter, _blur(12));
    expect(_tint(tester), const Color(0x80112233));
  });

  group('the shared helpers', () {
    testWidgets('no and yes still answer, over the frost', (
      WidgetTester tester,
    ) async {
      final List<bool?> answers = <bool?>[];
      Widget opener({required bool dismissible}) => Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async => answers.add(
            await showDialogWithNoAndYesOptions(
              context: context,
              title: 'Send',
              description: 'Send 1 ZNN?',
              isBarrierDismissible: dismissible,
            ),
          ),
          child: const Text('open'),
        ),
      );
      await tester.pumpWidget(_app(opener(dismissible: true)));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      expect(find.byType(FrostedSurface), findsOneWidget);
      expect(_filter(tester).filter, _blur(kFrostSigma));
      await tester.tap(find.byKey(const Key('dialog_yes_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_no_button')));
      await tester.pumpAndSettle();

      // Dismissed through the barrier: no answer.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(answers, <bool?>[true, false, null]);

      await tester.pumpWidget(_app(opener(dismissible: false)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Send 1 ZNN?'), findsOneWidget);
      expect(answers, <bool?>[true, false, null]);
    });

    testWidgets('a warning is frosted and cannot be tapped away', (
      WidgetTester tester,
    ) async {
      final List<bool> answers = <bool>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => answers.add(
                await showWarningDialog(
                  context: context,
                  title: 'Reset',
                  description: 'This erases the wallet',
                  buttonText: 'Erase',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      expect(find.byType(FrostedSurface), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(answers, isEmpty);

      await tester.tap(find.text('Erase'));
      await tester.pumpAndSettle();
      expect(answers, <bool>[true]);
    });

    testWidgets('a custom dialog is frosted and dismissed by its barrier', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showCustomDialog(
                context: context,
                content: const SizedBox(
                  width: 200,
                  height: 100,
                  child: Text('modal'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsOneWidget);
      expect(_filter(tester).filter, _blur(kFrostSigma));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('the Go to palette opens over the frost and answers', (
      WidgetTester tester,
    ) async {
      final List<int?> answers = <int?>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => answers.add(
                await showGoToPalette<int>(
                  context: context,
                  entries: const <GoToEntry<int>>[
                    GoToEntry<int>(value: 1, label: 'Home'),
                    GoToEntry<int>(value: 2, label: 'Send'),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      expect(_filter(tester).filter, _blur(kFrostSigma));
      final BackdropFilter paletteFilter = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byType(GoToPalette<int>),
          matching: find.byType(BackdropFilter),
        ),
      );
      expect(paletteFilter.filter, _blur(AppTokens.dark.dialogBlur));
      expect(paletteFilter.backdropGroupKey, isNull);
      expect(_filter(tester).backdropGroupKey, isNull);
      expect(
        _tint(tester),
        AppTheme.darkTheme.colorScheme.scrim.withValues(
          alpha: kFrostTintOpacity,
        ),
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(answers, <int?>[2]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(answers, <int?>[2, null]);
    });
  });
}
