import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

class _Client extends Client {
  final List<String> methods = <String>[];

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    methods.add(method);
    if (method == 'embedded.plasma.getEntriesByAddress') {
      return plasmaTestPage(<FusionEntry>[plasmaTestEntry(1)]).toJson();
    }
    if (method == 'ledger.getAccountInfoByAddress') {
      return <String, dynamic>{
        'address': emptyAddress.toString(),
        'accountHeight': 0,
        'balanceInfoMap': <String, dynamic>{},
      };
    }
    throw StateError('Unexpected fixture RPC');
  }
}

void main() {
  test(
    'bound Plasma and Ledger wrappers keep their original Client identities',
    () async {
      final _Client originalPlasma = _Client();
      final _Client originalLedger = _Client();
      final _Client replacement = _Client();
      final PlasmaApi plasma = PlasmaApi()..setClient(originalPlasma);
      final LedgerApi ledger = LedgerApi()..setClient(originalLedger);
      final PlasmaSession session = PlasmaSession.boundApis(
        address: emptyAddress.toString(),
        chainId: 321,
        plasmaSource: plasma,
        ledgerSource: ledger,
        isCurrent: () => true,
      );
      expect(session.isCurrent, isTrue);
      await session.readEntries(0, 2);
      await session.readAccount();
      plasma.setClient(replacement);
      ledger.setClient(replacement);
      expect(session.isCurrent, isFalse);
      // Direct retained callbacks refuse before any replacement transport call.
      expect(() => session.readEntries(0, 2), throwsStateError);
      expect(session.readAccount, throwsStateError);
      expect(originalPlasma.methods, <String>[
        'embedded.plasma.getEntriesByAddress',
      ]);
      expect(originalLedger.methods, <String>[
        'ledger.getAccountInfoByAddress',
      ]);
      expect(replacement.methods, isEmpty);
      plasma.setClient(originalPlasma);
      ledger.setClient(originalLedger);
      expect(session.isCurrent, isFalse);
    },
  );

  test(
    'a revision round trip revokes APIs even when the Client is unchanged',
    () {
      final _Client client = _Client();
      final PlasmaApi plasma = PlasmaApi()..setClient(client);
      final LedgerApi ledger = LedgerApi()..setClient(client);
      int revision = 0;
      final int captured = revision;
      final PlasmaSession session = PlasmaSession.boundApis(
        address: emptyAddress.toString(),
        chainId: 321,
        plasmaSource: plasma,
        ledgerSource: ledger,
        isCurrent: () => revision == captured,
      );
      revision += 2;
      expect(session.isCurrent, isFalse);
    },
  );

  test(
    'changing the same websocket Client URL revokes retained callbacks',
    () async {
      final _WsClient client = _WsClient()
        ..url = 'ws://fixture.invalid/original';
      try {
        final PlasmaApi plasma = PlasmaApi()..setClient(client);
        final LedgerApi ledger = LedgerApi()..setClient(client);
        final PlasmaSession session = PlasmaSession.boundApis(
          address: emptyAddress.toString(),
          chainId: 321,
          plasmaSource: plasma,
          ledgerSource: ledger,
          isCurrent: () => true,
        );
        client.url = 'ws://fixture.invalid/replacement';
        expect(session.isCurrent, isFalse);
        expect(() => session.readEntries(0, 2), throwsStateError);
        expect(client.calls, 0);
        client.url = 'ws://fixture.invalid/original';
        expect(session.isCurrent, isFalse);
      } finally {
        await client.restartedStreamController.close();
      }
    },
  );
}

class _WsClient extends WsClient {
  int calls = 0;

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    calls++;
    throw StateError('A revoked fixture must never dispatch');
  }
}
