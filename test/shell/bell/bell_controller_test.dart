import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';

import 'support.dart';

void main() {
  late MemoryBellHistory history;

  setUp(() => history = MemoryBellHistory());
  tearDown(() => history.close());

  test('a stored snapshot stays private and never replays a toast', () async {
    history.items[0] = event();
    final BellController controller = bell(history);
    final List<BellRecord> toasts = <BellRecord>[];
    final StreamSubscription<BellRecord> subscription = controller.toasts
        .listen(
          toasts.add,
        );
    expect(controller.state.records, isEmpty);
    expect(controller.hasUnseen.value, isFalse);
    controller.setPrivate(value: false);
    expect(controller.state.records, hasLength(1));
    expect(controller.hasUnseen.value, isTrue);
    expect(toasts, isEmpty);
    controller.refresh();
    expect(toasts, isEmpty);
    await subscription.cancel();
    await controller.close();
  });

  test(
    'duplicate timestamps retain their original keys and delete one row',
    () async {
      history.items[7] = event(title: 'First', timestamp: 10);
      history.items['7'] = event(title: 'Second', timestamp: 10);
      final BellController controller = bell(history)..setPrivate(value: false);
      final BellRecord first = controller.state.records.last;
      expect(
        controller.state.records.map((BellRecord r) => r.identity).toSet(),
        hasLength(2),
      );
      await controller.removeRecords(<BellRecord>[first]);
      expect(history.items.keys, <Object>['7']);
      expect(controller.state.records.single.notification.title, 'Second');
      await controller.close();
    },
  );

  test('seen state persists only in its wallet and chain scope', () async {
    final Map<String, List<String>> seen = <String, List<String>>{};
    history.items[0] = event();
    BellController controller = bell(history, seen: seen)
      ..setPrivate(value: false);
    controller.markSeen(controller.state.identities);
    expect(controller.hasUnseen.value, isFalse);
    await controller.close();
    controller = bell(history, seen: seen)..setPrivate(value: false);
    expect(controller.hasUnseen.value, isFalse);
    await controller.close();
    controller = bell(history, seen: seen, scope: '2:wallet-a')
      ..setPrivate(value: false);
    expect(controller.hasUnseen.value, isTrue);
    await controller.close();
  });

  test('a key overwritten with a different payload is unseen again', () async {
    history.items[0] = event(title: 'Earlier', timestamp: 10);
    final BellController controller = bell(history)..setPrivate(value: false);
    final BellRecord earlier = controller.state.records.single;
    controller.markSeen(controller.state.identities);
    history.put(0, event(title: 'Replacement', timestamp: 10));
    expect(controller.hasUnseen.value, isTrue);
    await controller.removeRecords(<BellRecord>[earlier]);
    expect(history.items[0]?.title, 'Replacement');
    await controller.close();
  });

  test('only a fresh visible insertion emits a toast', () async {
    final BellController controller = bell(history);
    final List<BellRecord> toasts = <BellRecord>[];
    final StreamSubscription<BellRecord> subscription = controller.toasts
        .listen(
          toasts.add,
        );
    history.put(0, event(title: 'Private'));
    controller.setPrivate(value: false);
    history
      ..put(1, event(title: 'Visible'))
      ..put(2, event(title: 'Other wallet', scope: '1:wallet-b'));
    expect(toasts.map((BellRecord r) => r.notification.title), <String>[
      'Visible',
    ]);
    controller.setPrivate(value: true);
    expect(controller.state.records, isEmpty);
    expect(controller.hasUnseen.value, isFalse);
    await subscription.cancel();
    await controller.close();
  });

  test(
    'clear preserves a concurrent new event and pending decisions',
    () async {
      final FakeApprovalClient client = FakeApprovalClient()..add(1);
      history.items[0] = event();
      final BellController controller = bell(
        history,
        approvals: client.controller,
      )..setPrivate(value: false);
      history.beforeDelete = () =>
          history.put(1, event(title: 'Arrived later'));
      await controller.clearHistory();
      expect(history.items.keys, <Object>[1]);
      expect(client.controller.value, hasLength(1));
      expect(client.approveCalls + client.declineCalls, 0);
      await controller.close();
      client.controller.dispose();
    },
  );

  test('a failed read is distinct from an empty history', () async {
    history.failRead = true;
    final BellController controller = bell(history)..setPrivate(value: false);
    expect(controller.state.historyFailed, isTrue);
    history.failRead = false;
    controller.refresh();
    expect(controller.state.historyFailed, isFalse);
    await controller.close();
  });

  test('repeated close awaits writes and closes owned streams', () async {
    history.items[0] = event();
    final Completer<void> writing = Completer<void>();
    final Completer<void> finishWrite = Completer<void>();
    final BellController controller = BellController(
      history: history,
      scope: testScope,
      readSeen: (String scope) => const <String>[],
      writeSeen: (String scope, List<String> identities) async {
        writing.complete();
        await finishWrite.future;
      },
    )..setPrivate(value: false);
    controller.markSeen(controller.state.identities);
    await writing.future;
    final Future<void> toastsClosed = controller.toasts.drain<void>();
    final Future<void> first = controller.close();
    final Future<void> second = controller.close();
    bool completed = false;
    final Future<void> both =
        Future.wait<void>(<Future<void>>[
          first,
          second,
        ]).then<void>((_) {
          completed = true;
        });
    expect(controller.state.private, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    finishWrite.complete();
    await both;
    await toastsClosed;
    expect(controller.isClosed, isTrue);
    await controller.close();
  });

  test('only explicit adjacent publication records fold', () {
    final String hash = List<String>.filled(64, 'a').join();
    BellRecord published(
      Object key, {
      int chain = 1,
      int? stamp,
      NotificationType type = NotificationType.paymentSent,
    }) => BellRecord(
      key: key,
      notification: event(
        kind: 'blockPublished',
        scope: testScope,
        chain: chain,
        hash: hash,
        timestamp: stamp ?? 100,
        type: type,
      ),
    );
    final List<BellRecord> records = <BellRecord>[
      published(1),
      published(2),
      BellRecord(key: 3, notification: event()),
      published(4),
      published(5, chain: 2),
      published(6, type: NotificationType.error),
      published(7, stamp: DateTime(2030, 1, 2).millisecondsSinceEpoch),
    ];
    final List<BellRun> runs = foldBellRecords(records, testScope);
    expect(runs.map((BellRun run) => run.records.length), <int>[
      2,
      1,
      1,
      1,
      1,
      1,
    ]);
    expect(runs.first.records.map((BellRecord r) => r.key), <Object>[1, 2]);
    expect(runs.first.records.first.notification.transactionHash, hash);
    expect(runs.first.records.first.notification.chainId, 1);
  });

  test('scope follows derivation order rather than selected address', () {
    expect(bellScopeForWallet(1, <String>['a', 'b']), '1:a');
    expect(bellScopeForWallet(2, <String>['a', 'b']), '2:a');
    expect(bellScopeForWallet(1, <String>[]), isNull);
    expect(bellScopeForWallet(1, <String>['']), isNull);
  });
}
