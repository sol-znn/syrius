import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_channel.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/server/dapp_bridge_consent.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_binding.dart'
    show WalletSettingsResources;
import 'package:znn_sdk_dart/znn_sdk_dart.dart' show getChainIdentifier;

/// Captures existing open resources. It never opens a box, socket or wallet.
AppsSettingsBinding? captureAppsSettingsBinding() {
  if (!Hive.isBoxOpen(kSharedPrefsBox) || NodeTransitions.pending) return null;
  final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
  final Object? preferences = app.sharedPrefsService;
  final Object? wallet = kWalletFile;
  final Object? client = app.zenon;
  final int revision = WalletContextRevision.value;
  final String? walletPath = kWalletPath;
  final String? selected = kSelectedAddress;
  final String? node = kCurrentNode;
  final int? nodeChain = kNodeChainId;
  final int chain = getChainIdentifier();
  final List<String?> addresses = List<String?>.of(kDefaultAddressList);
  final Map<String, String> labels = Map<String, String>.of(kAddressLabelMap);
  final DappBridgeControl? control = DappBridgeControl.app;
  final IWeb3WalletService? service = app.sl.isRegistered<IWeb3WalletService>()
      ? app.sl<IWeb3WalletService>()
      : null;
  final ValueNotifier<String?> incoming = kLastWalletConnectUriNotifier;
  DappBridgeActions? web;
  Web3WalletActions? wc;
  try {
    if (control case final DappBridgeOwnedControl original) {
      web = original.captureActions();
    }
  } on Object {
    // An unavailable original backend is rendered as unavailable.
  }
  try {
    if (service case final CapturedWeb3WalletService original) {
      wc = original.captureActions();
    }
  } on Object {
    // Missing client configuration does not create an invented connection.
  }
  final DappBridgeActions? originalWeb = web;
  final Web3WalletActions? originalWc = wc;
  final WalletSettingsResources resources = WalletSettingsResources(
    originalIdentities: <Object?>[
      box,
      preferences,
      wallet,
      client,
      control,
      service,
      incoming,
    ],
    originalValues: <Object?>[
      revision,
      walletPath,
      selected,
      node,
      nodeChain,
      chain,
      ...addresses,
      ...labels.entries.map(
        (MapEntry<String, String> entry) => '${entry.key}:${entry.value}',
      ),
    ],
    identities: () => <Object?>[
      if (Hive.isBoxOpen(kSharedPrefsBox))
        Hive.box<dynamic>(kSharedPrefsBox)
      else
        null,
      app.sharedPrefsService,
      kWalletFile,
      app.zenon,
      DappBridgeControl.app,
      if (app.sl.isRegistered<IWeb3WalletService>())
        app.sl<IWeb3WalletService>()
      else
        null,
      kLastWalletConnectUriNotifier,
    ],
    values: () => <Object?>[
      WalletContextRevision.value,
      kWalletPath,
      kSelectedAddress,
      kCurrentNode,
      kNodeChainId,
      getChainIdentifier(),
      ...kDefaultAddressList,
      ...kAddressLabelMap.entries.map(
        (MapEntry<String, String> entry) => '${entry.key}:${entry.value}',
      ),
    ],
    ready: () =>
        kWalletInitCompleted &&
        wallet != null &&
        selected != null &&
        box.isOpen &&
        !NodeTransitions.pending &&
        (originalWeb?.isCurrent() ?? true) &&
        (originalWc?.isCurrent() ?? true),
  );
  if (!resources.isCurrent) return null;

  AppsSnapshot read() {
    if (!resources.isCurrent) return AppsSnapshot.unavailable();
    final List<AppsConnection> connections = <AppsConnection>[];
    final List<AppsPairing> pairings = <AppsPairing>[];
    if (originalWeb != null && control != null) {
      for (final DappBridgeSite site in control.sites) {
        connections.add(
          AppsConnection(
            identity: site.requester,
            incarnation: site.incarnation,
            kind: site.viaLink
                ? AppsConnectionKind.link
                : AppsConnectionKind.webApp,
            site: site.origin,
            accounts: site.addresses,
          ),
        );
      }
    }
    if (originalWc != null) {
      // Active sessions remain visible even if their pairing was deleted.
      for (final SessionData session in originalWc.activeSessions().values) {
        connections.add(
          AppsConnection(
            identity: session.topic,
            incarnation: session,
            kind: AppsConnectionKind.walletConnect,
            site: session.peer.metadata.name,
            url: _shownUrl(session.peer.metadata.url),
            accounts: <String>[
              for (final Namespace namespace in session.namespaces.values)
                ...namespace.accounts,
            ],
            pairingTopic: session.pairingTopic,
            expiry: session.expiry,
            acknowledged: session.acknowledged,
            scope: jsonEncode(<String, Object?>{
              for (final MapEntry<String, Namespace> entry
                  in session.namespaces.entries)
                entry.key: <String, Object?>{
                  'chains': entry.value.chains,
                  'accounts': entry.value.accounts,
                  'methods': entry.value.methods,
                  'events': entry.value.events,
                },
            }),
          ),
        );
      }
      for (final PairingInfo pairing in List<PairingInfo>.of(
        originalWc.pairings.value,
      )) {
        pairings.add(
          AppsPairing(
            topic: pairing.topic,
            incarnation: pairing,
            site: pairing.peerMetadata?.name ?? '',
            url: _shownUrl(pairing.peerMetadata?.url ?? ''),
            expiry: pairing.expiry,
            active: pairing.active,
          ),
        );
      }
    }
    return AppsSnapshot(
      webAppsAvailable: originalWeb != null,
      walletConnectAvailable: originalWc != null,
      enabled: originalWeb != null && (control?.enabled ?? false),
      port: originalWeb == null ? null : control?.port,
      connections: connections,
      pairings: pairings,
      labels: <String, String>{
        ...labels,
        for (final MapEntry<String, String> entry in labels.entries)
          'zenon:$chain:${entry.key}': entry.value,
      },
    );
  }

  final Stream<void> changes = Stream<void>.multi((
    MultiStreamController<void> controller,
  ) {
    void changed() => controller.add(null);
    final StreamSubscription<void>? webChanges = control?.changes.listen(
      (_) => changed(),
    );
    originalWc?.sessions.addListener(changed);
    originalWc?.pairings.addListener(changed);
    WalletContextRevision.changes.addListener(changed);
    controller.onCancel = () async {
      await webChanges?.cancel();
      originalWc?.sessions.removeListener(changed);
      originalWc?.pairings.removeListener(changed);
      WalletContextRevision.changes.removeListener(changed);
    };
  }, isBroadcast: true);

  void require(bool Function() owns) {
    if (!resources.isCurrent || !owns()) {
      throw StateError('Connection unavailable');
    }
  }

  return AppsSettingsBinding(
    identity: box,
    ownsResources: () => resources.isCurrent,
    read: read,
    changes: changes,
    incomingLink: incoming,
    persist: (AppsIntent intent) {
      if (!resources.isCurrent) throw StateError('Setting unavailable');
      return box.put('apps_operation_intent', intent.stored);
    },
    setEnabled: ({required bool enabled, required bool Function() owns}) {
      require(owns);
      final DappBridgeActions original =
          originalWeb ?? (throw StateError('Setting unavailable'));
      return original.setEnabled(enabled: enabled, owns: owns);
    },
    disconnect: (AppsConnection row, bool Function() owns) {
      require(owns);
      if (row.kind == AppsConnectionKind.walletConnect) {
        final Web3WalletActions original =
            originalWc ?? (throw StateError('Connection unavailable'));
        return original.disconnectSession(row.identity);
      }
      final DappBridgeActions original =
          originalWeb ?? (throw StateError('Connection unavailable'));
      return original.disconnect(
        DappBridgeSite(
          requester: row.identity,
          addresses: row.accounts,
          incarnation: row.incarnation,
        ),
        owns,
      );
    },
    disconnectPairing: (AppsPairing row, bool Function() owns) {
      require(owns);
      final Web3WalletActions original =
          originalWc ?? (throw StateError('Connection unavailable'));
      return original.disconnectPairing(row.topic);
    },
    pair: (Uri uri, bool Function() owns) {
      require(owns);
      final Web3WalletActions original =
          originalWc ?? (throw StateError('Connection unavailable'));
      return original.pair(uri);
    },
  );
}

/// Peer URLs are untrusted metadata; credentials and callback data stay hidden.
String _shownUrl(String input) {
  final Uri? uri = Uri.tryParse(input);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return '';
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}
