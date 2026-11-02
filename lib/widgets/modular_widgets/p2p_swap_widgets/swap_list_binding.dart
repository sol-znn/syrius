import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Identity and value departures permanently revoke an original receipt.
class SwapListResources {
  /// Snapshots exact resource identities and values before asynchronous work.
  SwapListResources({
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

  /// Refuses permanently after an observed identity, value or readiness change.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final List<Object?> current = _readIdentities();
      final bool lost =
          !_ready() ||
          current.length != _identities.length ||
          Iterable<int>.generate(current.length).any(
            (int index) => !identical(current[index], _identities[index]),
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

String _string(Map<String, dynamic> value, String key) {
  final Object? result = value[key];
  if (result is! String || result.isEmpty) throw const SwapListRefused();
  return result;
}

int _integer(Map<String, dynamic> value, String key) {
  final Object? result = value[key];
  if (result is! int || result < 0) throw const SwapListRefused();
  return result;
}

String _hash(String value) {
  if (Hash.parse(value) == emptyHash || Hash.parse(value).toString() != value) {
    throw const SwapListRefused();
  }
  return value;
}

String _address(String value) {
  if (Address.parse(value).toString() != value) throw const SwapListRefused();
  return value;
}

/// Projects only public fields; the hydrated legacy model is never a view DTO.
SwapListRecord swapListRecordFromJson(Map<String, dynamic> value) {
  if (value['mode'] != P2pSwapMode.htlc.name ||
      value['type'] != P2pSwapType.native.name ||
      value['fromChain'] != P2pSwapChain.nom.name ||
      value['toChain'] != P2pSwapChain.nom.name) {
    throw const SwapListRefused();
  }
  final String standard = _string(value, 'fromTokenStandard');
  if (TokenStandard.parse(standard).toString() != standard) {
    throw const SwapListRefused();
  }
  final BigInt amount = BigInt.parse(_string(value, 'fromAmount'));
  final int decimals = _integer(value, 'fromDecimals');
  final int initialExpiration = _integer(value, 'initialHtlcExpirationTime');
  final int started = _integer(value, 'startTime');
  final int hashType = _integer(value, 'hashType');
  final String? counterId = value['counterHtlcId'] == null
      ? null
      : _hash(_string(value, 'counterHtlcId'));
  final int? counterExpiration = value['counterHtlcExpirationTime'] == null
      ? null
      : _integer(value, 'counterHtlcExpirationTime');
  if (amount <= BigInt.zero ||
      decimals > 255 ||
      initialExpiration <= started ||
      (counterId == null) != (counterExpiration == null) ||
      (counterExpiration != null && counterExpiration <= started) ||
      (hashType != htlcHashTypeSha3 && hashType != htlcHashTypeSha256)) {
    throw const SwapListRefused();
  }
  return SwapListRecord(
    id: _hash(_string(value, 'id')),
    chainId: _integer(value, 'chainId'),
    direction: P2pSwapDirection.values.byName(_string(value, 'direction')),
    selfAddress: _address(_string(value, 'selfAddress')),
    counterpartyAddress: _address(_string(value, 'counterpartyAddress')),
    fromAmount: amount,
    fromStandard: standard,
    fromSymbol: _string(value, 'fromSymbol'),
    fromDecimals: decimals,
    started: started,
    state: P2pSwapState.values.byName(_string(value, 'state')),
    initialDepositId: _hash(_string(value, 'initialHtlcId')),
    initialExpiration: initialExpiration,
    counterpartyDepositId: counterId,
    counterpartyExpiration: counterExpiration,
    hashLock: _hash(_string(value, 'hashLock')),
    hashType: hashType,
  );
}

int _contractInteger(Object? value) {
  if (value is int && value >= 0) return value;
  if (value is BigInt &&
      value >= BigInt.zero &&
      value <= BigInt.from(0x1fffffffffffff)) {
    return value.toInt();
  }
  throw const SwapListRefused();
}

SwapDepositProof? _deposit(AccountBlock? block, String id, int chain) {
  if (block == null) return null;
  final AccountBlockConfirmationDetail? confirmation = block.confirmationDetail;
  final Token? token = block.token;
  final BlockData? data = AccountBlockUtils.getDecodedBlockData(
    Definitions.htlc,
    block.data,
  );
  if (block.hash.toString() != id ||
      block.chainIdentifier != chain ||
      block.toAddress != htlcAddress ||
      block.blockType != BlockTypeEnum.userSend.index ||
      confirmation == null ||
      confirmation.momentumTimestamp <= 0 ||
      token == null ||
      token.tokenStandard != block.tokenStandard ||
      data == null ||
      data.function != 'Create' ||
      data.params['hashLock'] is! List<int> ||
      data.params['hashLocked'] is! Address) {
    throw const SwapListRefused();
  }
  return SwapDepositProof(
    id: id,
    chainId: chain,
    sender: block.address.toString(),
    recipient: data.params['hashLocked'].toString(),
    amount: block.amount,
    standard: token.tokenStandard.toString(),
    symbol: token.symbol,
    decimals: token.decimals,
    expiration: _contractInteger(data.params['expirationTime']),
    hashLock: FormatUtils.encodeHexString(data.params['hashLock'] as List<int>),
    hashType: _contractInteger(data.params['hashType']),
    confirmedAt: confirmation.momentumTimestamp,
  );
}

/// Independent wrappers keep an admitted read on its exact original transport.
class SwapListApiCapture {
  /// Binds independent ledger and HTLC wrappers to their original transports.
  SwapListApiCapture({
    required LedgerApi ledgerSource,
    required HtlcApi htlcSource,
    required this.chainId,
    required bool Function() isCurrent,
  }) {
    final Client ledgerTransport = ledgerSource.client;
    final Client htlcTransport = htlcSource.client;
    _ledger = LedgerApi()..setClient(ledgerTransport);
    _htlc = HtlcApi()..setClient(htlcTransport);
    _resources = SwapListResources(
      identities: () => <Object?>[
        ledgerSource.client,
        htlcSource.client,
        _ledger.client,
        _htlc.client,
      ],
      values: () => <Object?>[
        if (ledgerTransport is WsClient) ledgerTransport.url else null,
        if (htlcTransport is WsClient) htlcTransport.url else null,
      ],
      ready: isCurrent,
    );
  }

  /// Positive chain expected from every original ledger response.
  final int chainId;
  late final LedgerApi _ledger;
  late final HtlcApi _htlc;
  late final SwapListResources _resources;

  /// Monotonic ownership check for the original wrappers and transports.
  bool get isCurrent => _resources.isCurrent;

  void _requireCurrent() {
    if (!isCurrent) throw const SwapListRefused();
  }

  /// Reads a positive original-chain frontier timestamp with no fallback.
  Future<int> readChainTime() async {
    _requireCurrent();
    final Momentum value = await _ledger.getFrontierMomentum();
    if (value.chainIdentifier != chainId || value.timestamp <= 0) {
      throw const SwapListRefused();
    }
    return value.timestamp;
  }

  /// Reads and validates the exact confirmed Create hash for one deposit.
  Future<SwapDepositProof?> readDeposit(String id) async {
    _requireCurrent();
    return _deposit(
      await _ledger.getAccountBlockByHash(Hash.parse(id)),
      id,
      chainId,
    );
  }

  /// Copies current deposit facts from the original HTLC API; failures remain
  /// unavailable facts rather than inferred spent or expired status.
  Future<SwapLiveDeposit?> readLiveDeposit(String id) async {
    _requireCurrent();
    final HtlcInfo value = await _htlc.getById(Hash.parse(id));
    return SwapLiveDeposit(
      id: value.id.toString(),
      expiration: value.expirationTime,
      sender: value.timeLocked.toString(),
      recipient: value.hashLocked.toString(),
      amount: value.amount,
      standard: value.tokenStandard.toString(),
      hashLock: FormatUtils.encodeHexString(value.hashLock),
      hashType: value.hashType,
    );
  }
}

/// Captures actual store, wallet generation and API resources before I/O.
SwapListBinding? captureSwapListBinding() {
  try {
    final Object? file = kWalletFile;
    final String? path = kWalletPath;
    final String? selected = kSelectedAddress;
    final List<String?> members = List<String?>.of(kDefaultAddressList);
    final int chain = getChainIdentifier();
    final HtlcSwapsService? store = app.htlcSwapsService;
    final Box<dynamic>? box = store?.captureSwapsBox();
    final HtlcStoreCapture? originalStore = store?.captureStore(chainId: chain);
    final Zenon? client = app.zenon;
    if (file == null ||
        path == null ||
        selected == null ||
        store == null ||
        box == null ||
        originalStore == null ||
        !identical(originalStore.identity, box) ||
        client == null ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        NodeTransitions.pending ||
        chain <= 0 ||
        kNodeChainId != chain ||
        members.isEmpty ||
        !members.contains(selected) ||
        members.any(
          (String? value) =>
              value == null || Address.parse(value).toString() != value,
        ) ||
        members.toSet().length != members.length ||
        !Hive.isBoxOpen(kAddressesBox)) {
      return null;
    }
    final Box<dynamic> addresses = Hive.box<dynamic>(kAddressesBox);
    if (!listEquals(members, addresses.values.toList())) return null;
    final LedgerApi ledgerSource = client.ledger;
    final HtlcApi htlcSource = client.embedded.htlc;
    final Client ledgerTransport = ledgerSource.client;
    final Client htlcTransport = htlcSource.client;
    final WsClient socket = client.wsClient;
    if (!identical(ledgerTransport, socket) ||
        !identical(htlcTransport, socket) ||
        socket.url == null ||
        socket.url!.isEmpty) {
      return null;
    }
    late final SwapListResources resources;
    final SwapListApiCapture apis = SwapListApiCapture(
      ledgerSource: ledgerSource,
      htlcSource: htlcSource,
      chainId: chain,
      isCurrent: () => resources.isCurrent,
    );
    resources = SwapListResources(
      identities: () => <Object?>[
        kWalletFile,
        app.zenon,
        app.htlcSwapsService,
        store.captureSwapsBox(),
        if (Hive.isBoxOpen(kAddressesBox))
          Hive.box<dynamic>(kAddressesBox)
        else
          null,
        client.wsClient,
        client.ledger,
        client.embedded.htlc,
        ledgerSource.client,
        htlcSource.client,
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
        if (ledgerTransport is WsClient) ledgerTransport.url else null,
        if (htlcTransport is WsClient) htlcTransport.url else null,
      ],
      ready: () =>
          kWalletInitCompleted &&
          kCurrentPage != Tabs.lock &&
          !NodeTransitions.pending &&
          originalStore.isCurrent &&
          store.ownsSwapsBox(box) &&
          addresses.isOpen &&
          listEquals(members, addresses.values.toList()) &&
          identical(app.htlcSwapsService, store),
    );
    if (!resources.isCurrent) return null;
    final Map<dynamic, dynamic> original = Map<dynamic, dynamic>.of(
      box.toMap(),
    );
    final Map<String, Object?> rawRecords = <String, Object?>{};
    final List<SwapListRecord> records = <SwapListRecord>[];
    for (final MapEntry<dynamic, dynamic> entry in original.entries) {
      if (entry.key is! String || entry.value is! String) return null;
      if (!originalStore.isHistoryEntry(entry.key as String, entry.value)) {
        continue;
      }
      final Object? decoded = jsonDecode(entry.value as String);
      if (decoded is! Map<String, dynamic>) return null;
      final SwapListRecord record = swapListRecordFromJson(decoded);
      if (record.id != entry.key) return null;
      if (record.chainId != chain) continue;
      if (!members.contains(record.selfAddress) ||
          rawRecords.containsKey(record.id)) {
        return null;
      }
      records.add(record);
      rawRecords[record.id] = entry.value;
    }
    bool catalogueRevoked = false;
    bool catalogueCurrent() {
      if (catalogueRevoked || !resources.isCurrent) return false;
      catalogueRevoked =
          box.length != original.length ||
          original.entries.any(
            (MapEntry<dynamic, dynamic> entry) =>
                !box.containsKey(entry.key) ||
                box.get(entry.key) != entry.value,
          );
      return !catalogueRevoked;
    }

    final Set<String> revokedRows = <String>{};
    bool rowCurrent(SwapListRecord row) {
      if (revokedRows.contains(row.id) || !resources.isCurrent) return false;
      if (!rawRecords.containsKey(row.id) ||
          !box.containsKey(row.id) ||
          box.get(row.id) != rawRecords[row.id]) {
        revokedRows.add(row.id);
        return false;
      }
      return true;
    }

    if (!catalogueCurrent()) return null;
    return SwapListBinding(
      identity: box,
      chainId: chain,
      selected: selected,
      members: members.cast<String>(),
      ownsResources: () => resources.isCurrent,
      catalogueIsCurrent: catalogueCurrent,
      rowIsCurrent: rowCurrent,
      readPage: (int page, int size) async {
        if (!catalogueCurrent() || page < 0 || size <= 0) {
          throw const SwapListRefused();
        }
        final int start = page * size;
        if (start > records.length) throw const SwapListRefused();
        final int end = (start + size).clamp(0, records.length);
        return SwapListPage(
          total: records.length,
          more: end < records.length,
          records: records.sublist(start, end),
        );
      },
      readChainTime: apis.readChainTime,
      readDeposit: apis.readDeposit,
      readLiveDeposit: apis.readLiveDeposit,
      deleteRecords: (List<String> ids) {
        if (!catalogueCurrent() ||
            ids.isEmpty ||
            ids.any(
              (String id) =>
                  !rawRecords.containsKey(id) ||
                  box.get(id) != rawRecords[id] ||
                  !records.any(
                    (SwapListRecord row) => row.id == id && row.canDelete,
                  ),
            )) {
          throw const SwapListRefused();
        }
        return originalStore.deleteIds(ids);
      },
    );
  } on Object {
    // An incomplete original catalogue cannot become an empty list.
    return null;
  }
}
