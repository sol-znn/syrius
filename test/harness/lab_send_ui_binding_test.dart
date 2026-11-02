import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/receive_origin.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_sync_status/node_sync_status.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/widgets/send_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/fixtures/lab_send_ui_binding.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../helpers/hydrated_bloc.dart';
import '../settings_addresses_redesign/support.dart';

class _Blocks extends Mock implements AccountBlockUtils {}
class _Balances extends Mock implements ZenonAddressUtils {}
class _Client extends Mock implements Client {}
class _Sync extends MockCubit<NodeSyncStatusState>
    implements NodeSyncStatusCubit {}

class _Source extends Fake implements SeedSource {
  _Source(this.environment);
  @override
  final SeedEnvironment environment;
  bool current = true;
  @override
  bool get isCurrent => current;
}

Future<T> _drive<T>(WidgetTester tester, Future<T> command) async {
  bool done = false;
  T? result;
  Object? error;
  StackTrace? trace;
  unawaited(command.then((T value) {
    result = value;
    done = true;
  }, onError: (Object value, StackTrace stack) {
    error = value;
    trace = stack;
    done = true;
  }));
  for (int frame = 0; frame < 80 && !done; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'The original UI command must settle');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return result as T;
}

class _Fixture {
  _Fixture({this.customReview = false, this.deferReview = false,
    this.amount = '1'}) {
    source = _Source(SeedEnvironment(
      profile: 'fixture-ui', isolated: true, unlocked: true,
      initialized: true, booted: true, ws: seedWsOrigin, http: seedHttpOrigin,
      nodeChain: 321, signingChain: 321, selectedIndex: 1,
      owner: from, members: <String>[to, from],
    ));
    when(balances.refreshBalance).thenAnswer((_) {});
    when(() => blocks.createAccountBlock(
      any(), any(), address: any(named: 'address'),
      waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
    )).thenAnswer((_) {
      publications++;
      return publication.future;
    });
    sender = _sender();
    otherSender = _sender();
    provided = ValueNotifier<SendTransactionBloc>(sender);
    draft = SendDraftCubit()..save(fromAddress: from,
      tokenStandard: znnZts.toString(), recipient: to, amount: amount);
    whenListen(sync, syncStates.stream,
      initialState: const NodeSyncStatusState());
  }

  final String from = fixtureAddress(2);
  final String to = fixtureAddress(1);
  final String amount;
  final bool customReview;
  final bool deferReview;
  final _Blocks blocks = _Blocks();
  final _Balances balances = _Balances();
  final _Sync sync = _Sync();
  final StreamController<NodeSyncStatusState> syncStates =
      StreamController<NodeSyncStatusState>.broadcast(sync: true);
  final PriceFeed prices = PriceFeed(request: (_) async => '{}');
  final ContactsStore contacts = ContactsStore();
  final Completer<AccountBlockTemplate> publication =
      Completer<AccountBlockTemplate>();
  final ValueNotifier<int> replacement = ValueNotifier<int>(0);
  final ValueNotifier<bool> reviewVisible = ValueNotifier<bool>(false);
  final HarnessAgent agent = HarnessAgent.forTest();
  late final SendTransactionBloc sender;
  late final SendTransactionBloc otherSender;
  late final ValueNotifier<SendTransactionBloc> provided;
  late final SendDraftCubit draft;
  late final _Source source;
  final List<LabSendUiReview> reviews = <LabSendUiReview>[];
  bool originCurrent = true;
  int publications = 0;
  int down = 0;

  SendTransactionBloc _sender() => SendTransactionBloc(
    accountBlockUtilsHelper: blocks, zenonAddressUtils: balances,
    recordRecipient: (_, _) async {},
  );

  SendIntent clone(SendIntent intent) => SendIntent.capture(
    fromAddress: intent.fromAddress, recipient: intent.recipientInput,
    amount: intent.amountInput, token: kZnnCoin,
  );

  AccountBlockTemplate response() => AccountBlockTemplate.send(
    Address.parse(to), znnZts, BigInt.from(100000000),
  )..chainIdentifier = 321
   ..address = Address.parse(from)
   ..hash = Hash.parse(fixtureHash(9));

