part of 'node_management.dart';

List<NodeSettingsEntry> _walletNodeEntries() {
  final Set<String> fixed = <String>{
    ...kDefaultNodes,
    ...kDefaultCommunityNodes,
  };
  final Set<String> nodes = <String>{...fixed, ...kDbNodes};
  final String? current = kCurrentNode;
  if (current != null) {
    nodes.add(current);
  }
  return <NodeSettingsEntry>[
    for (final String node in nodes)
      NodeSettingsEntry(
        node: node,
        endpoint: node == kEmbeddedNode ? kLocalhostDefaultNodeUrl : node,
        embedded: node == kEmbeddedNode,
        custom: !fixed.contains(node) && kDbNodes.contains(node),
      ),
  ];
}

String _nodeUrl(String node) =>
    node == kEmbeddedNode ? kLocalhostDefaultNodeUrl : node;

List<Object?> _nodeServiceOwners() => <Object?>[
  if (app.sl.isRegistered<Zenon>()) app.sl<Zenon>() else null,
  if (app.sl.isRegistered<HtlcSwapsService>())
    app.sl<HtlcSwapsService>()
  else
    null,
  if (app.sl.isRegistered<HtlcSwapsHandler>())
    app.sl<HtlcSwapsHandler>()
  else
    null,
  if (app.sl.isRegistered<AutoUnlockHtlcWorker>())
    app.sl<AutoUnlockHtlcWorker>()
  else
    null,
  if (app.sl.isRegistered<AutoReceiveTxWorker>())
    app.sl<AutoReceiveTxWorker>()
  else
    null,
  if (app.sl.isRegistered<IWeb3WalletService>())
    app.sl<IWeb3WalletService>()
  else
    null,
  if (app.sl.isRegistered<NotificationsBloc>())
    app.sl<NotificationsBloc>()
  else
    null,
  if (app.sl.isRegistered<ReceivePort>(instanceName: 'embeddedStoppedPort'))
    app.sl<ReceivePort>(instanceName: 'embeddedStoppedPort')
  else
    null,
  if (app.sl.isRegistered<Stream<dynamic>>(
    instanceName: 'embeddedStoppedStream',
  ))
    app.sl<Stream<dynamic>>(instanceName: 'embeddedStoppedStream')
  else
    null,
];

class _NodeStoredPreference {
  _NodeStoredPreference.read(Box<dynamic> box, String key)
    : exists = box.containsKey(key),
      value = box.get(key);

  const _NodeStoredPreference.value(this.value) : exists = true;

  final bool exists;
  final Object? value;

  bool matches(Box<dynamic> box, String key) =>
      box.containsKey(key) == exists && box.get(key) == value;

  Future<void> restore(Box<dynamic> box, String key) =>
      exists ? box.put(key, value) : box.delete(key);
}

class _WalletNodeSettingsSession implements NodeSettingsSession {
  _WalletNodeSettingsSession({
    required this.originalTarget,
    required this.onboarding,
    required this.clientChain,
    required Zenon client,
    required this._preferences,
    required Box<dynamic> preferencesBox,
    required this._swaps,
    required this._visible,
    required this._didConnect,
  }) : _client = client,
       _preferencesBox = preferencesBox,
       _selectedPreference = _NodeStoredPreference.read(
         preferencesBox,
         kSelectedNodeKey,
       ),
       _chainPreference = _NodeStoredPreference.read(
         preferencesBox,
         kChainIdKey,
       ),
       _wallet = kWalletFile,
       _walletPath = kWalletPath,
       _address = kSelectedAddress,
       _addresses = List<String?>.of(kDefaultAddressList),
       _expectedNode = originalTarget.node,
       _expectedChain = clientChain,
       _expectedNodeChain = kNodeChainId,
       _expectedRevision = WalletContextRevision.value,
       _socket = client.wsClient,
       _ledgerSource = client.ledger,
       _statsSource = client.stats,
       _embeddedSource = client.embedded,
       _subscribeSource = client.subscribe,
       _htlcSource = client.embedded.htlc,
       _embeddedStopped =
           app.sl.isRegistered<ReceivePort>(instanceName: 'embeddedStoppedPort')
           ? app.sl<ReceivePort>(instanceName: 'embeddedStoppedPort')
           : null,
       _expectedUrl = client.wsClient.url,
       _initialized = kWalletInitCompleted,
       _services = _nodeServiceOwners(),
       _notifications = app.sl.isRegistered<NotificationsBloc>()
           ? app.sl<NotificationsBloc>()
           : null,
       _web3 = app.sl.isRegistered<IWeb3WalletService>()
           ? app.sl<IWeb3WalletService>()
           : null,
       _messages = <NodeSettingsNotice, String>{
         NodeSettingsNotice.connected: currentL10n.nodeSettingsChanged,
         NodeSettingsNotice.added: currentL10n.nodeSettingsAdded,
         NodeSettingsNotice.updated: currentL10n.nodeSettingsUpdated,
         NodeSettingsNotice.deleted: currentL10n.nodeSettingsDeleted,
         NodeSettingsNotice.chainChanged: currentL10n.nodeSettingsChainChanged,
       } {
    _ledgerClient = _ledgerSource.client;
    _statsClient = _statsSource.client;
    _ledger = LedgerApi()..setClient(_ledgerClient);
    _stats = StatsApi()..setClient(_statsClient);
    _expectedSelectedPreference = _selectedPreference;
    _expectedChainPreference = _chainPreference;
  }

