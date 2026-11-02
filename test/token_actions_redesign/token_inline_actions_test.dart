import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_action_dialog.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_inline_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.dark,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  theme: brightness == Brightness.dark
      ? AppTheme.darkTheme
      : AppTheme.lightTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 1120, child: child)),
      ),
    ),
  ),
);

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(ActionFixture) body,
) async {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  final String? selected = kSelectedAddress;
  final List<String?> addresses = kDefaultAddressList;
  final Map<String, String> labels = kAddressLabelMap;
  final ActionFixture fixture = ActionFixture();
  kSelectedAddress = emptyAddress.toString();
  kDefaultAddressList = <String?>[emptyAddress.toString()];
  kAddressLabelMap = <String, String>{emptyAddress.toString(): 'Fixture owner'};
  (Object, StackTrace)? bodyFailure;
  (Object, StackTrace)? cleanupFailure;
  try {
    await body(fixture);
  } on Object catch (error, trace) {
    bodyFailure = (error, trace);
  }
  try {
    await tester.pumpWidget(const SizedBox.shrink());
    await _closeFixture(tester, fixture);
  } on Object catch (error, trace) {
    cleanupFailure = (error, trace);
  } finally {
    kSelectedAddress = selected;
    kDefaultAddressList = addresses;
    kAddressLabelMap = labels;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
  if (bodyFailure != null) {
    if (cleanupFailure != null) {
      final (Object, StackTrace) secondary = cleanupFailure;
      addTearDown(() => Error.throwWithStackTrace(secondary.$1, secondary.$2));
    }
    Error.throwWithStackTrace(bodyFailure.$1, bodyFailure.$2);
  }
  if (cleanupFailure != null) {
    Error.throwWithStackTrace(cleanupFailure.$1, cleanupFailure.$2);
  }
}

Future<void> _closeFixture(WidgetTester tester, ActionFixture fixture) async {
  bool closed = false;
  (Object, StackTrace)? closeFailure;
  final Future<void> original = fixture.close();
  final Future<void> observed = original.then<void>(
    (_) {
      closed = true;
    },
    onError: (Object error, StackTrace trace) {
      closeFailure = (error, trace);
      closed = true;
    },
  );
  // Subscription cancellation can finish on the real event queue. The
  // operation starts on the widget clock, so advance both finite queues.
  for (int turn = 0; turn < 100 && !closed; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(closed, isTrue, reason: 'Original fixture close must finish');
  await observed;
  final (Object, StackTrace)? failure = closeFailure;
  if (failure != null) {
    Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}

Future<void> _editField(
  WidgetTester tester,
  String key,
  String value,
) async {
  await tester.enterText(find.byKey(Key(key)), value);
  // enterText flushes editing callbacks but does not rebuild enabled controls.
  await tester.pump();
}

Future<void> _ready(WidgetTester tester) => pumpActionUntil(
  tester,
  () => find.byKey(const Key('mint_amount_field')).evaluate().isNotEmpty,
);

Future<(NavigatorState, DialogRoute<void>, Future<void>)> _openTokenDialog(
  WidgetTester tester,
  Widget dialog,
) async {
  late BuildContext page;
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (BuildContext context) {
          page = context;
          return const Text('Fixture token page');
        },
      ),
    ),
  );
  final NavigatorState navigator = Navigator.of(page);
  final DialogRoute<void> route = DialogRoute<void>(
    context: page,
    barrierDismissible: false,
    builder: (_) => dialog,
  );
  final Future<void> closed = navigator.push<void>(route);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 151));
  await _ready(tester);
  return (navigator, route, closed);
}

Future<void> _routeSettled(WidgetTester tester, Future<void> route) async {
  bool settled = false;
  unawaited(
    route.then<void>((_) {
      settled = true;
    }),
  );
  await pumpActionUntil(tester, () => settled);
  await tester.pump(const Duration(milliseconds: 201));
}

