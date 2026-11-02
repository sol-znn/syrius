import 'package:collection/collection.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/periodic_p2p_swap_base_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';

/// Legacy periodic reads stay on the exact original encrypted catalogue.
class HtlcSwapBloc extends PeriodicP2pSwapBaseBloc<HtlcSwap> {
  /// Polls one record in the catalogue captured by [origin].
  HtlcSwapBloc(this.swapId, {this.origin});

  /// Exact catalogue key; this is never inferred from a hash lock.
  final String swapId;

  /// Original store and chain authority used by every poll.
  final SwapActionOrigin? origin;

  @override
  HtlcSwap makeCall() {
    final SwapActionOrigin? source = origin;
    if (source == null) throw const SwapActionRefused('source');
    source.requireCurrent();
    final HtlcSwap? result = source.readHistory().firstWhereOrNull(
      (HtlcSwap value) => value.id == swapId && value.chainId == source.chainId,
    );
    source.requireCurrent();
    if (result == null) throw const SwapActionRefused('record-unavailable');
    return HtlcSwap.fromJson(result.toJson());
  }
}
