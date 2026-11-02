import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Node extends Mock implements Zenon {}

class _ReadTransport extends Mock implements Client {}

Map<String, dynamic> _momentum(int chain) => <String, dynamic>{
  'version': 1,
  'chainIdentifier': chain,
  'hash': emptyHash.toString(),
  'previousHash': emptyHash.toString(),
  'height': 1,
  'timestamp': 1,
  'data': '',
  'content': <Object>[],
  'changesHash': emptyHash.toString(),
  'producer': emptyAddress.toString(),
};

void main() {
  late Zenon? previous;
  late String? previousNode;
  late _Node node;
  late LedgerApi ledger;
  late _ReadTransport transport;
  late Completer<Object?> response;

  setUp(() {
    previous = app.zenon;
    previousNode = kCurrentNode;
    node = _Node();
    transport = _ReadTransport();
    ledger = LedgerApi()..setClient(transport);
    response = Completer<Object?>();
    when(() => node.ledger).thenReturn(ledger);
    when(
      () => transport.sendRequest('ledger.getFrontierMomentum', any()),
    ).thenAnswer((_) => response.future);
    app.zenon = node;
    kCurrentNode = 'wss://node.example:35998';
  });
  tearDown(() {
    app.zenon = previous;
    kCurrentNode = previousNode;
    WalletContextRevision.invalidate();
  });

  test(
    'positive chain comes from the original independently bound API',
    () async {
      final Future<int?> read = NodeUtils.getNodeChainIdentifier();
      response.complete(_momentum(321));
      expect(await read, 321);
      verify(
        () => transport.sendRequest('ledger.getFrontierMomentum', any()),
      ).called(1);
    },
  );

  test('failed read remains unknown without a mainnet fallback', () async {
    final Future<int?> read = NodeUtils.getNodeChainIdentifier();
    response.completeError(StateError('Synthetic transport unavailable'));
    expect(await read, isNull);
  });

  test('a non-positive reported chain remains unknown', () async {
    final Future<int?> read = NodeUtils.getNodeChainIdentifier();
    response.complete(_momentum(0));
    expect(await read, isNull);
  });

  test(
    'rebinding a shared API cannot redirect or qualify an old reply',
    () async {
      final Future<int?> read = NodeUtils.getNodeChainIdentifier();
      final _ReadTransport replacement = _ReadTransport();
      ledger.setClient(replacement);
      response.complete(_momentum(321));
      expect(await read, isNull);
      verifyNever(() => replacement.sendRequest(any(), any()));
    },
  );

  test('an unobserved context round trip revokes an old read', () async {
    final Future<int?> read = NodeUtils.getNodeChainIdentifier();
    final String? original = kCurrentNode;
    kCurrentNode = 'wss://replacement.example:35998';
    WalletContextRevision.invalidate();
    kCurrentNode = original;
    WalletContextRevision.invalidate();
    response.complete(_momentum(321));
    expect(await read, isNull);
  });
}
