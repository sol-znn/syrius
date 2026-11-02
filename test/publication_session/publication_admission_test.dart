import 'dart:async';

// Pinned by flutter_test; no additional package is required for the clock.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
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
    registerFallbackValue(PowStatus.done);
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

  for (final String phase in <String>['sync', 'open', 'account', 'plasma']) {
    test(
      'external admission revoked during $phase refuses before SDK send',
      () {
        fakeAsync((FakeAsync clock) {
          bool admitted = true;
          final Completer<SyncInfo> sync = Completer<SyncInfo>();
          final Completer<Wallet> open = Completer<Wallet>();
          final Completer<WalletAccount> account = Completer<WalletAccount>();
          final Completer<bool> plasma = Completer<bool>();
          switch (phase) {
            case 'sync':
              fixture.syncReply = sync.future;
            case 'open':
              fixture.openReply = open.future;
            case 'account':
              fixture.accountReply = account.future;
            case 'plasma':
              fixture.powReply = plasma.future;
          }
          final AccountBlockUtils blocks = AccountBlockUtils(
            canPublish: () => admitted,
            publicationObserver: (_, _) {},
          );
          final PublicationOutcome outcome = PublicationOutcome(
            blocks.createAccountBlock(
              fixture.template,
              'Owner action',
              address: emptyAddress,
            ),
          );
          clock.flushMicrotasks();
          expect(outcome.settled, isFalse);
          admitted = false;
          switch (phase) {
            case 'sync':
              sync.complete(fixture.syncInfo);
            case 'open':
              open.complete(fixture.wallet);
            case 'account':
              account.complete(fixture.account);
            case 'plasma':
              plasma.complete(false);
          }
          clock.flushMicrotasks();
          expect(outcome.settled, isTrue);
          expect(outcome.result, isNull);
          expect(fixture.sendCalls, 0);
          verifyNever(() => fixture.account.sign(any()));
          verifyNever(() => fixture.account.signTx(any()));
        });
      },
    );
  }

  test('initial refusal happens before even a sync read', () {
    fakeAsync((FakeAsync clock) {
      final PublicationOutcome outcome = PublicationOutcome(
        AccountBlockUtils(
          canPublish: () => false,
        ).createAccountBlock(
          fixture.template,
          'Owner action',
          address: emptyAddress,
        ),
      );
      clock.flushMicrotasks();
      expect(outcome.settled, isTrue);
      expect(fixture.syncCalls, 0);
      expect(fixture.openCalls, 0);
      expect(fixture.sendCalls, 0);
    });
  });

  test(
    'admission revoked after dispatch cannot replace the original result',
    () {
      fakeAsync((FakeAsync clock) {
        bool admitted = true;
        final Completer<AccountBlockTemplate> reply =
            Completer<AccountBlockTemplate>();
        fixture.sendReply = reply.future;
        final PublicationOutcome outcome = PublicationOutcome(
          AccountBlockUtils(
            canPublish: () => admitted,
            publicationObserver: (_, _) {},
          ).createAccountBlock(
            fixture.template,
            'Owner action',
            address: emptyAddress,
          ),
        );
        clock.flushMicrotasks();
        expect(fixture.sendCalls, 1);
        admitted = false;
        reply.complete(fixture.response);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(outcome.result, same(fixture.response));
        expect(outcome.error, isNull);
        expect(fixture.sendCalls, 1);
      });
    },
  );
}
