import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_sync_status/node_sync_status.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/pair.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

class _Address extends Fake implements Address {}

class _Sync extends MockCubit<NodeSyncStatusState>
    implements NodeSyncStatusCubit {}

class _Info extends Mock implements SyncInfo {}

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(_Address());
  });
  final String from = emptyAddress.toString();
  final String to = Address('z', <int>[
    0,
    2,
    ...List<int>.filled(18, 7),
  ]).toString();
  late SendTransactionBloc sender;
  late _Blocks blocks;
  late _Balances balances;
  late SendDraftCubit draft;
  late PriceFeed prices;
  late ContactsStore contacts;
  late _Sync sync;
  late StreamController<NodeSyncStatusState> syncStates;
  late Completer<bool> confirmation;
  late Completer<AccountBlockTemplate> publication;
  late Completer<void> publicationStarted;
  late Completer<void> confirmationAnswered;
  late Completer<void> outcomeObserved;
  late List<SendIntent> shown;
  late List<SendRequestResult> observed;
  late int publishCount;
  late bool current;
  late bool throwObserver;
  late int revision;
  late String? previousAddress;
  late List<String?> previousAddresses;

  setUp(() {
    previousAddress = kSelectedAddress;
    previousAddresses = kDefaultAddressList;
    kSelectedAddress = from;
    kDefaultAddressList = <String?>[from];
    BalanceVisibility.debugReset();
    revision = WalletContextRevision.value;
    current = true;
    throwObserver = false;
    shown = <SendIntent>[];
    observed = <SendRequestResult>[];
    publishCount = 0;
    prices = PriceFeed(request: (_) async => '{}');
    contacts = ContactsStore();
    draft = SendDraftCubit()
      ..save(
        fromAddress: from,
        tokenStandard: kZnnCoin.tokenStandard.toString(),
        recipient: to,
        amount: '12.5',
      );
    blocks = _Blocks();
    balances = _Balances();
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
      ),
    ).thenAnswer((_) {
      publishCount++;
      publicationStarted.complete();
      return publication.future;
    });
    when(balances.refreshBalance).thenAnswer((_) {});
    sync = _Sync();
    syncStates = StreamController<NodeSyncStatusState>.broadcast(sync: true);
    whenListen(
      sync,
      syncStates.stream,
      initialState: const NodeSyncStatusState(),
    );
  });

  Future<void> finishOwned(WidgetTester tester, Future<void> operation) async {
    bool finished = false;
    final Future<void> observed = operation.whenComplete(() => finished = true);
    for (int turn = 0; turn < 20 && !finished; turn++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(finished, isTrue, reason: 'Owned asynchronous boundary must finish');
    await observed;
  }

  void checkWidgets(String description, WidgetTesterCallback body) {
    testWidgets(description, (WidgetTester tester) async {
      try {
        await body(tester);
      } finally {
        // Widget APIs must finish inside the test that owns their clock.
        await tester.pumpWidget(const SizedBox.shrink());
        if (!confirmation.isCompleted) confirmation.complete(false);
        if (!publication.isCompleted) {
          publication.complete(AccountBlockTemplate(blockType: 1));
        }
        await tester.pump();
        await finishOwned(tester, sender.close());
        await finishOwned(tester, draft.close());
        await finishOwned(tester, syncStates.close());
        contacts.dispose();
        prices.dispose();
        kSelectedAddress = previousAddress;
        kDefaultAddressList = previousAddresses;
        BalanceVisibility.debugReset();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  Widget host({bool actualDialog = false, bool light = false}) => MaterialApp(
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<SendTransactionBloc>.value(value: sender),
        BlocProvider<SendDraftCubit>.value(value: draft),
      ],
      child: Scaffold(
        body: SingleChildScrollView(
          child: SendPopulated(
            balances: <String, AccountInfo>{
              from: AccountInfo(
                address: from,
                blockCount: 1,
                balanceInfoList: <BalanceInfoListItem>[
                  BalanceInfoListItem(
                    token: kZnnCoin,
                    balance: BigInt.from(100000000000),
                  ),
                ],
              ),
            },
            contacts: contacts,
            priceFeed: prices,
            syncCubit: sync,
            captureSession: () => SendSession(
              isCurrent: () =>
                  current && WalletContextRevision.value == revision,
            ),
            confirm: actualDialog
                ? null
                : (SendIntent intent, SendSession _) async {
                    shown.add(intent);
                    final bool answer = await confirmation.future;
                    confirmationAnswered.complete();
                    return answer;
                  },
            onOriginalResult: (_, SendRequestResult result) async {
              observed.add(result);
              outcomeObserved.complete();
              if (throwObserver) throw StateError('Presentation failed');
            },
          ),
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    bool actualDialog = false,
    bool light = false,
  }) async {
    confirmation = Completer<bool>();
    publication = Completer<AccountBlockTemplate>();
    publicationStarted = Completer<void>();
    confirmationAnswered = Completer<void>();
    outcomeObserved = Completer<void>();
    // Bloc installs its event subscriptions in its constructor. Keep those
    // subscriptions on the same fake clock as admission and publication.
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
      recordRecipient: (_, _) async {},
    );
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(actualDialog: actualDialog, light: light));
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    final Finder action = find.byKey(const Key('send_submit_button'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
  }

  Future<void> answer(WidgetTester tester, {required bool accepted}) async {
    confirmation.complete(accepted);
    await finishOwned(tester, confirmationAnswered.future);
    await tester.pump();
  }

  checkWidgets('one immutable confirmation admits one original request', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await submit(tester);
    expect(shown, hasLength(1));
    expect(shown.single.displayAmount, '12.5');
    expect(shown.single.toAddress, to);
    final PrimaryPill pill = tester.widget<PrimaryPill>(
      find.descendant(
        of: find.byKey(const Key('send_submit_button')),
        matching: find.byType(PrimaryPill),
      ),
    );
    expect(pill.onPressed, isNull);
    final SendDraft confirmedDraft = draft.state;
    await answer(tester, accepted: true);
    await finishOwned(tester, publicationStarted.future);
    expect(draft.state, same(confirmedDraft));
    expect(
      publishCount,
      1,
      reason:
          'sender status ${sender.state.status}, observed ${observed.length}',
    );
    final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1);
    publication.complete(accepted);
    await finishOwned(tester, outcomeObserved.future);
    expect(observed.single.block, same(accepted));
    expect(draft.state.isEmpty, isTrue);
    expect(sender.busy.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final String change in <String>[
    'cancel',
    'session',
    'away-back',
    'draft',
    'draft-round-trip',
    'lag',
    'busy',
  ]) {
    checkWidgets('$change during confirmation cannot admit a transfer', (
      WidgetTester tester,
    ) async {
      await show(tester);
      await submit(tester);
      final SendDraft original = draft.state;
      final Object owner = Object();
      switch (change) {
        case 'session':
          current = false;
        case 'away-back':
          WalletContextRevision.invalidate();
        case 'draft':
          draft.selectRecipient(from);
        case 'draft-round-trip':
          draft
            ..selectRecipient(from)
            ..selectRecipient(original.recipient);
        case 'lag':
          final _Info info = _Info();
          when(() => info.state).thenReturn(SyncState.syncing);
          when(() => info.currentHeight).thenReturn(1);
          when(() => info.targetHeight).thenReturn(20);
          syncStates.add(
            NodeSyncStatusState(
              status: TimerStatus.success,
              data: Pair<SyncState, SyncInfo>(SyncState.syncDone, info),
            ),
          );
        case 'busy':
          expect(sender.tryReserve(owner), isTrue);
        case 'cancel':
          break;
      }
      await answer(tester, accepted: change != 'cancel');
      expect(publishCount, 0);
      expect(observed, isEmpty);
      expect(
        draft.state.recipient,
        change == 'draft' ? from : original.recipient,
      );
      sender.releaseReservation(owner);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  checkWidgets('late acceptance preserves a new draft after the form leaves', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await submit(tester);
    await answer(tester, accepted: true);
    await finishOwned(tester, publicationStarted.future);
    expect(publishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    draft.selectRecipient(from);
    throwObserver = true;
    final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1);
    publication.complete(accepted);
    await finishOwned(tester, outcomeObserved.future);
    expect(observed.single.block, same(accepted));
    expect(draft.state.recipient, from);
    expect(draft.state.amount, '12.5');
    expect(sender.busy.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  checkWidgets('a failed original result retains the exact draft', (
    WidgetTester tester,
  ) async {
    await show(tester);
    final SendDraft original = draft.state;
    await submit(tester);
    await answer(tester, accepted: true);
    await finishOwned(tester, publicationStarted.future);
    final StateError failure = StateError('Outcome unavailable');
    publication.completeError(failure);
    await finishOwned(tester, outcomeObserved.future);
    expect(observed.single.error, same(failure));
    expect(draft.state, original);
    expect(sender.busy.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  checkWidgets('late acceptance preserves a replacement with original values', (
    WidgetTester tester,
  ) async {
    await show(tester);
    final SendDraft original = draft.state;
    await submit(tester);
    await answer(tester, accepted: true);
    await finishOwned(tester, publicationStarted.future);
    expect(publishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    draft
      ..selectRecipient(from)
      ..selectRecipient(original.recipient);
    final SendDraft replacement = draft.state;
    expect(replacement, original);
    expect(identical(replacement, original), isFalse);
    publication.complete(AccountBlockTemplate(blockType: 1));
    await finishOwned(tester, outcomeObserved.future);
    expect(observed, hasLength(1));
    expect(draft.state, same(replacement));
  });

  checkWidgets(
    'callbacks from a dismissed confirmation cannot leave the wallet',
    (
      WidgetTester tester,
    ) async {
      await show(tester, actualDialog: true);
      await submit(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final Finder cancelKey = find.byKey(
        const Key('send_confirmation_cancel'),
      );
      final VoidCallback accept = tester
          .widget<PrimaryPill>(
            find.byKey(const Key('send_confirmation_accept')),
          )
          .onPressed!;
      final VoidCallback cancel = tester
          .widget<TextButton>(cancelKey)
          .onPressed!;
      Navigator.of(tester.element(cancelKey)).pop(false);
      accept();
      cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      accept();
      cancel();
      expect(find.byType(SendPopulated), findsOneWidget);
      expect(publishCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool acceptFirst in <bool>[false, true]) {
    checkWidgets(
      'one dialog decision survives repeated callbacks $acceptFirst',
      (
        WidgetTester tester,
      ) async {
        await show(tester, actualDialog: true);
        await submit(tester);
        await tester.pump(const Duration(milliseconds: 300));
        final PrimaryPill accept = tester.widget<PrimaryPill>(
          find.byKey(const Key('send_confirmation_accept')),
        );
        final TextButton cancel = tester.widget<TextButton>(
          find.byKey(const Key('send_confirmation_cancel')),
        );
        final VoidCallback first = acceptFirst
            ? accept.onPressed!
            : cancel.onPressed!;
        final VoidCallback second = acceptFirst
            ? cancel.onPressed!
            : accept.onPressed!;
        first();
        second();
        first();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SendPopulated), findsOneWidget);
        expect(publishCount, acceptFirst ? 1 : 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bool light in <bool>[false, true]) {
    checkWidgets(
      'actual dialog shows full original facts and cancellation $light',
      (WidgetTester tester) async {
        await show(tester, actualDialog: true, light: light);
        await submit(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const Key('send_confirmation_marker')),
          findsOneWidget,
        );
        expect(find.text('Send 12.5 ZNN?'), findsOneWidget);
        expect(find.text('Checked when sending'), findsOneWidget);
        expect(find.text('First send recorded here'), findsOneWidget);
        expect(find.text('Confirm on your device after Send.'), findsNothing);
        expect(find.text(to), findsWidgets);
        await tester.tap(find.byKey(const Key('send_confirmation_cancel')));
        await tester.pumpAndSettle();
        expect(publishCount, 0);
        expect(draft.state.amount, '12.5');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
