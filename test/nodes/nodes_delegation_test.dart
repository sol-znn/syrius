import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_panels.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Delegate extends MockBloc<DelegationEvent, DelegationState>
    implements DelegationBloc {}

class _Undelegate extends MockBloc<UndelegateEvent, UndelegateState>
    implements UndelegateBloc {}

class _Pillars
    extends MockBloc<InfiniteListEvent, InfiniteListState<PillarInfo>>
    implements PillarsBloc {}

class _Stats extends MockBloc<FetchEvent, FetchState<DelegationInfo>>
    implements DelegationStatsBloc {}

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _Info extends Mock implements DelegationInfo {}

class _Problem extends Mock implements SyriusException {
  @override
  String toString() => 'Network error. Try again.';
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late _Delegate delegate;
  late _Undelegate undelegate;
  late _Pillars pillars;
  late _Stats stats;
  late _Balances balances;
  late StreamController<DelegationState> delegateStates;
  late StreamController<UndelegateState> undelegateStates;
  late BuildContext actionContext;
  late String? previousAddress;

  setUpAll(() {
    registerFallbackValue(FetchRequestData(address: emptyAddress));
    registerFallbackValue(UndelegateRequested(address: emptyAddress));
  });

  setUp(() {
    previousAddress = kSelectedAddress;
    kSelectedAddress = emptyAddress.toString();
    delegate = _Delegate();
    undelegate = _Undelegate();
    pillars = _Pillars();
    stats = _Stats();
    balances = _Balances();
    delegateStates = StreamController<DelegationState>.broadcast();
    undelegateStates = StreamController<UndelegateState>.broadcast();
    whenListen(
      delegate,
      delegateStates.stream,
      initialState: const DelegationInitial(),
    );
    whenListen(
      undelegate,
      undelegateStates.stream,
      initialState: const UndelegateInitial(),
    );
    whenListen(
      pillars,
      const Stream<InfiniteListState<PillarInfo>>.empty(),
      initialState: InfiniteListState<PillarInfo>(
        status: InfiniteListStatus.failure,
        error: _Problem(),
      ),
    );
    final _Info info = _Info();
    when(() => info.name).thenReturn('first');
    whenListen(
      stats,
      const Stream<FetchState<DelegationInfo>>.empty(),
      initialState: FetchPopulated<DelegationInfo>(data: info),
    );
    whenListen(
      balances,
      const Stream<MultipleBalanceState>.empty(),
      initialState: const MultipleBalanceState(),
    );
  });

  tearDown(() async {
    kSelectedAddress = previousAddress;
    await delegateStates.close();
    await undelegateStates.close();
    await delegate.close();
    await undelegate.close();
    await pillars.close();
    await stats.close();
    await balances.close();
  });

  Widget host() => MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: const <Locale>[Locale('en')],
    home: Scaffold(
      body: MultiBlocProvider(
        providers: <SingleChildWidget>[
          BlocProvider<PillarsBloc>.value(value: pillars),
          BlocProvider<DelegationStatsBloc>.value(value: stats),
          BlocProvider<MultipleBalanceBloc>.value(value: balances),
        ],
        child: NodesDelegationScope(
          delegationBloc: delegate,
          undelegateBloc: undelegate,
          child: Builder(
            builder: (BuildContext context) {
              actionContext = context;
              return Column(
                children: <Widget>[
                  const Expanded(child: NodesDelegationList()),
                  TextButton(
                    onPressed: () => showDelegationChooser(context),
                    child: const Text('Choose'),
                  ),
                  TextButton(
                    onPressed: () => requestNodesUndelegation(
                      context,
                      pillarName: 'first',
                    ),
                    child: const Text('Remove delegation'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  for (final bool removing in <bool>[false, true]) {
    testWidgets(
      'closing the chooser preserves both action holds, removing=$removing',
      (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(host());
        await tester.tap(find.text('Choose'));
        await _frames(tester);
        expect(find.byType(PillarsCard), findsNWidgets(2));
        for (final PillarsCard card in tester.widgetList<PillarsCard>(
          find.byType(PillarsCard),
        )) {
          expect(card.delegationBloc, same(delegate));
        }
        if (removing) {
          undelegateStates.add(const UndelegateLoading());
        } else {
          delegateStates.add(const DelegationLoading());
        }
        await tester.pump();
        expect(
          tester
              .widgetList<PillarsCard>(find.byType(PillarsCard))
              .every((PillarsCard card) => card.delegationBlocked),
          isTrue,
        );
        await tester.tap(find.byKey(const Key('nodes_panel_close')));
        await _frames(tester);
        expect(find.byType(PillarsCard), findsOneWidget);
        expect(
          tester
              .widget<PillarsCard>(find.byType(PillarsCard))
              .delegationBlocked,
          isTrue,
        );
        verifyNever(() => delegate.close());
        verifyNever(() => undelegate.close());

        await tester.tap(find.text('Remove delegation'));
        await _frames(tester);
        expect(find.byType(Dialog), findsNothing);
        verifyNever(() => undelegate.add(any()));
        await showDelegationChooser(actionContext);
        expect(find.byType(Dialog), findsNothing);

        if (removing) {
          undelegateStates.add(const UndelegateDone());
        } else {
          delegateStates.add(const DelegationDone());
        }
        await tester.pump();
        expect(
          tester
              .widget<PillarsCard>(find.byType(PillarsCard))
              .delegationBlocked,
          isFalse,
        );
        verify(() => stats.add(any())).called(1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('confirmed undelegation adds only the existing shared event', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Remove delegation'));
    await _frames(tester);
    expect(find.text('Undelegate from first?'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await _frames(tester);
    verify(
      () => undelegate.add(UndelegateRequested(address: emptyAddress)),
    ).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a changed pillar cannot inherit an open confirmation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Remove delegation'));
    await _frames(tester);
    final _Info changed = _Info();
    when(() => changed.name).thenReturn('second');
    when(
      () => stats.state,
    ).thenReturn(FetchPopulated<DelegationInfo>(data: changed));
    await tester.tap(find.text('Yes'));
    await _frames(tester);
    verifyNever(() => undelegate.add(any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a pending delegate blocks an already-open undelegate confirmation',
    (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('Remove delegation'));
      await _frames(tester);
      delegateStates.add(const DelegationLoading());
      await tester.pump();
      await tester.tap(find.text('Yes'));
      await _frames(tester);
      verifyNever(() => undelegate.add(any()));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
