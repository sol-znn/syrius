import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_preflight.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_session.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// In-memory readers only. No wallet, session capture, signer or node exists.
class TokenCreateFixture {
  TokenCreateFixture() {
    final int captured = authority.value;
    session = TokenCreateSession(
      owner: emptyAddress.toString(),
      chainId: 321,
      isCurrent: () => authority.value == captured,
      readAccount: () {
        accountReads++;
        return accountRead?.call() ?? Future<AccountInfo>.value(account);
      },
      readPlasma: () {
        plasmaReads++;
        return plasmaRead?.call() ?? Future<PlasmaInfo>.value(plasma);
      },
    );
    preflight = TokenCreatePreflight(session: session, authority: authority);
  }

  final ValueNotifier<int> authority = ValueNotifier<int>(0);
  late final TokenCreateSession session;
  late final TokenCreatePreflight preflight;
  int accountReads = 0;
  int plasmaReads = 0;
  Future<AccountInfo> Function()? accountRead;
  Future<PlasmaInfo> Function()? plasmaRead;
  AccountInfo account = tokenCreateAccount();
  PlasmaInfo plasma = tokenCreatePlasma();
  bool _disposed = false;

  void revoke() => authority.value++;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    preflight.dispose();
    authority.dispose();
  }
}

AccountInfo tokenCreateAccount({BigInt? balance, String? owner}) => AccountInfo(
  address: owner ?? emptyAddress.toString(),
  blockCount: 1,
  balanceInfoList: <BalanceInfoListItem>[
    BalanceInfoListItem(
      token: kZnnCoin,
      balance: balance ?? tokenZtsIssueFeeInZnn * BigInt.from(2000),
    ),
  ],
);

PlasmaInfo tokenCreatePlasma([int amount = kIssueTokenPlasmaAmountNeeded]) =>
    PlasmaInfo(
      currentPlasma: amount,
      maxPlasma: amount,
      qsrAmount: BigInt.zero,
    );

class TokenCreateTransportCall {
  TokenCreateTransportCall(this.block, this.predicate);
  final AccountBlockTemplate block;
  final bool Function()? predicate;
}

/// Returns one original Future so forwarding identity is directly observable.
class TokenCreateTransport extends AccountBlockUtils {
  final List<TokenCreateTransportCall> calls = <TokenCreateTransportCall>[];
  final Completer<AccountBlockTemplate> response =
      Completer<AccountBlockTemplate>();

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purpose, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) {
    calls.add(TokenCreateTransportCall(transactionParams, canPublish));
    return response.future;
  }
}
