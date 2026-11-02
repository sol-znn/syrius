import 'dart:io';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Captures identity and scalar receipts before a preference crosses an await.
class WalletSettingsResources {
  /// Injected getters permit ownership tests without a wallet or native client.
  WalletSettingsResources({
    required List<Object?> Function() identities,
    required List<Object?> Function() values,
    required this._ready,
    List<Object?>? originalIdentities,
    List<Object?>? originalValues,
  }) : _identities = List<Object?>.unmodifiable(
         originalIdentities ?? identities(),
       ),
       _values = List<Object?>.unmodifiable(originalValues ?? values()),
       _readIdentities = identities,
       _readValues = values;

  final List<Object?> _identities;
  final List<Object?> _values;
  final List<Object?> Function() _readIdentities;
  final List<Object?> Function() _readValues;
  final bool Function() _ready;
  bool _revoked = false;

  /// Once any original resource leaves, returning cannot revive this receipt.
  bool get isCurrent {
    if (_revoked) {
      return false;
    }
    try {
      final List<Object?> identities = _readIdentities();
      final bool same =
          identities.length == _identities.length &&
          List<bool>.generate(
            identities.length,
            (int index) => identical(identities[index], _identities[index]),
          ).every((bool same) => same);
      final bool valid = _ready() && same && listEquals(_values, _readValues());
      _revoked = _revoked || !valid;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }
}

class _CapturedPreferences implements WalletPreferenceStore {
  _CapturedPreferences(this.box);

  final Box<dynamic> box;

  @override
  Object get identity => box;

  @override
  WalletStoredPreference read(WalletPreference preference) =>
      WalletStoredPreference(
        exists: box.containsKey(preference.key),
        value: box.get(preference.key),
      );

