import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  test(
    'two exact pages reach genesis and return owned blocks in ascending order',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(
        historyPage(descendingHistory(101, 2), count: 101, more: false),
      );
      fixture.pages.add(
        historyPage(<AccountBlock>[historyBlock(1)], count: 101, more: false),
      );
      final List<AccountBlock> blocks = await fixture.history();
      expect(blocks.map((AccountBlock block) => block.height).toList(), <int>[
        for (int i = 1; i <= 101; i++) i,
      ]);
      expect(
        fixture.replies.calls
            .map(((String, List<dynamic>) call) => call.$1)
            .toList(),
        <String>[
          'ledger.getAccountBlocksByPage',
          'ledger.getAccountBlocksByPage',
        ],
      );
      expect(fixture.replies.calls[0].$2, <dynamic>[
        fixture.address.toString(),
        0,
        100,
      ]);
      expect(fixture.replies.calls[1].$2, <dynamic>[
        fixture.address.toString(),
        1,
        100,
      ]);
    },
  );

  test(
    'the exact timestamp cutoff excludes its boundary and needs no later page',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(
        historyPage(descendingHistory(5, 3)),
      );
      final List<AccountBlock> blocks = await fixture.history(after: 1003);
      expect(blocks.map((AccountBlock block) => block.height).toList(), <int>[
        4,
        5,
      ]);
      expect(fixture.replies.calls.length, 1);
    },
  );

  test(
    'positive links and genesis remain provable when optional count is omitted',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(
        historyPage(descendingHistory(2, 1)),
      );
      expect(
        (await fixture.history())
            .map((AccountBlock block) => block.height)
            .toList(),
        <int>[1, 2],
      );
    },
  );

  for (final bool? more in <bool?>[false, null]) {
    test(
      'actual empty first page with positive count zero '
      'and more $more proves emptiness',
      () async {
        final HistoryFixture fixture = HistoryFixture();
        fixture.pages.add(historyPage(<AccountBlock>[], count: 0, more: more));
        expect(await fixture.history(), isEmpty);
        expect(fixture.replies.calls.length, 1);
      },
    );
  }

  for (final String defect in <String>[
    'null-list',
    'missing-count',
    'positive-count',
    'more',
  ]) {
    test('$defect cannot prove an empty account', () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(
        historyPage(
          defect == 'null-list' ? null : <AccountBlock>[],
          count: defect == 'missing-count'
              ? null
              : defect == 'positive-count'
              ? 1
              : 0,
          more: defect == 'more',
        ),
      );
      await expectLater(fixture.history(), throwsA(isA<StateError>()));
      expect(fixture.replies.calls.length, 1);
    });
  }

  test(
    'an empty later page cannot convert an incomplete prefix into absence',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(historyPage(descendingHistory(101, 2), count: 101));
      fixture.pages.add(historyPage(<AccountBlock>[], count: 0, more: false));
      await expectLater(fixture.history(), throwsA(isA<StateError>()));
      expect(fixture.replies.calls.length, 2);
    },
  );

  test(
    'a short page above genesis and cutoff refuses despite more false',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(
        historyPage(descendingHistory(5, 4), count: 2, more: false),
      );
      await expectLater(fixture.history(), throwsA(isA<StateError>()));
      expect(fixture.replies.calls.length, 1);
    },
  );

  test(
    'an oversized page is refused before its apparent genesis is trusted',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(historyPage(descendingHistory(101, 1), count: 101));
      await expectLater(fixture.history(), throwsA(isA<StateError>()));
    },
  );

  for (final String defect in <String>[
    'height-gap',
    'height-zero',
    'link',
    'duplicate',
    'address',
    'chain',
    'empty-hash',
    'confirmation',
    'zero-confirmations',
    'negative-confirmations',
    'zero-time',
    'increasing-time',
  ]) {
    test('history $defect refuses an incomplete chain', () async {
      final HistoryFixture fixture = HistoryFixture();
      final List<AccountBlock> page = descendingHistory(3, 1);
      final AccountBlock middle = page[1];
      if (defect == 'height-gap') middle.height = 1;
      if (defect == 'height-zero') middle.height = 0;
      if (defect == 'link') {
        page.first.previousHash = Hash.parse(historyHash(999));
      }
      if (defect == 'duplicate') middle.hash = page.first.hash;
      if (defect == 'address') middle.address = historyAddress(9);
      if (defect == 'chain') middle.chainIdentifier++;
      if (defect == 'empty-hash') middle.hash = emptyHash;
      if (defect == 'confirmation') middle.confirmationDetail = null;
      if (defect == 'zero-confirmations') {
        middle.confirmationDetail!.numConfirmations = 0;
      }
      if (defect == 'negative-confirmations') {
        middle.confirmationDetail!.numConfirmations = -1;
      }
      if (defect == 'zero-time') {
        middle.confirmationDetail!.momentumTimestamp = 0;
      }
      if (defect == 'increasing-time') {
        middle.confirmationDetail!.momentumTimestamp = 1004;
      }
      fixture.pages.add(historyPage(page, count: 3));
      await expectLater(fixture.history(), throwsA(isA<StateError>()));
      expect(fixture.replies.calls.length, 1);
    });
  }

  test(
    'the cross-page previous hash binds the exact next original block',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      final List<AccountBlock> first = descendingHistory(101, 2);
      first.last.previousHash = Hash.parse(historyHash(999));
      fixture.pages.add(historyPage(first, count: 101));
      fixture.pages.add(
        historyPage(<AccountBlock>[historyBlock(1)], count: 101),
      );
      await expectLater(fixture.history(), throwsA(isA<StateError>()));
      expect(fixture.replies.calls.length, 2);
    },
  );

  test(
    'a finite page limit refuses a prefix without dispatching an extra read',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      fixture.pages.add(historyPage(descendingHistory(101, 2), count: 101));
      await expectLater(
        fixture.history(maxPages: 1),
        throwsA(isA<StateError>()),
      );
      expect(fixture.replies.calls.length, 1);
    },
  );

  for (final (int, int) boundary in <(int, int)>[(-1, 1), (0, 0), (0, -1)]) {
    test('invalid history boundary $boundary never dispatches', () async {
      final HistoryFixture fixture = HistoryFixture();
      await expectLater(
        fixture.history(after: boundary.$1, maxPages: boundary.$2),
        throwsA(isA<StateError>()),
      );
      expect(fixture.replies.calls, isEmpty);
    });
  }

  for (final String departure in <String>['client', 'source', 'chain', 'URL']) {
    test(
      'an awaiting history $departure departure '
      'cannot adopt the original reply',
      () async {
        final HistoryFixture fixture = HistoryFixture(
          socket: departure == 'URL',
        );
        final HistoryReplies replacement = HistoryReplies();
        final Completer<dynamic> pending = fixture.ownCompleter<dynamic>();
        fixture.replies.answer = (_, _) => pending.future;
        final Future<List<AccountBlock>> original = fixture.history();
        final Future<void> refused = expectLater(
          original,
          throwsA(isA<StateError>()),
        );
        expect(fixture.replies.calls.length, 1);
        if (departure == 'client') {
          fixture.ledger.setClient(HistoryClient(replacement));
        }
        if (departure == 'source') fixture.current = false;
        if (departure == 'chain') {
          setChainIdentifier(chainIdentifier: historyChain + 1);
        }
        if (departure == 'URL') {
          (fixture.transport as HistorySocket).url =
              'ws://fixture.invalid/replacement';
        }
        pending.complete(
          historyPage(<AccountBlock>[historyBlock(1)], count: 1),
        );
        await refused;
        expect(fixture.replies.calls.length, 1);
        expect(replacement.calls, isEmpty);
      },
    );
  }

  test('a refused source does not dispatch its first history read', () async {
    final HistoryFixture fixture = HistoryFixture()..current = false;
    await expectLater(fixture.history(), throwsA(isA<StateError>()));
    expect(fixture.replies.calls, isEmpty);
  });

  for (final bool partial in <bool>[false, true]) {
    test(
      '${partial ? 'partial' : 'null'} raw history JSON '
      'remains unavailable instead of empty',
      () async {
        final HistoryFixture fixture = HistoryFixture();
        fixture.replies.answer = (_, _) => Future<dynamic>.value(
          partial
              ? <String, dynamic>{
                  'count': 1,
                  'list': <dynamic>[
                    <String, dynamic>{'hash': historyHash(1)},
                  ],
                }
              : null,
        );
        await expectLater(fixture.history(), throwsA(isA<TypeError>()));
        expect(fixture.replies.calls.length, 1);
      },
    );
  }

  test(
    'the exact original history error and trace survive transport replacement',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      final Completer<dynamic> pending = fixture.ownCompleter<dynamic>();
      fixture.replies.answer = (_, _) => pending.future;
      final Future<List<AccountBlock>> original = fixture.history();
      final Object failure = StateError('Synthetic original account history');
      final StackTrace trace = StackTrace.current;
      fixture.ledger.setClient(HistoryClient(HistoryReplies()));
      pending.completeError(failure, trace);
      try {
        await original;
        fail('The uncertain original RPC must not become an empty catalogue');
      } on Object catch (error, stackTrace) {
        expect(error, same(failure));
        expect(stackTrace, same(trace));
      }
      expect(fixture.replies.calls.length, 1);
    },
  );

  test(
    'an unresolved admitted history read remains pending '
    'until its owned reply settles',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      final Completer<dynamic> pending = fixture.ownCompleter<dynamic>();
      fixture.replies.answer = (_, _) => pending.future;
      bool settled = false;
      final Future<List<AccountBlock>> original = fixture.history();
      unawaited(
        original.then<void>(
          (_) {
            settled = true;
          },
          onError: (Object _, StackTrace _) {
            settled = true;
          },
        ),
      );
      await Future<void>.value();
      expect(settled, isFalse);
      pending.complete(historyPage(<AccountBlock>[historyBlock(1)], count: 1));
      expect((await original).single.height, 1);
      expect(fixture.replies.calls.length, 1);
    },
  );
}
