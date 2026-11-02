import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_panels.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation_stats/view/delegation_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/loading_button.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Reward extends Mock implements UncollectedReward {}

class _Transactions extends MockBloc<SendTransactionEvent, SendTransactionState>
    implements SendTransactionBloc {}

class _PillarHistory extends MockBloc<FetchEvent, FetchState<RewardHistoryList>>
    implements PillarRewardsHistoryBloc {}

class _SentinelHistory
    extends MockBloc<FetchEvent, FetchState<RewardHistoryList>>
    implements SentinelRewardsHistoryBloc {}

class _Problem extends Mock implements SyriusException {
  @override
  String toString() => 'Network error. Try again.';
}

class _Prices extends PriceFeed {
  _Prices({required PriceRequest request}) : super(request: request);

  bool get subscribed => hasListeners;
}

FetchPopulated<UncollectedReward> _due(String znn, [String qsr = '0']) {
  final _Reward reward = _Reward();
  when(() => reward.znnAmount).thenReturn(BigInt.parse(znn));
  when(() => reward.qsrAmount).thenReturn(BigInt.parse(qsr));
  return FetchPopulated<UncollectedReward>(data: reward);
}

Widget _host(Widget child, {bool light = false, bool rtl = false}) =>
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
      locale: rtl ? const Locale('ar') : const Locale('en'),
      home: Scaffold(body: child),
    );

Widget _strip(
  FetchState<UncollectedReward> state,
  PriceFeed feed, {
  bool active = true,
}) => TickerMode(
  enabled: active,
  child: ListenableBuilder(
    listenable: BalanceVisibility.instance,
    builder: (BuildContext context, Widget? child) => PageStrip(
      figures: <StripFigure>[
        nodesRewardsFigure(context, state: state, priceFeed: feed),
      ],
    ),
  ),
);

