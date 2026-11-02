import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/bell_panel.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

import '../../harness/app/agent.dart';
import '../shell/bell/support.dart' as bell_fixture;
import '../welcome/support.dart';

Future<void> _mount(
  WidgetTester tester, {
  required bool collapsed,
  required bool locked,
  required ValueChanged<Tabs> onSelected,
  Tabs selected = Tabs.dashboard,
  BellController? bell,
  bool light = false,
  Size size = const Size(1280, 780),
  Widget page = const SizedBox.expand(),
}) async {
  prepareWelcomeViewport(tester, size: size);
  final RailCollapse collapse = RailCollapse()
    ..setCollapsed(collapsed: collapsed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    collapse.dispose();
  });
  await tester.pumpWidget(
    welcomeHost(
      Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Builder(
              builder: (BuildContext context) => ShellRail(
                collapse: collapse,
                selected: selected,
                locked: locked,
                onSelected: onSelected,
                onNotifications: bell == null ? null : () => unawaited(
                  showBellPanel(context: context, controller: bell),
                ),
              ),
            ),
            Expanded(child: page),
          ],
        ),
      ),
      light: light,
      size: size,
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<T> _driveHarness<T>(WidgetTester tester, Future<T> command) async {
  bool done = false;
  T? result;
  Object? failure;
  StackTrace? trace;
  unawaited(command.then((T value) {
    result = value;
    done = true;
  }, onError: (Object error, StackTrace stack) {
    failure = error;
    trace = stack;
    done = true;
  }));
  for (int i = 0; i < 160 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'the original pointer command did not finish');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result as T;
}

Future<List<Map<String, Object?>>> _controls(HarnessAgent agent) async {
  final Map<String, Object?> view = await agent.commandForTest(
    <String, dynamic>{'cmd': 'wallet-recipe', 'action': 'observe'},
  );
  return view['controls']! as List<Map<String, Object?>>;
}

