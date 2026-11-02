import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/join_native_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/native_p2p_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/recover_deposit_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/start_native_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

/// Exercises the presentation mixin with a finite original Future.
class _RunHarness extends StatefulWidget {
  const _RunHarness({required this.origin, required this.operation, super.key});
  final SwapActionOrigin origin;
  final Future<SwapActionResult> Function() operation;
  @override
  State<_RunHarness> createState() => _RunHarnessState();
}

class _RunHarnessState extends State<_RunHarness>
    with CapturedSwapModal<_RunHarness> {
  final TextEditingController input = TextEditingController(
    text: 'Fixture input',
  );
  @override
  SwapActionOrigin? get providedOrigin => widget.origin;
  @override
  bool Function()? get providedIsCurrent => null;
  @override
  Widget build(BuildContext context) => captured((
    BuildContext context,
    SwapViewLease lease, {
    required bool hidden,
  }) {
    final Future<SwapActionResult> Function() operation = widget.operation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SwapPrimaryAction(
          key: const Key('fixture_submit'),
          label: 'Fixture action',
          busy: busy,
          onPressed: !owns(lease) || busy || held
              ? null
              : () => unawaited(submit(lease, operation)),
        ),
        OutlinedButton(
          key: const Key('fixture_paste'),
          onPressed: !owns(lease) ? null : () => unawaited(paste(lease, input)),
          child: const Text('Fixture paste'),
        ),
        OutlinedButton(
          key: const Key('fixture_copy'),
          onPressed: !owns(lease)
              ? null
              : () => unawaited(copy(lease, fixtureHash(1))),
          child: const Text('Fixture copy'),
        ),
        if (resultNotice(context) case final Widget notice) notice,
      ],
    );
  });
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}

VoidCallback _submit(WidgetTester tester) => tester
    .widget<SwapPrimaryAction>(find.byKey(const Key('fixture_submit')))
    .onPressed!;

