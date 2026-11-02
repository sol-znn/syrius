import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/receive_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _SocketFeed {
  _SocketFeed(this.client, this.socket);

  final Zenon client;
  final WsClient socket;
  ReceiveFeedConnection? connection;
  NodeReceiveBinding? owner;

  void connected(Stream<Map<String, dynamic>?> messages) {
    final String? url = socket.url;
    final SubscribeApi source = client.subscribe;
    final Client transport = source.client;
    final SubscribeApi subscriptions = SubscribeApi()..setClient(transport);
    final ReceiveFeedConnection next = ReceiveFeedConnection(
      messages: messages,
      isCurrent: () =>
          identical(client.wsClient, socket) &&
          socket.status() == WebsocketStatus.running &&
          socket.url == url &&
          identical(client.subscribe, source) &&
          identical(source.client, transport) &&
          identical(subscriptions.client, transport),
      subscribeMomentums: subscriptions.toMomentums,
      subscribeAccountBlocks: subscriptions.toAllAccountBlocks,
    );
    connection = next;
    owner?._connected(next);
  }
}

/// A shell-owned feed; permanent SDK callbacks cache only connection facts.
class NodeReceiveBinding {
  /// Attaches one original sender and shell without starting locked work.
  factory NodeReceiveBinding.attach({
    required Zenon client,
    required AutoReceiveTxWorker worker,
    required Object senderLease,
    required bool Function() isUnlocked,
  }) {
    register(client);
    final _SocketFeed slot = _sockets[client.wsClient]!;
    final NodeReceiveBinding binding = NodeReceiveBinding._(
      client: client,
      worker: worker,
      senderLease: senderLease,
      isUnlocked: isUnlocked,
      slot: slot,
    );
    unawaited(slot.owner?.close());
    slot.owner = binding;
    final ReceiveFeedConnection? connection = slot.connection;
    if (connection != null) binding._connected(connection);
    return binding;
  }
  NodeReceiveBinding._({
    required this.client,
    required this.worker,
    required this._senderLease,
    required this._isUnlocked,
    required this._slot,
  }) {
    _feed = ReceiveFeed<ReceiveOrigin>(
      prepare: _prepare,
      isOriginCurrent: (ReceiveOrigin origin) => origin.isCurrent,
      ownsAddress: (ReceiveOrigin origin, String address) =>
          origin.addresses.contains(address),
      scan: (ReceiveOrigin origin) => scan(worker: worker, origin: origin),
      enqueue: (ReceiveOrigin origin, String hash, String address) =>
          worker.addHash(
            Hash.parse(hash),
            origin: origin,
            toAddress: address,
          ),
      drain: (ReceiveOrigin origin) async {
        if (origin.isCurrent) await worker.autoReceive();
      },
      hasPending: () => worker.hasPending,
      notifySyncing: _notifySyncing,
    );
  }

  static final Expando<_SocketFeed> _sockets = Expando<_SocketFeed>(
    'Owned receive connections',
  );

  /// Registers once, before an SDK call can synchronously report connection.
  static void register(Zenon client) {
    final WsClient socket = client.wsClient;
    if (_sockets[socket] != null) return;
    final _SocketFeed slot = _SocketFeed(client, socket);
    _sockets[socket] = slot;
    socket.addOnConnectionEstablishedCallback(slot.connected);
  }

  /// These references never follow replacement service globals.
  final Zenon client;

  /// The exact original queue owner and its admission journal.
  final AutoReceiveTxWorker worker;
  final Object _senderLease;
  final bool Function() _isUnlocked;
  final _SocketFeed _slot;
  late final ReceiveFeed<ReceiveOrigin> _feed;
  bool _closed = false;

  bool get _current =>
      !_closed &&
      identical(_slot.owner, this) &&
      identical(app.zenon, client) &&
      worker.ownsSender(_senderLease) &&
      !NodeTransitions.pending &&
      _isUnlocked();

  void _connected(ReceiveFeedConnection connection) {
    if (!_closed) _feed.connect(connection);
  }

