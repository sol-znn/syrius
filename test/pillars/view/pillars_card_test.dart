import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Pillars
    extends MockBloc<InfiniteListEvent, InfiniteListState<PillarInfo>>
    implements PillarsBloc {}

class _Delegate extends MockBloc<DelegationEvent, DelegationState>
    implements DelegationBloc {}

class _Stats extends MockBloc<FetchEvent, FetchState<DelegationInfo>>
    implements DelegationStatsBloc {}

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _Pillar extends Mock implements PillarInfo {}

class _Delegation extends Mock implements DelegationInfo {}

class _Problem extends Mock implements SyriusException {}

PillarInfo _pillar(
  String name, {
  String weight = '100000000000',
  int produced = 1760,
  int expected = 1762,
}) {
  final _Pillar item = _Pillar();
  when(() => item.name).thenReturn(name);
  when(() => item.ownerAddress).thenReturn(emptyAddress);
  when(() => item.producerAddress).thenReturn(emptyAddress);
  when(() => item.withdrawAddress).thenReturn(emptyAddress);
  when(() => item.weight).thenReturn(BigInt.parse(weight));
  when(() => item.giveMomentumRewardPercentage).thenReturn(0);
  when(() => item.giveDelegateRewardPercentage).thenReturn(100);
  when(() => item.producedMomentums).thenReturn(produced);
  when(() => item.expectedMomentums).thenReturn(expected);
  return item;
}

InfiniteListState<PillarInfo> _loaded(
  List<PillarInfo> items, {
  bool complete = true,
}) => InfiniteListState<PillarInfo>(
  status: InfiniteListStatus.success,
  data: items,
  hasReachedMax: complete,
);

Finder _arrival(String name) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is ListEntranceItem && widget.key == ValueKey<String>(name),
);

