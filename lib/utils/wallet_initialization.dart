import 'dart:async';

/// A refusal contains no path, credentials or backend diagnostics.
class WalletInitializationRefused implements Exception {
  /// Classifies refusal with an internal code suitable for retained evidence.
  const WalletInitializationRefused([this.reason = 'unavailable']);

  /// An internal classification; callers map it to localized interface text.
  final String reason;
}

/// One actual original Future and its unchanged completion, independent of UI.
class WalletInitializationOperation {
  /// Names one captured asynchronous step without exposing its input data.
  WalletInitializationOperation(this.name);

  /// The operation kind, independent of backend diagnostics or private paths.
  final String name;

  /// The identical Future returned by the admitted operation, when it returned.
  Future<dynamic>? original;

  /// The unmodified original answer, which may legitimately be null.
  Object? result;

  /// The original failure, including a synchronous failure before a Future.
  Object? error;

  /// The trace retained with [error].
  StackTrace? stackTrace;

  /// Whether this operation settled; this does not prove cancellation.
  bool completed = false;

  /// Invokes once, retaining the actual Future and its exact result or failure.
  Future<T> run<T>(Future<T> Function() call) async {
    if (original != null || completed) {
      throw const WalletInitializationRefused('operation-reused');
    }
    try {
      final Future<T> future = call();
      original = future;
      final T value = await future;
      result = value;
      return value;
    } on Object catch (value, trace) {
      error = value;
      stackTrace = trace;
      rethrow;
    } finally {
      completed = true;
    }
  }
}

/// Private startup data is never a display model or a serialized report.
class WalletInitializationData {
  /// Freezes derived membership and labels for the original wallet file.
  WalletInitializationData({
    required this.path,
    required Iterable<String> members,
    required Map<String, String> labels,
    required this.selected,
    required this.chainId,
  }) : members = List<String>.unmodifiable(members),
       labels = Map<String, String>.unmodifiable(labels);

  /// The original encrypted file location; never serialize into public reports.
  final String path;

  /// Canonical addresses derived from the original wallet in account order.
  final List<String> members;

  /// The original private labels keyed by canonical member address.
  final Map<String, String> labels;

  /// The selected canonical address, which must occur in [members].
  final String selected;

  /// The captured signing chain, independent of later node observations.
  final int chainId;
}

/// What the original connection established about the signing chain.
enum WalletInitializationNetworkState {
  /// A live original connection observed the configured signing chain.
  compatible,

  /// A live original connection observed another chain requiring consent.
  knownMismatch,

  /// No chain was established; local entry grants no publication authority.
  unavailable,
}

/// A selected node, or the genuine absence of a first-profile selection.
class WalletInitializationTarget {
  const WalletInitializationTarget._(this.url);

  /// Missing selection is admitted only while creating the first wallet.
  /// A malformed saved target never becomes an offline or default target.
  static WalletInitializationTarget? fromPreference({
    required String? node,
    required bool creating,
    required String embeddedNode,
    required String embeddedUrl,
  }) {
    if (node == null) {
      return creating ? const WalletInitializationTarget._(null) : null;
    }
    final String url = node == embeddedNode ? embeddedUrl : node;
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null ||
        !<String>['ws', 'wss'].contains(parsed.scheme) ||
        parsed.host.isEmpty) {
      return null;
    }
    return WalletInitializationTarget._(url);
  }

  /// Null means no connection was requested before the node picker.
  final String? url;
}

/// Local initialization is not network readiness or SDK publication authority.
/// Observed chains belong to the exact captured connection, never preferences.
class WalletInitializationConnection {
  /// Records only observations attributable to the captured transport owner.
  const WalletInitializationConnection({
    required this.owner,
    required this.connected,
    required this.chainId,
    required this.state,
    this.transportUncertain = false,
  });

  /// The identical transport captured before any connection await.
  final Object owner;

  /// True only with a positive original connection receipt or live peer check.
  final bool connected;

  /// The positively observed node chain, or null when it was not established.
  final int? chainId;

  /// The relationship between that observation and the signing chain.
  final WalletInitializationNetworkState state;

  /// An unfinished terminal transport proof retains its existing quarantine.
  final bool transportUncertain;

  /// Allows local entry without treating mismatch or offline as online.
  bool permitsLocalInitialization(int signingChain) {
    if (signingChain <= 0) return false;
    switch (state) {
      case WalletInitializationNetworkState.compatible:
        return connected && !transportUncertain && chainId == signingChain;
      case WalletInitializationNetworkState.knownMismatch:
        return connected &&
            !transportUncertain &&
            chainId != null &&
            chainId! > 0 &&
            chainId != signingChain;
      case WalletInitializationNetworkState.unavailable:
        return chainId == null && (!transportUncertain || !connected);
    }
  }
}

