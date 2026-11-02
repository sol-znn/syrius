import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:version/version.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_receive_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Startup retains each actual open Future and the returned backend. A closed
/// or replaced original is never reopened or adopted on a later entry route.
abstract final class WalletInitializationSource {
  static Future<void>? _opening;
  static final List<WalletInitializationOperation> _opens =
      <WalletInitializationOperation>[];
  static Box<dynamic>? _pointer;
  static Box<dynamic>? _members;
  static Box<dynamic>? _labels;

  /// Actual startup opens, including failed and unfinished original operations.
  static List<WalletInitializationOperation> get openingOperations =>
      List<WalletInitializationOperation>.unmodifiable(_opens);

  static bool _owns(Box<dynamic> box) =>
      box.isOpen &&
      Hive.isBoxOpen(box.name) &&
      identical(Hive.box<dynamic>(box.name), box);

  static Future<Box<dynamic>> _open(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<dynamic>(name);
    final WalletInitializationOperation operation =
        WalletInitializationOperation('open-startup-box');
    _opens.add(operation);
    final Box<dynamic> box = await operation.run<Box<dynamic>>(
      () => Hive.openBox<dynamic>(name),
    );
    if (!_owns(box)) throw const WalletInitializationRefused('startup-box');
    return box;
  }

  /// Opens each startup store once and retains that original initialization.
  /// Later callers observe the same completion instead of reopening a failure.
  static Future<void> prepareBoxes() {
    if (_opening != null) return _opening!;
    final Completer<void> completion = Completer<void>();
    _opening = completion.future;
    unawaited(
      _prepareBoxes().then<void>(
        (_) => completion.complete(),
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  static Future<void> _prepareBoxes() async {
    _pointer = await _open(kKeyStoreBox);
    if (!_owns(_pointer!)) throw const WalletInitializationRefused('pointer');
    _members = await _open(kAddressesBox);
    if (!_owns(_pointer!) || !_owns(_members!)) {
      throw const WalletInitializationRefused('members');
    }
    _labels = await _open(kAddressLabelsBox);
    if (!_owns(_pointer!) || !_owns(_members!) || !_owns(_labels!)) {
      throw const WalletInitializationRefused('labels');
    }
  }

  /// Reads the already captured pointer without copying a legacy location or
  /// starting an unawaited write. Legacy relocation needs its own capability.
  static void restorePath() {
    final Box<dynamic>? box = _pointer;
    if (box == null ||
        !_owns(box) ||
        box.length > 1 ||
        (box.isNotEmpty && !box.containsKey(0))) {
      throw const WalletInitializationRefused('pointer');
    }
    final dynamic path = box.get(0);
    if (path != null && (path is! String || path.isEmpty)) {
      throw const WalletInitializationRefused('path');
    }
    if (kWalletPath != null && kWalletPath != path) {
      throw const WalletInitializationRefused('path-replaced');
    }
    if (path == null &&
        app.sharedPrefsService?.get(kEntropyFilePathKey) != null) {
      throw const WalletInitializationRefused('legacy-path');
    }
    kWalletPath = path as String?;
  }

  /// Captures only a fresh service set. Paused singleton owners have no restart
  /// receipt; none is opened, resumed, replaced or installed here.
  static WalletInitializationBinding? capture({
    WalletFile? originalFile,
    bool Function()? sourceIsCurrent,
    bool creating = false,
    bool decrypting = false,
  }) {
    try {
      final Box<dynamic>? pointer = _pointer;
      final Box<dynamic>? members = _members;
      final Box<dynamic>? labels = _labels;
      final SharedPrefsService? preferences = app.sharedPrefsService;
      final Zenon? client = app.zenon;
      if (pointer == null ||
          members == null ||
          labels == null ||
          preferences == null ||
          client == null ||
          !_owns(pointer) ||
          !_owns(members) ||
          !_owns(labels) ||
          !Hive.isBoxOpen(kSharedPrefsBox) ||
          !app.sl.isRegistered<Zenon>() ||
          !identical(client, app.sl<Zenon>()) ||
          !OriginalPublications.canChangeTransport(client) ||
          NodeTransitions.pending ||
          !app.sl.isRegistered<HtlcSwapsService>() ||
          !app.sl.isRegistered<HtlcSwapsHandler>() ||
          !app.sl.isRegistered<AutoUnlockHtlcWorker>() ||
          !app.sl.isRegistered<AutoReceiveTxWorker>()) {
        return null;
      }
      final Box<dynamic> prefs = Hive.box<dynamic>(kSharedPrefsBox);
      final HtlcSwapsService store = app.sl<HtlcSwapsService>();
      final HtlcSwapsHandler handler = app.sl<HtlcSwapsHandler>();
      final AutoUnlockHtlcWorker unlock = app.sl<AutoUnlockHtlcWorker>();
      final AutoReceiveTxWorker receive = app.sl<AutoReceiveTxWorker>();
      if (!identical(store, app.htlcSwapsService) ||
          store.isPaused ||
          store.operations.isNotEmpty ||
          store.captureSwapsBox() != null ||
          handler.isPaused ||
          handler.hasStarted ||
          handler.operations.isNotEmpty ||
          unlock.isPaused ||
          unlock.running ||
          unlock.pool.isNotEmpty ||
          unlock.operations.isNotEmpty ||
          receive.isPaused ||
          receive.running ||
          receive.hasPending ||
          kWalletInitCompleted ||
          (sourceIsCurrent != null && !sourceIsCurrent())) {
        return null;
      }
      final WalletFile? initialFile = kWalletFile;
      final String? initialPath = kWalletPath;
      if ((creating && decrypting) ||
          (creating
              ? initialFile != null || initialPath != null
              : decrypting
              ? initialPath == null ||
                    initialPath.isEmpty ||
                    (initialFile != null &&
                        (initialFile.walletPath != initialPath ||
                            initialFile.isOpen))
              : originalFile == null ||
                    !identical(initialFile, originalFile) ||
                    originalFile.walletPath != initialPath ||
                    originalFile.isOpen)) {
        return null;
      }
      if (pointer.length > 1 ||
          (pointer.isNotEmpty && !pointer.containsKey(0)) ||
          pointer.get(0) != initialPath) {
        return null;
      }
      final String version =
          prefs.get(kWalletVersionKey, defaultValue: kWalletVersion) as String;
      if (Version.parse(version) <= Version(0, 1, 0)) return null;
      final int chain = getChainIdentifier();
      final String? node = kCurrentNode;
      final bool selectedNodeExists = prefs.containsKey(kSelectedNodeKey);
      if (prefs.get(kSelectedNodeKey) != node ||
          (node == null && selectedNodeExists)) {
        return null;
      }
      final WalletInitializationTarget? target =
          WalletInitializationTarget.fromPreference(
            node: node,
            creating: creating,
            embeddedNode: kEmbeddedNode,
            embeddedUrl: kLocalhostDefaultNodeUrl,
          );
      if (chain <= 0 || target == null) return null;
      final String? url = target.url;
      final WsClient socket = client.wsClient;
      final ReceivePort? embeddedStopped =
          app.sl.isRegistered<ReceivePort>(instanceName: 'embeddedStoppedPort')
          ? app.sl<ReceivePort>(instanceName: 'embeddedStoppedPort')
          : null;
      final LedgerApi ledgerSource = client.ledger;
      final StatsApi statsSource = client.stats;
      final EmbeddedApi embeddedSource = client.embedded;
      final SubscribeApi subscribeSource = client.subscribe;
      final HtlcApi htlcSource = embeddedSource.htlc;
      if (!identical(ledgerSource.client, socket) ||
          !identical(statsSource.client, socket) ||
          !identical(embeddedSource.client, socket) ||
          !identical(subscribeSource.client, socket) ||
          !identical(htlcSource.client, socket)) {
        return null;
      }
      final WebsocketStatus initialStatus = socket.status();
      final String? initialUrl = socket.url;
      if (initialStatus != WebsocketStatus.uninitialized &&
          !(initialStatus == WebsocketStatus.running &&
              url != null &&
              initialUrl == url &&
              !socket.isClosed())) {
        return null;
      }
      final LedgerApi ledger = LedgerApi()..setClient(socket);
      final List<String?> initialMembers = List<String?>.of(
        kDefaultAddressList,
      );
      final Map<String, String> initialLabels = Map<String, String>.of(
        kAddressLabelMap,
      );
      final String? initialSelected = kSelectedAddress;
      final int? initialNodeChain = kNodeChainId;
      final Map<dynamic, dynamic> expectedPointer = Map<dynamic, dynamic>.of(
        pointer.toMap(),
      );
      final Map<dynamic, dynamic> expectedMembers = Map<dynamic, dynamic>.of(
        members.toMap(),
      );
      final Map<dynamic, dynamic> expectedLabels = Map<dynamic, dynamic>.of(
        labels.toMap(),
      );
      final Map<dynamic, dynamic> expectedPrefs = <dynamic, dynamic>{
        kWalletVersionKey: prefs.get(kWalletVersionKey),
        kDefaultAddressKey: prefs.get(kDefaultAddressKey),
        kChainIdKey: prefs.get(kChainIdKey),
        kSelectedNodeKey: prefs.get(kSelectedNodeKey),
      };
      final String Function(int) defaultLabel = currentL10n.addressDefaultLabel;
      int revision = WalletContextRevision.value;
      NodeTransitionLease? transition;
      bool acquiringTransition = false;
      bool releasedConnection = false;
      bool localBoundaryAdmitted = false;
      bool connecting = false;
      bool storeOpening = false;
      bool committed = false;
      String? committedBaseMember;
      bool retired = false;
      WalletFile? file = originalFile;
      String? path = originalFile?.walletPath;
      HtlcStoreCapture? capturedStore;
      Box<dynamic>? pendingBox;
      Map<dynamic, dynamic>? pendingMap;
      HtlcHandlerStart? reservation;
      WalletInitializationConnection? observedConnection;

      bool owners() =>
          app.sl.isRegistered<HtlcSwapsService>() &&
          app.sl.isRegistered<HtlcSwapsHandler>() &&
          app.sl.isRegistered<AutoUnlockHtlcWorker>() &&
          app.sl.isRegistered<AutoReceiveTxWorker>() &&
          identical(app.htlcSwapsService, store) &&
          identical(app.sl<HtlcSwapsService>(), store) &&
          identical(app.sl<HtlcSwapsHandler>(), handler) &&
          identical(app.sl<AutoUnlockHtlcWorker>(), unlock) &&
          identical(app.sl<AutoReceiveTxWorker>(), receive) &&
          !store.isPaused &&
          !handler.isPaused &&
          !unlock.isPaused &&
          !receive.isPaused;
      bool mapCurrent(Box<dynamic> box, Map<dynamic, dynamic> expected) =>
          mapEquals(box.toMap(), expected) ||
          (identical(pendingBox, box) &&
              pendingMap != null &&
              mapEquals(box.toMap(), pendingMap));
      bool transport() =>
          identical(app.zenon, client) &&
          app.sl.isRegistered<Zenon>() &&
          identical(app.sl<Zenon>(), client) &&
          identical(client.wsClient, socket) &&
          identical(client.ledger, ledgerSource) &&
          identical(ledgerSource.client, socket) &&
          identical(client.stats, statsSource) &&
          identical(statsSource.client, socket) &&
          identical(client.embedded, embeddedSource) &&
          identical(embeddedSource.client, socket) &&
          identical(embeddedSource.htlc, htlcSource) &&
          identical(htlcSource.client, socket) &&
          identical(client.subscribe, subscribeSource) &&
          identical(subscribeSource.client, socket) &&
          identical(ledger.client, socket);
      bool lifetimeCurrent() {
        final String? anchor = committedBaseMember;
        return committed &&
            path != null &&
            anchor != null &&
            kWalletInitCompleted &&
            kWalletPath == path &&
            owners() &&
            transport() &&
            capturedStore?.isCurrent == true &&
            identical(preferences, app.sharedPrefsService) &&
            _owns(pointer) &&
            pointer.length == 1 &&
            pointer.get(0) == path &&
            _owns(members) &&
            members.get(0) == anchor &&
            _owns(labels) &&
            _owns(prefs);
      }

      bool current() {
        if (retired) return false;
        bool valid;
        try {
          if (committed) {
            // Startup remains bound to its original file after publication.
            // The handler has a separate, explicitly committed lifetime.
            valid =
                file != null &&
                identical(kWalletFile, file) &&
                lifetimeCurrent();
          } else {
            valid =
                (sourceIsCurrent?.call() ?? true) &&
                WalletContextRevision.value == revision &&
                identical(kWalletFile, initialFile) &&
                kWalletPath == initialPath &&
                !kWalletInitCompleted &&
                kSelectedAddress == initialSelected &&
                kNodeChainId == initialNodeChain &&
                kCurrentNode == node &&
                getChainIdentifier() == chain &&
                listEquals(kDefaultAddressList, initialMembers) &&
                mapEquals(kAddressLabelMap, initialLabels) &&
                identical(preferences, app.sharedPrefsService) &&
                _owns(pointer) &&
                _owns(members) &&
                _owns(labels) &&
                _owns(prefs) &&
                prefs.containsKey(kSelectedNodeKey) == selectedNodeExists &&
                mapCurrent(pointer, expectedPointer) &&
                mapCurrent(members, expectedMembers) &&
                mapCurrent(labels, expectedLabels) &&
                expectedPrefs.entries.every(
                  (MapEntry<dynamic, dynamic> entry) =>
                      prefs.get(entry.key) == entry.value ||
                      (identical(pendingBox, prefs) &&
                          pendingMap != null &&
                          prefs.get(entry.key) == pendingMap![entry.key]),
                ) &&
                owners() &&
                transport() &&
                !unlock.running &&
                unlock.pool.isEmpty &&
                unlock.operations.isEmpty &&
                !receive.running &&
                !receive.hasPending &&
                (!handler.hasStarted || reservation?.invoked == true) &&
                (transition == null
                    ? (acquiringTransition
                          ? NodeTransitions.pending
                          : !NodeTransitions.pending)
                    : releasedConnection
                    ? !NodeTransitions.pending
                    : transition!.isOwner) &&
                (storeOpening ||
                    (store.operations.isEmpty &&
                        store.captureSwapsBox() == null) ||
                    capturedStore?.isCurrent == true) &&
                (connecting ? socket.url == url : socket.url == initialUrl) &&
                (connecting || socket.status() == initialStatus);
          }
        } on Object {
          valid = false;
        }
        retired = retired || !valid;
        return !retired;
      }

      final WalletInitializationLifetime lifetime =
          WalletInitializationLifetime(
            startupIsCurrent: current,
            committedSourceIsCurrent: () =>
                committed && identical(kWalletFile, file) && current(),
            ownerIsCurrent: lifetimeCurrent,
          );

      void require() {
        if (!current()) throw const WalletInitializationRefused('source');
      }

      Future<void> write(
        Box<dynamic> box,
        Map<dynamic, dynamic> expected,
        dynamic key,
        dynamic value,
        WalletInitializationRun run,
      ) async {
        require();
        final Map<dynamic, dynamic> next = Map<dynamic, dynamic>.of(expected)
          ..[key] = value;
        pendingBox = box;
        pendingMap = next;
        await run.observe<void>('startup-write', () => box.put(key, value));
        require();
        if (box.get(key) != value) {
          throw const WalletInitializationRefused('write');
        }
        expected[key] = value;
        pendingBox = null;
        pendingMap = null;
        await run.observe<void>('startup-flush', box.flush);
        require();
      }

      if (!current()) return null;
      return WalletInitializationBinding(
        identity: pointer,
        connectionOwner: socket,
        startupAdmissionReceipt: () => reservation,
        isCurrent: current,
        begin: () {
          require();
          if (!OriginalPublications.canChangeTransport(client)) {
            throw const WalletInitializationRefused('transport-publication');
          }
          // Capturing decrypt capabilities cannot consume a startup reservation
          // before authentication. Begin still precedes creation.
          reservation = handler.reserveStart(
            isCurrent: () => lifetime.isCurrent,
          );
          if (reservation == null ||
              !identical(reservation!.identity, handler) ||
              !reservation!.canActivate) {
            throw const WalletInitializationRefused('startup-reservation');
          }
          require();
          revision = WalletContextRevision.value + 1;
          // Ownership is installed before begin notifies synchronous observers.
          acquiringTransition = true;
          transition = NodeTransitions.begin();
          acquiringTransition = false;
          if (transition == null ||
              transition!.revision != revision ||
              !transition!.isOwner) {
            throw const WalletInitializationRefused('transition');
          }
        },
        protect: (Object original, Future<void> Function() action) =>
            OriginalPublications.run<void>(
              original,
              (OriginalPublication<void> _) => action(),
            ),
        prepare: (Object original, WalletInitializationRun run) async {
          require();
          if (original is! WalletFile ||
              original.isOpen ||
              (file != null && !identical(file, original))) {
            throw const WalletInitializationRefused('file');
          }
          file = original;
          path = original.walletPath;
          if (path!.isEmpty || (initialPath != null && path != initialPath)) {
            throw const WalletInitializationRefused('path');
          }
          final int count = expectedMembers.isEmpty
              ? kNumOfInitialAddresses
              : expectedMembers.length;
          if (count <= 0 ||
              expectedMembers.keys.any(
                (dynamic key) => key is! int || key < 0 || key >= count,
              )) {
            throw const WalletInitializationRefused('members');
          }
          final List<String> derived = <String>[];
          await OriginalPublications.run<void>(original, (
            OriginalPublication<void> operation,
          ) async {
            final Wallet acquired = await run.observe<Wallet>(
              'file-acquire',
              original.open,
            );
            try {
              require();
              for (int index = 0; index < count; index++) {
                final WalletAccount account = await run.observe<WalletAccount>(
                  'derive-account',
                  () => acquired.getAccount(index),
                );
                require();
                final Address address = await run.observe<Address>(
                  'derive-address',
                  account.getAddress,
                );
                require();
                final String value = address.toString();
                if (Address.parse(value).toString() != value ||
                    derived.contains(value) ||
                    (expectedMembers.isNotEmpty &&
                        expectedMembers[index] != value)) {
                  throw const WalletInitializationRefused('membership');
                }
                derived.add(value);
              }
            } finally {
              try {
                await run.observe<void>('file-release', original.close);
              } on Object catch (error, trace) {
                operation.recordReleaseFailure(error, trace);
                rethrow;
              }
            }
          });
          require();
          if (original.isOpen) {
            throw const WalletInitializationRefused('release');
          }
          final Map<String, String> names = <String, String>{};
          for (final MapEntry<dynamic, dynamic> entry
              in expectedLabels.entries) {
            if (entry.key is! String ||
                entry.value is! String ||
                Address.parse(entry.key as String).toString() != entry.key ||
                !derived.contains(entry.key) ||
                (entry.value as String).length > kAddressLabelMaxLength) {
              throw const WalletInitializationRefused('labels');
            }
            names[entry.key as String] = entry.value as String;
          }
          for (int index = 0; index < derived.length; index++) {
            names.putIfAbsent(derived[index], () => defaultLabel(index + 1));
          }
          final dynamic storedSelected = expectedPrefs[kDefaultAddressKey];
          if (storedSelected != null &&
              (storedSelected is! String ||
                  !derived.contains(storedSelected))) {
            throw const WalletInitializationRefused('selected');
          }
          return WalletInitializationData(
            path: path!,
            members: derived,
            labels: names,
            selected: storedSelected as String? ?? derived.first,
            chainId: chain,
          );
        },
        persist:
            (
              Object original,
              WalletInitializationData data,
              List<int> key,
              WalletInitializationRun run,
            ) async {
              require();
              if (!identical(original, file)) {
                throw const WalletInitializationRefused('file');
              }
              for (int index = 0; index < data.members.length; index++) {
                if (!expectedMembers.containsKey(index)) {
                  await write(
                    members,
                    expectedMembers,
                    index,
                    data.members[index],
                    run,
                  );
                }
              }
              for (final MapEntry<String, String> entry
                  in data.labels.entries) {
                if (!expectedLabels.containsKey(entry.key)) {
                  await write(
                    labels,
                    expectedLabels,
                    entry.key,
                    entry.value,
                    run,
                  );
                }
              }
              require();
              storeOpening = true;
              await run.observe<void>(
                'open-original-htlc',
                () => store.openBoxes(data.members.first, key),
              );
              require();
              capturedStore = store.captureStore(chainId: chain);
              if (capturedStore?.isCurrent != true) {
                throw const WalletInitializationRefused('store');
              }
              storeOpening = false;
              if (expectedPointer[0] != data.path) {
                await write(pointer, expectedPointer, 0, data.path, run);
              }
              if (expectedPrefs[kDefaultAddressKey] == null) {
                await write(
                  prefs,
                  expectedPrefs,
                  kDefaultAddressKey,
                  data.selected,
                  run,
                );
              }
              if (expectedPrefs[kWalletVersionKey] != kWalletVersion) {
                await write(
                  prefs,
                  expectedPrefs,
                  kWalletVersionKey,
                  kWalletVersion,
                  run,
                );
              }
            },
        connect: (WalletInitializationRun run) async {
          require();
          NodeReceiveBinding.register(client);
          WalletInitializationConnection receipt({
            required bool connected,
            int? observedChain,
            bool uncertain = false,
          }) {
            final WalletInitializationConnection value =
                WalletInitializationConnection(
                  owner: socket,
                  connected: connected,
                  chainId: observedChain,
                  state: observedChain == null
                      ? WalletInitializationNetworkState.unavailable
                      : observedChain == chain
                      ? WalletInitializationNetworkState.compatible
                      : WalletInitializationNetworkState.knownMismatch,
                  transportUncertain: uncertain,
                );
            observedConnection = value;
            return value;
          }

          // First-profile creation reaches the existing node picker without
          // inventing a default node or requesting an empty-URL connection.
          if (url == null) return receipt(connected: false);

          if (initialStatus == WebsocketStatus.uninitialized) {
            // The SDK transport is shared and has no awaitable cancellation.
            // A failed/late attempt retains quarantine, while exact local
            // authentication receipts can still establish read-only access.
            connecting = true;
            bool connected;
            try {
              connected = await run.observe<bool>(
                'connect-original-socket',
                () => socket.initialize(url, retry: false),
              );
            } on Object {
              require();
              return receipt(connected: false, uncertain: true);
            }
            require();
            if (!connected &&
                node == kEmbeddedNode &&
                embeddedStopped != null) {
              // This is the existing embedded start path, after the actual
              // original initialize settled false. Exceptions never retry.
              try {
                await run.observe<void>(
                  'start-original-embedded-node',
                  () => NodeUtils.startEmbeddedNode(
                    stoppedPort: embeddedStopped,
                    requireCurrent: require,
                  ),
                );
                require();
                connected = await run.observe<bool>(
                  'connect-started-original-embedded-node',
                  () => socket.initialize(url, retry: false),
                );
              } on Object {
                require();
                return receipt(connected: false, uncertain: true);
              }
              require();
            }
            if (!connected) return receipt(connected: false, uncertain: true);
          }
          if (socket.status() != WebsocketStatus.running ||
              socket.url != url ||
              socket.isClosed()) {
            return receipt(connected: false, uncertain: true);
          }
          Momentum momentum;
          try {
            momentum = await run.observe<Momentum>(
              'read-original-frontier',
              ledger.getFrontierMomentum,
            );
          } on Object {
            require();
            final bool stillConnected =
                socket.status() == WebsocketStatus.running &&
                socket.url == url &&
                !socket.isClosed();
            return receipt(
              connected: stillConnected,
              uncertain: !stillConnected,
            );
          }
          require();
          if (socket.status() != WebsocketStatus.running ||
              socket.url != url ||
              socket.isClosed()) {
            return receipt(connected: false, uncertain: true);
          }
          if (momentum.timestamp <= 0 ||
              momentum.height <= 0 ||
              momentum.chainIdentifier <= 0) {
            return receipt(connected: true);
          }
          return receipt(
            connected: true,
            observedChain: momentum.chainIdentifier,
          );
        },
        admitLocal: (WalletInitializationConnection connection) {
          require();
          if (!identical(connection, observedConnection) ||
              capturedStore?.isCurrent != true ||
              transition?.isOwner != true) {
            return false;
          }
          if (url == null) {
            if (connection.connected ||
                connection.chainId != null ||
                connection.transportUncertain ||
                socket.status() != initialStatus ||
                socket.url != initialUrl) {
              return false;
            }
            // No transport operation was admitted. The captured uninitialized
            // socket is positively unchanged; no uncertain attempt is released.
            revision = WalletContextRevision.value + 1;
            releasedConnection = true;
            localBoundaryAdmitted = true;
            return transition!.complete() && current();
          }
          if (connection.transportUncertain) {
            // Local initialization is positive; terminal transport ownership
            // remains unknown. No restoration or close receipt is invented.
            localBoundaryAdmitted = true;
            return current();
          }
          if (!connection.connected ||
              socket.status() != WebsocketStatus.running ||
              socket.url != url ||
              socket.isClosed()) {
            return false;
          }
          revision = WalletContextRevision.value + 1;
          releasedConnection = true;
          localBoundaryAdmitted = true;
          return transition!.complete() && current();
        },
        activate: () {
          require();
          return reservation!.activate();
        },
        publish: (Object original, WalletInitializationData data) {
          require();
          if (committed ||
              !identical(original, file) ||
              path != data.path ||
              !reservation!.invoked ||
              capturedStore?.isCurrent != true ||
              !localBoundaryAdmitted ||
              observedConnection == null) {
            return false;
          }
          // These plain assignments contain no await or observer. The lifetime
          // guard is bound before the single synchronous revision notification.
          kWalletFile = file;
          kWalletPath = data.path;
          kDefaultAddressList = List<String?>.of(data.members);
          kAddressLabelMap = Map<String, String>.of(data.labels);
          kSelectedAddress = data.selected;
          kNodeChainId = observedConnection!.chainId;
          kWalletInitCompleted = true;
          committedBaseMember = data.members.first;
          committed = true;
          if (!lifetime.handoff()) {
            throw const WalletInitializationRefused('service-handoff');
          }
          WalletContextRevision.invalidate();
          return true;
        },
      );
    } on Object {
      return null;
    }
  }
}
