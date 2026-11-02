import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// An exact-hash confirmation lookup on a specified chain.
typedef ChainConfirmationLookup = Future<bool> Function(int chainId, Hash hash);

/// Keeps published blocks in memory for their wallet and chain.
///
/// Locking only hides the view. Returning to the same wallet restores its
/// unresolved hashes without treating a timeout or a node switch as settlement.
class WalletFlightRegistry {
  /// Creates the registry with explicit confirmation and chain sources.
  WalletFlightRegistry({required this.lookup, required this.currentChainId});

  /// The running wallet's registry. It never signs, publishes or retries.
  static final WalletFlightRegistry instance = WalletFlightRegistry(
    currentChainId: getChainIdentifier,
    lookup: (int chainId, Hash hash) async {
      final AccountBlock? block = await zenon!.ledger.getAccountBlockByHash(
        hash,
      );
      return block?.hash == hash &&
          block?.chainIdentifier == chainId &&
          block?.confirmationDetail != null;
    },
  );

  /// Looks up the original hash on the current node.
  final ChainConfirmationLookup lookup;

  /// Rejects a lookup started or completed on another chain.
  final int Function() currentChainId;

  final Map<(int, String), InFlightBlocks> _wallets =
      <(int, String), InFlightBlocks>{};

  /// The first derived address anchors the wallet, independent of selection or
  /// later derived addresses. [addresses] must keep the wallet's index order.
  InFlightBlocks forWallet(int chainId, Iterable<String> addresses) {
    final String anchor = addresses.isEmpty ? '' : addresses.first;
    return _wallets.putIfAbsent((chainId, anchor), () {
      return InFlightBlocks(
        lookup: (Hash hash) async {
          if (currentChainId() != chainId) return false;
          final bool confirmed = await lookup(chainId, hash);
          return currentChainId() == chainId && confirmed;
        },
      );
    });
  }

  /// Observes the returned publication without modifying its template.
  /// Unknown token units stay unknown instead of assuming eight decimals.
  bool published(AccountBlockTemplate block, Iterable<String> walletAddresses) {
    final Set<String> addresses = walletAddresses.toSet();
    if (block.hash == emptyHash ||
        !addresses.contains(block.address.toString())) {
      return false;
    }
    Token? metadata;
    for (final Token token in kDualCoin) {
      if (token.tokenStandard == block.tokenStandard) metadata = token;
    }
    forWallet(block.chainIdentifier, addresses).sent(
      hash: block.hash,
      amount: block.amount,
      decimals: metadata?.decimals,
      symbol: metadata?.symbol,
    );
    return true;
  }

  /// Releases the session models when their owner is finished.
  void dispose() {
    for (final InFlightBlocks blocks in _wallets.values) {
      blocks.dispose();
    }
    _wallets.clear();
  }
}
