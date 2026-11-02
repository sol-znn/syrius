import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:logging/logging.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Observes an accepted block without signing, publishing or retrying it.
typedef PublicationObserver =
    void Function(
      AccountBlockTemplate block,
      Iterable<String> walletAddresses,
    );

/// Publishes account blocks through the existing wallet lock and plasma flow.
class AccountBlockUtils {
  /// Uses the wallet's flight registry unless an isolated observer is supplied.
  AccountBlockUtils({
    PublicationObserver? publicationObserver,
    this._canPublish,
  }) : _publicationObserver = publicationObserver ?? _observePublication,
       _capturedSession = null;

  AccountBlockUtils._captured(this._capturedSession, this._canPublish)
    : _publicationObserver = _observePublication;

  /// Binds the signer and session before a caller's first RPC or suspension.
  factory AccountBlockUtils.capture({
    required Address address,
    bool Function()? canPublish,
  }) {
    final _PublicationSession session = _PublicationSession.capture(address);
    if (!(canPublish?.call() ?? true)) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
    session.requireCurrent();
    return AccountBlockUtils._captured(session, canPublish);
  }

  final PublicationObserver _publicationObserver;
  final bool Function()? _canPublish;
  final _PublicationSession? _capturedSession;

  /// Returns the node's accepted template, preserving its exact published hash.
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purposeOfGeneratingPlasma, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) async {
    final _PublicationSession session =
        _capturedSession ?? _PublicationSession.capture(address);
    if (address != null &&
        address.toString() != session.addresses[session.accountIndex]) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
    return OriginalPublications.runForOwners<AccountBlockTemplate>(
      <Object>[session.walletFile, session.client],
      (OriginalPublication<AccountBlockTemplate> operation) => _publish(
        session,
        operation,
        transactionParams,
        purposeOfGeneratingPlasma,
        waitForRequiredPlasma: waitForRequiredPlasma,
        canPublish: canPublish,
      ),
    );
  }

  Future<AccountBlockTemplate> _publish(
    _PublicationSession session,
    OriginalPublication<AccountBlockTemplate> operation,
    AccountBlockTemplate transactionParams,
    String purposeOfGeneratingPlasma, {
    required bool waitForRequiredPlasma,
    bool Function()? canPublish,
  }) async {
    void requireCurrent() {
      if (!(_canPublish?.call() ?? true) || !(canPublish?.call() ?? true)) {
        throw FailureException(message: currentL10n.publicationSessionChanged);
      }
      session.requireCurrent();
    }

    requireCurrent();
    final SyncInfo syncInfo = await session.stats.syncInfo();
    requireCurrent();
    final bool nodeIsSynced =
        syncInfo.state == SyncState.syncDone ||
        (syncInfo.targetHeight > 0 &&
            syncInfo.currentHeight > 0 &&
            (syncInfo.targetHeight - syncInfo.currentHeight) < 20);
    if (!nodeIsSynced) throw NodeNotSyncedException();

    // An open can queue behind another publication. Only a returned wallet
    // belongs to this acquisition; a failed open releases its own lock.
    requireCurrent();
    final Wallet wallet = await session.walletFile.open();
    try {
      requireCurrent();
      final WalletAccount walletAccount = await wallet.getAccount(
        session.accountIndex,
      );
      requireCurrent();
      final bool needPlasma = await session.client.requiresPoW(
        transactionParams,
        blockSigningKey: walletAccount,
      );
      requireCurrent();
      // The existing SDK requiresPoW path sets this from the actual account's
      // public address. Refuse a membership/index mismatch before signing.
      if (transactionParams.address.toString() !=
          session.addresses[session.accountIndex]) {
        throw FailureException(message: currentL10n.publicationSessionChanged);
      }
      final bool needReview = session.walletFile.isHardwareWallet;

      if (needPlasma) {
        await session.notifications?.sendPlasmaNotification(
          purposeOfGeneratingPlasma,
          shouldDisplay: () => session.isCurrent,
          originalStore: session.notificationStore,
          requireOriginalStore: true,
        );
      } else if (needReview) {
        await _sendReviewNotification(transactionParams, session);
      }
      requireCurrent();
      // Once send starts, the SDK owns its outcome. Session changes only
      // suppress later displays; they cannot cancel or retry this publication.
      final AccountBlockTemplate response;
      try {
        await _display(session.claimPowWork);
        requireCurrent();
        response = await session.client.send(
          transactionParams,
          currentKeyPair: walletAccount,
          generatingPowCallback: (PowStatus status) {
            unawaited(
              _display(() async {
                if (!session.updatePowStatus(status)) return;
                // Record the real completion before optional hardware display
                // waits or fails. That display cannot own the generation clock.
                if (needReview && status == PowStatus.done) {
                  await _sendReviewNotification(
                    transactionParams,
                    session,
                    requirePowOwnership: true,
                  );
                }
              }),
            );
          },
          waitForRequiredPlasma: waitForRequiredPlasma,
        );
        operation.retainPublicationHash(response.hash.toString());
      } finally {
        // An SDK failure or a send with no done callback is not completion.
        // Its revoked token cannot clear a replacement send's display.
        await _display(session.releasePowWork);
      }
      // Observation and history retain the originating wallet even after lock.
      // Neither can replace a node-accepted result with an apparent send error.
      await _display(
        () => _publicationObserver(
          response,
          session.walletAddresses,
        ),
      );
      await _display(
        () => session.notifications?.addNotification(
          WalletNotification(
            title: currentL10n.accountBlockPublishedNotificationTitle,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            details: currentL10n.accountBlockPublishedNotificationDetails(
              FormatUtils.extractNameFromEnum<BlockTypeEnum>(
                BlockTypeEnum.values[response.blockType],
              ),
            ),
            type: NotificationType.paymentSent,
            eventKind: 'blockPublished',
            walletScope: bellScopeForWallet(
              session.chainId,
              session.walletAddresses,
            ),
            chainId: session.chainId,
            transactionHash: operation.acceptedHash,
          ),
          shouldDisplay: () => session.isCurrent,
          originalStore: session.notificationStore,
          requireOriginalStore: true,
        ),
      );

      // Keep the original frontier-processing delay under the acquired lock.
      await Future<void>.delayed(const Duration(seconds: 1));
      return response;
    } finally {
      try {
        await Future<void>.sync(session.walletFile.close);
      } on Object catch (error, stackTrace) {
        operation.recordReleaseFailure(error, stackTrace);
        // Releasing the original acquisition never closes a replacement file
        // and never changes an accepted result or hides the original failure.
        _reportObserverFailure(
          'Originating wallet release failed',
          error,
          stackTrace,
        );
      }
    }
  }

  /// Decodes a matching ABI entry without changing its encoded data.
  static BlockData? getDecodedBlockData(Abi abi, List<int> encodedData) {
    if (encodedData.length < AbiFunction.encodedSignLength) {
      return null;
    }
    final bool Function(List<int>? list1, List<int>? list2) eq =
        const ListEquality<int>().equals;
    try {
      for (final Entry entry in abi.entries) {
        if (eq(
          AbiFunction.extractSignature(entry.encodeSignature()),
          AbiFunction.extractSignature(encodedData),
        )) {
          final List<dynamic> decoded = AbiFunction(
            entry.name!,
            entry.inputs!,
          ).decode(encodedData);
          final Map<String, dynamic> params = <String, dynamic>{};
          for (int i = 0; i < entry.inputs!.length; i += 1) {
            params[entry.inputs![i].name!] = decoded[i];
          }
          return BlockData(function: entry.name!, params: params);
        }
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }

  /// Reads blocks through the existing paginated timestamp filter.
  static Future<List<AccountBlock>> getAccountBlocksAfterTime(
    Address address,
    int time, {
    LedgerApi? ledger,
    bool Function()? canRead,
    int maxPages = 4096,
  }) async {
    if (time < 0 || maxPages <= 0) throw StateError('Invalid history boundary');
    final LedgerApi source = ledger ?? zenon!.ledger;
    final Client transport = source.client;
    final String? url = transport is WsClient ? transport.url : null;
    final LedgerApi reader = LedgerApi()..setClient(transport);
    final int chainId = getChainIdentifier();
    void requireCurrent() {
      if (!(canRead?.call() ?? true) ||
          getChainIdentifier() != chainId ||
          !identical(source.client, transport) ||
          (transport is WsClient && transport.url != url)) {
        throw StateError('Original account history unavailable');
      }
    }

    final List<AccountBlock> blocks = <AccountBlock>[];
    int? nextHeight;
    Hash? nextHash;
    int? previousTimestamp;
    final Set<String> hashes = <String>{};
    for (int pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      requireCurrent();
      final AccountBlockList fetched = await reader.getAccountBlocksByPage(
        address,
        pageIndex: pageIndex,
        pageSize: 100,
      );
      requireCurrent();
      final List<AccountBlock>? page = fetched.list;
      if (page == null || page.length > 100) {
        throw StateError('Incomplete account history');
      }
      if (page.isEmpty) {
        if (pageIndex == 0 && fetched.count == 0 && fetched.more != true) {
          return <AccountBlock>[];
        }
        throw StateError('Incomplete account history');
      }
      for (final AccountBlock block in page) {
        final AccountBlockConfirmationDetail? confirmation =
            block.confirmationDetail;
        if (block.address != address ||
            block.chainIdentifier != chainId ||
            block.height <= 0 ||
            block.hash == emptyHash ||
            !hashes.add(block.hash.toString()) ||
            (nextHeight != null && block.height != nextHeight) ||
            (nextHash != null && block.hash != nextHash) ||
            confirmation == null ||
            confirmation.numConfirmations <= 0 ||
            confirmation.momentumTimestamp <= 0 ||
            (previousTimestamp != null &&
                confirmation.momentumTimestamp > previousTimestamp)) {
          throw StateError('Incomplete account history');
        }
        nextHeight = block.height - 1;
        nextHash = block.previousHash;
        previousTimestamp = confirmation.momentumTimestamp;
        if (confirmation.momentumTimestamp <= time) {
          return blocks.reversed.toList();
        }
        blocks.add(AccountBlock.fromJson(block.toJson()));
        if (block.height == 1) return blocks.reversed.toList();
      }
      // A short page above the cutoff or genesis is incomplete, regardless
      // of an optional pagination flag. It cannot establish hash absence.
      if (page.length != 100) throw StateError('Incomplete account history');
    }
    throw StateError('Account history limit reached');
  }

  /// Reads the confirmation timestamp of an exact account height.
  static Future<int?> getTimeForAccountBlockHeight(
    Address address,
    int height, {
    LedgerApi? ledger,
    bool Function()? canRead,
  }) async {
    final LedgerApi source = ledger ?? zenon!.ledger;
    final Client transport = source.client;
    final LedgerApi reader = LedgerApi()..setClient(transport);
    final String? url = transport is WsClient ? transport.url : null;
    final int chainId = getChainIdentifier();
    bool current() =>
        (canRead?.call() ?? true) &&
        getChainIdentifier() == chainId &&
        identical(source.client, transport) &&
        (transport is! WsClient || transport.url == url);
    if (!current()) return null;
    if (height >= 1) {
      try {
        final AccountBlockList block = await reader.getAccountBlocksByHeight(
          address,
          height,
          1,
        );
        if (current() && block.list?.length == 1) {
          final AccountBlock original = block.list!.single;
          final AccountBlockConfirmationDetail? confirmation =
              original.confirmationDetail;
          if (original.address == address &&
              original.height == height &&
              original.chainIdentifier == chainId &&
              original.hash != emptyHash &&
              confirmation != null &&
              confirmation.numConfirmations > 0 &&
              confirmation.momentumTimestamp > 0) {
            return confirmation.momentumTimestamp;
          }
        }
      } catch (e) {
        rethrow;
      }
    }
    return null;
  }

  static Future<void> _sendReviewNotification(
    AccountBlockTemplate transactionParams,
    _PublicationSession session, {
    bool requirePowOwnership = false,
  }) async {
    bool shouldDisplay() =>
        requirePowOwnership ? session.canDisplayPow : session.isCurrent;
    if (!shouldDisplay()) return;
    await session.notifications?.addNotification(
      WalletNotification(
        title: BlockUtils.isSendBlock(transactionParams.blockType)
            ? currentL10n.accountBlockReviewSendNotificationTitle
            : currentL10n.accountBlockReviewReceiveNotificationTitle,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: currentL10n.accountBlockReviewNotificationDetails(
          FormatUtils.extractNameFromEnum<BlockTypeEnum>(
            BlockTypeEnum.values[transactionParams.blockType],
          ),
        ),
        type: NotificationType.confirm,
      ),
      shouldDisplay: shouldDisplay,
      originalStore: session.notificationStore,
      requireOriginalStore: true,
    );
  }

  static void _observePublication(
    AccountBlockTemplate block,
    Iterable<String> walletAddresses,
  ) => WalletFlightRegistry.instance.published(block, walletAddresses);

  static Future<void> _display(FutureOr<void> Function() callback) async {
    try {
      await callback();
    } on Object catch (error, stackTrace) {
      _reportObserverFailure(
        'Publication display failed',
        error,
        stackTrace,
      );
    }
  }

  static void _reportObserverFailure(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      Logger('AccountBlockUtils').warning(message, error, stackTrace);
    } on Object {
      // A logging observer cannot replace the original publication outcome.
    }
  }
}

