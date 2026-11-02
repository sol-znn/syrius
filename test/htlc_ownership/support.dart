import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_worker_origin.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const int htlcChain = 321;
String htlcHash(int value) => value.toRadixString(16).padLeft(64, '0');
String htlcOwner(int value) => Address('z', <int>[
  0,
  value ~/ 256,
  value % 256,
  ...List<int>.filled(17, 6),
]).toString();

/// Synthetic values never leave this in-memory fixture.
HtlcSwap htlcRecord(
  int number, {
  P2pSwapDirection direction = P2pSwapDirection.incoming,
  P2pSwapState state = P2pSwapState.active,
}) {
  final List<int> value = List<int>.generate(
    32,
    (int index) => (number + index) % 256,
  );
  return HtlcSwap(
    id: htlcHash(number),
    chainId: htlcChain,
    type: P2pSwapType.native,
    direction: direction,
    selfAddress: htlcOwner(1),
    counterpartyAddress: htlcOwner(2),
    fromAmount: BigInt.parse('900719925474099300000001'),
    fromTokenStandard: znnZts.toString(),
    fromSymbol: 'ZNN',
    fromDecimals: 8,
    fromChain: P2pSwapChain.nom,
    toChain: P2pSwapChain.nom,
    toAmount: BigInt.from(250),
    toTokenStandard: qsrZts.toString(),
    toSymbol: 'QSR',
    toDecimals: 8,
    startTime: 100,
    state: state,
    initialHtlcId: htlcHash(number),
    initialHtlcExpirationTime: 5000,
    counterHtlcId: htlcHash(number + 1000),
    counterHtlcExpirationTime: 4000,
    hashLock: Hash.digest(value).toString(),
    hashType: htlcHashTypeSha3,
    preimage: FormatUtils.encodeHexString(value),
  );
}

Map<String, dynamic> htlcRecovery(HtlcSwap swap) => <String, dynamic>{
  'chainId': swap.chainId,
  'selfAddress': swap.selfAddress,
  'recipient': swap.counterpartyAddress,
  'amount': swap.fromAmount.toString(),
  'tokenStandard': swap.fromTokenStandard,
  'expirationTime': swap.initialHtlcExpirationTime,
  'hashLock': swap.hashLock,
  'hashType': swap.hashType,
  'keyMaxSize': htlcPreimageMaxLength,
  'preimage': swap.preimage,
  'fromDecimals': swap.fromDecimals,
  'fromSymbol': swap.fromSymbol,
  'startTime': swap.startTime,
};

AccountBlock htlcBlock({
  AccountBlockTemplate? template,
  int height = 1,
  String? hash,
  String? previous,
  int timestamp = 200,
  Token? token,
  AccountBlock? paired,
  List<AccountBlock> descendants = const <AccountBlock>[],
}) {
  final AccountBlockTemplate base =
      template ??
      (AccountBlockTemplate(blockType: BlockTypeEnum.contractSend.index)
        ..address = htlcAddress);
  return AccountBlock.fromJson(<String, dynamic>{
    ...base.toJson(),
    'chainIdentifier': htlcChain,
    'height': height,
    'hash': hash ?? htlcHash(9000 + height),
    'previousHash': previous ?? emptyHash.toString(),
    'token': token?.toJson(),
    'pairedAccountBlock': paired?.toJson(),
    'descendantBlocks': descendants
        .map((AccountBlock value) => value.toJson())
        .toList(),
    'basePlasma': 0,
    'usedPlasma': 0,
    'changesHash': emptyHash.toString(),
    'confirmationDetail': <String, dynamic>{
      'numConfirmations': 2,
      'momentumHeight': 100,
      'momentumHash': htlcHash(9999),
      'momentumTimestamp': timestamp,
    },
  });
}

