import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  test('a returning action proof cannot erase nested source refusal', () async {
    final ActionFixture fixture = ActionFixture();
    bool current = true;
    bool reenter = false;
    final List<bool> nested = <bool>[];
    late final SwapActionOrigin origin;
    origin = fixture.origin(
      sourceIsCurrent: () {
        final bool accepted = current;
        if (reenter) {
          reenter = false;
          current = false;
          nested.add(origin.isCurrent);
          current = true;
        }
        return accepted;
      },
    );
    expect(origin.isCurrent, isTrue);
    reenter = true;
    expect(origin.isCurrent, isFalse);
    expect(nested, <bool>[false]);
    expect(current, isTrue);
    expect(origin.isCurrent, isFalse);
    expect(origin.requireCurrent, throwsA(isA<SwapActionRefused>()));
    final SwapActionResult result = await SwapActions.start(
      origin,
      selfAddress: fixture.owner,
      counterparty: fixture.counterparty,
      fromToken: fixture.token,
      amount: BigInt.one,
      hashType: htlcHashTypeSha3,
    );
    expect(result.status, SwapActionStatus.refused);
    expect(result.error, isA<SwapActionRefused>());
    expect(fixture.events, isEmpty);
    expect(fixture.senderCaptures, 0);
    expect(fixture.storeReservations, 0);
    expect(fixture.markerReservations, 0);
    expect(fixture.publications, 0);
  });

  test(
    'original sender and both store reservations precede the first RPC',
    () async {
      final ActionFixture fixture = ActionFixture();
      fixture.onToken = () {
        expect(fixture.senderCaptures, 1);
        expect(fixture.storeReservations, 1);
        expect(fixture.markerReservations, 1);
      };
      final SwapActionResult result = await fixture.start();
      expect(result.status, SwapActionStatus.submitted);
      expect(fixture.events.take(4), <String>[
        'capture-sender',
        'reserve-store',
        'reserve-marker',
        'read-token',
      ]);
      expect(
        fixture.store.stored!.initialHtlcExpirationTime,
        fixture.now + kInitialHtlcDuration.inSeconds,
      );
      expect(result.persistence, same(fixture.store.original));
      expect(result.preparation, same(fixture.marker.prepareOriginal));
    },
  );

  test(
    'SDK publication waits for original durable secret preparation',
    () async {
      final ActionFixture fixture = ActionFixture();
      final Completer<void> prepared = fixture.ownCompleter<void>();
      fixture.marker.prepareReply = prepared.future;
      final Future<SwapActionResult> pending = fixture.start();
      await microtasksUntil(() => fixture.marker.preparations == 1);
      expect(fixture.publications, 0);
      expect(
        fixture.marker.recovery!['preimage'],
        hasLength(htlcPreimageDefaultLength * 2),
      );
      expect(
        fixture.marker.recovery!['expirationTime'],
        fixture.now + kInitialHtlcDuration.inSeconds,
      );
      prepared.complete();
      expect((await pending).status, SwapActionStatus.submitted);
      expect(fixture.publications, 1);
      expect(fixture.store.writes, 1);
    },
  );

  test(
    'known source loss before publication releases only original reservations',
    () async {
      final ActionFixture fixture = ActionFixture();
      final Completer<Token?> reply = fixture.ownCompleter<Token?>();
      fixture.tokenReply = reply.future;
      final Future<SwapActionResult> pending = fixture.start();
      await microtasksUntil(() => fixture.events.contains('read-token'));
      fixture.current = false;
      reply.complete(fixture.token);
      expect((await pending).status, SwapActionStatus.refused);
      expect(fixture.publications, 0);
      expect(fixture.store.refusals, 1);
      expect(fixture.marker.refusals, 1);
    },
  );

  test(
    'source loss after SDK handoff '
    'preserves original acceptance and persistence',
    () async {
      final ActionFixture fixture = ActionFixture();
      final Completer<AccountBlockTemplate> reply = fixture
          .ownCompleter<AccountBlockTemplate>();
      fixture.publicationReply = reply.future;
      final Future<SwapActionResult> pending = fixture.start();
      await microtasksUntil(() => fixture.publications == 1);
      final AccountBlockTemplate accepted = fixture.sent!;
      fixture.current = false;
      reply.complete(accepted);
      final SwapActionResult result = await pending;
      expect(result.status, SwapActionStatus.submitted);
      expect(result.block, same(accepted));
      expect(result.acceptedHash, actionHash(1));
      expect(fixture.store.stored!.id, actionHash(1));
    },
  );

  test('accepted hash is copied before asynchronous marker storage', () async {
    final ActionFixture fixture = ActionFixture();
    final Completer<void> marker = fixture.ownCompleter<void>();
    fixture.marker.acceptedReply = marker.future;
    final Future<SwapActionResult> pending = fixture.start();
    await microtasksUntil(() => fixture.marker.acceptances == 1);
    fixture.sent!.hash = Hash.parse(actionHash(99));
    marker.complete();
    final SwapActionResult result = await pending;
    expect(result.block, same(fixture.sent));
    expect(result.acceptedHash, actionHash(1));
    expect(result.swap!.id, actionHash(1));
    expect(fixture.marker.acceptedHash, actionHash(1));
  });

  test(
    'uncertain SDK result keeps its exact failure and never signs again',
    () async {
      final ActionFixture fixture = ActionFixture();
      final StateError error = StateError('Synthetic transport loss');
      final StackTrace trace = StackTrace.current;
      final Completer<AccountBlockTemplate> reply = fixture
          .ownCompleter<AccountBlockTemplate>();
      fixture.publicationReply = reply.future;
      final Future<SwapActionResult> pending = fixture.start();
      await microtasksUntil(() => fixture.publications == 1);
      reply.completeError(error, trace);
      final SwapActionResult result = await pending;
      expect(result.status, SwapActionStatus.unknown);
      expect(result.error, same(error));
      expect(result.stackTrace, same(trace));
      expect(fixture.marker.unknowns, 1);
      expect(fixture.store.unknowns, 1);
      expect(fixture.start(), same(pending));
      expect(fixture.publications, 1);
    },
  );

  test(
    'failed original recovery write cannot replace the accepted hash',
    () async {
      final ActionFixture fixture = ActionFixture();
      final StateError error = StateError('Synthetic recovery failure');
      fixture.store.error = error;
      final SwapActionResult result = await fixture.start();
      expect(result.status, SwapActionStatus.unknown);
      expect(result.block, same(fixture.sent));
      expect(result.acceptedHash, actionHash(1));
      expect(result.error, same(error));
      expect(result.persistence, same(fixture.store.original));
      expect(fixture.store.unknowns, 0);
      expect(fixture.publications, 1);
    },
  );

  test(
    'failed preparation cannot reach the SDK or masquerade as no action',
    () async {
      final ActionFixture fixture = ActionFixture();
      final Completer<void> prepared = fixture.ownCompleter<void>();
      fixture.marker.prepareReply = prepared.future;
      final Future<SwapActionResult> pending = fixture.start();
      await microtasksUntil(() => fixture.marker.preparations == 1);
      prepared.completeError(StateError('Synthetic preparation uncertainty'));
      final SwapActionResult result = await pending;
      expect(result.status, SwapActionStatus.unknown);
      expect(fixture.publications, 0);
      expect(fixture.start(), same(pending));
    },
  );

  test(
    'unknown or absent confirmation cannot release an accepted start',
    () async {
      final ActionFixture fixture = ActionFixture();
      final Future<SwapActionResult> original = fixture.start();
      await original;
      expect(
        await SwapActions.releaseConfirmedStart(
          fixture.origin(),
          fixture.owner,
        ),
        isFalse,
      );
      expect(fixture.rearmCalls, 0);
      expect(fixture.start(), same(original));
      fixture.confirmed = confirmedAction(fixture.sent!);
      fixture.confirmed!.hash = Hash.parse(actionHash(50));
      expect(
        await SwapActions.releaseConfirmedStart(
          fixture.origin(),
          fixture.owner,
        ),
        isFalse,
      );
      expect(fixture.rearmCalls, 0);
    },
  );

  test(
    'explicit New deposit also waits for positive original marker release',
    () async {
      final ActionFixture fixture = ActionFixture();
      final Future<SwapActionResult> original = fixture.start();
      await original;
      fixture.confirmed = confirmedAction(fixture.sent!);
      expect(
        await SwapActions.releaseConfirmedStart(
          fixture.origin(),
          fixture.owner,
        ),
        isFalse,
      );
      expect(fixture.start(), same(original));
      fixture.rearm = true;
      expect(
        await SwapActions.releaseConfirmedStart(
          fixture.origin(),
          fixture.owner,
        ),
        isTrue,
      );
      expect(fixture.publications, 1);
      final Future<SwapActionResult> next = fixture.start();
      expect(next, isNot(same(original)));
      await next;
      expect(fixture.publications, 2);
    },
  );

  test(
    'nonpositive amounts refuse before preparation or publication',
    () async {
      for (final BigInt amount in <BigInt>[BigInt.zero, -BigInt.one]) {
        final ActionFixture fixture = ActionFixture();
        final SwapActionResult result = await fixture.start(amount: amount);
        expect(result.status, SwapActionStatus.refused);
        expect(fixture.publications, 0);
        expect(fixture.marker.preparations, 0);
      }
    },
  );
}
