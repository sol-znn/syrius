import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/notification_type.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_ledger_dart/znn_ledger_dart.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// An address operation refused before its next original side effect.
class AddressGenerationRefused implements Exception {
  /// No wallet, address or backend detail is put into the refusal.
  const AddressGenerationRefused();
}

/// Original derivation and persistence outcomes survive the requesting view.
class AddressGenerationOutcome {
  /// Freezes the completed attempt and all original operation references.
  AddressGenerationOutcome({
    required this.committed,
    required this.published,
    required Iterable<String> addresses,
    required Iterable<Future<void>> labelWrites,
    required Iterable<Future<int>> memberWrites,
    this.acquisition,
    this.release,
    this.error,
    this.stackTrace,
    this.releaseError,
  }) : addresses = List<String>.unmodifiable(addresses),
       labelWrites = List<Future<void>>.unmodifiable(labelWrites),
       memberWrites = List<Future<int>>.unmodifiable(memberWrites);

  /// Every requested member was positively persisted.
  final bool committed;

  /// Every persisted extension was applied to its original live context.
  final bool published;

  /// Only positively persisted new members, including a partial attempt.
  final List<String> addresses;

  /// Identical original label Futures in admission order.
  final List<Future<void>> labelWrites;

  /// Identical original membership Futures, including a failed attempt.
  final List<Future<int>> memberWrites;

  /// The original file acquisition, when admitted.
  final Future<Object>? acquisition;

  /// The original acquired file's release.
  final Future<void>? release;

  /// The unchanged derivation, persistence or ownership error.
  final Object? error;

  /// The original failure trace.
  final StackTrace? stackTrace;

  /// Release failure cannot erase a positive membership commit.
  final Object? releaseError;
}

class _GenerationJournal {
  Future<AddressGenerationOutcome>? pending;
  int? count;
  final List<AddressGenerationOutcome> outcomes = <AddressGenerationOutcome>[];
}

/// One captured backend; injection never opens a wallet or a storage box.
class AddressGenerationBinding {
  /// Injects one complete original boundary for production or finite fixtures.
  AddressGenerationBinding({
    required Object identity,
    required Iterable<String> members,
    required this._owns,
    required this._acquire,
    required this._release,
    required this._derive,
    required this._defaultLabel,
    required this._writeLabel,
    required this._writeMember,
    required this._publish,
  }) : _members = List<String>.of(members),
       _journal = _journals[identity] ??= _GenerationJournal();

  static final Expando<_GenerationJournal> _journals =
      Expando<_GenerationJournal>();
  final List<String> _members;
  final bool Function() _owns;
  final Future<Object> Function() _acquire;
  final Future<void> Function() _release;
  final Future<String> Function(Object, int) _derive;
  final String Function(int) _defaultLabel;
  final Future<void> Function(String, String) _writeLabel;
  final Future<int> Function(String) _writeMember;
  final bool Function(String, String) _publish;
  final _GenerationJournal _journal;
  bool _revoked = false;

  /// Once revoked, a returned resource cannot resume this derivation.
  bool get owns => !_revoked && !(_revoked = !_owns());

  /// The original pending attempt is shared across remounted views.
  Future<AddressGenerationOutcome>? get pending => _journal.pending;

  /// Retained terminal attempts, independent of any widget.
  List<AddressGenerationOutcome> get outcomes =>
      List<AddressGenerationOutcome>.unmodifiable(_journal.outcomes);

  /// Repeated activation observes the original without deriving twice.
  Future<AddressGenerationOutcome> generate({int count = 1}) {
    final Future<AddressGenerationOutcome>? pending = _journal.pending;
    if (pending != null && _journal.count == count) return pending;
    final Completer<AddressGenerationOutcome> completion =
        Completer<AddressGenerationOutcome>();
    if (pending != null || count < 1 || count > 10 || !owns) {
      final AddressGenerationOutcome refused = AddressGenerationOutcome(
        committed: false,
        published: false,
        addresses: const <String>[],
        labelWrites: const <Future<void>>[],
        memberWrites: const <Future<int>>[],
        error: const AddressGenerationRefused(),
      );
      _journal.outcomes.add(refused);
      completion.complete(refused);
      return completion.future;
    }
    _journal.pending = completion.future;
    _journal.count = count;
    unawaited(
      _run(count).then<void>((AddressGenerationOutcome outcome) {
        _journal.outcomes.add(outcome);
        _journal.pending = null;
        _journal.count = null;
        completion.complete(outcome);
      }),
    );
    return completion.future;
  }

