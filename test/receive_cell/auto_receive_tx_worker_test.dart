import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

class _LoadingObserver extends BlocObserver {
  _LoadingObserver(this.revoke);
  SendTransactionBloc? sender;
  final void Function() revoke;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    if (identical(bloc, sender) &&
        change.nextState is SendTransactionState &&
        (change.nextState as SendTransactionState).status ==
            SendTransactionStatus.loading) {
      revoke();
    }
    super.onChange(bloc, change);
  }
}

void main() {
  initHydratedStorage();
  late ReceiveFixture fixture;
  final Hash hash = receiveHash(1);
  setUp(() => fixture = ReceiveFixture());
  tearDown(() => fixture.close());

  test(
    'manual proof reserves the sender and keeps exact owner and units',
    () async {
      final String destination = tokenAddress.toString();
      fixture.addresses.add(destination);
      fixture.selectedAddress = destination;
      final ReceiveOrigin origin = fixture.capture();
      final Completer<AccountBlock?> proof = Completer<AccountBlock?>();
      fixture.readInbound = (_) => proof.future;
      final Future<AccountBlockTemplate?> first = fixture.worker
          .autoReceiveTransactionHash(hash, origin: origin);
      expect(fixture.sender.busy.value, isTrue);
      expect(fixture.sender.tryReserve(Object()), isFalse);
      expect(
        fixture.worker.autoReceiveTransactionHash(hash, origin: origin),
        same(first),
      );
      final AccountBlock inbound = receiveInbound(
        hash,
        destination: tokenAddress,
      );
      proof.complete(inbound);
      final AccountBlockTemplate? response = await first;
      await receiveTurnsUntil(() => !fixture.worker.running);
      final ReceiveRecord original = fixture.worker.originals.single;
      expect(fixture.reservedDuringRead, <bool>[true]);
      expect(fixture.transport.calls.single.owner, tokenAddress);
      expect(
        fixture.transport.calls.single.block.chainIdentifier,
        receiveChain,
      );
      expect(fixture.transport.calls.single.block.fromBlockHash, hash);
      expect(original.result, same(await original.handle!.result));
      expect(original.result!.block, same(response));
      expect(original.future, same(first));
      expect(inbound.amount, BigInt.parse('900719925474099300000001'));
      expect(fixture.successOwners, <String>[destination]);
      expect(fixture.worker.inFlight.value, <Hash>{hash});
      expect(fixture.sender.busy.value, isFalse);
    },
  );

  test('manual receive does not read the automatic preference', () async {
    fixture.automatic = false;
    final AccountBlockTemplate? response = await fixture.worker
        .autoReceiveTransactionHash(hash);
    expect(response, isNotNull);
    expect(fixture.preferenceReads, 0);
    expect(fixture.transport.dispatched, 1);
  });

  test('empty inbound identity refuses before a fresh read', () async {
    await expectLater(
      fixture.worker.autoReceiveTransactionHash(emptyHash),
      throwsA(isA<ReceiveRefused>()),
    );
    await receiveTurnsUntil(() => !fixture.worker.running);
    expect(fixture.proofReads, 0);
    expect(fixture.transport.calls, isEmpty);
    expect(fixture.worker.inFlight.value, isEmpty);
  });

  test('known read failure rearms through a new fresh proof', () async {
    final StateError error = StateError('Synthetic read failure');
    fixture.readInbound = (_) => Future<AccountBlock?>.error(error);
    final Future<AccountBlockTemplate?> first = fixture.worker
        .autoReceiveTransactionHash(hash);
    await expectLater(first, throwsA(same(error)));
    await receiveTurnsUntil(() => !fixture.worker.running);
    expect(fixture.worker.originals, isEmpty);
    expect(fixture.worker.inFlight.value, isEmpty);
    fixture.readInbound = null;
    final Future<AccountBlockTemplate?> next = fixture.worker
        .autoReceiveTransactionHash(hash);
    expect(next, isNot(same(first)));
    expect(await next, isNotNull);
    expect(fixture.proofReads, 2);
    expect(fixture.transport.calls, hasLength(1));
  });

  test(
    'another selected member cannot consume the first owner projection',
    () async {
      fixture.addresses.add(tokenAddress.toString());
      final Future<AccountBlockTemplate?> first = fixture.worker
          .autoReceiveTransactionHash(hash);
      await first;
      await receiveTurnsUntil(() => !fixture.worker.running);
      fixture.selectedAddress = tokenAddress.toString();
      final Future<AccountBlockTemplate?> second = fixture.worker
          .autoReceiveTransactionHash(hash);
      expect(second, isNot(same(first)));
      await expectLater(second, throwsA(isA<ReceiveRefused>()));
      await receiveTurnsUntil(() => !fixture.worker.running);
      expect(fixture.worker.originals, hasLength(1));
      expect(fixture.transport.calls, hasLength(1));
      expect(
        fixture.worker.originals.single.toAddress,
        emptyAddress.toString(),
      );
      expect(fixture.worker.originals.single.chainId, receiveChain);
      expect(fixture.worker.originals.single.inboundHash, hash.toString());
    },
  );

  test(
    'sender leases revoke old origins and old detach preserves replacement',
    () async {
      final Object first = fixture.lease;
      final ReceiveOrigin old = fixture.capture();
      final SendTransactionBloc replacement = fixture.newSender();
      final Object next = fixture.worker.attachSender(replacement);
      fixture.worker.detachSender(first);
      expect(fixture.worker.ownsSender(next), isTrue);
      expect(fixture.worker.ownsSender(first), isFalse);
      expect(old.isCurrent, isFalse);
      await expectLater(
        fixture.worker.autoReceiveTransactionHash(hash, origin: old),
        throwsA(isA<ReceiveRefused>()),
      );
      expect(fixture.proofReads, 0);
      expect(fixture.transport.calls, isEmpty);
      fixture.worker.detachSender(next);
      expect(fixture.worker.captureOrigin(), isNull);
    },
  );

  final Map<String, AccountBlock? Function(Hash)> invalidProofs =
      <String, AccountBlock? Function(Hash)>{
        'missing block': (_) => null,
        'different inbound hash': (_) => receiveInbound(receiveHash(9)),
        'different chain': (Hash hash) => receiveInbound(hash, chainId: 1),
        'receive instead of send': (Hash hash) => receiveInbound(
          hash,
          type: BlockTypeEnum.userReceive.index,
        ),
        'nonmember destination': (Hash hash) => receiveInbound(
          hash,
          destination: tokenAddress,
        ),
      };
  for (final MapEntry<String, AccountBlock? Function(Hash)> invalid
      in invalidProofs.entries) {
    test('fresh proof refuses ${invalid.key} before admission', () async {
      fixture.readInbound = (Hash hash) async => invalid.value(hash);
      await expectLater(
        fixture.worker.autoReceiveTransactionHash(hash),
        throwsA(isA<ReceiveRefused>()),
      );
      await receiveTurnsUntil(() => !fixture.worker.running);
      expect(fixture.worker.originals, isEmpty);
      expect(fixture.worker.inFlight.value, isEmpty);
      expect(fixture.transport.calls, isEmpty);
      expect(fixture.sender.busy.value, isFalse);
    });
  }

  test('automatic proof must equal the enqueued member destination', () async {
    fixture.addresses.add(tokenAddress.toString());
    fixture.readInbound = (Hash hash) async => receiveInbound(
      hash,
      destination: tokenAddress,
    );
    await fixture.enqueue(hash);
    await fixture.worker.autoReceive();
    expect(fixture.proofReads, 1);
    expect(fixture.transport.calls, isEmpty);
    expect(fixture.worker.originals, isEmpty);
    expect(fixture.worker.hasPending, isFalse);
  });

  test('revision changes refuse a deferred inbound proof', () async {
    final Completer<AccountBlock?> proof = Completer<AccountBlock?>();
    fixture.readInbound = (_) => proof.future;
    final Future<void> refused = expectLater(
      fixture.worker.autoReceiveTransactionHash(hash),
      throwsA(isA<ReceiveRefused>()),
    );
    fixture.revision++;
    proof.complete(receiveInbound(hash));
    await refused;
    await receiveTurnsUntil(() => !fixture.worker.running);
    expect(fixture.transport.calls, isEmpty);
    expect(fixture.worker.inFlight.value, isEmpty);
    expect(fixture.sender.busy.value, isFalse);
  });

  test('synchronous busy observers revoke before the fresh proof', () async {
    void revoke() {
      if (fixture.sender.busy.value) fixture.revision++;
    }

    fixture.sender.busy.addListener(revoke);
    try {
      await expectLater(
        fixture.worker.autoReceiveTransactionHash(hash),
        throwsA(isA<ReceiveRefused>()),
      );
      await receiveTurnsUntil(() => !fixture.worker.running);
      expect(fixture.proofReads, 0);
      expect(fixture.transport.calls, isEmpty);
      expect(fixture.sender.busy.value, isFalse);
    } finally {
      fixture.sender.busy.removeListener(revoke);
    }
  });

  test('synchronous loading observer is rechecked before transport', () async {
    final BlocObserver previous = Bloc.observer;
    final _LoadingObserver observer = _LoadingObserver(() {
      fixture.revision++;
    });
    Bloc.observer = observer;
    final SendTransactionBloc sender = fixture.newSender();
    observer.sender = sender;
    fixture.worker.attachSender(sender);
    try {
      final Future<AccountBlockTemplate?> request = fixture.worker
          .autoReceiveTransactionHash(hash);
      Object? originalError;
      await request.then<void>(
        (_) => fail('Expected refusal'),
        onError: (Object error, StackTrace _) {
          originalError = error;
        },
      );
      await receiveTurnsUntil(() => !fixture.worker.running);
      final ReceiveRecord record = fixture.worker.originals.single;
      expect(record.result!.error, same(originalError));
      expect(fixture.transport.calls, isEmpty);
      expect(fixture.worker.autoReceiveTransactionHash(hash), same(request));
      expect(sender.busy.value, isFalse);
    } finally {
      Bloc.observer = previous;
    }
  });

  test(
    'preparation retains its original authority and exact unknown error',
    () async {
      fixture.transport.preparation = Completer<void>();
      final Future<AccountBlockTemplate?> request = fixture.worker
          .autoReceiveTransactionHash(hash);
      Object? originalError;
      final Future<void> settled = request.then<void>(
        (_) => fail('Expected revoked preparation'),
        onError: (Object error, StackTrace _) {
          originalError = error;
        },
      );
      await receiveTurnsUntil(() => fixture.transport.calls.length == 1);
      fixture.revision++;
      fixture.transport.preparation!.complete();
      await settled;
      await receiveTurnsUntil(() => !fixture.worker.running);
      final ReceiveRecord record = fixture.worker.originals.single;
      expect(record.result!.error, same(originalError));
      expect(fixture.transport.dispatched, 0);
      expect(fixture.worker.autoReceiveTransactionHash(hash), same(request));
      expect(fixture.worker.inFlight.value, <Hash>{hash});
    },
  );

  for (final bool fails in <bool>[false, true]) {
    test(
      'late ${fails ? 'unknown' : 'accepted'} original survives new sender',
      () async {
        fixture.transport.deferred = true;
        final Future<AccountBlockTemplate?> request = fixture.worker
            .autoReceiveTransactionHash(hash);
        AccountBlockTemplate? received;
        Object? receivedError;
        final Future<void> settled = request.then<void>(
          (AccountBlockTemplate? block) {
            received = block;
          },
          onError: (Object error, StackTrace _) {
            receivedError = error;
          },
        );
        await receiveTurnsUntil(() => fixture.transport.pending.length == 1);
        final ReceiveRecord record = fixture.worker.originals.single;
        final SendRequestHandle handle = record.handle!;
        fixture.worker.detachSender(fixture.lease);
        fixture.lease = fixture.worker.attachSender(fixture.newSender());
        final ReceiveOrigin replacement = fixture.capture();
        fixture.worker.clearAutomatic();
        expect(
          fixture.worker.autoReceiveTransactionHash(hash, origin: replacement),
          same(request),
        );
        final StateError error = StateError('Synthetic original uncertainty');
        final AccountBlockTemplate original = fixture.transport.complete(
          error: fails ? error : null,
        );
        await settled;
        await receiveTurnsUntil(() => !fixture.worker.running);
        expect(record, same(fixture.worker.originals.single));
        expect(record.handle, same(handle));
        expect(record.result, same(await handle.result));
        expect(received, fails ? isNull : same(original));
        expect(receivedError, fails ? same(error) : isNull);
        expect(record.result!.error, fails ? same(error) : isNull);
        expect(record.result!.block, fails ? isNull : same(original));
        expect(fixture.successes, isEmpty);
        expect(fixture.failures, isEmpty);
        expect(fixture.worker.inFlight.value, <Hash>{hash});
        await fixture.enqueue(hash, origin: replacement);
        await fixture.worker.autoReceive();
        expect(fixture.worker.autoReceiveTransactionHash(hash), same(request));
        expect(fixture.transport.calls, hasLength(1));
        expect(fixture.worker.originals, hasLength(1));
      },
    );

    test('disposed worker retains its late '
        '${fails ? 'unknown' : 'accepted'} original', () async {
      fixture.transport.deferred = true;
      final Future<AccountBlockTemplate?> request = fixture.worker
          .autoReceiveTransactionHash(hash);
      Object? receivedError;
      AccountBlockTemplate? received;
      final Future<void> settled = request.then<void>(
        (AccountBlockTemplate? block) {
          received = block;
        },
        onError: (Object error, StackTrace _) {
          receivedError = error;
        },
      );
      await receiveTurnsUntil(() => fixture.transport.pending.length == 1);
      final ReceiveRecord record = fixture.worker.originals.single;
      final SendRequestHandle handle = record.handle!;
      fixture.worker.dispose();
      final StateError error = StateError('Synthetic original disposal');
      final AccountBlockTemplate original = fixture.transport.complete(
        error: fails ? error : null,
      );
      await settled;
      await receiveTurnsUntil(() => !fixture.worker.running);
      expect(record.handle, same(handle));
      expect(record.result, same(await handle.result));
      expect(record.future, same(request));
      expect(record.chainId, receiveChain);
      expect(record.toAddress, emptyAddress.toString());
      expect(record.inboundHash, hash.toString());
      expect(received, fails ? isNull : same(original));
      expect(receivedError, fails ? same(error) : isNull);
      expect(fixture.successes, isEmpty);
      expect(fixture.failures, isEmpty);
      expect(fixture.transport.calls, hasLength(1));
    });
  }

  final Map<String, void Function(AccountBlockTemplate)> invalidResponses =
      <String, void Function(AccountBlockTemplate)>{
        'empty publication hash': (AccountBlockTemplate block) =>
            block.hash = emptyHash,
        'wrong owner': (AccountBlockTemplate block) =>
            block.address = tokenAddress,
        'wrong chain': (AccountBlockTemplate block) =>
            block.chainIdentifier = 1,
        'wrong inbound': (AccountBlockTemplate block) =>
            block.fromBlockHash = receiveHash(7),
        'wrong type': (AccountBlockTemplate block) =>
            block.blockType = BlockTypeEnum.userSend.index,
      };
  for (final MapEntry<String, void Function(AccountBlockTemplate)> invalid
      in invalidResponses.entries) {
    test('${invalid.key} retains the identical result as unknown', () async {
      late AccountBlockTemplate original;
      fixture.transport.reply = (ReceiveCall call) {
        original = fixture.transport.accepted(call);
        invalid.value(original);
        return original;
      };
      final Future<AccountBlockTemplate?> request = fixture.worker
          .autoReceiveTransactionHash(hash);
      ReceiveUnknownResult? unknown;
      await request.then<void>(
        (_) => fail('Expected unknown response'),
        onError: (Object error, StackTrace _) {
          unknown = error as ReceiveUnknownResult;
        },
      );
      await receiveTurnsUntil(() => !fixture.worker.running);
      final ReceiveRecord record = fixture.worker.originals.single;
      expect(record.result, same(unknown!.result));
      expect(record.result!.block, same(original));
      expect(record.error, same(unknown));
      expect(fixture.worker.autoReceiveTransactionHash(hash), same(request));
      expect(fixture.transport.calls, hasLength(1));
      expect(fixture.worker.inFlight.value, <Hash>{hash});
    });
  }

  test(
    'clear epoch fences old sync while exact replacement addition survives',
    () async {
      final ReceiveOrigin origin = fixture.capture();
      final Completer<SyncInfo> oldSync = Completer<SyncInfo>();
      fixture.readSync = () => oldSync.future;
      final Future<void> old = fixture.enqueue(hash, origin: origin);
      fixture.worker.clearAutomatic();
      final Completer<SyncInfo> nextSync = Completer<SyncInfo>();
      fixture.readSync = () => nextSync.future;
      final Future<void> next = fixture.enqueue(hash, origin: origin);
      oldSync.complete(receiveSync());
      await old;
      expect(fixture.worker.hasPending, isTrue);
      expect(fixture.queued, 0);
      nextSync.complete(receiveSync());
      await next;
      expect(fixture.queued, 1);
      await fixture.worker.autoReceive();
      expect(fixture.transport.calls, hasLength(1));
      expect(fixture.worker.hasPending, isFalse);
    },
  );

  test('old active proof cannot remove a replacement queue entry', () async {
    final Completer<AccountBlock?> proof = Completer<AccountBlock?>();
    fixture.readInbound = (_) => proof.future;
    await fixture.enqueue(hash);
    final Future<void> drain = fixture.worker.autoReceive();
    expect(fixture.proofReads, 1);
    fixture.worker.clearAutomatic();
    fixture.readInbound = (Hash hash) async => receiveInbound(hash);
    await fixture.enqueue(hash);
    proof.complete(receiveInbound(hash));
    await drain;
    expect(fixture.proofReads, 2);
    expect(fixture.worker.originals.single.inboundHash, hash.toString());
    expect(fixture.transport.calls, hasLength(1));
    expect(fixture.worker.hasPending, isFalse);
  });

  test('busy shared sender defers automatic work before proof', () async {
    final Object owner = Object();
    expect(fixture.sender.tryReserve(owner), isTrue);
    await fixture.enqueue(hash);
    await fixture.worker.autoReceive();
    expect(fixture.worker.hasPending, isTrue);
    expect(fixture.proofReads, 0);
    fixture.sender.releaseReservation(owner);
    await fixture.worker.autoReceive();
    expect(fixture.worker.hasPending, isFalse);
    expect(fixture.transport.calls, hasLength(1));
  });

  test(
    'explicit manual work ignores a disabled queued automatic preference',
    () async {
      fixture.priorityBusy = true;
      await fixture.enqueue(hash);
      await fixture.worker.autoReceive();
      fixture.automatic = false;
      final int reads = fixture.preferenceReads;
      final AccountBlockTemplate? result = await fixture.worker
          .autoReceiveTransactionHash(hash);
      expect(result, isNotNull);
      expect(fixture.preferenceReads, reads);
      expect(fixture.transport.calls, hasLength(1));
      await fixture.worker.autoReceive();
      expect(fixture.worker.hasPending, isFalse);
    },
  );

  test('success observers cannot replace an accepted original', () async {
    fixture.onSuccess = () => throw StateError('Synthetic display failure');
    final AccountBlockTemplate? block = await fixture.worker
        .autoReceiveTransactionHash(hash);
    await receiveTurnsUntil(() => !fixture.worker.running);
    expect(fixture.worker.originals.single.result!.block, same(block));
    expect(fixture.worker.originals.single.error, isNull);
    expect(fixture.transport.calls, hasLength(1));
  });
}
