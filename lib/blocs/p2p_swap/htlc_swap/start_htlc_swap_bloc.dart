import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/owned_swap_action_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The existing one-sided deposit operation, bound before the first RPC.
class StartHtlcSwapBloc extends OwnedSwapActionBloc<HtlcSwap> {
  /// Observes a single Start action on the original wallet source.
  StartHtlcSwapBloc({super.origin});

  /// Validates native terms and creates one funded initial deposit with durable
  /// recovery material before admitting the original signer.
  Future<void> startHtlcSwap({
    required Address selfAddress,
    required Address counterpartyAddress,
    required Token fromToken,
    required BigInt fromAmount,
    required int hashType,
    required P2pSwapType swapType,
    required P2pSwapChain fromChain,
    required P2pSwapChain toChain,
    required int initialHtlcDuration,
  }) => execute((SwapActionOrigin source) {
    if (swapType != P2pSwapType.native ||
        fromChain != P2pSwapChain.nom ||
        toChain != P2pSwapChain.nom ||
        initialHtlcDuration != kInitialHtlcDuration.inSeconds) {
      throw const SwapActionRefused('terms');
    }
    return SwapActions.start(
      source,
      selfAddress: selfAddress.toString(),
      counterparty: counterpartyAddress.toString(),
      fromToken: fromToken,
      amount: fromAmount,
      hashType: hashType,
    );
  }, (SwapActionResult result) => result.swap);
}
