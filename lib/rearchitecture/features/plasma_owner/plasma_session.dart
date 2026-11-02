import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The original account, transport and authority for a Plasma operation.
/// Dependencies are explicit so source tests never open a wallet or a socket.
class PlasmaSession {
  /// All reads and builders belong to the same captured owner and chain.
  PlasmaSession({
    required this.address,
    required this.chainId,
    required this._isCurrent,
    required this.readEntries,
    required this.readFrontier,
    required this.readAccount,
    required this.cancelBlock,
    required this.fuseBlock,
    this.confirmationChanges,
    this._confirmed,
  });

  /// Capture [action] before showing a question or yielding from a form.
  factory PlasmaSession.wallet(WalletActionContext action) {
    final PlasmaApi plasmaSource = action.client.embedded.plasma;
    final LedgerApi ledgerSource = action.client.ledger;
    final int chainId = getChainIdentifier();
    final List<String> addresses = List<String>.unmodifiable(
      kDefaultAddressList.whereType<String>(),
    );
    final InFlightBlocks flight = WalletFlightRegistry.instance.forWallet(
      chainId,
      addresses,
    );
    return PlasmaSession.boundApis(
      address: action.ownerAddress,
      chainId: chainId,
      confirmationChanges: flight,
      confirmed: (String hash, String owner, int originalChain) {
        if (!action.isCurrent ||
            owner != action.ownerAddress ||
            originalChain != chainId ||
            !addresses.contains(owner)) {
          return false;
        }
        try {
          final Hash original = Hash.parse(hash);
          return original != emptyHash && flight.hasConfirmed(original);
        } on Object {
          return false;
        }
      },
      plasmaSource: plasmaSource,
      ledgerSource: ledgerSource,
      isCurrent: () =>
          action.isCurrent &&
          identical(plasmaSource, action.client.embedded.plasma) &&
          identical(ledgerSource, action.client.ledger),
    );
  }

  /// Binds independent wrappers to original transports, including in fixtures.
  factory PlasmaSession.boundApis({
    required String address,
    required int chainId,
    required PlasmaApi plasmaSource,
    required LedgerApi ledgerSource,
    required bool Function() isCurrent,
    Listenable? confirmationChanges,
    bool Function(String hash, String owner, int chainId)? confirmed,
  }) {
    final Address owner = Address.parse(address);
    final Client plasmaClient = plasmaSource.client;
    final Client ledgerClient = ledgerSource.client;
    final String? plasmaUrl = plasmaClient is WsClient
        ? plasmaClient.url
        : null;
    final String? ledgerUrl = ledgerClient is WsClient
        ? ledgerClient.url
        : null;
    // The shared API objects can be rebound while a proof is awaiting its RPC.
    final PlasmaApi plasma = PlasmaApi()..setClient(plasmaClient);
    final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
    late final PlasmaSession session;
    void requireCurrent() {
      if (!session.isCurrent) {
        throw StateError('Plasma transport context changed');
      }
    }

    return session = PlasmaSession(
      address: address,
      chainId: chainId,
      confirmationChanges: confirmationChanges,
      confirmed: confirmed,
      isCurrent: () =>
          isCurrent() &&
          identical(plasmaClient, plasmaSource.client) &&
          identical(ledgerClient, ledgerSource.client) &&
          (plasmaClient is! WsClient || plasmaClient.url == plasmaUrl) &&
          (ledgerClient is! WsClient || ledgerClient.url == ledgerUrl),
      readEntries: (int page, int size) {
        requireCurrent();
        return plasma.getEntriesByAddress(
          owner,
          pageIndex: page,
          pageSize: size,
        );
      },
      readFrontier: () async {
        requireCurrent();
        final Momentum frontier = await ledger.getFrontierMomentum();
        requireCurrent();
        return frontier.height;
      },
      readAccount: () {
        requireCurrent();
        return ledger.getAccountInfoByAddress(owner);
      },
      cancelBlock: (String hash) {
        requireCurrent();
        return plasma.cancel(Hash.parse(hash));
      },
      fuseBlock: (String beneficiary, BigInt amount) {
        requireCurrent();
        return plasma.fuse(Address.parse(beneficiary), amount);
      },
    );
  }

  /// Exact selected owner, never a beneficiary inferred from a row.
  final String address;

