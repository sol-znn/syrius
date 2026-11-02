import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fused_plasma/view/fused_plasma_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

Widget _host(PlasmaFixture fixture, ThemeData theme) => MaterialApp(
  theme: theme.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  ),
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 1000,
        height: 650,
        child: FusedPlasmaCard(
          owner: fixture.owner,
          captureSession: fixture.session,
          isCurrent: () => fixture.visible,
        ),
      ),
    ),
  ),
);

Future<void> _prepare(
  WidgetTester tester,
  PlasmaFixture fixture,
  ThemeData theme, {
  ValueListenable<bool>? pageVisible,
}) async {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  BalanceVisibility.debugReset();
  await _completeInRealAsync<void>(
    tester,
    fixture.loadAll,
    operation: 'Plasma fixture load',
  );
  final Widget host = _host(fixture, theme);
  await tester.pumpWidget(
    pageVisible == null
        ? host
        : ValueListenableBuilder<bool>(
            valueListenable: pageVisible,
            child: host,
            builder: (_, bool visible, Widget? child) =>
                TickerMode(enabled: visible, child: child!),
          ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(microseconds: 1));
}

// SDK subscription cancellation can return a root-zone future, so the
// fixture and its original operations must start outside the widget clock.
Future<T> _completeInRealAsync<T>(
  WidgetTester tester,
  Future<T> Function() start, {
  required String operation,
}) async {
  bool settled = false;
  late T result;
  (Object, StackTrace)? failure;
  await tester.runAsync<void>(() async {
    try {
      result = await start().timeout(
        const Duration(seconds: 1),
        onTimeout: () =>
            fail('$operation did not settle within one real second'),
      );
      settled = true;
    } on Object catch (error, stackTrace) {
      // runAsync reports uncaught errors and returns null. Retain the exact
      // error and stack here so the widget test observes the original failure.
      failure = (error, stackTrace);
    }
  });
  if (failure case (final Object error, final StackTrace stackTrace)) {
    Error.throwWithStackTrace(error, stackTrace);
  }
  if (!settled) fail('$operation did not complete in the real async scope');
  return result;
}

typedef _PlasmaFailure = ({
  String operation,
  Object error,
  StackTrace stackTrace,
});

class _PlasmaLifecycleFailures implements Exception {
  _PlasmaLifecycleFailures(List<_PlasmaFailure> failures)
    : failures = List<_PlasmaFailure>.unmodifiable(failures);

  final List<_PlasmaFailure> failures;

  @override
  String toString() => failures
      .map(
        (_PlasmaFailure failure) =>
            '${failure.operation}: ${failure.error}\n${failure.stackTrace}',
      )
      .join('\n\n');
}

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(PlasmaFixture fixture) body,
) async {
  final PlasmaFixture fixture = await _completeInRealAsync<PlasmaFixture>(
    tester,
    () async => PlasmaFixture(),
    operation: 'Plasma fixture construction',
  );
  final List<_PlasmaFailure> failures = <_PlasmaFailure>[];
  try {
    await body(fixture);
  } on Object catch (error, stackTrace) {
    failures.add((
      operation: 'Plasma test body',
      error: error,
      stackTrace: stackTrace,
    ));
  }
  try {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  } on Object catch (error, stackTrace) {
    failures.add((
      operation: 'Plasma widget unmount',
      error: error,
      stackTrace: stackTrace,
    ));
  }
  try {
    await _completeInRealAsync<void>(
      tester,
      fixture.close,
      operation: 'Plasma fixture close',
    );
  } on Object catch (error, stackTrace) {
    failures.add((
      operation: 'Plasma fixture close',
      error: error,
      stackTrace: stackTrace,
    ));
  }
  try {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    BalanceVisibility.debugReset();
  } on Object catch (error, stackTrace) {
    failures.add((
      operation: 'Plasma widget reset',
      error: error,
      stackTrace: stackTrace,
    ));
  }
  if (failures.length == 1) {
    final _PlasmaFailure failure = failures.single;
    Error.throwWithStackTrace(failure.error, failure.stackTrace);
  }
  if (failures.isNotEmpty) {
    // A close failure must not replace a cancellation or assertion failure.
    Error.throwWithStackTrace(
      _PlasmaLifecycleFailures(failures),
      failures.first.stackTrace,
    );
  }
}

