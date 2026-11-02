import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

void main() {
  initHydratedStorage();
  late ReceiveFixture fixture;
  setUp(() {
    fixture = ReceiveFixture();
  });
  tearDown(() async {
    await fixture.close();
  });
  final Hash inbound = receiveHash(21);

  for (final bool pauseInPreference in <bool>[false, true]) {
    test(
      'automatic admission rechecks a reentrant terminal pause '
      'in $pauseInPreference',
      () async {
        Future<ReceiveDrainReceipt>? drain;
        bool armed = false;
        final ReceiveOrigin origin = fixture.capture(
          sourceIsCurrent: () {
            if (armed && !pauseInPreference) {
              drain ??= fixture.worker.pauseAndDrain();
            }
            return true;
          },
        );
        fixture.onReadAutomatic = () {
          if (armed && pauseInPreference) {
            drain ??= fixture.worker.pauseAndDrain();
          }
        };
        armed = true;
        await fixture.enqueue(inbound, origin: origin);
        expect(drain, isNotNull);
        final ReceiveDrainReceipt receipt = await drain!;
        expect(receipt.completed, isTrue);
        expect(receipt.reads, isEmpty);
        expect(receipt.publications, isEmpty);
        expect(fixture.syncReads, 0);
        expect(fixture.proofReads, 0);
        expect(fixture.transport.calls, isEmpty);
        expect(fixture.worker.hasPending, isFalse);
      },
    );
  }

  test('a reentrant pause cannot finish capturing a fresh origin', () async {
    Future<ReceiveDrainReceipt>? drain;
    final ReceiveOrigin? origin = fixture.worker.captureOrigin(
      sourceIsCurrent: () {
        drain ??= fixture.worker.pauseAndDrain();
        return true;
      },
    );
    expect(origin, isNull);
    expect(fixture.worker.isPaused, isTrue);
    expect((await drain!).completed, isTrue);
    expect(fixture.proofReads, 0);
    expect(fixture.transport.calls, isEmpty);
  });

  test(
    'an active read reserved during a pausing observer remains in its drain',
    () async {
      final Completer<AccountBlock?> reply = Completer<AccountBlock?>();
      addTearDown(() {
        if (!reply.isCompleted) reply.complete(receiveInbound(inbound));
      });
      fixture.readInbound = (_) => reply.future;
      Future<ReceiveDrainReceipt>? drain;
      void pauseOnMark() {
        if (fixture.worker.inFlight.value.isNotEmpty) {
          drain ??= fixture.worker.pauseAndDrain();
        }
      }

      fixture.worker.inFlight.addListener(pauseOnMark);
      addTearDown(() => fixture.worker.inFlight.removeListener(pauseOnMark));
      final Future<AccountBlockTemplate?> original = fixture.worker
          .autoReceiveTransactionHash(inbound);
      await receiveTurnsUntil(() => fixture.proofReads == 1);
      expect(drain, isNotNull);
      bool settled = false;
      unawaited(drain!.then<void>((_) => settled = true));
      await Future<void>.value();
      expect(settled, isFalse);
      reply.complete(receiveInbound(inbound));
      expect(await original, isNotNull);
      final ReceiveDrainReceipt receipt = await drain!;
      expect(receipt.completed, isTrue);
      expect(receipt.reads.single.name, 'inbound');
      expect(receipt.reads.single.future, isNotNull);
      expect(receipt.reads.single.completed, isTrue);
      expect(receipt.publications.single.result, isNotNull);
    },
  );

  test('terminal pause waits for the actual original inbound read', () async {
    final Completer<AccountBlock?> reply = Completer<AccountBlock?>();
    addTearDown(() {
      if (!reply.isCompleted) reply.complete(receiveInbound(inbound));
    });
    fixture.readInbound = (_) => reply.future;
    final Future<AccountBlockTemplate?> original = fixture.worker
        .autoReceiveTransactionHash(inbound);
    await receiveTurnsUntil(() => fixture.proofReads == 1);
    final Future<ReceiveDrainReceipt> drain = fixture.worker.pauseAndDrain();
    bool settled = false;
    unawaited(drain.then<void>((_) => settled = true));
    await Future<void>.value();
    expect(settled, isFalse);
    reply.complete(receiveInbound(inbound));
    expect(await original, isNotNull);
    final ReceiveDrainReceipt receipt = await drain;
    expect(receipt.owner, same(fixture.worker));
    expect(receipt.completed, isTrue);
    expect(receipt.publications.single.result, isNotNull);
    expect(receipt.reads.single.completed, isTrue);
    expect(fixture.worker.pauseAndDrain(), same(drain));
  });

  test('terminal pause waits for an admitted original SDK outcome', () async {
    fixture.transport.deferred = true;
    final Future<AccountBlockTemplate?> original = fixture.worker
        .autoReceiveTransactionHash(inbound);
    await receiveTurnsUntil(() => fixture.transport.pending.length == 1);
    final Future<ReceiveDrainReceipt> drain = fixture.worker.pauseAndDrain();
    bool settled = false;
    unawaited(drain.then<void>((_) => settled = true));
    await Future<void>.value();
    expect(settled, isFalse);
    final AccountBlockTemplate accepted = fixture.transport.complete();
    expect(await original, same(accepted));
    final ReceiveDrainReceipt receipt = await drain;
    expect(receipt.completed, isTrue);
    expect(receipt.publications.single.result!.block, same(accepted));
    await expectLater(
      fixture.worker.autoReceiveTransactionHash(receiveHash(22)),
      throwsA(isA<ReceiveRefused>()),
    );
    expect(fixture.worker.captureOrigin(), isNull);
    expect(
      () => fixture.worker.attachSender(fixture.sender),
      throwsA(isA<ReceiveRefused>()),
    );
  });

  test(
    'clearing a pending sync admission still waits for its original Future',
    () async {
      fixture.automatic = true;
      final Completer<SyncInfo> sync = Completer<SyncInfo>();
      addTearDown(() {
        if (!sync.isCompleted) sync.complete(receiveSync());
      });
      fixture.readSync = () => sync.future;
      final Future<void> original = fixture.enqueue(inbound);
      await receiveTurnsUntil(() => fixture.syncReads == 1);
      final Future<ReceiveDrainReceipt> drain = fixture.worker.pauseAndDrain();
      bool settled = false;
      unawaited(drain.then<void>((_) => settled = true));
      await Future<void>.value();
      expect(settled, isFalse);
      sync.complete(receiveSync());
      await original;
      final ReceiveDrainReceipt receipt = await drain;
      expect(receipt.completed, isTrue);
      expect(receipt.reads.single.result, isA<SyncInfo>());
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test(
    'a failed original read remains a failed positive-drain requirement',
    () async {
      final StateError error = StateError('Synthetic original read failure');
      fixture.readInbound = (_) => Future<AccountBlock?>.error(error);
      await expectLater(
        fixture.worker.autoReceiveTransactionHash(inbound),
        throwsA(same(error)),
      );
      await receiveTurnsUntil(() => !fixture.worker.running);
      final ReceiveDrainReceipt receipt = await fixture.worker.pauseAndDrain();
      expect(receipt.completed, isFalse);
      expect(receipt.reads.single.completed, isTrue);
      expect(receipt.reads.single.error, same(error));
      expect(receipt.publications, isEmpty);
      expect(fixture.transport.calls, isEmpty);
    },
  );
}
