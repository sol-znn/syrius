import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, FlutterExceptionHandler, StackFrame;
import 'package:flutter/gestures.dart';
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
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../harness/app/agent.dart';
import '../helpers/hydrated_bloc.dart';

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _Zenon extends Mock implements Zenon {}

class _Ledger extends Mock implements LedgerApi {}

const Set<String> _frameworkSources = <String>{
  'package:flutter/src/widgets/framework.dart',
  'package:flutter/src/rendering/object.dart',
  'package:flutter/src/rendering/box.dart',
  'package:flutter/src/material/dropdown.dart',
  'package:flutter/src/material/dropdown_menu.dart',
  'package:flutter/src/foundation/change_notifier.dart',
  'package:flutter/src/widgets/scroll_controller.dart',
  'package:flutter/src/widgets/binding.dart',
  'package:flutter/src/scheduler/binding.dart',
  'package:provider/src/provider.dart',
  'package:provider/src/inherited_provider.dart',
  'package:flutter_bloc/src/bloc_builder.dart',
  'package:flutter_bloc/src/bloc_provider.dart',
  'package:bloc/src/emitter.dart',
  'package:get_it/get_it_impl.dart',
  'package:flutter_test/src/binding.dart',
  'package:flutter_test/src/widget_tester.dart',
  'package:flutter_test/src/test_async_utils.dart',
  'package:flutter_test/src/async_matchers.dart',
};

void _reportFrameworkMessage(String message, void Function(String)? report) {
  if (report != null) {
    report(message);
  } else {
    // Only fixed markers, allowed package names and numbers reach this sink.
    // ignore: avoid_print
    print(message);
  }
}

void _reportFrameworkKind(
  FlutterErrorDetails details,
  void Function(String)? report,
) {
  final Object exception = details.exception;
  String kind = 'OTHER';
  if (exception is FlutterError) {
    kind = 'FLUTTER_ERROR';
  } else if (exception is AssertionError) {
    kind = 'ASSERTION_ERROR';
  } else if (exception is StateError) {
    kind = 'STATE_ERROR';
  } else if (exception is NoSuchMethodError) {
    kind = 'NO_SUCH_METHOD';
  } else if (exception is TypeError) {
    kind = 'TYPE_ERROR';
  } else if (exception is FormatException) {
    kind = 'FORMAT_ERROR';
  }
  _reportFrameworkMessage('CI_FRAMEWORK_FAILURE_KIND:$kind', report);
}

void _reportFrameworkPosition(
  FlutterErrorDetails details,
  void Function(String)? report,
) {
  final StackTrace? original = details.stack;
  if (original == null) return;
  final String text = FlutterError.demangleStackTrace(original).toString();
  if (text.length > 65536) return;
  final List<StackFrame> frames = StackFrame.fromStackString(text);
  for (final StackFrame frame in frames.take(128)) {
    final String source =
        '${frame.packageScheme}:${frame.package}/${frame.packagePath}';
    if (_frameworkSources.contains(source) &&
        frame.line > 0 && frame.line <= 999999 &&
        frame.column > 0 && frame.column <= 999999) {
      _reportFrameworkMessage(
        'CI_FRAMEWORK_CONTEXT ($source:${frame.line}:${frame.column})',
        report,
      );
      break;
    }
  }
}

VoidCallback _observeFrameworkErrors({
  void Function(String)? report,
  bool includeKind = false,
}) {
  final FlutterExceptionHandler? previous = FlutterError.onError;
  if (previous == null) throw StateError('Original error handler required');
  void observe(FlutterErrorDetails details) {
    try {
      if (includeKind) _reportFrameworkKind(details, report);
      _reportFrameworkPosition(details, report);
    } on Object {
      return;
    } finally {
      previous(details);
    }
  }

  FlutterError.onError = observe;
  return () {
    if (identical(FlutterError.onError, observe)) {
      FlutterError.onError = previous;
    }
  };
}

