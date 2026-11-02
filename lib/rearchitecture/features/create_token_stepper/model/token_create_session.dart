import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The original owner and independent readers of one token registration.
class TokenCreateSession {
  /// Fixtures supply readers and authority without opening a wallet or socket.
  TokenCreateSession({
    required this.owner,
    required this.chainId,
    required this._isCurrent,
    required this.readAccount,
    required this.readPlasma,
  });

  /// Captures every mutable SDK identity before the first read can yield.
  factory TokenCreateSession.wallet(RegistrationConfirmation confirmation) {
    final WalletActionContext action = confirmation.context!;
    final Zenon client = action.client;
    final EmbeddedApi embedded = client.embedded;
    final TokenApi token = embedded.token;
    final PlasmaApi plasma = embedded.plasma;
    final LedgerApi ledger = client.ledger;
    return TokenCreateSession.boundApis(
      owner: action.ownerAddress,
      chainId: confirmation.chainId,
      plasmaSource: plasma,
      ledgerSource: ledger,
      tokenSource: token,
      isCurrent: () =>
          confirmation.isCurrent &&
          identical(action.client, client) &&
          identical(client.embedded, embedded) &&
          identical(embedded.token, token) &&
          identical(embedded.plasma, plasma) &&
          identical(client.ledger, ledger),
    );
  }

  /// The shared SDK APIs can be rebound while an older RPC is still pending.
  factory TokenCreateSession.boundApis({
    required String owner,
    required int chainId,
    required PlasmaApi plasmaSource,
    required LedgerApi ledgerSource,
    required bool Function() isCurrent,
    TokenApi? tokenSource,
  }) {
    final Address address = Address.parse(owner);
    final Client plasmaClient = plasmaSource.client;
    final Client ledgerClient = ledgerSource.client;
    final Client? tokenClient = tokenSource?.client;
    final String? plasmaUrl = _url(plasmaClient);
    final String? ledgerUrl = _url(ledgerClient);
    final String? tokenUrl = _url(tokenClient);
    final PlasmaApi plasma = PlasmaApi()..setClient(plasmaClient);
    final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
    late final TokenCreateSession session;
    void requireCurrent() {
      if (!session.isCurrent) throw StateError('Token context changed');
    }

    return session = TokenCreateSession(
      owner: owner,
      chainId: chainId,
      isCurrent: () =>
          isCurrent() &&
          identical(plasmaSource.client, plasmaClient) &&
          identical(ledgerSource.client, ledgerClient) &&
          (tokenSource == null || identical(tokenSource.client, tokenClient)) &&
          _url(plasmaClient) == plasmaUrl &&
          _url(ledgerClient) == ledgerUrl &&
          _url(tokenClient) == tokenUrl,
      readAccount: () {
        requireCurrent();
        return ledger.getAccountInfoByAddress(address);
      },
      readPlasma: () {
        requireCurrent();
        return plasma.get(address);
      },
    );
  }

  static String? _url(Client? client) => client is WsClient ? client.url : null;

  /// The immutable original account.
  final String owner;

  /// The immutable original signing chain.
  final int chainId;
  final bool Function() _isCurrent;

  /// A complete account response is required to establish a fee balance.
  final Future<AccountInfo> Function() readAccount;

  /// Plasma belongs to the original account and transport.
  final Future<PlasmaInfo> Function() readPlasma;
  bool _revoked = false;

  /// Observed revocation cannot recover by returning to an earlier identity.
  bool get isCurrent => !_revoked && !(_revoked = !_isCurrent());
}

/// A missing, partial, foreign or malformed response never means zero ZNN.
BigInt? tokenCreateZnnBalance(AccountInfo account, String owner) {
  try {
    return TokenBalanceSnapshot.fromAccount(account, owner).unitsFor(znnZts);
  } on Object {
    // Partial balances and inconsistent metadata cannot establish admission.
    return null;
  }
}
