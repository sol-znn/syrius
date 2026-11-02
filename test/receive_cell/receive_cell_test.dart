import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/infinite_scroll_table/cells/receive_cell.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

Widget _shell(
  Widget child, {
  Brightness brightness = Brightness.dark,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  navigatorKey: navigatorKey,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  initHydratedStorage();
  final Hash first = Hash.digest(<int>[1]);
  final Hash second = Hash.digest(<int>[2]);
  late AutoReceiveTxWorker worker;
  late ReceiveFixture fixture;
  late Zenon? previousNode;

  setUp(() {
    previousNode = zenon;
    fixture = ReceiveFixture();
    worker = fixture.worker;
    sl.registerSingleton<AutoReceiveTxWorker>(worker);
  });

  tearDown(() async {
    if (!fixture.closed) await fixture.close();
    await sl.reset();
    zenon = previousNode;
  });

  IconButton button(WidgetTester tester, Hash hash) =>
      tester.widget<IconButton>(
        find.byKey(ValueKey<String>('receive_$hash')),
      );

  testWidgets('the button of a row whose receive is under way is off, '
      'and the other rows keep theirs', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: <Widget>[
              // A cell is its own Expanded.
              ReceiveCell(hash: first),
              ReceiveCell(hash: second),
            ],
          ),
        ),
      ),
    );
    expect(button(tester, first).onPressed, isNotNull);
    expect(button(tester, second).onPressed, isNotNull);

    worker.inFlight.value = <Hash>{first};
    await tester.pump();
    expect(button(tester, first).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(button(tester, second).onPressed, isNotNull);

    worker.inFlight.value = <Hash>{};
    await tester.pump();
    expect(button(tester, first).onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await closeReceiveFixture(tester, fixture);
  });

  test(
    'a receive that fails before it is published unblocks its row',
    () async {
      // No node: the first request throws.
      zenon = null;
      worker.detachSender(fixture.lease);
      final List<Set<Hash>> seen = <Set<Hash>>[];
      worker.inFlight.addListener(() => seen.add(worker.inFlight.value));
      await expectLater(
        worker.autoReceiveTransactionHash(first),
        throwsA(anything),
      );
      expect(seen.first, <Hash>{first}, reason: 'blocked while it ran');
      expect(worker.inFlight.value, isEmpty);
      expect(worker.running, isFalse);
    },
  );

  for (final Brightness brightness in Brightness.values) {
    testWidgets('saved row callback cannot receive a replacement hash in '
        '${brightness.name}', (WidgetTester tester) async {
      final ValueNotifier<Hash> shown = ValueNotifier<Hash>(first);
      try {
        await tester.pumpWidget(
          _shell(
            ValueListenableBuilder<Hash>(
              valueListenable: shown,
              builder: (_, Hash hash, _) => Row(
                children: <Widget>[ReceiveCell(hash: hash)],
              ),
            ),
            brightness: brightness,
          ),
        );
        final VoidCallback old = button(tester, first).onPressed!;
        shown.value = second;
        await tester.pump();
        old();
        expect(fixture.proofReads, 0);
        button(tester, second).onPressed!();
        await pumpReceiveUntil(
          tester,
          () =>
              worker.originals.length == 1 &&
              worker.originals.single.result != null,
        );
        expect(worker.originals.single.inboundHash, second.toString());
        expect(fixture.transport.calls, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        old();
        expect(fixture.transport.calls, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closeReceiveFixture(tester, fixture);
        shown.dispose();
      }
    });

    testWidgets('a covering route permanently revokes the saved callback in '
        '${brightness.name}', (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      try {
        await tester.pumpWidget(
          _shell(
            Row(children: <Widget>[ReceiveCell(hash: first)]),
            brightness: brightness,
            navigatorKey: navigator,
          ),
        );
        final VoidCallback old = button(tester, first).onPressed!;
        navigator.currentState!.push<void>(
          PageRouteBuilder<void>(
            opaque: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const Scaffold(body: Text('Cover')),
          ),
        );
        await tester.pump();
        old();
        expect(fixture.proofReads, 0);
        expect(find.text('Cover'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump();
        old();
        expect(fixture.proofReads, 0);
        button(tester, first).onPressed!();
        await pumpReceiveUntil(
          tester,
          () =>
              worker.originals.length == 1 &&
              worker.originals.single.result != null,
        );
        expect(fixture.transport.calls, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closeReceiveFixture(tester, fixture);
      }
    });

    testWidgets('inactivity and TickerMode revoke old row callbacks in '
        '${brightness.name}', (WidgetTester tester) async {
      final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
      try {
        await tester.pumpWidget(
          _shell(
            ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, bool enabled, _) => TickerMode(
                enabled: enabled,
                child: Row(children: <Widget>[ReceiveCell(hash: first)]),
              ),
            ),
            brightness: brightness,
          ),
        );
        final VoidCallback beforeInactive = button(tester, first).onPressed!;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        beforeInactive();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        beforeInactive();
        expect(fixture.proofReads, 0);
        final VoidCallback beforeHidden = button(tester, first).onPressed!;
        visible.value = false;
        await tester.pump();
        beforeHidden();
        visible.value = true;
        await tester.pump();
        beforeHidden();
        expect(fixture.proofReads, 0);
        button(tester, first).onPressed!();
        await pumpReceiveUntil(
          tester,
          () =>
              worker.originals.length == 1 &&
              worker.originals.single.result != null,
        );
        expect(fixture.transport.calls, hasLength(1));
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await closeReceiveFixture(tester, fixture);
        visible.dispose();
      }
    });

    for (final bool unknown in <bool>[false, true]) {
      testWidgets('remounted row holds the original '
          '${unknown ? 'unknown' : 'accepted'} result in ${brightness.name}', (
        WidgetTester tester,
      ) async {
        final ValueNotifier<bool> shown = ValueNotifier<bool>(true);
        fixture.transport.deferred = true;
        try {
          await tester.pumpWidget(
            _shell(
              ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (_, bool visible, _) => Row(
                  children: <Widget>[
                    if (visible) ReceiveCell(hash: first),
                  ],
                ),
              ),
              brightness: brightness,
            ),
          );
          final VoidCallback old = button(tester, first).onPressed!;
          old();
          await pumpReceiveUntil(
            tester,
            () => fixture.transport.pending.length == 1,
          );
          final ReceiveRecord record = worker.originals.single;
          final Future<AccountBlockTemplate?> projection = record.future;
          Object? originalError;
          AccountBlockTemplate? received;
          final Future<void> observed = projection.then<void>(
            (AccountBlockTemplate? block) {
              received = block;
            },
            onError: (Object error, StackTrace _) {
              originalError = error;
            },
          );
          shown.value = false;
          await tester.pump();
          shown.value = true;
          await tester.pump();
          expect(button(tester, first).onPressed, isNull);
          final StateError error = StateError('Synthetic receive uncertainty');
          final AccountBlockTemplate original = fixture.transport.complete(
            error: unknown ? error : null,
          );
          await pumpReceiveUntil(
            tester,
            () => record.result != null && !worker.running,
          );
          await observed;
          expect(received, unknown ? isNull : same(original));
          expect(originalError, unknown ? same(error) : isNull);
          expect(record.result!.block, unknown ? isNull : same(original));
          expect(record.result!.error, unknown ? same(error) : isNull);
          // Passing the removed one-minute timeout cannot release a hold.
          await tester.pump(const Duration(minutes: 2));
          expect(worker.autoReceiveTransactionHash(first), same(projection));
          old();
          expect(fixture.transport.calls, hasLength(1));
          expect(button(tester, first).onPressed, isNull);
          expect(worker.inFlight.value, <Hash>{first});
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await closeReceiveFixture(tester, fixture);
          shown.dispose();
        }
      });
    }
  }
}
