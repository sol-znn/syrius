import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/owned_swap_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The drawn deposit is refreshed exactly before the original counter deposit.
class JoinHtlcSwapBloc extends OwnedSwapActionBloc<HtlcSwap> {
  /// Observes a single Join action on the original wallet source.
  JoinHtlcSwapBloc({super.origin});

  /// Refreshes the drawn deposit and funding proof before creating the native
  /// counterdeposit; the chain clock supplies its expiration.
  Future<void> joinHtlcSwap({
    required HtlcInfo initialHtlc,
    required Token fromToken,
    required Token toToken,
    required BigInt fromAmount,
    required P2pSwapType swapType,
    required P2pSwapChain fromChain,
    required P2pSwapChain toChain,
    required int counterHtlcExpirationTime,
  }) => execute((SwapActionOrigin source) {
    if (swapType != P2pSwapType.native ||
        fromChain != P2pSwapChain.nom ||
        toChain != P2pSwapChain.nom) {
      throw const SwapActionRefused('terms');
    }
    // The legacy hint is never signing authority. The original chain time
    // determines the real one-hour counter expiry at this action's admission.
    return SwapActions.join(
      source,
      initialDeposit: initialHtlc,
      fromToken: fromToken,
      toToken: toToken,
      amount: fromAmount,
    );
  }, (SwapActionResult result) => result.swap);
}
