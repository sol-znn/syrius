import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/fixtures/seed_policy.dart';

const String _owner = 'owned-sender';

Future<T> _drive<T>(WidgetTester tester, Future<T> command) async {
  bool done = false;
  T? result;
  Object? error;
  StackTrace? trace;
  unawaited(command.then((T value) {
    result = value;
    done = true;
  }, onError: (Object value, StackTrace stack) {
    error = value;
    trace = stack;
    done = true;
  }));
  for (int frame = 0; frame < 80 && !done; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'The original sender input must settle');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return result as T;
}

class _Fixture {
  final HarnessAgent agent = HarnessAgent.forTest();
  final List<String> selected = <String>[];
  final List<bool> readyAtItemDown = <bool>[];
  bool current = true;
  bool revokeAtItemDown = false;
  int cancelled = 0;

  void requireCurrent() {
    if (!current) {
      throw const SeedRefused('original-lab-send-context-changed');
    }
  }

  Future<void> mount(WidgetTester tester, {
    bool light = false,
    Duration? opening,
    bool duplicate = false,
    bool enabled = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
    });
    await tester.pumpWidget(MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      builder: (_, Widget? child) => Listener(
        onPointerDown: (_) {
          final List<Element> items = find.byType(PopupMenuItem<String>)
              .evaluate().where((Element element) =>
                (element.widget as PopupMenuItem<String>).value == _owner)
              .toList();
          if (items.isNotEmpty) {
            readyAtItemDown.add(
              ModalRoute.of(items.first)?.animation?.isCompleted == true,
            );
            if (revokeAtItemDown) current = false;
          }
        },
        onPointerCancel: (_) => cancelled++,
        child: child,
      ),
      home: Scaffold(body: Center(child: PopupMenuButton<String>(
        key: const Key('transfer_sender'),
        initialValue: 'other-sender',
        popUpAnimationStyle: opening == null ? null :
          AnimationStyle(duration: opening),
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'other-sender', child: Text('Sender'),
          ),
          PopupMenuItem<String>(
            value: _owner, enabled: enabled, child: const Text('Sender'),
          ),
          if (duplicate) const PopupMenuItem<String>(
            value: _owner, child: Text('Sender'),
          ),
        ],
        onSelected: selected.add,
        child: const SizedBox(width: 180, height: 48, child: Text('Sender')),
      ))),
    ));
    await tester.pump();
  }

  Future<void> select() => agent.selectLabSenderForTest(_owner, requireCurrent);
}

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'typed sender value selects once despite identical labels $light',
        (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await fixture.mount(tester, light: light);
      await _drive(tester, fixture.select());
      expect(fixture.selected, <String>[_owner]);
      expect(fixture.readyAtItemDown, <bool>[true]);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(fixture.cancelled, 0);
    });
  }

  testWidgets('sender entry waits for its original opening animation',
      (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await fixture.mount(tester, opening: const Duration(milliseconds: 1100));
    await _drive(tester, fixture.select());
    expect(fixture.selected, <String>[_owner]);
    expect(fixture.readyAtItemDown, <bool>[true]);
    expect(fixture.cancelled, 0);
  });

  testWidgets('ambiguous owner entries cannot select a sender',
      (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await fixture.mount(tester, duplicate: true);
    await expectLater(_drive(tester, fixture.select()), throwsA(
      isA<SeedRefused>().having((SeedRefused value) => value.code, 'code',
        'original-lab-sender-choice-ambiguous'),
    ));
    expect(fixture.selected, isEmpty);
    expect(fixture.readyAtItemDown, isEmpty);
  });

  testWidgets('a disabled owner entry cannot select a sender',
      (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await fixture.mount(tester, enabled: false);
    await expectLater(_drive(tester, fixture.select()), throwsA(
      isA<SeedRefused>().having((SeedRefused value) => value.code, 'code',
        'original-lab-sender-choice-required'),
    ));
    expect(fixture.selected, isEmpty);
    expect(fixture.readyAtItemDown, isEmpty);
  });

  testWidgets('original owner loss between pointer down and up cancels input',
      (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..revokeAtItemDown = true;
    await fixture.mount(tester);
    await expectLater(_drive(tester, fixture.select()), throwsA(
      isA<SeedRefused>().having((SeedRefused value) => value.code, 'code',
        'original-lab-send-context-changed'),
    ));
    expect(fixture.selected, isEmpty);
    expect(fixture.readyAtItemDown, <bool>[true]);
    expect(fixture.cancelled, 1);
  });
}
