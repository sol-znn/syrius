import 'package:flutter_bloc/flutter_bloc.dart';

/// One saved node identity. A label never replaces its exact endpoint.
class NodeSettingsEntry {
  /// [node] is the persisted identity, including the embedded-node sentinel.
  const NodeSettingsEntry({
    required this.node,
    required this.endpoint,
    this.embedded = false,
    this.custom = false,
  });

  /// The value used for selection and persistence.
  final String node;

  /// The connection URL shown as data.
  final String endpoint;

  /// Whether selecting this row retains embedded-node startup semantics.
  final bool embedded;

  /// Only an entry owned by the custom catalog can be edited or deleted.
  final bool custom;
}

/// An immutable peer reported by the selected node.
class NodeSettingsPeer {
  /// Copies only the two facts the peer table presents.
  const NodeSettingsPeer({required this.ip, required this.publicKey});

  /// The node's reported peer address.
  final String ip;

  /// The full reported peer identifier.
  final String publicKey;
}

/// Facts from one explicitly bound connected node, never from other rows.
class NodeSettingsNetwork {
  /// Missing values remain unknown, including a missing peer list.
  NodeSettingsNetwork({
    required this.node,
    required this.chain,
    required this.height,
    this.synced,
    List<NodeSettingsPeer>? peers,
  }) : peers = peers == null
           ? null
           : List<NodeSettingsPeer>.unmodifiable(peers);

  /// The exact selected node that supplied this answer.
  final String node;

  /// The frontier's chain, separate from the client's signing chain.
  final int chain;

  /// The reported frontier height.
  final int height;

  /// Null until this same node successfully reports its sync state.
  final bool? synced;

  /// Null is unknown. An empty successful answer establishes zero peers.
  final List<NodeSettingsPeer>? peers;
}

/// The immutable mismatch shown before accepting a different node chain.
class NodeSettingsMismatch {
  /// A later selection cannot rewrite this question.
  const NodeSettingsMismatch({
    required this.node,
    required this.nodeChain,
    required this.clientChain,
  });

  /// The originally selected endpoint identity.
  final String node;

  /// The connected node's actual frontier chain.
  final int nodeChain;

  /// The signing chain captured before connecting.
  final int clientChain;
}

/// Events use short localized text at the production boundary.
enum NodeSettingsNotice {
  /// An explicitly accepted node was persisted and announced.
  connected,

  /// A custom endpoint was added to the catalog.
  added,

  /// A custom endpoint was changed without changing the connection.
  updated,

  /// A custom endpoint was removed from the catalog.
  deleted,

  /// The independently selected signing chain was saved.
  chainChanged,
}

/// A view-level failure, never a library's raw diagnostic text.
enum NodeSettingsFailure {
  /// The original transport, wallet or visible surface no longer owns work.
  stale,

  /// An explicit connection or rollback did not complete successfully.
  connection,

  /// The original catalog or preference write failed.
  save,

  /// This exact endpoint already exists.
  duplicate,

  /// The input is not an explicit supported node URL or positive chain.
  invalid,
}

/// The original transport target, before an explicit node transition begins.
sealed class NodeSettingsOriginalTarget {
  /// Only the selected and pristine variants can represent an original target.
  const NodeSettingsOriginalTarget();

  /// Null is a pristine transport, never an empty or invented endpoint.
  String? get node;
}

/// An actual selected node whose original chain may be positively restored.
final class NodeSettingsSelectedTarget extends NodeSettingsOriginalTarget {
  /// Retains the exact saved node identity, including the embedded sentinel.
  const NodeSettingsSelectedTarget(this.node);

  @override
  final String node;
}

/// No saved selection and no prior initialized socket exist for onboarding.
final class NodeSettingsPristineTarget extends NodeSettingsOriginalTarget {
  /// Requires production to verify absent preference and pristine socket state.
  const NodeSettingsPristineTarget();

  @override
  String? get node => null;
}

/// Operations captured together before an action crosses an async boundary.
/// Production binds real APIs; presentation tests provide every dependency.
abstract interface class NodeSettingsSession {
  /// Distinguishes a real prior node from positively pristine onboarding.
  NodeSettingsOriginalTarget get originalTarget;

