import 'package:zenon_syrius_wallet_flutter/blocs/base_bloc.dart';

import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';

/// Compatibility streams observe one original operation; they never own retry.
abstract class OwnedSwapActionBloc<T> extends BaseBloc<T?> {
  /// Observes actions from [origin] without discovering a replacement wallet.
  OwnedSwapActionBloc({this.origin});

  /// Original wallet capabilities retained for this observer's lifetime.
  final SwapActionOrigin? origin;
  Future<SwapActionResult>? _operation;
  SwapActionResult? _result;

  /// The identical future admitted by the original action source.
  Future<SwapActionResult>? get operation => _operation;

  /// Original accepted result and errors survive disposal of this observer.
  SwapActionResult? get originalResult => _result;

  /// Admits one original action and projects only a submitted result to the
  /// stream; disposal silences the observer without canceling that action.
  Future<void> execute(
    Future<SwapActionResult> Function(SwapActionOrigin source) action,
    T? Function(SwapActionResult result) project,
  ) async {
    final Future<SwapActionResult>? existing = _operation;
    if (existing != null) {
      try {
        await existing;
      } on Object {
        /* The first observer retains its failure. */
      }
      return;
    }
    final SwapActionOrigin? source = origin;
    Future<SwapActionResult> original;
    try {
      if (source == null || !source.isCurrent) {
        throw const SwapActionRefused('source');
      }
      original = action(source);
    } on Object catch (error, trace) {
      original = Future<SwapActionResult>.value(
        SwapActionResult(
          status: SwapActionStatus.refused,
          error: error,
          stackTrace: trace,
        ),
      );
    }
    _operation = original;
    if (!disposed) addEvent(null);
    SwapActionResult result;
    try {
      result = await original;
    } on Object catch (error, trace) {
      result = SwapActionResult(
        status: error is SwapActionRefused
            ? SwapActionStatus.refused
            : SwapActionStatus.unknown,
        error: error,
        stackTrace: trace,
      );
    }
    _result = result;
    if (disposed || source == null || !source.isCurrent) return;
    if (result.status == SwapActionStatus.submitted) {
      addEvent(project(result));
    } else {
      // Raw backend failures remain private in originalResult. The legacy
      // stream carries a fixed refusal that cannot disclose paths or secrets.
      await addError(
        SwapActionRefused(
          result.status == SwapActionStatus.unknown ? 'unknown' : 'refused',
        ),
        StackTrace.empty,
      );
    }
  }
}
