import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

AccountBlock _creationEffect(
  HtlcSwap swap, {
  required bool initial,
  int height = 1,
  String? previous,
  List<AccountBlock> outputs = const <AccountBlock>[],
}) {
  final AccountBlock paired = htlcCreate(swap, initial: initial);
  final AccountBlockTemplate receive =
      AccountBlockTemplate(blockType: BlockTypeEnum.contractReceive.index)
        ..address = htlcAddress
        ..fromBlockHash = paired.hash;
  return htlcBlock(
    template: receive,
    paired: paired,
    height: height,
    previous: previous,
    descendants: outputs,
  );
}

void _historicalReads(HtlcFixture fixture) {
  fixture.blockRead = (String id) async {
    for (final AccountBlock block in fixture.blocks) {
      if (block.hash.toString() == id) return block;
    }
    if (id == fixture.record.initialHtlcId) {
      return htlcCreate(fixture.record, initial: true);
    }
    if (id == fixture.record.counterHtlcId) {
      return htlcCreate(fixture.record, initial: false);
    }
    return null;
  };
}

HtlcSwapsHandler _handler(HtlcFixture fixture, {AutoUnlockHtlcWorker? worker}) {
  final HtlcSwapsHandler handler = HtlcSwapsHandler(
    captureOrigin: fixture.capture,
    unlockWorker: worker,
  );
  addTearDown(() async {
    await handler.pauseAndDrain();
  });
  return handler;
}

AutoUnlockHtlcWorker _worker(HtlcFixture fixture) {
  final AutoUnlockHtlcWorker worker = AutoUnlockHtlcWorker(
    captureOrigin: fixture.capture,
  );
  addTearDown(() async {
    await worker.pauseAndDrain();
    worker.dispose();
  });
  return worker;
}