  /// The original node, or null for a positively pristine onboarding transport.
  String? get node;

  /// The independently captured signing chain.
  int get clientChain;

  /// Once observed stale, this session can never become current again.
  bool get isCurrent;

  /// Checks exact source and client URLs after an intentional connection.
  bool isAt(String node);

  /// Quarantines an uncommitted node or signing-preference transition.
  bool beginTransition();

  /// Cleanup ignores page visibility but retains exact wallet/transport owner.
  bool get canRestore;

  /// Verifies the original node and restores only its own preference writes.
  Future<NodeSettingsNetwork?> restoreOriginal();

  /// Only a verified commit or original-node restoration releases quarantine.
  void completeTransition();

  /// Uses the existing real connection and embedded-node lifecycle.
  Future<bool> connect(String node);

  /// A strict frontier read, with no fallback chain identifier.
  Future<NodeSettingsNetwork> readFrontier(String node);

  /// Reads connected-node facts, never probes an inactive catalog row.
  Future<NodeSettingsNetwork> readNetwork();

  /// Resets the existing HTLC checkpoint before persisting a new node.
  Future<void> resetCheckpoint();

  /// Saves the chosen identity, retaining its original preference for rollback.
  Future<void> saveNode(String node);

  /// Updates globals and then announces exactly one accepted node change.
  void publishNode(String node, int chain);

  /// Saves a deliberately chosen client signing chain.
  Future<void> saveClientChain(int chain);

  /// Changes the signing chain and revokes earlier wallet contexts.
  void publishClientChain(int chain);

  /// Retains the existing connected-app chain-change event.
  Future<void> emitClientChain(int chain);

  /// A null original adds a node; a null replacement deletes one.
  Future<List<NodeSettingsEntry>> storeNode({
    String? original,
    String? replacement,
  });

  /// An observer failure cannot turn an accepted connection into a failure.
  Future<void> notify(NodeSettingsNotice notice);

  /// The existing return-to-wallet callback after successful notification.
  void didConnect();
}

/// The section's immutable presentation state.
class NodeSettingsState {
  /// The injected initial catalog establishes no network facts.
  NodeSettingsState({
    required List<NodeSettingsEntry> entries,
    required this.activeNode,
    required this.clientChain,
    this.network,
    this.pendingNode,
    this.busy = false,
    this.failure,
  }) : entries = List<NodeSettingsEntry>.unmodifiable(entries);

  /// An exact, deduplicated catalog, with no manufactured example rows.
  final List<NodeSettingsEntry> entries;

  /// The committed selected node, not a radio choice awaiting connection.
  final String? activeNode;

  /// The wallet's independent signing chain.
  final int clientChain;

  /// The answer whose producing session is retained by the presenter.
  final NodeSettingsNetwork? network;

  /// The captured endpoint whose connection is underway.
  final String? pendingNode;

  /// One mutation at a time, including while a question is open.
  final bool busy;

  /// A short actionable failure mapped by the view.
  final NodeSettingsFailure? failure;

