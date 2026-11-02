import 'dart:async';

// Pinned by flutter_test; no additional package is required for the clock.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  late PublicationGlobals globals;
  late PublicationFixture fixture;
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(MockPublicationAccount());
    registerFallbackValue(<int>[]);
    registerFallbackValue((PowStatus _) {});
    registerFallbackValue(() => true);
  });
  setUp(() {
    globals = PublicationGlobals();
    fixture = PublicationFixture();
  });
  tearDown(() async {
    try {
      await fixture.dispose();
    } finally {
      globals.restore();
    }
  });

  test('capture before caller RPC refuses a wallet context round trip', () {
    fakeAsync((FakeAsync clock) {
      final AccountBlockUtils sender = AccountBlockUtils.capture(
        address: emptyAddress,
      );
      kSelectedAddress = fixture.addresses.first;
      WalletContextRevision.invalidate();
      kSelectedAddress = fixture.addresses.last;
      WalletContextRevision.invalidate();
      final PublicationOutcome result = PublicationOutcome(
        sender.createAccountBlock(
          fixture.template,
          'Synthetic captured operation',
          address: emptyAddress,
        ),
      );
      clock.flushMicrotasks();
      expect(result.error, isNotNull);
      expect(result.settled, isTrue);
      expect(fixture.syncCalls, 0);
      expect(fixture.openCalls, 0);
      expect(fixture.sendCalls, 0);
    });
  });

  test('capture refuses an unknown chain or mismatched original file path', () {
    kNodeChainId = null;
    expect(
      () => AccountBlockUtils.capture(address: emptyAddress),
      throwsA(isA<FailureException>()),
    );
    kNodeChainId = PublicationFixture.chain;
    when(() => fixture.file.walletPath).thenReturn('other-synthetic-wallet');
    expect(
      () => AccountBlockUtils.capture(address: emptyAddress),
      throwsA(isA<FailureException>()),
    );
    expect(fixture.syncCalls, 0);
    expect(fixture.openCalls, 0);
    expect(fixture.sendCalls, 0);
  });

  test('the actual SDK account address must equal the captured signer', () {
    fakeAsync((FakeAsync clock) {
      fixture.actualSigner = Address.parse(fixture.addresses.first);
      final AccountBlockUtils sender = AccountBlockUtils.capture(
        address: emptyAddress,
      );
      final PublicationOutcome result = PublicationOutcome(
        sender.createAccountBlock(
          fixture.template,
          'Synthetic captured operation',
          address: emptyAddress,
        ),
      );
      clock.flushMicrotasks();
      expect(result.settled, isTrue);
      expect(result.error, isA<FailureException>());
      expect(fixture.powCalls, 1);
      expect(fixture.sendCalls, 0);
      expect(fixture.closeCalls, 1);
    });
  });

  test('a captured sender cannot substitute another owned account', () {
    fakeAsync((FakeAsync clock) {
      final AccountBlockUtils sender = AccountBlockUtils.capture(
        address: emptyAddress,
      );
      final PublicationOutcome result = PublicationOutcome(
        sender.createAccountBlock(
          fixture.template,
          'Synthetic captured operation',
          address: Address.parse(fixture.addresses.first),
        ),
      );
      clock.flushMicrotasks();
      expect(result.settled, isTrue);
      expect(result.error, isNotNull);
      expect(fixture.syncCalls, 0);
      expect(fixture.openCalls, 0);
    });
  });

  test('captured Stats transport replacement refuses before any RPC', () {
    fakeAsync((FakeAsync clock) {
      final AccountBlockUtils sender = AccountBlockUtils.capture(
        address: emptyAddress,
      );
      when(() => fixture.stats.client).thenReturn(MockPublicationClient());
      final PublicationOutcome result = PublicationOutcome(
        sender.createAccountBlock(
          fixture.template,
          'Synthetic captured operation',
          address: emptyAddress,
        ),
      );
      clock.flushMicrotasks();
      expect(result.error, isNotNull);
      expect(fixture.syncCalls, 0);
      expect(fixture.openCalls, 0);
      expect(fixture.sendCalls, 0);
    });
  });

  test(
    'original Stats reply after client replacement cannot acquire a wallet',
    () {
      fakeAsync((FakeAsync clock) {
        final Completer<SyncInfo> reply = Completer<SyncInfo>();
        fixture.syncReply = reply.future;
        final AccountBlockUtils sender = AccountBlockUtils.capture(
          address: emptyAddress,
        );
        final PublicationOutcome result = PublicationOutcome(
          sender.createAccountBlock(
            fixture.template,
            'Synthetic captured operation',
            address: emptyAddress,
          ),
        );
        clock.flushMicrotasks();
        expect(fixture.syncCalls, 1);
        expect(result.settled, isFalse);
        when(() => fixture.stats.client).thenReturn(MockPublicationClient());
        reply.complete(fixture.syncInfo);
        clock.flushMicrotasks();
        expect(result.error, isNotNull);
        expect(fixture.openCalls, 0);
        expect(fixture.sendCalls, 0);
      });
    },
  );
}
