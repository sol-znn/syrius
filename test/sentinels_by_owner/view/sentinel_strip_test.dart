import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels_by_owner/view/sentinel_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../sentinels/sentinel_fixture.dart';

Widget _host(
  Widget child, {
  bool light = false,
  bool rtl = false,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
  locale: rtl ? const Locale('ar') : const Locale('en'),
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Widget _strip(
  FetchState<List<SentinelInfo>> state, {
  Widget rewards = const Skeleton(width: 120),
  Widget collectAction = const TextButton(
    onPressed: null,
    child: Text('Collect'),
  ),
  VoidCallback? onOpenOwner,
  VoidCallback? onOpenRewards,
}) => SentinelStrip(
  selectedAddress: sentinelOwnerFixture(1),
  ownerState: state,
  rewards: rewards,
  collectAction: collectAction,
  onOpenOwner: onOpenOwner,
  onOpenRewards: onOpenRewards,
);

void main() {
  late Map<String, String> previousLabels;

  setUp(() {
    previousLabels = kAddressLabelMap;
    kAddressLabelMap = <String, String>{sentinelOwnerFixture(1): 'Address 3'};
    sharedPrefsService = null;
    BalanceVisibility.debugReset();
  });

  tearDown(() {
    kAddressLabelMap = previousLabels;
    sharedPrefsService = null;
    BalanceVisibility.debugReset();
    AppLottie.debugClear();
  });

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool light = false,
    bool rtl = false,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        child,
        light: light,
        rtl: rtl,
        disableAnimations: disableAnimations,
      ),
    );
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'proven ownership leads with the original at48px, light=$light',
      (
        WidgetTester tester,
      ) async {
        await show(
          tester,
          _strip(
            FetchPopulated<List<SentinelInfo>>(
              data: <SentinelInfo>[sentinelFixture(1)],
            ),
          ),
          light: light,
          disableAnimations: true,
        );
        final NodeObject object = tester.widget<NodeObject>(
          find.byType(NodeObject),
        );
        expect(object.size, 48);
        final AppLottie animation = tester.widget<AppLottie>(
          find.byType(AppLottie),
        );
        expect(animation.asset, AppLottieAsset.sentinel);
        expect(animation.repeat, isFalse);
        expect(find.byKey(const Key('nodes_sentinel_active')), findsOneWidget);
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('Address 3'), findsOneWidget);
        expect(find.byTooltip(sentinelOwnerFixture(1)), findsOneWidget);
        expect(find.text('Producing'), findsNothing);
        expect(find.text('None yet'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('inactive ownership stays owned instead of becoming empty', (
    WidgetTester tester,
  ) async {
    int opened = 0;
    await show(
      tester,
      _strip(
        FetchPopulated<List<SentinelInfo>>(
          data: <SentinelInfo>[sentinelFixture(1, active: false)],
        ),
        onOpenOwner: () => opened++,
      ),
    );
    expect(find.byType(NodeObject), findsOneWidget);
    expect(find.byKey(const Key('nodes_sentinel_revoked')), findsOneWidget);
    expect(find.text('None yet'), findsNothing);
    expect(find.text('Spawn'), findsNothing);
    expect(find.text('Active'), findsNothing);
    await tester.tap(find.byKey(const Key('nodes_sentinel_owner')));
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('foreign cached ownership stays unavailable and cannot act', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      _strip(
        FetchPopulated<List<SentinelInfo>>(
          data: <SentinelInfo>[sentinelFixture(2)],
        ),
        onOpenOwner: () => fail('Foreign ownership admitted'),
      ),
    );
    expect(find.byType(NodeObject), findsNothing);
    expect(find.byKey(const Key('nodes_sentinel_owner_address')), findsNothing);
    expect(find.byKey(const Key('nodes_sentinel_active')), findsNothing);
    expect(find.byType(Skeleton), findsNWidgets(3));
    expect(find.text('None yet'), findsNothing);
    final IconButton owner = tester.widget<IconButton>(
      find.byKey(const Key('nodes_sentinel_owner')),
    );
    expect(owner.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty ownership allows only the caller-provided owner action', (
    WidgetTester tester,
  ) async {
    int opened = 0;
    await show(
      tester,
      _strip(
        const FetchPopulated<List<SentinelInfo>>(data: <SentinelInfo>[]),
        onOpenOwner: () => opened++,
      ),
    );
    expect(find.text('None yet'), findsOneWidget);
    expect(find.byType(NodeObject), findsNothing);
    expect(find.byKey(const Key('nodes_sentinel_active')), findsNothing);
    await tester.tap(find.byKey(const Key('nodes_sentinel_owner')));
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owner failure remains distinct from no sentinel', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      _strip(
        FetchFailure<List<SentinelInfo>>(exception: FailureException()),
        onOpenOwner: () => fail('Failed ownership admitted'),
      ),
    );
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('None yet'), findsNothing);
    expect(find.byType(NodeObject), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('nodes_sentinel_owner')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('exact rewards and dollars leave no hidden amount semantics', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await show(
        tester,
        _strip(
          const FetchInitial<List<SentinelInfo>>(),
          rewards: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AmountText(
                BigInt.parse('900719925474099300000001'),
                decimals: 8,
                style: const TextStyle(fontSize: 19),
                symbol: 'ZNN',
              ),
              const Text(r'≈ $0.7905'),
            ],
          ),
        ),
      );
      expect(
        find.text('9,007,199,254,740,993.00000001 ZNN', findRichText: true),
        findsOneWidget,
      );
      BalanceVisibility.instance.set(true);
      await tester.pump();
      expect(find.text('••••'), findsOneWidget);
      expect(find.semantics.byLabel(RegExp(r'9,007|0\.7905')), findsNothing);
      BalanceVisibility.instance.set(false);
      await tester.pump();
      expect(find.text(r'≈ $0.7905'), findsOneWidget);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('root collection and history callbacks remain the only actions', (
    WidgetTester tester,
  ) async {
    int collected = 0;
    int opened = 0;
    await show(
      tester,
      _strip(
        const FetchInitial<List<SentinelInfo>>(),
        collectAction: TextButton(
          onPressed: () => collected++,
          child: const Text('Collect'),
        ),
        onOpenRewards: () => opened++,
      ),
    );
    await tester.tap(find.text('Collect'));
    await tester.tap(find.byKey(const Key('nodes_sentinel_rewards')));
    expect(collected, 1);
    expect(opened, 1);
    expect(find.byType(NodeObject), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('captured ownership can replace a foreign result in RTL', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      _strip(
        FetchPopulated<List<SentinelInfo>>(
          data: <SentinelInfo>[sentinelFixture(2), sentinelFixture(1)],
        ),
      ),
      rtl: true,
    );
    expect(find.text('Address 3'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Address 3'))),
      TextDirection.ltr,
    );
    expect(find.byTooltip(sentinelOwnerFixture(2)), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