double _opacity(WidgetTester tester, String name) => tester
    .widget<Opacity>(
      find.descendant(of: _arrival(name), matching: find.byType(Opacity)).first,
    )
    .opacity;

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late _Pillars pillars;
  late _Delegate delegate;
  late _Stats stats;
  late _Balances balances;
  late StreamController<InfiniteListState<PillarInfo>> pillarStates;
  late StreamController<DelegationState> delegateStates;
  late String? previousAddress;

  setUpAll(() {
    registerFallbackValue(const InfiniteListMoreRequested());
    registerFallbackValue(const MultipleBalanceFetch(addresses: <String>[]));
    registerFallbackValue(FetchRequestData(address: emptyAddress));
    registerFallbackValue(
      DelegationRequested(address: emptyAddress, pillarName: 'placeholder'),
    );
  });

  setUp(() {
    previousAddress = kSelectedAddress;
    kSelectedAddress = emptyAddress.toString();
    pillars = _Pillars();
    delegate = _Delegate();
    stats = _Stats();
    balances = _Balances();
    pillarStates = StreamController<InfiniteListState<PillarInfo>>.broadcast(
      sync: true,
    );
    delegateStates = StreamController<DelegationState>.broadcast(sync: true);
    whenListen(
      delegate,
      delegateStates.stream,
      initialState: const DelegationInitial(),
    );
    whenListen(
      stats,
      const Stream<FetchState<DelegationInfo>>.empty(),
      initialState: const FetchInitial<DelegationInfo>(),
    );
    whenListen(
      balances,
      const Stream<MultipleBalanceState>.empty(),
      initialState: MultipleBalanceState(
        status: MultipleBalanceStatus.success,
        data: <String, AccountInfo>{
          emptyAddress.toString(): AccountInfo(
            address: emptyAddress.toString(),
            blockCount: 1,
            balanceInfoList: <BalanceInfoListItem>[
              BalanceInfoListItem(
                token: kZnnCoin,
                balance: kMinDelegationAmount,
              ),
            ],
          ),
        },
      ),
    );
  });

  tearDown(() async {
    await pillarStates.close();
    await delegateStates.close();
    await pillars.close();
    await delegate.close();
    await stats.close();
    await balances.close();
    kSelectedAddress = previousAddress;
    AppLottie.debugClear();
  });

  Widget host({
    ThemeData? theme,
    bool light = false,
    bool rtl = false,
    bool blocked = false,
    double textScale = 1,
  }) => MaterialApp(
    theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<PillarsBloc>.value(value: pillars),
        BlocProvider<DelegationStatsBloc>.value(value: stats),
        BlocProvider<MultipleBalanceBloc>.value(value: balances),
      ],
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: PillarsCard(
            delegationBloc: delegate,
            delegationBlocked: blocked,
          ),
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester,
    List<PillarInfo> items, {
    bool complete = true,
    ThemeData? theme,
    bool light = false,
    bool rtl = false,
    bool blocked = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    whenListen(
      pillars,
      pillarStates.stream,
      initialState: _loaded(items, complete: complete),
    );
    await tester.pumpWidget(
      host(theme: theme, light: light, rtl: rtl, blocked: blocked),
    );
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets('five data columns and exact details, light=$light', (
      WidgetTester tester,
    ) async {
      await show(tester, <PillarInfo>[
        _pillar('alpha', weight: '9007199254740993'),
      ], light: light);
      await _frames(tester);
      for (final String heading in <String>[
        'NAME',
        'WEIGHT',
        'SHARES',
        'UPTIME',
        'APR EST.',
      ]) {
        expect(find.text(heading), findsOneWidget);
      }
      expect(find.text('0% / 100%'), findsOneWidget);
      expect(find.text('99.9%'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Tooltip && widget.message == '90,071,992.54740993 ZNN',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pillar_alpha_row')));
      await _frames(tester);
      expect(find.byKey(const Key('pillar_alpha_detail')), findsOneWidget);
      expect(find.text('1,760 of 1,762 expected'), findsOneWidget);
      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'Delegate keeps 26 px and the original pending guard '
      'in compact density, $light',
      (WidgetTester tester) async {
        final ThemeData theme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
              visualDensity: VisualDensity.compact,
            );
        await show(tester, <PillarInfo>[
          _pillar('alpha'),
          _pillar('beta'),
        ], theme: theme);
        await _frames(tester);
        final Finder alpha = find.byKey(const Key('pillar_alpha_delegate'));
        final Finder beta = find.byKey(const Key('pillar_beta_delegate'));
        expect(
          Theme.of(tester.element(alpha)).visualDensity,
          VisualDensity.compact,
        );
        expect(tester.getSize(alpha).height, 26);
        expect(tester.getSize(beta).height, 26);
        final VoidCallback original = tester
            .widget<OutlinedButton>(alpha)
            .onPressed!;
        await tester.tap(alpha);
        await tester.pump();
        expect(tester.getSize(alpha).height, 26);
        expect(tester.getSize(beta).height, 26);
        expect(tester.widget<OutlinedButton>(alpha).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(beta).onPressed, isNull);
        expect(
          find.descendant(
            of: alpha,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        original();
        verify(
          () => delegate.add(
            DelegationRequested(address: emptyAddress, pillarName: 'alpha'),
          ),
        ).called(1);
        expect(find.byKey(const Key('pillar_alpha_detail')), findsNothing);

        delegateStates.add(DelegationFailure(exception: _Problem()));
        await tester.pump();
        expect(tester.widget<OutlinedButton>(alpha).onPressed, isNotNull);
        await tester.pumpWidget(host(theme: theme, textScale: 1.75));
        await _frames(tester);
        expect(tester.getSize(alpha).height, greaterThan(26));
        expect(tester.getSize(beta).height, greaterThan(26));
        expect(tester.widget<OutlinedButton>(alpha).onPressed, isNotNull);
        verifyNever(() => stats.add(any()));
        verifyNever(() => delegate.close());
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('an empty filter still loads the next original page once', (
    WidgetTester tester,
  ) async {
    final PillarInfo alpha = _pillar('alpha');
    await show(tester, <PillarInfo>[alpha], complete: false);
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('pillars_search')), 'beta');
    await _frames(tester);
    expect(find.text('No matches'), findsOneWidget);
    final Finder more = find.byKey(const Key('pillars_load_more'));
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(more).onPressed, isNull);
    verify(() => pillars.add(const InfiniteListMoreRequested())).called(1);
    pillarStates.add(_loaded(<PillarInfo>[alpha, _pillar('beta')]));
    await _frames(tester);
    expect(find.byKey(const Key('pillar_beta_row')), findsOneWidget);
    expect(more, findsNothing);
    expect(find.text('No matches'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('filtering, sorting and refresh retain arrival and detail ids', (
    WidgetTester tester,
  ) async {
    final List<PillarInfo> source = <PillarInfo>[
      _pillar('alpha', weight: '200000000000', produced: 1, expected: 2),
      _pillar('beta', produced: 2, expected: 2),
    ];
    await show(tester, source);
    await _frames(tester);
    await tester.tap(find.byKey(const Key('pillar_alpha_row')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('pillars_sort')));
    await _frames(tester);
    final PopupMenuItem<dynamic> apr = tester.widget<PopupMenuItem<dynamic>>(
      find.byKey(const Key('pillars_sort_apr')),
    );
    expect(apr.enabled, isFalse);
    await tester.tap(find.byKey(const Key('pillars_sort_production')));
    await _frames(tester);
    expect(
      tester.getTopLeft(find.byKey(const Key('pillar_beta_row'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('pillar_alpha_row'))).dy),
    );
    expect(_opacity(tester, 'alpha'), 1);
    expect(find.byKey(const Key('pillar_alpha_detail')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pillars_search')), 'beta');
    await _frames(tester);
    pillarStates.add(_loaded(<PillarInfo>[...source, _pillar('gamma')]));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('pillars_search')), '');
    await tester.pump();
    expect(_opacity(tester, 'alpha'), 1);
    expect(_opacity(tester, 'gamma'), 1);
    expect(find.byKey(const Key('pillar_alpha_detail')), findsOneWidget);
    pillarStates.add(const InfiniteListState<PillarInfo>.initial());
    await _frames(tester);
    pillarStates.add(_loaded(source));
    await tester.pump();
    expect(_opacity(tester, 'alpha'), 1);
    expect(find.byKey(const Key('pillar_alpha_detail')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disabled delegation does not toggle row details', (
    WidgetTester tester,
  ) async {
    final _Delegation current = _Delegation();
    when(() => current.name).thenReturn('alpha');
    when(() => stats.state).thenReturn(
      FetchPopulated<DelegationInfo>(data: current),
    );
    await show(tester, <PillarInfo>[_pillar('alpha')], blocked: true);
    await _frames(tester);
    await tester.tap(find.byKey(const Key('pillar_alpha_delegate')));
    await _frames(tester);
    expect(find.byKey(const Key('pillar_alpha_detail')), findsNothing);
    verifyNever(() => delegate.add(any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a filtered pending action retains the shared owner and hold', (
    WidgetTester tester,
  ) async {
    await show(tester, <PillarInfo>[_pillar('alpha'), _pillar('beta')]);
    await _frames(tester);
    await tester.tap(find.byKey(const Key('pillar_alpha_delegate')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pillar_beta_delegate')));
    await tester.enterText(find.byKey(const Key('pillars_search')), 'beta');
    await _frames(tester);
    final OutlinedButton beta = tester.widget<OutlinedButton>(
      find.byKey(const Key('pillar_beta_delegate')),
    );
    expect(beta.onPressed, isNull);
    verify(
      () => delegate.add(
        DelegationRequested(address: emptyAddress, pillarName: 'alpha'),
      ),
    ).called(1);
    delegateStates.add(DelegationFailure(exception: _Problem()));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('pillar_beta_delegate')))
          .onPressed,
      isNotNull,
    );
    verifyNever(() => stats.add(any()));
    await tester.pumpWidget(const SizedBox.shrink());
    verifyNever(() => delegate.close());
    expect(tester.takeException(), isNull);
  });

  testWidgets('data remains left to right inside a mirrored list', (
    WidgetTester tester,
  ) async {
    await show(tester, <PillarInfo>[_pillar('alpha')], rtl: true);
    await _frames(tester);
    await tester.tap(find.byKey(const Key('pillar_alpha_row')));
    await _frames(tester);
    final Text weight = tester.widget<Text>(find.text('1K ZNN'));
    final Text momentums = tester.widget<Text>(
      find.text('1,760 of 1,762 expected'),
    );
    expect(weight.textDirection, TextDirection.ltr);
    expect(momentums.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
