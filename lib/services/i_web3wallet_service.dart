import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/services/pending_session_approval.dart';

/// The wallet's existing WalletConnect client and connection lifecycle.
abstract class IWeb3WalletService extends Disposable {
  /// Pairings retained by the current client.
  abstract ValueNotifier<List<PairingInfo>> pairings;

  /// Sessions retained by the current client.
  abstract ValueNotifier<List<SessionData>> sessions;

  /// Connection proposals awaiting an explicit user decision.
  PendingApprovalController get pendingApprovals;

  /// Completes after creating the client and registering its event listeners.
  Future<void> create();

  /// Initializes client storage and restores current pairing and session state.
  Future<void> init();

  /// Returns the client after creation.
  ReownWalletKit getWeb3Wallet();

  /// Pairs the current client with the supplied WalletConnect URI.
  Future<PairingInfo> pair(Uri uri);

  /// Activates the pairing identified by [topic].
  Future<void> activatePairing({
    required String topic,
  });

  /// Disconnects the pairing identified by [topic].
  Future<void> deactivatePairing({
    required String topic,
  });

  /// Returns sessions belonging to one pairing.
  Map<String, SessionData> getSessionsForPairing(String pairingTopic);

  /// Returns the client's active sessions keyed by session identity.
  Map<String, SessionData> getActiveSessions();

  /// Disconnects sessions owned by the current client pairings.
  Future<void> disconnectSessions();

  /// Disconnects the session identified by [topic].
  Future<void> disconnectSession({required String topic});

  /// Publishes an address change to the paired applications.
  Future<void> emitAddressChangeEvent(String newAddress);

  /// Invalidates old proposals and publishes a chain change.
  Future<void> emitChainIdChangeEvent(String newChainId);
}

/// Optional owned actions preserve existing injected service implementations.
abstract interface class CapturedWeb3WalletService {
  /// The existing client, captured without opening another client.
  ReownWalletKit getWeb3Wallet();

  /// Captures the actual client, not a later service-locator replacement.
  Web3WalletActions captureActions();
}

/// Every closure uses the same client, even after its service is disposed.
class Web3WalletActions {
  /// Retains one client and the closures that operate on that identical client.
  const Web3WalletActions({
    required this.identity,
    required this.isCurrent,
    required this.sessions,
    required this.pairings,
    required this.activeSessions,
    required this.pair,
    required this.disconnectSession,
    required this.disconnectPairing,
  });

  /// The exact original WalletConnect client object.
  final Object identity;

  /// Whether the original service still owns the captured client.
  final bool Function() isCurrent;

  /// The service's original observed session notifier.
  final ValueNotifier<List<SessionData>> sessions;

  /// The service's original observed pairing notifier.
  final ValueNotifier<List<PairingInfo>> pairings;

  /// Reads active sessions from the captured client only.
  final Map<String, SessionData> Function() activeSessions;

  /// Pairs the captured client with a strictly admitted ephemeral URI.
  final Future<PairingInfo> Function(Uri) pair;

  /// Disconnects one original session and propagates its actual failure.
  final Future<void> Function(String) disconnectSession;

  /// Disconnects one pairing without claiming that its sessions were deleted.
  final Future<void> Function(String) disconnectPairing;
}
