import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/nodes/cubit/nodes_counts_cubit.dart';

class _Source {
  final List<Completer<int>> replies = <Completer<int>>[];

  Future<int> load() {
    final Completer<int> reply = Completer<int>();
    replies.add(reply);
    return reply.future;
  }
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  late _Source pillars;
  late _Source sentinels;
  late bool current;
  late NodesCountsCubit cubit;

  setUp(() {
    pillars = _Source();
    sentinels = _Source();
    current = true;
    cubit = NodesCountsCubit(
      loadPillars: pillars.load,
      loadSentinels: sentinels.load,
      isCurrent: () => current,
    );
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  test(
    'requests only on refresh and accepts independent actual totals',
    () async {
      expect(cubit.state, (pillars: null, sentinels: null));
      expect(pillars.replies, isEmpty);
      expect(sentinels.replies, isEmpty);

      final Future<void> refresh = cubit.refresh();
      expect(pillars.replies, hasLength(1));
      expect(sentinels.replies, hasLength(1));
      sentinels.replies.single.complete(0);
      await _drain();
      expect(cubit.state, (pillars: null, sentinels: 0));

      pillars.replies.single.complete(97);
      await refresh;
      expect(cubit.state, (pillars: 97, sentinels: 0));
      expect(pillars.replies, hasLength(1));
      expect(sentinels.replies, hasLength(1));
    },
  );

  test(
    'a fresh refresh discards previous totals before either answer',
    () async {
      final Future<void> first = cubit.refresh();
      pillars.replies.single.complete(97);
      sentinels.replies.single.complete(12);
      await first;

      final Future<void> next = cubit.refresh();
      expect(cubit.state, (pillars: null, sentinels: null));
      pillars.replies.last.completeError(StateError('Unavailable'));
      sentinels.replies.last.complete(13);
      await next;
      expect(cubit.state, (pillars: null, sentinels: 13));
    },
  );

  for (final bool pillarFailure in <bool>[false, true]) {
    for (final bool throws in <bool>[false, true]) {
      test(
        '${pillarFailure ? 'pillar' : 'sentinel'} '
        '${throws ? 'failure' : 'negative total'} stays unknown',
        () async {
          final Future<void> refresh = cubit.refresh();
          final Completer<int> invalid = pillarFailure
              ? pillars.replies.single
              : sentinels.replies.single;
          final Completer<int> valid = pillarFailure
              ? sentinels.replies.single
              : pillars.replies.single;
          if (throws) {
            invalid.completeError(StateError('Unavailable'));
          } else {
            invalid.complete(-1);
          }
          valid.complete(0);
          await refresh;
          expect(
            cubit.state,
            pillarFailure
                ? (pillars: null, sentinels: 0)
                : (pillars: 0, sentinels: null),
          );
        },
      );
    }
  }

  test(
    'a synchronous source failure does not prevent the other request',
    () async {
      await cubit.close();
      cubit = NodesCountsCubit(
        loadPillars: () => throw StateError('Unavailable'),
        loadSentinels: sentinels.load,
        isCurrent: () => current,
      );
      final Future<void> refresh = cubit.refresh();
      expect(sentinels.replies, hasLength(1));
      sentinels.replies.single.complete(12);
      await refresh;
      expect(cubit.state, (pillars: null, sentinels: 12));
    },
  );

  for (final bool failure in <bool>[false, true]) {
    test('superseded ${failure ? 'failures' : 'totals'} are refused', () async {
      final Future<void> first = cubit.refresh();
      final Future<void> next = cubit.refresh();
      pillars.replies.last.complete(98);
      sentinels.replies.last.complete(13);
      await next;
      expect(cubit.state, (pillars: 98, sentinels: 13));

      if (failure) {
        pillars.replies.first.completeError(StateError('Old failure'));
        sentinels.replies.first.completeError(StateError('Old failure'));
      } else {
        pillars.replies.first.complete(97);
        sentinels.replies.first.complete(12);
      }
      await first;
      expect(cubit.state, (pillars: 98, sentinels: 13));
    });
  }

  test(
    'a changed context clears partial data and permanently revokes replies',
    () async {
      final Future<void> refresh = cubit.refresh();
      pillars.replies.single.complete(97);
      await _drain();
      expect(cubit.state, (pillars: 97, sentinels: null));

      current = false;
      sentinels.replies.single.complete(12);
      await refresh;
      expect(cubit.state, (pillars: null, sentinels: null));

      current = true;
      await cubit.refresh();
      expect(pillars.replies, hasLength(1));
      expect(sentinels.replies, hasLength(1));
      expect(cubit.state, (pillars: null, sentinels: null));
    },
  );

  test('an already changed context starts no requests', () async {
    current = false;
    await cubit.refresh();
    expect(pillars.replies, isEmpty);
    expect(sentinels.replies, isEmpty);
    expect(cubit.state, (pillars: null, sentinels: null));
  });

  test('a context predicate failure refuses requests', () async {
    await cubit.close();
    cubit = NodesCountsCubit(
      loadPillars: pillars.load,
      loadSentinels: sentinels.load,
      isCurrent: () => throw StateError('Context unavailable'),
    );
    await cubit.refresh();
    expect(pillars.replies, isEmpty);
    expect(sentinels.replies, isEmpty);
    expect(cubit.state, (pillars: null, sentinels: null));
  });

  test(
    'closing refuses late successes, failures and further refreshes',
    () async {
      final Future<void> refresh = cubit.refresh();
      await cubit.close();
      pillars.replies.single.complete(97);
      sentinels.replies.single.completeError(StateError('Late failure'));
      await refresh;
      await cubit.refresh();
      expect(cubit.state, (pillars: null, sentinels: null));
      expect(pillars.replies, hasLength(1));
      expect(sentinels.replies, hasLength(1));
    },
  );
}