  static _WalletNodeSettingsSession? capture({
    required bool Function() visible,
    required VoidCallback didConnect,
    bool onboarding = false,
  }) {
    final Zenon? client = app.zenon;
    final SharedPrefsService? preferences = app.sharedPrefsService;
    final HtlcSwapsService? swaps = app.htlcSwapsService;
    final String? node = kCurrentNode;
    if (client == null ||
        preferences == null ||
        swaps == null ||
        !Hive.isBoxOpen(kSharedPrefsBox) ||
        !app.sl.isRegistered<Zenon>() ||
        !identical(app.sl<Zenon>(), client) ||
        (!onboarding &&
            (node == null ||
                kWalletFile == null ||
                !kWalletInitCompleted ||
                kCurrentPage != Tabs.settings)) ||
        (onboarding && kWalletPath == null) ||
        !visible()) {
      return null;
    }
    final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
    final NodeSettingsOriginalTarget target;
    if (node == null) {
      if (!onboarding ||
          box.containsKey(kSelectedNodeKey) ||
          client.wsClient.status() != WebsocketStatus.uninitialized ||
          client.wsClient.url != null) {
        return null;
      }
      target = const NodeSettingsPristineTarget();
    } else {
      if (box.get(kSelectedNodeKey) != node) return null;
      target = NodeSettingsSelectedTarget(node);
    }
    final _WalletNodeSettingsSession session = _WalletNodeSettingsSession(
      originalTarget: target,
      onboarding: onboarding,
      clientChain: getChainIdentifier(),
      client: client,
      preferences: preferences,
      preferencesBox: box,
      swaps: swaps,
      visible: visible,
      didConnect: didConnect,
    );
    return session.isCurrent ? session : null;
  }

  @override
  final NodeSettingsOriginalTarget originalTarget;
  @override
  String? get node => originalTarget.node;
  final bool onboarding;
  @override
  final int clientChain;

  final Zenon _client;
  final SharedPrefsService _preferences;
  final Box<dynamic> _preferencesBox;
  final _NodeStoredPreference _selectedPreference;
  final _NodeStoredPreference _chainPreference;
  late _NodeStoredPreference _expectedSelectedPreference;
  late _NodeStoredPreference _expectedChainPreference;
  final HtlcSwapsService _swaps;
  final bool Function() _visible;
  final VoidCallback _didConnect;
  final Object? _wallet;
  final String? _walletPath;
  final String? _address;
  final List<String?> _addresses;
  final WsClient _socket;
  final bool _initialized;
  final List<Object?> _services;
  final NotificationsBloc? _notifications;
  final IWeb3WalletService? _web3;
  final LedgerApi _ledgerSource;
  final StatsApi _statsSource;
  final EmbeddedApi _embeddedSource;
  final SubscribeApi _subscribeSource;
  final HtlcApi _htlcSource;
  final ReceivePort? _embeddedStopped;
  final Map<NodeSettingsNotice, String> _messages;
  late final Client _ledgerClient;
  late final Client _statsClient;
  late final LedgerApi _ledger;
  late final StatsApi _stats;
  String? _expectedNode;
  int _expectedChain;
  int? _expectedNodeChain;
  int _expectedRevision;
  String? _expectedUrl;
  bool _revoked = false;
  bool _transportRevoked = false;
  bool _transitionComplete = false;
  NodeTransitionLease? _transition;
  NodeSettingsNetwork? _frontier;
  String? _verifiedNode;
  int? _originalChain;
  bool _capturedOriginal = false;
  bool _spawnedTargetEmbedded = false;
  bool _nodeWriteStarted = false;
  bool _nodeWriteSettled = false;
  bool _nodeWriteVerified = false;
  String? _nodeWriteTarget;
  bool _chainWriteStarted = false;
  bool _chainWriteSettled = false;
  bool _chainWriteVerified = false;
  int? _chainWriteTarget;

