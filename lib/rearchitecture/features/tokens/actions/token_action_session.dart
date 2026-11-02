import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/token_metadata.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Action modes share one retained form. Flags only describe existing metadata.
enum TokenActionMode {
  /// Mint to an exact beneficiary.
  mint,

  /// Burn the selected account's own units.
  burn,

  /// Transfer ownership while preserving the freshly read flags.
  transfer,

  /// Read the contract's existing flags.
  flags,
}

/// Original transports and builders, injectable without a wallet or a socket.
class TokenActionSession {
  /// Every dependency belongs to the same account and signing chain.
  TokenActionSession({
    required this.address,
    required this.chainId,
    required this._isCurrent,
    required this.readToken,
    required this.readAccount,
    required this.mintBlock,
    required this.burnBlock,
    required this.transferBlock,
  });

  /// Captures the real session before any question or asynchronous proof.
  factory TokenActionSession.wallet(WalletActionContext action) {
    final TokenApi tokens = action.client.embedded.token;
    final LedgerApi ledger = action.client.ledger;
    return TokenActionSession.boundApis(
      address: action.ownerAddress,
      chainId: getChainIdentifier(),
      tokenSource: tokens,
      ledgerSource: ledger,
      isCurrent: () =>
          action.isCurrent &&
          identical(tokens, action.client.embedded.token) &&
          identical(ledger, action.client.ledger),
    );
  }

  /// Shared SDK API objects may be rebound while an RPC is pending.
  factory TokenActionSession.boundApis({
    required String address,
    required int chainId,
    required TokenApi tokenSource,
    required LedgerApi ledgerSource,
    required bool Function() isCurrent,
  }) {
    final Client tokenClient = tokenSource.client;
    final Client ledgerClient = ledgerSource.client;
    final String? tokenUrl = tokenClient is WsClient ? tokenClient.url : null;
    final String? ledgerUrl = ledgerClient is WsClient
        ? ledgerClient.url
        : null;
    final TokenApi tokens = TokenApi()..setClient(tokenClient);
    final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
    final Address owner = Address.parse(address);
    late final TokenActionSession session;
    void requireCurrent() => session.requireCurrent();
    return session = TokenActionSession(
      address: address,
      chainId: chainId,
      isCurrent: () =>
          isCurrent() &&
          identical(tokenClient, tokenSource.client) &&
          identical(ledgerClient, ledgerSource.client) &&
          (tokenClient is! WsClient || tokenClient.url == tokenUrl) &&
          (ledgerClient is! WsClient || ledgerClient.url == ledgerUrl),
      readToken: (TokenStandard standard) {
        requireCurrent();
        return tokens.getByZts(standard);
      },
      readAccount: () {
        requireCurrent();
        return ledger.getAccountInfoByAddress(owner);
      },
      mintBlock: (TokenStandard standard, BigInt amount, Address receiver) {
        requireCurrent();
        return tokens.mintToken(standard, amount, receiver);
      },
      burnBlock: (TokenStandard standard, BigInt amount) {
        requireCurrent();
        return tokens.burnToken(standard, amount);
      },
      transferBlock: (Token token, Address receiver) {
        requireCurrent();
        return tokens.updateToken(
          token.tokenStandard,
          receiver,
          token.isMintable,
          token.isBurnable,
        );
      },
    );
  }

  /// The selected account captured before reading.
  final String address;

  /// The original signing chain.
  final int chainId;
  final bool Function() _isCurrent;

  /// Exact getByZts, never a name, symbol, catalog hit or fuzzy match.
  final Future<Token?> Function(TokenStandard standard) readToken;

  /// One complete account response from the original ledger transport.
  final Future<AccountInfo> Function() readAccount;

  /// The existing SDK mint builder.
  final AccountBlockTemplate Function(
    TokenStandard standard,
    BigInt amount,
    Address receiver,
  )
  mintBlock;

  /// The existing SDK burn builder.
  final AccountBlockTemplate Function(TokenStandard standard, BigInt amount)
  burnBlock;

