import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// An exact original resource receipt; observing a departure is terminal.
class AddressesSettingsResources {
  /// Freezes identity and scalar snapshots without performing I/O.
  AddressesSettingsResources({
    required List<Object?> Function() identities,
    required List<Object?> Function() values,
    required this._ready,
  }) : _identities = List<Object?>.unmodifiable(identities()),
       _values = List<Object?>.unmodifiable(values()),
       _readIdentities = identities,
       _readValues = values;

  final List<Object?> _identities;
  final List<Object?> _values;
  final List<Object?> Function() _readIdentities;
  final List<Object?> Function() _readValues;
  final bool Function() _ready;
  bool _revoked = false;

  /// A changed generation or resource permanently revokes this receipt.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final List<Object?> identities = _readIdentities();
      final bool lost =
          !_ready() ||
          identities.length != _identities.length ||
          Iterable<int>.generate(identities.length).any(
            (int index) => !identical(identities[index], _identities[index]),
          ) ||
          !listEquals(_values, _readValues());
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }
}

/// Missing or malformed balance facts never manufacture a zero.
AddressesAccount addressesAccountFromSdk(AccountInfo value, String requested) {
  final List<BalanceInfoListItem>? balances = value.balanceInfoList;
  final int? height = value.blockCount;
  if (value.address != requested ||
      height == null ||
      height < 0 ||
      balances == null) {
    throw const FormatException('Incomplete account response');
  }
  BigInt znn = BigInt.zero;
  BigInt qsr = BigInt.zero;
  final Set<String> standards = <String>{};
  for (final BalanceInfoListItem item in balances) {
    final Token? token = item.token;
    final BigInt? amount = item.balance;
    if (token == null ||
        amount == null ||
        amount.isNegative ||
        !standards.add(token.tokenStandard.toString())) {
      throw const FormatException('Incomplete account balance');
    }
    if (token.tokenStandard == znnZts || token.tokenStandard == qsrZts) {
      if (token.decimals != coinDecimals) {
        throw const FormatException('Native token decimals do not match');
      }
      if (token.tokenStandard == znnZts) znn = amount;
      if (token.tokenStandard == qsrZts) qsr = amount;
    }
  }
  return AddressesAccount(
    address: requested,
    height: height,
    znn: znn,
    qsr: qsr,
  );
}

AddressesChainBlock _block(AccountBlock value) => AddressesChainBlock(
  address: value.address.toString(),
  chain: value.chainIdentifier,
  height: value.height,
  hash: value.hash.toString(),
  previousHash: value.previousHash.toString(),
  type: value.blockType,
);

