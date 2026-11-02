import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

import 'support.dart';

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
) async {
  for (int tick = 0; tick < 100 && !done(); tick++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'the synthetic boundary completes within 1 s');
}

Future<void> _observed(WidgetTester tester, Future<void> operation) async {
  bool done = false;
  Object? failure;
  StackTrace? stack;
  unawaited(
    operation.then<void>(
      (void _) {
        done = true;
      },
      onError: (Object error, StackTrace trace) {
        failure = error;
        stack = trace;
        done = true;
      },
    ),
  );
  await _until(tester, () => done);
  if (failure != null) {
    Error.throwWithStackTrace(failure!, stack!);
  }
}

TextButton _button(WidgetTester tester, String key) =>
    tester.widget<TextButton>(
      find
          .descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextButton),
          )
          .first,
    );

bool _focusWithin(WidgetTester tester, String key) {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  final Element target = tester.element(find.byKey(Key(key)));
  bool found = false;
  context.visitAncestorElements((Element parent) {
    found = identical(parent, target);
    return !found;
  });
  return found;
}

void main() {
  late FakeNodeSettingsSession source;
  late NodeSettingsPresenter presenter;
  late ValueNotifier<bool> shown;
  late ValueNotifier<int> scope;

  Future<void> open(
    WidgetTester tester, {
    bool light = false,
    bool rtl = false,
    double scale = 1,
    double width = 992,
    Future<bool> Function(NodeSettingsMismatch)? question,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        locale: rtl ? const Locale('ar') : const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 674,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: ValueListenableBuilder<bool>(
                  valueListenable: shown,
                  builder:
                      (BuildContext context, bool visible, Widget? child) =>
                          TickerMode(enabled: visible, child: child!),
                  child: ValueListenableBuilder<int>(
                    valueListenable: scope,
                    builder: (BuildContext context, int epoch, Widget? _) =>
                        NodeSettingsView(
                          presenter: presenter,
                          isCurrent: () => scope.value == epoch,
                          question: question,
                          embeddedNode: const Panel(
                            key: Key('fixture_updater'),
                            title: 'Embedded node',
                            shrinkWrap: true,
                            child: Text('Fixture updater'),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _until(tester, () => presenter.currentNetwork != null);
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await presenter.close();
    await tester.pump(const Duration(milliseconds: 250));
  }

  setUp(() {
    source = FakeNodeSettingsSession();
    presenter = nodePresenter(source);
    shown = ValueNotifier<bool>(true);
    scope = ValueNotifier<int>(0);
  });

  tearDown(() async {
    if (!presenter.isClosed) {
      await presenter.close();
    }
    shown.dispose();
    scope.dispose();
  });

  for (final bool light in <bool>[false, true]) {
    for (final bool rtl in <bool>[false, true]) {
      testWidgets('one measured stack, light $light RTL $rtl', (
        WidgetTester tester,
      ) async {
        await open(tester, light: light, rtl: rtl);
        final Rect nodes = tester.getRect(
          find.byKey(const Key('node_settings_nodes')),
        );
        final Rect updater = tester.getRect(
          find.byKey(const Key('fixture_updater')),
        );
        final Rect chain = tester.getRect(
          find.byKey(const Key('node_settings_chain_card')),
        );
        final Rect peers = tester.getRect(
          find.byKey(const Key('node_settings_peers_card')),
        );
        final Rect sporks = tester.getRect(
          find.byKey(const Key('node_settings_sporks_gate')),
        );
        expect(nodes.width, 992);
        expect(updater.width, nodes.width);
        expect(updater.top - nodes.bottom, 12);
        expect(chain.top - updater.bottom, 12);
        expect(peers.top - chain.bottom, 12);
        expect(sporks.top - peers.bottom, 12);
        expect(find.text('3'), findsOneWidget);
        expect(find.textContaining('Confirm'), findsNothing);
        expect(
          find.byKey(const Key('node_settings_client_chain')).hitTestable(),
          findsNothing,
        );
        expect(find.text('9 ms'), findsNothing);
        expect(find.text('41 ms'), findsNothing);
        expect(find.text('Chain 321'), findsNothing);
        expect(source.calls, <String>['network:$embeddedNode']);
        expect(tester.takeException(), isNull);
        await close(tester);
      });

      testWidgets('scaled keyboard form, light $light RTL $rtl', (
        WidgetTester tester,
      ) async {
        await open(tester, light: light, rtl: rtl, scale: 1.75, width: 500);
        await tester.tap(find.byKey(const Key('node_settings_add')));
        await tester.pump(const Duration(milliseconds: 250));
        final Finder endpoint = find.byKey(const Key('node_settings_endpoint'));
        await tester.ensureVisible(endpoint);
        await tester.tap(endpoint);
        await tester.enterText(endpoint, 'wss://new.example:35998');
        await tester.pump();
        expect(
          _button(tester, 'node_settings_endpoint_save').onPressed,
          isNotNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_focusWithin(tester, 'node_settings_endpoint_save'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _until(tester, () => source.calls.contains('notice:added'));
        expect(
          source.calls.where((String call) => call.startsWith('connect:')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }
  }

  testWidgets('old radio and Add refuse after visibility reversal', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final ValueChanged<String?> oldRadio = tester
        .widget<RadioGroup<String>>(
          find.byKey(const Key('node_settings_choices')),
        )
        .onChanged;
    final VoidCallback oldAdd = _button(tester, 'node_settings_add').onPressed!;
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    oldRadio(remoteNode);
    oldAdd();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      source.calls.where((String call) => call.startsWith('connect:')),
      isEmpty,
    );
    expect(
      find.byKey(const Key('node_settings_endpoint')).hitTestable(),
      findsNothing,
    );
    await close(tester);
  });

  testWidgets('new section closures cannot revive old work', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final Completer<void> gate = Completer<void>();
    source.gates['connect:$remoteNode'] = gate;
    await tester.tap(
      find.byKey(const ValueKey<String>('node_settings_select_$remoteNode')),
    );
    await _until(tester, () => source.calls.contains('connect:$remoteNode'));
    scope.value++;
    await tester.pump();
    gate.complete();
    await _until(tester, () => !presenter.state.busy);
    expect(source.calls, isNot(contains('announce')));
    expect(source.calls, isNot(contains('callback')));
    expect(source.connected, source.selected);
    expect(source.transitionHeld, isFalse);
    await close(tester);
  });

  testWidgets('replacement presenter refuses old callbacks', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final VoidCallback oldAdd = _button(tester, 'node_settings_add').onPressed!;
    final ValueChanged<String?> oldRadio = tester
        .widget<RadioGroup<String>>(
          find.byKey(const Key('node_settings_choices')),
        )
        .onChanged;
    final NodeSettingsPresenter original = presenter;
    source = FakeNodeSettingsSession();
    presenter = nodePresenter(source);
    scope.value++;
    await tester.pump();
    oldAdd();
    oldRadio(remoteNode);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      source.calls.where((String call) => call.startsWith('connect:')),
      isEmpty,
    );
    expect(
      find.byKey(const Key('node_settings_endpoint')).hitTestable(),
      findsNothing,
    );
    await original.close();
    await close(tester);
  });

  testWidgets('deferred mismatch keeps the original signing chain', (
    WidgetTester tester,
  ) async {
    final Completer<bool> answer = Completer<bool>();
    NodeSettingsMismatch? asked;
    await open(
      tester,
      question: (NodeSettingsMismatch mismatch) {
        asked = mismatch;
        return answer.future;
      },
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('node_settings_select_$customNode')),
    );
    await _until(tester, () => asked != null);
    expect(asked?.node, customNode);
    expect(asked?.clientChain, 1);
    expect(presenter.state.busy, isTrue);
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    answer.complete(true);
    await _until(tester, () => !presenter.state.busy);
    expect(source.signingChain, 1);
    expect(source.calls, isNot(contains('announce')));
    expect(source.connected, source.selected);
    expect(source.transitionHeld, isFalse);
    await close(tester);
  });

  testWidgets('saved Delete callbacks reserve one owned question', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final Finder control = find.descendant(
      of: find.byKey(
        const ValueKey<String>('node_settings_delete_$customNode'),
      ),
      matching: find.byType(IconButton),
    );
    final VoidCallback remove = tester.widget<IconButton>(control).onPressed!;
    remove();
    remove();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(DialogCard), findsOneWidget);
    expect(
      find.byKey(const Key('node_settings_question_cancel')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('node_settings_question_cancel')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(DialogCard), findsNothing);
    final NavigatorState navigator = Navigator.of(
      tester.element(find.byKey(const Key('node_settings_page'))),
    );
    expect(navigator.canPop(), isFalse, reason: 'no orphan question remains');
    expect(source.calls, isNot(contains('catalog')));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('saved mismatch acceptance refuses after exit', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('node_settings_select_$customNode'),
      ),
    );
    await _until(
      tester,
      () => find
          .byKey(
            const Key('node_settings_question_accept'),
          )
          .evaluate()
          .isNotEmpty,
    );
    final VoidCallback accept = tester
        .widget<TextButton>(
          find.byKey(const Key('node_settings_question_accept')),
        )
        .onPressed!;
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    accept();
    await _until(tester, () => !presenter.state.busy);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(DialogCard), findsNothing);
    expect(source.calls, isNot(contains('announce')));
    expect(source.calls, isNot(contains('callback')));
    expect(source.connected, source.selected);
    expect(source.transitionHeld, isFalse);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('similar valid endpoints never share a selected identity', (
    WidgetTester tester,
  ) async {
    await presenter.close();
    source = FakeNodeSettingsSession(origin: remoteNode);
    const String prefix = 'wss://node.example:3599';
    presenter = NodeSettingsPresenter(
      initial: NodeSettingsState(
        entries: const <NodeSettingsEntry>[
          NodeSettingsEntry(node: remoteNode, endpoint: remoteNode),
          NodeSettingsEntry(node: prefix, endpoint: prefix),
        ],
        activeNode: remoteNode,
        clientChain: 1,
      ),
      capture: () => source,
    );
    await open(tester);
    final Radio<String> active = tester.widget<Radio<String>>(
      find.byKey(
        const ValueKey<String>('node_settings_select_$remoteNode'),
      ),
    );
    final Radio<String> other = tester.widget<Radio<String>>(
      find.byKey(
        const ValueKey<String>('node_settings_select_$prefix'),
      ),
    );
    final RadioGroup<String> choices = tester.widget<RadioGroup<String>>(
      find.byKey(const Key('node_settings_choices')),
    );
    expect(choices.groupValue, active.value);
    expect(choices.groupValue, isNot(other.value));
    expect(presenter.currentNetwork?.node, remoteNode);
    expect(presenter.currentNetwork?.synced, isTrue);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('node_settings_row_$remoteNode'),
        ),
        matching: find.text('Connected'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('node_settings_row_$prefix'),
        ),
        matching: find.text('Not checked'),
      ),
      findsOneWidget,
    );
    expect(source.calls, <String>['network:$remoteNode']);
    await close(tester);
  });

  testWidgets('an old node form cannot clear a newer draft', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('node_settings_add')));
    await tester.pump(const Duration(milliseconds: 250));
    final Finder input = find.byKey(const Key('node_settings_endpoint'));
    await tester.enterText(input, 'wss://original.example:35998');
    await tester.pump();
    expect(
      _button(tester, 'node_settings_endpoint_save').onPressed,
      isNotNull,
    );
    final Completer<void> gate = Completer<void>();
    source.gates['catalog'] = gate;
    final VoidCallback save = _button(
      tester,
      'node_settings_endpoint_save',
    ).onPressed!;
    save();
    await _until(tester, () => source.calls.contains('catalog'));
    _button(tester, 'node_settings_endpoint_cancel').onPressed!();
    await tester.pump(const Duration(milliseconds: 100));
    gate.complete();
    await _until(tester, () => !presenter.state.busy);
    await tester.tap(find.byKey(const Key('node_settings_add')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(input, 'wss://newer.example:35998');
    expect(
      tester.widget<TextField>(input).controller?.text,
      'wss://newer.example:35998',
    );
    expect(source.calls, isNot(contains('notice:added')));
    expect(
      source.calls.where((String call) => call.startsWith('connect:')),
      isEmpty,
    );
    await close(tester);
  });

  testWidgets('chain disclosure reverses and retains its draft', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final Finder toggle = find.byKey(const Key('node_settings_chain_toggle'));
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 250));
    final Finder input = find.byKey(const Key('node_settings_client_chain'));
    await tester.enterText(input, '321');
    await tester.pump();
    expect(
      _button(tester, 'node_settings_chain_save').onPressed,
      isNotNull,
    );
    final VoidCallback stale = _button(
      tester,
      'node_settings_chain_save',
    ).onPressed!;
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 60));
    stale();
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<TextField>(input).controller?.text, '321');
    expect(
      source.calls.where((String call) => call.startsWith('saveChain:')),
      isEmpty,
    );
    expect(source.signingChain, 1);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Sporks refuses pointer and semantic activation', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final SemanticsHandle semantics = tester.ensureSemantics();
    final Finder gate = find.byKey(const Key('node_settings_sporks_gate'));
    try {
      await tester.ensureVisible(gate);
      await tester.pump();
      expect(tester.widget<SeamGate>(gate).seam, Seam.sporks);
      final Finder tooltip = find.descendant(
        of: gate,
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsOneWidget);
      expect(tester.widget<Tooltip>(tooltip).message, 'Not yet');
      final SemanticsNode node = find.semantics
          .byLabel('Not yet')
          .evaluate()
          .single;
      expect(node.attached, isTrue);
      expect(
        node,
        isSemantics(
          label: 'Not yet',
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      expect(find.semantics.byLabel('Sporks'), findsNothing);
      expect(
        node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.tap(gate);
      await tester.pump(const Duration(milliseconds: 250));
      expect(source.calls, <String>['network:$embeddedNode']);
      expect(presenter.state.busy, isFalse);
    } finally {
      semantics.dispose();
    }
    await close(tester);
  });

  testWidgets('zero peers and unknown results remain distinct', (
    WidgetTester tester,
  ) async {
    source.peers = <NodeSettingsPeer>[];
    await open(tester);
    await tester.tap(find.byKey(const Key('node_settings_peers_toggle')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('None yet'), findsOneWidget);
    source.peers = null;
    await _observed(tester, presenter.refresh());
    expect(find.text('None yet'), findsNothing);
    expect(find.text('Not checked'), findsWidgets);
    await close(tester);
  });
}
