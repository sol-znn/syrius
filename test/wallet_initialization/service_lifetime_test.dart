import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_worker_origin.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';

import '../htlc_ownership/support.dart';

class _LifetimeFixture {
  _LifetimeFixture() {
    originalFile = source.wallet;
    file = originalFile;
    originalTransport = source.transport;
    originalApi = source.api;
    originalService = source.service;
    service = originalService;
    originalPath = source.path;
    anchor = source.members.first;
    pointer.entries[0] = originalPath;
    members.entries[0] = anchor;
    originalPointer = pointer;
    originalMembers = members;
    lifetime = WalletInitializationLifetime(
      startupIsCurrent: () =>
          routeCurrent && identical(file, originalFile) && ownersCurrent(),
      committedSourceIsCurrent: () =>
          committed && initialized && identical(file, originalFile),
      ownerIsCurrent: () => committed && initialized && ownersCurrent(),
    );
  }

  final HtlcFixture source = HtlcFixture(751);
  late final Object originalFile;
  late final Object originalTransport;
  late final Object originalApi;
  late final Object originalService;
  late final String originalPath;
  late final String anchor;
  late final MemoryHtlcBox originalPointer;
  late final MemoryHtlcBox originalMembers;
  late final WalletInitializationLifetime lifetime;
  MemoryHtlcBox pointer = MemoryHtlcBox('synthetic-pointer');
  MemoryHtlcBox members = MemoryHtlcBox('synthetic-members');
  late Object service;
  Object? file;
  bool routeCurrent = true;
  bool committed = false;
  bool initialized = false;

  bool ownersCurrent() =>
      source.store.isCurrent &&
      identical(service, originalService) &&
      identical(source.api, originalApi) &&
      identical(source.transport, originalTransport) &&
      source.path == originalPath &&
      identical(pointer, originalPointer) &&
      pointer.isOpen &&
      pointer.entries.length == 1 &&
      pointer.get(0) == originalPath &&
      identical(members, originalMembers) &&
      members.isOpen &&
      members.get(0) == anchor &&
      !source.service.isPaused;

  void publish() {
    committed = true;
    initialized = true;
  }
}