/// A source address and its clients are captured before the first suspension.
/// Reusing a retained wallet after lock would otherwise sign in a new session.
class _PublicationSession {
  _PublicationSession._({
    required this.client,
    required this.walletFile,
    required this.addresses,
    required this.accountIndex,
    required this.statsSource,
    required this.statsTransport,
  }) : contextRevision = WalletContextRevision.value,
       stats = StatsApi()..setClient(statsTransport),
       statsUrl = statsTransport is WsClient ? statsTransport.url : null,
       chainId = getChainIdentifier(),
       nodeChainId = kNodeChainId,
       node = kCurrentNode,
       walletPath = kWalletPath,
       selectedAddress = kSelectedAddress,
       initialized = kWalletInitCompleted,
       walletAddresses = List<String>.unmodifiable(
         addresses.whereType<String>(),
       ),
       notifications = sl.isRegistered<NotificationsBloc>()
           ? sl.get<NotificationsBloc>()
           : null,
       notificationStore = Hive.isBoxOpen(kNotificationsBox)
           ? Hive.box<dynamic>(kNotificationsBox)
           : null,
       powStatus = sl.isRegistered<PowGeneratingStatusBloc>()
           ? sl.get<PowGeneratingStatusBloc>()
           : null;

  factory _PublicationSession.capture(Address? address) {
    final Zenon? client = zenon;
    final WalletFile? walletFile = kWalletFile;
    final String? walletPath = kWalletPath;
    final int chainId = getChainIdentifier();
    final List<String?> addresses = List<String?>.unmodifiable(
      kDefaultAddressList,
    );
    final int index = addresses.indexOf(
      address?.toString() ?? kSelectedAddress,
    );
    if (NodeTransitions.pending ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        client == null ||
        walletFile == null ||
        walletPath == null ||
        walletFile.walletPath != walletPath ||
        chainId <= 0 ||
        kNodeChainId != chainId ||
        index < 0 ||
        addresses[index] == null) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
    final StatsApi statsSource = client.stats;
    final Client statsTransport = statsSource.client;
    return _PublicationSession._(
      client: client,
      walletFile: walletFile,
      addresses: addresses,
      accountIndex: index,
      statsSource: statsSource,
      statsTransport: statsTransport,
    );
  }