  Future<AddressGenerationOutcome> _run(int count) async {
    Future<Object>? acquisition;
    Future<void>? release;
    final List<Future<void>> labels = <Future<void>>[];
    final List<Future<int>> members = <Future<int>>[];
    final List<String> committed = <String>[];
    Object? error;
    StackTrace? trace;
    Object? releaseError;
    bool acquired = false;
    bool published = true;
    try {
      if (!owns) throw const AddressGenerationRefused();
      acquisition = _acquire();
      final Object wallet = await acquisition;
      acquired = true;
      for (int index = 0; index < count; index++) {
        if (!owns) throw const AddressGenerationRefused();
        final String address = await _derive(wallet, _members.length);
        if (!owns) throw const AddressGenerationRefused();
        if (ContactsStore.normalize(address) != address ||
            _members.contains(address)) {
          throw const FormatException('Derived address is not a new member');
        }
        final String label = _defaultLabel(_members.length + 1);
        final Future<void> labelWrite = _writeLabel(address, label);
        labels.add(labelWrite);
        await labelWrite;
        if (!owns) throw const AddressGenerationRefused();
        final Future<int> memberWrite = _writeMember(address);
        members.add(memberWrite);
        await memberWrite;
        committed.add(address);
        // This is the one allowed membership transition. Calling owns first
        // would revoke the receipt on its own newly persisted extension.
        published = false;
        final bool applied = _publish(address, label);
        published = applied;
        _members.add(address);
        if (!applied) throw const AddressGenerationRefused();
      }
    } on Object catch (failure, stack) {
      error = failure;
      trace = stack;
    } finally {
      if (acquired) {
        try {
          release = _release();
          await release;
        } on Object catch (failure) {
          releaseError = failure;
        }
      }
    }
    return AddressGenerationOutcome(
      committed: committed.length == count,
      published: committed.length == count && published,
      addresses: committed,
      labelWrites: labels,
      memberWrites: members,
      acquisition: acquisition,
      release: release,
      error: error,
      stackTrace: trace,
      releaseError: releaseError,
    );
  }
}

/// Existing address initialization and the captured owned derivation boundary.
class ZenonAddressUtils {
  /// Refreshes the legacy balance consumers after an explicit request.
  void refreshBalance() {
    unawaited(sl.get<BalanceBloc>().getBalanceForAllAddresses());
    sl.get<MultipleBalanceBloc>().add(
      MultipleBalanceFetch(
        addresses: kDefaultAddressList.map((String? e) => e!).toList(),
      ),
    );
  }

  /// The saved label, or the unchanged canonical identifier when unnamed.
  static String getLabel(String address) =>
      kAddressLabelMap[address] ?? address;

