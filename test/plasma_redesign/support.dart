import 'dart:async';
import 'dart:math' as math;

import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String plasmaTestHash(int value) => value.toRadixString(16).padLeft(64, '0');

FusionEntry plasmaTestEntry(int value, {int expiry = 10, BigInt? amount}) =>
    FusionEntry(
      beneficiary: emptyAddress,
      expirationHeight: expiry,
      id: Hash.parse(plasmaTestHash(value)),
      qsrAmount: amount ?? BigInt.from(value) * BigInt.from(100000000),
    );

FusionEntryList plasmaTestPage(
  List<FusionEntry> rows, {
  BigInt? total,
  int? count,
}) => FusionEntryList.fromJson(<String, dynamic>{
  'qsrAmount':
      (total ??
              rows.fold<BigInt>(
                BigInt.zero,
                (BigInt sum, FusionEntry entry) => sum + entry.qsrAmount,
              ))
          .toString(),
  'count': count ?? rows.length,
  'list': rows.map((FusionEntry entry) => entry.toJson()).toList(),
});

/// Records only in-memory publication arguments. No account or signer exists.
class PlasmaTransportCall {
  PlasmaTransportCall(this.block, this.address, this.canPublish);
  final AccountBlockTemplate block;
  final Address? address;
  final bool Function()? canPublish;
}

class PlasmaTransport extends AccountBlockUtils {
  final List<PlasmaTransportCall> calls = <PlasmaTransportCall>[];
  final List<(PlasmaTransportCall, Completer<AccountBlockTemplate>)> pending =
      <(PlasmaTransportCall, Completer<AccountBlockTemplate>)>[];
  Completer<PlasmaTransportCall> _next = Completer<PlasmaTransportCall>();
  Completer<void>? preparation;
  final StateError preparationError = StateError(
    'Fixture preparation was revoked',
  );
  bool deferred = false;
  int published = 0;
  Future<PlasmaTransportCall> get next => _next.future;

  AccountBlockTemplate accepted(PlasmaTransportCall call) =>
      AccountBlockTemplate.fromJson(call.block.toJson())
        ..address = emptyAddress
        ..chainIdentifier = 321
        ..hash = Hash.parse(plasmaTestHash(1000 + calls.indexOf(call)));

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purpose, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) async {
    final PlasmaTransportCall call = PlasmaTransportCall(
      transactionParams,
      address,
      canPublish,
    );
    calls.add(call);
    final Completer<PlasmaTransportCall> arrival = _next;
    _next = Completer<PlasmaTransportCall>();
    arrival.complete(call);
    if (preparation != null) await preparation!.future;
    if (!(canPublish?.call() ?? true)) {
      throw preparationError;
    }
    published++;
    if (!deferred) return accepted(call);
    final Completer<AccountBlockTemplate> reply =
        Completer<AccountBlockTemplate>();
    pending.add((call, reply));
    return reply.future;
  }

  void completeNext({Object? error, AccountBlockTemplate? response}) {
    final (PlasmaTransportCall call, Completer<AccountBlockTemplate> reply) =
        pending.removeAt(0);
    if (error != null) {
      reply.completeError(error);
    } else {
      reply.complete(response ?? accepted(call));
    }
  }

  void release() {
    if (preparation case final Completer<void> gate) {
      if (!gate.isCompleted) gate.complete();
    }
    while (pending.isNotEmpty) {
      completeNext();
    }
  }
}

class _Balances extends ZenonAddressUtils {
  @override
  void refreshBalance() {}
}

/// Source-only fixtures inject every read and publication boundary.
class PlasmaFixture {
  PlasmaFixture({int pageSize = 2}) {
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: transport,
      zenonAddressUtils: _Balances(),
      recordRecipient: (_, _) async {},
    );
    owner = PlasmaOwnerController(
      sender: sender,
      address: emptyAddress.toString(),
      chainId: 321,
      pageSize: pageSize,
    );
  }

  final PlasmaTransport transport = PlasmaTransport();
  late final SendTransactionBloc sender;
  late final PlasmaOwnerController owner;
  List<FusionEntry> rows = <FusionEntry>[
    plasmaTestEntry(1),
    plasmaTestEntry(2),
    plasmaTestEntry(3),
  ];
  final List<(int, int)> pages = <(int, int)>[];
  final List<String> cancellations = <String>[];
  Future<FusionEntryList> Function(int page, int size)? fetch;
  Future<AccountInfo> Function()? accountRead;
  int revision = 0;
  int frontier = 11;
  bool visible = true;
  bool closed = false;
  bool ownerDisposed = false;

  void disposeOwner() {
    if (ownerDisposed) return;
    ownerDisposed = true;
    owner.dispose();
  }

  PlasmaSession session() {
    final int captured = revision;
    const int chainId = 321;
    return PlasmaSession(
      address: emptyAddress.toString(),
      chainId: chainId,
      isCurrent: () => captured == revision,
      readEntries: (int page, int size) {
        pages.add((page, size));
        return fetch?.call(page, size) ??
            Future<FusionEntryList>.value(
              plasmaTestPage(
                rows.sublist(
                  math.min(page * size, rows.length),
                  math.min((page + 1) * size, rows.length),
                ),
                count: rows.length,
                total: rows.fold<BigInt>(
                  BigInt.zero,
                  (BigInt sum, FusionEntry entry) => sum + entry.qsrAmount,
                ),
              ),
            );
      },
      readFrontier: () async => frontier,
      readAccount: () =>
          accountRead?.call() ??
          Future<AccountInfo>.value(
            AccountInfo(
              address: emptyAddress.toString(),
              blockCount: 1,
              balanceInfoList: <BalanceInfoListItem>[
                BalanceInfoListItem(
                  token: kQsrCoin,
                  balance: BigInt.parse('1000000000000'),
                ),
              ],
            ),
          ),
      cancelBlock: (String hash) {
        cancellations.add(hash);
        return AccountBlockTemplate.callContract(
          plasmaAddress,
          znnZts,
          BigInt.zero,
          Hash.parse(hash).getBytes()!,
        )..chainIdentifier = chainId;
      },
      fuseBlock: (String beneficiary, BigInt amount) =>
          AccountBlockTemplate.callContract(
            plasmaAddress,
            qsrZts,
            amount,
            Address.parse(beneficiary).getBytes()!,
          )..chainIdentifier = chainId,
    );
  }

  Future<void> loadAll() async {
    await owner.load(session());
    while (owner.read?.hasMore ?? false) {
      await owner.loadMore();
    }
  }

  PlasmaCancelIntent intent({String? hash}) {
    if (hash == null) {
      for (final PlasmaFusion entry in owner.read!.entries) {
        owner.select(entry, selected: true);
      }
    }
    return owner.beginCancellation(
      session: session(),
      isCurrent: () => visible,
      hash: hash,
    )!;
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    visible = false;
    transport.release();
    disposeOwner();
    await sender.close().timeout(const Duration(seconds: 2));
  }
}
