import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/reclaim_htlc_swap_funds_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Recovery retains the original owner across lookup and fresh reclaim proof.
class RecoverHtlcSwapFundsBloc extends ReclaimHtlcSwapFundsBloc {
  /// Keeps recovery on the original chain readers, store and member signers.
  RecoverHtlcSwapFundsBloc({super.origin});

  /// Looks up the exact deposit and permits reclaim only for its owned sender.
  Future<void> recoverFunds({required Hash htlcId}) => execute((
    SwapActionOrigin source,
  ) async {
    source.requireCurrent();
    final HtlcInfo deposit = await source.readHtlc(htlcId.toString());
    source.requireCurrent();
    if (deposit.id != htlcId ||
        !source.members.contains(deposit.timeLocked.toString())) {
      throw const SwapActionRefused('owner');
    }
    return SwapActions.reclaim(source, htlcId, deposit.timeLocked.toString());
  }, (SwapActionResult result) => result.block);
}
