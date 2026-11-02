part of 'send_transaction_bloc.dart';

/// A single admitted request's original result, independent of later states.
class SendRequestResult {
  /// Records an accepted response or the original failure, without retrying.
  const SendRequestResult({this.block, this.error});

  /// The exact accepted response returned by the existing publication owner.
  final AccountBlockTemplate? block;

  /// A failure does not establish that the node rejected the publication.
  final Object? error;

  /// Whether an original accepted response is available.
  bool get accepted => block != null && error == null;
}

/// The outcome of one synchronously admitted request.
class SendRequestHandle {
  SendRequestHandle._(this.requestId, this.result);

  /// The caller's exact ephemeral request identity.
  final Object requestId;

  /// Settles once with the original response or failure.
  final Future<SendRequestResult> result;
}

class _SendAdmission {
  _SendAdmission(this.event, {this.owner, this.canStart, this.canPublish});

  final SendTransactionEvent event;
  final Object? owner;
  final bool Function()? canStart;
  final bool Function()? canPublish;
  final Completer<SendRequestResult> completion =
      Completer<SendRequestResult>();
  final Completer<void> drained = Completer<void>();
  bool started = false;
}

class _SenderBusyNotifier extends ValueNotifier<bool> {
  _SenderBusyNotifier(this._report) : super(false);

  final void Function(Object, StackTrace) _report;
  final Map<VoidCallback, List<VoidCallback>> _guarded =
      <VoidCallback, List<VoidCallback>>{};

  @override
  void addListener(VoidCallback listener) {
    void guarded() {
      try {
        listener();
      } on Object catch (error, trace) {
        // A throwing Flutter error handler leaves notifier dispatch unfinished.
        _report(error, trace);
      }
    }

    super.addListener(guarded);
    (_guarded[listener] ??= <VoidCallback>[]).add(guarded);
  }

  @override
  void removeListener(VoidCallback listener) {
    final List<VoidCallback>? registrations = _guarded[listener];
    if (registrations == null) return;
    final VoidCallback guarded = registrations.removeAt(0);
    if (registrations.isEmpty) _guarded.remove(listener);
    super.removeListener(guarded);
  }

  @override
  void dispose() {
    _guarded.clear();
    super.dispose();
  }
}
