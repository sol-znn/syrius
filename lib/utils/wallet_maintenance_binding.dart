import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/screens/reset_wallet_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/splash_screen.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/cache_policy.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/file_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Identity receipts exclude only the request's fixed revision transitions.
class WalletMaintenanceResources {
  /// Tests supply inert identities and scalar receipts, without a filesystem.
  WalletMaintenanceResources({
    required List<Object?> originalIdentities,
    required List<Object?> originalValues,
    required this._identities,
    required this._values,
    required this._ready,
  }) : originalIdentities = List<Object?>.unmodifiable(originalIdentities),
       originalValues = List<Object?>.unmodifiable(originalValues);

  /// Captured original objects, never re-resolved after an await.
  final List<Object?> originalIdentities;

  /// Captured paths, account order, URLs and chain identifiers.
  final List<Object?> originalValues;

  final List<Object?> Function() _identities;
  final List<Object?> Function() _values;
  final bool Function() _ready;
  bool _revoked = false;

  /// Observed replacement is terminal even when an original later returns.
  bool get isCurrent {
    if (_revoked) {
      return false;
    }
    try {
      final List<Object?> current = _identities();
      final bool same =
          current.length == originalIdentities.length &&
          List<bool>.generate(
            current.length,
            (int index) => identical(current[index], originalIdentities[index]),
          ).every((bool same) => same);
      final bool lost =
          !_ready() || !same || !listEquals(originalValues, _values());
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }
}

class _OriginalBox {
  _OriginalBox(this.name, this.box) : path = box.path;

  final String name;
  final Box<dynamic> box;
  final String? path;
  bool deleting = false;
  bool deleted = false;
  Future<void>? _deletion;

  // Hive requires the type used when the original node registry was opened.
  static Box<dynamic> readOpened(String name) => name == kNodesBox
      ? Hive.box<String>(name)
      : Hive.box<dynamic>(name);

  bool get owns {
    if (Hive.isBoxOpen(name)) {
      if (!identical(readOpened(name), box)) {
        return false;
      }
    } else if (!deleting && !deleted) {
      return false;
    }
    return box.path == path && (deleting || deleted || box.isOpen);
  }

  Future<void> remove() {
    if (_deletion != null) {
      return _deletion!;
    }
    if (!owns || !box.isOpen || deleted) {
      throw const WalletMaintenanceRefused('original-box');
    }
    deleting = true;
    final Future<void> original = box.deleteFromDisk();
    _deletion = original;
    // This observer records a known original transition, never a replacement.
    unawaited(
      original.then<void>((_) {
        deleted = true;
        deleting = false;
      }, onError: (Object _, StackTrace _) {}),
    );
    return original;
  }
}

class _Transition implements WalletMaintenanceTransition {
  _Transition(this.lease);

  final NodeTransitionLease lease;

  @override
  int get revision => lease.revision;

  @override
  bool get isOwner => lease.isOwner;

  @override
  bool complete() => lease.complete();
}

class _MaintenanceSession implements WalletMaintenanceSession {
  _MaintenanceSession({
    required this.resources,
    required this.cleanupAvailable,
    required this.drains,
    required this.actions,
    required this.capturedRevision,
    required this._resetCleared,
  });

  final WalletMaintenanceResources resources;
  final bool Function() _resetCleared;
  NodeTransitionLease? _lease;
  bool _acquiring = false;

  @override
  final bool cleanupAvailable;

  @override
  final List<WalletMaintenanceAction> drains;

  @override
  final List<WalletMaintenanceAction> actions;

  @override
  final int capturedRevision;

  @override
  bool get resetCleared => _resetCleared() && resources.isCurrent;

  bool get ownsTransition =>
      !NodeTransitions.pending || _acquiring || (_lease?.isOwner ?? false);

  @override
  bool get ownsResources => ownsTransition && resources.isCurrent;

  @override
  int get revision => WalletContextRevision.value;

