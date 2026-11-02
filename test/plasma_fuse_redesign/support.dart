import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../plasma_redesign/support.dart';

/// Offline publication plus the real exact-hash flight evidence model.
class FuseFixture extends PlasmaFixture {
  /// No wallet, key, socket or signing implementation exists in this fixture.
  FuseFixture() {
    registry = WalletFlightRegistry(
      currentChainId: () => confirmationChain,
      lookup: (int chainId, Hash hash) async {
        confirmationReads.add((chainId, hash.toString()));
        final Object? error = confirmationError;
        if (error != null) {
          Error.throwWithStackTrace(error, StackTrace.current);
        }
        return confirmedHashes.contains(hash.toString());
      },
    );
    flight = registry.forWallet(321, <String>[emptyAddress.toString()]);
  }

  /// Explicit positive replies for exact synthetic hashes.
  final Set<String> confirmedHashes = <String>{};

  /// Every requested chain and exact hash is recorded.
  final List<(int, String)> confirmationReads = <(int, String)>[];

  /// A changed chain cannot lend positive evidence.
  int confirmationChain = 321;

  /// Failed confirmation is uncertainty rather than success.
  Object? confirmationError;

  /// The existing registry is exercised without a real node.
  late final WalletFlightRegistry registry;

  /// The captured wallet and chain's pending and confirmed facts.
  late final InFlightBlocks flight;

  /// Adds only the optional confirmation seam to the original fixture session.
  PlasmaSession confirmedSession() {
    final PlasmaSession original = super.session();
    return PlasmaSession(
      address: original.address,
      chainId: original.chainId,
      isCurrent: () => original.isCurrent,
      readEntries: original.readEntries,
      readFrontier: original.readFrontier,
      readAccount: original.readAccount,
      cancelBlock: original.cancelBlock,
      fuseBlock: original.fuseBlock,
      confirmationChanges: flight,
      confirmed: (String hash, String owner, int chainId) =>
          owner == original.address &&
          chainId == original.chainId &&
          confirmationChain == chainId &&
          flight.hasConfirmed(Hash.parse(hash)),
    );
  }

  @override
  Future<void> close() async {
    await super.close();
    registry.dispose();
  }
}
