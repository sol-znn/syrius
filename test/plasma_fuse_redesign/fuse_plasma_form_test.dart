import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/view/fuse_plasma_disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/view/fuse_plasma_form.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

const Key _surface = Key('fixture_fuse_disclosure');
const Key _amount = Key('fuse_plasma_amount_field');
const Key _another = Key('fuse_plasma_beneficiary_address_field');
const Key _menu = Key('fuse_plasma_beneficiary_selector');
const Key _submit = Key('fuse_plasma_submit_button');

/// These labels and identifiers are injected presentation data. This fixture
/// has no wallet, sender, signer, transport, SDK owner or RPC implementation.
class _Fixture {
  final DisclosureController disclosure = DisclosureController();
  final TextEditingController amount = TextEditingController(
    text: '100.00000001',
  );
  final TextEditingController beneficiary = TextEditingController(
    text: 'z1fixturefirst',
  );
  final FocusNode amountFocus = FocusNode();
  final GlobalKey<LoadingButtonState> button = GlobalKey<LoadingButtonState>();
  late final Listenable inputs = Listenable.merge(<Listenable>[
    amount,
    beneficiary,
  ]);
  final List<(String, String)> submissions = <(String, String)>[];
  bool pageVisible = true;
  int visibilityEpoch = 0;
  bool Function()? authority;
  bool Function()? firstAuthority;
  String? amountError;

