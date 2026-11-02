import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Display ownership for one SDK send. Its identity contains no wallet data.
final class PowWorkToken {
  PowWorkToken._();
}

/// Separates forgotten work from an SDK-reported completion.
enum PowGenerationPhase {
  /// No generation belongs to the current display.
  idle,

  /// The owning SDK send reported that generation started.
  generating,

  /// The owning SDK send reported that generation finished.
  completed,
}

/// One generation display update, correlated by an opaque [work] identity.
final class PowGenerationState {
  /// Clears a display without claiming that any work finished.
  const PowGenerationState.idle()
    : phase = PowGenerationPhase.idle,
      work = null;

  /// Reports the SDK's generation start for [work].
  const PowGenerationState.generating(PowWorkToken this.work)
    : phase = PowGenerationPhase.generating;

  /// Reports the SDK's actual generation completion for [work].
  const PowGenerationState.completed(PowWorkToken this.work)
    : phase = PowGenerationPhase.completed;

  /// Whether work is absent, running, or known to have finished.
  final PowGenerationPhase phase;

  /// The owning send, or null when the display is idle.
  final PowWorkToken? work;

  /// Whether the owning SDK send has reported active generation.
  bool get isGenerating => phase == PowGenerationPhase.generating;
}

/// Retains only PoW display state owned by the current SDK send.
///
/// Revoking display ownership never cancels, signs, publishes or retries a
/// block. A later callback from a revoked send cannot restore its display.
class PowGeneratingStatusBloc {
  final BehaviorSubject<PowGenerationState> _controller =
      BehaviorSubject<PowGenerationState>.seeded(
        const PowGenerationState.idle(),
      );
  PowWorkToken? _work;

  /// Replays the current display, including explicit idle after invalidation.
  ValueStream<PowGenerationState> get stream => _controller.stream;

  /// The latest display state, available before an asynchronous replay.
  PowGenerationState get value => _controller.value;

  /// Claims display ownership without claiming that generation has started.
  ///
  /// Replacing an owner forgets its elapsed interval. After disposal the
  /// returned token is inert, so a display observer cannot disrupt a send.
  PowWorkToken claimWork() {
    final PowWorkToken work = PowWorkToken._();
    if (_controller.isClosed) return work;
    _work = work;
    _idle();
    return work;
  }

  /// Whether [work] still owns the display, even after its actual completion.
  bool ownsWork(PowWorkToken work) =>
      !_controller.isClosed && identical(_work, work);

  /// Accepts an actual SDK event only for its current [work] owner.
  ///
  /// Returns false for stale or duplicate events. A completed token cannot
  /// start again; another generation requires a new send ownership token.
  bool update(PowWorkToken work, PowStatus status) {
    if (!ownsWork(work)) return false;
    final PowGenerationState previous = value;
    if (identical(previous.work, work) &&
        (previous.phase == PowGenerationPhase.completed ||
            (previous.isGenerating && status == PowStatus.generating))) {
      return false;
    }
    _controller.add(switch (status) {
      PowStatus.generating => PowGenerationState.generating(work),
      PowStatus.done => PowGenerationState.completed(work),
    });
    return true;
  }

  /// Forgets only [work], leaving a replacement send's display untouched.
  void release(PowWorkToken work) {
    if (ownsWork(work)) invalidate();
  }

  /// Revokes every old token and clears the display without a completion.
  void invalidate() {
    _work = null;
    if (!_controller.isClosed) _idle();
  }

  void _idle() {
    if (value.phase != PowGenerationPhase.idle) {
      _controller.add(const PowGenerationState.idle());
    }
  }

  /// Revokes ownership and closes this display source. Safe to call twice.
  void dispose() {
    if (_controller.isClosed) return;
    invalidate();
    unawaited(_controller.close());
  }
}