AccountBlock htlcCreate(
  HtlcSwap swap, {
  required bool initial,
  int keySize = htlcPreimageMaxLength,
}) {
  final bool sending = initial == (swap.direction == P2pSwapDirection.outgoing);
  final Token token = sending ? kZnnCoin : kQsrCoin;
  final AccountBlockTemplate block =
      HtlcApi().create(
          token,
          sending ? swap.fromAmount : swap.toAmount!,
          Address.parse(sending ? swap.counterpartyAddress : swap.selfAddress),
          initial
              ? swap.initialHtlcExpirationTime
              : swap.counterHtlcExpirationTime!,
          swap.hashType,
          keySize,
          FormatUtils.decodeHexString(swap.hashLock),
        )
        ..chainIdentifier = swap.chainId
        ..address = Address.parse(
          sending ? swap.selfAddress : swap.counterpartyAddress,
        );
  return htlcBlock(
    template: block,
    hash: initial ? swap.initialHtlcId : swap.counterHtlcId,
    token: token,
  );
}

HtlcInfo htlcLive(
  HtlcSwap swap, {
  required bool initial,
  int keySize = htlcPreimageMaxLength,
}) {
  final bool sending = initial == (swap.direction == P2pSwapDirection.outgoing);
  return HtlcInfo(
    id: Hash.parse(initial ? swap.initialHtlcId : swap.counterHtlcId!),
    timeLocked: Address.parse(
      sending ? swap.selfAddress : swap.counterpartyAddress,
    ),
    hashLocked: Address.parse(
      sending ? swap.counterpartyAddress : swap.selfAddress,
    ),
    amount: sending ? swap.fromAmount : swap.toAmount!,
    tokenStandard: sending ? znnZts : qsrZts,
    expirationTime: initial
        ? swap.initialHtlcExpirationTime
        : swap.counterHtlcExpirationTime!,
    hashType: swap.hashType,
    keyMaxSize: keySize,
    hashLock: FormatUtils.decodeHexString(swap.hashLock),
  );
}

AccountBlock htlcTerminal(
  HtlcSwap swap, {
  required bool unlock,
  required bool initial,
  int height = 1,
  String? previous,
}) {
  final AccountBlock creation = htlcCreate(swap, initial: initial);
  final AccountBlockTemplate call =
      (unlock
            ? HtlcApi().unlock(
                creation.hash,
                FormatUtils.decodeHexString(swap.preimage!),
              )
            : HtlcApi().reclaim(creation.hash))
        ..address = Address.parse(
          unlock
              ? (initial == (swap.direction == P2pSwapDirection.outgoing)
                    ? swap.counterpartyAddress
                    : swap.selfAddress)
              : creation.address.toString(),
        );
  final AccountBlock paired = htlcBlock(
    template: call,
    hash: htlcHash(height + 6000),
  );
  final AccountBlockTemplate transfer =
      AccountBlockTemplate.send(
          unlock
              ? htlcLive(swap, initial: initial).hashLocked
              : creation.address,
          creation.tokenStandard,
          creation.amount,
        )
        ..address = htlcAddress
        ..blockType = BlockTypeEnum.contractSend.index;
  final AccountBlock output = htlcBlock(
    template: transfer,
    hash: htlcHash(height + 7000),
  );
  final AccountBlockTemplate received =
      AccountBlockTemplate(blockType: BlockTypeEnum.contractReceive.index)
        ..address = htlcAddress
        ..fromBlockHash = paired.hash;
  return htlcBlock(
    template: received,
    height: height,
    previous: previous,
    paired: paired,
    descendants: <AccountBlock>[output],
  );
}

class MemoryHtlcOperation {
  MemoryHtlcOperation(this.kind, this.commit);
  final String kind;
  final void Function() commit;
  final Completer<void> reply = Completer<void>();
  bool _committed = false;
  void optimisticCommit() {
    if (!_committed) {
      _committed = true;
      commit();
    }
  }

  void complete() {
    optimisticCommit();
    reply.complete();
  }

  void fail(Object error) => reply.completeError(error, StackTrace.current);
}

/// Implements only finite in-memory Box operations, including optimistic cache.
class MemoryHtlcBox implements Box<dynamic> {
  MemoryHtlcBox(this.name);
  @override
  final String name;
  final Map<dynamic, dynamic> entries = <dynamic, dynamic>{};
  final List<MemoryHtlcOperation> calls = <MemoryHtlcOperation>[];
  final Set<String> deferred = <String>{};
  bool optimistic = false;
  bool open = true;
  Object? readError;
  int destructiveCalls = 0;
  Future<void> _write(String kind, void Function() commit) {
    final MemoryHtlcOperation operation = MemoryHtlcOperation(kind, commit);
    calls.add(operation);
    if (optimistic) operation.optimisticCommit();
    if (!deferred.contains(kind)) operation.complete();
    return operation.reply.future;
  }