void main() {
  test('handoff requires the actual commit and cannot be retried', () {
    final _LifetimeFixture fixture = _LifetimeFixture();
    expect(fixture.lifetime.isCurrent, isTrue);
    expect(fixture.lifetime.handoff(), isFalse);
    fixture.publish();
    expect(fixture.lifetime.handoff(), isFalse);
    expect(fixture.lifetime.isCurrent, isFalse);
  });

  test('one handoff removes only the original file and route dependency', () {
    final _LifetimeFixture fixture = _LifetimeFixture()..publish();
    expect(fixture.lifetime.handoff(), isTrue);
    expect(fixture.lifetime.handoff(), isFalse);
    fixture
      ..routeCurrent = false
      ..file = null;
    final List<String> viewMembers = List<String>.of(fixture.source.members);
    fixture.source.members.clear();
    expect(fixture.lifetime.isCurrent, isTrue);
    fixture.source.members.addAll(viewMembers);
    fixture.file = Object();
    expect(fixture.lifetime.isCurrent, isTrue);
  });

  for (final String proof in <String>['startup', 'commit', 'owner']) {
    for (final bool throws in <bool>[false, true]) {
      test('$proof proof failure remains terminal, throwing=$throws', () {
        bool failed = true;
        bool answer(String current) {
          if (current != proof || !failed) {
            return true;
          }
          if (throws) {
            throw StateError('Synthetic original proof failure');
          }
          return false;
        }

        final WalletInitializationLifetime lifetime =
            WalletInitializationLifetime(
              startupIsCurrent: () => answer('startup'),
              committedSourceIsCurrent: () => answer('commit'),
              ownerIsCurrent: () => answer('owner'),
            );
        expect(lifetime.handoff(), isFalse);
        failed = false;
        expect(lifetime.isCurrent, isFalse);
        expect(lifetime.handoff(), isFalse);
      });
    }
  }

  for (final bool afterHandoff in <bool>[false, true]) {
    test(
      'nested proof refusal survives outer success, handed=$afterHandoff',
      () {
        bool armed = false;
        bool nested = false;
        bool valid = true;
        int proofs = 0;
        late final WalletInitializationLifetime lifetime;
        bool proof() {
          proofs++;
          if (armed && !nested) {
            nested = true;
            valid = false;
            expect(lifetime.isCurrent, isFalse);
            valid = true;
            return true;
          }
          return valid;
        }

        lifetime = WalletInitializationLifetime(
          startupIsCurrent: afterHandoff ? () => true : proof,
          committedSourceIsCurrent: () => true,
          ownerIsCurrent: afterHandoff ? proof : () => true,
        );
        if (afterHandoff) {
          expect(lifetime.handoff(), isTrue);
        }
        proofs = 0;
        armed = true;
        expect(lifetime.isCurrent, isFalse);
        expect(valid, isTrue);
        expect(proofs, 2);
        expect(lifetime.isCurrent, isFalse);
        expect(lifetime.handoff(), isFalse);
        expect(proofs, 2);
      },
    );
  }

  test('nested commit refusal prevents the pending handoff', () {
    bool startup = true;
    late final WalletInitializationLifetime lifetime;
    lifetime = WalletInitializationLifetime(
      startupIsCurrent: () => startup,
      committedSourceIsCurrent: () {
        startup = false;
        expect(lifetime.isCurrent, isFalse);
        startup = true;
        return true;
      },
      ownerIsCurrent: () => true,
    );
    expect(lifetime.handoff(), isFalse);
    expect(lifetime.isCurrent, isFalse);
    expect(startup, isTrue);
  });

  for (final String resource in <String>[
    'store',
    'transport',
    'api',
    'path',
    'pointer',
    'members',
    'anchor',
    'service',
  ]) {
    test('committed $resource loss refuses even after exact restoration', () {
      final _LifetimeFixture fixture = _LifetimeFixture()..publish();
      expect(fixture.lifetime.handoff(), isTrue);
      final void Function() restore;
      switch (resource) {
        case 'store':
          fixture.source.owned.remove(fixture.source.swaps);
          restore = () => fixture.source.owned.add(fixture.source.swaps);
        case 'transport':
          fixture.source.transport = Object();
          restore = () => fixture.source.transport = fixture.originalTransport;
        case 'api':
          fixture.source.api = Object();
          restore = () => fixture.source.api = fixture.originalApi;
        case 'path':
          fixture.source.path = 'different-synthetic-wallet';
          restore = () => fixture.source.path = fixture.originalPath;
        case 'pointer':
          fixture.pointer = MemoryHtlcBox('synthetic-pointer')
            ..entries[0] = fixture.originalPath;
          restore = () => fixture.pointer = fixture.originalPointer;
        case 'members':
          fixture.members = MemoryHtlcBox('synthetic-members')
            ..entries[0] = fixture.anchor;
          restore = () => fixture.members = fixture.originalMembers;
        case 'anchor':
          fixture.members.entries[0] = htlcOwner(99);
          restore = () => fixture.members.entries[0] = fixture.anchor;
        default:
          fixture.service = Object();
          restore = () => fixture.service = fixture.originalService;
      }
      expect(fixture.lifetime.isCurrent, isFalse);
      restore();
      expect(fixture.lifetime.isCurrent, isFalse);
      expect(fixture.lifetime.handoff(), isFalse);
    });
  }

  test('terminal service pause cannot become another startup', () async {
    final _LifetimeFixture fixture = _LifetimeFixture()..publish();
    expect(fixture.lifetime.handoff(), isTrue);
    expect((await fixture.source.service.pauseAndDrain()).completed, isTrue);
    expect(fixture.lifetime.isCurrent, isFalse);
    expect(fixture.lifetime.handoff(), isFalse);
  });

  test(
    'real handler admits a fresh cycle after lock without reviving old work',
    () async {
      final _LifetimeFixture fixture = _LifetimeFixture();
      fixture.source.record = htlcRecord(
        751,
        direction: P2pSwapDirection.outgoing,
      );
      fixture.source.seedRecord(fixture.source.record);
      fixture.source.blocks.add(htlcBlock());
      final List<HtlcWorkerOrigin> origins = <HtlcWorkerOrigin>[];
      final HtlcSwapsHandler handler = HtlcSwapsHandler(
        captureOrigin: () {
          if (!fixture.source.ready || fixture.file == null) {
            return null;
          }
          final HtlcWorkerOrigin origin = fixture.source.capture();
          origins.add(origin);
          return origin;
        },
      );
      final HtlcHandlerStart reservation = handler.reserveStart(
        isCurrent: () => fixture.lifetime.isCurrent,
      )!;
      try {
        expect(reservation.canActivate, isTrue);
        expect(reservation.activate(), isTrue);
        fixture.publish();
        expect(fixture.lifetime.handoff(), isTrue);
        await reservation.startup!.settled;
        expect(reservation.startup!.error, isNull);
        expect(origins, hasLength(1));
        final HtlcWorkerOrigin original = origins.single;
        final int reads = fixture.source.syncCalls;
        expect(original.isCurrent, isTrue);
        fixture
          ..routeCurrent = false
          ..file = null;
        fixture.source.ready = false;
        expect(original.isCurrent, isFalse);
        expect(fixture.lifetime.isCurrent, isTrue);
        await handler.runOnce();
        expect(origins, hasLength(1));
        expect(fixture.source.syncCalls, reads);
        final Object authenticatedFile = Object();
        fixture.file = authenticatedFile;
        fixture.source
          ..wallet = authenticatedFile
          ..ready = true;
        expect(fixture.lifetime.isCurrent, isTrue);
        expect(original.isCurrent, isFalse);
        await handler.runOnce();
        expect(origins, hasLength(2));
        expect(origins.last.walletIdentity, same(authenticatedFile));
        expect(origins.last.isCurrent, isTrue);
        expect(original.isCurrent, isFalse);
        expect(fixture.source.syncCalls, reads + 1);
        expect(reservation.activate(), isFalse);
      } finally {
        expect((await handler.pauseAndDrain()).completed, isTrue);
      }
    },
  );
}
