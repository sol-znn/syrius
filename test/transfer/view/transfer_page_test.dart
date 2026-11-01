import 'dart:async';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart' as foundation show TargetPlatform;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../../harness/app/agent.dart';

import '../../helpers/hydrated_bloc.dart';

Future<T> _driveReceiveCommand<T>(
  WidgetTester tester,
  Future<T> command,
) async {
  bool done = false;
  T? result;
  Object? failure;
  StackTrace? trace;
  unawaited(command.then((T value) {
    result = value;
    done = true;
  }, onError: (Object error, StackTrace stack) {
    failure = error;
    trace = stack;
    done = true;
  }));
  for (int frame = 0; frame < 80 && !done; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'The original UI command did not finish');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result as T;
}

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _Tokens extends MockBloc<AllTokensEvent, AllTokensState>
    implements AllTokensBloc {}

class _Transactions extends MockBloc<SendTransactionEvent, SendTransactionState>
    implements SendTransactionBloc {}

class _Pending
    extends MockBloc<InfiniteListEvent, InfiniteListState<AccountBlock>>
    implements PendingTransactionsBloc {}

class _Block extends Mock implements AccountBlock {}

class _Worker extends AutoReceiveTxWorker {
  _Worker(this.sender);

  final SendTransactionBloc sender;
  final List<Hash> calls = <Hash>[];
  Completer<AccountBlockTemplate?>? _completion;

  @override
  bool running = false;

  @override
  ReceiveOrigin? captureOrigin({bool Function()? sourceIsCurrent}) {
    final String? selected = kSelectedAddress;
    if (selected == null || !(sourceIsCurrent?.call() ?? true)) return null;
    final List<String> addresses = kDefaultAddressList.cast<String>().toList();
    return ReceiveOrigin(
      sender: sender,
      ledger: LedgerApi(),
      stats: StatsApi(),
      chainId: 321,
      nodeChainId: 321,
      selectedAddress: selected,
      addresses: addresses,
      isCurrent: () =>
          kSelectedAddress == selected &&
          kDefaultAddressList.length == addresses.length &&
          kDefaultAddressList.indexed.every(
            ((int, String?) member) => member.$2 == addresses[member.$1],
          ) &&
          (sourceIsCurrent?.call() ?? true),
    );
  }

  @override
  Future<AccountBlockTemplate?> autoReceiveTransactionHash(
    Hash hash, {
    ReceiveOrigin? origin,
    bool Function()? sourceIsCurrent,
  }) {
    if (origin == null ||
        !origin.isCurrent ||
        !(sourceIsCurrent?.call() ?? true)) {
      return Future<AccountBlockTemplate?>.error(const ReceiveRefused());
    }
    calls.add(hash);
    running = true;
    inFlight.value = <Hash>{...inFlight.value, hash};
    _completion = Completer<AccountBlockTemplate?>();
    return _completion!.future;
  }

  void finish({bool hold = true, bool fail = false}) {
    running = false;
    if (!hold) inFlight.value = <Hash>{};
    if (fail) {
      _completion!.completeError(StateError('test refusal'));
    } else {
      _completion!.complete();
    }
    _completion = null;
  }
}

AccountBlock _block(int index, {bool metadata = true}) {
  final _Block block = _Block();
  when(() => block.hash).thenReturn(Hash.digest(<int>[index]));
  when(() => block.blockType).thenReturn(2);
  when(() => block.address).thenReturn(emptyAddress);
  when(() => block.amount).thenReturn(BigInt.from(1250000000));
  when(() => block.token).thenReturn(metadata ? kZnnCoin : null);
  when(() => block.confirmationDetail).thenReturn(null);
  return block;
}

InfiniteListState<AccountBlock> _rows(
  List<AccountBlock> rows, {
  bool more = false,
}) => InfiniteListState<AccountBlock>(
  status: InfiniteListStatus.success,
  data: rows,
  hasReachedMax: !more,
);