  @override
  bool get isCurrent {
    if (_revoked) {
      return false;
    }
    return !(_revoked =
        !_visible() ||
        (!onboarding && kCurrentPage != Tabs.settings) ||
        !_transportCurrent);
  }

  bool get _transportCurrent {
    if (_transportRevoked) {
      return false;
    }
    final NodeTransitionLease? transition = _transition;
    final List<Object?> services = _nodeServiceOwners();
    return !(_transportRevoked =
        kWalletInitCompleted != _initialized ||
        services.length != _services.length ||
        Iterable<int>.generate(
          services.length,
        ).any((int index) => !identical(services[index], _services[index])) ||
        !identical(_wallet, kWalletFile) ||
        _walletPath != kWalletPath ||
        _address != kSelectedAddress ||
        !listEquals(_addresses, kDefaultAddressList) ||
        _expectedNode != kCurrentNode ||
        _expectedChain != getChainIdentifier() ||
        _expectedNodeChain != kNodeChainId ||
        _expectedRevision != WalletContextRevision.value ||
        !identical(_client, app.zenon) ||
        !identical(_preferences, app.sharedPrefsService) ||
        !_preferencesBox.isOpen ||
        !Hive.isBoxOpen(kSharedPrefsBox) ||
        !identical(_preferencesBox, Hive.box<dynamic>(kSharedPrefsBox)) ||
        !identical(_swaps, app.htlcSwapsService) ||
        !identical(_socket, _client.wsClient) ||
        !identical(_ledgerSource, _client.ledger) ||
        !identical(_statsSource, _client.stats) ||
        !identical(_embeddedSource, _client.embedded) ||
        !identical(_subscribeSource, _client.subscribe) ||
        !identical(_htlcSource, _embeddedSource.htlc) ||
        !identical(_ledgerClient, _ledgerSource.client) ||
        !identical(_statsClient, _statsSource.client) ||
        !identical(_ledgerClient, _socket) ||
        !identical(_statsClient, _socket) ||
        !identical(_embeddedSource.client, _socket) ||
        !identical(_subscribeSource.client, _socket) ||
        !identical(_htlcSource.client, _socket) ||
        (transition == null
            ? NodeChange.transitionPending
            : !_transitionComplete && !transition.isOwner) ||
        // Both original APIs must still use this exact original socket.
        // Its expected URL therefore binds all three transport references.
        _socket.url != _expectedUrl);
  }

  void _requireTransport({String? at}) {
    if (!_transportCurrent || (at != null && !_transportAt(at))) {
      throw const NodeSettingsRefused();
    }
  }

  bool _transportAt(String node) =>
      _transportCurrent &&
      _expectedUrl == _nodeUrl(node) &&
      _socket.url == _nodeUrl(node) &&
      _socket.status() == WebsocketStatus.running;

  void _require({String? at}) {
    if (!isCurrent || (at != null && !isAt(at))) {
      throw const NodeSettingsRefused();
    }
  }

  @override
  bool isAt(String node) => isCurrent && _transportAt(node);

  @override
  bool beginTransition() {
    _require();
    final Object? wallet = _wallet;
    if (_transition != null ||
        !OriginalPublications.canChangeTransport(_client) ||
        (wallet == null
            ? !onboarding || _initialized
            : !OriginalPublications.canChangeTransport(wallet))) {
      return false;
    }
    final int before = _expectedRevision;
    final int next = before + 1;
    _expectedRevision = next;
    final NodeTransitionLease? transition = NodeChange.beginTransition();
    if (transition == null) {
      _expectedRevision = before;
      return false;
    }
    _transition = transition;
    return transition.revision == next && transition.isOwner && isCurrent;
  }

  @override
  bool get canRestore =>
      !_transitionComplete &&
      (_transition?.isOwner ?? false) &&
      _transportCurrent;

