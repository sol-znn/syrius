import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  test(
    'an exact owned confirmed height returns its positive chain timestamp',
    () async {
      final HistoryFixture fixture = HistoryFixture()
        ..heightReply = historyPage(<AccountBlock>[
          historyBlock(5),
        ], count: 1);
      expect(await fixture.timestamp(), 1005);
      expect(
        fixture.replies.calls.single.$1,
        'ledger.getAccountBlocksByHeight',
      );
      expect(fixture.replies.calls.single.$2, <dynamic>[
        fixture.address.toString(),
        5,
        1,
      ]);
    },
  );

  for (final int height in <int>[0, -1]) {
    test('nonpositive exact height $height does not dispatch', () async {
      final HistoryFixture fixture = HistoryFixture();
      expect(await fixture.timestamp(height: height), isNull);
      expect(fixture.replies.calls, isEmpty);
    });
  }

  for (final String defect in <String>[
    'null-list',
    'empty',
    'multiple',
    'address',
    'height',
    'chain',
    'empty-hash',
    'confirmation',
    'zero-confirmations',
    'negative-confirmations',
    'zero-time',
    'negative-time',
  ]) {
    test(
      'exact height $defect returns unavailable '
      'instead of an invented timestamp',
      () async {
        final HistoryFixture fixture = HistoryFixture();
        final AccountBlock block = historyBlock(5);
        List<AccountBlock>? page = <AccountBlock>[block];
        if (defect == 'null-list') page = null;
        if (defect == 'empty') page = <AccountBlock>[];
        if (defect == 'multiple') page = <AccountBlock>[block, historyBlock(4)];
        if (defect == 'address') block.address = historyAddress(9);
        if (defect == 'height') block.height = 4;
        if (defect == 'chain') block.chainIdentifier++;
        if (defect == 'empty-hash') block.hash = emptyHash;
        if (defect == 'confirmation') block.confirmationDetail = null;
        if (defect == 'zero-confirmations') {
          block.confirmationDetail!.numConfirmations = 0;
        }
        if (defect == 'negative-confirmations') {
          block.confirmationDetail!.numConfirmations = -1;
        }
        if (defect == 'zero-time') {
          block.confirmationDetail!.momentumTimestamp = 0;
        }
        if (defect == 'negative-time') {
          block.confirmationDetail!.momentumTimestamp = -1;
        }
        fixture.heightReply = historyPage(page, count: page?.length);
        expect(await fixture.timestamp(), isNull);
        expect(fixture.replies.calls.length, 1);
      },
    );
  }

  for (final String departure in <String>['client', 'source', 'chain', 'URL']) {
    test(
      'an awaiting exact height $departure departure cannot supply a timestamp',
      () async {
        final HistoryFixture fixture = HistoryFixture(
          socket: departure == 'URL',
        );
        final HistoryReplies replacement = HistoryReplies();
        final Completer<dynamic> pending = fixture.ownCompleter<dynamic>();
        fixture.replies.answer = (_, _) => pending.future;
        final Future<int?> original = fixture.timestamp();
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
          historyPage(<AccountBlock>[historyBlock(5)], count: 1),
        );
        expect(await original, isNull);
        expect(fixture.replies.calls.length, 1);
        expect(replacement.calls, isEmpty);
      },
    );
  }

  test('a refused source does not dispatch an exact height read', () async {
    final HistoryFixture fixture = HistoryFixture()..current = false;
    expect(await fixture.timestamp(), isNull);
    expect(fixture.replies.calls, isEmpty);
  });

  for (final bool partial in <bool>[false, true]) {
    test(
      '${partial ? 'partial' : 'null'} raw exact-height JSON '
      'cannot become a missing height',
      () async {
        final HistoryFixture fixture = HistoryFixture();
        fixture.replies.answer = (_, _) => Future<dynamic>.value(
          partial
              ? <String, dynamic>{
                  'count': 1,
                  'list': <dynamic>[
                    <String, dynamic>{'hash': historyHash(5)},
                  ],
                }
              : null,
        );
        await expectLater(fixture.timestamp(), throwsA(isA<TypeError>()));
        expect(fixture.replies.calls.length, 1);
      },
    );
  }

  test(
    'an exact height original error and trace survive a source departure',
    () async {
      final HistoryFixture fixture = HistoryFixture();
      final Completer<dynamic> pending = fixture.ownCompleter<dynamic>();
      fixture.replies.answer = (_, _) => pending.future;
      final Future<int?> original = fixture.timestamp();
      final Object failure = StateError('Synthetic original exact height');
      final StackTrace trace = StackTrace.current;
      fixture.current = false;
      pending.completeError(failure, trace);
      try {
        await original;
        fail('An original read error cannot become a missing height');
      } on Object catch (error, stackTrace) {
        expect(error, same(failure));
        expect(stackTrace, same(trace));
      }
    },
  );
}