  /// Source-compatible entry point; original failures remain observable.
  static Future<void> generateNewAddress({
    int numAddr = 1,
    VoidCallback? callback,
    bool Function()? isCurrent,
  }) async {
    final AddressGenerationBinding? binding = captureGeneration(
      isCurrent: isCurrent,
    );
    if (binding == null) throw const AddressGenerationRefused();
    final AddressGenerationOutcome result = await binding.generate(
      count: numAddr,
    );
    if (result.error != null) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.empty,
      );
    }
    if (result.releaseError != null) {
      Error.throwWithStackTrace(result.releaseError!, StackTrace.current);
    }
    if (result.published && binding.owns && (isCurrent?.call() ?? true)) {
      callback?.call();
    }
  }

  /// Freezes the original file, member prefix and boxes before acquisition.
  static AddressGenerationBinding? captureGeneration({
    bool Function()? isCurrent,
  }) {
    final WalletFile? file = kWalletFile;
    final String? path = kWalletPath;
    final String? selected = kSelectedAddress;
    final Zenon? client = zenon;
    final String? node = kCurrentNode;
    final int? nodeChain = kNodeChainId;
    final int chain = getChainIdentifier();
    int revision = WalletContextRevision.value;
    List<String?> expected = List<String?>.of(kDefaultAddressList);
    if (file == null ||
        client == null ||
        selected == null ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        NodeTransitions.pending ||
        (isCurrent?.call() == false) ||
        !expected.contains(selected) ||
        expected.any(
          (String? value) =>
              value == null || ContactsStore.normalize(value) != value,
        ) ||
        expected.toSet().length != expected.length ||
        !Hive.isBoxOpen(kAddressesBox) ||
        !Hive.isBoxOpen(kAddressLabelsBox)) {
      return null;
    }
    final Box<dynamic> addresses = Hive.box<dynamic>(kAddressesBox);
    final Box<dynamic> labels = Hive.box<dynamic>(kAddressLabelsBox);
    for (final Object? key in labels.keys) {
      if (key is! String || labels.get(key) is! String) return null;
    }
    final LedgerApi ledgerSource = client.ledger;
    final Client ledgerTransport = ledgerSource.client;
    final String? ledgerUrl = ledgerTransport is WsClient
        ? ledgerTransport.url
        : null;
    final WsClient socket = client.wsClient;
    final String? socketUrl = socket.url;
    final NotificationsBloc? notifications =
        sl.isRegistered<NotificationsBloc>() ? sl<NotificationsBloc>() : null;
    final Box<dynamic>? notificationBox = Hive.isBoxOpen(kNotificationsBox)
        ? Hive.box<dynamic>(kNotificationsBox)
        : null;
    final AppLocalizations messages = currentL10n;
    final String originalFilePath = file.walletPath;
    bool revoked = false;
    bool baseCurrent() =>
        !revoked &&
        !(revoked =
            (isCurrent?.call() == false) ||
            revision != WalletContextRevision.value ||
            !identical(file, kWalletFile) ||
            path != kWalletPath ||
            originalFilePath != file.walletPath ||
            !identical(client, zenon) ||
            node != kCurrentNode ||
            !identical(client.ledger, ledgerSource) ||
            !identical(ledgerSource.client, ledgerTransport) ||
            !identical(client.wsClient, socket) ||
            socket.url != socketUrl ||
            (ledgerTransport is WsClient && ledgerTransport.url != ledgerUrl) ||
            (notifications != null &&
                (!sl.isRegistered<NotificationsBloc>() ||
                    !identical(notifications, sl<NotificationsBloc>()))) ||
            (notificationBox != null &&
                (!notificationBox.isOpen ||
                    !Hive.isBoxOpen(kNotificationsBox) ||
                    !identical(
                      notificationBox,
                      Hive.box<dynamic>(kNotificationsBox),
                    ))) ||
            nodeChain != kNodeChainId ||
            chain != getChainIdentifier() ||
            selected != kSelectedAddress ||
            !kWalletInitCompleted ||
            kCurrentPage == Tabs.lock ||
            NodeTransitions.pending ||
            !addresses.isOpen ||
            !labels.isOpen ||
            !Hive.isBoxOpen(kAddressesBox) ||
            !identical(addresses, Hive.box<dynamic>(kAddressesBox)) ||
            !Hive.isBoxOpen(kAddressLabelsBox) ||
            !identical(labels, Hive.box<dynamic>(kAddressLabelsBox)));
    bool owns() =>
        baseCurrent() &&
        listEquals(expected, kDefaultAddressList) &&
        listEquals(expected, addresses.values.toList());
    if (!owns()) return null;
    return AddressGenerationBinding(
      identity: addresses,
      members: expected.cast<String>(),
      owns: owns,
      acquire: file.open,
      release: file.close,
      derive: (Object wallet, int index) async {
        if (!owns()) throw const AddressGenerationRefused();
        final WalletAccount account = await (wallet as Wallet).getAccount(
          index,
        );
        if (!owns()) throw const AddressGenerationRefused();
        if (account is LedgerWalletAccount) {
          if (notifications != null &&
              notificationBox != null &&
              notifications.ownsOriginalStore(notificationBox)) {
            await notifications.writeNotification(
              WalletNotification(
                title: messages.addressAddConfirmNotificationTitle,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                details: messages.addressAddConfirmNotificationDetails(index),
                type: NotificationType.confirm,
              ),
              originalStore: notificationBox,
              shouldDisplay: owns,
            );
          }
          if (!owns()) throw const AddressGenerationRefused();
          return (await account.getAddress(true)).toString();
        }
        return (await account.getAddress()).toString();
      },
      defaultLabel: messages.addressDefaultLabel,
      writeLabel: (String address, String label) {
        if (!owns()) throw const AddressGenerationRefused();
        if (labels.containsKey(address)) {
          throw const FormatException('Derived address already has a label');
        }
        return labels.put(address, label);
      },
      writeMember: (String address) {
        if (!owns()) throw const AddressGenerationRefused();
        return addresses.add(address);
      },
      publish: (String address, String label) {
        final List<String?> extension = <String?>[...expected, address];
        if (!baseCurrent() ||
            !listEquals(expected, kDefaultAddressList) ||
            !listEquals(extension, addresses.values.toList()) ||
            labels.get(address) != label) {
          return false;
        }
        final Map<String, String> committedLabels = <String, String>{};
        for (final Object? key in labels.keys) {
          final Object? value = labels.get(key);
          if (key is! String || value is! String) return false;
          committedLabels[key] = value;
        }
        expected = extension;
        kDefaultAddressList = List<String?>.of(extension);
        kAddressLabelMap = committedLabels;
        // The existing root revokes immediately and rearms in a microtask,
        // after the exact committed member extension has become visible.
        revision++;
        WalletContextRevision.invalidate();
        return baseCurrent() && listEquals(expected, kDefaultAddressList);
      },
    );
  }

  /// Initializes the existing label store during wallet initialization.
  static Future<void> setAddressLabels() async {
    final Box<dynamic> addressLabelsBox = await Hive.openBox<dynamic>(
      kAddressLabelsBox,
    );

    if (addressLabelsBox.isEmpty) {
      for (final String? address in kDefaultAddressList) {
        await addressLabelsBox.put(
          address,
          currentL10n.addressDefaultLabel(
            kDefaultAddressList.indexOf(address) + 1,
          ),
        );
      }
    }
    _initAddressLabels(addressLabelsBox);
  }

  /// Restores the existing persisted account selection during initialization.
  static Future<void> setDefaultAddress() async {
    if (sharedPrefsService!.get(kDefaultAddressKey) == null) {
      await sharedPrefsService!.put(
        kDefaultAddressKey,
        kDefaultAddressList[0],
      );
    }
    kSelectedAddress = sharedPrefsService!.get(kDefaultAddressKey);
  }

  /// Initializes membership from the original wallet during startup.
  static Future<void> setAddresses(WalletFile? walletFile) async {
    final Box<dynamic> addressesBox = await Hive.openBox<dynamic>(
      kAddressesBox,
    );
    if (addressesBox.isEmpty) {
      await walletFile!.access((Wallet wallet) async {
        for (final String element in await Future.wait(
          List<Future<String>>.generate(
            kNumOfInitialAddresses,
            (int index) async => (await (await wallet.getAccount(
              index,
            )).getAddress()).toString(),
          ),
        )) {
          await addressesBox.add(element);
        }
      });
    }
    _initAddresses(addressesBox);
  }

  static void _initAddresses(Box<dynamic> addressesBox) =>
      kDefaultAddressList = List<String?>.from(addressesBox.values);

  static void _initAddressLabels(Box<dynamic> box) =>
      kAddressLabelMap = box.keys.toList().fold<Map<String, String>>(
        <String, String>{},
        (Map<String, String> previousValue, dynamic key) {
          previousValue[key] = box.get(key);
          return previousValue;
        },
      );
}