  /// Copies state with explicit null clearing for revoked facts.
  NodeSettingsState copyWith({
    List<NodeSettingsEntry>? entries,
    String? activeNode,
    int? clientChain,
    NodeSettingsNetwork? network,
    String? pendingNode,
    bool? busy,
    NodeSettingsFailure? failure,
    bool clearNetwork = false,
    bool clearPending = false,
    bool clearFailure = false,
  }) => NodeSettingsState(
    entries: entries ?? this.entries,
    activeNode: activeNode ?? this.activeNode,
    clientChain: clientChain ?? this.clientChain,
    network: clearNetwork ? null : network ?? this.network,
    pendingNode: clearPending ? null : pendingNode ?? this.pendingNode,
    busy: busy ?? this.busy,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

/// A refusal before the next side effect; it contains no wallet data.
class NodeSettingsRefused implements Exception {
  /// The original action lost its authority.
  const NodeSettingsRefused();
}

/// Explicit node changes and catalog writes over injected original sessions.
class NodeSettingsPresenter extends Cubit<NodeSettingsState> {
  /// The capture callback retains a failed original session's identity.
  NodeSettingsPresenter({
    required NodeSettingsState initial,
    required this._capture,
  }) : super(initial);

  final NodeSettingsSession? Function() _capture;
  NodeSettingsSession? _networkSession;
  int _epoch = 0;
  int _read = 0;
  bool _visible = true;
  bool _reading = false;
  bool _committing = false;
  Object? _lastError;
  StackTrace? _lastStack;

  /// Captured by UI callbacks so an old surface cannot act after returning.
  int get authorityEpoch => _epoch;

  /// The owner skips its own synchronous context-announcement listener.
  bool get committing => _committing;

  /// Opening an unrelated route or leaving the page revokes its work.
  bool get visible => _visible;

  /// Original failures remain available without rendering raw diagnostics.
  Object? get lastError => _lastError;

  /// The original stack is preserved with [lastError].
  StackTrace? get lastStack => _lastStack;

  /// A stale session cannot keep old node facts painted until another read.
  NodeSettingsNetwork? get currentNetwork {
    final NodeSettingsSession? session = _networkSession;
    final String? node = state.activeNode;
    return _visible &&
            session != null &&
            session.isCurrent &&
            node != null &&
            session.isAt(node)
        ? state.network
        : null;
  }

  /// Revocation is monotonic even when the visible surface soon returns.
  void setVisible({required bool visible}) {
    if (_visible == visible || isClosed) {
      return;
    }
    _visible = visible;
    if (!visible) {
      invalidate();
    }
  }

  /// Drops paint and callback authority without starting a new operation.
  void invalidate() {
    if (isClosed) {
      return;
    }
    _epoch++;
    _read++;
    _networkSession = null;
    emit(state.copyWith(clearNetwork: true, clearFailure: true));
  }

  bool _current(NodeSettingsSession session, int epoch) =>
      !isClosed && _visible && epoch == _epoch && session.isCurrent;

  void _require(NodeSettingsSession session, int epoch, {String? at}) {
    if (!_current(session, epoch) || (at != null && !session.isAt(at))) {
      throw const NodeSettingsRefused();
    }
  }

  NodeSettingsSession? _begin(int epoch) {
    if (isClosed || !_visible || state.busy || epoch != _epoch) {
      return null;
    }
    final NodeSettingsSession? session = _capture();
    if (session == null ||
        !session.isCurrent ||
        session.node != state.activeNode ||
        session.clientChain != state.clientChain) {
      return null;
    }
    _read++;
    _networkSession = null;
    _lastError = null;
    _lastStack = null;
    emit(state.copyWith(busy: true, clearFailure: true, clearNetwork: true));
    return session;
  }

  void _failed(Object error, StackTrace stack, NodeSettingsFailure kind) {
    _lastError = error;
    _lastStack = stack;
    if (!isClosed) {
      emit(state.copyWith(failure: kind, clearNetwork: true));
    }
  }

  void _finish() {
    if (!isClosed) {
      emit(state.copyWith(busy: false, clearPending: true));
    }
  }

  Future<void> _notify(
    NodeSettingsSession session,
    int epoch,
    NodeSettingsNotice notice,
  ) async {
    if (!_current(session, epoch)) {
      return;
    }
    try {
      await session.notify(notice);
    } on Object catch (error, stack) {
      _lastError = error;
      _lastStack = stack;
    }
  }

  /// Refreshes the connected node only. Failure establishes no zero values.
  Future<void> refresh() async {
    if (isClosed || !_visible || state.busy || _reading) {
      return;
    }
    final NodeSettingsSession? session = _capture();
    if (session == null || !session.isCurrent) {
      return;
    }
    if (session.node != state.activeNode ||
        session.clientChain != state.clientChain) {
      emit(
        state.copyWith(
          activeNode: session.node,
          clientChain: session.clientChain,
          clearNetwork: true,
        ),
      );
    }
    final String? originalNode = session.node;
    if (originalNode == null || !session.isAt(originalNode)) {
      return;
    }
    final int epoch = _epoch;
    final int read = ++_read;
    _reading = true;
    try {
      final NodeSettingsNetwork network = await session.readNetwork();
      _require(session, epoch, at: originalNode);
      if (read != _read || network.node != originalNode) {
        return;
      }
      _networkSession = session;
      emit(
        state.copyWith(
          activeNode: session.node,
          clientChain: session.clientChain,
          network: network,
        ),
      );
    } on Object catch (error, stack) {
      if (!isClosed && read == _read) {
        _failed(error, stack, NodeSettingsFailure.connection);
      }
    } finally {
      _reading = false;
    }
  }

  Future<bool> _restore(NodeSettingsSession session, int epoch) async {
    if (!session.canRestore ||
        session.originalTarget is NodeSettingsPristineTarget) {
      return false;
    }
    final NodeSettingsNetwork? original = await session.restoreOriginal();
    if (original == null ||
        original.node != session.node ||
        !session.canRestore) {
      return false;
    }
    _completeTransition(session);
    final String? originalNode = session.node;
    if (_current(session, epoch) &&
        originalNode != null &&
        session.isAt(originalNode)) {
      _networkSession = session;
      emit(state.copyWith(network: original));
    }
    return true;
  }

  void _completeTransition(NodeSettingsSession session) {
    _committing = true;
    try {
      session.completeTransition();
    } finally {
      _committing = false;
    }
  }

  void _acquireTransition(NodeSettingsSession session) {
    bool acquired;
    _committing = true;
    try {
      acquired = session.beginTransition();
    } finally {
      _committing = false;
    }
    if (!acquired) {
      throw const NodeSettingsRefused();
    }
  }

  /// Selection immediately runs the existing connection and consent flow.
  Future<bool> select(
    String node, {
    required int epoch,
    required Future<bool> Function(NodeSettingsMismatch mismatch) question,
    bool confirmCurrent = false,
  }) async {
    if (!state.entries.any((NodeSettingsEntry row) => row.node == node) ||
        (node == state.activeNode && !confirmCurrent)) {
      return false;
    }
    final NodeSettingsSession? session = _begin(epoch);
    if (session == null) {
      return false;
    }
    bool committed = false;
    bool restoring = false;
    emit(state.copyWith(pendingNode: node));
    try {
      _require(session, epoch);
      _acquireTransition(session);
      _require(session, epoch);
      final bool connected = await session.connect(node);
      _require(session, epoch);
      if (!connected) {
        throw const NodeSettingsRefused();
      }
      _require(session, epoch, at: node);
      final NodeSettingsNetwork network = await session.readFrontier(node);
      _require(session, epoch, at: node);
      if (network.node != node || network.chain <= 0 || network.height <= 0) {
        throw const NodeSettingsRefused();
      }
      if (network.chain != session.clientChain) {
        final bool accepted = await question(
          NodeSettingsMismatch(
            node: node,
            nodeChain: network.chain,
            clientChain: session.clientChain,
          ),
        );
        _require(session, epoch, at: node);
        if (!accepted) {
          restoring = true;
          if (!await _restore(session, epoch)) {
            throw const NodeSettingsRefused();
          }
          return false;
        }
      }
      _require(session, epoch, at: node);
      await session.resetCheckpoint();
      _require(session, epoch, at: node);
      await session.saveNode(node);
      _require(session, epoch, at: node);
      _committing = true;
      try {
        session.publishNode(node, network.chain);
      } finally {
        _committing = false;
      }
      committed = true;
      _completeTransition(session);
      _require(session, epoch, at: node);
      _networkSession = session;
      emit(state.copyWith(activeNode: node, network: network));
      await _notify(session, epoch, NodeSettingsNotice.connected);
      if (_current(session, epoch) && session.isAt(node)) {
        session.didConnect();
      }
      return true;
    } on Object catch (error, stack) {
      if (!committed && !restoring && session.canRestore) {
        try {
          await _restore(session, epoch);
        } on Object {
          // A failed restore never authorizes persistence or a success event.
        }
      }
      if (!committed) {
        _failed(
          error,
          stack,
          error is NodeSettingsRefused && !_current(session, epoch)
              ? NodeSettingsFailure.stale
              : NodeSettingsFailure.connection,
        );
      }
      return committed;
    } finally {
      _finish();
    }
  }

  /// Explicit text submission changes signing policy independently of a node.
  Future<bool> changeClientChain(
    int chain, {
    required int epoch,
    bool Function()? isCurrent,
  }) async {
    if (chain <= 0 || chain == state.clientChain) {
      return false;
    }
    final NodeSettingsSession? session = _begin(epoch);
    if (session == null) {
      return false;
    }
    final String? originalNode = session.node;
    if (originalNode == null) {
      _finish();
      return false;
    }
    bool committed = false;
    void requireCurrent() {
      _require(session, epoch, at: originalNode);
      if (!(isCurrent?.call() ?? true)) {
        throw const NodeSettingsRefused();
      }
    }

    try {
      requireCurrent();
      _acquireTransition(session);
      requireCurrent();
      final NodeSettingsNetwork original = await session.readFrontier(
        originalNode,
      );
      requireCurrent();
      if (original.node != session.node ||
          original.chain <= 0 ||
          original.height <= 0) {
        throw const NodeSettingsRefused();
      }
      await session.saveClientChain(chain);
      requireCurrent();
      _committing = true;
      try {
        session.publishClientChain(chain);
      } finally {
        _committing = false;
      }
      committed = true;
      _completeTransition(session);
      requireCurrent();
      emit(state.copyWith(clientChain: chain));
      await session.emitClientChain(chain);
      requireCurrent();
      await _notify(session, epoch, NodeSettingsNotice.chainChanged);
      return true;
    } on Object catch (error, stack) {
      if (!committed && session.canRestore) {
        try {
          await _restore(session, epoch);
        } on Object {
          // Failed preference restoration keeps the original lease held.
        }
      }
      if (committed) {
        _lastError = error;
        _lastStack = stack;
      } else {
        _failed(error, stack, NodeSettingsFailure.save);
      }
      return committed;
    } finally {
      _finish();
    }
  }

  /// Catalog mutation never changes the currently connected endpoint.
  Future<bool> storeNode({
    required int epoch,
    String? original,
    String? replacement,
    bool Function()? isCurrent,
  }) async {
    if (original == null && replacement == null) {
      return false;
    }
    if (original != null &&
        !state.entries.any(
          (NodeSettingsEntry row) => row.node == original && row.custom,
        )) {
      return false;
    }
    if (replacement != null && !isNodeSettingsEndpoint(replacement)) {
      return false;
    }
    if (replacement != null &&
        state.entries.any(
          (NodeSettingsEntry row) =>
              row.node == replacement && row.node != original,
        )) {
      emit(state.copyWith(failure: NodeSettingsFailure.duplicate));
      return false;
    }
    final NodeSettingsSession? session = _begin(epoch);
    if (session == null) {
      return false;
    }
    void requireCurrent() {
      _require(session, epoch);
      if (!(isCurrent?.call() ?? true)) {
        throw const NodeSettingsRefused();
      }
    }

    try {
      requireCurrent();
      final List<NodeSettingsEntry> entries = await session.storeNode(
        original: original,
        replacement: replacement,
      );
      requireCurrent();
      emit(state.copyWith(entries: entries));
      await _notify(
        session,
        epoch,
        original == null
            ? NodeSettingsNotice.added
            : replacement == null
            ? NodeSettingsNotice.deleted
            : NodeSettingsNotice.updated,
      );
      return true;
    } on Object catch (error, stack) {
      _failed(error, stack, NodeSettingsFailure.save);
      return false;
    } finally {
      _finish();
    }
  }

  /// Late futures retain their result but cannot emit after owned closure.
  @override
  Future<void> close() {
    _visible = false;
    _epoch++;
    _read++;
    _networkSession = null;
    return super.close();
  }
}

/// A user-entered node retains an explicit port and has no hidden URL parts.
bool isNodeSettingsEndpoint(String text) {
  final Uri? uri = Uri.tryParse(text);
  return uri != null &&
      text == text.trim() &&
      text.length <= 80 &&
      (uri.scheme == 'ws' || uri.scheme == 'wss') &&
      uri.host.isNotEmpty &&
      uri.hasPort &&
      uri.port > 0 &&
      uri.port <= 65535 &&
      uri.userInfo.isEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}