  /// The existing ownership update preserves the token's read flags.
  final AccountBlockTemplate Function(Token token, Address receiver)
  transferBlock;

  bool _revoked = false;

  /// Returning to a previously observed context cannot restore its authority.
  bool get isCurrent => !_revoked && !(_revoked = !_isCurrent());

  /// Refuses before reading, building or preparing a publication.
  void requireCurrent() {
    if (!isCurrent) throw const TokenActionRefused();
  }

  /// Both successful reads must belong to this original session.
  Future<TokenActionProof> prove(TokenStandard standard) async {
    requireCurrent();
    final String wanted = standard.toString();
    final TokenStandard requested = TokenStandard.parse(wanted);
    final Token? response = await readToken(requested);
    requireCurrent();
    if (response == null || response.tokenStandard.toString() != wanted) {
      throw const TokenActionRefused();
    }
    requireValidTokenMetadata(response);
    final Token token = Token.fromJson(response.toJson());
    final AccountInfo account = await readAccount();
    requireCurrent();
    final TokenBalanceSnapshot balances = TokenBalanceSnapshot.fromAccount(
      account,
      address,
    );
    // Conflicting metadata in the account cannot authorize a token action.
    for (final BalanceInfoListItem entry in account.balanceInfoList!) {
      if (entry.token!.tokenStandard.toString() == wanted &&
          !sameTokenActionMetadata(token, entry.token!)) {
        throw const TokenActionRefused();
      }
    }
    return TokenActionProof._(this, token, balances.unitsFor(requested));
  }
}

/// Complete read authority. SDK models returned to callers are independent.
class TokenActionProof {
  TokenActionProof._(this.session, Token token, this.balance)
    : _token = Map<String, dynamic>.unmodifiable(token.toJson());

  /// The account and original transports that produced this read.
  final TokenActionSession session;
  final Map<String, dynamic> _token;

  /// An identity unique to this complete successful read.
  final Object ticket = Object();

  /// Exact nonnegative smallest units from a complete selected account.
  final BigInt balance;

  /// Mutable SDK copies cannot rewrite the proof.
  Token get token => Token.fromJson(Map<String, dynamic>.of(_token));

  /// A proof cannot outlive its original transport and wallet context.
  bool get isCurrent => session.isCurrent;

  /// Permission uses the selected account, never another wallet address.
  bool permits(TokenActionMode mode) {
    if (!isCurrent) return false;
    final Token value = token;
    final bool owner = value.owner.toString() == session.address;
    return switch (mode) {
      TokenActionMode.mint =>
        owner && value.isMintable && value.totalSupply < value.maxSupply,
      TokenActionMode.burn =>
        (owner || value.isBurnable) && balance > BigInt.zero,
      TokenActionMode.transfer => owner,
      TokenActionMode.flags => true,
    };
  }
}

/// A known refusal before sender admission, not a claim about an RPC failure.
class TokenActionRefused implements Exception {
  /// Contains no wallet or transport details.
  const TokenActionRefused();
}

/// A changed total may still fit an intent; every other confirmed fact agrees.
bool sameTokenActionMetadata(Token a, Token b, {bool includeSupply = true}) =>
    a.tokenStandard == b.tokenStandard &&
    a.owner == b.owner &&
    a.name == b.name &&
    a.symbol == b.symbol &&
    a.domain == b.domain &&
    a.decimals == b.decimals &&
    a.maxSupply == b.maxSupply &&
    a.isMintable == b.isMintable &&
    a.isBurnable == b.isBurnable &&
    a.isUtility == b.isUtility &&
    (!includeSupply || a.totalSupply == b.totalSupply);

/// Raw decimal input becomes integer units without a float or truncation.
BigInt? parseTokenActionAmount(String text, int decimals) {
  if (decimals < 0 ||
      decimals > 255 ||
      text.length > decimals + 79 ||
      !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(text)) {
    return null;
  }
  final List<String> parts = text.split('.');
  final String fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  final BigInt units = BigInt.parse(
    '${parts[0]}${fraction.padRight(decimals, '0')}',
  );
  return units.bitLength <= 256 ? units : null;
}
