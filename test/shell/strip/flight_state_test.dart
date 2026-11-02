import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

final Hash _hash = Hash.parse('ab' * 32);
final Hash _other = Hash.parse('cd' * 32);

void main() {
  test(
    'keeps exact hashes, amounts and unknown units without duplicate records',
    () {
      final InFlightBlocks blocks = InFlightBlocks(lookup: (_) async => false);
      addTearDown(blocks.dispose);
      final BigInt exact = BigInt.parse('123456789012345678901234567890');
      int changes = 0;
      blocks
        ..addListener(() {
          changes++;
        })
        ..sent(hash: _hash, amount: exact)
        ..sent(hash: _hash, amount: BigInt.one, decimals: 8, symbol: 'ZNN');
      expect(changes, 1);
      expect(blocks.value.single.hash, _hash);
      expect(blocks.value.single.amount, exact);
      expect(blocks.value.single.decimals, isNull);
      expect(blocks.value.single.symbol, isNull);
      expect(() => blocks.value.clear(), throwsUnsupportedError);
    },
  );

  test(
    'only exact confirmation settles; errors and missing results '
    'retain records',
    () async {
      bool failed = true;
      final List<Hash> requested = <Hash>[];
      final InFlightBlocks blocks = InFlightBlocks(
        lookup: (Hash hash) async {
          requested.add(hash);
          if (failed) throw StateError('node unavailable');
          return hash == _hash;
        },
      );
      addTearDown(blocks.dispose);
      blocks
        ..sent(hash: _hash, amount: BigInt.zero)
        ..sent(hash: _other, amount: BigInt.one);
      await blocks.check();
      expect(blocks.value, hasLength(2));
      failed = false;
      await blocks.check();
      expect(blocks.value.single.hash, _other);
      expect(requested, <Hash>[_hash, _other, _hash, _other]);
    },
  );

  test('coalesces checks while a confirmation request is pending', () async {
    final Completer<bool> answer = Completer<bool>();
    int lookups = 0;
    final InFlightBlocks blocks = InFlightBlocks(
      lookup: (_) {
        lookups++;
        return answer.future;
      },
    );
    addTearDown(blocks.dispose);
    blocks.sent(hash: _hash, amount: BigInt.zero);
    final Future<void> first = blocks.check();
    await blocks.check();
    expect(lookups, 1);
    answer.complete(false);
    await first;
    expect(blocks.value.single.hash, _hash);
  });

  test(
    'old epoch confirmation cannot settle an equal hash in a new session',
    () async {
      final List<Completer<bool>> answers = <Completer<bool>>[
        Completer<bool>(),
        Completer<bool>(),
      ];
      int requests = 0;
      final InFlightBlocks blocks = InFlightBlocks(
        lookup: (_) => answers[requests++].future,
      );
      addTearDown(blocks.dispose);
      blocks.sent(hash: _hash, amount: BigInt.one);
      final Future<void> old = blocks.check();
      blocks
        ..clear()
        ..sent(hash: _hash, amount: BigInt.from(2));
      final Future<void> current = blocks.check();
      expect(requests, 2);
      answers[0].complete(true);
      await old;
      expect(blocks.value.single.amount, BigInt.from(2));
      answers[1].complete(false);
      await current;
      expect(blocks.value.single.hash, _hash);
    },
  );

  test('late confirmation after dispose cannot notify listeners', () async {
    final Completer<bool> result = Completer<bool>();
    final InFlightBlocks blocks = InFlightBlocks(lookup: (_) => result.future)
      ..sent(hash: _hash, amount: BigInt.one);
    int changes = 0;
    blocks.addListener(() {
      changes++;
    });
    final Future<void> pending = blocks.check();
    blocks.dispose();
    result.complete(true);
    await pending;
    expect(changes, 0);
  });

  for (final bool dark in <bool>[true, false]) {
    testWidgets(
      'unknown units and zero contract amounts stay generic '
      'in ${dark ? 'dark' : 'light'}',
      (WidgetTester tester) async {
        final InFlightBlocks blocks = InFlightBlocks(
          lookup: (_) async => false,
        );
        addTearDown(blocks.dispose);
        Future<void> show({
          required BigInt amount,
          int? decimals,
          String? symbol,
        }) async {
          blocks
            ..clear()
            ..sent(
              hash: _hash,
              amount: amount,
              decimals: decimals,
              symbol: symbol,
            );
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SizedBox(width: 700, child: FlightChip(blocks: blocks)),
              ),
            ),
          );
          await tester.pump();
        }

        for (final (BigInt, int?, String?) record in <(BigInt, int?, String?)>[
          (BigInt.zero, 8, 'ZNN'),
          (BigInt.from(123), null, null),
          (BigInt.one, 8, null),
          (BigInt.one, null, 'ZNN'),
          (BigInt.one, -1, 'ZNN'),
          (BigInt.one, 1 << 30, 'ZNN'),
          (BigInt.one, 8, ' '),
        ]) {
          await show(amount: record.$1, decimals: record.$2, symbol: record.$3);
          expect(
            find.text('Waiting for a momentum', findRichText: true),
            findsOneWidget,
          );
          expect(find.textContaining('ZNN', findRichText: true), findsNothing);
          expect(
            find.textContaining('0 ZNN', findRichText: true),
            findsNothing,
          );
          expect(blocks.value.single.hash, _hash);
          expect(blocks.value.single.amount, record.$1);
        }
        await show(amount: BigInt.from(1250000000), decimals: 8, symbol: 'ZNN');
        expect(find.text('12.5 ZNN'), findsOneWidget);
        expect(
          find.textContaining('waiting for a momentum', findRichText: true),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
