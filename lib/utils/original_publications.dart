import 'dart:async';

/// A paused original owner cannot admit another direct SDK publication.
class OriginalPublicationRefused implements Exception {
  /// The original lane has already closed admission.
  const OriginalPublicationRefused();
}

/// The exact asynchronous operation and its terminal answer.
class OriginalPublication<T> {
  OriginalPublication._();

  Future<T>? _future;
  final Completer<void> _settled = Completer<void>();
  T? _result;
  Object? _error;
  StackTrace? _stackTrace;
  Object? _releaseError;
  StackTrace? _releaseTrace;
  String? _acceptedHash;

  /// The identical Future returned by the original operation.
  Future<T>? get future => _future;

  /// Its accepted result stays identical even when release fails.
  T? get result => _result;

  /// The original operation's error, if any.
  Object? get error => _error;

  /// The original operation's error trace.
  StackTrace? get stackTrace => _stackTrace;

  /// A failed release prevents a positive drain without replacing a result.
  Object? get releaseError => _releaseError;

  /// The original release error trace.
  StackTrace? get releaseTrace => _releaseTrace;

  /// Copied immediately when the SDK returns, before optional observers await.
  String? get acceptedHash => _acceptedHash;

  /// Retains the first original accepted hash without changing its raw result.
  void retainPublicationHash(String hash) {
    _acceptedHash ??= hash;
  }

  /// True only after the actual operation Future has settled.
  bool get settled => _settled.isCompleted;

  /// The sender records a failed release of its acquired original file.
  void recordReleaseFailure(Object error, StackTrace trace) {
    _releaseError = error;
    _releaseTrace = trace;
  }

  Future<T> _start(Future<T> Function(OriginalPublication<T>) action) {
    Future<T> original;
    try {
      original = action(this);
    } on Object catch (error, trace) {
      original = Future<T>.error(error, trace);
    }
    _future = original;
    unawaited(
      original.then<void>(
        (T value) {
          _result = value;
          _settled.complete();
        },
        onError: (Object error, StackTrace trace) {
          _error = error;
          _stackTrace = trace;
          _settled.complete();
        },
      ),
    );
    return original;
  }
}

/// A terminal admission stop and the actual original operations it waited for.
class OriginalPublicationDrain {
  OriginalPublicationDrain._(
    this.owner,
    List<OriginalPublication<dynamic>> operations,
  ) : operations = List<OriginalPublication<dynamic>>.unmodifiable(operations);

  /// The identical wallet-file owner supplied at admission.
  final Object owner;

  /// No operation can be added to this owner's lane after it was paused.
  final List<OriginalPublication<dynamic>> operations;

  /// Failed publication is settled; failed file release is not quiescence.
  bool get completed => operations.every(
    (OriginalPublication<dynamic> operation) =>
        operation.settled && operation.releaseError == null,
  );
}

class _OriginalPublicationLane {
  final List<OriginalPublication<dynamic>> operations =
      <OriginalPublication<dynamic>>[];
  bool paused = false;
  bool refusedAdmission = false;
  Future<OriginalPublicationDrain>? draining;
}

/// Tracks original SDK sends without signing, retrying or canceling them.
abstract final class OriginalPublications {
  static final Expando<_OriginalPublicationLane> _lanes =
      Expando<_OriginalPublicationLane>();

  /// Observes whether this owner's terminal lane refused a new admission.
  static bool hasRefusedAdmission(Object owner) =>
      _lanes[owner]?.refusedAdmission ?? false;

  /// Observes originals without pausing, admitting or publishing work.
  static List<OriginalPublication<dynamic>> snapshot(Object owner) =>
      List<OriginalPublication<dynamic>>.unmodifiable(
        _lanes[owner]?.operations ?? <OriginalPublication<dynamic>>[],
      );

  /// Existing direct sends must settle and release before transport changes.
  static bool canChangeTransport(Object owner) => snapshot(owner).every(
    (OriginalPublication<dynamic> operation) =>
        operation.settled && operation.releaseError == null,
  );

  /// Reserves before invoking code that can notify a synchronous observer.
  static Future<T> run<T>(
    Object owner,
    Future<T> Function(OriginalPublication<T> operation) action,
  ) => runForOwners(<Object>[owner], action);

  /// Reserves one original in every captured lane before invoking its callback.
  /// The SDK lane protects a pending send across a decrypted-file replacement.
  static Future<T> runForOwners<T>(
    Iterable<Object> owners,
    Future<T> Function(OriginalPublication<T> operation) action,
  ) {
    final Set<Object> identities = Set<Object>.identity()..addAll(owners);
    if (identities.isEmpty) throw const OriginalPublicationRefused();
    final List<_OriginalPublicationLane> lanes = identities
        .map(
          (Object owner) => _lanes[owner] ??= _OriginalPublicationLane(),
        )
        .toList();
    if (lanes.any((_OriginalPublicationLane lane) => lane.paused)) {
      for (final _OriginalPublicationLane lane in lanes) {
        if (lane.paused) lane.refusedAdmission = true;
      }
      throw const OriginalPublicationRefused();
    }
    final OriginalPublication<T> operation = OriginalPublication<T>._();
    for (final _OriginalPublicationLane lane in lanes) {
      lane.operations.add(operation);
    }
    return operation._start(action);
  }

  /// Closes admission synchronously and waits for the actual original Futures.
  static Future<OriginalPublicationDrain> pauseAndDrain(Object owner) {
    final _OriginalPublicationLane lane =
        (_lanes[owner] ??= _OriginalPublicationLane())..paused = true;
    return lane.draining ??= _drain(owner, lane);
  }

  static Future<OriginalPublicationDrain> _drain(
    Object owner,
    _OriginalPublicationLane lane,
  ) async {
    final List<OriginalPublication<dynamic>> originals =
        List<OriginalPublication<dynamic>>.of(lane.operations);
    for (final OriginalPublication<dynamic> operation in originals) {
      await operation._settled.future;
    }
    return OriginalPublicationDrain._(owner, originals);
  }
}
