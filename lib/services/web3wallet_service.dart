import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/wallet_connect_pairings_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/wallet_connect_sessions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/notification_type.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_service.dart'
    show publicNodeUrl;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_scope.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/pending_session_approval.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Manages the existing WalletConnect client and explicit session decisions.
class Web3WalletService extends IWeb3WalletService
    implements CapturedWeb3WalletService {
  /// Creates the owner; client creation and initialization remain explicit.
  Web3WalletService();

  /// Injects a client without creating, initializing or connecting one.
  @visibleForTesting
  Web3WalletService.withClient(ReownWalletKit client) : _wcClient = client;

  static const Duration _pendingRequestsPollInterval = Duration(seconds: 1);
  static const String _metadataIcon =
      'https://raw.githubusercontent.com/zenon-network/syrius/master/'
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-MacOS-512x512%402x.png';

  final Logger _logger = Logger('WalletConnectService');

  ReownWalletKit? _wcClient;
  bool _disposed = false;
  bool _subscribed = false;
  Timer? _pendingRequestsPollTimer;
  Timer? _sessionRefreshTimer;

  final Set<int> _approvedProposalIds = <int>{};
  final Set<(String, int)> _handledRequestIds = <(String, int)>{};

  @override
  ValueNotifier<List<PairingInfo>> pairings = ValueNotifier<List<PairingInfo>>(
    <PairingInfo>[],
  );

  @override
  ValueNotifier<List<SessionData>> sessions = ValueNotifier<List<SessionData>>(
    <SessionData>[],
  );

  @override
  late final PendingApprovalController pendingApprovals =
      PendingApprovalController(
        isCurrentContext: _isCurrentApprovalContext,
        proposalExists: _proposalExists,
        approve: _approveProposal,
        decline: _declineProposal,
      );

  String? get _approvalScope => bellScopeForWallet(
    getChainIdentifier(),
    kDefaultAddressList.whereType<String>(),
  );

  bool get _isCreated => _wcClient != null;
  String get _namespaceChainId => 'zenon:${getChainIdentifier()}';

  @override
  Future<void> create() async {
    if (_disposed || _wcClient != null) return;
    if (kWcProjectId.isEmpty) {
      _logger.warning('WalletConnect project id missing');
      return;
    }

    _wcClient = ReownWalletKit(
      core: ReownCore(projectId: kWcProjectId),
      metadata: const PairingMetadata(
        name: 's y r i u s',
        description: 'A wallet for interacting with Zenon Network',
        url: 'https://zenon.network',
        icons: <String>[_metadataIcon],
      ),
    );

    _subscribeListeners();
    _subscribed = true;
    _registerRequestHandlers();
    _startPendingRequestsPolling();
  }

  @override
  Future<void> init() async {
    if (!_isCreated) {
      _logger.warning('init called before create');
      return;
    }

    final ReownWalletKit client = _wcClient!;
    await client.init();
    if (!_ownsClient(client)) return;

    pairings.value = List<PairingInfo>.from(client.pairings.getAll());
    sessions.value = List<SessionData>.from(client.sessions.getAll());
    client.getPendingSessionProposals().values.forEach(_enqueueProposal);
  }

  @override
  FutureOr<void> onDispose() {
    _disposed = true;
    _pendingRequestsPollTimer?.cancel();
    _pendingRequestsPollTimer = null;
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;

    if (_wcClient != null && _subscribed) {
      _unsubscribeListeners();
      _subscribed = false;
    }

    _approvedProposalIds.clear();
    _handledRequestIds.clear();
    pendingApprovals
      ..invalidate()
      ..dispose();

    pairings.dispose();
    sessions.dispose();
  }

  @override
  ReownWalletKit getWeb3Wallet() => _requireClient();

  ReownWalletKit _requireClient() {
    final ReownWalletKit? client = _wcClient;
    if (client == null || _disposed) throw StateError('Connection unavailable');
    return client;
  }

  bool _ownsClient(ReownWalletKit client) =>
      !_disposed && identical(client, _wcClient);

  @override
  Web3WalletActions captureActions() {
    final ReownWalletKit client = _requireClient();
    void requireCurrent() {
      if (!_ownsClient(client)) throw StateError('Connection unavailable');
    }

    return Web3WalletActions(
      identity: client,
      isCurrent: () => _ownsClient(client),
      sessions: sessions,
      pairings: pairings,
      activeSessions: () {
        requireCurrent();
        return client.getActiveSessions();
      },
      pair: (Uri uri) {
        requireCurrent();
        return client.pair(uri: uri);
      },
      disconnectSession: (String topic) {
        requireCurrent();
        return client.disconnectSession(
          topic: topic,
          reason: Errors.getSdkError(Errors.USER_DISCONNECTED).toSignError(),
        );
      },
      disconnectPairing: (String topic) {
        requireCurrent();
        return _disconnectPairing(client, topic);
      },
    );
  }

  @override
  Future<PairingInfo> pair(Uri uri) {
    final ReownWalletKit client = _requireClient();
    return client.pair(uri: uri);
  }

  @override
  Future<void> activatePairing({
    required String topic,
  }) {
    final ReownWalletKit client = _requireClient();
    return client.core.pairing.activate(topic: topic);
  }

  @override
  Future<void> deactivatePairing({
    required String topic,
  }) => _disconnectPairing(_requireClient(), topic);

  Future<void> _disconnectPairing(ReownWalletKit client, String topic) async {
    await client.core.pairing.disconnect(topic: topic);
    if (_ownsClient(client)) {
      _approvedProposalIds.clear();
      pendingApprovals.invalidate();
    }
  }

  @override
  Map<String, SessionData> getSessionsForPairing(String pairingTopic) {
    return _requireClient().getSessionsForPairing(pairingTopic: pairingTopic);
  }

  @override
  Future<void> emitAddressChangeEvent(String newAddress) {
    return _emitEventPairedDApps(
      changeName: 'addressChange',
      newValue: newAddress,
    );
  }

  @override
  Future<void> emitChainIdChangeEvent(String newChainId) {
    pendingApprovals.invalidate();
    return _emitEventPairedDApps(
      changeName: 'chainIdChange',
      newValue: newChainId,
    );
  }

  @override
  Future<void> disconnectSessions() async {
    final ReownWalletKit client = _requireClient();
    final List<String> topics = List<String>.of(
      client.getActiveSessions().keys,
    );
    for (final String topic in topics) {
      if (!_ownsClient(client)) return;
      await client.disconnectSession(
        topic: topic,
        reason: Errors.getSdkError(Errors.USER_DISCONNECTED).toSignError(),
      );
    }

    if (_ownsClient(client)) {
      _approvedProposalIds.clear();
      pendingApprovals.invalidate();
    }
  }

  @override
  Future<void> disconnectSession({required String topic}) {
    final ReownWalletKit client = _requireClient();
    return client.disconnectSession(
      topic: topic,
      reason: Errors.getSdkError(Errors.USER_DISCONNECTED).toSignError(),
    );
  }

  @override
  Map<String, SessionData> getActiveSessions() {
    return _requireClient().getActiveSessions();
  }

  void _subscribeListeners() {
    _wcClient!.core.relayClient.onRelayClientConnect.subscribe(
      _onRelayClientConnect,
    );
    _wcClient!.core.relayClient.onRelayClientDisconnect.subscribe(
      _onRelayClientDisconnect,
    );
    _wcClient!.core.relayClient.onRelayClientError.subscribe(
      _onRelayClientError,
    );

    _wcClient!.core.pairing.onPairingCreate.subscribe(_onPairingCreate);
    _wcClient!.core.pairing.onPairingActivate.subscribe(_onPairingActivate);
    _wcClient!.core.pairing.onPairingPing.subscribe(_onPairingPing);
    _wcClient!.core.pairing.onPairingInvalid.subscribe(_onPairingInvalid);
    _wcClient!.core.pairing.onPairingDelete.subscribe(_onPairingDelete);

    _wcClient!.pairings.onSync.subscribe(_onPairingsSync);
    _wcClient!.sessions.onSync.subscribe(_onSessionsSync);

    _wcClient!.onSessionProposal.subscribe(_onSessionProposal);
    _wcClient!.onProposalExpire.subscribe(_onProposalExpire);
    _wcClient!.onSessionConnect.subscribe(_onSessionConnect);
    _wcClient!.onSessionRequest.subscribe(_onSessionRequest);
    _wcClient!.onSessionProposalError.subscribe(_onSessionProposalError);
    _wcClient!.onSessionDelete.subscribe(_onSessionDelete);
  }

  void _unsubscribeListeners() {
    _wcClient!.core.relayClient.onRelayClientConnect.unsubscribe(
      _onRelayClientConnect,
    );
    _wcClient!.core.relayClient.onRelayClientDisconnect.unsubscribe(
      _onRelayClientDisconnect,
    );
    _wcClient!.core.relayClient.onRelayClientError.unsubscribe(
      _onRelayClientError,
    );

    _wcClient!.core.pairing.onPairingCreate.unsubscribe(_onPairingCreate);
    _wcClient!.core.pairing.onPairingActivate.unsubscribe(_onPairingActivate);
    _wcClient!.core.pairing.onPairingPing.unsubscribe(_onPairingPing);
    _wcClient!.core.pairing.onPairingInvalid.unsubscribe(_onPairingInvalid);
    _wcClient!.core.pairing.onPairingDelete.unsubscribe(_onPairingDelete);

    _wcClient!.pairings.onSync.unsubscribe(_onPairingsSync);
    _wcClient!.sessions.onSync.unsubscribe(_onSessionsSync);

    _wcClient!.onSessionProposal.unsubscribe(_onSessionProposal);
    _wcClient!.onProposalExpire.unsubscribe(_onProposalExpire);
    _wcClient!.onSessionConnect.unsubscribe(_onSessionConnect);
    _wcClient!.onSessionRequest.unsubscribe(_onSessionRequest);
    _wcClient!.onSessionProposalError.unsubscribe(_onSessionProposalError);
    _wcClient!.onSessionDelete.unsubscribe(_onSessionDelete);
  }

  void _registerRequestHandlers() {
    _wcClient!.registerRequestHandler(
      chainId: _namespaceChainId,
      method: 'znn_info',
      handler: _handleZnnInfoRequest,
    );

    _wcClient!.registerRequestHandler(
      chainId: _namespaceChainId,
      method: 'znn_sign',
      handler: _handleZnnSignRequest,
    );

    _wcClient!.registerRequestHandler(
      chainId: _namespaceChainId,
      method: 'znn_send',
      handler: _handleZnnSendRequest,
    );
  }

  void _startPendingRequestsPolling() {
    _pendingRequestsPollTimer?.cancel();
    _pendingRequestsPollTimer = Timer.periodic(
      _pendingRequestsPollInterval,
      (_) => _drainPendingSessionRequests(),
    );
  }

  Future<void> _drainPendingSessionRequests() async {
    final ReownWalletKit? client = _wcClient;
    if (client == null || !_ownsClient(client)) return;

    final Map<String, SessionRequest> pendingRequests =
        _safeGetPendingRequests();
    if (pendingRequests.isEmpty) return;

    for (final SessionRequest request in pendingRequests.values) {
      if (!_ownsClient(client)) return;
      final int id = request.id;
      final String topic = request.topic;
      final String method = request.method;
      final String chainId = request.chainId;
      final dynamic params = request.params;

      if (_handledRequestIds.contains((topic, id))) {
        continue;
      }

      _handledRequestIds.add((topic, id));

      try {
        final dynamic result = await _dispatchSessionRequest(
          topic: topic,
          chainId: chainId,
          method: method,
          params: params,
        );

        await _respondSuccess(
          client: client,
          topic: topic,
          requestId: id,
          result: result,
        );
      } on Object {
        _logger.warning('Session request unavailable');

        try {
          await _respondError(
            client: client,
            topic: topic,
            requestId: id,
            code: 5000,
            message: 'Request unavailable',
          );
        } on Object {
          _logger.warning('Request response unavailable');
        }
      }
    }
  }

  Map<String, SessionRequest> _safeGetPendingRequests() {
    try {
      return _wcClient!.getPendingSessionRequests();
    } on Object {
      return const <String, SessionRequest>{};
    }
  }

  Future<dynamic> _dispatchSessionRequest({
    required String topic,
    required String chainId,
    required String method,
    required dynamic params,
  }) {
    if (_disposed || chainId != _namespaceChainId) {
      throw StateError('Request unavailable');
    }
    switch (method) {
      case 'znn_info':
        return _handleZnnInfoRequest(topic, params);
      case 'znn_sign':
        return _handleZnnSignRequest(topic, params);
      case 'znn_send':
        return _handleZnnSendRequest(topic, params);
      default:
        throw UnsupportedError('Unsupported WalletConnect method: $method');
    }
  }

  Future<dynamic> _handleZnnInfoRequest(String topic, dynamic params) async {
    final ReownWalletKit client = _requireClient();
    final String address = _primaryAddress();
    final int chain = getChainIdentifier();
    final SessionData? session = client.getActiveSessions()[topic];
    final String account = 'zenon:$chain:$address';
    if (session == null ||
        !session.namespaces.values.any(
          (Namespace grant) =>
              grant.accounts.contains(account) &&
              grant.methods.contains('znn_info'),
        )) {
      throw StateError('Request unavailable');
    }

    return <String, dynamic>{
      'address': address,
      'chainId': chain,
      'nodeUrl': publicNodeUrl(kCurrentNode),
    };
  }

  Future<dynamic> _handleZnnSignRequest(String topic, dynamic params) async {
    throw UnimplementedError('znn_sign is not implemented');
  }

  Future<dynamic> _handleZnnSendRequest(String topic, dynamic params) async {
    throw UnimplementedError('znn_send is not implemented');
  }

  Future<void> _respondSuccess({
    required ReownWalletKit client,
    required String topic,
    required int requestId,
    required dynamic result,
  }) {
    final JsonRpcResponse<dynamic> response = JsonRpcResponse<dynamic>(
      id: requestId,
      result: result,
    );

    return client.respondSessionRequest(
      topic: topic,
      response: response,
    );
  }

  Future<void> _respondError({
    required ReownWalletKit client,
    required String topic,
    required int requestId,
    required int code,
    required String message,
  }) {
    final JsonRpcResponse<dynamic> response = JsonRpcResponse<dynamic>(
      id: requestId,
      error: JsonRpcError(
        code: code,
        message: message,
      ),
    );

    return client.respondSessionRequest(
      topic: topic,
      response: response,
    );
  }

  String _primaryAddress() {
    if (kAddressLabelMap.isEmpty) {
      throw StateError('No Zenon address available');
    }

    return kAddressLabelMap.keys.first;
  }

  void _onSessionProposal(SessionProposalEvent? event) {
    if (_disposed || event == null || event.id != event.params.id) return;
    _enqueueProposal(event.params);
  }

  void _onProposalExpire(SessionProposalEvent? event) {
    if (!_disposed && event != null) pendingApprovals.expire(event.id);
  }

  void _enqueueProposal(ProposalData proposal) {
    final ReownWalletKit? client = _wcClient;
    final String? scope = _approvalScope;
    if (_disposed || client == null || scope == null) return;
    final Map<String, ApprovalNamespace> approved = <String, ApprovalNamespace>{
      'zenon': ApprovalNamespace(
        chains: <String>[_namespaceChainId],
        accounts: _walletAccounts(),
        methods: const <String>['znn_sign', 'znn_info', 'znn_send'],
        events: const <String>['chainIdChange', 'addressChange'],
      ),
    };
    pendingApprovals.enqueue(
      PendingSessionApproval(
        id: proposal.id,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(proposal.expiry * 1000),
        name: proposal.proposer.metadata.name,
        url: proposal.proposer.metadata.url,
        walletScope: scope,
        clientIdentity: client,
        requiredNamespaces: _copyRequestedNamespaces(
          proposal.requiredNamespaces,
        ),
        optionalNamespaces: _copyRequestedNamespaces(
          proposal.optionalNamespaces,
        ),
        approvedNamespaces: approved,
      ),
    );
  }

  Map<String, ApprovalNamespace> _copyRequestedNamespaces(
    Map<String, RequiredNamespace> values,
  ) => values.map(
    (String name, RequiredNamespace value) =>
        MapEntry<String, ApprovalNamespace>(
          name,
          ApprovalNamespace(
            chains: value.chains ?? const <String>[],
            methods: value.methods,
            events: value.events,
          ),
        ),
  );

  bool _sameRequestedNamespaces(
    Map<String, RequiredNamespace> current,
    Map<String, ApprovalNamespace> copied,
  ) {
    if (current.length != copied.length) return false;
    for (final MapEntry<String, RequiredNamespace> entry in current.entries) {
      final ApprovalNamespace? old = copied[entry.key];
      if (old == null ||
          !listEquals(entry.value.chains ?? const <String>[], old.chains) ||
          !listEquals(entry.value.methods, old.methods) ||
          !listEquals(entry.value.events, old.events)) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrentApprovalContext(PendingSessionApproval proposal) {
    if (_disposed ||
        !identical(_wcClient, proposal.clientIdentity) ||
        _approvalScope != proposal.walletScope ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        kWalletFile == null) {
      return false;
    }
    final List<String> copied =
        proposal.approvedNamespaces['zenon']?.accounts ?? const <String>[];
    final List<String> current = _walletAccounts();
    return copied.isNotEmpty &&
        copied.length == current.length &&
        List<bool>.generate(
          current.length,
          (int i) => copied[i] == current[i],
        ).every((bool same) => same);
  }

  bool _proposalExists(PendingSessionApproval proposal) {
    if (!identical(_wcClient, proposal.clientIdentity)) return false;
    final ProposalData? current = _wcClient!
        .getPendingSessionProposals()[proposal.id.toString()];
    return current != null &&
        current.id == proposal.id &&
        current.expiry * 1000 == proposal.expiresAt.millisecondsSinceEpoch &&
        current.proposer.metadata.name == proposal.name &&
        current.proposer.metadata.url == proposal.url &&
        _sameRequestedNamespaces(
          current.requiredNamespaces,
          proposal.requiredNamespaces,
        ) &&
        _sameRequestedNamespaces(
          current.optionalNamespaces,
          proposal.optionalNamespaces,
        );
  }

  Future<void> _approveProposal(PendingSessionApproval proposal) async {
    if (!proposal.expiresAt.isAfter(DateTime.now()) ||
        !_isCurrentApprovalContext(proposal) ||
        !_proposalExists(proposal)) {
      throw StateError('Connection proposal unavailable');
    }
    final Map<String, Namespace> namespaces = proposal.approvedNamespaces.map(
      (String name, ApprovalNamespace value) => MapEntry<String, Namespace>(
        name,
        Namespace(
          chains: value.chains,
          accounts: value.accounts,
          methods: value.methods,
          events: value.events,
        ),
      ),
    );
    final ReownWalletKit client = _requireClient();
    final ApproveResponse response = await client.approveSession(
      id: proposal.id,
      namespaces: namespaces,
    );
    if (!_isCurrentApprovalContext(proposal) || response.session == null) {
      throw StateError('Connection approval outcome unavailable');
    }
    _approvedProposalIds.add(proposal.id);
    _upsertSession(response.session!);
    // Notification persistence is an observer of an established session. It
    // cannot turn that session into a retryable connection failure.
    try {
      await _sendSuccessfullyApprovedSessionNotification(
        proposal,
      );
    } on Object {
      _logger.warning('Connection notification unavailable');
    }
  }

  Future<void> _declineProposal(PendingSessionApproval proposal) {
    if (!proposal.expiresAt.isAfter(DateTime.now()) ||
        !_isCurrentApprovalContext(proposal) ||
        !_proposalExists(proposal)) {
      throw StateError('Connection proposal unavailable');
    }
    return _wcClient!.rejectSession(
      id: proposal.id,
      reason: Errors.getSdkError(Errors.USER_REJECTED).toSignError(),
    );
  }

  void _onSessionConnect(SessionConnect? args) {
    if (_disposed) return;
    if (args != null) {
      _upsertSession(args.session);
    }

    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed && sl.isRegistered<WalletConnectSessionsBloc>()) {
        sl.get<WalletConnectSessionsBloc>().refreshResults();
      }
    });
  }

  Future<void> _sendSuccessfullyApprovedSessionNotification(
    PendingSessionApproval proposal,
  ) {
    final List<String> chains =
        proposal.approvedNamespaces['zenon']?.chains ?? const <String>[];
    final String? chain = chains.length == 1 ? chains.single : null;
    return sl.get<NotificationsBloc>().addNotification(
      WalletNotification(
        title: 'Successfully connected to ${proposal.name}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Successfully connected to ${proposal.name} via WalletConnect',
        type: NotificationType.paymentSent,
        walletScope: proposal.walletScope,
        chainId: chain != null && chain.startsWith('zenon:')
            ? int.tryParse(chain.substring('zenon:'.length))
            : null,
      ),
      shouldDisplay: () => _isCurrentApprovalContext(proposal),
    );
  }

  List<String> _walletAccounts() {
    final int chainId = getChainIdentifier();
    return kAddressLabelMap.keys
        .map((String address) => '$kZenonNameSpace:$chainId:$address')
        .toList();
  }

  void _upsertSession(SessionData session) {
    if (_disposed) return;
    final List<SessionData> updated = List<SessionData>.from(sessions.value);
    final int index = updated.indexWhere(
      (SessionData item) => item.topic == session.topic,
    );

    if (index == -1) {
      updated.add(session);
    } else {
      updated[index] = session;
    }

    sessions.value = updated;
  }

  Future<void> _emitEventPairedDApps({
    required String changeName,
    required String newValue,
  }) async {
    final ReownWalletKit client = _requireClient();
    final String chain = _namespaceChainId;
    final String? scope = _approvalScope;
    final List<String> sessionTopics = pairings.value.fold<List<String>>(
      <String>[],
      (List<String> topics, PairingInfo pairing) {
        if (pairing.active) {
          topics.addAll(getSessionsForPairing(pairing.topic).keys);
        }
        return topics;
      },
    );

    for (final String sessionTopic in sessionTopics) {
      if (!_ownsClient(client) ||
          chain != _namespaceChainId ||
          scope != _approvalScope) {
        return;
      }
      await _emitDAppEvent(
        client: client,
        chain: chain,
        sessionTopic: sessionTopic,
        changeName: changeName,
        newValue: newValue,
      );
    }
  }

  Future<void> _emitDAppEvent({
    required ReownWalletKit client,
    required String chain,
    required String sessionTopic,
    required String changeName,
    required String newValue,
  }) {
    return client.emitSessionEvent(
      topic: sessionTopic,
      chainId: chain,
      event: SessionEventParams(
        name: changeName,
        data: newValue,
      ),
    );
  }

  Future<void> _onSessionRequest(SessionRequestEvent? args) async {
    final ReownWalletKit? client = _wcClient;
    if (args == null || client == null || !_ownsClient(client)) return;
    final int id = args.id;
    final String topic = args.topic;
    final String method = args.method;
    final String chain = args.chainId;
    final dynamic params = args.params;

    if (_handledRequestIds.contains((topic, id))) {
      return;
    }

    _handledRequestIds.add((topic, id));

    try {
      final dynamic result = await _dispatchSessionRequest(
        topic: topic,
        chainId: chain,
        method: method,
        params: params,
      );

      await _respondSuccess(
        client: client,
        topic: topic,
        requestId: id,
        result: result,
      );
    } on Object {
      _logger.warning('Session request unavailable');

      await _respondError(
        client: client,
        topic: topic,
        requestId: id,
        code: 5000,
        message: 'Request unavailable',
      );
    }
  }

  void _onSessionsSync(StoreSyncEvent? args) {
    if (args == null || _disposed) return;
    sessions.value = List<SessionData>.from(_wcClient!.sessions.getAll());
  }

  void _onPairingsSync(StoreSyncEvent? args) {
    if (args == null || _disposed) return;
    pairings.value = List<PairingInfo>.from(_wcClient!.pairings.getAll());
  }

  void _onSessionDelete(SessionDelete? args) {
    if (_disposed) return;
    sl.get<WalletConnectSessionsBloc>().refreshResults();
  }

  void _onSessionProposalError(SessionProposalErrorEvent? args) {
    if (_disposed) return;
    _logger.warning('Connection proposal unavailable');
    sl.get<WalletConnectPairingsBloc>().refreshResults();
    pendingApprovals.refresh();
  }

  void _onPairingCreate(PairingEvent? args) {
    if (_disposed) return;
    sl.get<WalletConnectPairingsBloc>().refreshResults();
  }

  void _onPairingActivate(PairingActivateEvent? args) {
    if (_disposed) return;
    sl.get<WalletConnectPairingsBloc>().refreshResults();
  }

  void _onPairingPing(PairingEvent? args) {}

  void _onPairingInvalid(PairingInvalidEvent? args) {}

  void _onPairingDelete(PairingEvent? args) {
    if (_disposed) return;
    pendingApprovals.refresh();
  }

  void _onRelayClientConnect(dynamic args) {}

  void _onRelayClientDisconnect(dynamic args) {}

  void _onRelayClientError(dynamic args) {
    _logger.warning('Relay client unavailable');
  }
}
