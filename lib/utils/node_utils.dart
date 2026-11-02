import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:hive_ce/hive_ce.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/embedded_node.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/date_time_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_receive_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notification_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Binds node lifecycle work to its original SDK and registered native ports.
class NodeUtils {
  /// Performs one original connection attempt; false is never automatic retry.
  static Future<bool> establishConnectionToNode(String url) async {
    final Zenon? client = zenon;
    if (client == null || NodeTransitions.pending) return false;
    final bool connectionStatus = await client.wsClient.initialize(
      url,
      retry: false,
    );
    return connectionStatus;
  }

  /// Returns a positive frontier chain only while its exact source is current.
  static Future<int?> getNodeChainIdentifier() async {
    final Zenon? client = zenon;
    if (client == null || NodeTransitions.pending) return null;
    final LedgerApi source = client.ledger;
    final Client transport = source.client;
    final String? url = transport is WsClient ? transport.url : null;
    final String? node = kCurrentNode;
    final int revision = WalletContextRevision.value;
    final LedgerApi ledger = LedgerApi()..setClient(transport);
    try {
      final Momentum value = await ledger.getFrontierMomentum();
      if (identical(client, zenon) &&
          identical(source, client.ledger) &&
          identical(source.client, transport) &&
          node == kCurrentNode &&
          revision == WalletContextRevision.value &&
          (transport is! WsClient || transport.url == url) &&
          value.chainIdentifier > 0 &&
          value.height > 0 &&
          value.timestamp > 0) {
        return value.chainIdentifier;
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Starts the native isolate once after the original failed attempt settled.
  /// A spawned isolate is no health receipt.
  /// Callers still require its frontier.
  static Future<void> startEmbeddedNode({
    required ReceivePort stoppedPort,
    required void Function() requireCurrent,
  }) async {
    void requireOwner() {
      requireCurrent();
      if (!sl.isRegistered<ReceivePort>(instanceName: 'embeddedStoppedPort') ||
          !identical(
            stoppedPort,
            sl<ReceivePort>(instanceName: 'embeddedStoppedPort'),
          )) {
        throw StateError('The original embedded-node port was replaced.');
      }
    }

    requireOwner();
    if (kEmbeddedNodeRunning) {
      throw StateError('An embedded-node start is already owned.');
    }
    final bool heldWakeLock = await WakelockPlus.enabled;
    requireOwner();
    if (!heldWakeLock) {
      await WakelockPlus.enable();
      requireOwner();
    }
    await Isolate.spawn<List<String>>(
      EmbeddedNode.runNode,
      <String>[''],
      onExit: stoppedPort.sendPort,
    );
    requireOwner();
    kEmbeddedNodeRunning = true;
    await Future<void>.delayed(kEmbeddedConnectionDelay);
    requireOwner();
  }

  /// Stops only the captured native owner and awaits its actual exit message.
  static Future<void> closeEmbeddedNode({
    void Function()? requireCurrent,
  }) async {
    final String? node = kCurrentNode;
    final SendPort? commands = ui.IsolateNameServer.lookupPortByName(
      'embeddedIsolate',
    );
    final ReceivePort? stopped =
        sl.isRegistered<ReceivePort>(instanceName: 'embeddedStoppedPort')
        ? sl<ReceivePort>(instanceName: 'embeddedStoppedPort')
        : null;
    final Stream<dynamic>? events =
        sl.isRegistered<Stream<dynamic>>(instanceName: 'embeddedStoppedStream')
        ? sl<Stream<dynamic>>(instanceName: 'embeddedStoppedStream')
        : null;
    final NotificationsBloc? notifications =
        sl.isRegistered<NotificationsBloc>() ? sl<NotificationsBloc>() : null;
    final String title = currentL10n.embeddedNodeStoppingNotificationTitle;
    final String details = currentL10n.embeddedNodeStoppingNotificationDetails;
    void requireOwner() {
      requireCurrent?.call();
      if (kCurrentNode != node ||
          (stopped != null &&
              (!sl.isRegistered<ReceivePort>(
                    instanceName: 'embeddedStoppedPort',
                  ) ||
                  !identical(
                    stopped,
                    sl<ReceivePort>(instanceName: 'embeddedStoppedPort'),
                  ))) ||
          (events != null &&
              (!sl.isRegistered<Stream<dynamic>>(
                    instanceName: 'embeddedStoppedStream',
                  ) ||
                  !identical(
                    events,
                    sl<Stream<dynamic>>(instanceName: 'embeddedStoppedStream'),
                  )))) {
        throw StateError('The original embedded-node owner was replaced.');
      }
    }

    requireOwner();
    final bool heldWakeLock = await WakelockPlus.enabled;
    requireOwner();
    if (heldWakeLock) {
      await WakelockPlus.disable();
      requireOwner();
    }
    if ((node == kLocalhostDefaultNodeUrl || node == kEmbeddedNode) &&
        kEmbeddedNodeRunning) {
      if (stopped == null || events == null) {
        throw StateError('The original embedded-node exit source is absent.');
      }
      if (notifications != null) {
        await notifications.addNotification(
          WalletNotification(
            title: title,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            details: details,
            type: NotificationType.changedNode,
          ),
        );

        requireOwner();
      }
      final Completer<void> embeddedStoppedCompleter = Completer<void>();
      final StreamSubscription<dynamic> subscription = events.listen(
        (dynamic _) {
          if (!embeddedStoppedCompleter.isCompleted) {
            embeddedStoppedCompleter.complete();
          }
        },
        onError: (Object error, StackTrace trace) {
          if (!embeddedStoppedCompleter.isCompleted) {
            embeddedStoppedCompleter.completeError(error, trace);
          }
        },
        onDone: () {
          if (!embeddedStoppedCompleter.isCompleted) {
            embeddedStoppedCompleter.completeError(
              StateError('The original embedded-node exit source closed.'),
            );
          }
        },
      );
      try {
        requireOwner();
        if (commands == null ||
            commands !=
                ui.IsolateNameServer.lookupPortByName('embeddedIsolate')) {
          throw StateError(
            'The original embedded-node command port is absent.',
          );
        }
        commands.send('stop');
        await embeddedStoppedCompleter.future;
        requireOwner();
        final SendPort? replacement = ui.IsolateNameServer.lookupPortByName(
          'embeddedIsolate',
        );
        if (replacement != null) {
          throw StateError('Embedded-node exit has no original owner receipt.');
        }
        kEmbeddedNodeRunning = false;
      } finally {
        await subscription.cancel();
      }
    }
  }

  /// Requests the original SDK stop without claiming awaitable cancellation.
  static void stopWebSocketClient() {
    final Zenon? client = zenon;
    try {
      client?.wsClient.stop();
    } on Object {
      // The SDK exposes no stop completion or cancellation receipt to publish.
    }
  }

  /// Retains the legacy entry point with one settled attempt.
  /// An uncertain result cannot authorize a blind retry.
  static Future<void> initWebSocketClient() async {
    final Zenon? client = zenon;
    if (client == null || NodeTransitions.pending) return;
    NodeReceiveBinding.register(client);
    final String url = kCurrentNode == kEmbeddedNode
        ? kLocalhostDefaultNodeUrl
        : kCurrentNode ?? '';
    if (url.isEmpty) return;
    await client.wsClient.initialize(url, retry: false);
  }

  /// Registers receive events against the captured client rather than a retry.
  static Future<void> addOnWebSocketConnectedCallback() async {
    final Zenon? client = zenon;
    if (client != null) NodeReceiveBinding.register(client);
  }

  /// Scans only through the caller's captured receive origin.
  static Future<void> getUnreceivedTransactions({
    required ReceiveOrigin origin,
  }) => NodeReceiveBinding.scan(
    worker: sl<AutoReceiveTxWorker>(),
    origin: origin,
  );

  /// Scans one member of the original receive origin, without replacing it.
  static Future<void> getUnreceivedTransactionsByAddress(
    Address address, {
    required ReceiveOrigin origin,
  }) => NodeReceiveBinding.scanAddress(
    worker: sl<AutoReceiveTxWorker>(),
    origin: origin,
    address: address.toString(),
  );

  /// Compares local time with a positive frontier from one unchanged source.
  static Future<void> checkForLocalTimeDiscrepancy(
    String warningMessage,
  ) async {
    const Duration maxAllowedDiscrepancy = Duration(minutes: 5);
    final Zenon? client = zenon;
    if (client == null || NodeTransitions.pending) return;
    final LedgerApi ledger = client.ledger;
    final StatsApi stats = client.stats;
    final Client transport = ledger.client;
    final String? node = kCurrentNode;
    final int revision = WalletContextRevision.value;
    final String? url = client.wsClient.url;
    final String discrepancy = currentL10n.nodeLocalTimeDiscrepancyError;
    bool current() =>
        identical(client, zenon) &&
        identical(ledger, client.ledger) &&
        identical(stats, client.stats) &&
        identical(transport, ledger.client) &&
        identical(transport, stats.client) &&
        identical(transport, client.wsClient) &&
        client.wsClient.url == url &&
        node == kCurrentNode &&
        revision == WalletContextRevision.value &&
        !NodeTransitions.pending;
    try {
      final SyncInfo syncInfo = await stats.syncInfo();
      if (!current()) return;
      final bool nodeIsSynced =
          syncInfo.state == SyncState.syncDone ||
          (syncInfo.targetHeight > 0 &&
              syncInfo.currentHeight > 0 &&
              (syncInfo.targetHeight - syncInfo.currentHeight) < 20);
      if (nodeIsSynced) {
        final Momentum frontier = await ledger.getFrontierMomentum();
        if (!current() ||
            frontier.height <= 0 ||
            frontier.timestamp <= 0 ||
            frontier.chainIdentifier <= 0) {
          return;
        }
        final int frontierTime = frontier.timestamp;
        final int timeDifference = (frontierTime - DateTimeUtils.unixTimeNow)
            .abs();
        if (timeDifference > maxAllowedDiscrepancy.inSeconds) {
          await NotificationUtils.sendNotificationError(
            Exception(discrepancy),
            warningMessage,
          );
        }
      }
    } on Object {
      // Unavailable frontier data cannot establish a local-clock discrepancy.
    }
  }

  /// Loads a catalog only while its original Box and caller still own the read.
  static Future<void> loadDbNodes({bool Function()? isCurrent}) async {
    final Zenon? client = zenon;
    final Object? preferences = sharedPrefsService;
    final int revision = WalletContextRevision.value;
    final String? selected = kCurrentNode;
    bool current() =>
        (isCurrent?.call() ?? true) &&
        identical(client, zenon) &&
        identical(preferences, sharedPrefsService) &&
        revision == WalletContextRevision.value &&
        selected == kCurrentNode;
    if (!current()) return;
    final Box<String> nodesBox;
    if (!Hive.isBoxOpen(kNodesBox)) {
      nodesBox = await Hive.openBox<String>(kNodesBox);
    } else {
      nodesBox = Hive.box<String>(kNodesBox);
    }
    if (!current() ||
        !nodesBox.isOpen ||
        !Hive.isBoxOpen(kNodesBox) ||
        !identical(nodesBox, Hive.box<String>(kNodesBox))) {
      return;
    }
    if (kDbNodes.isNotEmpty) {
      kDbNodes.clear();
    }
    kDbNodes.addAll(nodesBox.values);
    // Handle the case in which some default nodes were deleted
    // so they can't be found in the cache
    final String? currentNode = kCurrentNode;
    if (currentNode != null &&
        !kDefaultNodes.contains(currentNode) &&
        !kDbNodes.contains(currentNode)) {
      kDefaultNodes.add(currentNode);
    }
  }

  /// Restores the saved identity without mutating transport before decrypt.
  /// Embedded startup belongs to the later captured initialization operation.
  static Future<void> setNode() async {
    final String? savedNode = sharedPrefsService!.get(kSelectedNodeKey);
    kCurrentNode = savedNode;
  }
}
