import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

class _Client extends Client {
  final List<String> calls = <String>[];
  Completer<dynamic>? pending;
  final Object failure = Object();

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) {
    calls.add(method);
    return pending?.future ?? Future<dynamic>.error(failure);
  }
}

class _Socket extends WsClient {
  int calls = 0;
  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    calls++;
    throw StateError('A revoked source must not dispatch');
  }
}

void main() {
  for (final bool htlcReplacement in <bool>[false, true]) {
    test(
      'original ${htlcReplacement ? 'HTLC' : 'ledger'} Client replacement '
      'cannot rebind a read',
      () async {
        final _Client ledgerClient = _Client();
        final _Client htlcClient = _Client();
        final _Client replacement = _Client();
        final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
        final HtlcApi htlc = HtlcApi()..setClient(htlcClient);
        final SwapListApiCapture source = SwapListApiCapture(
          ledgerSource: ledger,
          htlcSource: htlc,
          chainId: 321,
          isCurrent: () => true,
        );
        await expectLater(
          source.readDeposit(swapHash(1)),
          throwsA(same(ledgerClient.failure)),
        );
        await expectLater(
          source.readLiveDeposit(swapHash(1)),
          throwsA(same(htlcClient.failure)),
        );
        if (htlcReplacement) {
          htlc.setClient(replacement);
        } else {
          ledger.setClient(replacement);
        }
        expect(source.isCurrent, isFalse);
        await expectLater(
          source.readDeposit(swapHash(1)),
          throwsA(isA<SwapListRefused>()),
        );
        await expectLater(
          source.readLiveDeposit(swapHash(1)),
          throwsA(isA<SwapListRefused>()),
        );
        expect(replacement.calls, isEmpty);
        ledger.setClient(ledgerClient);
        htlc.setClient(htlcClient);
        expect(source.isCurrent, isFalse);
        expect(ledgerClient.calls.length, 1);
        expect(htlcClient.calls.length, 1);
      },
    );
  }

  test(
    'an admitted original failure survives source rebind while awaiting',
    () async {
      final _Client original = _Client()..pending = Completer<dynamic>();
      final _Client replacement = _Client();
      final LedgerApi ledger = LedgerApi()..setClient(original);
      final HtlcApi htlc = HtlcApi()..setClient(original);
      final SwapListApiCapture source = SwapListApiCapture(
        ledgerSource: ledger,
        htlcSource: htlc,
        chainId: 321,
        isCurrent: () => true,
      );
      final Future<SwapDepositProof?> read = source.readDeposit(swapHash(1));
      final Future<void> retained = expectLater(
        read,
        throwsA(same(original.failure)),
      );
      ledger.setClient(replacement);
      htlc.setClient(replacement);
      original.pending!.completeError(original.failure, StackTrace.current);
      await retained;
      expect(original.calls.length, 1);
      expect(replacement.calls, isEmpty);
      expect(source.isCurrent, isFalse);
    },
  );

  for (final bool changeHtlcUrl in <bool>[false, true]) {
    test(
      'same ${changeHtlcUrl ? 'HTLC' : 'ledger'} socket URL departure '
      'is terminal',
      () async {
        final _Socket ledgerSocket = _Socket()
          ..url = 'ws://fixture.invalid/ledger';
        final _Socket htlcSocket = _Socket()..url = 'ws://fixture.invalid/htlc';
        try {
          final SwapListApiCapture source = SwapListApiCapture(
            ledgerSource: LedgerApi()..setClient(ledgerSocket),
            htlcSource: HtlcApi()..setClient(htlcSocket),
            chainId: 321,
            isCurrent: () => true,
          );
          final _Socket changed = changeHtlcUrl ? htlcSocket : ledgerSocket;
          final String? originalUrl = changed.url;
          changed.url = 'ws://fixture.invalid/replacement';
          expect(source.isCurrent, isFalse);
          changed.url = originalUrl;
          expect(source.isCurrent, isFalse);
          await expectLater(
            source.readChainTime(),
            throwsA(isA<SwapListRefused>()),
          );
          expect(ledgerSocket.calls, 0);
          expect(htlcSocket.calls, 0);
        } finally {
          await ledgerSocket.restartedStreamController.close();
          await htlcSocket.restartedStreamController.close();
        }
      },
    );
  }
}