  @override
  Future<NodeSettingsNetwork?> restoreOriginal() async {
    final String? originalNode = node;
    final int? originalChain = _originalChain;
    if (!canRestore ||
        originalNode == null ||
        _expectedNode != node ||
        originalChain == null ||
        originalChain <= 0) {
      return null;
    }
    if (!await _connect(originalNode, restoring: true)) {
      return null;
    }
    _requireTransport(at: node);
    final Momentum momentum = await _ledger.getFrontierMomentum();
    _requireTransport(at: node);
    if (momentum.chainIdentifier <= 0 ||
        momentum.height <= 0 ||
        momentum.timestamp <= 0 ||
        momentum.chainIdentifier != originalChain) {
      return null;
    }
    final NodeSettingsNetwork original = NodeSettingsNetwork(
      node: originalNode,
      chain: momentum.chainIdentifier,
      height: momentum.height,
    );
    await _restorePreferences();
    _requireTransport(at: node);
    _expectedNodeChain = original.chain;
    kNodeChainId = original.chain;
    if (_spawnedTargetEmbedded) {
      // The legacy starter exposes no positively owned shutdown receipt.
      // Restoring the socket alone cannot qualify this native rollback.
      return null;
    }
    _verifiedNode = node;
    return original;
  }

  Future<void> _restorePreferences() async {
    _requireTransport(at: node);
    if (_nodeWriteStarted) {
      final _NodeStoredPreference target = _NodeStoredPreference.value(
        _nodeWriteTarget,
      );
      if (!_nodeWriteSettled ||
          (!_selectedPreference.matches(_preferencesBox, kSelectedNodeKey) &&
              !target.matches(_preferencesBox, kSelectedNodeKey))) {
        throw const NodeSettingsRefused();
      }
      _nodeWriteVerified = false;
      await _selectedPreference.restore(_preferencesBox, kSelectedNodeKey);
      _requireTransport(at: node);
      if (!_selectedPreference.matches(_preferencesBox, kSelectedNodeKey)) {
        throw const NodeSettingsRefused();
      }
      _expectedSelectedPreference = _selectedPreference;
      _nodeWriteVerified = true;
    }
    if (_chainWriteStarted) {
      final _NodeStoredPreference target = _NodeStoredPreference.value(
        _chainWriteTarget,
      );
      if (!_chainWriteSettled ||
          (!_chainPreference.matches(_preferencesBox, kChainIdKey) &&
              !target.matches(_preferencesBox, kChainIdKey))) {
        throw const NodeSettingsRefused();
      }
      _chainWriteVerified = false;
      await _chainPreference.restore(_preferencesBox, kChainIdKey);
      _requireTransport(at: node);
      if (!_chainPreference.matches(_preferencesBox, kChainIdKey)) {
        throw const NodeSettingsRefused();
      }
      _expectedChainPreference = _chainPreference;
      _chainWriteVerified = true;
    }
    _requirePreferences();
  }

  void _requirePreferences() {
    _requireTransport();
    if ((_nodeWriteStarted && !_nodeWriteVerified) ||
        (_chainWriteStarted && !_chainWriteVerified) ||
        !_expectedSelectedPreference.matches(
          _preferencesBox,
          kSelectedNodeKey,
        ) ||
        !_expectedChainPreference.matches(_preferencesBox, kChainIdKey)) {
      throw const NodeSettingsRefused();
    }
  }

  @override
  void completeTransition() {
    final NodeTransitionLease? transition = _transition;
    final String? selected = _expectedNode;
    if (!canRestore ||
        selected == null ||
        transition == null ||
        _verifiedNode != _expectedNode ||
        !_transportAt(selected)) {
      throw const NodeSettingsRefused();
    }
    _requirePreferences();
    final int before = _expectedRevision;
    _expectedRevision = before + 1;
    _transitionComplete = true;
    if (!transition.complete()) {
      _expectedRevision = before;
      _transportRevoked = true;
      throw const NodeSettingsRefused();
    }
    _requireTransport(at: _expectedNode);
  }

  Future<bool> _initialize(String target, {required bool restoring}) async {
    void requireCurrent() {
      if (restoring) {
        _requireTransport();
      } else {
        _require();
      }
    }

    requireCurrent();
    final String? before = _expectedUrl;
    // This explicit action moves the original socket to its chosen URL.
    // Later checks bind to that target, rather than the previous URL.
    _expectedUrl = target;
    try {
      final bool connected = await _socket.initialize(target, retry: false);
      if (_socket.url == before && !connected) {
        _expectedUrl = before;
      }
      requireCurrent();
      return connected;
    } on Object {
      if (_socket.url == before) {
        _expectedUrl = before;
      }
      rethrow;
    }
  }