void _incomingCounterWithdrawal(HtlcFixture fixture) {
  final HtlcSwap hidden = HtlcSwap.fromJson(fixture.record.toJson())
    ..preimage = null;
  fixture.seedRecord(hidden);
  final AccountBlock creation = _creationEffect(fixture.record, initial: false);
  fixture.blocks.addAll(<AccountBlock>[
    creation,
    htlcTerminal(
      fixture.record,
      unlock: true,
      initial: false,
      height: 2,
      previous: creation.hash.toString(),
    ),
  ]);
  _historicalReads(fixture);
  fixture.liveRead = (String id) async {
    if (id != fixture.record.initialHtlcId) {
      throw StateError('Synthetic consumed counterdeposit');
    }
    return htlcLive(fixture.record, initial: true);
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'confirmed Create effects replay through consumed deposits '
    'and discover their exact counterdeposit',
    () async {
      final HtlcFixture fixture = HtlcFixture(421)
        ..record = htlcRecord(421, direction: P2pSwapDirection.outgoing);
      final HtlcSwap pending = HtlcSwap.fromJson(fixture.record.toJson())
        ..state = P2pSwapState.pending
        ..counterHtlcId = null
        ..counterHtlcExpirationTime = null
        ..toAmount = null
        ..toTokenStandard = null
        ..toDecimals = null
        ..toSymbol = null;
      fixture.seedRecord(pending);
      final AccountBlock initial = _creationEffect(
        fixture.record,
        initial: true,
      );
      final AccountBlock counter = _creationEffect(
        fixture.record,
        initial: false,
        height: 2,
        previous: initial.hash.toString(),
      );
      fixture.blocks.addAll(<AccountBlock>[
        initial,
        counter,
        htlcTerminal(
          fixture.record,
          unlock: true,
          initial: false,
          height: 3,
          previous: counter.hash.toString(),
        ),
      ]);
      fixture.liveRead = (_) => Future<HtlcInfo>.error(
        StateError('Synthetic already consumed deposit'),
      );
      final HtlcSwapsHandler handler = _handler(fixture);
      await handler.runOnce();
      final HtlcSwap stored = fixture.store.getSwapById(pending.id)!;
      expect(stored.state, P2pSwapState.completed);
      expect(stored.counterHtlcId, fixture.record.counterHtlcId);
      expect(stored.toAmount, fixture.record.toAmount);
      expect(stored.toTokenStandard, fixture.record.toTokenStandard);
      expect(fixture.liveReads, isEmpty);
      expect(fixture.store.readCursor().height, 3);
      expect(
        fixture.store.readCursor().hash,
        fixture.blocks.last.hash.toString(),
      );
    },
  );

  for (final bool allow in <bool>[false, true]) {
    test(
      'a confirmed ${allow ? 'AllowProxyUnlock' : 'DenyProxyUnlock'} call '
      'does not block later own withdrawal history',
      () async {
        final HtlcFixture fixture = HtlcFixture(422 + (allow ? 1 : 0));
        fixture.record = htlcRecord(
          fixture.number,
          direction: P2pSwapDirection.outgoing,
        );
        fixture.seedRecord(fixture.record);
        final AccountBlockTemplate call =
            (allow ? HtlcApi().allowProxyUnlock() : HtlcApi().denyProxyUnlock())
              ..address = Address.parse(htlcOwner(9));
        final AccountBlock paired = htlcBlock(
          template: call,
          hash: htlcHash(60000),
        );
        final AccountBlock policy = htlcBlock(
          template:
              AccountBlockTemplate(
                  blockType: BlockTypeEnum.contractReceive.index,
                )
                ..address = htlcAddress
                ..fromBlockHash = paired.hash,
          paired: paired,
        );
        fixture.blocks.addAll(<AccountBlock>[
          policy,
          htlcTerminal(
            fixture.record,
            unlock: true,
            initial: false,
            height: 2,
            previous: policy.hash.toString(),
          ),
        ]);
        final HtlcSwapsHandler handler = _handler(fixture);
        await handler.runOnce();
        expect(fixture.store.readCursor().height, 2);
        expect(
          fixture.store.getSwapById(fixture.record.id)!.state,
          P2pSwapState.completed,
        );
        expect(fixture.liveReads, isEmpty);
      },
    );
  }

  test(
    'an exact incoming counter withdrawal permits the initial claim '
    'and survives a fresh handler',
    () async {
      final HtlcFixture fixture = HtlcFixture(424);
      _incomingCounterWithdrawal(fixture);
      final AutoUnlockHtlcWorker worker = _worker(fixture);
      final HtlcSwapsHandler handler = _handler(fixture, worker: worker);
      await handler.runOnce();
      expect(
        fixture.store.getSwapById(fixture.record.id)!.preimage,
        fixture.record.preimage,
      );
      expect(
        fixture.store.getSwapById(fixture.record.id)!.state,
        P2pSwapState.active,
      );
      expect(fixture.signers, <String>[fixture.record.selfAddress]);
      expect(fixture.liveReads, <String>[fixture.record.initialHtlcId]);
      expect(
        fixture.store
            .readObservedWithdrawal(
              fixture.record.counterHtlcId!,
              fixture.record.selfAddress,
            )!
            .hash,
        fixture.blocks.last.hash.toString(),
      );
      expect(fixture.store.readAll(), hasLength(1));
      expect((await handler.pauseAndDrain()).completed, isTrue);
      expect((await worker.pauseAndDrain()).completed, isTrue);

      final HtlcSwapsHandler fresh = _handler(
        fixture,
        worker: _worker(fixture),
      );
      await fresh.runOnce();
      expect(fixture.signers, <String>[fixture.record.selfAddress]);
      expect(fixture.liveReads, <String>[fixture.record.initialHtlcId]);
      expect(
        fixture.blockReads.where(
          (String id) => id == fixture.blocks.last.hash.toString(),
        ),
        hasLength(2),
      );
      expect((await fresh.pauseAndDrain()).completed, isTrue);
    },
  );

  for (final String failure in <String>['missing', 'mismatched', 'rpc']) {
    test(
      'a $failure observed event cannot replace exact withdrawal proof '
      'on a later cycle',
      () async {
        final HtlcFixture fixture = HtlcFixture(
          425 + <String>['missing', 'mismatched', 'rpc'].indexOf(failure),
        );
        _incomingCounterWithdrawal(fixture);
        final HtlcSwapsHandler handler = _handler(
          fixture,
          worker: _worker(fixture),
        );
        await handler.runOnce();
        final Object originalError = StateError(
          'Synthetic history uncertainty',
        );
        final Future<AccountBlock?> Function(String) originalRead =
            fixture.blockRead!;
        fixture.blockRead = (String id) {
          if (id != fixture.blocks.last.hash.toString()) {
            return originalRead(id);
          }
          if (failure == 'rpc') {
            return Future<AccountBlock?>.error(originalError);
          }
          return Future<AccountBlock?>.value(
            failure == 'missing' ? null : fixture.blocks.first,
          );
        };
        await expectLater(
          handler.runOnce(),
          failure == 'rpc'
              ? throwsA(same(originalError))
              : throwsA(isA<HtlcOwnershipRefused>()),
        );
        expect(fixture.signers, <String>[fixture.record.selfAddress]);
        expect(fixture.liveReads, <String>[fixture.record.initialHtlcId]);
        expect(
          fixture.store.getSwapById(fixture.record.id)!.state,
          P2pSwapState.active,
        );
        expect(fixture.store.readCursor().height, 2);
      },
    );
  }

  test(
    'an uncertain withdrawal-reference write preserves its original failure '
    'and does not advance that cursor or claim',
    () async {
      final HtlcFixture fixture = HtlcFixture(428);
      _incomingCounterWithdrawal(fixture);
      fixture.swaps.deferred.add('put');
      final HtlcSwapsHandler handler = _handler(
        fixture,
        worker: _worker(fixture),
      );
      final HtlcOutcome<void> cycle = HtlcOutcome<void>(handler.runOnce());
      await htlcMicrotasks();
      expect(fixture.swaps.calls, hasLength(1));
      final Object failure = StateError('Synthetic withdrawal reference write');
      fixture.swaps.calls.single.fail(failure);
      await expectLater(cycle.future, throwsA(same(failure)));
      expect(
        fixture.store.operations
            .where(
              (HtlcOperationReceipt value) =>
                  value.name == 'put-observed-withdrawal',
            )
            .single
            .error,
        same(failure),
      );
      expect(fixture.signers, isEmpty);
      expect(fixture.liveReads, isEmpty);
      expect(
        (fixture.cursor.entries.values.single
            as Map<String, dynamic>)['height'],
        1,
      );
      expect((await handler.pauseAndDrain()).completed, isFalse);
    },
  );

  test('a refunded Create effect never activates its pending record', () async {
    final HtlcFixture fixture = HtlcFixture(429);
    fixture
      ..record = htlcRecord(
        429,
        direction: P2pSwapDirection.outgoing,
        state: P2pSwapState.pending,
      )
      ..seedRecord(fixture.record)
      ..blocks.add(
        _creationEffect(
          fixture.record,
          initial: true,
          outputs: <AccountBlock>[htlcBlock()],
        ),
      );
    final HtlcSwapsHandler handler = _handler(fixture);
    await expectLater(handler.runOnce(), throwsA(isA<HtlcOwnershipRefused>()));
    expect(
      fixture.store.getSwapById(fixture.record.id)!.state,
      P2pSwapState.pending,
    );
    expect(fixture.store.readCursor().height, 0);
    expect(fixture.signers, isEmpty);
  });
}
