import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A finite injectable origin. No reader or sender can discover a replacement.
class HtlcWorkerOrigin {
  /// Freezes members, bound readers, signer and owned side effects.
  HtlcWorkerOrigin({
    required this.walletIdentity,
    required this.store,
    required this.chainId,
    required this.selected,
    required Iterable<String> members,
    required this._isCurrent,
    required this.readSync,
    required this.readFrontier,
    required this.readBlocks,
    required this.readBlock,
    required this.readLive,
    required this.readChainTime,
    required this.buildUnlock,
    required this.publish,
    required this.notify,
    required this.canNotify,
    required this.enableWakeLock,
    required this.disableWakeLock,
  }) : members = List<String>.unmodifiable(members);

  /// Original wallet file identity, never a path or decrypted wallet material.
  final Object walletIdentity;

  /// Exact original encrypted catalogue and chain-cursor backends.
  final HtlcStoreCapture store;

  /// Positive chain identifier shared by every bound API and publication.
  final int chainId;

  /// Selection captured with this origin; signers may use other owned members.
  final String selected;

  /// Immutable complete wallet membership at capture.
  final List<String> members;
  final bool Function() _isCurrent;

  /// Original Stats transport's synchronization result.
  final Future<SyncInfo> Function() readSync;

  /// Original ledger's HTLC contract frontier, including an honest null result.
  final Future<AccountBlock?> Function() readFrontier;

  /// Exact height page from the original HTLC account chain.
  final Future<List<AccountBlock>?> Function(int height, int count) readBlocks;

  /// Exact-hash lookup used to prove original Create and withdrawal events.
  final Future<AccountBlock?> Function(String id) readBlock;

  /// Current deposit lookup; an error never establishes spent or expired state.
  final Future<HtlcInfo> Function(String id) readLive;

  /// Positive timestamp from the original chain's frontier momentum.
  final Future<int> Function() readChainTime;

  /// Pure original SDK builder for one exact deposit and copied preimage.
  final AccountBlockTemplate Function(String id, List<int> value) buildUnlock;

  /// Captured member signer; its actual Future and accepted block are retained.
  final Future<AccountBlockTemplate> Function(
    AccountBlockTemplate block,
    String target,
  )
  publish;

  /// Writes only to the captured notification owner and original Box.
  final Future<void> Function(WalletNotification value) notify;

  /// Whether the exact notification owner and store were available at capture.
  final bool canNotify;

  /// Acquires the original handler's wake-lock lifecycle.
  final Future<void> Function() enableWakeLock;

  /// Releases only that handler's admitted original wake-lock lifecycle.
  final Future<void> Function() disableWakeLock;
  bool _revoked = false;

  /// Monotonic ownership guard; a source that changed cannot return by ABA.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final bool lost =
          chainId <= 0 ||
          !members.contains(selected) ||
          members.toSet().length != members.length ||
          !store.isCurrent ||
          !_isCurrent();
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Refuses before admitting work if any captured resource lost ownership.
  void requireCurrent() {
    if (!isCurrent) throw const HtlcOwnershipRefused('worker-origin-changed');
  }
}

