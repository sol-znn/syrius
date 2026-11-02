import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/cubit/send_draft_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/rise_switcher.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_view.dart';

import '../../harness/app/agent.dart';
import '../settings_addresses_redesign/support.dart';
import '../welcome/support.dart';

void main() {
  for (final bool revoked in <bool>[false, true]) {
    testWidgets('the original address choice retains its owner $revoked', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      final AddressesFixture source = AddressesFixture();
      final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
        binding: source.bind(),
      );
      final SendDraftCubit draft = SendDraftCubit();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await presenter.close();
        await draft.close();
      });
      await tester.pumpWidget(welcomeHost(Scaffold(
        body: Center(child: SizedBox(width: 1000, height: 650,
          child: AddressesSettingsView(presenter: presenter, draft: draft,
            isCurrent: source.captureView()),
        )),
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final Finder choice = find.byKey(ValueKey<String>(
        'addresses_select_${source.members[1]}',
      ));
      final IconButton original = tester.widget<IconButton>(choice);
      expect(original.onPressed, isNotNull);
      expect(tester.widget<IconButton>(find.byKey(ValueKey<String>(
        'addresses_select_${source.members[0]}',
      ))).onPressed, isNull);
      if (revoked) {
        source.leaveAndReturn();
        original.onPressed!();
      } else {
        await tester.tap(choice);
      }
      await tester.pump();
      expect(source.selections,
        revoked ? isEmpty : <String>[source.members[1]]);
      expect(tester.takeException(), isNull);
    });
  }
  for (final AddressesInputGate gate in <AddressesInputGate>[
    AddressesInputGate.section,
    AddressesInputGate.focus,
    AddressesInputGate.window,
  ]) {
    testWidgets('painted input snapshot retains the original $gate guard', (
      WidgetTester tester,
    ) async {
      prepareWelcomeViewport(tester);
      final AddressesFixture source = AddressesFixture();
      int captures = 0;
      source.generationCapture = (_) { captures++; return null; };
      final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
        binding: source.bind(),
      );
      final Object? binding = presenter.binding;
      final SendDraftCubit draft = SendDraftCubit();
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      bool section = true;
      bool focusable = true;
      int currentReads = 0;
      bool isCurrent() { currentReads++; return section; }
      late StateSetter rebuild;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await presenter.close();
        await draft.close();
      });
      await tester.pumpWidget(welcomeHost(StatefulBuilder(
        builder: (BuildContext context, StateSetter update) {
          rebuild = update;
          return Scaffold(body: Center(child: SizedBox(width: 1000, height: 650,
            child: Focus(descendantsAreFocusable: focusable,
              child: AddressesSettingsView(presenter: presenter, draft: draft,
                isCurrent: isCurrent),
            ),
          )));
        },
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final Finder view = find.byType(AddressesSettingsView);
      final Object originalState = tester.state(view);
      final AddressesInputSource snapshot =
          originalState as AddressesInputSource;
      final Finder add = find.byKey(const Key('settings_add_address'));
      final VoidCallback oldAction =
          tester.widget<OutlinedButton>(add).onPressed!;
      expect(snapshot.paintedInputGate, AddressesInputGate.ready);
      final int reads = currentReads;
      for (int count = 0; count < 12; count++) {
        expect(snapshot.paintedInputGate, AddressesInputGate.ready);
      }
      expect(currentReads, reads);
      if (gate == AddressesInputGate.window) {
        (originalState as WidgetsBindingObserver)
            .didChangeAppLifecycleState(AppLifecycleState.inactive);
      } else {
        rebuild(() {
          if (gate == AddressesInputGate.section) section = false;
          if (gate == AddressesInputGate.focus) focusable = false;
        });
      }
      await tester.pump();
      expect(tester.state(view), same(originalState));
      expect(presenter.binding, same(binding));
      expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
      expect(snapshot.paintedInputGate, gate);
      final int blockedReads = currentReads;
      final Map<String, Object?> observed = await agent.commandForTest(
        <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
      );
      final List<Map<String, Object?>> controls =
          observed['controls']! as List<Map<String, Object?>>;
      final Map<String, Object?> control = controls.singleWhere(
        (Map<String, Object?> value) => value['key'] == 'settings_add_address',
      );
      expect(control['enabled'], isFalse);
      expect(control['blockedBy'], 'widget');
      expect(control['inputGate'], gate.name);
      expect(currentReads, blockedReads);
      oldAction();
      await tester.pump();
      expect(captures, 0);
      if (gate == AddressesInputGate.window) {
        (originalState as WidgetsBindingObserver)
            .didChangeAppLifecycleState(AppLifecycleState.resumed);
      } else {
        rebuild(() { section = true; focusable = true; });
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.state(view), same(originalState));
      expect(presenter.binding, same(binding));
      expect(snapshot.paintedInputGate, AddressesInputGate.ready);
      expect(tester.widget<OutlinedButton>(add).onPressed, isNotNull);
      oldAction();
      await tester.pump();
      expect(captures, 0);
      await tester.tap(add);
      await tester.pump();
      expect(captures, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nested page arrival restores original address input', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final AddressesFixture source = AddressesFixture();
    int captures = 0;
    source.generationCapture = (_) { captures++; return null; };
    final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
      binding: source.bind(),
    );
    final Object? binding = presenter.binding;
    final SendDraftCubit draft = SendDraftCubit();
    late StateSetter navigate;
    int page = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await presenter.close();
      await draft.close();
    });
    await tester.pumpWidget(welcomeHost(Scaffold(
      body: Center(child: SizedBox(width: 1000, height: 650,
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter update) {
            navigate = update;
            return RiseSwitcher(child: KeyedSubtree(
              key: ValueKey<int>(page),
              child: page == 0 ? const SizedBox.expand() : RiseSwitcher(
                child: AddressesSettingsView(presenter: presenter, draft: draft,
                  isCurrent: () => page == 1),
              ),
            ));
          },
        ),
      )),
    )));
    navigate(() => page = 1);
    await tester.pump();
    final Finder view = find.byType(AddressesSettingsView);
    final Object original = tester.state(view);
    final AddressesInputSource snapshot = original as AddressesInputSource;
    final Finder add = find.byKey(const Key('settings_add_address'));
    expect(snapshot.paintedInputGate, AddressesInputGate.focus);
    expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
    expect(captures, 0);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.state(view), same(original));
    expect(presenter.binding, same(binding));
    expect(snapshot.paintedInputGate, AddressesInputGate.ready);
    expect(tester.widget<OutlinedButton>(add).onPressed, isNotNull);
    await tester.tap(add);
    await tester.pump();
    expect(captures, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outer focus keeps old address callbacks revoked', (
    WidgetTester tester,
  ) async {
    prepareWelcomeViewport(tester);
    final AddressesFixture source = AddressesFixture();
    int captures = 0;
    source.generationCapture = (_) { captures++; return null; };
    final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
      binding: source.bind(),
    );
    final Object? binding = presenter.binding;
    final SendDraftCubit draft = SendDraftCubit();
    final FocusNode outer = FocusNode();
    final FocusNode inner = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      outer.dispose();
      inner.dispose();
      await presenter.close();
      await draft.close();
    });
    await tester.pumpWidget(welcomeHost(Scaffold(
      body: Center(child: SizedBox(width: 1000, height: 650,
        child: Focus.withExternalFocusNode(focusNode: outer,
          child: Focus.withExternalFocusNode(focusNode: inner,
            child: AddressesSettingsView(presenter: presenter, draft: draft,
              isCurrent: source.captureView()),
          ),
        ),
      )),
    )));
    await tester.pump();
    final Finder view = find.byType(AddressesSettingsView);
    final Object original = tester.state(view);
    final AddressesInputSource snapshot = original as AddressesInputSource;
    final Finder add = find.byKey(const Key('settings_add_address'));
    final VoidCallback old = tester.widget<OutlinedButton>(add).onPressed!;
    outer.descendantsAreFocusable = false;
    old();
    expect(captures, 0);
    // The node notification queues the visibility refresh and its next paint.
    await tester.pump();
    await tester.pump();
    expect(inner.descendantsAreFocusable, isTrue);
    expect(snapshot.paintedInputGate, AddressesInputGate.focus);
    expect(tester.widget<OutlinedButton>(add).onPressed, isNull);
    old();
    expect(captures, 0);
    outer.descendantsAreFocusable = true;
    await tester.pump();
    await tester.pump();
    expect(tester.state(view), same(original));
    expect(presenter.binding, same(binding));
    expect(snapshot.paintedInputGate, AddressesInputGate.ready);
    old();
    expect(captures, 0);
    final VoidCallback returning =
        tester.widget<OutlinedButton>(add).onPressed!;
    outer.descendantsAreFocusable = false;
    FocusManager.instance.applyFocusChangesIfNeeded();
    outer.descendantsAreFocusable = true;
    FocusManager.instance.applyFocusChangesIfNeeded();
    await tester.pump();
    await tester.pump();
    returning();
    expect(captures, 0);
    await tester.tap(add);
    await tester.pump();
    expect(captures, 1);
    expect(tester.takeException(), isNull);
  });
}
