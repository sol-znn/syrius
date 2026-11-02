import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// WalletKit exposes IPairing through Core but omits its export; dependencies
// remain frozen at the pinned reown_core override for this contract test.
// ignore: depend_on_referenced_packages
import 'package:reown_core/pairing/i_pairing.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/web3wallet_service.dart';

class _WalletKit extends Mock implements ReownWalletKit {}

class _Core extends Mock implements ReownCore {}

class _Pairing extends Mock implements IPairing {}

void main() {
  setUpAll(
    () => registerFallbackValue(
      Errors.getSdkError(Errors.USER_DISCONNECTED).toSignError(),
    ),
  );
  late _WalletKit client;
  late _Core core;
  late _Pairing pairing;
  late Web3WalletService service;
  setUp(() {
    client = _WalletKit();
    core = _Core();
    pairing = _Pairing();
    when(() => client.core).thenReturn(core);
    when(() => core.pairing).thenReturn(pairing);
    service = Web3WalletService.withClient(client);
  });

  test('pairing disconnection exposes the original failure', () async {
    final Object error = StateError('fixture disconnect failed');
    when(
      () => pairing.disconnect(topic: 'fixture-pairing'),
    ).thenAnswer((_) => Future<void>.error(error));
    await expectLater(
      service.deactivatePairing(topic: 'fixture-pairing'),
      throwsA(same(error)),
    );
    verify(() => pairing.disconnect(topic: 'fixture-pairing')).called(1);
    verifyNever(
      () => client.disconnectSession(
        topic: any(named: 'topic'),
        reason: any(named: 'reason'),
      ),
    );
    await service.onDispose();
  });

  test(
    'captured pairing completion survives disposal and affects no session',
    () async {
      final Completer<void> response = Completer<void>();
      when(
        () => pairing.disconnect(topic: 'fixture-pairing'),
      ).thenAnswer((_) => response.future);
      final Web3WalletActions original = service.captureActions();
      final Future<void> pending = original.disconnectPairing(
        'fixture-pairing',
      );
      await service.onDispose();
      expect(original.isCurrent(), isFalse);
      response.complete();
      await pending;
      verifyNever(
        () => client.disconnectSession(
          topic: any(named: 'topic'),
          reason: any(named: 'reason'),
        ),
      );
      expect(
        () => original.disconnectPairing('fixture-pairing'),
        throwsStateError,
      );
    },
  );

  test('captured session disconnect retains its original Future', () async {
    final Completer<void> response = Completer<void>();
    when(
      () => client.disconnectSession(
        topic: 'fixture-session',
        reason: any(named: 'reason'),
      ),
    ).thenAnswer((_) => response.future);
    final Web3WalletActions original = service.captureActions();
    final Future<void> pending = original.disconnectSession('fixture-session');
    expect(identical(pending, response.future), isTrue);
    await service.onDispose();
    response.complete();
    await pending;
    verify(
      () => client.disconnectSession(
        topic: 'fixture-session',
        reason: any(named: 'reason'),
      ),
    ).called(1);
  });
}