/// Binds file, members, actual Boxes, APIs, Clients and URLs before awaiting.
HtlcWorkerOrigin? captureHtlcWorkerOrigin({
  required bool Function() ownerIsCurrent,
}) {
  try {
    final String? selected = kSelectedAddress;
    final Object? wallet = kWalletFile;
    final String? path = kWalletPath;
    final List<String?> members = List<String?>.of(kDefaultAddressList);
    final int chain = getChainIdentifier();
    final HtlcSwapsService? service = app.htlcSwapsService;
    final Zenon? client = app.zenon;
    final WalletActionContext? action = selected == null
        ? null
        : WalletActionContext.capture(selected);
    final HtlcStoreCapture? store = service?.captureStore(chainId: chain);
    if (wallet == null ||
        path == null ||
        selected == null ||
        client == null ||
        action == null ||
        store == null ||
        chain <= 0 ||
        kNodeChainId != chain ||
        members.isEmpty ||
        members.any(
          (String? value) =>
              value == null || Address.parse(value).toString() != value,
        ) ||
        !members.contains(selected) ||
        members.toSet().length != members.length ||
        !Hive.isBoxOpen(kAddressesBox) ||
        !ownerIsCurrent()) {
      return null;
    }
    final Box<dynamic> addresses = Hive.box<dynamic>(kAddressesBox);
    if (!listEquals(members, addresses.values.toList())) return null;
    final LedgerApi ledgerSource = client.ledger;
    final HtlcApi htlcSource = client.embedded.htlc;
    final StatsApi statsSource = client.stats;
    final Client ledgerTransport = ledgerSource.client;
    final Client htlcTransport = htlcSource.client;
    final Client statsTransport = statsSource.client;
    final WsClient socket = client.wsClient;
    if (!identical(ledgerTransport, socket) ||
        !identical(htlcTransport, socket) ||
        !identical(statsTransport, socket) ||
        socket.url == null ||
        socket.url!.isEmpty) {
      return null;
    }
    final String? ledgerUrl = ledgerTransport is WsClient
        ? ledgerTransport.url
        : null;
    final String? htlcUrl = htlcTransport is WsClient
        ? htlcTransport.url
        : null;
    final String? statsUrl = statsTransport is WsClient
        ? statsTransport.url
        : null;
    final LedgerApi ledger = LedgerApi()..setClient(ledgerTransport);
    final HtlcApi htlc = HtlcApi()..setClient(htlcTransport);
    final StatsApi stats = StatsApi()..setClient(statsTransport);
    final NotificationsBloc? notifications =
        app.sl.isRegistered<NotificationsBloc>()
        ? app.sl<NotificationsBloc>()
        : null;
    final Box<dynamic>? notificationStore = Hive.isBoxOpen(kNotificationsBox)
        ? Hive.box<dynamic>(kNotificationsBox)
        : null;
    bool revoked = false;
    bool current() {
      if (revoked) return false;
      revoked =
          !ownerIsCurrent() ||
          !action.isCurrent ||
          !store.isCurrent ||
          !identical(app.htlcSwapsService, service) ||
          !identical(app.zenon, client) ||
          !addresses.isOpen ||
          !Hive.isBoxOpen(kAddressesBox) ||
          !identical(Hive.box<dynamic>(kAddressesBox), addresses) ||
          !listEquals(members, addresses.values.toList()) ||
          !identical(client.ledger, ledgerSource) ||
          !identical(client.embedded.htlc, htlcSource) ||
          !identical(client.stats, statsSource) ||
          !identical(client.wsClient, socket) ||
          !identical(ledgerSource.client, ledgerTransport) ||
          !identical(htlcSource.client, htlcTransport) ||
          !identical(statsSource.client, statsTransport) ||
          (ledgerTransport is WsClient && ledgerTransport.url != ledgerUrl) ||
          (htlcTransport is WsClient && htlcTransport.url != htlcUrl) ||
          (statsTransport is WsClient && statsTransport.url != statsUrl);
      return !revoked;
    }

    if (!current()) return null;
    // Each member's signer keeps the original selected address as its context.
    final Map<String, AccountBlockUtils> senders = <String, AccountBlockUtils>{
      for (final String target in members.cast<String>())
        target: AccountBlockUtils.capture(
          address: Address.parse(target),
          canPublish: current,
        ),
    };
    void requireCurrent() {
      if (!current()) throw const HtlcOwnershipRefused('worker-origin-changed');
    }

    return HtlcWorkerOrigin(
      walletIdentity: wallet,
      store: store,
      chainId: chain,
      selected: selected,
      members: members.cast<String>(),
      isCurrent: current,
      canNotify:
          notifications != null &&
          notificationStore != null &&
          notifications.ownsOriginalStore(notificationStore),
      readSync: () {
        requireCurrent();
        return stats.syncInfo();
      },
      readFrontier: () {
        requireCurrent();
        return ledger.getFrontierAccountBlock(htlcAddress);
      },
      readBlocks: (int height, int count) async {
        requireCurrent();
        return (await ledger.getAccountBlocksByHeight(
          htlcAddress,
          height,
          count,
        )).list;
      },
      readBlock: (String id) {
        requireCurrent();
        return ledger.getAccountBlockByHash(Hash.parse(id));
      },
      readLive: (String id) {
        requireCurrent();
        return htlc.getById(Hash.parse(id));
      },
      readChainTime: () async {
        requireCurrent();
        final Momentum value = await ledger.getFrontierMomentum();
        if (value.chainIdentifier != chain || value.timestamp <= 0) {
          throw const HtlcOwnershipRefused('chain-time-unproven');
        }
        return value.timestamp;
      },
      buildUnlock: (String id, List<int> value) {
        requireCurrent();
        return htlc.unlock(Hash.parse(id), List<int>.of(value))
          ..chainIdentifier = chain;
      },
      publish: (AccountBlockTemplate block, String target) {
        requireCurrent();
        final AccountBlockUtils? sender = senders[target];
        if (sender == null) {
          throw const HtlcOwnershipRefused('recipient-not-owned');
        }
        return sender.createAccountBlock(
          block,
          PlasmaPurpose.completeSwap.message,
          address: Address.parse(target),
          waitForRequiredPlasma: true,
          canPublish: current,
        );
      },
      notify: (WalletNotification value) async {
        if (notifications == null || notificationStore == null) {
          throw const HtlcOwnershipRefused('notification-owner-absent');
        }
        final NotificationWriteReceipt receipt = await notifications
            .writeNotification(
              value,
              originalStore: notificationStore,
              shouldDisplay: current,
            );
        if (!identical(receipt.owner, notifications) ||
            !identical(receipt.store, notificationStore) ||
            !receipt.completed) {
          Error.throwWithStackTrace(
            receipt.error ??
                const HtlcOwnershipRefused('notification-unproven'),
            receipt.stackTrace ?? StackTrace.current,
          );
        }
      },
      enableWakeLock: WakelockPlus.enable,
      disableWakeLock: WakelockPlus.disable,
    );
  } on Object {
    return null;
  }
}