void main() {
  initHydratedStorage();

  for (final bool dark in <bool>[false, true]) {
    testWidgets(
      'strict expiry controls in ${dark ? 'dark' : 'light'}',
      (WidgetTester tester) async {
        await _withFixture(tester, (PlasmaFixture fixture) async {
          fixture.rows[1].expirationHeight = 11;
          await _prepare(
            tester,
            fixture,
            dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          );
          expect(find.byKey(const Key('plasma_fused_count')), findsOneWidget);
          final Finder eligible = find.byKey(
            ValueKey<String>('plasma_select_${plasmaTestHash(1)}'),
          );
          final Finder locked = find.byKey(
            ValueKey<String>('plasma_select_${plasmaTestHash(2)}'),
          );
          expect(tester.widget<Checkbox>(eligible).onChanged, isNotNull);
          expect(tester.widget<Checkbox>(locked).onChanged, isNull);
          for (final int id in <int>[1, 2]) {
            final Finder cancel = find.byKey(
              ValueKey<String>('plasma_cancel_${plasmaTestHash(id)}'),
            );
            final OutlinedButton button = tester.widget<OutlinedButton>(
              cancel,
            );
            expect(tester.getSize(cancel).height, 26);
            expect(
              button.style!.textStyle!.resolve(<WidgetState>{})!.fontSize,
              12,
            );
            expect(
              button.style!.padding!
                  .resolve(<WidgetState>{})!
                  .resolve(TextDirection.ltr),
              const EdgeInsets.symmetric(horizontal: 10),
            );
          }
          await tester.tap(eligible);
          await tester.pump();
          expect(fixture.owner.selected, <String>{plasmaTestHash(1)});
          expect(
            find.byKey(const Key('plasma_cancel_selected')),
            findsOneWidget,
          );
          expect(find.text('1 selected'), findsOneWidget);
          expect(
            tester
                .getSize(find.byKey(const Key('plasma_cancel_selected')))
                .height,
            26,
          );
          expect(fixture.transport.calls, isEmpty);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }

  testWidgets(
    'exact question hashes and stale callbacks preserve the current route',
    (WidgetTester tester) async {
      await _withFixture(tester, (PlasmaFixture fixture) async {
        await _prepare(tester, fixture, AppTheme.darkTheme);
        await tester.tap(
          find.byKey(ValueKey<String>('plasma_cancel_${plasmaTestHash(1)}')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.byKey(const Key('plasma_cancel_confirmation')),
          findsOneWidget,
        );
        expect(find.text(plasmaTestHash(1)), findsOneWidget);
        final Finder decline = find.byKey(const Key('plasma_cancel_decline'));
        final VoidCallback stale = tester
            .widget<TextButton>(decline)
            .onPressed!;
        final FrostedDialogRoute<bool> route =
            ModalRoute.of<bool>(tester.element(decline))!
                as FrostedDialogRoute<bool>;
        await tester.tap(decline);
        stale();
        await tester.pump();
        await tester.pump(route.reverseTransitionDuration);
        await tester.pump(const Duration(microseconds: 1));
        expect(find.byKey(const Key('plasma_fused_list')), findsOneWidget);
        expect(fixture.owner.questioning, isFalse);
        expect(fixture.transport.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'leaving and returning cannot revive an original cancel question',
    (WidgetTester tester) async {
      final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await _withFixture(tester, (PlasmaFixture fixture) async {
        await _prepare(
          tester,
          fixture,
          AppTheme.darkTheme,
          pageVisible: visible,
        );
        await tester.tap(
          find.byKey(ValueKey<String>('plasma_cancel_${plasmaTestHash(1)}')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final Finder accept = find.byKey(const Key('plasma_cancel_accept'));
        final VoidCallback original = tester
            .widget<OutlinedButton>(accept)
            .onPressed!;
        final ModalRoute<bool> route = ModalRoute.of<bool>(
          tester.element(accept),
        )!;
        expect(route.isCurrent, isTrue);
        visible.value = false;
        await tester.pump();
        visible.value = true;
        await tester.pump();
        // No check ran during the hidden visit. Its epoch still revokes it.
        original();
        expect(route.isCurrent, isTrue);
        expect(fixture.transport.calls, isEmpty);
        await tester.tap(find.byKey(const Key('plasma_cancel_decline')));
        await tester.pump();
        await tester.pump(route.reverseTransitionDuration);
        await tester.pump(const Duration(microseconds: 1));
        expect(fixture.owner.questioning, isFalse);
        expect(fixture.transport.calls, isEmpty);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'submitted rows remain present and disabled pending contract outcome',
    (WidgetTester tester) async {
      await _withFixture(tester, (PlasmaFixture fixture) async {
        await _prepare(tester, fixture, AppTheme.lightTheme);
        final PlasmaCancelIntent intent = fixture.intent(
          hash: plasmaTestHash(1),
        );
        final PlasmaCancellationBatch? batch =
            await _completeInRealAsync<PlasmaCancellationBatch?>(
              tester,
              () => fixture.owner.cancel(intent),
              operation: 'Original Plasma cancellation',
            );
        expect(batch!.submitted, 1);
        await tester.pump();
        expect(
          find.byKey(ValueKey<String>('plasma_row_${plasmaTestHash(1)}')),
          findsOneWidget,
        );
        expect(find.text('Submitted'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(
                  ValueKey<String>('plasma_cancel_${plasmaTestHash(1)}'),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining('cancelled'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    },
  );
}
