import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _Transactions extends MockBloc<SendTransactionEvent, SendTransactionState>
    implements SendTransactionBloc {}

class _Zenon extends Mock implements Zenon {}

class _Embedded extends Mock implements EmbeddedApi {}

class _Stake extends Mock implements StakeApi {}

const Key _amountKey = Key('create_stake_amount_field');
const Key _submitKey = Key('create_stake_submit_button');

AccountInfo _account(int wholeZnn) => AccountInfo(
  address: emptyAddress.toString(),
  blockCount: 1,
  balanceInfoList: <BalanceInfoListItem>[
    BalanceInfoListItem(
      token: kZnnCoin,
      balance: BigInt.from(wholeZnn) * BigInt.from(10).pow(kZnnCoin.decimals),
    ),
  ],
);

MultipleBalanceState _balanceState(
  int amount, {
  MultipleBalanceStatus status = MultipleBalanceStatus.success,
}) => MultipleBalanceState(
  status: status,
  data: <String, AccountInfo>{emptyAddress.toString(): _account(amount)},
);

void main() {
  late _Balances balances;
  late _Transactions transactions;
  late StreamController<MultipleBalanceState> balanceStates;
  late StreamController<SendTransactionState> transactionStates;
  late _Stake stake;
  late Zenon? previousZenon;
  late String? previousAddress;
  late SelectedAddressNotifier selection;

  setUpAll(() {
    registerFallbackValue(const MultipleBalanceFetch(addresses: <String>[]));
    registerFallbackValue(
      SendTransactionInitiateFromBlock(
        block: AccountBlockTemplate(blockType: 1),
        fromAddress: emptyAddress.toString(),
        reasonForGeneratingPlasma: '',
      ),
    );
  });

  setUp(() {
    previousAddress = kSelectedAddress;
    previousZenon = app.zenon;
    kSelectedAddress = emptyAddress.toString();
    selection = SelectedAddressNotifier();
    balances = _Balances();
    transactions = _Transactions();
    balanceStates = StreamController<MultipleBalanceState>.broadcast(
      sync: true,
    );
    transactionStates = StreamController<SendTransactionState>.broadcast(
      sync: true,
    );
    whenListen(
      balances,
      balanceStates.stream,
      initialState: _balanceState(1000),
    );
    whenListen(
      transactions,
      transactionStates.stream,
      initialState: const SendTransactionState(),
    );
    app.sl.registerSingleton<MultipleBalanceBloc>(balances);

    final _Zenon zenon = _Zenon();
    final _Embedded embedded = _Embedded();
    stake = _Stake();
    when(() => zenon.embedded).thenReturn(embedded);
    when(() => embedded.stake).thenReturn(stake);
    app.zenon = zenon;
  });

  tearDown(() async {
    await balanceStates.close();
    await transactionStates.close();
    await app.sl.unregister<MultipleBalanceBloc>();
    selection.dispose();
    kSelectedAddress = previousAddress;
    app.zenon = previousZenon;
  });

  Widget host({
    bool light = false,
    bool rtl = false,
    double width = 1180,
    DisclosureController? disclosure,
    VoidCallback? onCreated,
    ValueChanged<AccountBlockTemplate>? onPublished,
  }) {
    final Widget form = CreateStakeCard(
      framed: false,
      createTransactionBloc: () => transactions,
      onStakeCreated: onCreated ?? () {},
      onStakePublished: onPublished,
    );
    return MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SelectedAddressNotifier>.value(
            value: selection,
          ),
          BlocProvider<MultipleBalanceBloc>.value(value: balances),
        ],
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: width,
                child: disclosure == null
                    ? form
                    : Disclosure.bare(
                        controller: disclosure,
                        keepAlive: true,
                        child: form,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(child);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> chooseSixMonths(WidgetTester tester) async {
    await tester.tap(find.byKey(Segment.keyOf('create_stake_months', 6)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('presets and exact amount validation retain the chain limits', (
    WidgetTester tester,
  ) async {
    await show(tester, host());
    final Segment<int> segment = tester.widget<Segment<int>>(
      find.byType(Segment<int>),
    );
    expect(segment.items.map((SegmentItem<int> item) => item.value), <int>[
      1,
      2,
      3,
      6,
      9,
      12,
    ]);
    expect(
      tester.widget<PrimaryPill>(find.byKey(_submitKey)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('create_stake_unlock_date')))
          .data,
      isEmpty,
    );

    await chooseSixMonths(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('create_stake_unlock_date')))
          .data,
      DateFormat(
        'd MMM yyyy',
        'en',
      ).format(DateTime.now().add(Duration(seconds: 6 * stakeTimeUnitSec))),
    );
    await tester.enterText(find.byKey(_amountKey), '1001');
    await tester.pump();
    expect(
      tester.widget<PrimaryPill>(find.byKey(_submitKey)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byKey(_amountKey)).decoration!.errorText,
      isNotNull,
    );
    await tester.enterText(find.byKey(_amountKey), '0.1');
    await tester.pump();
    expect(
      tester.widget<PrimaryPill>(find.byKey(_submitKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('create_stake_max_button')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(_amountKey)).controller!.text,
      _account(
        1000,
      ).getBalance(kZnnCoin.tokenStandard).addDecimals(kZnnCoin.decimals),
    );
    expect(find.text('Stake 1,000 ZNN'), findsOneWidget);
    expect(
      tester.widget<PrimaryPill>(find.byKey(_submitKey)).onPressed,
      isNotNull,
    );
    verifyNever(() => transactions.add(any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the same draft survives disclosure close and balance refresh', (
    WidgetTester tester,
  ) async {
    final DisclosureController disclosure = DisclosureController();
    addTearDown(disclosure.dispose);
    await show(tester, host(disclosure: disclosure));
    disclosure.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await chooseSixMonths(tester);
    await tester.enterText(find.byKey(_amountKey), '300');
    await tester.pump();
    final TextEditingController controller = tester
        .widget<TextField>(find.byKey(_amountKey))
        .controller!;
    disclosure.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    disclosure.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<TextField>(find.byKey(_amountKey)).controller,
      same(controller),
    );
    expect(controller.text, '300');
    expect(tester.widget<Segment<int>>(find.byType(Segment<int>)).selected, 6);

    balanceStates.add(
      _balanceState(1000, status: MultipleBalanceStatus.loading),
    );
    await tester.pump();
    balanceStates.add(_balanceState(500));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(_amountKey)).controller,
      same(controller),
    );
    expect(controller.text, '300');
    expect(find.text('of 500 ZNN'), findsOneWidget);
    verifyNever(() => transactions.add(any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keyboard resubmission cannot enqueue a second stake', (
    WidgetTester tester,
  ) async {
    int created = 0;
    final BigInt amount =
        BigInt.from(300) * BigInt.from(10).pow(kZnnCoin.decimals);
    final AccountBlockTemplate block = AccountBlockTemplate(blockType: 1);
    when(() => stake.stake(6 * stakeTimeUnitSec, amount)).thenReturn(block);
    final List<AccountBlockTemplate> observed = <AccountBlockTemplate>[];
    await show(tester, host(onCreated: () => created++,
      onPublished: (AccountBlockTemplate original) {
        observed.add(original);
        throw StateError('Read observer refused');
      }));
    await chooseSixMonths(tester);
    await tester.enterText(find.byKey(_amountKey), '300');
    await tester.pump();
    final ValueChanged<String> submit = tester
        .widget<TextField>(find.byKey(_amountKey))
        .onSubmitted!;
    submit('300');
    submit('300');
    await tester.pump();
    verify(() => stake.stake(6 * stakeTimeUnitSec, amount)).called(1);
    final List<dynamic> sent = verify(
      () => transactions.add(captureAny()),
    ).captured;
    expect(sent, hasLength(1));
    final SendTransactionInitiateFromBlock event =
        sent.single as SendTransactionInitiateFromBlock;
    expect(event.block, same(block));
    expect(event.fromAddress, emptyAddress.toString());
    expect(
      tester.widget<PrimaryPill>(find.byKey(_submitKey)).onPressed,
      isNull,
    );

    transactionStates.add(
      const SendTransactionState(status: SendTransactionStatus.loading),
    );
    await tester.pump();
    submit('300');
    verifyNever(() => transactions.add(any()));
    transactionStates.add(
      SendTransactionState(status: SendTransactionStatus.success, data: block),
    );
    await tester.pump();
    expect(created, 1);
    expect(observed, hasLength(1));
    expect(observed.single, same(block));
    expect(
      tester.widget<TextField>(find.byKey(_amountKey)).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<Segment<int>>(find.byType(Segment<int>)).selected,
      isNull,
    );
    verify(() => balances.add(any())).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'compact form fits the ${light ? 'light' : 'dark'} RTL layout',
      (
        WidgetTester tester,
      ) async {
        await show(tester, host(light: light, rtl: true, width: 980));
        await chooseSixMonths(tester);
        await tester.enterText(find.byKey(_amountKey), '300.5');
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byKey(_amountKey)).textDirection,
          TextDirection.ltr,
        );
        expect(find.text('Stake 300.5 ZNN'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
