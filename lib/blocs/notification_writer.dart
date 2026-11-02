part of 'notifications_bloc.dart';

/// A fixed ownership refusal, without backend paths or native diagnostics.
class NotificationWriterRefused implements Exception {
  /// Creates a source-level refusal.
  const NotificationWriterRefused(this.reason);

  /// Names the missing original capability.
  final String reason;
}

/// One actual original operation, including its unmodified terminal answer.
class NotificationOperationReceipt {
  /// Retains the identical Future returned by the captured backend or plugin.
  const NotificationOperationReceipt({
    required this.name,
    required this.future,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// A fixed operation name, never a backend path.
  final String name;

  /// The actual original Future, without a success-substituting wrapper.
  final Future<dynamic> future;

  /// The exact original successful result.
  final Object? result;

  /// The exact original error, if the Future failed.
  final Object? error;

  /// The original failure trace.
  final StackTrace? stackTrace;
}

/// One admitted notification's original storage and display operations.
class NotificationWriteReceipt {
  /// Copies only the receipt list; Future, error and result identities survive.
  NotificationWriteReceipt({
    required this.owner,
    required this.store,
    required this.completed,
    required List<NotificationOperationReceipt> operations,
    this.error,
    this.stackTrace,
  }) : operations = List<NotificationOperationReceipt>.unmodifiable(operations);

  /// The exact writer that admitted this notification.
  final NotificationsBloc owner;

  /// The original returned or explicitly supplied backend.
  final Box<dynamic>? store;

  /// True only when admitted work finished without error or revocation.
  final bool completed;

  /// Actual original operations in invocation order.
  final List<NotificationOperationReceipt> operations;

  /// The original refusal or failure, never a display replacement.
  final Object? error;

  /// The original refusal or failure trace.
  final StackTrace? stackTrace;
}

/// Positive terminal pause for one exact writer and its admitted originals.
class NotificationDrainReceipt {
  /// Preserves every admitted write, including failed original operations.
  NotificationDrainReceipt({
    required this.owner,
    required this.store,
    required List<NotificationWriteReceipt> writes,
    required this.completed,
    this.error,
    this.stackTrace,
  }) : writes = List<NotificationWriteReceipt>.unmodifiable(writes);

  /// The exact paused owner, independent of a widget's route lifetime.
  final NotificationsBloc owner;

  /// The owner's original backend, if any operation bound one.
  final Box<dynamic>? store;

  /// Every write reserved before admission closed.
  final List<NotificationWriteReceipt> writes;

  /// True only after all originals settled and ownership remains valid.
  /// Failed settled writes remain inspectable in [writes].
  final bool completed;

  /// A terminal ownership refusal; write failures remain in [writes].
  final Object? error;

  /// Its original failure trace.
  final StackTrace? stackTrace;
}

class _NotificationWrite {
  final Completer<NotificationWriteReceipt> _completion =
      Completer<NotificationWriteReceipt>();
  final List<_NotificationOperation> operations = <_NotificationOperation>[];
  Box<dynamic>? store;
  _NotificationOperation? open;
  _NotificationTurn? turn;
  Future<void> Function()? show;
  Object? setupError;
  StackTrace? setupStack;
  Object? displayError;
  StackTrace? displayStack;

  Future<NotificationWriteReceipt> get future => _completion.future;

  _NotificationOperation observe(String name, Future<dynamic> original) {
    final _NotificationOperation operation = _NotificationOperation(
      name,
      original,
    );
    operations.add(operation);
    operation.observe();
    return operation;
  }

  void complete(NotificationWriteReceipt receipt) =>
      _completion.complete(receipt);
}

class _NotificationOperation {
  _NotificationOperation(this.name, this.future);

  final String name;
  final Future<dynamic> future;
  NotificationOperationReceipt? receipt;
  late final Future<void> _observation;

  void observe() => _observation = _observe();

  Future<void> _observe() async {
    try {
      final Object? result = await future;
      receipt = NotificationOperationReceipt(
        name: name,
        future: future,
        result: result,
      );
    } on Object catch (error, stackTrace) {
      receipt = NotificationOperationReceipt(
        name: name,
        future: future,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Object?> result() async {
    await _observation;
    final NotificationOperationReceipt original = receipt!;
    if (original.error != null) {
      Error.throwWithStackTrace(original.error!, original.stackTrace!);
    }
    return original.result;
  }
}

class _NotificationStoreLane {
  Future<void> _tail = Future<void>.value();

  _NotificationTurn reserve() {
    final _NotificationTurn turn = _NotificationTurn(_tail);
    _tail = turn._released.future;
    return turn;
  }
}

class _NotificationTurn {
  _NotificationTurn(this.ready);

  final Future<void> ready;
  final Completer<void> _released = Completer<void>();

  void release() => _released.complete();
}