VoidCallback _observeTestExceptions({void Function(String)? report}) {
  final TestExceptionReporter previous = reportTestException;
  void observe(FlutterErrorDetails details, String description) {
    try {
      _reportFrameworkKind(details, report);
      _reportFrameworkPosition(details, report);
    } on Object {
      return;
    } finally {
      previous(details, description);
    }
  }

  reportTestException = observe;
  return () {
    if (identical(reportTestException, observe)) {
      reportTestException = previous;
    }
  };
}

class _Tokens extends MockBloc<AllTokensEvent, AllTokensState>
    implements AllTokensBloc {}

class _Transactions extends MockBloc<SendTransactionEvent, SendTransactionState>
    implements SendTransactionBloc {}

class _Pending
    extends MockBloc<InfiniteListEvent, InfiniteListState<AccountBlock>>
    implements PendingTransactionsBloc {}

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

InfiniteListState<AccountBlock> _rows(
  List<AccountBlock> rows, {
  bool more = false,
}) => InfiniteListState<AccountBlock>(
  status: InfiniteListStatus.success,
  data: rows,
  hasReachedMax: !more,
);

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
    // Transfer's original shader keeps frames scheduled. Let the agent's
    // unchanged wall-clock settle cap elapse alongside the test frame clock.
    await tester.runAsync(() =>
      Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'The actual header command must settle');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return result as T;
}

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
    registerFallbackValue(emptyAddress);
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
    Hive.init('transfer-sender-preferences');
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
    TextDirection direction = TextDirection.ltr,
    double scale = 1,
    MultipleBalanceBloc? balanceSource,
  }) => MaterialApp(
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<MultipleBalanceBloc>.value(
          value: balanceSource ?? balances,
        ),
        BlocProvider<AllTokensBloc>.value(value: tokens),
        BlocProvider<SendTransactionBloc>.value(value: transactions),
        BlocProvider<PendingTransactionsBloc>.value(value: pending),
        BlocProvider<SendDraftCubit>.value(value: draft),
      ],
      child: Scaffold(
        body: TransferPage(
          controller: controller,
          receiveWorker: worker,
          priceFeed: prices,
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    bool light = false,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(light: light, reduced: reduced));
    await tester.pump(const Duration(milliseconds: 500));
  }

  String addSecondAddress() {
    final String second = Address(
      'z', <int>[0, 2, ...List<int>.filled(18, 3)],
    ).toString();
    kDefaultAddressList = <String?>[emptyAddress.toString(), second];
    kSelectedAddress = second;
    kAddressLabelMap[second] = 'Address 2';
    balanceStates.add(MultipleBalanceState(
      status: MultipleBalanceStatus.success,
      data: <String, AccountInfo>{
        ...balances.state.data!,
        second: AccountInfo(
          address: second, blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(
              token: kZnnCoin, balance: BigInt.from(2500000000),
            ),
          ],
        ),
      },
    ));
    return second;
  }

  test('framework observation preserves the exact original error', () {
    final FlutterExceptionHandler? before = FlutterError.onError;
    final List<FlutterErrorDetails> received = <FlutterErrorDetails>[];
    final List<String> reports = <String>[];
    FlutterError.onError = received.add;
    final VoidCallback restore = _observeFrameworkErrors(report: reports.add);
    try {
      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: StateError('private test details'),
        stack: StackTrace.fromString(
          '#0 private (package:flutter/src/widgets/framework.dart:123:9)',
        ),
      );
      FlutterError.onError!(details);
      expect(received, hasLength(1));
      expect(identical(received.single, details), isTrue);
      const String expected = 'CI_FRAMEWORK_CONTEXT '
          '(package:flutter/src/widgets/framework.dart:123:9)';
      expect(reports, <String>[expected]);
      expect(reports.single, isNot(contains('private')));
    } finally {
      restore();
      FlutterError.onError = before;
    }
  });

  test('diagnostic failure and unknown sources still forward original errors',
      () {
    final FlutterExceptionHandler? before = FlutterError.onError;
    final List<FlutterErrorDetails> received = <FlutterErrorDetails>[];
    int reports = 0;
    FlutterError.onError = received.add;
    final VoidCallback restore = _observeFrameworkErrors(report: (_) {
      reports++;
      throw StateError('private observer failure');
    });
    try {
      final FlutterErrorDetails unknown = FlutterErrorDetails(
        exception: StateError('private test details'),
        stack: StackTrace.fromString(
          '#0 private (package:private/framework.dart:123:9)',
        ),
      );
      FlutterError.onError!(unknown);
      expect(reports, 0);
      final FlutterErrorDetails oversized = FlutterErrorDetails(
        exception: StateError('private test details'),
        stack: StackTrace.fromString(
          String.fromCharCodes(List<int>.filled(65537, 120)),
        ),
      );
      FlutterError.onError!(oversized);
      expect(reports, 0);
      final FlutterErrorDetails known = FlutterErrorDetails(
        exception: StateError('private test details'),
        stack: StackTrace.fromString(
          '#0 private (package:flutter/src/widgets/framework.dart:123:9)',
        ),
      );
      FlutterError.onError!(known);
      expect(reports, 1);
      expect(received, hasLength(3));
      expect(identical(received[0], unknown), isTrue);
      expect(identical(received[1], oversized), isTrue);
      expect(identical(received[2], known), isTrue);
    } finally {
      restore();
      FlutterError.onError = before;
    }
  });

  test('test reporter forwards the original error and description', () {
    final TestExceptionReporter before = reportTestException;
    final List<(FlutterErrorDetails, String)> received =
        <(FlutterErrorDetails, String)>[];
    final List<String> reports = <String>[];
    reportTestException = (FlutterErrorDetails details, String description) {
      received.add((details, description));
    };
    final VoidCallback restore = _observeTestExceptions(report: reports.add);
    try {
      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: StateError('private test details'),
        stack: StackTrace.fromString(
          '#0 private (package:flutter_test/src/binding.dart:123:9)',
        ),
      );
      const String description = 'private test description';
      reportTestException(details, description);
      expect(received, hasLength(1));
      expect(identical(received.single.$1, details), isTrue);
      expect(identical(received.single.$2, description), isTrue);
      const String position = 'CI_FRAMEWORK_CONTEXT '
          '(package:flutter_test/src/binding.dart:123:9)';
      expect(reports, <String>[
        'CI_FRAMEWORK_FAILURE_KIND:STATE_ERROR', position,
      ]);
      expect(reports.any((String value) => value.contains('private')), isFalse);
    } finally {
      restore();
      reportTestException = before;
    }
  });

  test('test reporter diagnostic failure preserves original delivery', () {
    final TestExceptionReporter before = reportTestException;
    final List<(FlutterErrorDetails, String)> received =
        <(FlutterErrorDetails, String)>[];
    reportTestException = (FlutterErrorDetails details, String description) {
      received.add((details, description));
    };
    final VoidCallback restore = _observeTestExceptions(report: (_) {
      throw StateError('private diagnostic failure');
    });
    try {
      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: StateError('private test details'),
      );
      const String description = 'private test description';
      reportTestException(details, description);
      expect(received, hasLength(1));
      expect(identical(received.single.$1, details), isTrue);
      expect(identical(received.single.$2, description), isTrue);
    } finally {
      restore();
      reportTestException = before;
    }
  });

  testWidgets(
      'Transfer refreshes a derived member through the real balance bloc',
      (WidgetTester tester) async {
    final String first = kSelectedAddress!;
    final String second = Address(
      'z', <int>[0, 2, ...List<int>.filled(18, 3)],
    ).toString();
    final _Zenon sdk = _Zenon();
    final _Ledger ledger = _Ledger();
    final List<String> reads = <String>[];
    final Completer<AccountInfo> secondReply = Completer<AccountInfo>();
    final AccountInfo derived = AccountInfo(
      address: second,
      blockCount: 1,
      balanceInfoList: <BalanceInfoListItem>[
        BalanceInfoListItem(
          token: kZnnCoin, balance: BigInt.from(2500000000),
        ),
      ],
    );
    when(() => sdk.ledger).thenReturn(ledger);
    when(() => ledger.getAccountInfoByAddress(any())).thenAnswer(
      (Invocation invocation) async {
        final String address =
            (invocation.positionalArguments.single as Address).toString();
        reads.add(address);
        if (address == second) return secondReply.future;
        expectSync(address, first);
        return balances.state.data![first]!;
      },
    );
    final MultipleBalanceBloc source = MultipleBalanceBloc(zenon: sdk);
    addTearDown(() async {
      if (!secondReply.isCompleted) secondReply.complete(derived);
      source.cancelStreamSubscription();
      await source.close();
    });
    source.add(MultipleBalanceFetch(addresses: <String>[first]));
    await source.stream.firstWhere((MultipleBalanceState state) =>
        state.status == MultipleBalanceStatus.success);
    expect(source.state.data!.keys, <String>[first]);
    kDefaultAddressList = <String?>[first, second];
    kSelectedAddress = second;
    kAddressLabelMap[second] = 'Address 2';
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final VoidCallback restoreErrors =
        _observeFrameworkErrors(includeKind: true);
    final VoidCallback restoreReporter = _observeTestExceptions();
    try {
      await tester.pumpWidget(host(balanceSource: source));
      await tester.pump();
      expect(reads, <String>[first, first, second]);
      expect(source.state.status, MultipleBalanceStatus.loading);
      expect(find.byType(SendPopulated), findsNothing);
      secondReply.complete(derived);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final StatefulElement form =
          tester.element(find.byType(SendPopulated)) as StatefulElement;
      expect(
        (form.widget as SendPopulated).balances.keys,
        <String>[first, second],
      );
      expect((form.state as SendFormOrigin).draftSender, second);
      await tester.tap(find.byKey(const Key('transfer_sender')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byWidgetPredicate((Widget widget) =>
            widget is PopupMenuItem<String> && widget.value == second),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      restoreReporter();
      restoreErrors();
    }
  });

  testWidgets('embedded Transfer waits for every current member balance',
      (WidgetTester tester) async {
    final String first = kSelectedAddress!;
    final String second = Address(
      'z', <int>[0, 2, ...List<int>.filled(18, 3)],
    ).toString();
    kDefaultAddressList = <String?>[first, second];
    kSelectedAddress = second;
    kAddressLabelMap[second] = 'Address 2';
    await show(tester);
    expect(find.byType(SendPopulated), findsNothing);
    expect(find.byType(SendLoading), findsOneWidget);
    expect(draft.state.isEmpty, isTrue);
    final MultipleBalanceFetch request =
        verify(() => balances.add(captureAny())).captured.single
            as MultipleBalanceFetch;
    expect(request.addresses, <String>[first, second]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Transfer retains a complete cached balance without another fetch',
      (WidgetTester tester) async {
    await show(tester);
    verifyNever(() => balances.add(any()));
    expect(find.byType(SendPopulated), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('Receive header owns its choices across layouts $light',
        (WidgetTester tester) async {
      await show(tester, light: light);
      final String selected = addSecondAddress();
      await tester.pump();
      controller.value = TransferMode.receive;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final State<StatefulWidget> owner = tester.state(
        find.byType(ReceivePopulated),
      );
      final Finder picker = find.byKey(const Key('transfer_receiver'));
      expect(picker, findsOneWidget);
      expect(find.byKey(const Key('receive_address_picker')), findsNothing);
      final ModalRoute<dynamic> route = ModalRoute.of(tester.element(picker))!;
      await tester.tap(picker);
      await tester.pump();
      expect(route.isCurrent, isTrue);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Address 2'));
      await tester.pump();
      await tester.pump();
      expect(kSelectedAddress, selected);
      expect(
        tester.widget<SelectableText>(find.byKey(const Key('receive_address')))
            .data,
        selected,
      );
      controller.value = TransferMode.zap;
      await tester.pump();
      expect(picker, findsNothing);
      controller.value = TransferMode.receive;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tester.state(find.byType(ReceivePopulated)), same(owner));
      for (final double width in <double>[1280, 480]) {
        for (final TextDirection direction in TextDirection.values) {
          tester.view.physicalSize = Size(width, 900);
          await tester.pumpWidget(host(
            light: light,
            direction: direction,
            scale: width < 520 ? 1.5 : 1,
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(picker, findsOneWidget);
          expect(tester.getSize(picker).width, lessThan(width));
          expect(
            tester.widget<SelectableText>(
              find.byKey(const Key('receive_address')),
            ).data,
            selected,
          );
          expect(tester.state(find.byType(ReceivePopulated)), same(owner));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.tap(picker);
      await tester.pump();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Address 1'));
      await tester.pump();
      await tester.pump();
      expect(kSelectedAddress, selected);
      expect(
        tester.widget<SelectableText>(find.byKey(const Key('receive_address')))
            .data,
        emptyAddress.toString(),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('actual Transfer header selects its typed owner $light',
        (WidgetTester tester) async {
      await show(tester, light: light);
      final String owner = addSecondAddress();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final StatefulElement form =
          tester.element(find.byType(SendPopulated)) as StatefulElement;
      final SendFormOrigin original = form.state as SendFormOrigin;
      expect(original.draftSender, isNot(owner));
      bool current = true;
      addTearDown(() async {
        current = false;
        await tester.pump(const Duration(milliseconds: 40));
      });
      void requireCurrent() {
        if (!current || !form.mounted ||
            !identical(form.state, original) || kSelectedAddress != owner ||
            !kDefaultAddressList.contains(owner)) {
          throw StateError('The original header owner changed');
        }
      }
      final HarnessAgent agent = HarnessAgent.forTest();
      await _drive(tester, agent.selectLabSenderForTest(owner, requireCurrent));
      expect(draft.state.fromAddress, owner);
      expect(original.draftSender, owner);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an open actual sender menu retains its original choices',
      (WidgetTester tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('transfer_sender')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final List<Widget> original = find.byType(PopupMenuItem<String>)
        .evaluate().map((Element item) => item.widget).toList();
    expect(original, hasLength(1));
    final String owner = addSecondAddress();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final List<Widget> current = find.byType(PopupMenuItem<String>)
        .evaluate().map((Element item) => item.widget).toList();
    expect(current, original);
    expect(current.where((Widget item) =>
      (item as PopupMenuItem<String>).value == owner), isEmpty);
    final SendPopulated form = tester.widget<SendPopulated>(
      find.byType(SendPopulated),
    );
    expect(form.balances.containsKey(owner), isTrue);
    final ModalRoute<dynamic> route = ModalRoute.of(
      tester.element(find.byType(PopupMenuItem<String>).first),
    )!;
    final Animation<double> animation = route.animation!;
    bool detached = false;
    unawaited(route.completed.then<void>((_) { detached = true; }));
    expect(route.isCurrent, isTrue);
    expect(animation.isCompleted, isTrue);
    final List<Element> barriers = find.byType(ModalBarrier).evaluate()
        .where((Element item) => (item.widget as ModalBarrier).dismissible)
        .toList();
    expect(barriers, hasLength(1));
    final RenderObject barrier = barriers.single.renderObject!;
    final Size size = tester.view.physicalSize / tester.view.devicePixelRatio;
    Offset? outside;
    for (final Offset point in <Offset>[
      const Offset(8, 8), Offset(size.width - 8, 8),
      Offset(8, size.height - 8), Offset(size.width - 8, size.height - 8),
    ]) {
      final bool hitsBarrier = tester.hitTestOnBinding(point).path.any(
          (HitTestEntry<HitTestTarget> entry) {
        final Object target = entry.target;
        if (target is! RenderObject) return false;
        for (RenderObject? parent = target; parent != null;
            parent = parent.parent) {
          if (identical(parent, barrier)) return true;
        }
        return false;
      });
      if (hitsBarrier) {
        outside = point;
        break;
      }
    }
    expect(outside, isNotNull, reason: 'The original barrier must be hit');
    await tester.tapAt(outside!);
    await tester.pump();
    expect(animation.status, AnimationStatus.reverse);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump();
    expect(animation.isDismissed, isTrue);
    expect(detached, isTrue);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
