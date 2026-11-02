import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/sentinels.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/view/sentinel_values.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../sentinel_fixture.dart';

class _Sentinels
    extends MockBloc<InfiniteListEvent, InfiniteListState<SentinelInfo>>
    implements SentinelsBloc {}

InfiniteListState<SentinelInfo> _populated(
  List<SentinelInfo> entries, {
  bool complete = true,
}) => InfiniteListState<SentinelInfo>(
  status: InfiniteListStatus.success,
  data: entries,
  hasReachedMax: complete,
);

Finder _row(int index) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is ListEntranceItem &&
      widget.key == ValueKey<String>(sentinelOwnerFixture(index)),
);

double _opacity(WidgetTester tester, int index) => tester
    .widget<Opacity>(
      find.descendant(of: _row(index), matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  late _Sentinels reader;
  late StreamController<InfiniteListState<SentinelInfo>> states;
  late Map<String, String> previousLabels;

  setUpAll(() {
    registerFallbackValue(const InfiniteListRequested());
  });

  setUp(() {
    reader = _Sentinels();
    states = StreamController<InfiniteListState<SentinelInfo>>.broadcast(
      sync: true,
    );
    previousLabels = kAddressLabelMap;
    kAddressLabelMap = <String, String>{sentinelOwnerFixture(1): 'Address 3'};
  });

  tearDown(() async {
    await states.close();
    kAddressLabelMap = previousLabels;
    AppLottie.debugClear();
  });

  Widget host({
    ThemeData? theme,
    double textScale = 1,
    bool light = false,
    bool rtl = false,
    String? selected,
    VoidCallback? onSpawn,
    VoidCallback? onOpenOwner,
  }) => MaterialApp(
    theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
    locale: rtl ? const Locale('ar') : const Locale('en'),
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: SentinelsCard(
        bloc: reader,
        selectedAddress: selected ?? sentinelOwnerFixture(1),
        onSpawn: onSpawn,
        onOpenOwner: onOpenOwner,
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester,
    InfiniteListState<SentinelInfo> initial, {
    ThemeData? theme,
    bool light = false,
    bool rtl = false,
    String? selected,
    VoidCallback? onSpawn,
    VoidCallback? onOpenOwner,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    whenListen(reader, states.stream, initialState: initial);
    await tester.pumpWidget(
      host(
        theme: theme,
        light: light,
        rtl: rtl,
        selected: selected,
        onSpawn: onSpawn,
        onOpenOwner: onOpenOwner,
      ),
    );
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets('four factual columns are present, light=$light', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        _populated(<SentinelInfo>[
          sentinelFixture(1),
          sentinelFixture(2, open: true),
        ]),
        light: light,
      );
      await tester.pump(const Duration(milliseconds: 450));
      for (final String label in <String>[
        'OWNER',
        'REGISTERED',
        'REVOCABLE',
        'STATUS',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('27 d ago'), findsNWidgets(2));
      expect(find.text('in 3 d 2 h'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
      expect(find.text('Yours'), findsOneWidget);
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.byTooltip(sentinelOwnerFixture(1)), findsOneWidget);
      expect(find.byTooltip(sentinelOwnerFixture(2)), findsOneWidget);
      expect(find.text('Producing'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'Spawn keeps 26 px and caller enablement in compact density, $light',
      (WidgetTester tester) async {
        final ThemeData theme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
              visualDensity: VisualDensity.compact,
            );
        int spawned = 0;
        await show(
          tester,
          _populated(<SentinelInfo>[sentinelFixture(1)]),
          theme: theme,
          onSpawn: () => spawned++,
        );
        await tester.pump(const Duration(milliseconds: 450));
        final Finder button = find.byKey(const Key('sentinels_spawn'));
        expect(
          Theme.of(tester.element(button)).visualDensity,
          VisualDensity.compact,
        );
        expect(tester.getSize(button).height, 26);
        expect(tester.widget<TextButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        expect(spawned, 1);

        await tester.pumpWidget(host(theme: theme));
        await tester.pump();
        expect(tester.getSize(button).height, 26);
        expect(tester.widget<TextButton>(button).onPressed, isNull);
        await tester.tap(button);
        expect(spawned, 1);

        await tester.pumpWidget(
          host(theme: theme, textScale: 1.75, onSpawn: () => spawned++),
        );
        await tester.pump();
        expect(tester.getSize(button).height, greaterThan(26));
        expect(tester.widget<TextButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        expect(spawned, 2);
        verifyNever(() => reader.add(any()));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'active pages do not become revoked history or duplicate owners',
    (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        _populated(<SentinelInfo>[
          sentinelFixture(1),
          sentinelFixture(1),
          sentinelFixture(2, active: false),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(SentinelRegistrationTime), findsOneWidget);
      expect(_row(1), findsOneWidget);
      expect(_row(2), findsNothing);
      expect(find.text('Revoked'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('only exact selected ownership opens its existing workflow', (
    WidgetTester tester,
  ) async {
    int spawned = 0;
    int opened = 0;
    await show(
      tester,
      _populated(<SentinelInfo>[sentinelFixture(1), sentinelFixture(2)]),
      onSpawn: () => spawned++,
      onOpenOwner: () => opened++,
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const Key('sentinels_open_owner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sentinels_spawn')));
    await tester.tap(find.byKey(const Key('sentinels_open_owner')));
    expect(spawned, 1);
    expect(opened, 1);
    verifyNever(() => reader.add(any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('foreign rows do not inherit an owner action', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      _populated(<SentinelInfo>[sentinelFixture(2)]),
      onOpenOwner: () => fail('Foreign owner action'),
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Yours'), findsNothing);
    expect(find.byKey(const Key('sentinels_open_owner')), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('sentinels_spawn')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'keyboard traversal reaches the admitted Spawn and owner actions',
    (
      WidgetTester tester,
    ) async {
      int spawned = 0;
      int opened = 0;
      await show(
        tester,
        _populated(<SentinelInfo>[sentinelFixture(1)]),
        onSpawn: () => spawned++,
        onOpenOwner: () => opened++,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(spawned, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('overlapping membership refreshes retain each row entrance', (
    WidgetTester tester,
  ) async {
    final List<SentinelInfo> entries = <SentinelInfo>[
      sentinelFixture(1),
      sentinelFixture(2),
    ];
    await show(tester, _populated(entries));
    expect(_opacity(tester, 1), 0);
    await tester.pump(const Duration(milliseconds: 450));
    states.add(_populated(entries.reversed.toList()));
    await tester.pump();
    expect(_opacity(tester, 1), 1);
    states.add(_populated(const <SentinelInfo>[]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('None yet'), findsOneWidget);
    states.add(_populated(entries));
    await tester.pump();
    expect(_opacity(tester, 1), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unfilled live page requests its actual next page once', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      _populated(<SentinelInfo>[sentinelFixture(1)], complete: false),
    );
    await tester.pump();
    verify(() => reader.add(const InfiniteListMoreRequested())).called(1);
    await tester.pump(const Duration(milliseconds: 450));
    verifyNever(() => reader.add(const InfiniteListMoreRequested()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failure offers a real refresh without showing an empty claim', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      InfiniteListState<SentinelInfo>(
        status: InfiniteListStatus.failure,
        error: FailureException(),
      ),
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('None yet'), findsNothing);
    await tester.tap(find.text('Retry'));
    verify(() => reader.add(const InfiniteListRefreshRequested())).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owner identifiers keep LTR data in an Arabic layout', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      _populated(<SentinelInfo>[sentinelFixture(1)]),
      rtl: true,
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      Directionality.of(tester.element(find.text('Address 3'))),
      TextDirection.ltr,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
