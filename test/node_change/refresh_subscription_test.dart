import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/refresh_bloc_mixin.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Reader with RefreshBlocMixin {
  int refreshes = 0;

  void refresh() => refreshes++;
}

class _Reconnects {
  final StreamController<bool> source = StreamController<bool>.broadcast(
    sync: true,
  );
  int listeners = 0;
  int cancellations = 0;

  late final Stream<bool> stream = Stream<bool>.multi(
    (MultiStreamController<bool> output) {
      listeners++;
      final StreamSubscription<bool> subscription = source.stream.listen(
        output.addSync,
      );
      output.onCancel = () {
        cancellations++;
        return subscription.cancel();
      };
    },
    isBroadcast: true,
  );
}

void main() {
  test(
    'the pinned SDK reconnect source detaches without opening a socket',
    () async {
      final WsClient client = WsClient();
      final _Reader reader = _Reader();
      try {
        reader.listenToWsRestart(
          reader.refresh,
          client: client,
        );
        client.restartedStreamController.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(reader.refreshes, 1);
        reader.cancelStreamSubscription();
        await Future<void>.delayed(Duration.zero);
        expect(client.restartedStreamController.hasListener, isFalse);
      } finally {
        reader.cancelStreamSubscription();
        await client.restartedStreamController.close();
      }
    },
  );

  test(
    'SDK readers detach independently without closing the shared source',
    () async {
      final WsClient client = WsClient();
      final _Reader first = _Reader();
      final _Reader second = _Reader();
      try {
        first.listenToWsRestart(first.refresh, client: client);
        second.listenToWsRestart(second.refresh, client: client);
        first.cancelStreamSubscription();
        client.restartedStreamController.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(first.refreshes, 0);
        expect(second.refreshes, 1);
        expect(client.restartedStreamController.hasListener, isTrue);
        second.cancelStreamSubscription();
        await Future<void>.delayed(Duration.zero);
        expect(client.restartedStreamController.hasListener, isFalse);
        expect(client.restartedStreamController.isClosed, isFalse);
      } finally {
        first.cancelStreamSubscription();
        second.cancelStreamSubscription();
        await client.restartedStreamController.close();
      }
    },
  );

  test(
    'each reconnect refreshes once without creating another listener',
    () async {
      final _Reader reader = _Reader();
      final _Reconnects reconnects = _Reconnects();
      try {
        reader.listenToWsRestart(reader.refresh, restarts: reconnects.stream);
        reconnects.source.add(false);
        for (int i = 0; i < 4; i++) {
          reconnects.source.add(true);
          expect(reader.refreshes, i + 1);
        }
        expect(reconnects.listeners, 1);
        expect(reconnects.cancellations, 0);
        reader.cancelStreamSubscription();
        reconnects.source.add(true);
        expect(reader.refreshes, 4);
        expect(reconnects.cancellations, 1);
      } finally {
        reader.cancelStreamSubscription();
        await reconnects.source.close();
      }
    },
  );

  test(
    'replacement detaches both old sources before the next callback',
    () async {
      final _Reader reader = _Reader();
      final _Reconnects old = _Reconnects();
      final _Reconnects current = _Reconnects();
      int oldCalls = 0;
      try {
        reader.listenToWsRestart(() => oldCalls++, restarts: old.stream);
        // This event is already queued when ownership changes.
        NodeChange.announce();
        reader.listenToWsRestart(reader.refresh, restarts: current.stream);
        old.source.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(oldCalls, 0);
        expect(reader.refreshes, 0);
        current.source.add(true);
        expect(reader.refreshes, 1);
        NodeChange.announce();
        await Future<void>.delayed(Duration.zero);
        expect(reader.refreshes, 2);
        expect(old.listeners, 1);
        expect(old.cancellations, 1);
        expect(current.listeners, 1);
        reader.cancelStreamSubscription();
        NodeChange.announce();
        current.source.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(reader.refreshes, 2);
        expect(current.cancellations, 1);
      } finally {
        reader.cancelStreamSubscription();
        await old.source.close();
        await current.source.close();
      }
    },
  );

  test(
    'repeated registration leaves one node listener and close is idempotent',
    () async {
      final _Reader reader = _Reader();
      final _Reconnects reconnects = _Reconnects();
      try {
        for (int i = 0; i < 3; i++) {
          reader.listenToWsRestart(reader.refresh, restarts: reconnects.stream);
        }
        NodeChange.announce();
        await Future<void>.delayed(Duration.zero);
        expect(reader.refreshes, 1);
        expect(reconnects.listeners, 3);
        expect(reconnects.cancellations, 2);
        reader
          ..cancelStreamSubscription()
          ..cancelStreamSubscription();
        expect(reconnects.cancellations, 3);
        NodeChange.announce();
        await Future<void>.delayed(Duration.zero);
        expect(reader.refreshes, 1);
      } finally {
        reader.cancelStreamSubscription();
        await reconnects.source.close();
      }
    },
  );
}