  void _read() {
    if (readError != null) {
      Error.throwWithStackTrace(readError!, StackTrace.current);
    }
  }

  @override
  bool get isOpen => open;
  @override
  int get length {
    _read();
    return entries.length;
  }

  @override
  Iterable<dynamic> get keys {
    _read();
    return entries.keys;
  }

  @override
  Iterable<dynamic> get values {
    _read();
    return entries.values;
  }

  @override
  Map<dynamic, dynamic> toMap() {
    _read();
    return Map<dynamic, dynamic>.of(entries);
  }

  @override
  bool containsKey(dynamic key) {
    _read();
    return entries.containsKey(key);
  }

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    _read();
    return entries[key] ?? defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) =>
      _write('put', () => entries[key] = value);
  @override
  Future<void> delete(dynamic key) =>
      _write('delete', () => entries.remove(key));
  @override
  Future<void> deleteAll(Iterable<dynamic> keys) {
    final List<dynamic> originals = keys.toList();
    return _write('deleteAll', () {
      originals.forEach(entries.remove);
    });
  }

  @override
  Future<void> flush() => _write('flush', () {});
  @override
  Future<void> close() => _write('close', () => open = false);
  @override
  Future<void> deleteFromDisk() {
    destructiveCalls++;
    throw StateError('Synthetic destructive operation refused');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Synthetic Box boundary');
}

