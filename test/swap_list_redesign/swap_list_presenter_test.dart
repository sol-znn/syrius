import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';

import 'support.dart';

void main() {
  test('a returning catalogue proof retains nested revocation', () {
    final Object identity = Object();
    bool ready = true;
    bool reenter = false;
    final List<bool> nested = <bool>[];
    late final SwapListResources source;
    source = SwapListResources(
      identities: () => <Object>[identity],
      values: () => <int>[1],
      ready: () {
        final bool accepted = ready;
        if (reenter) {
          reenter = false;
          ready = false;
          nested.add(source.isCurrent);
          ready = true;
        }
        return accepted;
      },
    );
    expect(source.isCurrent, isTrue);
    reenter = true;
    expect(source.isCurrent, isFalse);
    expect(nested, <bool>[false]);
    expect(ready, isTrue);
    expect(source.isCurrent, isFalse);
  });

  test(
    'all pages close one exact catalogue before counts or rows publish',
    () async {
      final SwapListFixture source = SwapListFixture();
      for (int number = 1; number <= 65; number++) {
        source.add(
          swapRecord(
            number,
            state: number < 30
                ? P2pSwapState.active
                : number < 60
                ? P2pSwapState.completed
                : P2pSwapState.reclaimable,
          ),
          prove: false,
        );
      }
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      await presenter.load();
      expect(source.pages, <int>[0, 1, 2]);
      expect(presenter.snapshot!.rows.length, 65);
      expect(presenter.snapshot!.active, 29);
      expect(presenter.snapshot!.completed, 30);
      expect(presenter.snapshot!.reclaimable, 6);
      expect(presenter.snapshot!.rows.first.record.id, swapHash(65));
      presenter.dispose();
    },
  );

  for (final String failure in <String>[
    'total',
    'short',
    'duplicate',
    'early',
    'large',
    'negative',
  ]) {
    test(
      'incomplete $failure source refuses instead of publishing a partial list',
      () async {
        final SwapListFixture source = SwapListFixture();
        final List<SwapListRecord> rows = List<SwapListRecord>.generate(
          33,
          (int i) => swapRecord(i + 1),
        );
        source.pageRead = (int page, int size) async => switch (failure) {
          'large' => SwapListPage(
            total: 1001,
            more: true,
            records: rows.take(32),
          ),
          'negative' => SwapListPage(
            total: -1,
            more: false,
            records: const <SwapListRecord>[],
          ),
          'short' => SwapListPage(
            total: 33,
            more: true,
            records: rows.take(31),
          ),
          'early' => SwapListPage(
            total: 33,
            more: false,
            records: rows.take(32),
          ),
          'duplicate' => SwapListPage(
            total: 33,
            more: page == 0,
            records: page == 0 ? rows.take(32) : <SwapListRecord>[rows.first],
          ),
          _ => SwapListPage(
            total: page == 0 ? 33 : 34,
            more: page == 0,
            records: page == 0 ? rows.take(32) : <SwapListRecord>[rows.last],
          ),
        };
        final SwapListPresenter presenter = SwapListPresenter(source.bind());
        await presenter.load();
        expect(presenter.snapshot, isNull);
        expect(presenter.error, isA<SwapListRefused>());
        expect(source.deposits, isEmpty);
        presenter.dispose();
      },
    );
  }

  test('an explicit complete empty source proves zero counts', () async {
    final SwapListPresenter presenter = SwapListPresenter(
      SwapListFixture().bind(),
    );
    await presenter.load();
    expect(presenter.snapshot!.rows, isEmpty);
    expect(presenter.snapshot!.active, 0);
    expect(presenter.error, isNull);
    presenter.dispose();
  });

  test(
    'a pending original read retains its exact success after owner ABA',
    () async {
      final SwapListFixture source = SwapListFixture();
      final Completer<SwapListPage> reply = Completer<SwapListPage>();
      source.pageRead = (_, _) => reply.future;
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      final Future<void> loading = presenter.load();
      source.path = 'away';
      source.revision++;
      source.path = 'fixture-wallet';
      final SwapListPage original = SwapListPage(
        total: 0,
        more: false,
        records: const <SwapListRecord>[],
      );
      reply.complete(original);
      await loading;
      expect(presenter.snapshot, isNull);
      expect(presenter.reads.single.operation, same(reply.future));
      expect(presenter.reads.single.result, same(original));
      expect(presenter.error, isA<SwapListRefused>());
      presenter.dispose();
    },
  );

  test(
    'disposal retains the original error and starts no later reads',
    () async {
      final SwapListFixture source = SwapListFixture();
      final Completer<SwapListPage> reply = Completer<SwapListPage>();
      final Object error = Object();
      source.pageRead = (_, _) => reply.future;
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      int deliveries = 0;
      presenter.addListener(() => deliveries++);
      final Future<void> loading = presenter.load();
      final int before = deliveries;
      presenter.dispose();
      reply.completeError(error, StackTrace.current);
      await loading;
      expect(deliveries, before);
      expect(presenter.reads.single.operation, same(reply.future));
      expect(presenter.reads.single.error, same(error));
      expect(presenter.error, same(error));
      expect(source.deposits, isEmpty);
    },
  );

  test(
    'hydrated receiving fields cannot manufacture a receiving amount or rate',
    () async {
      final SwapListFixture source = SwapListFixture()
        ..add(swapRecord(1), prove: false);
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      await presenter.load();
      final SwapListRow row = presenter.snapshot!.rows.single;
      expect(row.receiving, isNull);
      expect(row.rate, isNull);
      expect(row.currentExpiration, isNull);
      presenter.dispose();
    },
  );

  test(
    'an unavailable live read retains its exact error '
    'and leaves expiry unknown',
    () async {
      final SwapListRecord record = swapRecord(1);
      final SwapListFixture source = SwapListFixture()..add(record);
      final Object originalError = Object();
      late Future<SwapLiveDeposit?> original;
      source.liveRead = (_) =>
          original = Future<SwapLiveDeposit?>.error(originalError);
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      await presenter.load();
      expect(presenter.snapshot!.rows.single.currentExpiration, isNull);
      final SwapListOutcome retained = presenter.reads.last;
      expect(retained.operation, same(original));
      expect(retained.error, same(originalError));
      expect(presenter.snapshot!.rows.single.record.state, P2pSwapState.active);
      presenter.dispose();
    },
  );

  test(
    'successful pending reads cannot initiate more I/O after disposal',
    () async {
      final SwapListFixture source = SwapListFixture();
      final Completer<SwapListPage> reply = Completer<SwapListPage>();
      source.pageRead = (_, _) => reply.future;
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      final Future<void> reading = presenter.load();
      presenter.dispose();
      final SwapListPage result = SwapListPage(
        total: 0,
        more: false,
        records: const <SwapListRecord>[],
      );
      reply.complete(result);
      await reading;
      expect(presenter.reads.single.result, same(result));
      expect(presenter.snapshot, isNull);
      expect(presenter.reads.length, 1);
    },
  );

  test(
    'only positive matching live proof establishes current expiry',
    () async {
      final SwapListRecord record = swapRecord(1);
      final SwapListFixture source = SwapListFixture()..add(record);
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      await presenter.load();
      expect(
        presenter.snapshot!.rows.single.currentExpiration,
        record.initialExpiration,
      );
      expect(presenter.snapshot!.rows.single.rate, '1 ZNN = 10 QSR');
      presenter.dispose();
    },
  );

  test(
    'a missing live HTLC does not manufacture completed or reclaim authority',
    () async {
      final SwapListRecord record = swapRecord(1);
      final SwapListFixture source = SwapListFixture()
        ..add(record, current: false);
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      await presenter.load();
      expect(presenter.snapshot!.rows.single.record.state, P2pSwapState.active);
      expect(presenter.snapshot!.rows.single.currentExpiration, isNull);
      expect(await presenter.delete(<SwapListRecord>[record]), isNull);
      presenter.dispose();
    },
  );

  for (final String mismatch in <String>['sender', 'recipient', 'chain']) {
    test(
      'a $mismatch mismatch leaves receiving amount and rate unknown',
      () async {
        final SwapListRecord record = swapRecord(1);
        final SwapListFixture source = SwapListFixture()..add(record);
        source.proofs[record.receiveDepositId!] = swapProof(
          record,
          sending: false,
          sender: mismatch == 'sender' ? swapAddress(3) : null,
          recipient: mismatch == 'recipient' ? swapAddress(3) : null,
          chain: mismatch == 'chain' ? 1 : null,
        );
        final SwapListPresenter presenter = SwapListPresenter(source.bind());
        await presenter.load();
        expect(presenter.snapshot!.rows.single.receiving, isNull);
        expect(presenter.snapshot!.rows.single.rate, isNull);
        presenter.dispose();
      },
    );
  }

  test(
    'nonterminating rates stay unknown without rounding financial terms',
    () {
      final SwapListRecord record = swapRecord(1, amount: BigInt.from(3));
      final SwapListRow row = SwapListRow(
        record: record,
        sending: swapProof(record, sending: true),
        receiving: swapProof(record, sending: false, amount: BigInt.one),
      );
      expect(row.rate, isNull);
    },
  );

  for (final P2pSwapDirection direction in P2pSwapDirection.values) {
    test(
      'exact initial and counter deposits remain distinct for $direction',
      () {
        final SwapListRecord record = swapRecord(1, direction: direction);
        expect(
          record.ownDepositId,
          direction == P2pSwapDirection.outgoing
              ? record.initialDepositId
              : record.counterpartyDepositId,
        );
        expect(
          record.receiveDepositId,
          direction == P2pSwapDirection.outgoing
              ? record.counterpartyDepositId
              : record.initialDepositId,
        );
        expect(record.ownDepositId, isNot(record.id));
      },
    );
  }

  test(
    'the original Box lane and exact write completion '
    'survive disposal and replacement',
    () async {
      final SwapListRecord record = swapRecord(
        1,
        state: P2pSwapState.completed,
      );
      final SwapListFixture source = SwapListFixture()
        ..add(record, prove: false);
      final Completer<Object?> reply = Completer<Object?>();
      source.deleteWrite = (_) => reply.future;
      final SwapListPresenter first = SwapListPresenter(source.bind());
      final Future<SwapListOutcome?> deleting = first.delete(<SwapListRecord>[
        record,
      ]);
      final SwapListPresenter second = SwapListPresenter(source.bind());
      expect(await second.delete(<SwapListRecord>[record]), isNull);
      first.dispose();
      source.wallet = Object();
      final Object result = Object();
      reply.complete(result);
      final SwapListOutcome outcome = (await deleting)!;
      expect(outcome.operation, same(reply.future));
      expect(outcome.result, same(result));
      expect(outcome.completed, isTrue);
      expect(second.writes.single, same(outcome));
      expect(source.deletes.single, <String>[record.id]);
      second.dispose();
    },
  );

  test(
    'an original failed delete retains the same error and never retries',
    () async {
      final SwapListRecord record = swapRecord(
        1,
        state: P2pSwapState.completed,
      );
      final SwapListFixture source = SwapListFixture()
        ..add(record, prove: false);
      final Completer<void> reply = Completer<void>();
      final Object error = Object();
      source.deleteWrite = (_) => reply.future;
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      final Future<SwapListOutcome?> deleting = presenter.delete(
        <SwapListRecord>[record],
      );
      presenter.dispose();
      reply.completeError(error, StackTrace.current);
      final SwapListOutcome outcome = (await deleting)!;
      expect(outcome.operation, same(reply.future));
      expect(outcome.error, same(error));
      expect(source.deletes.length, 1);
    },
  );

  test(
    'replaced exact records refuse history deletion before admission',
    () async {
      final SwapListRecord record = swapRecord(
        1,
        state: P2pSwapState.completed,
      );
      final SwapListFixture source = SwapListFixture()
        ..add(record, prove: false);
      final SwapListPresenter presenter = SwapListPresenter(source.bind());
      source.replacedRows.add(record.id);
      expect(await presenter.delete(<SwapListRecord>[record]), isNull);
      expect(source.deletes, isEmpty);
      presenter.dispose();
    },
  );

  for (final int position in <int>[0, 1, 2, 3]) {
    test(
      'original resource identity $position cannot revive after observed ABA',
      () {
        final Object original = Object();
        final List<Object?> identities = <Object?>[
          Object(),
          Object(),
          Object(),
          Object(),
        ];
        identities[position] = original;
        final SwapListResources receipt = SwapListResources(
          identities: () => identities,
          values: () => <Object?>[0, 'fixture-path', 'fixture-url'],
          ready: () => true,
        );
        identities[position] = Object();
        expect(receipt.isCurrent, isFalse);
        identities[position] = original;
        expect(receipt.isCurrent, isFalse);
      },
    );
  }

  for (final int position in <int>[0, 1, 2, 3, 4]) {
    test(
      'path, membership, selection, revision and URL scalar $position '
      'departures revoke',
      () {
        final List<Object?> values = <Object?>[
          'fixture-path',
          'member-a',
          'selected-a',
          0,
          'fixture-url',
        ];
        final SwapListResources receipt = SwapListResources(
          identities: () => const <Object?>[],
          values: () => values,
          ready: () => true,
        );
        final Object? original = values[position];
        values[position] = 'changed';
        expect(receipt.isCurrent, isFalse);
        values[position] = original;
        expect(receipt.isCurrent, isFalse);
      },
    );
  }
}