void main() {
  final Map<String, Widget Function()> unbound = <String, Widget Function()>{
    'Start': () =>
        StartNativeSwapModal(onSwapStarted: (_) {}, dollars: fixtureDollars),
    'Join': () =>
        JoinNativeSwapModal(onJoinedSwap: (_) {}, dollars: fixtureDollars),
    'Recover': () => const RecoverDepositModal(dollars: fixtureDollars),
    'Details': () =>
        NativeP2pSwapModal(swapId: fixtureHash(1), dollars: fixtureDollars),
  };
  for (final MapEntry<String, Widget Function()> entry in unbound.entries) {
    testWidgets(
      'unbound ${entry.key} refuses without resolving a later wallet',
      (WidgetTester tester) async {
        prepareSwapViewport(tester);
        await tester.pumpWidget(swapHost(entry.value()));
        await swapFrames(tester);
        expect(
          find.text('Wallet or node changed. Refresh swaps.'),
          findsOneWidget,
        );
        expect(find.byType(SwapAmountPane), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a previously unbound Start cannot adopt a replacement origin', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture replacement = SwapUiFixture();
    await tester.pumpWidget(
      swapHost(
        StartNativeSwapModal(
          key: const Key('original_modal'),
          onSwapStarted: (_) {},
          dollars: fixtureDollars,
        ),
      ),
    );
    await tester.pumpWidget(
      swapHost(
        StartNativeSwapModal(
          key: const Key('original_modal'),
          onSwapStarted: (_) {},
          source: replacement.origin,
          dollars: fixtureDollars,
        ),
      ),
    );
    await swapFrames(tester);
    expect(replacement.accountReads, isEmpty);
    expect(replacement.mutations, 0);
    expect(find.text('Wallet or node changed. Refresh swaps.'), findsOneWidget);
  });

  testWidgets('Start renders only the original positive account answer', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    final Completer<AccountInfo> original = Completer<AccountInfo>();
    fixture.accountReply = original.future;
    await tester.pumpWidget(
      swapHost(
        StartNativeSwapModal(
          onSwapStarted: (_) {},
          source: fixture.origin,
          dollars: fixtureDollars,
        ),
      ),
    );
    expect(fixture.accountReads, <String>[fixture.owner]);
    fixture.accountReply = Future<AccountInfo>.value(
      fixture.account(fixture.member),
    );
    original.complete(fixture.account(fixture.owner));
    await swapFrames(tester);
    expect(
      tester
          .widgetList<AmountText>(find.byType(AmountText))
          .where((AmountText amount) => amount.raw == fixture.available)
          .length,
      1,
    );
    expect(fixture.mutations, 0);
    expect(find.byKey(const Key('swap_create_deposit')), findsNothing);
  });

  testWidgets('a pending Start read cannot fill a replacement source', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    final SwapUiFixture replacement = SwapUiFixture();
    final Completer<AccountInfo> original = Completer<AccountInfo>();
    fixture.accountReply = original.future;
    await tester.pumpWidget(
      swapHost(
        StartNativeSwapModal(
          key: const Key('original'),
          onSwapStarted: (_) {},
          source: fixture.origin,
          dollars: fixtureDollars,
        ),
      ),
    );
    await tester.pumpWidget(
      swapHost(
        StartNativeSwapModal(
          key: const Key('original'),
          onSwapStarted: (_) {},
          source: replacement.origin,
          dollars: fixtureDollars,
        ),
      ),
    );
    original.complete(fixture.account(fixture.owner));
    await swapFrames(tester);
    expect(replacement.accountReads, isEmpty);
    expect(find.byType(SwapAmountPane), findsNothing);
    expect(fixture.mutations + replacement.mutations, 0);
  });

  testWidgets(
    'Native details never paint completed history as fresh chain completion',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SwapUiFixture fixture = SwapUiFixture();
      final HtlcSwap record = fixtureRecord(
        fixture,
        state: P2pSwapState.completed,
      );
      fixture.records = <HtlcSwap>[record];
      await tester.pumpWidget(
        swapHost(
          NativeP2pSwapModal(
            swapId: record.id,
            source: fixture.origin,
            dollars: fixtureDollars,
          ),
        ),
      );
      await swapFrames(tester);
      expect(find.text('Chain status unknown'), findsOneWidget);
      expect(find.text('Recorded'), findsWidgets);
      expect(find.textContaining('completed'), findsNothing);
      expect(find.text(record.hashLock), findsNothing);
      expect(find.byKey(const Key('swap_detail_action')), findsNothing);
      expect(fixture.mutations, 0);
    },
  );

  testWidgets(
    'positive expired details offer an explicit reclaim '
    'despite an old terminal label',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SwapUiFixture fixture = SwapUiFixture()..now = 10000;
      final HtlcSwap record = fixtureRecord(
        fixture,
        state: P2pSwapState.completed,
      );
      fixture.records = <HtlcSwap>[record];
      fixture.htlcReply = (_) async => fixtureDeposit(fixture);
      await tester.pumpWidget(
        swapHost(
          NativeP2pSwapModal(
            swapId: record.id,
            source: fixture.origin,
            dollars: fixtureDollars,
          ),
        ),
      );
      await swapFrames(tester);
      expect(
        find.text('Deposit expired. Reclaim it explicitly.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('swap_detail_action')), findsOneWidget);
      expect(
        tester
            .widget<SwapPrimaryAction>(
              find.byKey(const Key('swap_detail_action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('completed'), findsNothing);
      expect(fixture.mutations, 0);
    },
  );

  testWidgets(
    'Recover discovery never signs automatically after positive expiry',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SwapUiFixture fixture = SwapUiFixture()..now = 10000;
      fixture.htlcReply = (_) async => fixtureDeposit(fixture);
      await tester.pumpWidget(
        swapHost(
          RecoverDepositModal(source: fixture.origin, dollars: fixtureDollars),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('swap_deposit_id_input')),
        fixtureHash(1),
      );
      await tester.pump();
      tester
          .widget<SwapPrimaryAction>(
            find.byKey(const Key('swap_recover_action')),
          )
          .onPressed!();
      await swapFrames(tester);
      expect(
        find.text('Deposit expired. Reclaim it explicitly.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwapPrimaryAction>(
              find.byKey(const Key('swap_recover_action')),
            )
            .label,
        'Reclaim',
      );
      expect(fixture.depositReads, 1);
      expect(fixture.mutations, 0);
    },
  );

  testWidgets(
    'busy clicks and an unknown original never invoke a replacement action',
    (WidgetTester tester) async {
      prepareSwapViewport(tester);
      final SwapUiFixture fixture = SwapUiFixture();
      final Completer<SwapActionResult> original =
          Completer<SwapActionResult>();
      final GlobalKey<_RunHarnessState> owner = GlobalKey<_RunHarnessState>();
      int calls = 0;
      await tester.pumpWidget(
        swapHost(
          _RunHarness(
            key: owner,
            origin: fixture.origin,
            operation: () {
              calls++;
              return original.future;
            },
          ),
        ),
      );
      final VoidCallback saved = _submit(tester);
      saved();
      saved();
      await tester.pump();
      expect(calls, 1);
      expect(
        identical(owner.currentState!.activeRun!.original, original.future),
        isTrue,
      );
      original.complete(SwapActionResult(status: SwapActionStatus.unknown));
      await swapFrames(tester);
      saved();
      expect(calls, 1);
      expect(
        find.text('Result unknown. Check this deposit before another action.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwapPrimaryAction>(find.byKey(const Key('fixture_submit')))
            .onPressed,
        isNull,
      );
      expect(fixture.mutations, 0);
    },
  );

  testWidgets('accepted submission is labelled Submitted and remains held', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    int calls = 0;
    await tester.pumpWidget(
      swapHost(
        _RunHarness(
          origin: fixture.origin,
          operation: () {
            calls++;
            return Future<SwapActionResult>.value(
              SwapActionResult(status: SwapActionStatus.submitted),
            );
          },
        ),
      ),
    );
    final VoidCallback saved = _submit(tester);
    saved();
    await swapFrames(tester);
    saved();
    expect(calls, 1);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.textContaining('completed'), findsNothing);
  });

  testWidgets('coverage suppresses a late original result across return', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final GlobalKey<_RunHarnessState> owner = GlobalKey<_RunHarnessState>();
    final Completer<SwapActionResult> original = Completer<SwapActionResult>();
    await tester.pumpWidget(
      swapHost(
        _RunHarness(
          key: owner,
          origin: fixture.origin,
          operation: () => original.future,
        ),
        navigator: navigator,
      ),
    );
    _submit(tester)();
    await tester.pump();
    final Future<void> cover = showDialog<void>(
      context: tester.element(find.byType(_RunHarness)),
      builder: (_) => const AlertDialog(content: Text('Fixture cover')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    original.complete(SwapActionResult(status: SwapActionStatus.submitted));
    await swapFrames(tester);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await cover;
    expect(owner.currentState!.shownResult, isNull);
    expect(
      identical(owner.currentState!.activeRun!.original, original.future),
      isTrue,
    );
    expect(find.text('Submitted'), findsNothing);
    expect(
      tester
          .widget<SwapPrimaryAction>(find.byKey(const Key('fixture_submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('an original result after disposal cannot repaint or navigate', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    final Completer<SwapActionResult> original = Completer<SwapActionResult>();
    await tester.pumpWidget(
      swapHost(
        _RunHarness(origin: fixture.origin, operation: () => original.future),
      ),
    );
    _submit(tester)();
    await tester.pumpWidget(const SizedBox.shrink());
    original.complete(SwapActionResult(status: SwapActionStatus.submitted));
    await swapFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(SwapPrimaryAction), findsNothing);
  });

  testWidgets('a changed input refuses the original clipboard read', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    final GlobalKey<_RunHarnessState> owner = GlobalKey<_RunHarnessState>();
    final Completer<Map<String, Object?>> clipboard =
        Completer<Map<String, Object?>>();
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(
            SystemChannels.platform,
            (MethodCall call) async =>
                call.method == 'Clipboard.getData' ? clipboard.future : null,
          );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      swapHost(
        _RunHarness(
          key: owner,
          origin: fixture.origin,
          operation: () async =>
              SwapActionResult(status: SwapActionStatus.refused),
        ),
      ),
    );
    tester
        .widget<OutlinedButton>(find.byKey(const Key('fixture_paste')))
        .onPressed!();
    owner.currentState!.input.text = 'Replacement input';
    clipboard.complete(<String, Object?>{'text': 'Original clipboard'});
    await swapFrames(tester);
    expect(owner.currentState!.input.text, 'Replacement input');
    expect(fixture.mutations, 0);
  });

  testWidgets('a stale clipboard callback cannot read or write the platform', (
    WidgetTester tester,
  ) async {
    prepareSwapViewport(tester);
    final SwapUiFixture fixture = SwapUiFixture();
    int requests = 0;
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method.startsWith('Clipboard.')) {
              requests++;
            }
            return null;
          });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      swapHost(
        _RunHarness(
          origin: fixture.origin,
          operation: () async =>
              SwapActionResult(status: SwapActionStatus.refused),
        ),
      ),
    );
    final VoidCallback paste = tester
        .widget<OutlinedButton>(find.byKey(const Key('fixture_paste')))
        .onPressed!;
    final VoidCallback copy = tester
        .widget<OutlinedButton>(find.byKey(const Key('fixture_copy')))
        .onPressed!;
    fixture.current = false;
    paste();
    copy();
    await swapFrames(tester);
    expect(requests, 0);
  });
}