class HtlcFixture {
  HtlcFixture(int seed) : number = seed {
    owned.addAll(<Object>[swaps, cursor]);
    service = HtlcSwapsService.bound(
      swaps: swaps,
      cursor: cursor,
      ownsBox: owned.contains,
    );
    store = service.captureStore(chainId: htlcChain)!;
    record = htlcRecord(seed);
    seedRecord(record);
  }
  final int number;
  final MemoryHtlcBox swaps = MemoryHtlcBox('synthetic-swaps');
  final MemoryHtlcBox cursor = MemoryHtlcBox('synthetic-cursor');
  final Set<Object> owned = <Object>{};
  late final HtlcSwapsService service;
  late final HtlcStoreCapture store;
  late HtlcSwap record;
  MemoryHtlcBox get journal => swaps;
  Map<dynamic, dynamic> get markers => <dynamic, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in swaps.entries.entries)
      if (entry.key is String &&
          (entry.key as String).startsWith('_htlc-private:v1:'))
        entry.key: jsonDecode(entry.value as String),
  };
  Object wallet = Object();
  Object api = Object();
  Object transport = Object();
  String path = 'synthetic-wallet';
  String url = 'synthetic-node';
  int revision = 0;
  bool ready = true;
  String selected = htlcOwner(3);
  final List<String> members = <String>[htlcOwner(1), htlcOwner(3)];
  final List<AccountBlock> blocks = <AccountBlock>[];
  final List<(int, int)> pages = <(int, int)>[];
  final List<String> liveReads = <String>[];
  final List<String> blockReads = <String>[];
  final List<String> signers = <String>[];
  final List<WalletNotification> notifications = <WalletNotification>[];
  Future<SyncInfo> Function()? syncRead;
  Future<AccountBlock?> Function()? frontierRead;
  Future<List<AccountBlock>?> Function(int, int)? pageRead;
  Future<AccountBlock?> Function(String)? blockRead;
  Future<HtlcInfo> Function(String)? liveRead;
  Future<int> Function()? timeRead;
  Future<AccountBlockTemplate> Function(AccountBlockTemplate, String)?
  publication;
  Future<void> Function(WalletNotification)? notification;
  Future<void> Function()? wakeDisable;
  int syncCalls = 0;
  int wakeEnables = 0;
  int wakeDisables = 0;
  void seedRecord(HtlcSwap value) {
    swaps.entries[value.id] = jsonEncode(value.toJson());
  }

  SyncInfo synced() => SyncInfo.fromJson(<String, dynamic>{
    'state': SyncState.syncDone.index,
    'currentHeight': 100,
    'targetHeight': 100,
  });
  HtlcWorkerOrigin capture({bool Function()? sourceIsCurrent}) {
    final List<Object> identities = <Object>[wallet, api, transport];
    final List<String> originalMembers = List<String>.of(members);
    final String originalPath = path;
    final String originalUrl = url;
    final String originalSelected = selected;
    final int originalRevision = revision;
    return HtlcWorkerOrigin(
      walletIdentity: wallet,
      store: store,
      chainId: htlcChain,
      selected: selected,
      members: originalMembers,
      isCurrent: () =>
          ready &&
          identical(wallet, identities[0]) &&
          identical(api, identities[1]) &&
          identical(transport, identities[2]) &&
          path == originalPath &&
          url == originalUrl &&
          selected == originalSelected &&
          revision == originalRevision &&
          members.join(',') == originalMembers.join(',') &&
          (sourceIsCurrent?.call() ?? true),
      canNotify: true,
      readSync: () {
        syncCalls++;
        return syncRead?.call() ?? Future<SyncInfo>.value(synced());
      },
      readFrontier: () =>
          frontierRead?.call() ??
          Future<AccountBlock?>.value(blocks.isEmpty ? null : blocks.last),
      readBlocks: (int height, int count) {
        pages.add((height, count));
        return pageRead?.call(height, count) ??
            Future<List<AccountBlock>?>.value(
              blocks.skip(height - 1).take(count).toList(),
            );
      },
      readBlock: (String id) {
        blockReads.add(id);
        return blockRead?.call(id) ??
            Future<AccountBlock?>.value(
              id == record.initialHtlcId
                  ? htlcCreate(record, initial: true)
                  : id == record.counterHtlcId
                  ? htlcCreate(record, initial: false)
                  : null,
            );
      },
      readLive: (String id) {
        liveReads.add(id);
        return liveRead?.call(id) ??
            Future<HtlcInfo>.value(
              htlcLive(record, initial: id == record.initialHtlcId),
            );
      },
      readChainTime: () => timeRead?.call() ?? Future<int>.value(1000),
      buildUnlock: (String id, List<int> value) =>
          HtlcApi().unlock(Hash.parse(id), List<int>.of(value))
            ..chainIdentifier = htlcChain,
      publish: (AccountBlockTemplate block, String target) {
        signers.add(target);
        return publication?.call(block, target) ??
            Future<AccountBlockTemplate>.value(
              AccountBlockTemplate.fromJson(block.toJson())
                ..address = Address.parse(target)
                ..hash = Hash.parse(htlcHash(number + 20000)),
            );
      },
      notify: (WalletNotification value) {
        notifications.add(value);
        return notification?.call(value) ?? Future<void>.value();
      },
      enableWakeLock: () async {
        wakeEnables++;
      },
      disableWakeLock: () {
        wakeDisables++;
        return wakeDisable?.call() ?? Future<void>.value();
      },
    );
  }
}

/// Observes an original Future before releasing a finite fixture boundary.
class HtlcOutcome<T> {
  HtlcOutcome(this.future) {
    unawaited(
      future.then<void>(
        (T value) {
          result = value;
          completed = true;
        },
        onError: (Object value, StackTrace trace) {
          error = value;
          stackTrace = trace;
          completed = true;
        },
      ),
    );
  }
  final Future<T> future;
  bool completed = false;
  T? result;
  Object? error;
  StackTrace? stackTrace;
}

Future<void> htlcMicrotasks() async {
  for (int step = 0; step < 80; step++) {
    await Future<void>.value();
  }
}

/// Advances both Future zones without awaiting a fake-dependent operation in
/// the real zone or moving the widget's timer clock.
Future<void> pumpHtlcUntil(
  WidgetTester tester,
  bool Function() completed,
) async {
  for (int turn = 0; turn < 80 && !completed(); turn++) {
    await tester.runAsync<void>(() async {
      await Future<void>.value();
    });
    await tester.pump();
  }
  expect(completed(), isTrue, reason: 'Original HTLC operation did not settle');
}