Finder _mode(TransferMode mode) =>
    find.byKey(Segment.keyOf('transfer_mode', mode));
Finder _button(AccountBlock block) =>
    find.byKey(ValueKey<String>('receive_${block.hash}'));

void main() {
  initHydratedStorage();
  late _Balances balances;
  late _Tokens tokens;
  late _Transactions transactions;
  late _Pending pending;
  late _Worker worker;
  late SendDraftCubit draft;
  late PriceFeed prices;
  late TransferController controller;
  late StreamController<InfiniteListState<AccountBlock>> pendingStates;
  late StreamController<MultipleBalanceState> balanceStates;
  late StreamController<SendTransactionState> transactionStates;
  late ValueNotifier<bool> senderBusy;
  late String? previousAddress;
  late List<String?> previousAddresses;
  late Map<String, String> previousLabels;
  late SharedPrefsService? previousPreferences;

  setUpAll(() {
    registerFallbackValue(const MultipleBalanceFetch(addresses: <String>[]));
    registerFallbackValue(const AllTokensRequested());
    registerFallbackValue(const InfiniteListRequested());
    registerFallbackValue(
      SendTransactionInitiateFromBlock(
        block: AccountBlockTemplate(blockType: 1),
        fromAddress: emptyAddress.toString(),
        reasonForGeneratingPlasma: '',
      ),
    );
  });

  setUp(() async {
    previousAddress = kSelectedAddress;
    previousAddresses = kDefaultAddressList;
    previousLabels = kAddressLabelMap;
    previousPreferences = app.sharedPrefsService;
    kSelectedAddress = emptyAddress.toString();
    kDefaultAddressList = <String?>[kSelectedAddress];
    kAddressLabelMap = <String, String>{kSelectedAddress!: 'Address 1'};
    Hive.init('transfer-view-preferences');
    final Box<dynamic> preferences = await Hive.openBox<dynamic>(
      kSharedPrefsBox,
      bytes: Uint8List(0),
    );
    await preferences.put(kAutoReceiveKey, false);
    app.sharedPrefsService = await SharedPrefsService.getInstance();
    BalanceVisibility.debugReset();
    balances = _Balances();
    tokens = _Tokens();
    transactions = _Transactions();
    pending = _Pending();
    worker = _Worker(transactions);
    draft = SendDraftCubit();
    prices = PriceFeed(request: (_) async => '{}');
    controller = TransferController();
    pendingStates = StreamController<InfiniteListState<AccountBlock>>.broadcast(
      sync: true,
    );
    balanceStates = StreamController<MultipleBalanceState>.broadcast(
      sync: true,
    );
    transactionStates = StreamController<SendTransactionState>.broadcast(
      sync: true,
    );
    senderBusy = ValueNotifier<bool>(false);
    when(() => transactions.busy).thenReturn(senderBusy);
    whenListen(
      balances,
      balanceStates.stream,
      initialState: MultipleBalanceState(
        status: MultipleBalanceStatus.success,
        data: <String, AccountInfo>{
          kSelectedAddress!: AccountInfo(
            address: kSelectedAddress,
            blockCount: 1,
            balanceInfoList: <BalanceInfoListItem>[
              BalanceInfoListItem(
                token: kZnnCoin,
                balance: BigInt.from(100000000000),
              ),
              BalanceInfoListItem(
                token: kQsrCoin,
                balance: BigInt.from(100000000000),
              ),
            ],
          ),
        },
      ),
    );
    whenListen(
      tokens,
      const Stream<AllTokensState>.empty(),
      initialState: AllTokensPopulated(data: <Token>[kZnnCoin, kQsrCoin]),
    );
    whenListen(
      transactions,
      transactionStates.stream,
      initialState: const SendTransactionState(),
    );
    whenListen(
      pending,
      pendingStates.stream,
      initialState: _rows(<AccountBlock>[]),
    );
  });

  tearDown(() async {
    await pendingStates.close();
    await balanceStates.close();
    await transactionStates.close();
    senderBusy.dispose();
    await draft.close();
    prices.dispose();
    controller.dispose();
    worker.dispose();
    await Hive.close();
    app.sharedPrefsService = previousPreferences;
    kSelectedAddress = previousAddress;
    kDefaultAddressList = previousAddresses;
    kAddressLabelMap = previousLabels;
    BalanceVisibility.debugReset();
    AppLottie.debugClear();
  });

  Widget host({
    bool light = false,
    bool reduced = false,
    ThemeData? themeOverride,
  }) => MaterialApp(
    theme: themeOverride ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<MultipleBalanceBloc>.value(value: balances),
        BlocProvider<AllTokensBloc>.value(value: tokens),
        BlocProvider<SendTransactionBloc>.value(value: transactions),
        BlocProvider<PendingTransactionsBloc>.value(value: pending),
        BlocProvider<SendDraftCubit>.value(value: draft),
      ],
      child: RepaintBoundary(
        key: const Key('transfer_paint'),
        child: Scaffold(
          body: TransferPage(
            controller: controller,
            receiveWorker: worker,
            priceFeed: prices,
          ),
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    bool light = false,
    bool reduced = false,
    ThemeData? themeOverride,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(
      light: light, reduced: reduced, themeOverride: themeOverride,
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> select(WidgetTester tester, TransferMode mode) async {
    await tester.tap(_mode(mode));
    await tester.pump();
    await tester.pump(
      TransferPage.modeDuration + const Duration(microseconds: 1),
    );
  }

  Future<Map<String, Color>?> paintedSurface(
    WidgetTester tester,
    Rect card,
  ) => tester.runAsync<Map<String, Color>>(() async {
    final RenderRepaintBoundary boundary = tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('transfer_paint')),
        );
    final ui.Image image = await boundary.toImage();
    try {
      final ByteData bytes = (await image.toByteData())!;
      Color pixel(int x, int y) {
        final int offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }
      return <String, Color>{
        'field': pixel(100, 100),
        'outside': pixel(card.left.round() - 12, card.top.round() + 30),
        'corner': pixel(card.left.round() + 5, card.top.round() + 3),
      };
    } finally {
      image.dispose();
    }
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'one centered card and an established empty Receive line, light $light',
      (WidgetTester tester) async {
        await show(tester, light: light);
        final Rect card = tester.getRect(
          find.byKey(const Key('transfer_card')),
        );
        expect(card.width, 640);
        expect(card.center.dx, 640);
        final AppTokens paintTokens = light ? AppTokens.light : AppTokens.dark;
        final Map<String, Color> painted =
            (await paintedSurface(tester, card))!;
        expect(painted['field'], paintTokens.background);
        expect(painted['outside'], paintTokens.background);
        expect(painted['corner'], paintTokens.card);
        expect(find.byKey(const Key('transfer_send_screen')), findsOneWidget);
        expect(find.byKey(const Key('transfer_receive_screen')), findsNothing);
        expect(find.byKey(const Key('transfer_pending')), findsNothing);
        expect(find.byType(LatestTransactionsCard), findsNothing);
        await select(tester, TransferMode.receive);
        expect(
          find.byKey(const Key('transfer_receive_screen')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('transfer_pending')), findsOneWidget);
        expect(find.text('None yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('actual Receive popup selects QSR through original agent input',
    (WidgetTester tester) async {
      await show(tester, reduced: true, themeOverride:
        AppTheme.darkTheme.copyWith(
          platform: foundation.TargetPlatform.windows,
        ));
      await select(tester, TransferMode.receive);
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      // Keep direct call sites so the finite failure projection names the step.
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'key', 'key': 'escape'},
      ));
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'key', 'key': 'escape'},
      ));
      expect(find.byKey(const Key('receive_qr_toggle')).hitTestable(),
        findsOneWidget);
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'tap', 'key': 'receive_qr_toggle'},
      ));
      expect(find.text('Hide QR'), findsOneWidget);
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'tap', 'key': 'receive_request_toggle'},
      ));
      expect(find.byKey(const Key('receive_amount_field')).hitTestable(),
        findsOneWidget);
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{
          'cmd': 'type', 'key': 'receive_amount_field', 'value': '100',
        },
      ));
      final DropdownMenu<Token> initial = tester.widget<DropdownMenu<Token>>(
        find.byKey(const Key('receive_token_picker')),
      );
      expect(initial.dropdownMenuEntries.map(
        (DropdownMenuEntry<Token> row) => row.value.tokenStandard,
      ), contains(kQsrCoin.tokenStandard));
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'tap', 'key': 'receive_token_picker'},
      ));
      expect(find.text('QSR').hitTestable(), findsOneWidget,
        reason: 'The original picker must expose a reachable QSR menu entry');
      await _driveReceiveCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'tap', 'text': 'QSR', 'exact': true},
      ));
      final DropdownMenu<Token> picker = tester.widget<DropdownMenu<Token>>(
        find.byKey(const Key('receive_token_picker')),
      );
      expect(picker.controller!.text, 'QSR');
      expect(find.text('Hide QR'), findsOneWidget);
      final String payload = tester.widget<Tooltip>(
        find.byKey(const Key('receive_qr_payload')),
      ).message!;
      expect(payload, startsWith('qsr:'));
      expect(payload, contains('zts=${kQsrCoin.tokenStandard}'));
      expect(payload, endsWith('&amount=10000000000'));
      expect(find.byKey(const Key('receive_share_image')), findsOneWidget);
      expect(find.byKey(const Key('receive_save_image')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'modes retain live form state and deny hidden focus, semantics and tickers',
    (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await show(tester);
        final Finder recipient = find.byKey(const Key('send_recipient_field'));
        final Finder amount = find.byKey(const Key('send_amount_field'));
        final Object sendState = tester.state(find.byType(SendPopulated));
        final Object receiveState = tester.state(
          find.byType(ReceivePopulated, skipOffstage: false),
        );
        await tester.enterText(recipient, emptyAddress.toString());
        await tester.enterText(amount, '12.5');
        final FocusNode focus = tester.widget<TextField>(amount).focusNode!;
        expect(focus.hasFocus, isTrue);
        await select(tester, TransferMode.receive);
        expect(focus.hasFocus, isFalse);
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        expect(find.semantics.byLabel('Recipient Address'), findsNothing);
        final Element hidden = tester.element(
          find.byKey(const Key('transfer_send_screen'), skipOffstage: false),
        );
        expect(TickerMode.valuesOf(hidden).enabled, isFalse);
        expect(tester.state(find.byType(ReceivePopulated)), same(receiveState));
        await select(tester, TransferMode.send);
        expect(tester.state(find.byType(SendPopulated)), same(sendState));
        expect(
          tester.widget<TextField>(recipient).controller!.text,
          emptyAddress.toString(),
        );
        expect(tester.widget<TextField>(amount).controller!.text, '12.5');
        expect(draft.state.amount, '12.5');
        expect(TickerMode.valuesOf(tester.element(recipient)).enabled, isTrue);
        expect(focus.skipTraversal, isFalse);
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        final FocusNode recipientFocus = tester
            .widget<TextField>(recipient)
            .focusNode!;
        for (int i = 0; i < 20 && !recipientFocus.hasFocus; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(recipientFocus.hasFocus, isTrue);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'header sender changes preserve the exact draft and reject busy calls',
    (
      WidgetTester tester,
    ) async {
      await show(tester);
      final Finder recipient = find.byKey(const Key('send_recipient_field'));
      final Finder amount = find.byKey(const Key('send_amount_field'));
      await tester.enterText(recipient, emptyAddress.toString());
      await tester.enterText(amount, '12.5');
      final String second = Address(
        'z',
        <int>[0, 2, ...List<int>.filled(18, 3)],
      ).toString();
      kDefaultAddressList = <String?>[kSelectedAddress, second];
      kAddressLabelMap[second] = 'Address 2';
      balanceStates.add(
        MultipleBalanceState(
          status: MultipleBalanceStatus.success,
          data: <String, AccountInfo>{
            ...balances.state.data!,
            second: AccountInfo(
              address: second,
              blockCount: 1,
              balanceInfoList: <BalanceInfoListItem>[
                BalanceInfoListItem(
                  token: kZnnCoin,
                  balance: BigInt.from(2500000000),
                ),
              ],
            ),
          },
        ),
      );
      await tester.pump();
      final Finder header = find.byKey(const Key('transfer_sender'));
      await tester.tap(header);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Address 2').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(draft.state.fromAddress, second);
      expect(draft.state.recipient, emptyAddress.toString());
      expect(draft.state.amount, '12.5');
      expect(
        tester.widget<TextField>(recipient).controller!.text,
        emptyAddress.toString(),
      );
      expect(tester.widget<TextField>(amount).controller!.text, '12.5');
      senderBusy.value = true;
      await tester.pump();
      final PopupMenuButton<String> picker = tester
          .widget<PopupMenuButton<String>>(header);
      expect(picker.enabled, isFalse);
      picker.onSelected!(kSelectedAddress!);
      await tester.pump();
      expect(draft.state.fromAddress, second);
      expect(draft.state.amount, '12.5');
      senderBusy.value = false;
      await tester.pump();
    },
  );

  testWidgets('collection outcomes preserve a mounted transfer draft', (
    WidgetTester tester,
  ) async {
    await show(tester);
    final Finder recipient = find.byKey(const Key('send_recipient_field'));
    final Finder amount = find.byKey(const Key('send_amount_field'));
    await tester.enterText(recipient, emptyAddress.toString());
    await tester.enterText(amount, '12.50000001');
    final SendDraft original = draft.state;
    senderBusy.value = true;
    transactionStates.add(
      const SendTransactionState(
        status: SendTransactionStatus.loading,
        origin: SendTransactionOrigin.collection,
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    transactionStates.add(
      SendTransactionState(
        status: SendTransactionStatus.success,
        origin: SendTransactionOrigin.collection,
        data: AccountBlockTemplate(blockType: 1),
      ),
    );
    senderBusy.value = false;
    await tester.pump();
    expect(
      tester.widget<TextField>(recipient).controller!.text,
      emptyAddress.toString(),
    );
    expect(tester.widget<TextField>(amount).controller!.text, '12.50000001');
    expect(draft.state, original);
    expect(tester.takeException(), isNull);
    verifyNever(() => transactions.add(any()));
  });

  testWidgets('palette recipient reaches an already mounted or retained Send', (
    WidgetTester tester,
  ) async {
    await show(tester);
    final Finder recipient = find.byKey(const Key('send_recipient_field'));
    final Finder amount = find.byKey(const Key('send_amount_field'));
    await tester.enterText(amount, '12.50000001');
    final String first = Address(
      Address.prefix,
      List<int>.generate(20, (int i) => i == 0 ? 0 : 1),
    ).toString();
    final String second = Address(
      Address.prefix,
      List<int>.generate(20, (int i) => i == 0 ? 0 : 2),
    ).toString();
    draft.selectRecipient(first);
    await tester.pump();
    expect(tester.widget<TextField>(recipient).controller!.text, first);
    expect(tester.widget<TextField>(amount).controller!.text, '12.50000001');
    await select(tester, TransferMode.receive);
    draft.selectRecipient(second);
    await tester.pump();
    await select(tester, TransferMode.send);
    expect(tester.widget<TextField>(recipient).controller!.text, second);
    expect(tester.widget<TextField>(amount).controller!.text, '12.50000001');
    expect(draft.state.recipient, second);
    verifyNever(() => transactions.add(any()));
  });

  testWidgets(
    'mode fade keeps 260 ms under both reduced-motion flags',
    (WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await show(tester, reduced: true);
      await tester.tap(_mode(TransferMode.receive));
      await tester.pump();
      final Finder fade = find
          .ancestor(
            of: find.byKey(const Key('transfer_receive_screen')),
            matching: find.byType(FadeTransition),
          )
          .first;
      expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 130));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        closeTo(0.5, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 130, microseconds: 1));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'segment arrow keys change the mounted mode',
    (WidgetTester tester) async {
      await show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(_mode(TransferMode.send))).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(
        TransferPage.modeDuration + const Duration(microseconds: 1),
      );
      expect(controller.value, TransferMode.receive);
      expect(find.byKey(const Key('transfer_receive_screen')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.value, TransferMode.send);
    },
  );

  testWidgets(
    'unknown and failed pending states cannot become None yet',
    (WidgetTester tester) async {
      whenListen(
        pending,
        pendingStates.stream,
        initialState: const InfiniteListState<AccountBlock>.initial(),
      );
      controller.value = TransferMode.receive;
      await show(tester);
      expect(find.byKey(const Key('transfer_pending_loading')), findsOneWidget);
      expect(find.text('None yet'), findsNothing);
      pendingStates.add(
        InfiniteListState<AccountBlock>(
          status: InfiniteListStatus.failure,
          error: FailureException(),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('transfer_pending_failure')), findsOneWidget);
      expect(find.text('None yet'), findsNothing);
      await tester.tap(find.text('Retry'));
      verify(
        () => pending.add(InfiniteListRefreshRequested(address: emptyAddress)),
      ).called(1);
    },
  );

  testWidgets(
    'receives by exact hash with global and published guards',
    (WidgetTester tester) async {
      final AccountBlock first = _block(1);
      final AccountBlock second = _block(2);
      whenListen(
        pending,
        pendingStates.stream,
        initialState: _rows(<AccountBlock>[first, second]),
      );
      await show(tester);
      expect(find.text('Auto-receive off'), findsOneWidget);
      await tester.tap(_button(first));
      await tester.pump();
      expect(worker.calls, <Hash>[first.hash]);
      expect(tester.widget<OutlinedButton>(_button(first)).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_button(second)).onPressed, isNull);
      expect(find.text('Receiving'), findsOneWidget);
      worker.finish();
      await tester.pump();
      expect(tester.widget<OutlinedButton>(_button(first)).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(_button(second)).onPressed,
        isNotNull,
      );
      pendingStates.add(_rows(<AccountBlock>[second, first]));
      await tester.pump();
      expect(tester.widget<OutlinedButton>(_button(first)).onPressed, isNull);
      await select(tester, TransferMode.receive);
      expect(tester.widget<OutlinedButton>(_button(first)).onPressed, isNull);
      worker.inFlight.value = <Hash>{};
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(_button(first)).onPressed,
        isNotNull,
      );
      expect(worker.calls, <Hash>[first.hash]);
    },
  );

  testWidgets(
    'externally running work blocks every row and failures do not retry',
    (WidgetTester tester) async {
      final AccountBlock first = _block(3);
      final AccountBlock second = _block(4);
      whenListen(
        pending,
        pendingStates.stream,
        initialState: _rows(<AccountBlock>[first, second]),
      );
      worker.running = true;
      worker.inFlight.value = <Hash>{first.hash};
      await show(tester);
      expect(tester.widget<OutlinedButton>(_button(second)).onPressed, isNull);
      worker.running = false;
      worker.inFlight.value = <Hash>{};
      await tester.pump();
      await tester.tap(_button(second));
      await tester.pump();
      worker.finish(hold: false, fail: true);
      await tester.pump();
      expect(find.text('Receive transaction failed'), findsOneWidget);
      expect(worker.calls, <Hash>[second.hash]);
      expect(
        tester.widget<OutlinedButton>(_button(second)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'exact duplicate hashes render once and missing metadata invents no amount',
    (WidgetTester tester) async {
      final AccountBlock known = _block(5);
      final AccountBlock unknown = _block(6, metadata: false);
      whenListen(
        pending,
        pendingStates.stream,
        initialState: _rows(<AccountBlock>[known, known, unknown]),
      );
      await show(tester);
      expect(_button(known), findsOneWidget);
      expect(_button(unknown), findsOneWidget);
      final Finder row = find.byKey(
        ValueKey<String>('transfer_pending_${unknown.hash}'),
      );
      expect(
        find.descendant(of: row, matching: find.text('Pending')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: row, matching: find.byType(AmountText)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'pagination asks for the next page once until a live answer arrives',
    (WidgetTester tester) async {
      final List<AccountBlock> rows = List<AccountBlock>.generate(
        8,
        (int index) => _block(index + 10),
      );
      whenListen(
        pending,
        pendingStates.stream,
        initialState: _rows(rows, more: true),
      );
      await show(tester);
      await tester.tap(find.byKey(const Key('transfer_pending_more')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('transfer_pending_more')))
            .onPressed,
        isNull,
      );
      verify(
        () => pending.add(InfiniteListMoreRequested(address: emptyAddress)),
      ).called(1);
      pendingStates.add(_rows(rows));
      await tester.pump();
      expect(find.byKey(const Key('transfer_pending_more')), findsNothing);
      verifyNever(
        () => pending.add(any(that: isA<InfiniteListMoreRequested>())),
      );
    },
  );

  testWidgets(
    'paired receipts retain inbound hashes and hide amounts',
    (WidgetTester tester) async {
      final AccountBlock inbound = _block(40);
      final _Block receipt = _Block();
      when(() => receipt.hash).thenReturn(Hash.digest(<int>[41]));
      when(() => receipt.blockType).thenReturn(3);
      when(() => receipt.pairedAccountBlock).thenReturn(inbound);
      whenListen(
        pending,
        pendingStates.stream,
        initialState: _rows(<AccountBlock>[receipt]),
      );
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await show(tester);
        expect(_button(inbound), findsOneWidget);
        expect(_button(receipt), findsNothing);
        expect(find.text('12.5 ZNN', findRichText: true), findsOneWidget);
        BalanceVisibility.instance.set(true);
        await tester.pump();
        expect(find.semantics.byLabel(RegExp('12[.]5.*ZNN')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('transfer_pending')),
            matching: find.text('••••'),
          ),
          findsOneWidget,
        );
        expect(worker.calls, isEmpty);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'controller refreshes mounted modes and keeps Zap seamed',
    (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await show(tester);
        controller.refresh();
        verify(
          () => balances.add(any(that: isA<MultipleBalanceFetch>())),
        ).called(1);
        await select(tester, TransferMode.receive);
        controller.refresh();
        verify(() => tokens.add(const AllTokensRequested())).called(1);
        await select(tester, TransferMode.zap);
        controller.refresh();
        expect(find.byKey(const Key('transfer_zap_screen')), findsOneWidget);
        expect(find.byType(SeamGate), findsWidgets);
        expect(
          tester
              .widgetList<SeamGate>(find.byType(SeamGate))
              .every((SeamGate gate) => gate.seam == Seam.zapSend),
          isTrue,
        );
        expect(find.semantics.byLabel('Not yet'), findsWidgets);
        expect(worker.calls, isEmpty);
        verifyNever(() => transactions.add(any()));
        await tester.pumpWidget(const SizedBox());
        controller
          ..refresh()
          ..value = TransferMode.receive;
        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.byKey(const Key('transfer_receive_screen')),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
