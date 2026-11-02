import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/bloc/latest_transactions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/model/activity_entry.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/view/activity_row.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/view/latest_transactions_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/infinite_list/infinite_list_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/models/card/card_type.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'activity_fixtures.dart';

typedef _History = InfiniteListState<AccountBlock>;

class _Bloc extends MockBloc<InfiniteListEvent, _History>
    implements LatestTransactionsBloc {}

_History _loaded(List<AccountBlock> blocks, {bool hasReachedMax = true}) =>
    InfiniteListState<AccountBlock>(
      status: InfiniteListStatus.success,
      data: blocks,
      hasReachedMax: hasReachedMax,
    );

void main() {
  late _Bloc bloc;
  late StreamController<_History> states;
  late SharedPrefsService? preferences;
  late Map<String, String> labels;
  late String? selected;

  setUp(() {
    preferences = app.sharedPrefsService;
    app.sharedPrefsService = null;
    labels = kAddressLabelMap;
    selected = kSelectedAddress;
    kAddressLabelMap = <String, String>{emptyAddress.toString(): 'Address 2'};
    kSelectedAddress = emptyAddress.toString();
    BalanceVisibility.debugReset();
    bloc = _Bloc();
    states = StreamController<_History>.broadcast(sync: true);
  });

  tearDown(() async {
    await states.close();
    await bloc.close();
    kAddressLabelMap = labels;
    kSelectedAddress = selected;
    app.sharedPrefsService = preferences;
    BalanceVisibility.debugReset();
    AppLottie.debugClear();
  });

  Future<void> mount(
    WidgetTester tester,
    _History state, {
    bool light = false,
    String? address,
    int? chain = 1,
    Map<String, ActivityZapPreview> previews =
        const <String, ActivityZapPreview>{},
  }) async {
    whenListen(bloc, states.stream, initialState: state);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('en')],
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 734,
              height: 300,
              child: BlocProvider<LatestTransactionsBloc>.value(
                value: bloc,
                child: LatestTransactionsCard(
                  type: CardType.latestTransactionsDashboard,
                  address: address,
                  chainId: chain,
                  zapPreviews: previews,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets('compact selected-address ledger in theme $light', (
      WidgetTester tester,
    ) async {
      await mount(
        tester,
        _loaded(<AccountBlock>[activityBlock()]),
        light: light,
      );
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Address 2'), findsOneWidget);
      expect(find.text('All addresses'), findsNothing);
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(find.text('Sender'), findsNothing);
      expect(find.byType(ActivityRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'deduplicates source hashes and suppresses another address history',
    (WidgetTester tester) async {
      final AccountBlock first = activityBlock();
      final AccountBlock foreign = activityBlock(
        address: pillarAddress,
        hash: ''.padLeft(64, 'c'),
      );
      await mount(tester, _loaded(<AccountBlock>[first, first, foreign]));
      expect(find.byType(ActivityRow), findsOneWidget);
      expect(
        tester.widget<ActivityRow>(find.byType(ActivityRow)).entry.hash,
        first.hash.toString(),
      );
    },
  );

  testWidgets(
    'preview metadata attaches only to the exact existing source hash',
    (WidgetTester tester) async {
      final AccountBlock first = activityBlock();
      final AccountBlock other = activityBlock(hash: ''.padLeft(64, 'c'));
      await mount(
        tester,
        _loaded(<AccountBlock>[first, other]),
        previews: <String, ActivityZapPreview>{
          first.hash.toString(): const ActivityZapPreview(),
          ''.padLeft(64, 'd'): const ActivityZapPreview(),
        },
      );
      expect(find.byType(ActivityRow), findsNWidgets(2));
      expect(find.text('Zap'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    },
  );

  testWidgets('an explicit source chain suppresses another chain history', (
    WidgetTester tester,
  ) async {
    await mount(tester, _loaded(<AccountBlock>[activityBlock()]), chain: 321);
    expect(find.byType(ActivityRow), findsNothing);
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('history follows the same shared privacy singleton as Home', (
    WidgetTester tester,
  ) async {
    await mount(tester, _loaded(<AccountBlock>[activityBlock()]));
    expect(find.text(kHiddenAmountDots), findsNothing);
    BalanceVisibility.instance.set(true);
    await tester.pump();
    expect(find.text(kHiddenAmountDots), findsOneWidget);
    expect(find.text('ZNN'), findsOneWidget);
  });

  testWidgets(
    'pagination retains the presented owner if global selection changes',
    (WidgetTester tester) async {
      await mount(
        tester,
        _loaded(<AccountBlock>[activityBlock()], hasReachedMax: false),
        address: emptyAddress.toString(),
      );
      kSelectedAddress = pillarAddress.toString();
      await tester.drag(
        find.byKey(const Key('activity_list')),
        const Offset(0, -200),
      );
      await tester.pump();
      verify(
        () => bloc.add(InfiniteListMoreRequested(address: emptyAddress)),
      ).called(1);
      verifyNever(
        () => bloc.add(InfiniteListMoreRequested(address: pillarAddress)),
      );
    },
  );

  testWidgets(
    'a duplicate-only completed page can request the following page',
    (WidgetTester tester) async {
      final AccountBlock block = activityBlock();
      await mount(tester, _loaded(<AccountBlock>[block], hasReachedMax: false));
      verify(
        () => bloc.add(InfiniteListMoreRequested(address: emptyAddress)),
      ).called(1);
      states.add(_loaded(<AccountBlock>[block, block], hasReachedMax: false));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ActivityRow), findsOneWidget);
      verify(
        () => bloc.add(InfiniteListMoreRequested(address: emptyAddress)),
      ).called(1);
    },
  );

  testWidgets('keyed row state survives a newer block arriving ahead of it', (
    WidgetTester tester,
  ) async {
    final AccountBlock first = activityBlock();
    await mount(tester, _loaded(<AccountBlock>[first]));
    final Finder oldRow = find.byWidgetPredicate(
      (Widget widget) =>
          widget is ActivityRow && widget.entry.hash == first.hash.toString(),
    );
    final State<ActivityRow> before = tester.state<State<ActivityRow>>(oldRow);
    states.add(
      _loaded(<AccountBlock>[
        activityBlock(hash: ''.padLeft(64, 'c')),
        first,
      ]),
    );
    await tester.pump();
    expect(tester.state<State<ActivityRow>>(oldRow), same(before));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading, failure and empty states contain no stale amount rows',
    (WidgetTester tester) async {
      await mount(tester, const InfiniteListState<AccountBlock>.initial());
      expect(find.byType(ActivityRow), findsNothing);
      states.add(
        const InfiniteListState<AccountBlock>(
          status: InfiniteListStatus.failure,
        ),
      );
      await tester.pump();
      expect(find.byType(ActivityRow), findsNothing);
      states.add(_loaded(<AccountBlock>[]));
      await tester.pump();
      expect(find.text('None yet'), findsOneWidget);
      expect(find.byType(ActivityRow), findsNothing);
    },
  );
}