void main() {
  for (final bool collapsed in <bool>[true, false]) {
    testWidgets('the real bell retains the selected rail page $collapsed', (
      WidgetTester tester,
    ) async {
      final bell_fixture.MemoryBellHistory history =
          bell_fixture.MemoryBellHistory();
      final BellController controller = bell_fixture.bell(history)
        ..setPrivate(value: false);
      final List<Tabs> selected = <Tabs>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        bool finished = false;
        final Future<void> closing = controller.close().whenComplete(
          () => finished = true,
        );
        for (int turn = 0; turn < 20 && !finished; turn++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
        }
        expect(finished, isTrue);
        await closing;
        await history.close();
      });
      await _mount(tester, collapsed: collapsed, locked: false,
        selected: Tabs.accelerator, bell: controller, onSelected: selected.add);
      await tester.tap(find.byKey(const Key('nav_notifications')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('bell_panel')).hitTestable(), findsOneWidget);
      expect(tester.widget<ShellRail>(find.byType(ShellRail)).selected,
        Tabs.accelerator);
      expect(selected, isEmpty);
      await tester.tap(find.byKey(const Key('bell_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('bell_panel')), findsNothing);
      expect(selected, isEmpty);
    });
  }

  for (final bool collapsed in <bool>[true, false]) {
    testWidgets('the real rail exposes reachable navigation $collapsed', (
      WidgetTester tester,
    ) async {
      final List<Tabs> opened = <Tabs>[];
      await _mount(
        tester,
        collapsed: collapsed,
        locked: false,
        onSelected: opened.add,
      );
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      final List<Map<String, Object?>> controls = await _controls(agent);
      final Map<String, Object?> tree = await agent.commandForTest(
        <String, dynamic>{'cmd': 'tree'},
      );
      final List<Map<String, Object?>> nodes =
          tree['nodes']! as List<Map<String, Object?>>;
      final Map<String, Object?> toggle = nodes.singleWhere(
        (Map<String, Object?> row) => row['key'] == 'rail_toggle',
      );
      expect(toggle['kind'], 'button');
      final List<int> rect = List<int>.from(toggle['rect']! as List<Object?>);
      expect(rect.sublist(2), <int>[if (collapsed) 40 else 184, 32]);
      expect(nodes.where((Map<String, Object?> row) =>
          row['key'] == 'rail_label_dashboard'), isEmpty);
      expect(find.byKey(const ValueKey<String>('rail_label_dashboard')),
          collapsed ? findsNothing : findsOneWidget);
      for (final String key in <String>['nav_dashboard', 'nav_settings']) {
        expect(
          tester.widget<Widget>(find.byKey(ValueKey<String>(key))),
          isA<InkWell>(),
        );
        final List<Map<String, Object?>> matches = controls.where(
          (Map<String, Object?> row) => row['key'] == key,
        ).toList();
        expect(matches, hasLength(1));
        expect(matches.single['enabled'], isTrue);
      }
      Map<String, Object?>? reply;
      Object? error;
      final Future<void> tapped = agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'key': 'nav_settings', 'settleMs': 0,
      }).then<void>(
        (Map<String, Object?> value) {
          reply = value;
        },
        onError: (Object value) {
          error = value;
        },
      );
      for (int frame = 0;
          frame < 8 && reply == null && error == null;
          frame++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(error, isNull);
      expect(reply, isNotNull);
      await tapped;
      final Map<String, Object?> target =
          reply!['target']! as Map<String, Object?>;
      expect(target['key'], 'nav_settings');
      expect(target['kind'], 'button');
      expect(target['tab'], 'settings');
      expect(opened, <Tabs>[Tabs.settings]);
      if (collapsed) {
        for (final bool light in <bool>[false, true]) {
          for (final Size size in <Size>[
            const Size(1280, 780), const Size(1200, 600),
          ]) {
            await _mount(tester, collapsed: true, locked: false,
              light: light, size: size, onSelected: opened.add);
            await _driveHarness(tester, agent.commandForTest(<String, dynamic>{
              'cmd': 'hover', 'at': <int>[0, 0], 'settleMs': 0,
            }));
            await _driveHarness(tester, agent.commandForTest(<String, dynamic>{
              'cmd': 'hover', 'key': 'nav_notifications',
            }));
            await tester.pump(const Duration(milliseconds: 1000));
            final Finder painted = find.byWidgetPredicate((Widget widget) =>
                widget is RichText && widget.text.toPlainText(
                  includeSemanticsLabels: false) == 'Notifications');
            expect(painted, findsOneWidget);
            final RichText tooltip = tester.widget<RichText>(painted);
            // Reproduce the parent's actual extraction on the rendered span.
            expect(tooltip.text.toPlainText(),
                'NotificationsNotifications');
            final Map<String, Object?> observed = await agent.commandForTest(
              <String, dynamic>{'cmd': 'tree'},
            );
            final List<Map<String, Object?>> rows =
                observed['nodes']! as List<Map<String, Object?>>;
            expect(rows.where((Map<String, Object?> row) =>
                row['kind'] == 'text' && row['label'] == 'Notifications'),
                hasLength(1));
            await _driveHarness(tester, agent.commandForTest(<String, dynamic>{
              'cmd': 'wait', 'text': 'Notifications', 'kind': 'text',
              'exact': true, 'timeoutMs': 5000,
            }));
            expect(find.byKey(const Key('bell_panel')), findsNothing);
            expect(opened, <Tabs>[Tabs.settings]);
          }
        }
        await _mount(tester, collapsed: true, locked: false,
          onSelected: opened.add, page: const Column(children: <Widget>[
            Text('ordinary', key: Key('label_plain')),
            Text.rich(TextSpan(text: 'leaf', semanticsLabel: 'spoken leaf'),
              key: Key('label_leaf')),
            Text.rich(TextSpan(text: '', children: <InlineSpan>[
              TextSpan(text: 'nested'),
            ]), key: Key('label_nested')),
            Text.rich(TextSpan(text: 'prefix', semanticsLabel: 'spoken prefix',
              children: <InlineSpan>[TextSpan(text: ' child')]),
              key: Key('label_prefix')),
          ]));
        final Map<String, Object?> originalKinds = await agent.commandForTest(
          <String, dynamic>{'cmd': 'tree'},
        );
        final List<Map<String, Object?>> rows =
            originalKinds['nodes']! as List<Map<String, Object?>>;
        for (final MapEntry<String, String> value in <String, String>{
          'label_plain': 'ordinary', 'label_leaf': 'spoken leaf',
          'label_nested': 'nested', 'label_prefix': 'spoken prefix child',
        }.entries) {
          expect(rows.singleWhere((Map<String, Object?> row) =>
              row['key'] == value.key)['label'], value.value);
        }
      }
    });
  }

  testWidgets('a locked real rail refuses navigation without a callback', (
    WidgetTester tester,
  ) async {
    final List<Tabs> opened = <Tabs>[];
    await _mount(
      tester,
      collapsed: true,
      locked: true,
      onSelected: opened.add,
    );
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    final List<Map<String, Object?>> controls = await _controls(agent);
    expect(
      controls.where((Map<String, Object?> row) =>
          row['key'] == 'nav_settings' && row['enabled'] == true),
      isEmpty,
    );
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'key': 'nav_settings', 'settleMs': 0,
      }),
      throwsA(isA<HarnessError>()),
    );
    expect(opened, isEmpty);
  });
}
