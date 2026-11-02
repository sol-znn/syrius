import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';

import '../htlc_ownership/support.dart' as owned;
import 'support.dart';

class _OriginalPublication implements SwapPublicationReservation {
  _OriginalPublication(this.request);
  final HtlcActionWriteRequest request;
  Future<void>? preparation;
  @override
  Future<void> prepare({Map<String, dynamic>? recovery}) =>
      preparation = request.prepare(recovery: recovery);
  @override
  Future<void> accepted(String exactHash) => request.accepted(exactHash);
  @override
  Future<void> refuseBeforePublication() => request.refuseBeforePublication();
  @override
  void retainUnknown(Object error, StackTrace trace) =>
      request.retainUnknown(error, trace);
}

void main() {
  test(
    'a held durable action settles the new pre-write refusal '
    'without clearing the old hold',
    () async {
      final ActionFixture action = ActionFixture();
      final owned.HtlcFixture backend = owned.HtlcFixture(501);
      final HtlcActionWriteRequest old = backend.store.reserveAction(
        kind: 'start',
        targetId: 'new',
        owner: action.owner,
      );
      await old.prepare(recovery: <String, dynamic>{'fixture': 'retained'});
      await old.accepted(actionHash(800));
      final Map<dynamic, dynamic> retained = Map<dynamic, dynamic>.of(
        backend.swaps.entries,
      );
      late _OriginalPublication request;
      action.reserveMarker = (String kind, String target, String owner) =>
          request = _OriginalPublication(
            backend.store.reserveAction(
              kind: kind,
              targetId: target,
              owner: owner,
            ),
          );

      final SwapActionResult result = await action.start();
      expect(result.status, SwapActionStatus.refused);
      expect(
        result.error,
        isA<HtlcOwnershipRefused>().having(
          (HtlcOwnershipRefused value) => value.reason,
          'reason',
          'durable-action-held',
        ),
      );
      expect(result.preparation, same(request.preparation));
      expect(result.reservationError, isNull);
      expect(request.request.receipt.completed, isTrue);
      expect(request.request.receipt.error, isNull);
      expect(action.publications, 0);
      expect(action.store.refusals, 1);
      expect(backend.swaps.entries, retained);
      final owned.HtlcOutcome<HtlcDrainReceipt> drain =
          owned.HtlcOutcome<HtlcDrainReceipt>(backend.service.pauseAndDrain());
      await owned.htlcMicrotasks();
      expect(drain.completed, isTrue);
      expect((await drain.future).completed, isTrue);
    },
  );

  test(
    'a shared automatic withdrawal hold '
    'positively settles manual preparation refusal',
    () async {
      final ActionFixture action = ActionFixture();
      final HtlcSwap swap = action.seedSwap();
      final owned.HtlcFixture backend = owned.HtlcFixture(502);
      final HtlcUnlockWriteRequest old = backend.store.reserveUnlock(
        swap.initialHtlcId,
        action.owner,
      );
      expect(await old.claim(), isTrue);
      await old.accept(actionHash(801));
      final Map<dynamic, dynamic> retained = Map<dynamic, dynamic>.of(
        backend.swaps.entries,
      );
      late _OriginalPublication request;
      action.reserveMarker = (String kind, String target, String owner) =>
          request = _OriginalPublication(
            backend.store.reserveAction(
              kind: kind,
              targetId: target,
              owner: owner,
            ),
          );

      final SwapActionResult result = await action.complete(swap);
      expect(result.status, SwapActionStatus.refused);
      expect(
        result.error,
        isA<HtlcOwnershipRefused>().having(
          (HtlcOwnershipRefused value) => value.reason,
          'reason',
          'withdrawal-outcome-held',
        ),
      );
      expect(result.preparation, same(request.preparation));
      expect(request.request.receipt.completed, isTrue);
      expect(request.request.receipt.error, isNull);
      expect(action.publications, 0);
      expect(backend.swaps.entries, retained);
      final owned.HtlcOutcome<HtlcDrainReceipt> drain =
          owned.HtlcOutcome<HtlcDrainReceipt>(backend.service.pauseAndDrain());
      await owned.htlcMicrotasks();
      expect(drain.completed, isTrue);
      expect((await drain.future).completed, isTrue);
    },
  );

  test(
    'a failed original preparation write retains its exact failure '
    'and reaches a negative terminal drain',
    () async {
      final ActionFixture action = ActionFixture();
      final owned.HtlcFixture backend = owned.HtlcFixture(503);
      backend.swaps.deferred.add('put');
      backend.swaps.optimistic = true;
      late _OriginalPublication request;
      action.reserveMarker = (String kind, String target, String owner) =>
          request = _OriginalPublication(
            backend.store.reserveAction(
              kind: kind,
              targetId: target,
              owner: owner,
            ),
          );
      final Future<SwapActionResult> original = action.start();
      await microtasksUntil(() => backend.swaps.calls.isNotEmpty);
      final Object failure = StateError('Synthetic original preparation write');
      backend.swaps.calls.single.fail(failure);
      final SwapActionResult result = await original;
      expect(result.status, SwapActionStatus.unknown);
      expect(result.error, same(failure));
      expect(result.reservationError, same(failure));
      expect(result.preparation, same(request.preparation));
      expect(request.request.receipt.completed, isTrue);
      expect(request.request.receipt.error, same(failure));
      expect(action.start(), same(original));
      expect(action.publications, 0);
      expect(
        (backend.markers.values.single as Map<String, dynamic>)['status'],
        'publishing',
      );
      final owned.HtlcOutcome<HtlcDrainReceipt> drain =
          owned.HtlcOutcome<HtlcDrainReceipt>(backend.service.pauseAndDrain());
      await owned.htlcMicrotasks();
      expect(drain.completed, isTrue);
      final HtlcDrainReceipt receipt = await drain.future;
      expect(receipt.completed, isFalse);
      expect(receipt.error, same(failure));
      expect(
        receipt.operations.every(
          (HtlcOperationReceipt value) => value.completed,
        ),
        isTrue,
      );
    },
  );
}
