import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const int receiveChain = 321;

Hash receiveHash(int value) => Hash.digest(<int>[value]);

AccountBlock receiveInbound(
  Hash hash, {
  Address? destination,
  int chainId = receiveChain,
  int? type,
}) {
  final AccountBlockTemplate template =
      AccountBlockTemplate.send(
          destination ?? emptyAddress,
          znnZts,
          BigInt.parse('900719925474099300000001'),
        )
        ..hash = hash
        ..chainIdentifier = chainId
        ..blockType = type ?? BlockTypeEnum.userSend.index;
  return AccountBlock.fromJson(<String, dynamic>{
    ...template.toJson(),
    'descendantBlocks': const <dynamic>[],
    'basePlasma': 0,
    'usedPlasma': 0,
    'changesHash': emptyHash.toString(),
  });
}

SyncInfo receiveSync() => SyncInfo.fromJson(<String, dynamic>{
  'state': SyncState.syncDone.index,
  'currentHeight': 10,
  'targetHeight': 10,
});

class ReceiveCall {
  ReceiveCall(this.block, this.owner, this.canPublish);
  final AccountBlockTemplate block;
  final Address? owner;
  final bool Function()? canPublish;
}

/// Only in-memory preparation and response. No wallet or socket is created.
class ReceiveTransport extends AccountBlockUtils {
  final List<ReceiveCall> calls = <ReceiveCall>[];
  final List<(ReceiveCall, Completer<AccountBlockTemplate>)> pending =
      <(ReceiveCall, Completer<AccountBlockTemplate>)>[];
  Completer<void>? preparation;
  bool deferred = false;
  int dispatched = 0;
  Object? failure;
  AccountBlockTemplate Function(ReceiveCall)? reply;

  AccountBlockTemplate accepted(ReceiveCall call) =>
      AccountBlockTemplate.fromJson(call.block.toJson())
        ..address = call.owner!
        ..hash = receiveHash(100 + calls.indexOf(call));

  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate transactionParams,
    String purpose, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) async {
    final ReceiveCall call = ReceiveCall(
      transactionParams,
      address,
      canPublish,
    );
    calls.add(call);
    final Completer<void>? gate = preparation;
    if (gate != null) await gate.future;
    if (!(canPublish?.call() ?? true)) {
      throw StateError('Synthetic receive preparation revoked');
    }
    dispatched++;
    final Object? error = failure;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    if (!deferred) return reply?.call(call) ?? accepted(call);
    final Completer<AccountBlockTemplate> completion =
        Completer<AccountBlockTemplate>();
    pending.add((call, completion));
    return completion.future;
  }

  AccountBlockTemplate complete({Object? error, AccountBlockTemplate? block}) {
    final (ReceiveCall call, Completer<AccountBlockTemplate> completion) =
        pending.removeAt(0);
    final AccountBlockTemplate original = block ?? accepted(call);
    if (error == null) {
      completion.complete(original);
    } else {
      completion.completeError(error, StackTrace.current);
    }
    return original;
  }

  void release() {
    deferred = false;
    final Completer<void>? gate = preparation;
    if (gate != null && !gate.isCompleted) gate.complete();
    for (int index = pending.length; index > 0; index--) {
      complete();
    }
  }
}

class _Balances extends ZenonAddressUtils {
  @override
  void refreshBalance() {}
}

