import 'dart:ui' as ui;

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/hero_field.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

import 'support.dart';

ImportSeedDraft _draft(String text, {int count = 12, bool valid = false}) =>
    ImportSeedDraft(
      text,
      expectedWords: count,
      isValidWord: (_) => true,
      validateMnemonic: (_) => valid,
    );

ImportSurface _surface(
  TextEditingController controller, {
  bool file = false,
  bool refused = false,
  bool pickerFailed = false,
  VoidCallback? onContinue,
  VoidCallback? onBrowse,
  ValueChanged<String>? onSeedChanged,
  ValueChanged<int>? onWordCountChanged,
}) => ImportSurface(
  seedController: controller,
  draft: _draft(controller.text),
  fileSelected: file,
  fileRefused: refused,
  pickerFailed: pickerFailed,
  onSeedChanged: onSeedChanged ?? (_) {},
  onWordCountChanged: onWordCountChanged ?? (_) {},
  onBack: () {},
  onContinue: onContinue,
  onBrowse: onBrowse ?? () {},
  background: const SizedBox.expand(),
);

const Key _paintBoundary = Key('import_paint_boundary');

Widget _compactEntry(Widget child, {required bool light}) => entryHost(
  Theme(
    data: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
      visualDensity: VisualDensity.compact,
    ),
    child: child,
  ),
  light: light,
);

