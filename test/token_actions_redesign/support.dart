import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String actionHash(int value) => value.toRadixString(16).padLeft(64, '0');

Token actionToken({
  Address? owner,
  bool burnable = true,
  bool mintable = true,
  int decimals = 8,
  BigInt? supply,
  int id = 1,
}) => Token(
  'Action token $id',
  'ACT',
  'example.invalid',
  supply ?? BigInt.parse('1000000000000000000000000000000'),
  decimals,
  owner ?? emptyAddress,
  TokenStandard.fromBytes(<int>[id, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  BigInt.parse('10000000000000000000000000000000'),
  burnable,
  mintable,
  true,
);

class ActionCall {
  ActionCall(this.block, this.owner, this.guard);
  final AccountBlockTemplate block;
  final Address? owner;
  final bool Function()? guard;
}

/// In-memory preparation and response only. No signer or node is constructed.
class ActionTransport extends AccountBlockUtils {
  final List<ActionCall> calls = <ActionCall>[];
  final List<(ActionCall, Completer<AccountBlockTemplate>)> pending =
      <(ActionCall, Completer<AccountBlockTemplate>)>[];
  Completer<void>? preparation;
  bool deferred = false;
  Object? error;
  AccountBlockTemplate Function(ActionCall call)? reply;
  int published = 0;

  AccountBlockTemplate accepted(ActionCall call) =>
      AccountBlockTemplate.fromJson(call.block.toJson())
        ..address = call.owner ?? emptyAddress
        ..hash = Hash.parse(actionHash(100 + calls.indexOf(call)));

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purpose, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) async {
    final ActionCall call = ActionCall(transactionParams, address, canPublish);
    calls.add(call);
    final Completer<void>? gate = preparation;
    if (gate != null) await gate.future;
    if (!(canPublish?.call() ?? true)) {
      throw StateError('Synthetic preparation revoked');
    }
    published++;
    final Object? failure = error;
    if (failure != null) Error.throwWithStackTrace(failure, StackTrace.current);
    if (!deferred) return reply?.call(call) ?? accepted(call);
    final Completer<AccountBlockTemplate> completion =
        Completer<AccountBlockTemplate>();
    pending.add((call, completion));
    return completion.future;
  }

  void complete({AccountBlockTemplate? block, Object? failure}) {
    final (ActionCall call, Completer<AccountBlockTemplate> reply) = pending
        .removeAt(0);
    if (failure != null) {
      reply.completeError(failure, StackTrace.current);
    } else {
      reply.complete(block ?? accepted(call));
    }
  }

  void release() {
    final Completer<void>? gate = preparation;
    if (gate != null && !gate.isCompleted) gate.complete();
    while (pending.isNotEmpty) {
      complete();
    }
  }
}

class _Balances extends ZenonAddressUtils {
  @override
  void refreshBalance() {}
}

/// Exercises synchronous delivery and diagnostic failures on one adapter only.
class ActionTerminalObserver<T extends Object> extends BlocObserver {
  ActionTerminalObserver({required this.target, required this.terminal});

  final bool Function(BlocBase<dynamic>) target;
  final bool Function(T) terminal;
  final StateError displayError = StateError('Synthetic terminal observer');
  final StateError diagnosticError = StateError(
    'Synthetic diagnostic observer',
  );
  final List<T> attempted = <T>[];
  final List<Object> reported = <Object>[];

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    final dynamic next = change.nextState;
    if (target(bloc) && next is T && terminal(next)) {
      attempted.add(next);
      throw displayError;
    }
    super.onChange(bloc, change);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    if (target(bloc)) {
      reported.add(error);
      throw diagnosticError;
    }
    super.onError(bloc, error, stackTrace);
  }
}

