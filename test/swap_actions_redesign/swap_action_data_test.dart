import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  test('amounts preserve exact base units beyond double precision', () {
    final BigInt value = BigInt.parse('900719925474099312345678');
    expect(swapAmount('9007199254740993.12345678', 8), value);
    expect(swapAmountInput(value, 8), '9007199254740993.12345678');
    expect(swapAmountInput(BigInt.from(100000000), 8), '1');
    expect(swapAmount('0', 0), BigInt.zero);
  });

  test('malformed, excessive and truncated precision never become amounts', () {
    for (final String input in <String>[
      '',
      '-1',
      '+1',
      '1e2',
      '01',
      '1,2',
      ' 1',
      '1.',
      '.1',
      '1.001',
    ]) {
      expect(swapAmount(input, 2), isNull);
    }
    expect(swapAmount('1', -1), isNull);
    expect(swapAmount('1', 256), isNull);
    expect(swapAmount(List<String>.filled(1025, '1').join(), 8), isNull);
  });

  test(
    'counterparty excludes every captured member and IDs exclude empty hash',
    () {
      final SwapUiFixture fixture = SwapUiFixture();
      expect(swapCounterparty(fixture.owner, fixture.origin.members), isFalse);
      expect(swapCounterparty(fixture.member, fixture.origin.members), isFalse);
      expect(
        swapCounterparty(fixture.counterparty, fixture.origin.members),
        isTrue,
      );
      expect(
        swapCounterparty('fixture-invalid', fixture.origin.members),
        isFalse,
      );
      expect(swapDepositId(emptyHash.toString()), isNull);
      expect(swapDepositId(fixtureHash(1))?.toString(), fixtureHash(1));
      expect(swapDepositId('fixture-invalid'), isNull);
    },
  );

  test(
    'funds retain one original account read and copied token metadata',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      final Completer<AccountInfo> original = Completer<AccountInfo>();
      fixture.accountReply = original.future;
      final Future<SwapFunds> pending = SwapFunds.read(
        fixture.origin,
        fixture.owner,
      );
      fixture.accountReply = Future<AccountInfo>.value(
        fixture.account(fixture.member),
      );
      original.complete(fixture.account(fixture.owner));
      final SwapFunds result = await pending;
      expect(result.address, fixture.owner);
      expect(result.balance(kZnnCoin), fixture.available);
      expect(identical(result.tokens.first, kZnnCoin), isFalse);
      expect(fixture.accountReads, <String>[fixture.owner]);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'a departed original account read cannot authorize replacement funds',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      final Completer<AccountInfo> original = Completer<AccountInfo>();
      fixture.accountReply = original.future;
      final Future<SwapFunds> pending = SwapFunds.read(
        fixture.origin,
        fixture.owner,
      );
      final Future<void> rejected = expectLater(
        pending,
        throwsA(isA<SwapActionRefused>()),
      );
      fixture.current = false;
      original.complete(fixture.account(fixture.owner));
      await rejected;
      fixture.current = true;
      expect(fixture.origin.isCurrent, isFalse);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'incomplete, negative, duplicate and foreign accounts stay unspendable',
    () async {
      for (final AccountInfo invalid in <AccountInfo>[
        AccountInfo(address: fixtureAddress(1), blockCount: 0),
        AccountInfo(
          address: fixtureAddress(1),
          blockCount: -1,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
        AccountInfo(
          address: fixtureAddress(2),
          blockCount: 0,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
        AccountInfo(
          address: fixtureAddress(1),
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: kZnnCoin, balance: -BigInt.one),
          ],
        ),
        AccountInfo(
          address: fixtureAddress(1),
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: kZnnCoin, balance: BigInt.one),
            BalanceInfoListItem(token: kZnnCoin, balance: BigInt.one),
          ],
        ),
      ]) {
        final SwapUiFixture fixture = SwapUiFixture()
          ..accountReply = Future<AccountInfo>.value(invalid);
        await expectLater(
          SwapFunds.read(fixture.origin, fixture.owner),
          throwsA(isA<SwapActionRefused>()),
        );
        expect(fixture.mutations, 0);
      }
    },
  );

  test(
    'original action Future and exact accepted answer are retained',
    () async {
      final Completer<SwapActionResult> original =
          Completer<SwapActionResult>();
      final SwapUiRun run = SwapUiRun(() => original.future);
      final SwapActionResult result = SwapActionResult(
        status: SwapActionStatus.submitted,
      );
      expect(identical(run.original, original.future), isTrue);
      expect(identical(run.completion, run.completion), isTrue);
      original.complete(result);
      expect(identical(await run.completion, result), isTrue);
      expect(identical(run.result, result), isTrue);
    },
  );

  test(
    'an exceptional original is held unknown without recreating it',
    () async {
      int calls = 0;
      final Object failure = StateError('Synthetic failure');
      final SwapUiRun run = SwapUiRun(() {
        calls++;
        return Future<SwapActionResult>.error(failure);
      });
      final SwapActionResult result = await run.completion;
      expect(result.status, SwapActionStatus.unknown);
      expect(identical(result.error, failure), isTrue);
      expect(calls, 1);
      await run.completion;
      expect(calls, 1);
    },
  );

  test(
    'record copies survive caller mutation without a terminal chain claim',
    () {
      final SwapUiFixture fixture = SwapUiFixture();
      final HtlcSwap record = HtlcSwap(
        id: fixtureHash(1),
        chainId: 321,
        type: P2pSwapType.native,
        direction: P2pSwapDirection.outgoing,
        selfAddress: fixture.owner,
        counterpartyAddress: fixture.counterparty,
        fromAmount: BigInt.one,
        fromTokenStandard: kZnnCoin.tokenStandard.toString(),
        fromSymbol: kZnnCoin.symbol,
        fromDecimals: kZnnCoin.decimals,
        fromChain: P2pSwapChain.nom,
        toChain: P2pSwapChain.nom,
        startTime: 100,
        state: P2pSwapState.completed,
        hashLock: fixtureHash(2),
        hashType: htlcHashTypeSha3,
        initialHtlcId: fixtureHash(1),
        initialHtlcExpirationTime: 10000,
      );
      fixture.records = <HtlcSwap>[record];
      final HtlcSwap copied = swapOriginalRecord(
        fixture.origin,
        fixtureHash(1),
      );
      record.toAmount = BigInt.from(999);
      expect(copied.toAmount, isNull);
      expect(identical(record, copied), isFalse);
      expect(fixture.depositReads, 0);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'completed local history and an absent deposit '
    'grant no live or expiry proof',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      fixture.records = <HtlcSwap>[
        fixtureRecord(fixture, state: P2pSwapState.completed),
      ];
      final SwapDetailRead result = await SwapDetailRead.read(
        fixture.origin,
        fixtureHash(1),
      );
      expect(result.own, isNull);
      expect(result.other, isNull);
      expect(result.ownMatches, isFalse);
      expect(result.otherMatches, isFalse);
      expect(fixture.depositReads, 1);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'expiry is a positive original chain-time fact and never a local timer',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      fixture.htlcReply = (_) async => fixtureDeposit(fixture, expires: 1001);
      final SwapDepositFact live = await SwapDepositFact.read(
        fixture.origin,
        Hash.parse(fixtureHash(1)),
      );
      expect(live.expired, isFalse);
      fixture.now = 1001;
      expect(live.expired, isFalse);
      final SwapDepositFact expired = await SwapDepositFact.read(
        fixture.origin,
        Hash.parse(fixtureHash(1)),
      );
      expect(expired.expired, isTrue);
      expect(fixture.clockReads, 2);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'a different returned deposit ID refuses before token or time reads',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      fixture.htlcReply = (_) async => fixtureDeposit(fixture, id: 2);
      await expectLater(
        SwapDepositFact.read(fixture.origin, Hash.parse(fixtureHash(1))),
        throwsA(isA<SwapActionRefused>()),
      );
      expect(fixture.tokenReads, 0);
      expect(fixture.clockReads, 0);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'required original deposit fields are copied before the pending response',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      final HtlcInfo original = fixtureDeposit(fixture);
      final HtlcInfo expected = HtlcInfo.fromJson(original.toJson());
      final Completer<HtlcInfo> reply = Completer<HtlcInfo>();
      fixture.htlcReply = (_) => reply.future;
      final Future<SwapDepositFact> pending = SwapDepositFact.read(
        fixture.origin,
        Hash.parse(fixtureHash(1)),
        exact: expected,
      );
      expected.amount = BigInt.one;
      reply.complete(original);
      expect((await pending).amount, BigInt.from(10000000000));
      expect(fixture.mutations, 0);
    },
  );

  test(
    'source departure during token metadata '
    'cannot become a current deposit fact',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      final Completer<Token?> token = Completer<Token?>();
      fixture.htlcReply = (_) async => fixtureDeposit(fixture);
      fixture.tokenReply = token.future;
      final Future<SwapDepositFact> pending = SwapDepositFact.read(
        fixture.origin,
        Hash.parse(fixtureHash(1)),
      );
      final Future<void> refusal = expectLater(
        pending,
        throwsA(isA<SwapActionRefused>()),
      );
      for (int i = 0; i < 4; i++) {
        await Future<void>.value();
      }
      expect(fixture.tokenReads, 1);
      fixture.current = false;
      token.complete(kZnnCoin);
      await refusal;
      expect(fixture.clockReads, 0);
      expect(fixture.mutations, 0);
    },
  );

  test(
    'live comparisons use the exact record copied before metadata awaits',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      final HtlcSwap record = fixtureRecord(fixture)
        ..counterHtlcId = fixtureHash(2)
        ..counterHtlcExpirationTime = 5000
        ..toAmount = BigInt.from(100000000000)
        ..toTokenStandard = kQsrCoin.tokenStandard.toString()
        ..toSymbol = kQsrCoin.symbol
        ..toDecimals = kQsrCoin.decimals;
      fixture.records = <HtlcSwap>[record];
      fixture.htlcReply = (String id) async =>
          fixtureDeposit(fixture, own: id == fixtureHash(1));
      final Future<SwapDetailRead> pending = SwapDetailRead.read(
        fixture.origin,
        record.id,
      );
      record.toAmount = BigInt.one;
      final SwapDetailRead result = await pending;
      expect(result.ownMatches, isTrue);
      expect(result.otherMatches, isTrue);
      expect(result.original.toAmount, BigInt.from(100000000000));
      expect(fixture.mutations, 0);
    },
  );

  test(
    'a live counter deposit does not invent missing recorded counter terms',
    () async {
      final SwapUiFixture fixture = SwapUiFixture();
      final HtlcSwap record = fixtureRecord(fixture)
        ..counterHtlcId = fixtureHash(2)
        ..counterHtlcExpirationTime = 5000
        ..toTokenStandard = kQsrCoin.tokenStandard.toString()
        ..toSymbol = kQsrCoin.symbol
        ..toDecimals = kQsrCoin.decimals;
      fixture.records = <HtlcSwap>[record];
      fixture.htlcReply = (String id) async =>
          fixtureDeposit(fixture, own: id == fixtureHash(1));
      final SwapDetailRead result = await SwapDetailRead.read(
        fixture.origin,
        record.id,
      );
      expect(result.other?.amount, BigInt.from(100000000000));
      expect(result.original.toAmount, isNull);
      expect(result.otherMatches, isFalse);
      expect(fixture.mutations, 0);
    },
  );
}