Future<Color> _paintedColor(
  WidgetTester tester,
  Offset global,
) async {
  final RenderRepaintBoundary layer = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_paintBoundary));
  final Offset local = layer.globalToLocal(global);
  final Color? color = await tester.runAsync<Color>(() async {
    final ui.Image image = await layer.toImage();
    try {
      final ByteData pixels = (await image.toByteData())!;
      final int offset =
          (local.dy.floor() * image.width + local.dx.floor()) * 4;
      return Color.fromARGB(
        pixels.getUint8(offset + 3),
        pixels.getUint8(offset),
        pixels.getUint8(offset + 1),
        pixels.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  return color!;
}

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'the ${light ? 'light' : 'dark'} import view keeps its measured card',
      (
        WidgetTester tester,
      ) async {
        prepareEntryViewport(tester);
        final TextEditingController controller = TextEditingController(
          text: List<String>.generate(
            8,
            (int index) => 'fixture-$index',
          ).join(' '),
        );
        disposeEntryControllers(tester, <TextEditingController>[controller]);
        await tester.pumpWidget(entryHost(_surface(controller), light: light));
        await tester.pump(const Duration(milliseconds: 401));
        expect(
          tester.getSize(find.byKey(const Key('import_screen_marker'))).width,
          620,
        );
        expect(find.text('8 of 12'), findsOneWidget);
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Finder field = find.byKey(const Key('import_seed_field'));
        final RenderEditable seed = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        ).renderEditable;
        expect(seed.text!.style!.fontFamily, tokens.sansFontFamily);
        expect(seed.text!.style!.letterSpacing, 0);
        final Finder count = find.text('8 of 12');
        final RenderParagraph counter = tester.renderObject<RenderParagraph>(
          count,
        );
        expect(counter.text.style!.fontFamily, tokens.monoFontFamily);
        expect(counter.text.style!.fontSize, 12.5);
        expect(counter.text.style!.letterSpacing, 0);
        expect(
          tester.getBottomLeft(count).dy,
          closeTo(
            tester.getBottomLeft(
              find.byKey(const Key('import_seed_panel')),
            ).dy - tokens.transferFieldPadding.bottom - 1,
            0.01,
          ),
        );
        expect(find.byType(HeroField), findsNothing);
        expect(
          tester
              .widget<PrimaryPill>(find.byKey(const Key('import_continue')))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the ${light ? 'light' : 'dark'} import footer keeps reference measures',
      (WidgetTester tester) async {
        prepareEntryViewport(tester);
        final TextEditingController controller = TextEditingController();
        disposeEntryControllers(tester, <TextEditingController>[controller]);
        int continues = 0;
        await tester.pumpWidget(
          _compactEntry(
            _surface(
              controller,
              file: true,
              onContinue: () => continues++,
            ),
            light: light,
          ),
        );
        await tester.pump(const Duration(milliseconds: 401));
        final Finder action = find.byKey(const Key('import_continue'));
        final Finder label = find.descendant(
          of: action,
          matching: find.text('Continue'),
        );
        expect(tester.getSize(action).height, 38);
        expect(
          tester.getSize(action).width,
          closeTo(tester.getSize(label).width + 32, 0.01),
        );
        final Finder words12 = find.text('12 words');
        final Finder words24 = find.text('24 words');
        for (final Finder choice in <Finder>[words12, words24]) {
          final TextStyle style = tester.widget<Text>(choice).style!;
          expect(style.fontSize, 13);
          expect(style.fontWeight, FontWeight.w400);
          expect(
            tester.renderObject<RenderParagraph>(choice)
                .text.style!.letterSpacing,
            0,
          );
        }
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        expect(tokens.importWordChoicePadding,
            const EdgeInsets.symmetric(horizontal: 13.25, vertical: 5));
        expect(tester.widget<Segment<int>>(find.byType(Segment<int>))
            .pillPadding, tokens.importWordChoicePadding);
        // Two measured tabular-label insets, plus both 1px + 3px track sides.
        final double segmentWidth = tester.getSize(words12).width +
            tester.getSize(words24).width +
            2 * tokens.importWordChoicePadding.horizontal + 8;
        expect(
          tester.getSize(find.byType(Segment<int>)).width,
          closeTo(segmentWidth, 0.01),
        );
        await tester.tap(action);
        expect(continues, 1);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'the ${light ? 'light' : 'dark'} seed uses one stable focus boundary',
      (WidgetTester tester) async {
        prepareEntryViewport(tester);
        final TextEditingController controller = TextEditingController();
        disposeEntryControllers(tester, <TextEditingController>[controller]);
        final List<String> edits = <String>[];
        final List<int> choices = <int>[];
        await tester.pumpWidget(
          entryHost(
            _surface(
              controller,
              onSeedChanged: edits.add,
              onWordCountChanged: choices.add,
            ),
            light: light,
          ),
        );
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Finder panel = find.byKey(const Key('import_seed_panel'));
        final Finder field = find.byKey(const Key('import_seed_field'));
        BorderSide outline() =>
            (tester.widget<Container>(panel).decoration! as BoxDecoration)
                .border!
                .top;
        final Rect before = tester.getRect(panel);
        expect(before.height, 72);
        expect(outline().color, tokens.line);
        await tester.tap(field);
        await tester.pump();
        expect(tester.getRect(panel), before);
        expect(outline().color, tokens.faint);
        expect(outline().width, 1);
        final InputDecoration decoration = tester
            .widget<InputDecorator>(
              find.descendant(of: field, matching: find.byType(InputDecorator)),
            )
            .decoration;
        expect(decoration.filled, isFalse);
        for (final InputBorder? border in <InputBorder?>[
          decoration.border,
          decoration.enabledBorder,
          decoration.disabledBorder,
          decoration.focusedBorder,
          decoration.errorBorder,
          decoration.focusedErrorBorder,
        ]) {
          expect(border, InputBorder.none);
        }
        await tester.enterText(field, ' fixture  words ');
        expect(edits, <String>[' fixture  words ']);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          Focus.of(
            tester.element(find.byKey(Segment.keyOf('import_words', 12))),
          ).hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(choices, <int>[24]);
        expect(outline().color, tokens.line);
        expect(tester.getRect(panel), before);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'the ${light ? 'light' : 'dark'} drop keeps its fill under pointer hover',
      (WidgetTester tester) async {
        prepareEntryViewport(tester);
        final TextEditingController controller = TextEditingController();
        disposeEntryControllers(tester, <TextEditingController>[controller]);
        int browses = 0;
        await tester.pumpWidget(
          entryHost(
            RepaintBoundary(
              key: _paintBoundary,
              child: _surface(controller, onBrowse: () => browses++),
            ),
            light: light,
          ),
        );
        await tester.pump(const Duration(milliseconds: 401));
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Finder zone = find.byKey(const Key('import_file_zone'));
        final Offset sample = tester.getTopLeft(zone) + const Offset(30, 30);
        expect(await _paintedColor(tester, sample), tokens.card2);
        final TestGesture pointer = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        addTearDown(pointer.removePointer);
        await pointer.addPointer(location: sample);
        await tester.pump(const Duration(milliseconds: 201));
        expect(await _paintedColor(tester, sample), tokens.card2);
        expect(browses, 0);
        final Finder dashed = find.descendant(
          of: zone,
          matching: find.byType(DottedBorder),
        );
        expect(
          find.descendant(of: dashed, matching: find.byType(CustomPaint)),
          paints..path(
            color: tokens.faint,
            strokeWidth: 1.5,
            style: PaintingStyle.stroke,
          ),
        );
        await tester.tap(zone);
        expect(browses, 1);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
    'file admission displays a fact without receiving a private path',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final TextEditingController controller = TextEditingController();
      disposeEntryControllers(tester, <TextEditingController>[controller]);
      int requests = 0;
      await tester.pumpWidget(
        entryHost(
          _surface(controller, file: true, onContinue: () => requests++),
        ),
      );
      expect(find.text('Wallet file selected'), findsOneWidget);
      expect(find.textContaining('fixture.private'), findsNothing);
      await tester.tap(find.byKey(const Key('import_continue')));
      expect(requests, 1);
      await tester.pumpWidget(entryHost(_surface(controller, refused: true)));
      expect(find.text('Not a Syrius wallet file'), findsOneWidget);
      expect(find.text('Wallet file selected'), findsNothing);
      expect(
        tester
            .widget<PrimaryPill>(find.byKey(const Key('import_continue')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'a picker failure has a mapped label and no previous file action',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final TextEditingController controller = TextEditingController();
      disposeEntryControllers(tester, <TextEditingController>[controller]);
      await tester.pumpWidget(
        entryHost(_surface(controller, pickerFailed: true)),
      );
      expect(
        find.text('Could not open the file picker. Try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PrimaryPill>(find.byKey(const Key('import_continue')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'a narrow scaled RTL card retains the field and reachable action',
    (
      WidgetTester tester,
    ) async {
      const Size size = Size(540, 360);
      prepareEntryViewport(tester, size: size);
      final TextEditingController controller = TextEditingController();
      disposeEntryControllers(tester, <TextEditingController>[controller]);
      int requests = 0;
      await tester.pumpWidget(
        entryHost(
          _surface(controller, file: true, onContinue: () => requests++),
          size: size,
          rtl: true,
          scale: 2.5,
        ),
      );
      await tester.pump(const Duration(milliseconds: 401));
      await tester.ensureVisible(find.byKey(const Key('import_continue')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('import_continue')));
      expect(requests, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import_seed_field')))
            .textDirection,
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard activation requests browsing without a platform adapter',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final TextEditingController controller = TextEditingController();
      disposeEntryControllers(tester, <TextEditingController>[controller]);
      int requests = 0;
      await tester.pumpWidget(
        entryHost(_surface(controller, onBrowse: () => requests++)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(requests, 1);
    },
  );

  testWidgets(
    'pure password and unlock views obscure input and respect busy state',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final TextEditingController password = TextEditingController();
      final TextEditingController confirmation = TextEditingController();
      disposeEntryControllers(tester, <TextEditingController>[
        password,
        confirmation,
      ]);
      await tester.pumpWidget(
        entryHost(
          ImportPasswordSurface(
            password: password,
            confirmation: confirmation,
            onChanged: () {},
            onBack: () {},
            onContinue: null,
            background: const SizedBox.expand(),
          ),
        ),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import_new_password')))
            .obscureText,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import_confirm_password')))
            .obscureText,
        isTrue,
      );
      await tester.pumpWidget(
        entryHost(
          ImportUnlockSurface(
            password: password,
            onChanged: () {},
            onBack: () {},
            onContinue: () {},
            busy: true,
            error: 'Incorrect password',
            background: const SizedBox.expand(),
          ),
        ),
      );
      final TextField unlock = tester.widget<TextField>(
        find.byKey(const Key('import_unlock_password')),
      );
      expect(unlock.obscureText, isTrue);
      expect(unlock.enabled, isFalse);
      expect(
        tester
            .widget<PrimaryPill>(
              find.byKey(const Key('import_unlock_continue')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Incorrect password'), findsOneWidget);
    },
  );
}
