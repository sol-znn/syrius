import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';

/// An identity sentinel with no native embedded node behind this fixture.
const String embeddedNode = 'Embedded Node';

/// A reserved example-domain endpoint that is never opened.
const String remoteNode = 'wss://node.example:35998';

/// An inert catalog row representing a different reported chain.
const String customNode = 'ws://127.0.0.1:45998';

/// Three explicit fixture rows, separate from production globals.
const List<NodeSettingsEntry> nodeEntries = <NodeSettingsEntry>[
  NodeSettingsEntry(
    node: embeddedNode,
    endpoint: 'ws://127.0.0.1:35998',
    embedded: true,
  ),
  NodeSettingsEntry(node: remoteNode, endpoint: remoteNode),
  NodeSettingsEntry(node: customNode, endpoint: customNode, custom: true),
];

/// Every operation is an in-memory observation. No SDK object is constructed.
class FakeNodeSettingsSession implements NodeSettingsSession {
  /// The optional origin stays immutable during an intentional target change.
  FakeNodeSettingsSession({this.origin = embeddedNode, this.originalChain = 1})
    : connected = origin,
      selected = origin,
      savedNode = origin;

  /// The original selected identity of this synthetic session.
  final String? origin;

  /// Null means no original node-chain baseline was established.
  final int? originalChain;

  /// Ordered observations, including persistence and observer boundaries.
  final List<String> calls = <String>[];

  /// Explicit deferred operations, completed by the owning test.
  final Map<String, Completer<void>> gates = <String, Completer<void>>{};

  /// The exact entry into a deferred operation.
  final Map<String, Completer<void>> started = <String, Completer<void>>{};

  /// Original error objects thrown without replacement.
  final Map<String, Object> failures = <String, Object>{};

  /// Synthetic responses keyed by exact original node identity.
  final Map<String, int> chains = <String, int>{
    embeddedNode: 1,
    remoteNode: 1,
    customNode: 321,
  };

  /// The in-memory custom catalog.
  List<NodeSettingsEntry> entries = List<NodeSettingsEntry>.of(nodeEntries);

  /// Null and a complete empty list have different meanings.
  List<NodeSettingsPeer>? peers = <NodeSettingsPeer>[
    const NodeSettingsPeer(ip: '192.0.2.10', publicKey: 'peer-b'),
    const NodeSettingsPeer(ip: '192.0.2.11', publicKey: 'peer-a'),
  ];

  /// The intentionally selected fixture transport.
  String? connected;

  /// The committed identity, separate from a pending transport change.
  String? selected;

  /// The selected-node preference, separate from committed globals.
  String? savedNode;

  /// The signing-chain preference, separate from the signing policy.
  int savedChain = 1;

  /// The independent signing chain.
  int signingChain = 1;

  /// Tests may revoke the original session before a gate completes.
  bool authority = true;
  bool _revoked = false;

  /// The synthetic result of an explicit connection request.
  bool connectAnswer = true;

  /// Models a synchronous observer changing authority during announcement.
  void Function()? afterPublish;

  /// A failed or unowned restoration keeps this quarantine held.
  bool transitionHeld = false;

  /// Replacing a lease cannot transfer cleanup authority to this old session.
  bool ownsTransition = true;

  /// A native start with no positively owned shutdown receipt stays unknown.
  bool spawnedUnowned = false;
  String? _writtenNode;
  int? _writtenChain;

  @override
  String? get node => origin;

  @override
  NodeSettingsOriginalTarget get originalTarget {
    final String? original = origin;
    return original == null
        ? const NodeSettingsPristineTarget()
        : NodeSettingsSelectedTarget(original);
  }

  @override
  int get clientChain => 1;

  @override
  bool get isCurrent => !_revoked && !(_revoked = !authority);

  @override
  bool isAt(String node) => isCurrent && connected == node;

  @override
  bool beginTransition() {
    if (transitionHeld || !isCurrent) {
      return false;
    }
    transitionHeld = true;
    calls.add('lease');
    return true;
  }

  @override
  bool get canRestore => transitionHeld && ownsTransition && isCurrent;

