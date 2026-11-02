import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_preflight.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_session.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Client extends Client {
  final List<String> methods = <String>[];
  Completer<dynamic>? account;

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    methods.add(method);
    if (method == 'embedded.plasma.get') {
      return <String, dynamic>{
        'currentPlasma': 189000,
        'maxPlasma': 189000,
        'qsrAmount': '0',
      };
    }
    if (method == 'ledger.getAccountInfoByAddress') {
      return account?.future ??
          <String, dynamic>{
            'address': emptyAddress.toString(),
            'accountHeight': 0,
            'balanceInfoMap': <String, dynamic>{},
          };
    }
    throw StateError('Unexpected in-memory RPC');
  }
}

class _WsClient extends WsClient {
  int calls = 0;

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    calls++;
    throw StateError('Revoked fixture must not dispatch');
  }
}

void main() {
  for (final bool replacePlasma in <bool>[false, true]) {
    test(
      'independent readers refuse a replaced '
      '${replacePlasma ? 'Plasma' : 'Ledger'} Client',
      () async {
        final _Client plasmaClient = _Client();
        final _Client ledgerClient = _Client();
        final _Client replacement = _Client();
        final PlasmaApi plasma = PlasmaApi()..setClient(plasmaClient);
        final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
        final TokenCreateSession session = TokenCreateSession.boundApis(
          owner: emptyAddress.toString(),
          chainId: 321,
          plasmaSource: plasma,
          ledgerSource: ledger,
          isCurrent: () => true,
        );
        await session.readAccount();
        await session.readPlasma();
        if (replacePlasma) {
          plasma.setClient(replacement);
        } else {
          ledger.setClient(replacement);
        }
        expect(session.isCurrent, isFalse);
        expect(session.readAccount, throwsStateError);
        expect(session.readPlasma, throwsStateError);
        expect(replacement.methods, isEmpty);
        expect(plasmaClient.methods, <String>['embedded.plasma.get']);
        expect(ledgerClient.methods, <String>[
          'ledger.getAccountInfoByAddress',
        ]);
        plasma.setClient(plasmaClient);
        ledger.setClient(ledgerClient);
        expect(session.isCurrent, isFalse);
      },
    );
  }

  test(
    'same websocket Client URL changes revoke the original callbacks',
    () async {
      final _WsClient client = _WsClient()
        ..url = 'ws://fixture.invalid/original';
      try {
        final TokenCreateSession session = TokenCreateSession.boundApis(
          owner: emptyAddress.toString(),
          chainId: 321,
          plasmaSource: PlasmaApi()..setClient(client),
          ledgerSource: LedgerApi()..setClient(client),
          tokenSource: TokenApi()..setClient(client),
          isCurrent: () => true,
        );
        client.url = 'ws://fixture.invalid/replacement';
        expect(session.isCurrent, isFalse);
        expect(session.readPlasma, throwsStateError);
        expect(session.readAccount, throwsStateError);
        client.url = 'ws://fixture.invalid/original';
        expect(session.isCurrent, isFalse);
        expect(client.calls, 0);
      } finally {
        await client.restartedStreamController.close();
      }
    },
  );

  test('an unchanged transport cannot revive a changed revision', () {
    final _Client client = _Client();
    int revision = 7;
    final int captured = revision;
    final TokenCreateSession session = TokenCreateSession.boundApis(
      owner: emptyAddress.toString(),
      chainId: 321,
      plasmaSource: PlasmaApi()..setClient(client),
      ledgerSource: LedgerApi()..setClient(client),
      isCurrent: () => revision == captured,
    );
    revision += 2;
    expect(session.isCurrent, isFalse);
    revision = captured;
    expect(session.isCurrent, isFalse);
    expect(session.readAccount, throwsStateError);
    expect(client.methods, isEmpty);
  });

  test('the original token API client is also part of dispatch authority', () {
    final _Client client = _Client();
    final _Client replacement = _Client();
    final TokenApi token = TokenApi()..setClient(client);
    final TokenCreateSession session = TokenCreateSession.boundApis(
      owner: emptyAddress.toString(),
      chainId: 321,
      plasmaSource: PlasmaApi()..setClient(client),
      ledgerSource: LedgerApi()..setClient(client),
      tokenSource: token,
      isCurrent: () => true,
    );
    token.setClient(replacement);
    expect(session.isCurrent, isFalse);
    expect(session.readAccount, throwsStateError);
    expect(client.methods, isEmpty);
    expect(replacement.methods, isEmpty);
  });

  test(
    'rebinding during an original read cannot paint or dispatch its late facts',
    () async {
      final _Client ledgerClient = _Client()..account = Completer<dynamic>();
      final _Client plasmaClient = _Client();
      final _Client replacement = _Client();
      final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
      final TokenCreateSession session = TokenCreateSession.boundApis(
        owner: emptyAddress.toString(),
        chainId: 321,
        plasmaSource: PlasmaApi()..setClient(plasmaClient),
        ledgerSource: ledger,
        isCurrent: () => true,
      );
      final TokenCreatePreflight preflight = TokenCreatePreflight(
        session: session,
      );
      try {
        final Future<bool> read = preflight.refresh();
        ledger.setClient(replacement);
        ledgerClient.account!.complete(<String, dynamic>{
          'address': emptyAddress.toString(),
          'accountHeight': 0,
          'balanceInfoMap': <String, dynamic>{},
        });
        expect(await read, isFalse);
        expect(preflight.znn, isNull);
        expect(preflight.plasma, isNull);
        expect(preflight.ticket, isNull);
        expect(replacement.methods, isEmpty);
        expect(ledgerClient.methods, <String>[
          'ledger.getAccountInfoByAddress',
        ]);
      } finally {
        preflight.dispose();
      }
    },
  );
}
