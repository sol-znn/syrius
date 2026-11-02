import 'package:animations/animations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_project_list_item.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'fixtures.dart';

class _Routes extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Widget host(
  Widget child, {
  bool light = false,
  double scale = 1,
  NavigatorObserver? observer,
}) => MaterialApp(
  theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  ),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  navigatorObservers: <NavigatorObserver>[?observer],
  home: MediaQuery(
    // Motion is deliberately exercised even when the platform flag is set.
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  ),
);

AcceleratorListView listView(
  AcceleratorListPresenter presenter, {
  AcceleratorProjectDetailBuilder? detailBuilder,
  ValueChanged<AcceleratorListSnapshot>? donate,
}) => AcceleratorListView(
  presenter: presenter,
  onRefresh: () {},
  onDonate: donate,
  detailBuilder: detailBuilder,
  onStepperNotificationSeeMorePressed: () {},
);

Future<AcceleratorListPresenter> loadedPresenter() async {
  final AcceleratorListPresenter presenter = AcceleratorListPresenter(
    now: () => DateTime.fromMillisecondsSinceEpoch(listClock * 1000),
  );
  await presenter.load(
    listBinding(
      pages: (int _, int _) async => listPage(<Project>[
        listProject(1, name: 'Sentinel snapshot sync'),
        listProject(
          2,
          name: 'Syrius desktop redesign',
          status: AcceleratorProjectStatus.active,
          phases: <int>[20],
        ),
      ]),
      pillars: () async => <PillarInfo>[listPillar()],
      fund: () async => listAccount(
        entries: <BalanceInfoListItem>[
          listBalance(znnZts, BigInt.zero),
          listBalance(qsrZts, null),
        ],
      ),
    ),
  );
  return presenter;
}

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'az fund, filters and unknown quorum in ${light ? 'light' : 'dark'}',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 780));
        final AcceleratorListPresenter presenter = await loadedPresenter();
        try {
          await tester.pumpWidget(host(listView(presenter), light: light));
          await tester.pump(const Duration(milliseconds: 700));
          expect(find.byKey(const Key('accelerator_strip')), findsOneWidget);
          expect(
            find.byKey(const Key('accelerator_filter_voting')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('accelerator_filter_active')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('accelerator_filter_mine')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('accelerator_filter_all')),
            findsOneWidget,
          );
          expect(find.text('Sentinel snapshot sync'), findsOneWidget);
          expect(find.text('Syrius desktop redesign'), findsOneWidget);
          expect(
            find.byKey(ValueKey<String>('accelerator_quorum_${listHash(1)}')),
            findsOneWidget,
          );
          final Text quorum = tester.widget<Text>(
            find.byKey(ValueKey<String>('accelerator_quorum_${listHash(1)}')),
          );
          expect(quorum.data, 'Unknown');
          expect(find.text('Your vote'), findsNWidgets(2));
          expect(
            tester.getSize(find.byKey(const Key('accelerator_sort'))).height,
            30,
          );
          expect(find.text('28 of 33'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          presenter.dispose();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  }

  testWidgets('search and sort use the same complete captured list', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 780));
    final AcceleratorListPresenter presenter = await loadedPresenter();
    try {
      await tester.pumpWidget(host(listView(presenter)));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.enterText(
        find.byKey(const Key('accelerator_search')),
        'Syrius',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Syrius desktop redesign'), findsOneWidget);
      expect(find.text('Sentinel snapshot sync'), findsNothing);
      await tester.tap(find.byKey(const Key('accelerator_sort')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Oldest'), findsOneWidget);
      expect(presenter.rows!.single.id, listHash(2));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      presenter.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('a revoked retained row callback cannot navigate', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 780));
    final AcceleratorListPresenter presenter = await loadedPresenter();
    int opened = 0;
    try {
      await tester.pumpWidget(
        host(
          listView(
            presenter,
            detailBuilder:
                (BuildContext context, AcceleratorListProject project) {
                  opened++;
                  return const Scaffold(body: Text('Synthetic detail'));
                },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      final InkWell row = tester.widget<InkWell>(
        find.byKey(ValueKey<String>('accelerator_project_${listHash(1)}')),
      );
      final VoidCallback saved = row.onTap!;
      presenter.invalidate();
      saved();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 0);
      expect(find.text('Synthetic detail'), findsNothing);
      expect(find.text('Sentinel snapshot sync'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      presenter.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('container transform is 300 ms on the nested navigator', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 780));
    final AcceleratorListPresenter presenter = await loadedPresenter();
    final _Routes root = _Routes();
    final _Routes nested = _Routes();
    try {
      await tester.pumpWidget(
        host(
          Navigator(
            observers: <NavigatorObserver>[nested],
            onGenerateRoute: (RouteSettings settings) =>
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => listView(
                    presenter,
                    detailBuilder:
                        (
                          BuildContext context,
                          AcceleratorListProject project,
                        ) => Scaffold(body: Text('Exact ${project.id}')),
                  ),
                ),
          ),
          observer: root,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      final OpenContainer<void> transform = tester.widget<OpenContainer<void>>(
        find.byKey(ValueKey<String>('accelerator_transform_${listHash(1)}')),
      );
      expect(transform.transitionDuration, const Duration(milliseconds: 300));
      expect(transform.useRootNavigator, isFalse);
      await tester.tap(
        find.byKey(ValueKey<String>('accelerator_project_${listHash(1)}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));
      expect(nested.pushed, hasLength(2));
      expect(root.pushed, hasLength(1));
      expect(find.text('Exact ${listHash(1)}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      presenter.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('narrow scaled layout keeps the complete ledger reachable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 780));
    final AcceleratorListPresenter presenter = await loadedPresenter();
    try {
      await tester.pumpWidget(host(listView(presenter), scale: 1.5));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('accelerator_search')), findsOneWidget);
      expect(find.byKey(const Key('accelerator_rows')), findsOneWidget);
      for (final String filter in <String>['voting', 'active', 'mine', 'all']) {
        expect(
          find.byKey(Key('accelerator_filter_$filter')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const Key('accelerator_sort')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Your vote'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      presenter.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
