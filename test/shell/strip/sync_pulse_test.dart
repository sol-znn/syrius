import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/cubits/timer_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/pair.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/status_dot.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/sync.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Widget _app(Widget child, {bool dark = true, bool disabled = false}) =>
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disabled),
          child: Center(child: child),
        ),
      ),
    );

BoxShadow _halo(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(StatusDot),
        matching: find.byType(DecoratedBox),
      ),
    )
    .map((DecoratedBox box) => box.decoration)
    .whereType<BoxDecoration>()
    .singleWhere((BoxDecoration box) => box.boxShadow?.isNotEmpty ?? false)
    .boxShadow!
    .single;

NodeSyncStatusState _state({
  int current = 100,
  int target = 100,
  SyncState actual = SyncState.syncDone,
  SyncState remembered = SyncState.syncDone,
}) => NodeSyncStatusState(
  status: TimerStatus.success,
  data: Pair<SyncState, SyncInfo>(
    remembered,
    SyncInfo.fromJson(<String, dynamic>{
      'state': actual.index,
      'currentHeight': current,
      'targetHeight': target,
    }),
  ),
);

void main() {
  for (final bool disabled in <bool>[false, true]) {
    testWidgets(
      'CSS pulse keeps 2.4 seconds with OS animations disabled=$disabled',
      (WidgetTester tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: disabled);
        try {
          await tester.pumpWidget(
            _app(StatusDot(color: AppTokens.dark.znn), disabled: disabled),
          );
          await tester.pump();
          expect(_halo(tester).spreadRadius, 0);
          expect(_halo(tester).color.a, closeTo(0.6, 0.001));
          expect(
            find.descendant(
              of: find.byType(StatusDot),
              matching: find.byType(RepaintBoundary),
            ),
            findsOneWidget,
          );
          await tester.pump(const Duration(milliseconds: 840));
          const Curve cssEase = Cubic(0.4, 0, 0.2, 1);
          final double halfway = cssEase.transform(0.5);
          expect(_halo(tester).spreadRadius, closeTo(7 * halfway, 0.001));
          expect(_halo(tester).color.a, closeTo(0.6 * (1 - halfway), 0.001));
          await tester.pump(const Duration(milliseconds: 840));
          expect(_halo(tester).spreadRadius, closeTo(7, 0.001));
          expect(_halo(tester).color.a, closeTo(0, 0.001));
          await tester.pump(const Duration(milliseconds: 420));
          expect(_halo(tester).spreadRadius, closeTo(7, 0.001));
          expect(_halo(tester).color.a, closeTo(0, 0.001));
          await tester.pump(const Duration(milliseconds: 300));
          expect(_halo(tester).spreadRadius, closeTo(0, 0.001));
          expect(_halo(tester).color.a, closeTo(0.6, 0.001));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        }
      },
    );
  }

  testWidgets(
    'changing status color preserves the phase and solid dot geometry',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(StatusDot(color: AppTokens.dark.znn, fillKey: const Key('fill'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 840));
      final double before = _halo(tester).spreadRadius;
      await tester.pumpWidget(
        _app(StatusDot(color: AppTokens.dark.qsr, fillKey: const Key('fill'))),
      );
      expect(_halo(tester).spreadRadius, closeTo(before, 0.001));
      expect(tester.getSize(find.byKey(const Key('fill'))), const Size(8, 8));
      expect(
        (tester
                    .widget<AnimatedContainer>(find.byKey(const Key('fill')))
                    .decoration!
                as BoxDecoration)
            .color,
        AppTokens.dark.qsr,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final bool dark in <bool>[true, false]) {
    testWidgets(
      'sync color follows current node state in ${dark ? 'dark' : 'light'}',
      (WidgetTester tester) async {
        final AppTokens tokens = dark ? AppTokens.dark : AppTokens.light;
        Future<Color> show(NodeSyncStatusState state) async {
          await tester.pumpWidget(_app(SyncDot(state: state), dark: dark));
          return (tester
                      .widget<AnimatedContainer>(
                        find.byKey(const Key('strip_sync')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
        }

        expect(await show(_state()), tokens.znn);
        expect(
          await show(_state(current: 97, actual: SyncState.syncing)),
          tokens.warn,
        );
        expect(
          await show(_state(current: 98, actual: SyncState.syncing)),
          tokens.znn,
        );
        expect(
          await show(_state(current: 0, target: 0, actual: SyncState.unknown)),
          tokens.warn,
        );
        expect(
          await show(
            NodeSyncStatusState(
              status: TimerStatus.failure,
              error: FailureException(message: 'Node unavailable'),
            ),
          ),
          tokens.error,
        );
        expect(await show(const NodeSyncStatusState()), tokens.warn);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('the localized sync state is accessible without color alone', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _app(SyncDot(state: _state(current: 80, actual: SyncState.syncing))),
      );
      expect(
        find.semantics.byLabel('Syncing, momentum 80 of 100'),
        findsOneWidget,
      );
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Syncing, momentum 80 of 100',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    }
  });
}