  ReceiveOrigin origin({SendTransactionBloc? attached}) => ReceiveOrigin(
    sender: attached ?? sender,
    ledger: LedgerApi()..setClient(_Client()),
    stats: StatsApi()..setClient(_Client()),
    chainId: 321, nodeChainId: 321, selectedAddress: from,
    addresses: <String>[to, from], isCurrent: () => originCurrent,
  );

  LabSendUiBinding binding(WidgetTester tester, {ReceiveOrigin? captured}) =>
      LabSendUiBinding.capture(form: tester.element(find.byType(SendPopulated)),
        source: source, origin: captured ?? origin());

  LabSendUiReview capture(LabSendUiBinding binding) {
    final LabSendUiReview review = agent.captureLabReviewForTest(binding);
    reviews.add(review);
    return review;
  }

  Widget host() => BlocProvider<SendTransactionBloc>.value(
    // The root dialog provider deliberately differs from the real form owner.
    value: otherSender,
    child: MaterialApp(theme: AppTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, Widget? child) => Listener(
        onPointerDown: (_) => down++, child: child,
      ),
      home: ValueListenableBuilder<SendTransactionBloc>(
        valueListenable: provided,
        builder: (_, SendTransactionBloc value, _) =>
            BlocProvider<SendTransactionBloc>.value(value: value,
              child: BlocProvider<SendDraftCubit>.value(value: draft,
                child: Scaffold(body: SingleChildScrollView(
                  child: SendPopulated(showSender: false,
                    balances: <String, AccountInfo>{
                      from: AccountInfo(address: from, blockCount: 1,
                        balanceInfoList: <BalanceInfoListItem>[
                          BalanceInfoListItem(token: kZnnCoin,
                            balance: BigInt.from(100000000000)),
                        ]),
                    },
                    contacts: contacts, priceFeed: prices, syncCubit: sync,
                    captureSession: () => SendSession(
                      isCurrent: () => source.current && originCurrent,
                    ),
                    confirm: !customReview ? null :
                      (SendIntent intent, SendSession _) async =>
                        await showFrostedDialog<bool>(
                          context: testerContext!, barrierDismissible: false,
                          builder: (BuildContext context) {
                            final Widget original = ValueListenableBuilder<int>(
                              valueListenable: replacement,
                              builder: (_, int changed, _) => SendConfirmation(
                                key: ValueKey<int>(changed == 2 ? 2 : 0),
                                intent: changed == 1 ? clone(intent) : intent,
                                onConfirm: () => Navigator.pop(context, true),
                                onCancel: () => Navigator.pop(context, false),
                              ),
                            );
                            if (!deferReview) return original;
                            return ValueListenableBuilder<bool>(
                              valueListenable: reviewVisible,
                              child: original,
                              builder: (_, bool visible, Widget? child) =>
                                visible ? child! :
                                  const SizedBox(width: 440, height: 240),
                            );
                          },
                        ) ?? false,
                  ),
                )),
              ),
            ),
      ),
    ),
  );

  BuildContext? testerContext;

  Future<void> mount(WidgetTester tester) async {
    final String? saved = kSelectedAddress;
    final List<String?> members = kDefaultAddressList;
    kSelectedAddress = from;
    kDefaultAddressList = <String?>[to, from];
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!publication.isCompleted) publication.complete(response());
      await tester.pump();
      for (final LabSendUiReview review in reviews) {
        await _drive(tester, review.witness.close());
      }
      await _drive(tester, sender.close());
      await _drive(tester, otherSender.close());
      await _drive(tester, draft.close());
      await _drive(tester, syncStates.close());
      provided.dispose();replacement.dispose();reviewVisible.dispose();
      contacts.dispose();prices.dispose();
      kSelectedAddress = saved;kDefaultAddressList = members;
      tester.view.reset();
    });
    await tester.pumpWidget(host());
    await tester.pump();
    testerContext = tester.element(find.byType(SendPopulated));
  }

  Future<void> open(WidgetTester tester) async {
    final Finder submit = find.byKey(const Key('send_submit_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SendConfirmation), findsOneWidget);
  }
}

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 2));
    registerFallbackValue(Address.parse(fixtureAddress(1)));
  });

  test('HTTP lab-send input cannot choose terms or non-lab transports',
      () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    const Map<String, dynamic> fixed = <String, dynamic>{
      'cmd': 'lab-send', 'profile': 'fixture-ui',
      'ws': seedWsOrigin, 'http': seedHttpOrigin,
    };
    for (final Map<String, dynamic> change in <Map<String, dynamic>>[
      <String, dynamic>{'amount': '2'},
      <String, dynamic>{'recipient': 'arbitrary'},
      <String, dynamic>{'action': 'retry'},
      <String, dynamic>{'ws': 'ws://localhost:45998'},
      <String, dynamic>{'http': 'https://example.test'},
    ]) {
      await expectLater(agent.commandForTest(
        <String, dynamic>{...fixed, ...change},
      ),
        throwsA(isA<HarnessError>().having(
          (HarnessError error) => error.message,
          'fixed refusal', 'fixed-original-lab-send-required')));
    }
  });

  for (final bool revokeAfterInput in <bool>[false, true]) {
  testWidgets('actual form retains its original result $revokeAfterInput', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture();await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    await f.open(tester);
    final SendConfirmation shown = tester.widget(find.byType(SendConfirmation));
    final LabSendUiReview review = f.capture(binding);
    expect(review.intent, same(shown.intent));
    expect(review.witness.sender, same(f.sender));
    expect(tester.element(find.byType(SendConfirmation))
      .read<SendTransactionBloc>(), same(f.otherSender));
    await _drive(tester, f.agent.acceptLabReviewForTest(review));
    expect(f.publications, 1);
    expect(review.witness.started, isTrue);
    expect(review.witness.identity, same(shown.intent.requestId));
    if (revokeAfterInput) f.originCurrent = false;
    final AccountBlockTemplate original = f.response();
    f.publication.complete(original);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SendConfirmation), findsNothing);
    expect(review.witness.result, same(original));
    expect(review.witness.settled, isTrue);
    // Failure must sample the original lease without a preceding isCurrent
    // read, while preserving the original known response and hash.
    expect(review.witness.failed, revokeAfterInput);
    expect(binding.isCurrent, !revokeAfterInput);
    expect(review.witness.acceptedHash, fixtureHash(9));
  });
  }

  testWidgets('provider replacement cannot rename the original form sender', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture();await f.mount(tester);
    f.provided.value = f.otherSender;await tester.pump();
    expect(() => f.binding(tester, captured: f.origin(attached: f.otherSender)),
      throwsA(isA<SeedRefused>()));
    expect(f.publications, 0);
  });

  testWidgets('a late original dialog rise waits after its route completes', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture(customReview: true, deferReview: true);
    await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    final Finder submit = find.byKey(const Key('send_submit_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SendConfirmation), findsNothing);
    f.reviewVisible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final Finder confirmation = find.byType(SendConfirmation);
    final Animation<double> originalRise = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const Key('send_confirmation_marker')),
        matching: find.byType(FadeTransition),
      ).first,
    ).opacity;
    expect(ModalRoute.of(tester.element(confirmation))!.animation!.isCompleted,
      isTrue);
    expect(originalRise.isCompleted, isFalse);
    expect(() => f.capture(binding), throwsA(isA<SeedRefused>().having(
      (SeedRefused value) => value.code, 'code',
      'original-lab-control-unsettled',
    )));
    expect(f.publications, 0);
    for (int frame = 0; frame < 8 && !originalRise.isCompleted; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(originalRise.isCompleted, isTrue);
    final LabSendUiReview review = f.capture(binding);
    expect(review.intent, same(tester.widget<SendConfirmation>(
      confirmation).intent));
    await _drive(tester, f.agent.acceptLabReviewForTest(review));
    expect(f.publications, 1);
    expect(review.witness.started, isTrue);
  });

  testWidgets('scalar-matching reconstructed review is not form authority', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture(customReview: true);await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    f.replacement.value = 1;await f.open(tester);
    expect(() => f.capture(binding), throwsA(isA<SeedRefused>()));
    expect(f.publications, 0);
  });

  for (final int replacement in <int>[1, 2]) {
    testWidgets('replacing review identity before input refuses $replacement', (
      WidgetTester tester,
    ) async {
      final _Fixture f = _Fixture(customReview: true);await f.mount(tester);
      final LabSendUiBinding binding = f.binding(tester);
      await f.open(tester);final LabSendUiReview review = f.capture(binding);
      f.replacement.value = replacement;await tester.pump();
      await expectLater(_drive(tester,
        f.agent.acceptLabReviewForTest(review)), throwsA(isA<SeedRefused>()));
      expect(f.publications, 0);
    });
  }

  testWidgets('every changed original center is refused without tolerance', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture();await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    await f.open(tester);final LabSendUiReview review = f.capture(binding);
    expect(() => review.requireReady(review.button,
      center: review.center + const Offset(0.25, 0)),
      throwsA(isA<SeedRefused>()));
    expect(f.publications, 0);
  });

  testWidgets('provider loss between pointer down and up cancels input', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture();await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    await f.open(tester);final LabSendUiReview review = f.capture(binding);
    f.down = 0;
    Object? error;
    final Future<void> command = f.agent.acceptLabReviewForTest(review)
      .catchError((Object value) { error = value; });
    for (int frame = 0; frame < 4 && f.down == 0; frame++) {
      await tester.pump();
    }
    expect(f.down, 1);
    f.provided.value = f.otherSender;
    // Apply the replacement before advancing the pending pointer-up timer.
    await tester.pump();
    expect(tester.element(find.byType(SendPopulated))
      .read<SendTransactionBloc>(), same(f.otherSender));
    await tester.pump(const Duration(milliseconds: 60));
    await _drive(tester, command);
    expect(error, isA<SeedRefused>());
    expect(f.publications, 0);
    f.provided.value = f.sender;await tester.pump();
    expect(binding.requireForm, throwsA(isA<SeedRefused>()));
  });

  for (final bool sourceLoss in <bool>[true, false]) {
    testWidgets('original owner or worker lease cannot revive $sourceLoss', (
      WidgetTester tester,
    ) async {
      final _Fixture f = _Fixture();await f.mount(tester);
      final LabSendUiBinding binding = f.binding(tester);
      await f.open(tester);final LabSendUiReview review = f.capture(binding);
      if (sourceLoss) { f.source.current = false; }
      else { f.originCurrent = false; }
      expect(() => review.requireReady(review.button, center: review.center),
        throwsA(isA<SeedRefused>()));
      f.source.current = true;f.originCurrent = true;
      expect(binding.isCurrent, isFalse);
      expect(f.publications, 0);
    });
  }

  testWidgets('a draft edit cannot retain the original review admission', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture();await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    await f.open(tester);final LabSendUiReview review = f.capture(binding);
    final TextField field = tester.widget(
      find.byKey(const Key('send_amount_field')),
    );
    expect(field.enabled, isFalse);
    expect(field.controller!.text, '1');
    final SendDraft original = f.draft.state;
    // The ordinary header/palette updates this owner while review fields are
    // disabled; the form retains its old text until the operation is idle.
    f.draft.save(fromAddress: f.from, tokenStandard: znnZts.toString(),
      recipient: f.to, amount: '2');
    await tester.pump();
    expect(f.draft.state, isNot(same(original)));
    expect(f.draft.state.amount, '2');
    expect(field.controller!.text, '1');
    expect(() => review.requireReady(review.button, center: review.center),
      throwsA(isA<SeedRefused>()));
    expect(f.publications, 0);
  });

  testWidgets('an actual review outside the fixed one-ZNN terms is refused', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture(amount: '2');await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);
    await f.open(tester);
    expect(() => f.capture(binding), throwsA(isA<SeedRefused>()));
    expect(f.publications, 0);
  });

  testWidgets('the ordinary cancel control cannot be accepted as publication', (
    WidgetTester tester,
  ) async {
    final _Fixture f = _Fixture();await f.mount(tester);
    final LabSendUiBinding binding = f.binding(tester);await f.open(tester);
    final Finder cancel = find.byKey(const Key('send_confirmation_cancel'));
    expect(() => binding.captureReview(tester.element(cancel),
      center: tester.getCenter(cancel)), throwsA(isA<SeedRefused>()));
    expect(f.publications, 0);
  });
}
