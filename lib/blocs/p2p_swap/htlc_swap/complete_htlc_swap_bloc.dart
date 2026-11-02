import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/owned_swap_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';

/// Unlock submission does not manufacture a completed swap state.
class CompleteHtlcSwapBloc extends OwnedSwapActionBloc<HtlcSwap> {
  /// Keeps the existing stream API on the captured action source.
  CompleteHtlcSwapBloc({super.origin});

  /// Submits one exact deposit unlock; completion remains a chain-history fact.
  Future<void> completeHtlcSwap({required HtlcSwap swap}) => execute(
    (SwapActionOrigin source) => SwapActions.complete(source, swap),
    (SwapActionResult result) => result.swap,
  );
}