void main() {
  initHydratedStorage();

  for (final Brightness brightness in Brightness.values) {
    for (final TextDirection direction in TextDirection.values) {
      for (final double scale in <double>[1, 1.5]) {
        testWidgets(
          '${brightness.name} ${direction.name} scale $scale '
          'retains exact fields and factual Flags',
          (WidgetTester tester) async {
            await _withFixture(tester, (ActionFixture fixture) async {
              await tester.pumpWidget(
                _host(
                  TokenInlineActions(
                    token: fixture.token,
                    publisher: fixture.publisher,
                    isCurrent: () => true,
                  ),
                  brightness: brightness,
                  direction: direction,
                  scale: scale,
                ),
              );
              await _ready(tester);
              const String exact = '9007199254740993.12345678';
              await _editField(
                tester,
                'mint_amount_field',
                exact,
              );
              final TextField field = tester.widget<TextField>(
                find.byKey(const Key('mint_amount_field')),
              );
              expect(
                field.style!.fontFamily,
                AppTokens.of(
                  tester.element(find.byType(TokenInlineActions)),
                ).monoFontFamily,
              );
              await tester.tap(find.byKey(const Key('token_action_mode_burn')));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 260));
              await _editField(
                tester,
                'burn_amount_field',
                '7',
              );
              await tester.tap(find.byKey(const Key('token_action_mode_mint')));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 260));
              expect(
                tester
                    .widget<TextField>(
                      find.byKey(const Key('mint_amount_field')),
                    )
                    .controller!
                    .text,
                exact,
              );
              await tester.tap(
                find.byKey(const Key('token_action_mode_flags')),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 260));
              expect(find.byType(PrimaryPill), findsNothing);
              expect(find.byType(Switch), findsNothing);
              expect(find.byType(Checkbox), findsNothing);
              expect(find.text('Issued'), findsNothing);
              expect(fixture.transport.calls, isEmpty);
              expect(fixture.transfers, isEmpty);
              expect(tester.takeException(), isNull);
            });
          },
        );
      }
    }
  }

  for (final Brightness brightness in Brightness.values) {
    testWidgets('confirmed Another rearms a new proof in ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        final List<TokenActionOutcome> outcomes = <TokenActionOutcome>[];
        final List<TokenActionIntent> questions = <TokenActionIntent>[];
        Widget panel(TokenActionPublisher publisher) => _host(
          TokenInlineActions(
            token: fixture.token,
            publisher: publisher,
            isCurrent: () => true,
            question: (TokenActionIntent intent) async {
              questions.add(intent);
              return true;
            },
            onOutcome: outcomes.add,
          ),
          brightness: brightness,
          direction: TextDirection.rtl,
          scale: 1.5,
        );
        await tester.pumpWidget(panel(fixture.publisher));
        await _ready(tester);
        await _editField(tester, 'mint_amount_field', '1');
        // The engine delivers a single-line Enter as this text-input action.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpActionUntil(tester, () => outcomes.length == 1);
        await tester.pump();
        final TokenActionOutcome original = outcomes.single;
        expect(original.status, TokenActionStatus.submitted);
        TextButton another() => tester.widget<TextButton>(
          find.byKey(const Key('token_action_another')),
        );
        expect(another().onPressed, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        final TokenActionPublisher reopened = fixture.reopenPublisher();
        await tester.pumpWidget(panel(reopened));
        await _ready(tester);
        expect(find.text('Submitted'), findsOneWidget);
        expect(another().onPressed, isNull);
        await _editField(tester, 'mint_amount_field', '9');
        final ValueChanged<String> oldEnter = tester
            .widget<TextField>(find.byKey(const Key('mint_amount_field')))
            .onSubmitted!;
        await tester.tap(find.byKey(const Key('token_action_mode_burn')));
        await tester.pump(const Duration(milliseconds: 260));
        await _editField(tester, 'burn_amount_field', '2');
        expect(
          tester
              .widget<PrimaryPill>(find.byKey(const Key('token_burn_submit')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const Key('token_action_mode_mint')));
        await tester.pump(const Duration(milliseconds: 260));
        final ValueChanged<String> beforeAnother = tester
            .widget<TextField>(find.byKey(const Key('mint_amount_field')))
            .onSubmitted!;
        fixture.confirm(original);
        await tester.pump();
        expect(another().onPressed, isNotNull);
        final VoidCallback oldAnother = another().onPressed!;
        await tester.tap(find.byKey(const Key('token_action_mode_burn')));
        await tester.pump(const Duration(milliseconds: 260));
        await tester.tap(find.byKey(const Key('token_action_mode_mint')));
        await tester.pump(const Duration(milliseconds: 260));
        final int reads = fixture.tokenReads;
        oldAnother();
        await tester.pump(const Duration(milliseconds: 1));
        expect(fixture.tokenReads, reads);
        final ValueChanged<String> currentBeforeAnother = tester
            .widget<TextField>(find.byKey(const Key('mint_amount_field')))
            .onSubmitted!;
        await tester.tap(find.byKey(const Key('token_action_another')));
        await pumpActionUntil(
          tester,
          () =>
              tester
                  .widget<TextField>(find.byKey(const Key('mint_amount_field')))
                  .controller!
                  .text
                  .isEmpty &&
              find.byKey(const Key('token_action_another')).evaluate().isEmpty,
        );
        expect(fixture.tokenReads, reads + 1);
        expect(find.byKey(const Key('token_action_another')), findsNothing);
        oldEnter('9');
        beforeAnother('9');
        currentBeforeAnother('9');
        await tester.pump(const Duration(milliseconds: 1));
        expect(questions, hasLength(1));
        await _editField(tester, 'mint_amount_field', '3');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpActionUntil(tester, () => outcomes.length == 2);
        await tester.pump();
        expect(
          identical(questions.first.proof.ticket, questions.last.proof.ticket),
          isFalse,
        );
        expect(outcomes.first, same(original));
        expect(fixture.transport.calls, hasLength(2));
        expect(another().onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets(
    'a deferred question freezes exact units and receiver before edits',
    (WidgetTester tester) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        fixture.transport.deferred = true;
        final Completer<bool> decision = Completer<bool>();
        final List<TokenActionIntent> questions = <TokenActionIntent>[];
        final List<TokenActionOutcome> outcomes = <TokenActionOutcome>[];
        await tester.pumpWidget(
          _host(
            TokenInlineActions(
              token: fixture.token,
              publisher: fixture.publisher,
              isCurrent: () => true,
              question: (TokenActionIntent intent) {
                questions.add(intent);
                return decision.future;
              },
              onOutcome: outcomes.add,
            ),
          ),
        );
        await _ready(tester);
        await _editField(
          tester,
          'mint_amount_field',
          '123.00000001',
        );
        final VoidCallback submit = tester
            .widget<PrimaryPill>(find.byKey(const Key('token_mint_submit')))
            .onPressed!;
        submit();
        submit();
        await pumpActionUntil(tester, () => questions.length == 1);
        await _editField(
          tester,
          'mint_amount_field',
          '999',
        );
        await _editField(
          tester,
          'mint_beneficiary_field',
          tokenAddress.toString(),
        );
        expect(questions.single.amount, BigInt.from(12300000001));
        expect(questions.single.receiver, emptyAddress.toString());
        decision.complete(true);
        await pumpActionUntil(
          tester,
          () => fixture.transport.pending.isNotEmpty,
        );
        expect(fixture.mints.single.$2, BigInt.from(12300000001));
        expect(fixture.mints.single.$3, emptyAddress.toString());
        final AccountBlockTemplate accepted = fixture.transport.accepted(
          fixture.transport.calls.single,
        );
        fixture.transport.complete(block: accepted);
        await pumpActionUntil(tester, () => outcomes.isNotEmpty);
        await tester.pump();
        expect(outcomes.single.block, same(accepted));
        expect(accepted.amount, BigInt.zero);
        expect(outcomes.single.requestedMintAmount, BigInt.from(12300000001));
        expect(find.text('Submitted'), findsOneWidget);
      });
    },
  );

  testWidgets('mode round trips permanently refuse captured callbacks', (
    WidgetTester tester,
  ) async {
    await _withFixture(tester, (ActionFixture fixture) async {
      int questions = 0;
      await tester.pumpWidget(
        _host(
          TokenInlineActions(
            token: fixture.token,
            publisher: fixture.publisher,
            isCurrent: () => true,
            question: (_) async {
              questions++;
              return false;
            },
          ),
        ),
      );
      await _ready(tester);
      await _editField(tester, 'mint_amount_field', '1');
      final VoidCallback old = tester
          .widget<PrimaryPill>(find.byKey(const Key('token_mint_submit')))
          .onPressed!;
      await tester.tap(find.byKey(const Key('token_action_mode_burn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('token_action_mode_mint')));
      await tester.pump();
      old();
      await tester.pump(const Duration(milliseconds: 1));
      expect(questions, 0);
      expect(fixture.transport.calls, isEmpty);
    });
  });

  testWidgets(
    'one ZTS detail stays open and close reopen cannot revive submit or Send',
    (WidgetTester tester) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        final GlobalKey<RowDetailGroupState> group =
            GlobalKey<RowDetailGroupState>();
        final Token other = actionToken(id: 2);
        final _Favorites favorites = _Favorites();
        final List<String> sends = <String>[];
        int epoch = 0;
        int questions = 0;
        await tester.pumpWidget(
          _host(
            StatefulBuilder(
              builder: (BuildContext context, StateSetter update) {
                final int captured = epoch;
                return RowDetailGroup(
                  key: group,
                  onChanged: (_) {
                    epoch++;
                    update(() {});
                  },
                  child: Column(
                    children: <Widget>[
                      for (final Token token in <Token>[fixture.token, other])
                        TokenCard(
                          token: token,
                          favoritesCallback: () {},
                          balance: fixture.balance,
                          favoriteRepository: favorites,
                          publisher: fixture.publisher,
                          isCurrent: () => true,
                          detailIsCurrent: () =>
                              captured == epoch &&
                              group.currentState!.openId ==
                                  token.tokenStandard.toString(),
                          onSendToken: sends.add,
                          question: (_) async {
                            questions++;
                            return false;
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        group.currentState!.open(fixture.token.tokenStandard.toString());
        await tester.pump();
        await _ready(tester);
        await tester.pump(const Duration(milliseconds: 240));
        await _editField(tester, 'mint_amount_field', '1');
        final VoidCallback submit = tester
            .widget<PrimaryPill>(find.byKey(const Key('token_mint_submit')))
            .onPressed!;
        final VoidCallback send = tester
            .widget<TextButton>(find.byKey(const Key('token_send')))
            .onPressed!;
        group.currentState!.close();
        group.currentState!.open(fixture.token.tokenStandard.toString());
        submit();
        send();
        await tester.pump();
        expect(questions, 0);
        expect(sends, isEmpty);
        expect(fixture.transport.calls, isEmpty);
        group.currentState!.open(other.tokenStandard.toString());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 241));
        expect(find.byType(TokenInlineActions), findsOneWidget);
        expect(group.currentState!.openId, other.tokenStandard.toString());
      });
    },
  );

  testWidgets(
    'keyboard submission uses the active mode and hidden modes cannot submit',
    (WidgetTester tester) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        int questions = 0;
        await tester.pumpWidget(
          _host(
            TokenInlineActions(
              token: fixture.token,
              publisher: fixture.publisher,
              isCurrent: () => true,
              question: (_) async {
                questions++;
                return false;
              },
            ),
          ),
        );
        await _ready(tester);
        await _editField(tester, 'mint_amount_field', '1');
        final ValueChanged<String> retainedSubmit = tester
            .widget<TextField>(find.byKey(const Key('mint_amount_field')))
            .onSubmitted!;
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpActionUntil(tester, () => questions == 1);
        await tester.tap(find.byKey(const Key('token_action_mode_flags')));
        await tester.pump();
        retainedSubmit('1');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 1));
        expect(questions, 1);
        expect(fixture.transport.calls, isEmpty);
      });
    },
  );

  testWidgets(
    'Tab and Shift Tab reach the retained Mint field after Burn',
    (WidgetTester tester) async {
      final FocusNode before = FocusNode(debugLabel: 'Before token modes');
      final FocusNode after = FocusNode(debugLabel: 'After token modes');
      try {
        await _withFixture(tester, (ActionFixture fixture) async {
          await tester.pumpWidget(
            _host(
              Column(
                children: <Widget>[
                  TextButton(
                    focusNode: before,
                    onPressed: () {},
                    child: const Text('Before modes'),
                  ),
                  TokenInlineActions(
                    token: fixture.token,
                    publisher: fixture.publisher,
                    isCurrent: () => true,
                  ),
                  TextButton(
                    focusNode: after,
                    onPressed: () {},
                    child: const Text('After modes'),
                  ),
                ],
              ),
            ),
          );
          await _ready(tester);
          FocusNode fieldNode(String key) => tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode;
          final FocusNode mint = fieldNode('mint_amount_field');
          Future<void> tabTo(FocusNode target, {bool reverse = false}) async {
            for (int turn = 0; turn < 20 && !target.hasPrimaryFocus; turn++) {
              if (reverse) {
                await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              }
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              if (reverse) {
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
              }
              await tester.pump(const Duration(milliseconds: 1));
            }
            expect(target.hasPrimaryFocus, isTrue);
          }

          before.requestFocus();
          await tester.pump();
          await tabTo(mint);
          await tester.tap(find.byKey(const Key('token_action_mode_burn')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 260));
          final FocusNode burn = fieldNode('burn_amount_field');
          await tabTo(burn);
          await tester.tap(find.byKey(const Key('token_action_mode_mint')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 260));
          expect(fieldNode('mint_amount_field'), same(mint));
          expect(mint.skipTraversal, isFalse);
          expect(mint.canRequestFocus, isTrue);
          before.requestFocus();
          await tester.pump();
          await tabTo(mint);
          expect(burn.hasFocus, isFalse);
          after.requestFocus();
          await tester.pump();
          await tabTo(mint, reverse: true);
          expect(burn.hasFocus, isFalse);
          expect(fixture.transport.calls, isEmpty);
          expect(tester.takeException(), isNull);
        });
      } finally {
        before.dispose();
        after.dispose();
      }
    },
  );

  for (final bool accepted in <bool>[true, false]) {
    testWidgets('late $accepted result cannot replace a new token scope', (
      WidgetTester tester,
    ) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        fixture.transport.deferred = true;
        final List<bool> oldBusy = <bool>[];
        final List<TokenActionOutcome> oldOutcomes = <TokenActionOutcome>[];
        await tester.pumpWidget(
          _host(
            TokenInlineActions(
              key: const Key('replaced_token_scope'),
              token: fixture.token,
              publisher: fixture.publisher,
              authorityEpoch: 1,
              isCurrent: () => true,
              question: (_) async => true,
              onBusyChanged: oldBusy.add,
              onOutcome: oldOutcomes.add,
            ),
          ),
        );
        await _ready(tester);
        final State<StatefulWidget> retained = tester.state(
          find.byType(TokenInlineActions),
        );
        await _editField(tester, 'mint_amount_field', '1');
        await tester.tap(find.byKey(const Key('token_mint_submit')));
        await pumpActionUntil(
          tester,
          () => fixture.transport.pending.isNotEmpty,
        );
        expect(oldBusy, <bool>[true]);
        final AccountBlockTemplate originalBlock = fixture.transport.accepted(
          fixture.transport.calls.single,
        );
        final StateError originalError = StateError('Synthetic old scope');
        final ActionFixture replacement = ActionFixture(
          initialToken: actionToken(owner: tokenAddress, id: 2),
          ownerAddress: tokenAddress.toString(),
        );
        try {
          final List<bool> newBusy = <bool>[];
          final List<TokenActionOutcome> newOutcomes = <TokenActionOutcome>[];
          final List<TokenActionIntent> newQuestions = <TokenActionIntent>[];
          await tester.pumpWidget(
            _host(
              TokenInlineActions(
                key: const Key('replaced_token_scope'),
                token: replacement.token,
                publisher: replacement.publisher,
                authorityEpoch: 2,
                isCurrent: () => true,
                question: (TokenActionIntent intent) async {
                  newQuestions.add(intent);
                  return true;
                },
                onBusyChanged: newBusy.add,
                onOutcome: newOutcomes.add,
              ),
            ),
          );
          await _ready(tester);
          expect(tester.state(find.byType(TokenInlineActions)), same(retained));
          await tester.tap(find.text('This address'));
          await _editField(
            tester,
            'mint_amount_field',
            '2',
          );
          await tester.tap(find.byKey(const Key('token_mint_submit')));
          await pumpActionUntil(tester, () => newOutcomes.length == 1);
          await tester.pump();
          final TokenActionOutcome newOriginal = newOutcomes.single;
          final int reads = replacement.tokenReads;
          expect(newBusy, <bool>[true, false]);
          expect(newQuestions.single.standard, replacement.token.tokenStandard);
          expect(newQuestions.single.owner, replacement.session.address);
          fixture.transport.complete(
            block: accepted ? originalBlock : null,
            failure: accepted ? null : originalError,
          );
          await pumpActionUntil(
            tester,
            () => fixture.publisher.lastOutcome != null,
          );
          await tester.pump();
          final TokenActionOutcome oldOriginal = fixture.publisher.lastOutcome!;
          expect(oldOutcomes, isEmpty);
          expect(oldBusy, <bool>[true]);
          expect(newBusy, <bool>[true, false]);
          expect(newOutcomes, <TokenActionOutcome>[newOriginal]);
          expect(replacement.publisher.lastOutcome, same(newOriginal));
          expect(replacement.tokenReads, reads);
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('mint_amount_field')))
                .controller!
                .text,
            '2',
          );
          expect(find.text('Submitted'), findsOneWidget);
          expect(
            TokenActionPublisher.originalOutcomesFor(fixture.sender).single,
            same(oldOriginal),
          );
          if (accepted) {
            expect(oldOriginal.block, same(originalBlock));
          } else {
            expect(oldOriginal.error, same(originalError));
            expect(oldOriginal.result!.error, same(originalError));
          }
          replacement.confirm(newOriginal);
          await tester.pump();
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const Key('token_action_another')),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byKey(const Key('token_action_another')));
          await pumpActionUntil(
            tester,
            () => tester
                .widget<TextField>(find.byKey(const Key('mint_amount_field')))
                .controller!
                .text
                .isEmpty,
          );
          expect(replacement.tokenReads, reads + 1);
          await tester.tap(find.text('This address'));
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const Key('mint_beneficiary_field')),
                )
                .controller!
                .text,
            replacement.session.address,
          );
          expect(newOutcomes, <TokenActionOutcome>[newOriginal]);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _closeFixture(tester, replacement);
        }
      });
    });
  }

  testWidgets('a reopened row follows its held original settlement', (
    WidgetTester tester,
  ) async {
    await _withFixture(tester, (ActionFixture fixture) async {
      fixture.transport.deferred = true;
      final GlobalKey<RowDetailGroupState> group =
          GlobalKey<RowDetailGroupState>();
      final _Favorites favorites = _Favorites();
      int epoch = 0;
      int questions = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter update) {
              final int captured = epoch;
              return RowDetailGroup(
                key: group,
                initiallyOpen: fixture.token.tokenStandard.toString(),
                onChanged: (_) {
                  epoch++;
                  update(() {});
                },
                child: TokenCard(
                  token: fixture.token,
                  favoritesCallback: () {},
                  balance: fixture.balance,
                  favoriteRepository: favorites,
                  publisher: fixture.publisher,
                  isCurrent: () => true,
                  detailIsCurrent: () =>
                      captured == epoch &&
                      group.currentState!.openId ==
                          fixture.token.tokenStandard.toString(),
                  question: (_) async {
                    questions++;
                    return true;
                  },
                ),
              );
            },
          ),
        ),
      );
      await _ready(tester);
      await _editField(tester, 'mint_amount_field', '1');
      await tester.tap(find.byKey(const Key('token_mint_submit')));
      await pumpActionUntil(tester, () => fixture.transport.pending.isNotEmpty);
      group.currentState!.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 241));
      expect(find.byType(TokenInlineActions), findsNothing);
      group.currentState!.open(fixture.token.tokenStandard.toString());
      await tester.pump();
      await _ready(tester);
      await tester.pump(const Duration(milliseconds: 241));
      expect(find.text('Submitting'), findsOneWidget);
      final AccountBlockTemplate original = fixture.transport.accepted(
        fixture.transport.calls.single,
      );
      fixture.transport.complete(block: original);
      await pumpActionUntil(
        tester,
        () => find.text('Submitted').evaluate().isNotEmpty,
      );
      expect(find.text('Submitting'), findsNothing);
      expect(questions, 1);
      expect(fixture.transport.calls, hasLength(1));
      expect(fixture.publisher.lastOutcome!.block, same(original));
      fixture.confirm(fixture.publisher.lastOutcome!);
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('token_action_another')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'disposal retains the original error and removes observers',
    (WidgetTester tester) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        fixture.transport.deferred = true;
        final List<TokenActionOutcome> observations = <TokenActionOutcome>[];
        await tester.pumpWidget(
          _host(
            TokenInlineActions(
              token: fixture.token,
              publisher: fixture.publisher,
              isCurrent: () => true,
              question: (_) async => true,
              onOutcome: observations.add,
            ),
          ),
        );
        await _ready(tester);
        await _editField(tester, 'mint_amount_field', '1');
        await tester.tap(find.byKey(const Key('token_mint_submit')));
        await pumpActionUntil(
          tester,
          () => fixture.transport.pending.isNotEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        final StateError original = StateError('Synthetic late original');
        fixture.transport.complete(failure: original);
        await pumpActionUntil(
          tester,
          () => fixture.publisher.lastOutcome != null,
        );
        expect(fixture.publisher.lastOutcome!.error, same(original));
        expect(fixture.publisher.lastOutcome!.result!.error, same(original));
        expect(
          fixture.publisher.lastOutcome!.status,
          TokenActionStatus.unknown,
        );
        expect(observations, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'old confirmation callbacks preserve a covering route',
    (WidgetTester tester) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        await tester.pumpWidget(
          _host(
            TokenInlineActions(
              token: fixture.token,
              publisher: fixture.publisher,
              isCurrent: () => true,
            ),
          ),
        );
        await _ready(tester);
        await _editField(tester, 'mint_amount_field', '1');
        await tester.tap(find.byKey(const Key('token_mint_submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 151));
        final Finder dialog = find.byType(DialogCard);
        expect(dialog, findsOneWidget);
        final VoidCallback oldConfirm = tester
            .widget<OutlinedButton>(
              find.descendant(
                of: dialog,
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed!;
        final NavigatorState navigator = Navigator.of(tester.element(dialog));
        final DialogRoute<void> cover = DialogRoute<void>(
          context: tester.element(dialog),
          builder: (_) =>
              const Center(child: Text('Independent covering route')),
        );
        final Future<void> covered = navigator.push<void>(cover);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 151));
        oldConfirm();
        await tester.pump(const Duration(milliseconds: 1));
        expect(cover.isActive, isTrue);
        expect(cover.isCurrent, isTrue);
        expect(find.text('Independent covering route'), findsOneWidget);
        expect(fixture.transport.calls, isEmpty);
        navigator.removeRoute(cover);
        bool removed = false;
        unawaited(
          covered.then<void>((_) {
            removed = true;
          }),
        );
        await pumpActionUntil(tester, () => removed);
        oldConfirm();
        expect(fixture.transport.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );

  for (final bool covered in <bool>[false, true]) {
    for (final bool accepted in <bool>[false, true]) {
      testWidgets(
        'dialog settles $accepted chrome through '
        '${covered ? 'route coverage' : 'minimize and resume'}',
        (WidgetTester tester) async {
          await _withFixture(tester, (ActionFixture fixture) async {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            try {
              fixture.transport.deferred = true;
              final (
                NavigatorState navigator,
                DialogRoute<void> outer,
                Future<void> closed,
              ) = await _openTokenDialog(
                tester,
                TokenActionDialog(
                  token: fixture.token,
                  mode: TokenActionMode.mint,
                  publisher: fixture.publisher,
                  question: (_) async => true,
                ),
              );
              TextButton cancel() => tester.widget<TextButton>(
                find.widgetWithText(
                  TextButton,
                  'Cancel',
                  skipOffstage: false,
                ),
              );
              final VoidCallback oldCancel = cancel().onPressed!;
              await _editField(
                tester,
                'mint_amount_field',
                '1',
              );
              await tester.tap(find.byKey(const Key('token_mint_submit')));
              await pumpActionUntil(
                tester,
                () => fixture.transport.pending.isNotEmpty,
              );
              await tester.pump();
              expect(cancel().onPressed, isNull);
              expect(outer.popDisposition, RoutePopDisposition.doNotPop);
              DialogRoute<void>? cover;
              Future<void>? coverClosed;
              if (covered) {
                cover = DialogRoute<void>(
                  context: tester.element(find.byType(TokenActionDialog)),
                  builder: (_) =>
                      const Center(child: Text('Independent busy cover')),
                );
                coverClosed = navigator.push<void>(cover);
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 151));
              } else {
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.inactive,
                );
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.hidden,
                );
              }
              final AccountBlockTemplate original = fixture.transport.accepted(
                fixture.transport.calls.single,
              );
              final StateError error = StateError('Synthetic dialog outcome');
              fixture.transport.complete(
                block: accepted ? original : null,
                failure: accepted ? null : error,
              );
              await pumpActionUntil(
                tester,
                () => fixture.publisher.lastOutcome != null,
              );
              if (covered) {
                await tester.pump();
                expect(cancel().onPressed, isNotNull);
                oldCancel();
                cancel().onPressed!();
                final DialogRoute<void> originalCover = cover!;
                expect(originalCover.isActive, isTrue);
                expect(originalCover.isCurrent, isTrue);
                expect(outer.isActive, isTrue);
                navigator.removeRoute(originalCover);
                await _routeSettled(tester, coverClosed!);
              } else {
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.inactive,
                );
                tester.binding.handleAppLifecycleStateChanged(
                  AppLifecycleState.resumed,
                );
                await tester.pump();
              }
              await _ready(tester);
              await tester.pump();
              expect(outer.isActive, isTrue);
              expect(outer.isCurrent, isTrue);
              expect(cancel().onPressed, isNotNull);
              expect(outer.popDisposition, RoutePopDisposition.pop);
              if (accepted) {
                expect(fixture.publisher.lastOutcome!.block, same(original));
              } else {
                expect(fixture.publisher.lastOutcome!.error, same(error));
                expect(
                  fixture.publisher.lastOutcome!.result!.error,
                  same(error),
                );
              }
              cancel().onPressed!();
              await _routeSettled(tester, closed);
              expect(find.text('Fixture token page'), findsOneWidget);
              expect(fixture.transport.calls, hasLength(1));
              expect(tester.takeException(), isNull);
            } finally {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            }
          });
        },
      );
    }
  }

  testWidgets('an older dialog settlement cannot unlock replacement chrome', (
    WidgetTester tester,
  ) async {
    await _withFixture(tester, (ActionFixture fixture) async {
      fixture.transport.deferred = true;
      final ActionFixture replacement = ActionFixture(
        initialToken: actionToken(owner: tokenAddress, id: 2),
        ownerAddress: tokenAddress.toString(),
      )..transport.deferred = true;
      try {
        ActionFixture active = fixture;
        late StateSetter update;
        final (
          _,
          DialogRoute<void> outer,
          Future<void> closed,
        ) = await _openTokenDialog(
          tester,
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setter) {
              update = setter;
              return TokenActionDialog(
                token: active.token,
                mode: TokenActionMode.mint,
                publisher: active.publisher,
                question: (_) async => true,
              );
            },
          ),
        );
        TextButton cancel() => tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Cancel'),
        );
        final VoidCallback oldCancel = cancel().onPressed!;
        await _editField(tester, 'mint_amount_field', '1');
        await tester.tap(find.byKey(const Key('token_mint_submit')));
        await pumpActionUntil(
          tester,
          () => fixture.transport.pending.isNotEmpty,
        );
        update(() => active = replacement);
        await tester.pump();
        await _ready(tester);
        expect(cancel().onPressed, isNotNull);
        await tester.tap(find.text('This address'));
        await _editField(tester, 'mint_amount_field', '2');
        await tester.tap(find.byKey(const Key('token_mint_submit')));
        await pumpActionUntil(
          tester,
          () => replacement.transport.pending.isNotEmpty,
        );
        await tester.pump();
        expect(cancel().onPressed, isNull);
        oldCancel();
        expect(outer.isActive, isTrue);
        final AccountBlockTemplate original = fixture.transport.accepted(
          fixture.transport.calls.single,
        );
        fixture.transport.complete(block: original);
        await pumpActionUntil(
          tester,
          () => fixture.publisher.lastOutcome != null,
        );
        await tester.pump();
        expect(cancel().onPressed, isNull);
        expect(outer.popDisposition, RoutePopDisposition.doNotPop);
        expect(fixture.publisher.lastOutcome!.block, same(original));
        final StateError error = StateError('Synthetic replacement outcome');
        replacement.transport.complete(failure: error);
        await pumpActionUntil(
          tester,
          () => replacement.publisher.lastOutcome != null,
        );
        await tester.pump();
        expect(cancel().onPressed, isNotNull);
        expect(outer.popDisposition, RoutePopDisposition.pop);
        expect(replacement.publisher.lastOutcome!.error, same(error));
        cancel().onPressed!();
        await _routeSettled(tester, closed);
        expect(find.text('Fixture token page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _closeFixture(tester, replacement);
      }
    });
  });

  testWidgets(
    'legacy Cancel and late outcomes preserve covering and popping routes',
    (WidgetTester tester) async {
      await _withFixture(tester, (ActionFixture fixture) async {
        late BuildContext page;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (BuildContext context) {
                page = context;
                return const Text('Original token page');
              },
            ),
          ),
        );
        final NavigatorState navigator = Navigator.of(page);
        final DialogRoute<void> outer = DialogRoute<void>(
          context: page,
          builder: (_) => TokenActionDialog(
            token: fixture.token,
            mode: TokenActionMode.mint,
            publisher: fixture.publisher,
          ),
        );
        final Future<void> originalRoute = navigator.push<void>(outer);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 151));
        await _ready(tester);
        final VoidCallback oldCancel = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed!;
        final ValueChanged<TokenActionOutcome> lateOutcome = tester
            .widget<TokenInlineActions>(find.byType(TokenInlineActions))
            .onOutcome!;
        TokenActionProof? proof;
        unawaited(
          fixture.publisher.read(fixture.token.tokenStandard).then<void>((
            TokenActionProof value,
          ) {
            proof = value;
          }),
        );
        await pumpActionUntil(tester, () => proof != null);
        final TokenActionIntent intent = TokenActionIntent(
          proof: proof!,
          mode: TokenActionMode.mint,
          amount: BigInt.one,
          receiver: emptyAddress.toString(),
          isCurrent: () => true,
        );
        final AccountBlockTemplate accepted = fixture.block(<int>[1])
          ..address = emptyAddress
          ..hash = Hash.parse(actionHash(777));
        final TokenActionOutcome original = TokenActionOutcome(
          intent: intent,
          status: TokenActionStatus.submitted,
          result: SendRequestResult(block: accepted),
        );
        final DialogRoute<void> cover = DialogRoute<void>(
          context: page,
          builder: (_) => const Center(child: Text('Independent outer cover')),
        );
        final Future<void> covered = navigator.push<void>(cover);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 151));
        oldCancel();
        lateOutcome(original);
        expect(cover.isActive, isTrue);
        expect(cover.isCurrent, isTrue);
        expect(outer.isActive, isTrue);
        navigator.removeRoute(cover);
        bool coverRemoved = false;
        unawaited(
          covered.then<void>((_) {
            coverRemoved = true;
          }),
        );
        await pumpActionUntil(tester, () => coverRemoved);
        bool outerRemoved = false;
        unawaited(
          originalRoute.then<void>((_) {
            outerRemoved = true;
          }),
        );
        navigator.pop();
        oldCancel();
        lateOutcome(original);
        await pumpActionUntil(tester, () => outerRemoved);
        await tester.pump(const Duration(milliseconds: 201));
        oldCancel();
        lateOutcome(original);
        expect(find.text('Original token page'), findsOneWidget);
        expect(original.block, same(accepted));
        expect(original.publicationHash, actionHash(777));
        expect(fixture.transport.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );
}

class _Favorites implements FavoriteTokensRepository {
  final Set<String> standards = <String>{};
  @override
  bool contains(TokenStandard standard) =>
      standards.contains(standard.toString());
  @override
  Future<void> add(TokenStandard standard) async {
    standards.add(standard.toString());
  }

  @override
  Future<void> remove(TokenStandard standard) async {
    standards.remove(standard.toString());
  }
}
