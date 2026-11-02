import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/peer_count.dart';

void main() {
  test('unknown until an actual count, including a real zero', () async {
    int actual = 23;
    final PeerCount peers = PeerCount(
      lookup: () async => actual,
      isConnected: () => true,
    );
    addTearDown(peers.dispose);
    expect(peers.value, isNull);
    await peers.refresh();
    expect(peers.value, 23);
    actual = 0;
    await peers.refresh();
    expect(peers.value, 0);
    actual = -1;
    await peers.refresh();
    expect(peers.value, isNull);
  });

  test('concurrent refreshes share one lookup in an epoch', () async {
    final Completer<int> result = Completer<int>();
    int lookups = 0;
    final PeerCount peers = PeerCount(
      lookup: () {
        lookups++;
        return result.future;
      },
      isConnected: () => true,
    );
    addTearDown(peers.dispose);
    final Future<void> first = peers.refresh();
    final Future<void> second = peers.refresh();
    final Future<void> third = peers.refresh();
    expect(second, same(first));
    expect(third, same(first));
    expect(lookups, 1);
    result.complete(7);
    await Future.wait(<Future<void>>[first, second, third]);
    expect(peers.value, 7);
  });

  test('reset ignores old results and permits a new epoch lookup', () async {
    final List<Completer<int>> results = <Completer<int>>[
      Completer<int>(),
      Completer<int>(),
    ];
    int lookups = 0;
    final PeerCount peers = PeerCount(
      lookup: () => results[lookups++].future,
      isConnected: () => true,
    );
    addTearDown(peers.dispose);
    final Future<void> old = peers.refresh();
    peers.reset();
    final Future<void> current = peers.refresh();
    expect(lookups, 2);
    results[1].complete(19);
    await current;
    expect(peers.value, 19);
    results[0].complete(99);
    await old;
    expect(peers.value, 19);
  });

  test('late failure cannot erase a current epoch count', () async {
    final Completer<int> oldResult = Completer<int>();
    int lookups = 0;
    final PeerCount peers = PeerCount(
      lookup: () => lookups++ == 0 ? oldResult.future : Future<int>.value(8),
      isConnected: () => true,
    );
    addTearDown(peers.dispose);
    final Future<void> old = peers.refresh();
    peers.reset();
    await peers.refresh();
    oldResult.completeError(StateError('old node refused'));
    await old;
    expect(peers.value, 8);
  });

  test('failures are unknown and a later refresh can recover', () async {
    bool fail = true;
    final PeerCount peers = PeerCount(
      lookup: () {
        if (fail) throw StateError('lookup refused');
        return Future<int>.value(5);
      },
      isConnected: () => true,
    );
    addTearDown(peers.dispose);
    await peers.refresh();
    expect(peers.value, isNull);
    fail = false;
    await peers.refresh();
    expect(peers.value, 5);
  });

  test('disconnection is unknown and never launches a lookup', () async {
    bool connected = true;
    int lookups = 0;
    final PeerCount peers = PeerCount(
      lookup: () async {
        lookups++;
        return 12;
      },
      isConnected: () => connected,
    );
    addTearDown(peers.dispose);
    await peers.refresh();
    expect(peers.value, 12);
    connected = false;
    await peers.refresh();
    expect(peers.value, isNull);
    expect(lookups, 1);
  });

  test('disconnection during a lookup discards its successful count', () async {
    final Completer<int> result = Completer<int>();
    bool connected = true;
    final PeerCount peers = PeerCount(
      lookup: () => result.future,
      isConnected: () => connected,
    );
    addTearDown(peers.dispose);
    final Future<void> request = peers.refresh();
    connected = false;
    result.complete(31);
    await request;
    expect(peers.value, isNull);
  });

  test('a failed connection probe is unknown', () async {
    final PeerCount peers = PeerCount(
      lookup: () async => fail('a disconnected probe must not fetch'),
      isConnected: () => throw StateError('connection state unavailable'),
    );
    addTearDown(peers.dispose);
    await peers.refresh();
    expect(peers.value, isNull);
  });

  test('dispose ignores a late result and further refreshes', () async {
    final Completer<int> result = Completer<int>();
    int notifications = 0;
    int lookups = 0;
    final PeerCount peers =
        PeerCount(
          lookup: () {
            lookups++;
            return result.future;
          },
          isConnected: () => true,
        )..addListener(() {
          notifications++;
        });
    final Future<void> request = peers.refresh();
    peers.dispose();
    result.complete(18);
    await request;
    await peers.refresh();
    peers.reset();
    expect(notifications, 0);
    expect(lookups, 1);
  });
}