  @override
  Future<bool> connect(String node) {
    if (!canRestore) {
      throw const NodeSettingsRefused();
    }
    return _connect(node, restoring: false);
  }

  Future<bool> _connect(String node, {required bool restoring}) async {
    void requireCurrent({String? at}) {
      if (restoring) {
        if (!canRestore) {
          throw const NodeSettingsRefused();
        }
        _requireTransport(at: at);
      } else {
        _require(at: at);
      }
    }

    requireCurrent();
    if (!restoring && !_capturedOriginal) {
      _capturedOriginal = true;
      final String? originalNode = this.node;
      if (originalNode != null && _transportAt(originalNode)) {
        try {
          final Momentum original = await _ledger.getFrontierMomentum();
          requireCurrent(at: this.node);
          if (original.chainIdentifier > 0 &&
              original.height > 0 &&
              original.timestamp > 0) {
            _originalChain ??= original.chainIdentifier;
          }
        } on Object {
          requireCurrent();
        }
      }
    }
    if (_transportAt(node) && !_socket.isClosed()) return true;
    final bool heldWakeLock = await WakelockPlus.enabled;
    requireCurrent();
    if (!heldWakeLock) {
      await WakelockPlus.enable();
      requireCurrent();
    }
    final String target = _nodeUrl(node);
    bool connected = await _initialize(target, restoring: restoring);
    requireCurrent();
    if (node == kEmbeddedNode) {
      if (!connected) {
        final ReceivePort? stopped = _embeddedStopped;
        if (stopped == null) throw const NodeSettingsRefused();
        requireCurrent();
        if (!restoring) {
          _spawnedTargetEmbedded = true;
        }
        await NodeUtils.startEmbeddedNode(
          stoppedPort: stopped,
          requireCurrent: requireCurrent,
        );
        requireCurrent();
        connected = await _initialize(target, restoring: restoring);
        requireCurrent();
      }
    } else if (connected) {
      await NodeUtils.closeEmbeddedNode(requireCurrent: requireCurrent);
      requireCurrent(at: node);
    }
    return connected;
  }

  @override
  Future<NodeSettingsNetwork> readFrontier(String node) async {
    _require(at: node);
    final Momentum momentum = await _ledger.getFrontierMomentum();
    _require(at: node);
    if (momentum.chainIdentifier <= 0 ||
        momentum.height <= 0 ||
        momentum.timestamp <= 0) {
      throw const NodeSettingsRefused();
    }
    if (node == this.node && _expectedNode == this.node) {
      _originalChain ??= momentum.chainIdentifier;
    }
    return _frontier = NodeSettingsNetwork(
      node: node,
      chain: momentum.chainIdentifier,
      height: momentum.height,
    );
  }

  @override
  Future<NodeSettingsNetwork> readNetwork() async {
    final String? selected = _expectedNode;
    if (selected == null) throw const NodeSettingsRefused();
    final NodeSettingsNetwork frontier = await readFrontier(selected);
    _require(at: selected);
    List<NodeSettingsPeer>? peers;
    bool? synced;
    try {
      final NetworkInfo network = await _stats.networkInfo();
      _require(at: selected);
      peers = <NodeSettingsPeer>[
        for (final Peer peer in network.peers)
          NodeSettingsPeer(ip: peer.ip, publicKey: peer.publicKey),
      ];
    } on Object {
      _require(at: selected);
    }
    try {
      final SyncInfo sync = await _stats.syncInfo();
      _require(at: selected);
      if (sync.state == SyncState.syncDone) {
        synced = true;
      } else if (sync.currentHeight > 0 && sync.targetHeight > 0) {
        synced = false;
      }
    } on Object {
      _require(at: selected);
    }
    return NodeSettingsNetwork(
      node: selected,
      chain: frontier.chain,
      height: frontier.height,
      synced: synced,
      peers: peers,
    );
  }

  @override
  Future<void> resetCheckpoint() async {
    _require();
    // Each chain owns its cursor; an absent cursor starts an unscanned chain.
    // Changing nodes must not erase the retained height and hash of another.
    _require();
  }