/// Retains partial originals without cleanup, deletion, retry or replacement.
class WalletInitializationOutcome {
  /// Retains partial work and failures even when startup could not publish.
  WalletInitializationOutcome({
    required this.published,
    required this.initialized,
    required Iterable<WalletInitializationOperation> operations,
    this.file,
    this.data,
    this.startupAdmitted = false,
    this.startupAdmission,
    this.connection,
    this.error,
    this.stackTrace,
  }) : operations = List<WalletInitializationOperation>.unmodifiable(
         operations,
       );

  /// Whether the captured owner installed the original local wallet state.
  final bool published;

  /// Whether all required local steps completed with that publication.
  final bool initialized;

  /// Source admission is separate from the retained first worker cycle.
  final bool startupAdmitted;

  /// The original worker-start reservation, never a replacement service.
  final Object? startupAdmission;

  /// The original transport observation, independent of local success.
  final WalletInitializationConnection? connection;

  /// The exact created or decrypted file, including a retained partial file.
  final Object? file;

  /// The prepared private membership, if derivation completed.
  final WalletInitializationData? data;

  /// Ordered actual asynchronous steps and their retained outcomes.
  final List<WalletInitializationOperation> operations;

  /// The original failure; partial files are retained rather than recreated.
  final Object? error;

  /// The original trace for [error].
  final StackTrace? stackTrace;

  /// Completed local creation can be displayed without clearing an uncertain
  /// original transport's quarantine or claiming network readiness.
  bool get canShowQuarantinedReady =>
      published &&
      initialized &&
      file != null &&
      data != null &&
      error == null &&
      connection?.state == WalletInitializationNetworkState.unavailable &&
      connection?.connected == false &&
      connection?.chainId == null &&
      connection?.transportUncertain == true;
}

/// One once-only initialization attempt, retained independently of its route.
class WalletInitializationRun {
  WalletInitializationRun._();
  final Completer<WalletInitializationOutcome> _completion =
      Completer<WalletInitializationOutcome>();
  final List<WalletInitializationOperation> _operations =
      <WalletInitializationOperation>[];

  /// Settles once with local completion or retained partial originals.
  Future<WalletInitializationOutcome> get completion => _completion.future;

  /// An immutable view of the actual asynchronous steps admitted so far.
  List<WalletInitializationOperation> get operations =>
      List<WalletInitializationOperation>.unmodifiable(_operations);

  /// The retained terminal outcome, or null while the original is unfinished.
  WalletInitializationOutcome? outcome;

  /// Reserves evidence before invoking a step that may reenter its owner.
  Future<T> observe<T>(String name, Future<T> Function() call) {
    final WalletInitializationOperation operation =
        WalletInitializationOperation(name);
    _operations.add(operation);
    return operation.run<T>(call);
  }
}

/// Derives private startup data from the exact admitted file.
typedef WalletInitializationPrepare =
    Future<WalletInitializationData> Function(
      Object file,
      WalletInitializationRun run,
    );

/// Writes startup data through the originally captured stores and cipher key.
typedef WalletInitializationPersist =
    Future<void> Function(
      Object file,
      WalletInitializationData data,
      List<int> cipherKey,
      WalletInitializationRun run,
    );

/// Separates one strict startup from its committed service lifetime.
/// Ordinary lock cannot revive startup or any previously captured cycle.
class WalletInitializationLifetime {
  /// Captures independent startup, commit and original-owner proofs.
  WalletInitializationLifetime({
    required this._startupIsCurrent,
    required this._committedSourceIsCurrent,
    required this._ownerIsCurrent,
  });

  final bool Function() _startupIsCurrent;
  final bool Function() _committedSourceIsCurrent;
  final bool Function() _ownerIsCurrent;
  bool _handoffAttempted = false;
  bool _handedOff = false;
  bool _revoked = false;

  bool _accept(bool Function() proof) {
    try {
      if (proof() && !_revoked) {
        return true;
      }
    } on Object {
      // An unproven original owner cannot regain admission later.
    }
    _revoked = true;
    return false;
  }

  /// Uses strict startup authority until the exact committed handoff.
  /// Any observed ownership loss permanently refuses later admission.
  bool get isCurrent {
    if (_revoked) {
      return false;
    }
    return _accept(_handedOff ? _ownerIsCurrent : _startupIsCurrent);
  }

  /// Transfers admission once, after synchronous original publication.
  /// This neither starts another handler nor resumes a paused owner.
  bool handoff() {
    if (_handoffAttempted || _revoked) {
      return false;
    }
    _handoffAttempted = true;
    if (!isCurrent ||
        !_accept(_committedSourceIsCurrent) ||
        !_accept(_ownerIsCurrent)) {
      return false;
    }
    _handedOff = true;
    return isCurrent;
  }
}

