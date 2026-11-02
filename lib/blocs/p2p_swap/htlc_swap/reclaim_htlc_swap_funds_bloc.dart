import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/owned_swap_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Reclaims only a freshly proven original deposit after positive chain time.
class ReclaimHtlcSwapFundsBloc
    extends OwnedSwapActionBloc<AccountBlockTemplate> {
  /// Observes reclaim publication without owning retries or terminal status.
  ReclaimHtlcSwapFundsBloc({super.origin});

  /// Rechecks exact deposit ownership and expiry before one reclaim submission.
  Future<void> reclaimFunds({
    required Hash htlcId,
    required Address selfAddress,
  }) => execute(
    (SwapActionOrigin source) =>
        SwapActions.reclaim(source, htlcId, selfAddress.toString()),
    (SwapActionResult result) => result.block,
  );
}