  @override
  Future<void> write(WalletPreference preference, {required bool value}) =>
      box.put(preference.key, value);
}

/// Production capture shared by Wallet and the existing startup preference row.
/// No box, package metadata, platform service or RPC is opened during capture.
WalletSettingsBinding? captureWalletSettingsBinding({
  required Future<void> Function() scanForReceives,
  bool Function()? senderIsCurrent,
}) {
  final int revision = WalletContextRevision.value;
  final Object? wallet = kWalletFile;
  final String? walletPath = kWalletPath;
  final bool initialized = kWalletInitCompleted;
  final String? selected = kSelectedAddress;
  final List<String?> addresses = List<String?>.of(kDefaultAddressList);
  final String? node = kCurrentNode;
  final int? nodeChain = kNodeChainId;
  final int chain = getChainIdentifier();
  final SharedPrefsService? preferences = app.sharedPrefsService;
  final Zenon? client = app.zenon;
  if (preferences == null ||
      NodeTransitions.pending ||
      !Hive.isBoxOpen(kSharedPrefsBox)) {
    return null;
  }
  final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
  final WsClient? socket = client?.wsClient;
  final LedgerApi? ledger = client?.ledger;
  final StatsApi? stats = client?.stats;
  final Client? ledgerClient = ledger?.client;
  final Client? statsClient = stats?.client;
  final AutoReceiveTxWorker? worker = app.sl.isRegistered<AutoReceiveTxWorker>()
      ? app.sl<AutoReceiveTxWorker>()
      : null;
  final NotificationsBloc? notifications =
      app.sl.isRegistered<NotificationsBloc>()
      ? app.sl<NotificationsBloc>()
      : null;
  final Box<dynamic>? notificationBox = Hive.isBoxOpen(kNotificationsBox)
      ? Hive.box<dynamic>(kNotificationsBox)
      : null;
  final ClipboardWatcher watcher = clipboardWatcher;
  final ValueNotifier<String?> uri = kLastWalletConnectUriNotifier;
  final LaunchAtStartup startup = launchAtStartup;
  final String executable = Platform.resolvedExecutable;
  final AppLocalizations messages = currentL10n;
  final String? socketUrl = socket?.url;
  final String? ledgerUrl = ledgerClient is WsClient ? ledgerClient.url : null;
  final String? statsUrl = statsClient is WsClient ? statsClient.url : null;
  final WalletSettingsResources resources = WalletSettingsResources(
    originalIdentities: <Object?>[
      preferences,
      box,
      wallet,
      client,
      socket,
      ledger,
      stats,
      ledgerClient,
      statsClient,
      watcher,
      uri,
      worker,
      notifications,
      notificationBox,
    ],
    originalValues: <Object?>[
      revision,
      walletPath,
      initialized,
      selected,
      ...addresses,
      node,
      nodeChain,
      chain,
      socketUrl,
      ledgerUrl,
      statsUrl,
    ],
    identities: () => <Object?>[
      app.sharedPrefsService,
      if (Hive.isBoxOpen(kSharedPrefsBox))
        Hive.box<dynamic>(kSharedPrefsBox)
      else
        null,
      kWalletFile,
      app.zenon,
      client?.wsClient,
      client?.ledger,
      client?.stats,
      ledger?.client,
      stats?.client,
      clipboardWatcher,
      kLastWalletConnectUriNotifier,
      if (app.sl.isRegistered<AutoReceiveTxWorker>())
        app.sl<AutoReceiveTxWorker>()
      else
        null,
      if (app.sl.isRegistered<NotificationsBloc>())
        app.sl<NotificationsBloc>()
      else
        null,
      if (Hive.isBoxOpen(kNotificationsBox))
        Hive.box<dynamic>(kNotificationsBox)
      else
        null,
    ],
    values: () => <Object?>[
      WalletContextRevision.value,
      kWalletPath,
      kWalletInitCompleted,
      kSelectedAddress,
      ...kDefaultAddressList,
      kCurrentNode,
      kNodeChainId,
      getChainIdentifier(),
      client?.wsClient.url,
      if (ledgerClient is WsClient) ledgerClient.url else null,
      if (statsClient is WsClient) statsClient.url else null,
    ],
    ready: () =>
        !NodeTransitions.pending &&
        box.isOpen &&
        (senderIsCurrent?.call() ?? true),
  );
  if (!resources.isCurrent) {
    return null;
  }
  final Map<WalletPreference, WalletNotification> notices =
      <WalletPreference, WalletNotification>{};
  String label(WalletPreference preference) => switch (preference) {
    WalletPreference.autoReceive => messages.walletSettingsAutoReceive,
    WalletPreference.desktopNotifications =>
      messages.walletSettingsDesktopNotifications,
    WalletPreference.launchAtStartup => messages.walletSettingsLaunchAtStartup,
    WalletPreference.clipboard => messages.walletSettingsClipboard,
  };
  return WalletSettingsBinding(
    store: _CapturedPreferences(box),
    ownsResources: () => resources.isCurrent,
    apply:
        (
          WalletPreference preference, {
          required bool value,
          required bool Function() ownsResources,
        }) async {
          final bool Function() owns = ownsResources;
          if (!owns()) {
            return false;
          }
          switch (preference) {
            case WalletPreference.autoReceive:
              if (value) {
                await scanForReceives();
              } else {
                // Advance the queue epoch even if no item is visible yet.
                worker?.clearAutomatic();
              }
            case WalletPreference.desktopNotifications:
              // Existing notification delivery reads this committed preference.
              break;
            case WalletPreference.launchAtStartup:
              final PackageInfo package = await PackageInfo.fromPlatform();
              if (!owns()) {
                return false;
              }
              startup.setup(appName: package.appName, appPath: executable);
              if (!owns()) {
                return false;
              }
              // The plugin's boolean is an actual result, not just completion.
              return value ? startup.enable() : startup.disable();
            case WalletPreference.clipboard:
              if (value) {
                await watcher.start();
              } else {
                uri.value = null;
                if (!owns()) {
                  return false;
                }
                await watcher.stop();
              }
          }
          return null;
        },
    notify: notificationBox == null || notifications == null
        ? null
        : (
            WalletPreference preference, {
            required bool value,
            required bool Function() canDisplay,
          }) {
            if (!canDisplay()) {
              return Future<void>.value();
            }
            final WalletNotification event = WalletNotification(
              title: label(preference),
              details: value
                  ? messages.walletSettingsOn
                  : messages.walletSettingsOff,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              type: NotificationType.paymentSent,
            );
            notices[preference] = event;
            return notificationBox.add(event);
          },
    display: notifications == null
        ? null
        : (
            WalletPreference preference, {
            required bool value,
            required bool Function() canDisplay,
          }) {
            final WalletNotification? event = notices.remove(preference);
            if (canDisplay() && event != null) {
              notifications.addEvent(event);
            }
          },
  );
}
