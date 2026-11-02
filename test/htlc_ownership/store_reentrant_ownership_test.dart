import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';

import 'support.dart';

void main() {
  for (final bool selection in <bool>[false, true]) {
    test(
      'nested store loss survives a restored outer proof, selection $selection',
      () {
        final MemoryHtlcBox swaps = MemoryHtlcBox('reentrant-swaps');
        final MemoryHtlcBox cursor = MemoryHtlcBox('reentrant-cursor');
        bool owned = true;
        bool reenter = false;
        bool? nested;
        int reads = 0;
        late final HtlcStoreCapture capture;
        final HtlcSwapsService service = HtlcSwapsService.bound(
          swaps: swaps,
          cursor: cursor,
          ownsBox: (_) {
            reads++;
            if (reenter) {
              reenter = false;
              owned = false;
              nested = selection ? capture.isCurrent : capture.ownsStore;
              owned = true;
            }
            return owned;
          },
        );
        capture = service.captureStore(chainId: htlcChain)!;
        reenter = true;
        expect(selection ? capture.isCurrent : capture.ownsStore, isFalse);
        expect(nested, isFalse);
        expect(owned, isTrue);
        final int readsAfterRevocation = reads;
        expect(capture.ownsStore, isFalse);
        expect(capture.isCurrent, isFalse);
        expect(capture.reserveWrite, throwsA(isA<HtlcOwnershipRefused>()));
        expect(reads, readsAfterRevocation);
        expect(swaps.calls, isEmpty);
        expect(cursor.calls, isEmpty);
      },
    );
  }
}
