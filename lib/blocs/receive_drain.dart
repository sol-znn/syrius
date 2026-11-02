part of 'auto_receive_tx_worker.dart';

/// The identical admitted read Future and its terminal answer.
class ReceiveReadReceipt<T> {
  ReceiveReadReceipt._(this.name);

  /// Names the original read stage without retaining transport diagnostics.
  final String name;
  Future<T>? _future;
  T? _result;
  Object? _error;
  StackTrace? _stackTrace;
  final Completer<void> _settled = Completer<void>();

  /// The identical Future returned by the captured read port.
  Future<T>? get future => _future;

  /// The unchanged result of that original read.
  T? get result => _result;

  /// The original failure remains separate from later presentation.
  Object? get error => _error;

  /// The original failure trace, retained privately.
  StackTrace? get stackTrace => _stackTrace;

  /// Settlement alone does not establish a successful read.
  bool get completed => _settled.isCompleted;

  Future<T> _read(Future<T> Function() read) async {
    try {
      final Future<T> original = read();
      _future = original;
      final T result = await original;
      _result = result;
      return result;
    } on Object catch (error, trace) {
      _error = error;
      _stackTrace = trace;
      rethrow;
    } finally {
      _settled.complete();
    }
  }
}

/// A terminal pause and all original work that it actually waited for.
class ReceiveDrainReceipt {
  ReceiveDrainReceipt._({
    required this.owner,
    required this.completed,
    required List<ReceiveReadReceipt<dynamic>> reads,
    required List<ReceiveRecord> publications,
  }) : reads = List<ReceiveReadReceipt<dynamic>>.unmodifiable(reads),
       publications = List<ReceiveRecord>.unmodifiable(publications);

  /// The exact worker whose admission was closed.
  final AutoReceiveTxWorker owner;

  /// Requires successful original reads and accepted original publications.
  final bool completed;

  /// Actual admitted reads, including reads added by an active drain.
  final List<ReceiveReadReceipt<dynamic>> reads;

  /// Original publications, never a reconstructed replacement attempt.
  final List<ReceiveRecord> publications;
}

/// Maintenance waits for the existing owner; it cannot cancel an original.
extension ReceiveQuiescence on AutoReceiveTxWorker {
  /// Closes admission synchronously, then waits for actual original operations.
  Future<ReceiveDrainReceipt> pauseAndDrain() {
    final Future<ReceiveDrainReceipt>? existing = _pausing;
    if (existing != null) return existing;
    // Admission closes before a notifier, cleanup or another owner can run.
    _paused = true;
    final Completer<ReceiveDrainReceipt> completion =
        Completer<ReceiveDrainReceipt>();
    _pausing = completion.future;
    final List<ReceiveReadReceipt<dynamic>> admittedReads =
        List<ReceiveReadReceipt<dynamic>>.of(_readOperations);
    final Future<void>? originalDrain = _drain;
    clearAutomatic();
    for (final _ReceiveRequest queued in List<_ReceiveRequest>.of(_queue)) {
      _refuse(queued, const ReceiveRefused(), StackTrace.current);
    }
    _queue.clear();
    unawaited(() async {
      for (final ReceiveReadReceipt<dynamic> read in admittedReads) {
        await read._settled.future;
      }
      if (originalDrain != null) await originalDrain;
      // An admitted active request may reserve its read during a synchronous
      // observer that pauses admission. Its actual drain must finish first.
      final List<ReceiveReadReceipt<dynamic>> reads =
          List<ReceiveReadReceipt<dynamic>>.of(_readOperations);
      for (final ReceiveReadReceipt<dynamic> read in reads) {
        await read._settled.future;
      }
      final List<ReceiveRecord> originals = List<ReceiveRecord>.of(_originals);
      completion.complete(
        ReceiveDrainReceipt._(
          owner: this,
          completed:
              reads.every(
                (ReceiveReadReceipt<dynamic> read) =>
                    read.completed && read.error == null,
              ) &&
              originals.every(
                (ReceiveRecord record) =>
                    record.result != null &&
                    record.error == null &&
                    AutoReceiveTxWorker._accepted(record, record.result!.block),
              ),
          reads: reads,
          publications: originals,
        ),
      );
    }());
    return completion.future;
  }
}