  final Zenon client;
  final WalletFile walletFile;
  final StatsApi stats;
  final StatsApi statsSource;
  final Client statsTransport;
  final String? statsUrl;
  final List<String?> addresses;
  final List<String> walletAddresses;
  final int accountIndex;
  final int contextRevision;
  final int chainId;
  final int? nodeChainId;
  final String? node;
  final String? walletPath;
  final String? selectedAddress;
  final bool initialized;
  final NotificationsBloc? notifications;
  final Box<dynamic>? notificationStore;
  final PowGeneratingStatusBloc? powStatus;
  PowWorkToken? _powWork;
  bool _powActive = false;
  bool _revoked = false;

  bool get isCurrent {
    if (_revoked) return false;
    final Client statsTransport = this.statsTransport;
    final bool current =
        !NodeTransitions.pending &&
        WalletContextRevision.value == contextRevision &&
        initialized &&
        kCurrentPage != Tabs.lock &&
        identical(zenon, client) &&
        identical(kWalletFile, walletFile) &&
        identical(client.stats, statsSource) &&
        identical(statsSource.client, statsTransport) &&
        (statsTransport is! WsClient || statsTransport.url == statsUrl) &&
        kCurrentNode == node &&
        kNodeChainId == nodeChainId &&
        getChainIdentifier() == chainId &&
        kWalletPath == walletPath &&
        kSelectedAddress == selectedAddress &&
        kWalletInitCompleted == initialized &&
        const ListEquality<String?>().equals(addresses, kDefaultAddressList);
    if (!current) _revoked = true;
    return current;
  }

  void claimPowWork() {
    _powActive = true;
    _powWork = powStatus?.claimWork();
  }

  bool get canDisplayPow {
    final PowWorkToken? work = _powWork;
    return _powActive &&
        isCurrent &&
        (powStatus == null || work != null && powStatus!.ownsWork(work));
  }

  bool updatePowStatus(PowStatus status) {
    if (!_powActive) return false;
    if (!isCurrent) {
      releasePowWork();
      return false;
    }
    final PowWorkToken? work = _powWork;
    return powStatus == null || work != null && powStatus!.update(work, status);
  }

  void releasePowWork() {
    final PowWorkToken? work = _powWork;
    _powActive = false;
    _powWork = null;
    if (work != null) powStatus?.release(work);
  }

  void requireCurrent() {
    if (!isCurrent) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
  }
}