/// Captures already-open Boxes and independently bound APIs without I/O.
AddressesSettingsBinding? captureAddressesSettingsBinding({
  required void Function(String address, bool Function() current)
  applySelection,
  bool Function()? senderIsCurrent,
}) {
  final Object? file = kWalletFile;
  final String? path = kWalletPath;
  final String? selected = kSelectedAddress;
  final List<String?> members = List<String?>.of(kDefaultAddressList);
  final Zenon? client = app.zenon;
  final Object? preferences = app.sharedPrefsService;
  final int chain = getChainIdentifier();
  final int? nodeChain = kNodeChainId;
  if (file == null ||
      path == null ||
      selected == null ||
      client == null ||
      preferences == null ||
      !kWalletInitCompleted ||
      kCurrentPage == Tabs.lock ||
      NodeTransitions.pending ||
      chain <= 0 ||
      nodeChain != chain ||
      members.isEmpty ||
      !members.contains(selected) ||
      members.toSet().length != members.length ||
      members.any(
        (String? value) =>
            value == null || ContactsStore.normalize(value) != value,
      ) ||
      !Hive.isBoxOpen(kAddressesBox) ||
      !Hive.isBoxOpen(kAddressLabelsBox) ||
      !Hive.isBoxOpen(kSharedPrefsBox)) {
    return null;
  }
  final Box<dynamic> addressBox = Hive.box<dynamic>(kAddressesBox);
  final Box<dynamic> labelsBox = Hive.box<dynamic>(kAddressLabelsBox);
  final Box<dynamic> preferencesBox = Hive.box<dynamic>(kSharedPrefsBox);
  final ContactsStore contacts = ContactsStore.instance;
  final Object contactsIdentity = contacts.storageIdentity;
  final LedgerApi ledgerSource = client.ledger;
  final Client transport = ledgerSource.client;
  final WsClient socket = client.wsClient;
  final LedgerApi ledger = LedgerApi()..setClient(transport);
  final AutoReceiveTxWorker? worker = app.sl.isRegistered<AutoReceiveTxWorker>()
      ? app.sl<AutoReceiveTxWorker>()
      : null;
  final ReceiveOrigin? originalSender = worker?.captureOrigin();
  final AddressesSettingsResources resources = AddressesSettingsResources(
    identities: () => <Object?>[
      kWalletFile,
      app.zenon,
      app.sharedPrefsService,
      if (Hive.isBoxOpen(kAddressesBox))
        Hive.box<dynamic>(kAddressesBox)
      else
        null,
      if (Hive.isBoxOpen(kAddressLabelsBox))
        Hive.box<dynamic>(kAddressLabelsBox)
      else
        null,
      if (Hive.isBoxOpen(kSharedPrefsBox))
        Hive.box<dynamic>(kSharedPrefsBox)
      else
        null,
      ContactsStore.instance,
      contacts.storageIdentity,
      client.wsClient,
      client.ledger,
      ledgerSource.client,
      ledger.client,
      if (app.sl.isRegistered<AutoReceiveTxWorker>())
        app.sl<AutoReceiveTxWorker>()
      else
        null,
    ],
    values: () => <Object?>[
      WalletContextRevision.value,
      kWalletPath,
      kSelectedAddress,
      ...kDefaultAddressList,
      kCurrentNode,
      kNodeChainId,
      getChainIdentifier(),
      socket.url,
      if (transport is WsClient) transport.url else null,
    ],
    ready: () =>
        kWalletInitCompleted &&
        kCurrentPage != Tabs.lock &&
        !NodeTransitions.pending &&
        addressBox.isOpen &&
        labelsBox.isOpen &&
        preferencesBox.isOpen &&
        identical(contacts.storageIdentity, contactsIdentity) &&
        listEquals(members, addressBox.values.toList()) &&
        identical(client.wsClient, socket) &&
        identical(client.ledger, ledgerSource) &&
        identical(ledgerSource.client, transport) &&
        identical(ledger.client, transport) &&
        (senderIsCurrent?.call() ?? true),
  );
  if (!resources.isCurrent) return null;
  final Map<String, String> initialLabels = <String, String>{};
  for (int index = 0; index < members.length; index++) {
    final String member = members[index]!;
    final Object? saved = labelsBox.get(member);
    if (saved != null && saved is! String) return null;
    initialLabels[member] = saved is String
        ? saved
        : currentL10n.addressDefaultLabel(index + 1);
  }
  final Map<String, String> committedLabels = Map<String, String>.of(
    initialLabels,
  );
  return AddressesSettingsBinding(
    identity: labelsBox,
    members: members.cast<String>(),
    selected: selected,
    chainId: chain,
    contacts: contacts,
    requiresPersistentContacts: true,
    canSend: () =>
        resources.isCurrent &&
        originalSender != null &&
        originalSender.isCurrent &&
        identical(
          worker,
          app.sl.isRegistered<AutoReceiveTxWorker>()
              ? app.sl<AutoReceiveTxWorker>()
              : null,
        ),
    labels: () {
      // Hive paints an admitted value before its Future confirms durability.
      // This private committed map is deliberately independent of that cache.
      return committedLabels;
    },
    ownsResources: () => resources.isCurrent,
    readAccount: (String address) async {
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      final AccountInfo value = await ledger.getAccountInfoByAddress(
        Address.parse(address),
      );
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      return addressesAccountFromSdk(value, address);
    },
    readFrontier: (String address) async {
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      final AccountBlock? value = await ledger.getFrontierAccountBlock(
        Address.parse(address),
      );
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      return value == null ? null : _block(value);
    },
    readBlocks: (String address, int height, int count) async {
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      final AccountBlockList value = await ledger.getAccountBlocksByHeight(
        Address.parse(address),
        height,
        count,
      );
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      return value.list?.map(_block).toList();
    },
    writeLabel: (String address, String label) {
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      return labelsBox.put(address, label);
    },
    publishLabel: (String address, String label) {
      if (!resources.isCurrent || labelsBox.get(address) != label) return;
      committedLabels[address] = label;
      kAddressLabelMap = <String, String>{...kAddressLabelMap, address: label};
    },
    writeSelection: (String address) {
      if (!resources.isCurrent) throw const AddressesSettingsRefused();
      return preferencesBox.put(kDefaultAddressKey, address);
    },
    applySelection: (String address, bool Function() current) {
      if (current() &&
          resources.isCurrent &&
          preferencesBox.get(kDefaultAddressKey) == address) {
        applySelection(address, current);
      }
    },
    generation: (bool Function() current) =>
        ZenonAddressUtils.captureGeneration(isCurrent: current),
  );
}