  /// The signing chain captured with the original owner.
  final int chainId;
  final bool Function() _isCurrent;
  final bool Function(String hash, String owner, int chainId)? _confirmed;

  /// Existing exact-hash flight evidence can update a retained Fuse form.
  final Listenable? confirmationChanges;

  /// Positive retained evidence only. This never signs, reads or retries.
  bool confirmsOriginal(String hash, String owner, int originalChain) {
    try {
      return isCurrent &&
          owner == address &&
          originalChain == chainId &&
          (_confirmed?.call(hash, owner, originalChain) ?? false);
    } on Object {
      return false;
    }
  }

  /// The SDK response includes the complete owner's aggregate and one page.
  final Future<FusionEntryList> Function(int page, int size) readEntries;

  /// Height is authority for cancellation. A clock is only a display estimate.
  final Future<int> Function() readFrontier;

  /// A fresh, successful account read establishes available QSR.
  final Future<AccountInfo> Function() readAccount;

  /// Existing SDK builders, with immutable original arguments.
  final AccountBlockTemplate Function(String hash) cancelBlock;

  /// Builds a fusion for the original beneficiary and smallest-unit amount.
  final AccountBlockTemplate Function(String beneficiary, BigInt amount)
  fuseBlock;

  bool _revoked = false;

  /// Leaving and returning never revives an observed revoked session.
  bool get isCurrent => !_revoked && !(_revoked = !_isCurrent());
}

/// Copies the mutable SDK object before any asynchronous boundary.
class PlasmaFusion {
  /// One exact original fusion, expressed only in integer smallest units.
  const PlasmaFusion({
    required this.hash,
    required this.beneficiary,
    required this.amount,
    required this.expirationHeight,
  });

  /// The SDK entry's identifier remains the cancellation identity.
  factory PlasmaFusion.copy(FusionEntry entry) => PlasmaFusion(
    hash: entry.id.toString(),
    beneficiary: entry.beneficiary.toString(),
    amount: entry.qsrAmount,
    expirationHeight: entry.expirationHeight,
  );

  /// Full original hash used as the cancellation identity.
  final String hash;

  /// The address receiving plasma, which may differ from the owner.
  final String beneficiary;

  /// The original fusion amount in QSR smallest units.
  final BigInt amount;

  /// The final locked momentum height returned by the contract.
  final int expirationHeight;

  /// The contract unlocks in the momentum after the expiration height.
  bool eligibleAt(int height) => height > expirationHeight;

  /// Fresh ownership proof must match every displayed original field.
  bool matches(PlasmaFusion other) =>
      hash == other.hash &&
      beneficiary == other.beneficiary &&
      amount == other.amount &&
      expirationHeight == other.expirationHeight;
}

/// Unknown and incomplete accounts cannot manufacture a zero balance.
BigInt? plasmaQsrFromAccount(AccountInfo account, String owner) {
  final List<BalanceInfoListItem>? balances = account.balanceInfoList;
  final int? height = account.blockCount;
  if (account.address != owner ||
      height == null ||
      height < 0 ||
      balances == null) {
    return null;
  }
  final Set<String> seen = <String>{};
  BigInt result = BigInt.zero;
  for (final BalanceInfoListItem item in balances) {
    final Token? token = item.token;
    final BigInt? amount = item.balance;
    if (token == null || amount == null || amount < BigInt.zero) return null;
    if (!seen.add(token.tokenStandard.toString())) return null;
    if (token.tokenStandard == qsrZts) result = amount;
  }
  return result;
}

/// Only a successful selected-account response can populate the strip.
BigInt? plasmaAvailableQsr(MultipleBalanceState state, String owner) {
  if (state.status != MultipleBalanceStatus.success) return null;
  final AccountInfo? account = state.data?[owner];
  return account == null ? null : plasmaQsrFromAccount(account, owner);
}

/// Preserves valid raw fractional QSR without a float or decimal truncation.
BigInt? parsePlasmaQsr(String text, {int decimals = coinDecimals}) {
  if (decimals < 0 || !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(text)) {
    return null;
  }
  final List<String> parts = text.split('.');
  final String fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  return BigInt.parse('${parts[0]}${fraction.padRight(decimals, '0')}');
}