class ReceiveFixture {
  ReceiveFixture() {
    sender = newSender();
    worker = AutoReceiveTxWorker(
      originSource: (SendTransactionBloc owner, bool Function() isCurrent) {
        captures++;
        final int originalRevision = revision;
        final int originalChain = chainId;
        final int originalNodeChain = nodeChainId;
        final List<String> members = List<String>.of(addresses);
        final String selected = selectedAddress;
        return ReceiveOrigin(
          sender: owner,
          ledger: LedgerApi(),
          stats: StatsApi(),
          chainId: chainId,
          nodeChainId: nodeChainId,
          selectedAddress: selected,
          addresses: members,
          isCurrent: () =>
              active &&
              revision == originalRevision &&
              chainId == originalChain &&
              nodeChainId == originalNodeChain &&
              selectedAddress == selected &&
              listEquals(addresses, members) &&
              isCurrent(),
          readInbound: (Hash hash) async {
            proofReads++;
            reservedDuringRead.add(owner.busy.value);
            final Future<AccountBlock?> Function(Hash)? reader = readInbound;
            if (reader != null) return reader(hash);
            return receiveInbound(hash);
          },
          readSync: () async {
            syncReads++;
            final Future<SyncInfo> Function()? reader = readSync;
            if (reader != null) return reader();
            return receiveSync();
          },
        );
      },
      automaticEnabled: () {
        preferenceReads++;
        onReadAutomatic?.call();
        return automatic;
      },
      otherWorkerBusy: () => priorityBusy,
      onSuccess: (ReceiveOrigin origin, AccountBlockTemplate block, String to) {
        successes.add(block);
        successOwners.add(to);
        onSuccess?.call();
      },
      onQueued: (_) => queued++,
      onFailure: failures.add,
    );
    lease = worker.attachSender(sender);
  }

  final ReceiveTransport transport = ReceiveTransport();
  final List<SendTransactionBloc> senders = <SendTransactionBloc>[];
  late final SendTransactionBloc sender;
  late final AutoReceiveTxWorker worker;
  late Object lease;
  final List<AccountBlockTemplate> successes = <AccountBlockTemplate>[];
  final List<String> successOwners = <String>[];
  final List<Object> failures = <Object>[];
  final List<bool> reservedDuringRead = <bool>[];
  List<String> addresses = <String>[emptyAddress.toString()];
  String selectedAddress = emptyAddress.toString();
  int chainId = receiveChain;
  int nodeChainId = receiveChain;
  int revision = 0;
  int captures = 0;
  int preferenceReads = 0;
  int proofReads = 0;
  int syncReads = 0;
  int queued = 0;
  bool active = true;
  bool automatic = true;
  bool priorityBusy = false;
  Future<AccountBlock?> Function(Hash)? readInbound;
  Future<SyncInfo> Function()? readSync;
  VoidCallback? onSuccess;
  VoidCallback? onReadAutomatic;
  bool closed = false;

  SendTransactionBloc newSender() {
    final SendTransactionBloc value = SendTransactionBloc(
      accountBlockUtilsHelper: transport,
      zenonAddressUtils: _Balances(),
      recordRecipient: (_, _) async {},
    );
    senders.add(value);
    return value;
  }

  ReceiveOrigin capture({bool Function()? sourceIsCurrent}) =>
      worker.captureOrigin(sourceIsCurrent: sourceIsCurrent)!;

  Future<void> enqueue(
    Hash hash, {
    ReceiveOrigin? origin,
    String? destination,
  }) => worker.addHash(
    hash,
    origin: origin ?? capture(),
    toAddress: destination ?? selectedAddress,
  );

  Future<void> close() async {
    if (closed) return;
    transport.release();
    await worker.autoReceive();
    for (final SendTransactionBloc value in senders) {
      await value.close();
    }
    worker.dispose();
    closed = true;
  }
}

/// A finite positive logical boundary on the unit test's event queue.
Future<void> receiveTurnsUntil(bool Function() done) async {
  for (int turn = 0; turn < 60 && !done(); turn++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'Receive did not reach its finite boundary');
}

/// Widget time and the asynchronous bloc cancellation queue both make progress.
Future<void> pumpReceiveUntil(
  WidgetTester tester,
  bool Function() done,
) async {
  for (int turn = 0; turn < 60 && !done(); turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue, reason: 'Receive did not reach its rendered boundary');
}

Future<void> closeReceiveFixture(
  WidgetTester tester,
  ReceiveFixture fixture,
) async {
  bool closed = false;
  final Future<void> close = fixture.close().then<void>((_) {
    closed = true;
  });
  await pumpReceiveUntil(tester, () => closed);
  await close;
}