void main() {
  late _Prices feed;
  late int asked;

  setUp(() {
    sharedPrefsService = null;
    BalanceVisibility.debugReset();
    asked = 0;
    feed = _Prices(
      request: (Uri uri) async {
        asked++;
        return '{"zenon-2":{"usd":0.62},"quasar":{"usd":0.031}}';
      },
    );
  });

  tearDown(() {
    feed.dispose();
    BalanceVisibility.debugReset();
    sharedPrefsService = null;
  });

  test('only a known, nonzero reward enables Collect', () {
    expect(hasNodesRewards(const FetchInitial<UncollectedReward>()), isFalse);
    expect(
      hasNodesRewards(
        FetchFailure<UncollectedReward>(exception: FailureException()),
      ),
      isFalse,
    );
    expect(hasNodesRewards(_due('0')), isFalse);
    expect(hasNodesRewards(_due('1')), isTrue);
    expect(hasNodesRewards(_due('0', '1')), isTrue);
  });

  testWidgets('ZNN rewards show an exact amount and a single-coin price', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_strip(_due('321400000'), feed)));
    await tester.pump();
    expect(find.text('3.214 ZNN', findRichText: true), findsOneWidget);
    expect(find.text(r'$1.99'), findsOneWidget);
    expect(asked, 1);
    expect(find.textContaining('3.2140', findRichText: true), findsNothing);
  });

  testWidgets('both reward coins enter one dollar sum', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_strip(_due('321400000', '40000000'), feed)));
    await tester.pump();
    expect(find.text('3.214 ZNN', findRichText: true), findsOneWidget);
    expect(find.text('0.4 QSR', findRichText: true), findsOneWidget);
    expect(find.text(r'≈ $2.01'), findsOneWidget);
    expect(asked, 1);
  });

  testWidgets('large base-unit amounts are not rounded through a double', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(_strip(_due('900719925474099300000001'), feed)),
    );
    await tester.pump();
    expect(
      find.text('9,007,199,254,740,993.00000001 ZNN', findRichText: true),
      findsOneWidget,
    );
    expect(find.text(r'$5,584,463,537,939,415.66'), findsOneWidget);
  });

  testWidgets('unknown rewards stay a skeleton and do not start prices', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(_strip(const FetchInitial<UncollectedReward>(), feed)),
    );
    await tester.pump();
    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.byType(DollarText), findsNothing);
    expect(find.text('0 ZNN', findRichText: true), findsNothing);
    expect(asked, 0);
  });

  testWidgets('hidden rewards and their dollars leave no amount semantics', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host(_strip(_due('321400000'), feed)));
      await tester.pump();
      BalanceVisibility.instance.toggle();
      await tester.pump();
      expect(find.text('••••'), findsNWidgets(2));
      expect(find.semantics.byLabel(RegExp(r'3\.214|\$1\.99')), findsNothing);
      BalanceVisibility.instance.toggle();
      await tester.pump();
      expect(find.text(r'$1.99'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an inactive kept strip unmounts its dollar listener', (
    WidgetTester tester,
  ) async {
    final FetchState<UncollectedReward> due = _due('321400000');
    await tester.pumpWidget(_host(_strip(due, feed)));
    await tester.pump();
    expect(feed.subscribed, isTrue);
    await tester.pumpWidget(_host(_strip(due, feed, active: false)));
    await tester.pump();
    expect(find.byType(DollarText), findsNothing);
    expect(feed.subscribed, isFalse);
    await tester.pump(const Duration(minutes: 2));
    expect(asked, 1);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('rewards stay LTR in either theme, light=$light', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _strip(_due('321400000', '40000000'), feed),
          light: light,
          rtl: true,
        ),
      );
      await tester.pump();
      final BuildContext amount = tester.element(
        find.text('3.214 ZNN', findRichText: true),
      );
      expect(Directionality.of(amount), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('both adapters keep the existing disabled collection button', (
    WidgetTester tester,
  ) async {
    final _Transactions transactions = _Transactions();
    whenListen(
      transactions,
      const Stream<SendTransactionState>.empty(),
      initialState: const SendTransactionState(),
    );
    await tester.pumpWidget(
      _host(
        BlocProvider<SendTransactionBloc>.value(
          value: transactions,
          child: const Column(
            children: <Widget>[
              PillarCollectAction(enabled: false),
              SentinelCollectAction(enabled: false),
            ],
          ),
        ),
      ),
    );
    final Iterable<LoadingButton> buttons = tester.widgetList<LoadingButton>(
      find.byType(LoadingButton),
    );
    expect(buttons, hasLength(2));
    expect(
      buttons.every((LoadingButton button) => button.onPressed == null),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await transactions.close();
  });

  for (final bool sentinel in <bool>[false, true]) {
    testWidgets(
      'unrelated sends leave collection idle across history, '
      'sentinel=$sentinel',
      (
        WidgetTester tester,
      ) async {
        final _Transactions transactions = _Transactions();
        final StreamController<SendTransactionState> states =
            StreamController<SendTransactionState>.broadcast();
        final _PillarHistory pillarHistory = _PillarHistory();
        final _SentinelHistory sentinelHistory = _SentinelHistory();
        final FetchState<RewardHistoryList> failure =
            FetchFailure<RewardHistoryList>(exception: _Problem());
        whenListen(
          transactions,
          states.stream,
          initialState: const SendTransactionState(),
        );
        whenListen(
          pillarHistory,
          const Stream<FetchState<RewardHistoryList>>.empty(),
          initialState: failure,
        );
        whenListen(
          sentinelHistory,
          const Stream<FetchState<RewardHistoryList>>.empty(),
          initialState: failure,
        );
        await tester.pumpWidget(
          _host(
            BlocProvider<SendTransactionBloc>.value(
              value: transactions,
              child: Builder(
                builder: (BuildContext context) => Column(
                  children: <Widget>[
                    if (sentinel)
                      const SentinelCollectAction(enabled: true)
                    else
                      const PillarCollectAction(enabled: true),
                    TextButton(
                      onPressed: () => showNodesPanel(
                        context: context,
                        title: 'Rewards',
                        body: sentinel
                            ? BlocProvider<SentinelRewardsHistoryBloc>.value(
                                value: sentinelHistory,
                                child: const SentinelRewardsChart(),
                              )
                            : BlocProvider<PillarRewardsHistoryBloc>.value(
                                value: pillarHistory,
                                child: const PillarRewardsChart(),
                              ),
                      ),
                      child: const Text('History'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        states.add(
          const SendTransactionState(status: SendTransactionStatus.loading),
        );
        await tester.pump();
        await tester.tap(find.text('History'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Network error. Try again.'), findsOneWidget);
        expect(find.byType(LoadingButton), findsOneWidget);
        expect(find.byType(PillarCollectScope), findsNothing);
        expect(find.byType(SentinelCollectScope), findsNothing);
        await tester.tap(find.byKey(const Key('nodes_panel_close')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          tester.state<LoadingButtonState>(find.byType(LoadingButton)).btnState,
          ButtonState.idle,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await states.close();
        await transactions.close();
        await pillarHistory.close();
        await sentinelHistory.close();
      },
    );
  }
}
