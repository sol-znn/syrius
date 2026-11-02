import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String swapAddress(int number) => Address('z', <int>[
  0,
  number ~/ 256,
  number % 256,
  ...List<int>.filled(17, 9),
]).toString();
String swapHash(int number) => number.toRadixString(16).padLeft(64, '0');

SwapListRecord swapRecord(
  int number, {
  P2pSwapState state = P2pSwapState.active,
  P2pSwapDirection direction = P2pSwapDirection.outgoing,
  bool joined = true,
  BigInt? amount,
}) => SwapListRecord(
  id: swapHash(number),
  chainId: 321,
  direction: direction,
  selfAddress: swapAddress(1),
  counterpartyAddress: swapAddress(2),
  fromAmount: amount ?? BigInt.from(10000000000),
  fromStandard: znnTokenStandard,
  fromSymbol: 'ZNN',
  fromDecimals: 8,
  started: 100 + number,
  state: state,
  initialDepositId: swapHash(number + 1000),
  initialExpiration: 100000,
  counterpartyDepositId: joined ? swapHash(number + 2000) : null,
  counterpartyExpiration: joined ? 90000 : null,
  hashLock: swapHash(number + 3000),
  hashType: htlcHashTypeSha3,
);

SwapDepositProof swapProof(
  SwapListRecord record, {
  required bool sending,
  BigInt? amount,
  int? chain,
  String? sender,
  String? recipient,
}) {
  final String id = (sending ? record.ownDepositId : record.receiveDepositId)!;
  return SwapDepositProof(
    id: id,
    chainId: chain ?? record.chainId,
    sender:
        sender ?? (sending ? record.selfAddress : record.counterpartyAddress),
    recipient:
        recipient ??
        (sending ? record.counterpartyAddress : record.selfAddress),
    amount: amount ?? (sending ? record.fromAmount : BigInt.from(100000000000)),
    standard: sending ? znnTokenStandard : qsrTokenStandard,
    symbol: sending ? 'ZNN' : 'QSR',
    decimals: 8,
    expiration: id == record.initialDepositId
        ? record.initialExpiration
        : record.counterpartyExpiration!,
    hashLock: record.hashLock,
    hashType: record.hashType,
    confirmedAt: 500,
  );
}

SwapLiveDeposit swapLive(SwapDepositProof proof) => SwapLiveDeposit(
  id: proof.id,
  expiration: proof.expiration,
  sender: proof.sender,
  recipient: proof.recipient,
  amount: proof.amount,
  standard: proof.standard,
  hashLock: proof.hashLock,
  hashType: proof.hashType,
);

/// A finite injected source with no wallet, socket, Box, native call or timer.
class SwapListFixture {
  final Object box = Object();
  Object wallet = Object();
  Object api = Object();
  Object transport = Object();
  int revision = 0;
  String path = 'fixture-wallet';
  String url = 'fixture-node';
  bool ready = true;
  bool catalogue = true;
  final Set<String> replacedRows = <String>{};
  final List<SwapListRecord> records = <SwapListRecord>[];
  final List<int> pages = <int>[];
  final List<String> deposits = <String>[];
  final List<String> liveReads = <String>[];
  final List<List<String>> deletes = <List<String>>[];
  final Map<String, SwapDepositProof> proofs = <String, SwapDepositProof>{};
  final Map<String, SwapLiveDeposit> live = <String, SwapLiveDeposit>{};
  Future<SwapListPage> Function(int, int)? pageRead;
  Future<SwapDepositProof?> Function(String)? depositRead;
  Future<SwapLiveDeposit?> Function(String)? liveRead;
  Future<dynamic> Function(List<String>)? deleteWrite;

  void add(SwapListRecord record, {bool prove = true, bool current = true}) {
    records.add(record);
    if (!prove) return;
    if (record.ownDepositId != null) {
      final SwapDepositProof own = swapProof(record, sending: true);
      proofs[own.id] = own;
      if (current) live[own.id] = swapLive(own);
    }
    if (record.receiveDepositId != null) {
      final SwapDepositProof receive = swapProof(record, sending: false);
      proofs[receive.id] = receive;
    }
  }

  SwapListBinding bind() {
    final SwapListResources resources = SwapListResources(
      identities: () => <Object?>[wallet, api, transport, box],
      values: () => <Object?>[revision, path, url],
      ready: () => ready,
    );
    final List<SwapListRecord> original = List<SwapListRecord>.of(records);
    return SwapListBinding(
      identity: box,
      chainId: 321,
      selected: swapAddress(1),
      members: <String>[swapAddress(1)],
      ownsResources: () => resources.isCurrent,
      catalogueIsCurrent: () => resources.isCurrent && catalogue,
      rowIsCurrent: (SwapListRecord row) =>
          resources.isCurrent && !replacedRows.contains(row.id),
      readPage: (int page, int size) {
        pages.add(page);
        if (pageRead != null) return pageRead!(page, size);
        final int end = ((page + 1) * size).clamp(0, original.length);
        return Future<SwapListPage>.value(
          SwapListPage(
            total: original.length,
            more: end < original.length,
            records: original.sublist(page * size, end),
          ),
        );
      },
      readChainTime: () async => 1000,
      readDeposit: (String id) {
        deposits.add(id);
        return depositRead?.call(id) ??
            Future<SwapDepositProof?>.value(proofs[id]);
      },
      readLiveDeposit: (String id) {
        liveReads.add(id);
        return liveRead?.call(id) ?? Future<SwapLiveDeposit?>.value(live[id]);
      },
      deleteRecords: (List<String> ids) {
        deletes.add(List<String>.of(ids));
        return deleteWrite?.call(ids) ?? Future<void>.value();
      },
    );
  }
}