class ActionFixture {
  ActionFixture({Token? initialToken, String? ownerAddress}) {
    token = initialToken ?? actionToken();
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: transport,
      zenonAddressUtils: _Balances(),
      recordRecipient: (_, _) async {},
    );
    session = TokenActionSession(
      address: ownerAddress ?? emptyAddress.toString(),
      chainId: 321,
      isCurrent: () => active,
      readToken: (TokenStandard standard) async {
        tokenReads++;
        return tokenRead == null
            ? Token.fromJson(token.toJson())
            : await tokenRead!(standard);
      },
      readAccount: () async {
        accountReads++;
        return accountRead == null ? account() : await accountRead!();
      },
      mintBlock: (TokenStandard standard, BigInt amount, Address receiver) {
        mints.add((standard.toString(), amount, receiver.toString()));
        return block(<int>[
          1,
          ...amount.toString().codeUnits,
          ...receiver.getBytes()!,
        ]);
      },
      burnBlock: (TokenStandard standard, BigInt amount) {
        burns.add((standard.toString(), amount));
        return block(
          <int>[2, ...amount.toString().codeUnits],
          amount: amount,
          standard: standard,
        );
      },
      transferBlock: (Token token, Address receiver) {
        transfers.add((
          token.isMintable,
          token.isBurnable,
          receiver.toString(),
        ));
        return block(<int>[
          3,
          if (token.isMintable) 1 else 0,
          if (token.isBurnable) 1 else 0,
          ...receiver.getBytes()!,
        ]);
      },
    );
    publisher = reopenPublisher();
  }

  final ActionTransport transport = ActionTransport();
  late final SendTransactionBloc sender;
  late final TokenActionSession session;
  late final TokenActionPublisher publisher;
  final InFlightBlocks flights = InFlightBlocks(lookup: (_) async => false);
  late Token token;
  BigInt balance = BigInt.parse('900719925474099312345');
  bool active = true;
  bool visible = true;
  int tokenReads = 0;
  int accountReads = 0;
  Future<Token?> Function(TokenStandard)? tokenRead;
  Future<AccountInfo> Function()? accountRead;
  final List<(String, BigInt, String)> mints = <(String, BigInt, String)>[];
  final List<(String, BigInt)> burns = <(String, BigInt)>[];
  final List<(bool, bool, String)> transfers = <(bool, bool, String)>[];

  TokenActionPublisher reopenPublisher() => TokenActionPublisher(
    sender: sender,
    session: session,
    confirmationChanges: flights,
    hasConfirmedOriginal:
        ({
          required String hash,
          required String owner,
          required int chainId,
        }) =>
            owner == session.address &&
            chainId == session.chainId &&
            flights.hasConfirmed(Hash.parse(hash)),
  );

  void confirm(TokenActionOutcome original) {
    final Hash hash = Hash.parse(original.publicationHash!);
    flights
      ..sent(hash: hash, amount: original.intent.amount)
      ..settle(hash);
  }

  AccountInfo account() => AccountInfo(
    address: session.address,
    blockCount: 1,
    balanceInfoList: <BalanceInfoListItem>[
      BalanceInfoListItem(
        token: Token.fromJson(token.toJson()),
        balance: balance,
      ),
    ],
  );

  AccountBlockTemplate block(
    List<int> data, {
    BigInt? amount,
    TokenStandard? standard,
  }) => AccountBlockTemplate.callContract(
    tokenAddress,
    standard ?? znnZts,
    amount ?? BigInt.zero,
    data,
  )..chainIdentifier = 321;

  Future<TokenActionIntent> intent({
    TokenActionMode mode = TokenActionMode.mint,
    BigInt? amount,
    String? receiver,
  }) async => TokenActionIntent(
    proof: await publisher.read(token.tokenStandard),
    mode: mode,
    amount:
        amount ?? (mode == TokenActionMode.transfer ? BigInt.zero : BigInt.one),
    receiver: mode == TokenActionMode.burn || mode == TokenActionMode.flags
        ? null
        : receiver ?? emptyAddress.toString(),
    isCurrent: () => visible,
  );

  Future<void> close() async {
    transport.release();
    await sender.close();
    flights.dispose();
  }
}

/// Bounded logical observation on the owning clock, without unbounded settle.
Future<void> actionTurnsUntil(bool Function() done) async {
  for (int turn = 0; turn < 100 && !done(); turn++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    done(),
    isTrue,
    reason: 'Synthetic operation did not reach its finite boundary',
  );
}

Future<void> pumpActionUntil(WidgetTester tester, bool Function() done) async {
  for (int turn = 0; turn < 100 && !done(); turn++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(
    done(),
    isTrue,
    reason: 'Synthetic operation did not reach its widget-clock boundary',
  );
}
