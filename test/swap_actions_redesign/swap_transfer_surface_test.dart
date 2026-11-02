import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

Widget _surface(
  TextEditingController amount, {
  bool visible = true,
  SwapDollarBuilder dollars = fixtureDollars,
  VoidCallback? onClose,
}) => SwapTransferSurface(
  title: 'Start swap',
  marker: const Key('fixture_transfer'),
  onClose: onClose ?? () {},
  send: SwapAmountPane(
    label: 'You send',
    token: kZnnCoin,
    controller: amount,
    visible: visible,
    balance: BigInt.from(120450000000),
    dollars: dollars,
    choices: <Token>[kZnnCoin, kQsrCoin],
    onChanged: (_) {},
    onToken: (_) {},
    onMax: () {},
  ),
  receive: SwapAmountPane(
    label: 'You receive',
    token: kQsrCoin,
    amount: BigInt.from(100000000000),
    visible: visible,
    dollars: dollars,
  ),
  counterparty: SwapIdentifier(fixtureAddress(3)),
  rate: SwapRate(
    fromAmount: BigInt.from(10000000000),
    fromToken: kZnnCoin,
    toAmount: BigInt.from(100000000000),
    toToken: kQsrCoin,
  ),
  timing: '8 h initial · 1 h counter',
  primary: SeamGate(
    seam: Seam.swapTerms,
    child: SwapPrimaryAction(label: 'Start swap', onPressed: () {}),
  ),
  details: SwapActionDetails(
    summary: 'Fixture summary',
    onToggle: () => true,
    child: OutlinedButton(
      key: const Key('fixture_deposit'),
      onPressed: () {},
      child: const Text('Create deposit'),
    ),
  ),
);

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'the ${light ? 'light' : 'dark'} surface uses 480 pixels and exact data',
      (WidgetTester tester) async {
        prepareSwapViewport(tester);
        final TextEditingController amount = TextEditingController(text: '100');
        addTearDown(amount.dispose);
        await tester.pumpWidget(swapHost(_surface(amount), light: light));
        expect(
          tester.getSize(find.byKey(const Key('fixture_transfer'))).width,
          480,
        );
        expect(find.text('1 ZNN = 10 QSR'), findsOneWidget);
        expect(find.byKey(const Key('fixture_dollars')), findsNWidgets(2));
        expect(find.byKey(const Key('fixture_deposit')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'token choice keeps 34 px and ownership in compact density, $light',
      (WidgetTester tester) async {
        prepareSwapViewport(tester);
        final TextEditingController amount = TextEditingController(
          text: '7.00000001',
        );
        addTearDown(amount.dispose);
        final ThemeData theme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
              visualDensity: VisualDensity.compact,
            );
        final List<String> selected = <String>[];
        final String qsr = kQsrCoin.tokenStandard.toString();
        bool editable = true;
        bool current = true;

        Future<void> show({double scale = 1}) async {
          await tester.pumpWidget(
            swapHost(
              Theme(
                data: theme,
                child: SizedBox(
                  width: 480,
                  child: SwapAmountPane(
                    label: 'You send',
                    token: kZnnCoin,
                    visible: false,
                    controller: amount,
                    choices: <Token>[kZnnCoin, kQsrCoin],
                    onChanged: editable ? (String _) {} : null,
                    onToken: editable ? selected.add : null,
                    canInteract: () => current,
                    dollars: fixtureDollars,
                  ),
                ),
              ),
              light: light,
              scale: scale,
            ),
          );
          await tester.pump();
        }

        final Finder button = find.descendant(
          of: find.byType(SwapChoice),
          matching: find.byType(OutlinedButton),
        );
        final Finder qsrItem = find.widgetWithText(MenuItemButton, 'QSR');
        await show();
        expect(
          Theme.of(tester.element(button)).visualDensity,
          VisualDensity.compact,
        );
        expect(tester.getSize(button).height, 34);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        await tester.pump();
        expect(qsrItem, findsOneWidget);
        final VoidCallback retained = tester
            .widget<MenuItemButton>(qsrItem)
            .onPressed!;
        await tester.tap(qsrItem);
        await tester.pump(const Duration(milliseconds: 241));
        expect(selected, <String>[qsr]);
        expect(amount.text, '7.00000001');

        await tester.tap(button);
        await tester.pump();
        current = false;
        await tester.tap(qsrItem);
        await tester.pump(const Duration(milliseconds: 241));
        retained();
        await tester.tap(button);
        await tester.pump();
        expect(selected, <String>[qsr]);
        expect(find.byType(MenuItemButton), findsNothing);

        editable = false;
        await show();
        expect(tester.getSize(button).height, 34);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(selected, <String>[qsr]);

        current = true;
        editable = true;
        await show(scale: 2);
        final Rect bounds = tester.getRect(button);
        final Rect label = tester.getRect(
          find.descendant(of: button, matching: find.text('ZNN')),
        );
        expect(bounds.height, greaterThan(34));
        expect(label.top, greaterThanOrEqualTo(bounds.top));
        expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
        editable = false;
        await show(scale: 2);
        expect(tester.getSize(button).height, greaterThan(34));
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        expect(amount.text, '7.00000001');
        expect(selected, <String>[qsr]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('scaled narrow RTL remains scrollable without overflowing', (
    WidgetTester tester,
  ) async {
    const Size size = Size(360, 620);
    prepareSwapViewport(tester, size: size);
    final TextEditingController amount = TextEditingController(
      text: '9007199254740993.12345678',
    );
    addTearDown(amount.dispose);
    await tester.pumpWidget(
      swapHost(_surface(amount), rtl: true, scale: 2.5, size: size),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('swap_action_scroll')), findsOneWidget);
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('swap_amount_input')),
    );
    expect(field.textDirection, TextDirection.ltr);
    await tester.drag(
      find.byKey(const Key('swap_action_scroll')),
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden or ticker-muted panes never construct dollar art', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final TextEditingController amount = TextEditingController(text: '100');
    addTearDown(amount.dispose);
    int constructed = 0;
    Widget dollars(BuildContext context, BigInt value, Token token) {
      constructed++;
      return const Text('Finite dollars');
    }

    await tester.pumpWidget(
      swapHost(_surface(amount, visible: false, dollars: dollars)),
    );
    expect(constructed, 0);
    await tester.pumpWidget(
      swapHost(_surface(amount, dollars: dollars), enabled: false),
    );
    expect(constructed, 0);
    await tester.pumpWidget(swapHost(_surface(amount, dollars: dollars)));
    expect(constructed, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the offer gate denies pointer, keyboard and semantic activation',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        int calls = 0;
        await tester.pumpWidget(
          swapHost(
            SeamGate(
              key: const Key('fixture_gate'),
              seam: Seam.swapTerms,
              child: SwapPrimaryAction(
                label: 'Start swap',
                onPressed: () => calls++,
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('fixture_gate')));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(calls, 0);
        final SemanticsNode node = tester.getSemantics(
          find.byKey(const Key('fixture_gate')),
        );
        expect(node.flagsCollection.isEnabled, isNot(Tristate.none));
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    },
  );

  test(
    'the direct offer service refuses before any UI or wallet work',
    () async {
      await expectLater(
        const UnbuiltSwapTermsService().start(),
        throwsA(
          isA<SeamNotBuilt>().having(
            (SeamNotBuilt value) => value.seam,
            'seam',
            Seam.swapTerms,
          ),
        ),
      );
    },
  );

  testWidgets(
    'Details keeps its full clock when OS animation effects are disabled',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        swapHost(
          SwapActionDetails(
            summary: 'Fixture',
            onToggle: () => true,
            child: const Text('Fixture details', key: Key('fixture_details')),
          ),
        ),
      );
      expect(find.byKey(const Key('fixture_details')), findsNothing);
      await tester.tap(find.byKey(const Key('swap_action_details_toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final SizeTransition transition = tester.widget<SizeTransition>(
        find.byType(SizeTransition),
      );
      expect(transition.sizeFactor.value, greaterThan(0));
      expect(transition.sizeFactor.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 121));
      expect(
        tester
            .widget<SizeTransition>(find.byType(SizeTransition))
            .sizeFactor
            .value,
        1,
      );
      await tester.tap(find.byKey(const Key('swap_action_details_toggle')));
      await tester.pump();
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .descendant(
                    of: find.byType(SwapActionDetails),
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 241));
      expect(find.byKey(const Key('fixture_details')), findsNothing);
    },
  );

  testWidgets('a stale Details toggle cannot reveal its actions', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    bool current = true;
    await tester.pumpWidget(
      swapHost(
        SwapActionDetails(
          summary: 'Fixture',
          onToggle: () => current,
          child: const Text('Fixture details'),
        ),
      ),
    );
    final VoidCallback saved = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('swap_action_details_toggle')),
        )
        .onPressed!;
    current = false;
    saved();
    await tester.pump(const Duration(milliseconds: 241));
    expect(find.text('Fixture details'), findsNothing);
  });

  testWidgets(
    'Tab and Enter reach a real close action without entering the offer',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      int closed = 0;
      await tester.pumpWidget(
        swapHost(
          SwapDialogSurface(
            title: 'Fixture',
            marker: const Key('fixture'),
            onClose: () => closed++,
            primary: SeamGate(
              seam: Seam.swapTerms,
              child: SwapPrimaryAction(label: 'Start swap', onPressed: () {}),
            ),
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(closed, 1);
    },
  );

  testWidgets('semantic errors use crimson rather than the reserved accent', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    await tester.pumpWidget(
      swapHost(const SwapNotice('Synthetic refusal', error: true)),
    );
    final BuildContext context = tester.element(find.byType(SwapNotice));
    final Icon icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppTokens.of(context).error);
    expect(icon.color, isNot(AppTokens.of(context).pink));
  });
}
