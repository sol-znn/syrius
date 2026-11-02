import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

void main() {
  initHydratedStorage();

  for (final int height in <int>[9, 10, 11]) {
    test(
      'frontier $height uses strict greater-than expiration eligibility',
      () async {
        final PlasmaFixture fixture = PlasmaFixture()..frontier = height;
        addTearDown(fixture.close);
        await fixture.loadAll();
        final PlasmaFusion entry = fixture.owner.read!.entries.first;
        expect(fixture.owner.canSelect(entry), height > 10);
        final PlasmaCancelIntent? intent = fixture.owner.beginCancellation(
          session: fixture.session(),
          hash: entry.hash,
          isCurrent: () => true,
        );
        expect(intent != null, height > 10);
        if (intent != null) fixture.owner.finishQuestion(intent);
        expect(fixture.transport.calls, isEmpty);
      },
    );
  }

  test(
    'fresh frontier equality refuses a previously eligible displayed row',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(1));
      fixture.frontier = 10;
      final PlasmaCancellationBatch result = (await fixture.owner.cancel(
        intent,
      ))!;
      expect(result.outcomes.single.status, PlasmaCancellationStatus.refused);
      expect(fixture.cancellations, isEmpty);
      expect(fixture.transport.calls, isEmpty);
      expect(fixture.owner.read!.entries.length, 3);
    },
  );

  test(
    'fresh exact ownership refuses changed amounts and fuzzy replacements',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(1));
      fixture.rows = <FusionEntry>[
        plasmaTestEntry(9, amount: intent.entries.single.amount),
        plasmaTestEntry(2),
        plasmaTestEntry(3),
      ];
      final PlasmaCancellationBatch result = (await fixture.owner.cancel(
        intent,
      ))!;
      expect(result.outcomes.single.entry.hash, plasmaTestHash(1));
      expect(result.outcomes.single.status, PlasmaCancellationStatus.refused);
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test(
    'same hash with changed beneficiary facts cannot pass a fresh proof',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(1));
      fixture.rows.first.qsrAmount += BigInt.one;
      final PlasmaCancellationBatch result = (await fixture.owner.cancel(
        intent,
      ))!;
      expect(result.outcomes.single.status, PlasmaCancellationStatus.refused);
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test(
    'fresh ownership scans later pages for the original exact hash',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.pages.clear();
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(3));
      final PlasmaCancellationBatch result = (await fixture.owner.cancel(
        intent,
      ))!;
      expect(fixture.pages, <(int, int)>[(0, 2), (1, 2)]);
      expect(fixture.cancellations, <String>[plasmaTestHash(3)]);
      expect(result.submitted, 1);
      expect(result.outcomes.single.entry.hash, plasmaTestHash(3));
      // An accepted send does not establish that the contract removed a row.
      expect(fixture.owner.read!.entries.length, 3);
    },
  );

  test(
    'batch dispatch is serial and stops on the first unknown original result',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.deferred = true;
      final PlasmaCancelIntent intent = fixture.intent();
      final Future<PlasmaTransportCall> first = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        intent,
      );
      await first.timeout(const Duration(seconds: 2));
      expect(fixture.transport.calls.length, 1);
      expect(fixture.sender.busy.value, isTrue);
      final Future<PlasmaTransportCall> second = fixture.transport.next;
      fixture.transport.completeNext();
      await second.timeout(const Duration(seconds: 2));
      expect(fixture.transport.calls.length, 2);
      final Object originalError = StateError('Fixture response was lost');
      fixture.transport.completeNext(error: originalError);
      final PlasmaCancellationBatch result = (await operation)!;
      expect(result.submitted, 1);
      expect(
        result.outcomes.map((PlasmaCancellationOutcome o) => o.status),
        <PlasmaCancellationStatus>[
          PlasmaCancellationStatus.submitted,
          PlasmaCancellationStatus.unknown,
        ],
      );
      expect(result.outcomes.last.result!.error, same(originalError));
      expect(result.intent.entries.map((PlasmaFusion e) => e.hash), <String>[
        plasmaTestHash(1),
        plasmaTestHash(2),
        plasmaTestHash(3),
      ]);
      expect(fixture.cancellations, <String>[
        plasmaTestHash(1),
        plasmaTestHash(2),
      ]);
      expect(fixture.owner.outcomes.containsKey(plasmaTestHash(3)), isFalse);
      expect(fixture.sender.busy.value, isFalse);
      expect(fixture.owner.read!.entries.length, 3);
      expect(fixture.owner.canSelect(fixture.owner.read!.entries[1]), isFalse);
      expect(fixture.owner.canSelect(fixture.owner.read!.entries[2]), isTrue);
    },
  );

  test(
    'selection and original facts are frozen before a question yields',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.owner.select(fixture.owner.read!.entries[1], selected: true);
      final PlasmaCancelIntent intent = fixture.owner.beginCancellation(
        session: fixture.session(),
        isCurrent: () => fixture.visible,
      )!;
      fixture.owner.select(fixture.owner.read!.entries[0], selected: true);
      expect(intent.entries.single.hash, plasmaTestHash(2));
      expect(fixture.owner.selected, <String>{plasmaTestHash(2)});
      expect(
        fixture.owner.beginCancellation(
          session: fixture.session(),
          hash: plasmaTestHash(1),
          isCurrent: () => true,
        ),
        isNull,
      );
      final PlasmaCancellationBatch result = (await fixture.owner.cancel(
        intent,
      ))!;
      expect(result.intent, same(intent));
      expect(fixture.cancellations, <String>[plasmaTestHash(2)]);
    },
  );

  test(
    'duplicate callbacks cannot enqueue another row or repeat an admitted hash',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.deferred = true;
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(1));
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        intent,
      );
      await started.timeout(const Duration(seconds: 2));
      expect(await fixture.owner.cancel(intent), isNull);
      fixture.transport.completeNext();
      await operation;
      expect(await fixture.owner.cancel(intent), isNull);
      expect(
        fixture.owner.beginCancellation(
          session: fixture.session(),
          hash: plasmaTestHash(1),
          isCurrent: () => true,
        ),
        isNull,
      );
      expect(fixture.transport.calls.length, 1);
    },
  );

  test(
    'revocation after an accepted first send preserves it and stops the suffix',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.deferred = true;
      final PlasmaCancelIntent intent = fixture.intent();
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        intent,
      );
      await started.timeout(const Duration(seconds: 2));
      fixture.revision++;
      fixture.transport.completeNext();
      final PlasmaCancellationBatch result = (await operation)!;
      expect(result.submitted, 1);
      expect(result.outcomes.single.publicationHash, plasmaTestHash(1000));
      expect(fixture.transport.calls.length, 1);
      expect(
        fixture.owner.outcomes[plasmaTestHash(1)]!.status,
        PlasmaCancellationStatus.submitted,
      );
    },
  );

  test(
    'preparation guard refuses a context round trip before transport',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.preparation = Completer<void>();
      final PlasmaCancelIntent intent = fixture.intent();
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        intent,
      );
      await started.timeout(const Duration(seconds: 2));
      fixture.revision += 2;
      fixture.transport.preparation!.complete();
      final PlasmaCancellationBatch result = (await operation)!;
      expect(result.submitted, 0);
      expect(result.outcomes.single.status, PlasmaCancellationStatus.unknown);
      expect(fixture.transport.published, 0);
      expect(fixture.transport.calls.length, 1);
    },
  );

  test(
    'page disposal after dispatch retains the original submitted result',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.deferred = true;
      final PlasmaCancelIntent intent = fixture.intent();
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        intent,
      );
      await started.timeout(const Duration(seconds: 2));
      fixture.disposeOwner();
      fixture.transport.completeNext();
      final PlasmaCancellationBatch result = (await operation)!;
      expect(result.submitted, 1);
      expect(result.outcomes.single.result!.accepted, isTrue);
      expect(
        fixture.owner.outcomes[plasmaTestHash(1)]!.publicationHash,
        plasmaTestHash(1000),
      );
      expect(fixture.transport.calls.length, 1);
    },
  );

  test(
    'wrong returned chain is unknown and cannot start the next cancellation',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.deferred = true;
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        fixture.intent(),
      );
      final PlasmaTransportCall call = await started.timeout(
        const Duration(seconds: 2),
      );
      fixture.transport.completeNext(
        response: fixture.transport.accepted(call)..chainIdentifier = 1,
      );
      final PlasmaCancellationBatch result = (await operation)!;
      expect(result.submitted, 0);
      expect(result.outcomes.single.status, PlasmaCancellationStatus.unknown);
      expect(result.outcomes.single.publicationHash, plasmaTestHash(1000));
      expect(fixture.transport.calls.length, 1);
    },
  );

  test(
    'a same-account response with another cancellation payload is unknown',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      fixture.transport.deferred = true;
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> operation = fixture.owner.cancel(
        fixture.intent(),
      );
      final PlasmaTransportCall call = await started.timeout(
        const Duration(seconds: 2),
      );
      fixture.transport.completeNext(
        response: fixture.transport.accepted(call)
          ..data = Hash.parse(plasmaTestHash(9)).getBytes()!,
      );
      final PlasmaCancellationBatch batch = (await operation)!;
      expect(batch.outcomes.single.status, PlasmaCancellationStatus.unknown);
      expect(batch.outcomes.single.entry.hash, plasmaTestHash(1));
      expect(fixture.transport.calls.length, 1);
    },
  );

  test(
    'failed follow-up retains rows and journal without fresh authority',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final PlasmaCancellationBatch batch = (await fixture.owner.cancel(
        fixture.intent(hash: plasmaTestHash(1)),
      ))!;
      fixture.fetch = (_, _) async => throw StateError('Fixture read failed');
      await fixture.owner.load(fixture.session());
      expect(fixture.owner.read, isNull);
      expect(fixture.owner.displayRead!.entries.length, 3);
      expect(
        fixture.owner.outcomes[plasmaTestHash(1)],
        same(batch.outcomes.single),
      );
      expect(
        fixture.owner.beginCancellation(
          session: fixture.session(),
          hash: plasmaTestHash(2),
          isCurrent: () => true,
        ),
        isNull,
      );
    },
  );

  test(
    'null sender admission is a known refusal, not an uncertain publication',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(1));
      fixture.fetch = (_, _) {
        unawaited(fixture.sender.close());
        return Future<FusionEntryList>.value(
          plasmaTestPage(
            fixture.rows.take(2).toList(),
            count: 3,
            total: BigInt.from(600000000),
          ),
        );
      };
      final PlasmaCancellationBatch batch = (await fixture.owner.cancel(
        intent,
      ))!;
      expect(batch.outcomes.single.status, PlasmaCancellationStatus.refused);
      expect(batch.outcomes.single.requestId, isNotNull);
      expect(batch.outcomes.single.result, isNull);
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test(
    'a successful fresh read rearms only a known pre-admission refusal',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final PlasmaCancelIntent first = fixture.intent(hash: plasmaTestHash(1));
      fixture.frontier = 10;
      final PlasmaCancellationBatch refused = (await fixture.owner.cancel(
        first,
      ))!;
      expect(refused.outcomes.single.status, PlasmaCancellationStatus.refused);
      expect(
        fixture.owner.canSelect(fixture.owner.read!.entries.first),
        isFalse,
      );
      fixture.frontier = 11;
      await fixture.owner.load(fixture.session());
      expect(
        fixture.owner.canSelect(fixture.owner.read!.entries.first),
        isTrue,
      );
      expect(fixture.owner.displayOutcome(plasmaTestHash(1)), isNull);
      final PlasmaCancellationBatch submitted = (await fixture.owner.cancel(
        fixture.intent(hash: plasmaTestHash(1)),
      ))!;
      expect(submitted.submitted, 1);
      expect(fixture.owner.batches, <PlasmaCancellationBatch>[
        refused,
        submitted,
      ]);
      expect(
        fixture.owner.batches.first.outcomes.single.status,
        PlasmaCancellationStatus.refused,
      );
      await fixture.owner.load(fixture.session());
      expect(
        fixture.owner.canSelect(fixture.owner.read!.entries.first),
        isFalse,
      );
      expect(
        fixture.owner.displayOutcome(plasmaTestHash(1))!.status,
        PlasmaCancellationStatus.submitted,
      );
    },
  );
}
