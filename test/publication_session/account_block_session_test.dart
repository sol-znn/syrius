import 'dart:async';

// Pinned by flutter_test; no additional package is required for the clock.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
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

  void assertNoSigning() {
    verifyNever(() => fixture.account.getPublicKey());
    verifyNever(() => fixture.account.getAddress());
    verifyNever(() => fixture.account.sign(any()));
    verifyNever(() => fixture.account.signTx(any()));
    expect(fixture.sendCalls, 0);
  }

  void assertRefused(PublicationOutcome outcome) {
    expect(outcome.settled, isTrue);
    expect(outcome.result, isNull);
    expect(
      outcome.error,
      isA<FailureException>().having(
        (FailureException error) => error.message,
        'message',
        currentL10n.publicationSessionChanged,
      ),
    );
    assertNoSigning();
    expect(
      fixture.records.where(
        (WalletNotification e) => e.eventKind == 'blockPublished',
      ),
      isEmpty,
    );
  }

  test('transport quarantine refuses before sync or wallet acquisition', () {
    fakeAsync((FakeAsync clock) {
      final NodeTransitionLease lease = NodeTransitions.begin()!;
      try {
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        assertRefused(outcome);
        expect(fixture.syncCalls, 0);
        expect(fixture.openCalls, 0);
      } finally {
        lease.complete();
      }
    });
  });

  final Map<String, void Function()> changes = <String, void Function()>{
    'lock': () => kWalletFile = null,
    'client replacement': () => app.zenon = MockPublicationZenon(),
    'wallet replacement': () => kWalletFile = MockPublicationFile(),
    'unobserved transport round trip': () {
      final NodeTransitionLease lease = NodeTransitions.begin()!;
      expect(lease.complete(), isTrue);
    },
  };

  for (final String phase in <String>['sync', 'open', 'account', 'plasma']) {
    for (final MapEntry<String, void Function()> change in changes.entries) {
      test('${change.key} while $phase waits refuses before send', () {
        fakeAsync((FakeAsync clock) {
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
          final PublicationOutcome outcome = fixture.publish();
          clock.flushMicrotasks();
          expect(outcome.settled, isFalse);
          change.value();
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
          assertRefused(outcome);
          expect(fixture.openCalls, phase == 'sync' ? 0 : 1);
          expect(fixture.closeCalls, phase == 'sync' ? 0 : 1);
          expect(
            fixture.accountIndices,
            phase == 'sync' || phase == 'open' ? isEmpty : <int>[1],
          );
          if (phase != 'plasma') expect(fixture.powCalls, 0);
        });
      });
    }
  }

  test('a replaced file is never closed when a queued acquisition returns', () {
    fakeAsync((FakeAsync clock) {
      final Completer<Wallet> opened = Completer<Wallet>();
      fixture.openReply = opened.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      final MockPublicationFile replacement = MockPublicationFile();
      kWalletFile = replacement;
      opened.complete(fixture.wallet);
      clock.flushMicrotasks();
      assertRefused(outcome);
      expect(fixture.closeCalls, 1);
      verifyNever(replacement.close);
    });
  });

  for (final String phase in <String>['sync', 'open', 'account', 'plasma']) {
    test('a context round trip while $phase waits cannot reuse authority', () {
      fakeAsync((FakeAsync clock) {
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
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        final String? original = kSelectedAddress;
        kSelectedAddress = kDefaultAddressList.first;
        WalletContextRevision.invalidate();
        kSelectedAddress = original;
        WalletContextRevision.invalidate();
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
        assertRefused(outcome);
        expect(fixture.closeCalls, phase == 'sync' ? 0 : 1);
      });
    });
  }

  final Map<String, void Function()> contextChanges = <String, void Function()>{
    'node endpoint': () => kCurrentNode = 'replacement-node',
    'node chain': () => kNodeChainId = 99,
    'SDK chain': () => setChainIdentifier(chainIdentifier: 99),
    'derivation order': () =>
        kDefaultAddressList = kDefaultAddressList.reversed.toList(),
    'selected address': () => kSelectedAddress = kDefaultAddressList.first,
    'wallet path': () => kWalletPath = 'replacement-wallet',
    'initialization': () => kWalletInitCompleted = false,
    'locked page with retained file': () => kCurrentPage = Tabs.lock,
  };

  test('a revision change after dispatch preserves the original response', () {
    fakeAsync((FakeAsync clock) {
      final Completer<AccountBlockTemplate> accepted =
          Completer<AccountBlockTemplate>();
      fixture.sendReply = accepted.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      expect(fixture.sendCalls, 1);
      WalletContextRevision.invalidate();
      accepted.complete(fixture.response);
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(outcome.result, same(fixture.response));
      expect(outcome.error, isNull);
      expect(fixture.closeCalls, 1);
      expect(
        fixture.records.single.transactionHash,
        fixture.response.hash.toString(),
      );
      expect(fixture.displayGuards.single(), isFalse);
    });
  });

  for (final MapEntry<String, void Function()> change
      in contextChanges.entries) {
    test('${change.key} is checked immediately before send', () {
      fakeAsync((FakeAsync clock) {
        final Completer<void> display = Completer<void>();
        fixture
          ..needsPlasma = true
          ..plasmaReply = display.future;
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        expect(fixture.plasmaCalls, 1);
        change.value();
        display.complete();
        clock.flushMicrotasks();
        assertRefused(outcome);
        expect(fixture.closeCalls, 1);
        expect(fixture.displayGuards.single(), isFalse);
      });
    });
  }

  test('replacement of mutable client stats is a session change', () {
    fakeAsync((FakeAsync clock) {
      final Completer<SyncInfo> sync = Completer<SyncInfo>();
      fixture.syncReply = sync.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      when(() => fixture.node.stats).thenReturn(MockPublicationStats());
      sync.complete(fixture.syncInfo);
      clock.flushMicrotasks();
      assertRefused(outcome);
      expect(fixture.openCalls, 0);
    });
  });

  test('normal unsynced refusal never acquires a wallet', () {
    fakeAsync((FakeAsync clock) {
      fixture.syncInfo = SyncInfo.fromJson(<String, dynamic>{
        'state': SyncState.syncing.index,
        'currentHeight': 0,
        'targetHeight': 100,
      });
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      expect(outcome.error, isA<NodeNotSyncedException>());
      expect(fixture.openCalls, 0);
      expect(fixture.closeCalls, 0);
      assertNoSigning();
    });
  });

  test(
    'the existing near-frontier sync threshold still permits publication',
    () {
      fakeAsync((FakeAsync clock) {
        fixture.syncInfo = SyncInfo.fromJson(<String, dynamic>{
          'state': SyncState.syncing.index,
          'currentHeight': 81,
          'targetHeight': 100,
        });
        final PublicationOutcome outcome = fixture.publish();
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 1));
        expect(outcome.result, same(fixture.response));
        expect(fixture.sendCalls, 1);
      });
    },
  );

  test('an already locked wallet refuses before contacting the node', () {
    fakeAsync((FakeAsync clock) {
      kWalletFile = null;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      assertRefused(outcome);
      expect(fixture.syncCalls, 0);
      expect(fixture.openCalls, 0);
    });
  });

  for (final bool locked in <bool>[true, false]) {
    test('retained file refuses before RPC when locked=$locked', () {
      fakeAsync((FakeAsync clock) {
        if (locked) {
          kCurrentPage = Tabs.lock;
        } else {
          kWalletInitCompleted = false;
        }
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        assertRefused(outcome);
        expect(fixture.syncCalls, 0);
        expect(fixture.openCalls, 0);
        expect(fixture.closeCalls, 0);
      });
    });
  }

  test(
    'open failure preserves its error without releasing another acquisition',
    () {
      fakeAsync((FakeAsync clock) {
        final StateError failure = StateError('Fixture open failure');
        final Completer<Wallet> acquisition = Completer<Wallet>();
        fixture.openReply = acquisition.future;
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        acquisition.completeError(failure);
        clock.flushMicrotasks();
        expect(outcome.error, same(failure));
        expect(fixture.closeCalls, 0);
        assertNoSigning();
      });
    },
  );

  test(
    'normal publication keeps the exact response, account and original flow',
    () {
      fakeAsync((FakeAsync clock) {
        final Map<String, dynamic> returned = fixture.response.toJson();
        final PublicationOutcome outcome = fixture.publish(waitForPlasma: true);
        clock.flushMicrotasks();
        expect(outcome.settled, isFalse);
        expect(fixture.closeCalls, 0);
        expect(fixture.sendCalls, 1);
        clock.elapse(const Duration(milliseconds: 999));
        expect(outcome.settled, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(outcome.result, same(fixture.response));
        expect(outcome.result!.toJson(), returned);
        expect(fixture.sentTemplate, same(fixture.template));
        expect(fixture.accountIndices, <int>[1]);
        expect(fixture.sentAccount, same(fixture.account));
        expect(fixture.signingAccount, same(fixture.account));
        expect(fixture.waitedForPlasma, isTrue);
        expect(fixture.closeCalls, 1);
        final WalletNotification event = fixture.records.single;
        expect(event.title, currentL10n.accountBlockPublishedNotificationTitle);
        expect(event.type, NotificationType.paymentSent);
        expect(event.eventKind, 'blockPublished');
        expect(event.chainId, PublicationFixture.chain);
        expect(
          event.walletScope,
          bellScopeForWallet(
            PublicationFixture.chain,
            fixture.addresses,
          ),
        );
        expect(event.transactionHash, fixture.response.hash.toString());
        expect(fixture.displayGuards.single(), isTrue);
        expect(fixture.pow.value.phase, PowGenerationPhase.idle);
        expect(fixture.powEvents, isEmpty);
      });
    },
  );

  for (final MapEntry<String, void Function()> change
      in <String, void Function()>{...changes, ...contextChanges}.entries) {
    test(
      '${change.key} after SDK acceptance retains its original scoped result',
      () {
        fakeAsync((FakeAsync clock) {
          final Completer<AccountBlockTemplate> sent =
              Completer<AccountBlockTemplate>();
          fixture
            ..sendReply = sent.future
            ..hardware = true
            ..needsPlasma = true;
          final PublicationOutcome outcome = fixture.publish();
          clock.flushMicrotasks();
          expect(fixture.sendCalls, 1);
          sent.complete(fixture.response);
          change.value();
          fixture.powCallback!(PowStatus.done);
          clock
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 1));
          expect(outcome.error, isNull);
          expect(outcome.result, same(fixture.response));
          expect(fixture.closeCalls, 1);
          expect(fixture.sendCalls, 1);
          expect(fixture.observedAddresses.single, fixture.addresses);
          expect(
            fixture.registry
                .forWallet(PublicationFixture.chain, fixture.addresses)
                .value
                .single
                .hash,
            fixture.response.hash,
          );
          final WalletNotification event = fixture.records.single;
          expect(
            event.walletScope,
            bellScopeForWallet(
              PublicationFixture.chain,
              fixture.addresses,
            ),
          );
          expect(event.chainId, PublicationFixture.chain);
          expect(event.transactionHash, fixture.response.hash.toString());
          expect(
            fixture.displayGuards.every((bool Function() guard) => !guard()),
            isTrue,
          );
          expect(fixture.powEvents, isEmpty);
          if (kWalletFile case final MockPublicationFile replacement
              when !identical(replacement, fixture.file)) {
            verifyNever(replacement.close);
          }
        });
      },
    );
  }

  test('original explicit address uses the original derivation index', () {
    fakeAsync((FakeAsync clock) {
      final PublicationOutcome outcome = fixture.publish(
        address: Address.parse(fixture.addresses.first),
      );
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(outcome.result, same(fixture.response));
      expect(fixture.accountIndices, <int>[0]);
    });
  });

  test('an address outside the originating wallet never opens or signs', () {
    fakeAsync((FakeAsync clock) {
      kDefaultAddressList = <String?>[fixture.addresses.first];
      final PublicationOutcome outcome = fixture.publish(
        address: Address.parse(fixture.addresses.last),
      );
      clock.flushMicrotasks();
      assertRefused(outcome);
      expect(fixture.syncCalls, 0);
      expect(fixture.openCalls, 0);
    });
  });

  for (final String boundary in <String>['observer', 'history', 'close']) {
    test(
      '$boundary failure cannot turn an accepted publication into retry',
      () {
        fakeAsync((FakeAsync clock) {
          final StateError failure = StateError('Fixture $boundary failure');
          switch (boundary) {
            case 'observer':
              fixture.observerFailure = failure;
            case 'history':
              fixture.historyFailure = failure;
            case 'close':
              fixture.closeFailure = failure;
          }
          final PublicationOutcome outcome = fixture.publish();
          clock
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 1));
          expect(outcome.result, same(fixture.response));
          expect(outcome.error, isNull);
          expect(fixture.sendCalls, 1);
          expect(fixture.closeCalls, 1);
          expect(
            fixture.records.single.transactionHash,
            fixture.response.hash.toString(),
          );
        });
      },
    );
  }

  test('an asynchronous close override cannot lose an accepted result', () {
    fakeAsync((FakeAsync clock) {
      final AsyncClosingPublicationFile file = AsyncClosingPublicationFile(
        StateError('Fixture asynchronous close failure'),
      );
      fixture.configureFile(file);
      kWalletFile = file;
      final PublicationOutcome outcome = fixture.publish();
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(outcome.result, same(fixture.response));
      expect(outcome.error, isNull);
      expect(file.closes, 1);
      expect(fixture.closeCalls, 0);
      expect(fixture.sendCalls, 1);
    });
  });

  test(
    'hardware review follows plasma and cannot throw out of the SDK callback',
    () {
      fakeAsync((FakeAsync clock) {
        final Completer<AccountBlockTemplate> sent =
            Completer<AccountBlockTemplate>();
        fixture
          ..hardware = true
          ..needsPlasma = true
          ..sendReply = sent.future;
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        expect(fixture.plasmaCalls, 1);
        expect(fixture.records, isEmpty);
        fixture.historyFailure = StateError('Fixture review display failure');
        fixture.powCallback!(PowStatus.done);
        clock.flushMicrotasks();
        expect(fixture.pow.value.phase, PowGenerationPhase.completed);
        expect(fixture.powEvents, <PowStatus>[PowStatus.done]);
        expect(fixture.records.single.type, NotificationType.confirm);
        fixture.historyFailure = null;
        fixture.powCallback!(PowStatus.done);
        clock.flushMicrotasks();
        expect(fixture.powEvents, <PowStatus>[PowStatus.done]);
        expect(fixture.records, hasLength(1));
        sent.complete(fixture.response);
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 1));
        expect(outcome.result, same(fixture.response));
        expect(fixture.sendCalls, 1);
        expect(fixture.records.last.eventKind, 'blockPublished');
      });
    },
  );

  test('lock during hardware review refuses before publication', () {
    fakeAsync((FakeAsync clock) {
      final Completer<void> reviewed = Completer<void>();
      fixture
        ..hardware = true
        ..reviewReply = reviewed.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      expect(fixture.records.single.type, NotificationType.confirm);
      kWalletFile = null;
      reviewed.complete();
      clock.flushMicrotasks();
      assertRefused(outcome);
      expect(fixture.closeCalls, 1);
      expect(fixture.displayGuards.single(), isFalse);
    });
  });

  test('original send failure surfaces even when release also fails', () {
    fakeAsync((FakeAsync clock) {
      final StateError failure = StateError('Fixture original send failure');
      fixture
        ..sendFailure = failure
        ..closeFailure = StateError('Fixture release failure');
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      expect(outcome.error, same(failure));
      expect(outcome.result, isNull);
      expect(fixture.sendCalls, 1);
      expect(fixture.closeCalls, 1);
      expect(fixture.observerCalls, 0);
      expect(fixture.records, isEmpty);
    });
  });

  test(
    'SDK failure without done clears only its display and keeps its error',
    () {
      fakeAsync((FakeAsync clock) {
        final Completer<AccountBlockTemplate> sent =
            Completer<AccountBlockTemplate>();
        final StateError failure = StateError('Fixture original SDK failure');
        fixture.sendReply = sent.future;
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        fixture.powCallback!(PowStatus.generating);
        clock.flushMicrotasks();
        expect(fixture.pow.value.isGenerating, isTrue);
        sent.completeError(failure);
        clock.flushMicrotasks();
        expect(outcome.error, same(failure));
        expect(outcome.result, isNull);
        expect(fixture.pow.value.phase, PowGenerationPhase.idle);
        expect(fixture.powEvents, <PowStatus>[PowStatus.generating]);
        expect(fixture.sendCalls, 1);
        expect(fixture.closeCalls, 1);
        expect(fixture.observerCalls, 0);
        fixture.powCallback!(PowStatus.done);
        clock.flushMicrotasks();
        expect(fixture.powEvents, <PowStatus>[PowStatus.generating]);
      });
    },
  );

  test(
    'accepted send without done clears display and keeps its exact hash',
    () {
      fakeAsync((FakeAsync clock) {
        final Completer<AccountBlockTemplate> sent =
            Completer<AccountBlockTemplate>();
        fixture.sendReply = sent.future;
        final Map<String, dynamic> accepted = fixture.response.toJson();
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        fixture.powCallback!(PowStatus.generating);
        clock.flushMicrotasks();
        sent.complete(fixture.response);
        clock.flushMicrotasks();
        expect(fixture.pow.value.phase, PowGenerationPhase.idle);
        expect(fixture.powEvents, <PowStatus>[PowStatus.generating]);
        clock.elapse(const Duration(seconds: 1));
        expect(outcome.result, same(fixture.response));
        expect(outcome.result!.toJson(), accepted);
        expect(fixture.sendCalls, 1);
        expect(fixture.closeCalls, 1);
      });
    },
  );

  test('observed context invalidation stays revoked after restoration', () {
    fakeAsync((FakeAsync clock) {
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      fixture.sendReply = sent.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      fixture.powCallback!(PowStatus.generating);
      clock.flushMicrotasks();
      kCurrentPage = Tabs.lock;
      fixture.powCallback!(PowStatus.done);
      clock.flushMicrotasks();
      expect(fixture.pow.value.phase, PowGenerationPhase.idle);
      kCurrentPage = Tabs.dashboard;
      fixture.powCallback!(PowStatus.generating);
      fixture.powCallback!(PowStatus.done);
      clock.flushMicrotasks();
      expect(fixture.powEvents, <PowStatus>[PowStatus.generating]);
      sent.complete(fixture.response);
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(outcome.result, same(fixture.response));
      expect(fixture.displayGuards.single(), isFalse);
      expect(fixture.sendCalls, 1);
      expect(fixture.closeCalls, 1);
    });
  });

  test('revoked callbacks and SDK settlement cannot clear a fresh owner', () {
    fakeAsync((FakeAsync clock) {
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      fixture.sendReply = sent.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      fixture.powCallback!(PowStatus.generating);
      clock.flushMicrotasks();
      fixture.pow.invalidate();
      final PowWorkToken replacement = fixture.pow.claimWork();
      fixture.pow.update(replacement, PowStatus.generating);
      fixture.powCallback!(PowStatus.done);
      fixture.powCallback!(PowStatus.generating);
      clock.flushMicrotasks();
      expect(fixture.pow.value.work, same(replacement));
      expect(fixture.pow.value.isGenerating, isTrue);
      sent.complete(fixture.response);
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(outcome.result, same(fixture.response));
      expect(fixture.pow.value.work, same(replacement));
      expect(fixture.pow.value.isGenerating, isTrue);
      expect(fixture.sendCalls, 1);
      expect(fixture.closeCalls, 1);
    });
  });

  test('actual done reaches the display before a hardware review waits', () {
    fakeAsync((FakeAsync clock) {
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      final Completer<void> reviewed = Completer<void>();
      fixture
        ..sendReply = sent.future
        ..reviewReply = reviewed.future
        ..hardware = true
        ..needsPlasma = true;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      fixture.powCallback!(PowStatus.generating);
      fixture.powCallback!(PowStatus.done);
      clock.flushMicrotasks();
      expect(fixture.pow.value.phase, PowGenerationPhase.completed);
      expect(fixture.powEvents, <PowStatus>[
        PowStatus.generating,
        PowStatus.done,
      ]);
      expect(fixture.records.single.type, NotificationType.confirm);
      expect(outcome.settled, isFalse);
      reviewed.complete();
      sent.complete(fixture.response);
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(outcome.result, same(fixture.response));
      expect(fixture.pow.value.phase, PowGenerationPhase.idle);
      expect(fixture.sendCalls, 1);
    });
  });

  test('a PoW display observer failure cannot replace the accepted result', () {
    fakeAsync((FakeAsync clock) {
      final Completer<AccountBlockTemplate> sent =
          Completer<AccountBlockTemplate>();
      fixture.sendReply = sent.future;
      final PublicationOutcome outcome = fixture.publish();
      clock.flushMicrotasks();
      fixture.powDisplayFailure = StateError(
        'Fixture display observer failure',
      );
      fixture.powCallback!(PowStatus.generating);
      fixture.powCallback!(PowStatus.done);
      clock.flushMicrotasks();
      expect(fixture.pow.value.phase, PowGenerationPhase.completed);
      sent.complete(fixture.response);
      clock
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(outcome.result, same(fixture.response));
      expect(outcome.error, isNull);
      expect(fixture.pow.value.phase, PowGenerationPhase.idle);
      expect(fixture.sendCalls, 1);
      expect(fixture.closeCalls, 1);
    });
  });

  test(
    'locking after send starts cannot report the original send as cancelled',
    () {
      fakeAsync((FakeAsync clock) {
        final Completer<AccountBlockTemplate> sent =
            Completer<AccountBlockTemplate>();
        final StateError failure = StateError('Fixture SDK send failure');
        fixture.sendReply = sent.future;
        final PublicationOutcome outcome = fixture.publish();
        clock.flushMicrotasks();
        expect(fixture.sendCalls, 1);
        kWalletFile = null;
        sent.completeError(failure);
        clock.flushMicrotasks();
        expect(outcome.error, same(failure));
        expect(outcome.result, isNull);
        expect(fixture.sendCalls, 1);
        expect(fixture.closeCalls, 1);
        expect(fixture.records, isEmpty);
      });
    },
  );
}