  Future<ReceiveOrigin?> _prepare(bool Function() sourceCurrent) async {
    if (!_current || !sourceCurrent()) return null;
    final String? address = kSelectedAddress;
    if (address == null) return null;
    final WalletActionContext? action = WalletActionContext.capture(address);
    if (action == null) return null;
    final LedgerApi source = client.ledger;
    final Client transport = source.client;
    final String? url = transport is WsClient ? transport.url : null;
    final LedgerApi ledger = LedgerApi()..setClient(transport);
    bool original() =>
        _current &&
        sourceCurrent() &&
        action.isCurrent &&
        identical(client.ledger, source) &&
        identical(source.client, transport) &&
        (transport is! WsClient || transport.url == url);
    if (!original()) return null;
    final Momentum frontier = await ledger.getFrontierMomentum();
    if (!original() || frontier.chainIdentifier <= 0) return null;
    // This is a positive read of the original connection, never a fallback.
    kNodeChainId = frontier.chainIdentifier;
    if (!_current || !sourceCurrent()) return null;
    return worker.captureOrigin(
      sourceIsCurrent: () => _current && sourceCurrent(),
    );
  }

  /// Revokes immediately; a deferred fresh rearm observes actual readiness.
  void revoke() => _feed.revoke();

  /// An unlock or verified transition may reuse this connection's receipts.
  void rearm() {
    if (_current) {
      _feed.rearm();
    } else {
      _feed.revoke();
    }
  }

  /// Captures once before the explicit preference-triggered scan begins.
  Future<void> scanNow() async {
    if (!_current) return;
    final ReceiveOrigin? origin = worker.captureOrigin(
      sourceIsCurrent: () => _current,
    );
    if (origin == null) return;
    await scan(worker: worker, origin: origin);
    if (origin.isCurrent) await worker.autoReceive();
  }

  /// Reads only the original member snapshot and original independent ledger.
  static Future<void> scan({
    required AutoReceiveTxWorker worker,
    required ReceiveOrigin origin,
  }) async {
    for (final String address in origin.addresses) {
      if (!origin.isCurrent) return;
      await scanAddress(worker: worker, origin: origin, address: address);
    }
  }

  /// Preference and Box identity are retained before the first network await.
  static Future<void> scanAddress({
    required AutoReceiveTxWorker worker,
    required ReceiveOrigin origin,
    required String address,
  }) async {
    if (!origin.isCurrent || !origin.addresses.contains(address)) return;
    final Object? preferences = app.sharedPrefsService;
    if (preferences == null || !Hive.isBoxOpen(kSharedPrefsBox)) return;
    final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
    bool current() =>
        origin.isCurrent &&
        identical(preferences, app.sharedPrefsService) &&
        box.isOpen &&
        Hive.isBoxOpen(kSharedPrefsBox) &&
        identical(box, Hive.box<dynamic>(kSharedPrefsBox)) &&
        box.get(kAutoReceiveKey, defaultValue: kAutoReceiveDefaultValue) ==
            true;
    if (!current()) return;
    final AccountBlockList response = await origin.ledger
        .getUnreceivedBlocksByAddress(Address.parse(address));
    if (!current()) return;
    final List<AccountBlock>? blocks = response.list;
    if (blocks == null) return;
    for (final AccountBlock block in blocks) {
      if (!current()) return;
      await worker.addHash(block.hash, origin: origin, toAddress: address);
    }
  }

  Future<void> _notifySyncing(ReceiveOrigin origin) async {
    if (!origin.isCurrent || !app.sl.isRegistered<NotificationsBloc>()) return;
    final NotificationsBloc notifications = app.sl<NotificationsBloc>();
    final String title = currentL10n.nodeSyncingNotificationTitle;
    final String details = currentL10n.nodeSyncingNotificationDetails;
    final SyncInfo sync = await origin.stats.syncInfo();
    if (!origin.isCurrent ||
        !app.sl.isRegistered<NotificationsBloc>() ||
        !identical(notifications, app.sl<NotificationsBloc>())) {
      return;
    }
    if (sync.targetHeight == 0 ||
        sync.currentHeight == 0 ||
        sync.targetHeight - sync.currentHeight > 20) {
      await notifications.addNotification(
        WalletNotification(
          title: title,
          details: details,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: NotificationType.changedNode,
        ),
      );
    }
  }

  /// Does not remove SDK callbacks or close a replacement owner's resources.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(_slot.owner, this)) _slot.owner = null;
    await _feed.close();
  }
}