  @override
  Future<NodeSettingsNetwork?> restoreOriginal() async {
    final String? node = origin;
    final int? expectedChain = originalChain;
    if (!canRestore ||
        node == null ||
        expectedChain == null ||
        expectedChain <= 0 ||
        !await connect(node) ||
        !canRestore) {
      return null;
    }
    final NodeSettingsNetwork original = await readFrontier(node);
    if (!canRestore || !isAt(node) || original.chain != expectedChain) {
      return null;
    }
    if (_writtenNode != null) {
      if (savedNode != node && savedNode != _writtenNode) {
        return null;
      }
      await _step('restoreNode:$node');
      if (!canRestore) {
        return null;
      }
      savedNode = node;
    }
    if (_writtenChain != null) {
      if (savedChain != clientChain && savedChain != _writtenChain) {
        return null;
      }
      await _step('restoreChain:$clientChain');
      if (!canRestore) {
        return null;
      }
      savedChain = clientChain;
    }
    if (spawnedUnowned) {
      return null;
    }
    calls.add('restored:${original.chain}');
    return original;
  }

  @override
  void completeTransition() {
    if (!canRestore || savedNode != selected || savedChain != signingChain) {
      throw const NodeSettingsRefused();
    }
    calls.add('release');
    transitionHeld = false;
  }

  Future<void> _step(String name) async {
    calls.add(name);
    final Completer<void> observed = started.putIfAbsent(
      name,
      Completer<void>.new,
    );
    if (!observed.isCompleted) {
      observed.complete();
    }
    await gates[name]?.future;
    final Object? failure = failures[name];
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
  }

  /// Waits for an actual fixture operation, rather than elapsed guessed time.
  Future<void> saw(String name) =>
      started.putIfAbsent(name, Completer<void>.new).future;

  @override
  Future<bool> connect(String node) async {
    // The target change is intentional, rather than an old-URL comparison.
    connected = node;
    await _step('connect:$node');
    return connectAnswer;
  }

  @override
  Future<NodeSettingsNetwork> readFrontier(String node) async {
    await _step('frontier:$node');
    return NodeSettingsNetwork(node: node, chain: chains[node]!, height: 123);
  }

  @override
  Future<NodeSettingsNetwork> readNetwork() async {
    final String? requested = selected;
    if (requested == null) throw const NodeSettingsRefused();
    await _step('network:$requested');
    return NodeSettingsNetwork(
      node: requested,
      chain: chains[requested]!,
      height: 123,
      synced: true,
      peers: peers,
    );
  }

  @override
  Future<void> resetCheckpoint() => _step('checkpoint:0');

  @override
  Future<void> saveNode(String node) {
    _writtenNode = node;
    savedNode = node;
    return _step('save:$node');
  }

  @override
  void publishNode(String node, int chain) {
    calls.add('globals:$node:$chain');
    selected = node;
    calls.add('announce');
    afterPublish?.call();
  }

  @override
  Future<void> saveClientChain(int chain) {
    _writtenChain = chain;
    savedChain = chain;
    return _step('saveChain:$chain');
  }

  @override
  void publishClientChain(int chain) {
    signingChain = chain;
    calls.add('clientChain:$chain');
  }

  @override
  Future<void> emitClientChain(int chain) => _step('emitChain:$chain');

  @override
  Future<List<NodeSettingsEntry>> storeNode({
    String? original,
    String? replacement,
  }) async {
    await _step('catalog');
    return entries = <NodeSettingsEntry>[
      for (final NodeSettingsEntry row in entries)
        if (row.node != original) row,
      if (replacement != null)
        NodeSettingsEntry(
          node: replacement,
          endpoint: replacement,
          custom: true,
        ),
    ];
  }

  @override
  Future<void> notify(NodeSettingsNotice notice) =>
      _step('notice:${notice.name}');

  @override
  void didConnect() => calls.add('callback');
}

/// Creates a presenter with no production capture path.
NodeSettingsPresenter nodePresenter(FakeNodeSettingsSession source) =>
    NodeSettingsPresenter(
      initial: NodeSettingsState(
        entries: nodeEntries,
        activeNode: source.node,
        clientChain: 1,
      ),
      capture: () => source,
    );