  @override
  WalletMaintenanceTransition? beginTransition() {
    if (_lease != null || !ownsResources) {
      return null;
    }
    _acquiring = true;
    try {
      final NodeTransitionLease? lease = NodeTransitions.begin();
      _lease = lease;
      return lease == null ? null : _Transition(lease);
    } finally {
      _acquiring = false;
    }
  }
}

/// Captures existing handles only. Missing backends are never opened by name.
WalletMaintenanceSession? captureWalletMaintenanceSession({
  required WalletMaintenanceKind kind,
  required SendTransactionBloc sender,
  WalletMaintenanceQuiescence? quiescence,
}) {
  final int capturedRevision = WalletContextRevision.value;
  if (NodeTransitions.pending) {
    return null;
  }
  final SharedPrefsService? preferences = app.sharedPrefsService;
  if (preferences == null || !Hive.isBoxOpen(kSharedPrefsBox)) {
    return null;
  }
  final Box<dynamic> preferenceBox = Hive.box<dynamic>(kSharedPrefsBox);
  final WalletFile? wallet = kWalletFile;
  final String? walletPath = kWalletPath;
  if (kind == WalletMaintenanceKind.reset &&
      (walletPath == null ||
          (wallet != null && wallet.walletPath != walletPath))) {
    return null;
  }
  final bool initialized = kWalletInitCompleted;
  final String? selected = kSelectedAddress;
  final List<String?> addresses = List<String?>.of(kDefaultAddressList);
  final String? node = kCurrentNode;
  final int? nodeChain = kNodeChainId;
  final int chain = getChainIdentifier();
  final bool embedded = kEmbeddedNodeRunning;
  final Zenon? client = app.zenon;
  final WsClient? socket = client?.wsClient;
  final LedgerApi? ledger = client?.ledger;
  final StatsApi? stats = client?.stats;
  final Client? ledgerClient = ledger?.client;
  final Client? statsClient = stats?.client;
  final String? socketUrl = socket?.url;
  final String? ledgerUrl = ledgerClient is WsClient ? ledgerClient.url : null;
  final String? statsUrl = statsClient is WsClient ? statsClient.url : null;
  final AutoReceiveTxWorker? receive =
      app.sl.isRegistered<AutoReceiveTxWorker>()
      ? app.sl<AutoReceiveTxWorker>()
      : null;
  final AutoUnlockHtlcWorker? unlock =
      app.sl.isRegistered<AutoUnlockHtlcWorker>()
      ? app.sl<AutoUnlockHtlcWorker>()
      : null;
  final HtlcSwapsHandler? handler = app.sl.isRegistered<HtlcSwapsHandler>()
      ? app.sl<HtlcSwapsHandler>()
      : null;
  final NotificationsBloc? notifications =
      app.sl.isRegistered<NotificationsBloc>()
      ? app.sl<NotificationsBloc>()
      : null;
  final IWeb3WalletService? web3 = app.sl.isRegistered<IWeb3WalletService>()
      ? app.sl<IWeb3WalletService>()
      : null;
  ReownWalletKit? pairingClient;
  List<String> pairingTopics = const <String>[];
  bool pairingCaptured = true;
  if (kind == WalletMaintenanceKind.reset && web3 != null) {
    try {
      pairingClient = web3.getWeb3Wallet();
      pairingTopics = List<String>.unmodifiable(
        web3.pairings.value.map((PairingInfo pairing) => pairing.topic),
      );
    } on Object {
      pairingCaptured = false;
    }
  }
  final ReownWalletKit? originalPairingClient = pairingClient;
  final List<String> names = kind == WalletMaintenanceKind.cache
      ? kOrdinaryCacheBoxesToBeDeleted
      : <String>[...kCacheBoxesToBeDeleted, kKeyStoreBox];
  final List<_OriginalBox> boxes = <_OriginalBox>[
    for (final String name in names)
      if (Hive.isBoxOpen(name))
        _OriginalBox(name, _OriginalBox.readOpened(name)),
  ];
  final WalletMaintenanceWriters writers = WalletMaintenanceWriters(
    sender: sender,
    htlcHandler: handler,
    autoUnlockWorker: unlock,
    autoReceiveWorker: receive,
    notifications: notifications,
  );
  final bool writersNeedDrain =
      handler != null ||
      unlock != null ||
      receive != null ||
      notifications != null;
  bool cleared = false;
  late final _MaintenanceSession session;
  final WalletMaintenanceResources resources = WalletMaintenanceResources(
    originalIdentities: List<Object?>.unmodifiable(<Object?>[
      preferences,
      preferenceBox,
      wallet,
      client,
      socket,
      ledger,
      stats,
      ledgerClient,
      statsClient,
      receive,
      unlock,
      handler,
      notifications,
      web3,
      originalPairingClient,
    ]),
    originalValues: List<Object?>.unmodifiable(<Object?>[
      walletPath,
      initialized,
      selected,
      ...addresses,
      node,
      nodeChain,
      chain,
      embedded,
      socketUrl,
      ledgerUrl,
      statsUrl,
    ]),
    identities: () => <Object?>[
      app.sharedPrefsService,
      // The exact deleted preference backend is an owned known transition.
      if (boxes.any(
        (_OriginalBox box) =>
            identical(box.box, preferenceBox) && (box.deleting || box.deleted),
      ))
        preferenceBox
      else if (Hive.isBoxOpen(kSharedPrefsBox))
        Hive.box<dynamic>(kSharedPrefsBox)
      else
        null,
      if (cleared) wallet else kWalletFile,
      app.zenon, client?.wsClient, client?.ledger, client?.stats,
      ledger?.client, stats?.client,
      if (app.sl.isRegistered<AutoReceiveTxWorker>())
        app.sl<AutoReceiveTxWorker>()
      else
        null,
      if (app.sl.isRegistered<AutoUnlockHtlcWorker>())
        app.sl<AutoUnlockHtlcWorker>()
      else
        null,
      if (app.sl.isRegistered<HtlcSwapsHandler>())
        app.sl<HtlcSwapsHandler>()
      else
        null,
      if (app.sl.isRegistered<NotificationsBloc>())
        app.sl<NotificationsBloc>()
      else
        null,
      if (app.sl.isRegistered<IWeb3WalletService>())
        app.sl<IWeb3WalletService>()
      else
        null,
      if (kind == WalletMaintenanceKind.reset && originalPairingClient != null)
        web3?.getWeb3Wallet()
      else
        null,
    ],
    values: () => <Object?>[
      if (cleared) walletPath else kWalletPath,
      if (cleared) initialized else kWalletInitCompleted,
      kSelectedAddress,
      ...kDefaultAddressList,
      kCurrentNode,
      kNodeChainId,
      getChainIdentifier(),
      kEmbeddedNodeRunning,
      client?.wsClient.url,
      if (ledgerClient is WsClient) ledgerClient.url else null,
      if (statsClient is WsClient) statsClient.url else null,
    ],
    ready: () =>
        session.ownsTransition &&
        boxes.every((_OriginalBox box) => box.owns) &&
        (!cleared ||
            (kWalletFile == null &&
                kWalletPath == null &&
                !kWalletInitCompleted)),
  );
  Future<bool>? originalQuiescence;
  Future<void>? originalPreferences;
  Future<void>? originalSender;
  final List<WalletMaintenanceAction> drains = <WalletMaintenanceAction>[
    if (writersNeedDrain && quiescence != null)
      WalletMaintenanceAction(
        name: 'captured-writers',
        run: () => originalQuiescence ??= quiescence(writers),
      ),
    WalletMaintenanceAction(
      name: 'captured-sender',
      run: () => originalSender ??= sender.close(),
    ),
    WalletMaintenanceAction(
      name: 'captured-preferences',
      run: () => originalPreferences ??= WalletSettingsBinding.pendingForStore(
        preferenceBox,
      ),
    ),
  ];
  final List<WalletMaintenanceAction> actions = <WalletMaintenanceAction>[
    if (kind == WalletMaintenanceKind.reset && originalPairingClient != null)
      for (final String topic in pairingTopics)
        WalletMaintenanceAction(
          name: 'deactivate-original-pairing',
          // The service wrapper swallows SDK errors and touches its mutable
          // current client after awaits. Bind the original SDK call instead.
          run: () => originalPairingClient.core.pairing.disconnect(
            topic: topic,
          ),
        ),
    for (final _OriginalBox box in boxes)
      WalletMaintenanceAction(name: 'remove-original-box', run: box.remove),
    if (kind == WalletMaintenanceKind.reset && walletPath != null)
      WalletMaintenanceAction(
        name: 'remove-selected-wallet-file',
        run: () {
          if (wallet?.isOpen ?? false) {
            throw const WalletMaintenanceRefused('wallet-acquisition');
          }
          return FileUtils.deleteFile(walletPath);
        },
      ),
    if (kind == WalletMaintenanceKind.reset)
      WalletMaintenanceAction(
        name: 'forget-original-wallet',
        run: () => Future<void>.sync(() {
          if (!resources.isCurrent) {
            throw const WalletMaintenanceRefused('original-wallet');
          }
          cleared = true;
          kWalletFile = null;
          kWalletPath = null;
          kWalletInitCompleted = false;
        }),
      ),
  ];
  session = _MaintenanceSession(
    resources: resources,
    capturedRevision: capturedRevision,
    cleanupAvailable:
        boxes.length == names.length &&
        pairingCaptured &&
        !embedded &&
        (!writersNeedDrain || quiescence != null),
    drains: List<WalletMaintenanceAction>.unmodifiable(drains),
    actions: List<WalletMaintenanceAction>.unmodifiable(actions),
    resetCleared: () => cleared && kind == WalletMaintenanceKind.reset,
  );
  return resources.isCurrent ? session : null;
}

/// Captures once before the owned question; no later route recaptures globals.
Future<void> openWalletMaintenance({
  required BuildContext context,
  required WalletMaintenanceOwner owner,
  required WalletMaintenanceKind kind,
  required bool Function() sourceIsCurrent,
  Widget Function(WalletMaintenanceRequest request)? splashBuilder,
}) async {
  final WalletMaintenanceRequest? request = owner.capture(
    kind,
    sourceIsCurrent: sourceIsCurrent,
  );
  if (request == null) {
    return;
  }
  late final _MaintenanceRoute question;
  question = _MaintenanceRoute(
    request: request,
    builder: (_) => ResetWalletScreen(
      request: request,
      onConfirm: () => handoffWalletMaintenance(
        request,
        splashBuilder: splashBuilder,
      ),
    ),
  );
  if (!context.mounted || !request.reserveQuestion(question)) {
    request.cancel();
    return;
  }
  await request.navigator.push<void>(question);
  await question.completed;
  if (!request.handoffReserved) {
    request.cancel();
  }
}

/// Auto-erase carries the request captured before decrypt, without a question.
void handoffWalletMaintenance(
  WalletMaintenanceRequest request, {
  Widget Function(WalletMaintenanceRequest request)? splashBuilder,
}) {
  final bool question = request.questionIsCurrent;
  final _MaintenanceRoute splash = _MaintenanceRoute(
    request: request,
    builder: (_) =>
        splashBuilder?.call(request) ?? SplashScreen(maintenance: request),
  );
  if (!request.reserveSplash(splash)) {
    return;
  }
  try {
    request.installReservedSplash(splash, () {
      if (question) {
        // Main is covered by our exact question. Replace it before removing
        // that question, without exposing another mutable top-route interval.
        request.navigator.replace<void>(
          oldRoute: request.sourceRoute,
          newRoute: splash,
        );
        final Route<dynamic>? originalQuestion = request.questionRoute;
        if (originalQuestion != null) {
          request.navigator.removeRoute(originalQuestion);
        }
      } else {
        request.navigator.pushReplacement<void, void>(splash);
      }
    });
  } on Object catch (error) {
    request.navigationFailed(error);
  }
}

class _MaintenanceRoute extends MaterialPageRoute<void> {
  _MaintenanceRoute({required this.request, required super.builder});

  final WalletMaintenanceRequest request;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    request.routeCovered(this, nextRoute);
    super.didChangeNext(nextRoute);
  }

  @override
  bool didPop(void result) {
    request.routeLeft(this);
    return super.didPop(null);
  }

  @override
  void dispose() {
    request.routeLeft(this);
    super.dispose();
  }
}
