import 'package:zenon_syrius_wallet_flutter/blocs/base_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Compatibility streams observe original outcomes without owning publication.
abstract class AcceleratorActionBloc extends BaseBloc<AccountBlockTemplate?> {
  /// Captures an original source and the retained action controller once.
  AcceleratorActionBloc({
    AcceleratorActionSource? source,
    AcceleratorActionController? controller,
  }) : _source = source ?? _capture(),
       _controller = controller ?? AcceleratorActionController.shared;
  static AcceleratorActionSource? _capture() {
    try {
      return AcceleratorActionBinding.capture();
    } on Object {
      return null;
    }
  }

  final AcceleratorActionSource? _source;
  final AcceleratorActionController _controller;
  bool _closed = false;

  /// Observes one original action; display failure cannot replace its outcome.
  Future<AcceleratorActionOutcome> run(AcceleratorActionRequest request) async {
    final AcceleratorActionSource? source = _source;
    if (_closed || source == null || !source.isCurrent) {
      return AcceleratorActionOutcome(AcceleratorActionState.refused);
    }
    try {
      addEvent(null);
    } on Object {
      /* Display cannot own admission. */
    }
    final Future<AcceleratorActionOutcome> original = _controller.submit(
      source,
      request,
      canContinue: () => !_closed && source.isCurrent,
    );
    final AcceleratorActionOutcome outcome = await original;
    if (!_closed && source.isCurrent) {
      try {
        if (outcome.state == AcceleratorActionState.submitted) {
          addEvent(outcome.blocks.last);
        } else if (outcome.error != null) {
          await addError(
            outcome.error!,
            outcome.stackTrace ?? StackTrace.current,
          );
        }
      } on Object {
        // A UI or logging observer cannot replace the original result.
      }
    }
    return outcome;
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