  @override
  Future<void> saveNode(String node) async {
    _require(at: node);
    _requirePreferences();
    _nodeWriteStarted = true;
    _nodeWriteTarget = node;
    try {
      await _preferencesBox.put(kSelectedNodeKey, node);
    } finally {
      _nodeWriteSettled = true;
    }
    _requireTransport(at: node);
    final _NodeStoredPreference saved = _NodeStoredPreference.value(node);
    if (!saved.matches(_preferencesBox, kSelectedNodeKey)) {
      throw const NodeSettingsRefused();
    }
    _expectedSelectedPreference = saved;
    _nodeWriteVerified = true;
    _require(at: node);
  }

  @override
  void publishNode(String node, int chain) {
    _require(at: node);
    _requirePreferences();
    if (_frontier?.node != node || _frontier?.chain != chain) {
      throw const NodeSettingsRefused();
    }
    final int nextRevision = _expectedRevision + 1;
    _expectedNodeChain = chain;
    kNodeChainId = chain;
    kCurrentNode = node;
    _expectedNode = node;
    _expectedRevision = nextRevision;
    NodeChange.announce();
    if (_transportCurrent) {
      _verifiedNode = node;
    }
  }

  @override
  Future<void> saveClientChain(int chain) async {
    final String? originalNode = node;
    if (originalNode == null) throw const NodeSettingsRefused();
    _require(at: originalNode);
    _requirePreferences();
    _chainWriteStarted = true;
    _chainWriteTarget = chain;
    try {
      await _preferencesBox.put(kChainIdKey, chain);
    } finally {
      _chainWriteSettled = true;
    }
    _requireTransport(at: node);
    final _NodeStoredPreference saved = _NodeStoredPreference.value(chain);
    if (!saved.matches(_preferencesBox, kChainIdKey)) {
      throw const NodeSettingsRefused();
    }
    _expectedChainPreference = saved;
    _chainWriteVerified = true;
    _require(at: node);
  }

  @override
  void publishClientChain(int chain) {
    final String? originalNode = node;
    if (originalNode == null) throw const NodeSettingsRefused();
    _require(at: originalNode);
    _requirePreferences();
    if (_frontier?.node != node) {
      throw const NodeSettingsRefused();
    }
    final int nextRevision = _expectedRevision + 1;
    setChainIdentifier(chainIdentifier: chain);
    _expectedChain = chain;
    _expectedRevision = nextRevision;
    WalletContextRevision.invalidate();
    if (_transportCurrent) {
      _verifiedNode = node;
    }
  }

  @override
  Future<void> emitClientChain(int chain) async {
    final String? originalNode = node;
    if (originalNode == null) throw const NodeSettingsRefused();
    _require(at: originalNode);
    final IWeb3WalletService? service = _web3;
    if (service == null) return;
    await service.emitChainIdChangeEvent(chain.toString());
    _require(at: node);
  }

  @override
  Future<List<NodeSettingsEntry>> storeNode({
    String? original,
    String? replacement,
  }) async {
    _require();
    final Box<String> box = Hive.isBoxOpen(kNodesBox)
        ? Hive.box<String>(kNodesBox)
        : await Hive.openBox<String>(kNodesBox);
    _require();
    void requireBox() {
      _require();
      if (!Hive.isBoxOpen(kNodesBox) ||
          !identical(box, Hive.box<String>(kNodesBox))) {
        throw const NodeSettingsRefused();
      }
    }

    requireBox();
    if (original == null) {
      if (replacement == null || box.values.contains(replacement)) {
        throw const NodeSettingsRefused();
      }
      await box.add(replacement);
    } else {
      Object? originalKey;
      for (final Object? key in box.keys) {
        if (box.get(key) == original) {
          originalKey = key;
          break;
        }
      }
      if (originalKey == null) {
        throw const NodeSettingsRefused();
      }
      requireBox();
      if (replacement == null) {
        await box.delete(originalKey);
      } else {
        if (box.values.any(
          (String value) => value == replacement && value != original,
        )) {
          throw const NodeSettingsRefused();
        }
        await box.put(originalKey, replacement);
      }
    }
    requireBox();
    await NodeUtils.loadDbNodes(isCurrent: () => isCurrent);
    requireBox();
    return _walletNodeEntries();
  }

  @override
  Future<void> notify(NodeSettingsNotice notice) async {
    _require();
    final String message = _messages[notice]!;
    final NotificationsBloc? notifications = _notifications;
    if (notifications == null) return;
    await notifications.addNotification(
      WalletNotification(
        title: message,
        details: null,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: NotificationType.changedNode,
      ),
    );
    _require();
  }

  @override
  void didConnect() {
    _require(at: _expectedNode);
    _didConnect();
  }
}