/// A finite injected protocol. It owns no SDK, file, Box, network or widget.
/// Production captures each capability before the first creation/decrypt await.
class WalletInitializationBinding {
  /// Binds startup capabilities before creation or authentication can suspend.
  WalletInitializationBinding({
    required this.identity,
    required this.connectionOwner,
    required this._isCurrent,
    required this._begin,
    required this._prepare,
    required this._persist,
    required this._connect,
    required this._admitLocal,
    required this._activate,
    required this._publish,
    this._startupAdmission,
    this._startupAdmissionReceipt,
    Future<void> Function(Object, Future<void> Function())? protect,
  }) : _protect = protect ?? _unprotected;
  static Future<void> _unprotected(Object _, Future<void> Function() action) =>
      action();
  static final Expando<WalletInitializationRun> _originals =
      Expando<WalletInitializationRun>();

  /// Original owner used for once-only admission across remounts.
  final Object identity;

  /// Original transport identity required in the connection receipt.
  final Object connectionOwner;
  final Object? _startupAdmission;
  final Object? Function()? _startupAdmissionReceipt;

  /// The original admission created at begin, without a later global lookup.
  Object? get startupAdmission =>
      _startupAdmissionReceipt?.call() ?? _startupAdmission;
  final bool Function() _isCurrent;
  final void Function() _begin;
  final WalletInitializationPrepare _prepare;
  final WalletInitializationPersist _persist;
  final Future<WalletInitializationConnection> Function(WalletInitializationRun)
  _connect;
  final bool Function(WalletInitializationConnection) _admitLocal;
  final bool Function() _activate;
  final Future<void> Function(Object, Future<void> Function()) _protect;
  final bool Function(Object, WalletInitializationData) _publish;
  bool _retired = false;

  /// Remains revoked after any captured capability is observed replaced.
  bool get isCurrent {
    if (_retired) return false;
    try {
      final bool valid = _isCurrent();
      _retired = _retired || !valid;
      return !_retired;
    } on Object {
      _retired = true;
      return false;
    }
  }

  /// Refuses work rather than looking up or adopting replacement resources.
  void requireCurrent() {
    if (!isCurrent) throw const WalletInitializationRefused('source');
  }

  /// Reserves before the factory can synchronously reenter a remounted owner.
  /// A partial or uncertain original can never start another wallet file.
  WalletInitializationRun start({
    required Future<Object> Function() create,
    required List<int> cipherKey,
  }) {
    final WalletInitializationRun? existing = _originals[identity];
    if (existing != null) return existing;
    final WalletInitializationRun run = WalletInitializationRun._();
    _originals[identity] = run;
    final List<int> originalKey = List<int>.unmodifiable(cipherKey);
    unawaited(_execute(run, create, originalKey));
    return run;
  }

  Future<void> _execute(
    WalletInitializationRun run,
    Future<Object> Function() create,
    List<int> key,
  ) async {
    Object? file;
    WalletInitializationData? data;
    WalletInitializationConnection? observedConnection;
    bool initialized = false;
    bool startupAdmitted = false;
    bool published = false;
    Object? error;
    StackTrace? trace;
    try {
      requireCurrent();
      _begin();
      requireCurrent();
      file = await run.observe<Object>('file', create);
      requireCurrent();
      final Object originalFile = file;
      await run.observe<void>(
        'protected-initialization',
        () => _protect(originalFile, () async {
          final WalletInitializationData originalData = await run
              .observe<WalletInitializationData>(
                'prepare',
                () => _prepare(originalFile, run),
              );
          data = originalData;
          requireCurrent();
          if (originalData.members.isEmpty ||
              originalData.members.toSet().length !=
                  originalData.members.length ||
              !originalData.members.contains(originalData.selected) ||
              originalData.chainId <= 0 ||
              originalData.path.isEmpty) {
            throw const WalletInitializationRefused('membership');
          }
          await run.observe<void>(
            'persist',
            () => _persist(originalFile, originalData, key, run),
          );
          requireCurrent();
          final WalletInitializationConnection connection = await run
              .observe<WalletInitializationConnection>(
                'connect',
                () => _connect(run),
              );
          observedConnection = connection;
          requireCurrent();
          if (!identical(connection.owner, connectionOwner) ||
              !connection.permitsLocalInitialization(originalData.chainId) ||
              !_admitLocal(connection)) {
            throw const WalletInitializationRefused('connection');
          }
          requireCurrent();
          // This is source admission. Its retained first-cycle result is a
          // separate proof, deferred until this publication stack unwinds.
          if (!_activate()) {
            throw const WalletInitializationRefused('activation');
          }
          startupAdmitted = true;
          requireCurrent();
          published = _publish(originalFile, originalData);
          if (!published) {
            throw const WalletInitializationRefused('publication');
          }
          initialized = true;
        }),
      );
    } on Object catch (value, stack) {
      error = value;
      trace = stack;
      _retired = true;
      initialized = false;
    }
    final WalletInitializationOutcome outcome = WalletInitializationOutcome(
      initialized: initialized,
      published: published,
      file: file,
      data: data,
      startupAdmitted: startupAdmitted,
      startupAdmission: startupAdmission,
      connection: observedConnection,
      operations: run.operations,
      error: error,
      stackTrace: trace,
    );
    run.outcome = outcome;
    run._completion.complete(outcome);
  }
}
