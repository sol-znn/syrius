import 'package:zenon_syrius_wallet_flutter/blocs/base_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Read-only compatibility observer for one captured original lookup source.
class InitialHtlcForSwapBloc extends BaseBloc<HtlcInfo?> {
  /// Uses a captured lookup source; a missing source refuses before RPC.
  InitialHtlcForSwapBloc({this.origin});

  /// Original chain readers and ownership guard for all lookups.
  final SwapActionOrigin? origin;

  /// Last unchanged backend failure, retained outside the display stream.
  Object? originalError;

  /// Original stack trace associated with [originalError].
  StackTrace? originalStackTrace;

  /// Actual lookup Future, retained even if a later lookup supersedes its UI.
  Future<HtlcInfo>? originalLookup;
  int _epoch = 0;

  /// Requires a live deposit, its exact confirmed Create and complete history
  /// before exposing it as a candidate for Join.
  Future<void> getInitialHtlc(Hash id) async {
    final int epoch = ++_epoch;
    final SwapActionOrigin? source = origin;
    try {
      if (source == null) throw const SwapActionRefused('source');
      final Future<HtlcInfo> original = SwapActions.initial(source, id);
      originalLookup = original;
      final HtlcInfo result = await original;
      if (!disposed && epoch == _epoch && source.isCurrent) addEvent(result);
    } on Object catch (error, trace) {
      originalError = error;
      originalStackTrace = trace;
      if (!disposed && epoch == _epoch && (source?.isCurrent ?? false)) {
        await addError(
          const SwapActionRefused('deposit-unavailable'),
          StackTrace.empty,
        );
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }
}