  Widget host({
    ThemeData? theme,
    TextDirection direction = TextDirection.ltr,
    double scale = 1,
    bool disableAnimations = false,
  }) {
    final int capturedVisibilityEpoch = visibilityEpoch;
    return MaterialApp(
      theme: (theme ?? AppTheme.darkTheme).copyWith(
        platform: TargetPlatform.windows,
      ),
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1280, 780),
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1000,
                height: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FusePlasmaDisclosure(
                      key: _surface,
                      controller: disclosure,
                      isCurrent: () =>
                          pageVisible &&
                          capturedVisibilityEpoch == visibilityEpoch,
                      builder: (_, bool Function() isCurrent) {
                        firstAuthority ??= isCurrent;
                        authority = isCurrent;
                        return Panel(
                          child: ListenableBuilder(
                            listenable: inputs,
                            builder: (_, _) => FusePlasmaForm(
                              amountController: amount,
                              beneficiaryController: beneficiary,
                              amountFocusNode: amountFocus,
                              buttonKey: button,
                              beneficiaries: const <FusePlasmaBeneficiary>[
                                FusePlasmaBeneficiary(
                                  address: 'z1fixturefirst',
                                  label: 'Address 1',
                                ),
                                FusePlasmaBeneficiary(
                                  address: 'z1fixturesecond',
                                  label: 'z1fixture…second',
                                  isAddress: true,
                                ),
                              ],
                              amount: BigInt.parse('10000000001'),
                              decimals: 8,
                              amountEnabled: true,
                              inputValid:
                                  amount.text.isNotEmpty &&
                                  beneficiary.text.isNotEmpty,
                              amountError: amountError,
                              beneficiaryError: null,
                              isCurrent: isCurrent,
                              onMax: () => amount.text = '200.00000001',
                              onSubmit: () => submissions.add((
                                amount.text,
                                beneficiary.text,
                              )),
                            ),
                          ),
                        );
                      },
                    ),
                    const Expanded(
                      child: SizedBox.expand(key: Key('remaining_space')),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('After form'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void leaveAndReturn() {
    pageVisible = false;
    visibilityEpoch++;
    pageVisible = true;
  }

  void dispose() {
    disclosure.dispose();
    amount.dispose();
    beneficiary.dispose();
    amountFocus.dispose();
  }
}

Future<_Fixture> _prepare(
  WidgetTester tester, {
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  bool disableAnimations = false,
}) async {
  final _Fixture fixture = _Fixture();
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    fixture.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    fixture.host(
      theme: theme,
      direction: direction,
      scale: scale,
      disableAnimations: disableAnimations,
    ),
  );
  fixture.disclosure.open();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
  return fixture;
}

Future<void> _pick(WidgetTester tester, Key option) async {
  await tester.tap(find.byKey(_menu));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final ModalRoute<Object?> menu = ModalRoute.of<Object?>(
    tester.element(find.byKey(option)),
  )!;
  expect(menu.isCurrent, isTrue);
  bool closed = false;
  unawaited(menu.completed.then<void>((_) => closed = true));
  await tester.tap(find.byKey(option));
  await tester.pump();
  for (int frame = 0; frame < 40 && !closed; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(closed, isTrue, reason: 'The original menu overlay must leave');
  await tester.pump();
}

Future<void> _assertFieldTraversal(
  WidgetTester tester,
  _Fixture fixture,
) async {
  final FocusNode anotherFocus = tester
      .widget<TextField>(find.byKey(_another))
      .focusNode!;
  expect(find.byType(TextField), findsNWidgets(2));
  expect(fixture.amountFocus.canRequestFocus, isTrue);
  expect(anotherFocus.canRequestFocus, isTrue);
  fixture.amountFocus.requestFocus();
  await tester.pump();
  expect(fixture.amountFocus.hasFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  expect(anotherFocus.hasFocus, isTrue);
  expect(fixture.amountFocus.hasFocus, isFalse);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  expect(fixture.amountFocus.hasFocus, isTrue);
  expect(anotherFocus.hasFocus, isFalse);
}

String _attachedLabels() => find.semantics
    .byPredicate((SemanticsNode node) => true)
    .evaluate()
    .map((SemanticsNode node) {
      final SemanticsData resolved = node.getSemanticsData();
      return 'raw=${node.label}; rawUnits=${node.label.codeUnits}; '
          'resolved=${resolved.label}; '
          'resolvedUnits=${resolved.label.codeUnits}';
    })
    .join('\n');

void main() {
  for (final (String, ThemeData, TextDirection, double) variant
      in <(String, ThemeData, TextDirection, double)>[
        ('dark', AppTheme.darkTheme, TextDirection.ltr, 1),
        ('light RTL scaled', AppTheme.lightTheme, TextDirection.rtl, 1.5),
      ]) {
    testWidgets('compact natural form: ${variant.$1}', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = await _prepare(
        tester,
        theme: variant.$2,
        direction: variant.$3,
        scale: variant.$4,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Available'), findsNothing);
      expect(find.text('After fusing'), findsNothing);
      expect(
        find.text('Cancel unlocked fuses to recover QSR.'),
        findsOneWidget,
      );
      expect(find.textContaining('10 hours'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_submit),
          matching: find.byType(AmountText),
        ),
        findsOneWidget,
      );
      final AmountText actionAmount = tester.widget<AmountText>(
        find.descendant(
          of: find.byKey(_submit),
          matching: find.byType(AmountText),
        ),
      );
      expect(actionAmount.raw, BigInt.parse('10000000001'));
      expect(actionAmount.decimals, 8);
      final Text actionDigits = tester.widget<Text>(
        find.descendant(
          of: find.byType(AmountText),
          matching: find.byType(Text),
        ),
      );
      expect(actionDigits.textDirection, TextDirection.ltr);
      final TextField field = tester.widget<TextField>(find.byKey(_amount));
      expect(field.textDirection, TextDirection.ltr);
      expect(
        field.style!.fontFamily,
        AppTokens.of(tester.element(find.byKey(_amount))).monoFontFamily,
      );
      expect(field.style!.fontSize, 18);
      expect(tester.getSize(find.byKey(_surface)).height, lessThan(220));
      expect(
        tester.getRect(find.byKey(_amount)).top,
        closeTo(tester.getRect(find.byKey(_menu)).top, 1),
      );
      expect(fixture.authority!(), isTrue);
      expect(fixture.firstAuthority!(), isFalse);
      await _pick(tester, const Key('fuse_plasma_another_address_option'));
      expect(
        tester.widget<TextField>(find.byKey(_another)).textDirection,
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'known beneficiaries and the separate address draft survive switches',
    (WidgetTester tester) async {
      final _Fixture fixture = await _prepare(tester);
      await _pick(tester, const Key('fuse_plasma_another_address_option'));
      await tester.enterText(find.byKey(_another), 'z1externaldraft');
      await tester.pump();
      expect(fixture.beneficiary.text, 'z1externaldraft');
      await _pick(
        tester,
        const ValueKey<String>('fuse_plasma_beneficiary_option_1'),
      );
      expect(fixture.beneficiary.text, 'z1fixturesecond');
      expect(find.byKey(_another), findsNothing);
      final Finder selectedLabel = find.descendant(
        of: find.byKey(_menu),
        matching: find.text('z1fixture…second'),
      );
      expect(selectedLabel, findsOneWidget);
      final Text identifier = tester.widget<Text>(
        selectedLabel,
      );
      expect(identifier.textDirection, TextDirection.ltr);
      expect(
        identifier.style!.fontFamily,
        AppTokens.of(tester.element(find.byKey(_menu))).monoFontFamily,
      );
      await _pick(tester, const Key('fuse_plasma_another_address_option'));
      expect(
        tester.widget<TextField>(find.byKey(_another)).controller!.text,
        'z1externaldraft',
      );
      expect(fixture.beneficiary.text, 'z1externaldraft');
      expect(fixture.amount.text, '100.00000001');
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool disabled in <bool>[false, true]) {
    testWidgets(
      'two real fields retain keyboard traversal after reversal, '
      'OS flag $disabled',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          final _Fixture fixture = await _prepare(
            tester,
            disableAnimations: disabled,
          );
          await _pick(tester, const Key('fuse_plasma_another_address_option'));
          await tester.enterText(find.byKey(_another), 'z1retainedexternal');
          await tester.pump();
          final State<StatefulWidget> amountState = tester.state(
            find.byKey(_amount),
          );
          final State<StatefulWidget> anotherState = tester.state(
            find.byKey(_another),
          );
          await _assertFieldTraversal(tester, fixture);
          // Plain labels can merge with adjacent static text in the attached
          // tree. Require their exact label lines in that merged node.
          final RegExp amountLabel = RegExp(r'(^|\n)AMOUNT($|\n)');
          final RegExp forLabel = RegExp(r'(^|\n)FOR($|\n)');
          expect(
            find.semantics.byLabel(amountLabel),
            findsOneWidget,
            reason: _attachedLabels(),
          );
          expect(find.semantics.byLabel(forLabel), findsOneWidget);
          expect(find.byKey(_amount).hitTestable(), findsOneWidget);
          expect(find.byKey(_another).hitTestable(), findsOneWidget);
          fixture.disclosure.close();
          await tester.pump();
          expect(fixture.amountFocus.hasFocus, isFalse);
          await tester.pump(const Duration(milliseconds: 240));
          expect(find.byKey(_amount, skipOffstage: false), findsOneWidget);
          expect(find.byKey(_another, skipOffstage: false), findsOneWidget);
          expect(find.byKey(_amount).hitTestable(), findsNothing);
          expect(find.byKey(_another).hitTestable(), findsNothing);
          expect(find.semantics.byLabel(amountLabel), findsNothing);
          expect(find.semantics.byLabel(forLabel), findsNothing);
          expect(fixture.amountFocus.canRequestFocus, isFalse);
          fixture.disclosure.open();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 240));
          expect(tester.state(find.byKey(_amount)), same(amountState));
          expect(tester.state(find.byKey(_another)), same(anotherState));
          expect(find.semantics.byLabel(amountLabel), findsOneWidget);
          expect(find.semantics.byLabel(forLabel), findsOneWidget);
          expect(find.byKey(_amount).hitTestable(), findsOneWidget);
          expect(find.byKey(_another).hitTestable(), findsOneWidget);
          await _assertFieldTraversal(tester, fixture);
          fixture.disclosure.close();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          fixture.disclosure.open();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          fixture.disclosure.close();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          fixture.disclosure.open();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 240));
          await _assertFieldTraversal(tester, fixture);
          expect(
            tester.widget<TextField>(find.byKey(_another)).controller!.text,
            'z1retainedexternal',
          );
          expect(fixture.amount.text, '100.00000001');
          expect(fixture.submissions, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'close revokes captured controls and deferred authority without a frame',
    (WidgetTester tester) async {
      final _Fixture fixture = await _prepare(tester);
      final VoidCallback oldPress = tester
          .widget<LoadingButton>(find.byKey(fixture.button))
          .onPressed!;
      final ValueChanged<String> oldEnter = tester
          .widget<TextField>(find.byKey(_amount))
          .onSubmitted!;
      final bool Function() originalAuthority = fixture.authority!;
      final Completer<void> proof = Completer<void>();
      int admitted = 0;
      final Future<void> deferred = proof.future.then((_) {
        if (originalAuthority()) admitted++;
      });
      fixture.disclosure.close();
      expect(originalAuthority(), isFalse);
      oldPress();
      oldEnter('100.00000001');
      fixture.disclosure.open();
      expect(originalAuthority(), isFalse);
      oldPress();
      oldEnter('100.00000001');
      proof.complete();
      await tester.pump();
      await deferred;
      await tester.pump(const Duration(milliseconds: 240));
      expect(admitted, 0);
      expect(fixture.submissions, isEmpty);
      expect(fixture.authority!(), isTrue);
      tester.widget<LoadingButton>(find.byKey(fixture.button)).onPressed!();
      expect(fixture.submissions, <(String, String)>[
        ('100.00000001', 'z1fixturefirst'),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a captured page epoch and disposal cannot revive old authority',
    (WidgetTester tester) async {
      final _Fixture fixture = await _prepare(tester);
      final bool Function() beforeLeave = fixture.authority!;
      fixture.leaveAndReturn();
      expect(beforeLeave(), isFalse);
      await tester.pumpWidget(fixture.host());
      await tester.pump();
      expect(fixture.authority!(), isTrue);
      expect(beforeLeave(), isFalse);
      final bool Function() beforeDispose = fixture.authority!;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(beforeDispose(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validation grows the natural form without losing either control',
    (WidgetTester tester) async {
      final _Fixture fixture = await _prepare(tester);
      final double before = tester.getSize(find.byKey(_surface)).height;
      fixture.amountError = 'Not enough QSR';
      await tester.pumpWidget(fixture.host());
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('Not enough QSR'), findsOneWidget);
      expect(tester.getSize(find.byKey(_surface)).height, greaterThan(before));
      expect(find.byKey(_menu), findsOneWidget);
      expect(find.byKey(_submit), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
