import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';

class _Client extends Mock implements Zenon {}

class _Ledger extends Mock implements LedgerApi {}

Address _address(int id) => Address(
  Address.prefix,
  List<int>.generate(20, (int index) => index == 0 ? 0 : id),
);

AccountBlock _block(Address address, int id, {int? chain}) =>
    AccountBlock.fromJson(<String, dynamic>{
      'descendantBlocks': const <AccountBlock>[],
      'basePlasma': 21000,
      'usedPlasma': 21000,
      'changesHash': emptyHash.toString(),
      'confirmationDetail': null,
      'version': 1,
      'chainIdentifier': chain ?? getChainIdentifier(),
      'blockType': 2,
      'hash': Hash.digest(<int>[id]).toString(),
      'previousHash': emptyHash.toString(),
      'height': id,
      'momentumAcknowledged': <String, dynamic>{
        'hash': emptyHash.toString(),
        'height': 1,
      },
      'address': address.toString(),
      'toAddress': emptyAddress.toString(),
      'amount': '100000001',
      'tokenStandard': znnZts.toString(),
      'fromBlockHash': emptyHash.toString(),
      'data': null,
      'fusedPlasma': 0,
      'difficulty': 0,
      'nonce': '0',
      'publicKey': null,
      'signature': null,
      'token': kZnnCoin.toJson(),
      'pairedAccountBlock': null,
    });

class _Call {
  _Call(this.address, this.page);
  final Address address;
  final int page;
  final Completer<AccountBlockList> result = Completer<AccountBlockList>();

  void answer(List<AccountBlock> rows) => result.complete(
    AccountBlockList(count: rows.length, list: rows, more: true),
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  initHydratedStorage();
  setUpAll(() => registerFallbackValue(emptyAddress));
  final Address a = _address(1);
  final Address b = _address(2);
  late LatestTransactionsBloc reader;
  late List<_Call> calls;
  late String? previousNode;
  late String? previousAddress;
  late int? previousChain;

  setUp(() {
    previousNode = kCurrentNode;
    previousAddress = kSelectedAddress;
    previousChain = kNodeChainId;
    kCurrentNode = 'ws://127.0.0.1:45998';
    kSelectedAddress = a.toString();
    kNodeChainId = getChainIdentifier();
    final _Client client = _Client();
    final _Ledger ledger = _Ledger();
    calls = <_Call>[];
    when(() => client.ledger).thenReturn(ledger);
    when(
      () => ledger.getAccountBlocksByPage(
        any(),
        pageIndex: any(named: 'pageIndex'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((Invocation invocation) {
      final _Call call = _Call(
        invocation.positionalArguments.first as Address,
        invocation.namedArguments[#pageIndex] as int,
      );
      calls.add(call);
      return call.result.future;
    });
    reader = LatestTransactionsBloc(zenon: client, pageSize: 1);
    app.sl.pushNewScope();
    app.sl.registerSingleton<LatestTransactionsBloc>(reader);
  });

  tearDown(() async {
    if (!reader.isClosed) await reader.close();
    for (final _Call call in calls) {
      if (!call.result.isCompleted) call.answer(<AccountBlock>[]);
    }
    await _flush();
    await app.sl.popScope();
    kCurrentNode = previousNode;
    kSelectedAddress = previousAddress;
    kNodeChainId = previousChain;
  });

  test('a late old-address answer cannot replace a newer selection', () async {
    reader.add(InfiniteListRequested(address: a));
    await _flush();
    kSelectedAddress = b.toString();
    reader.add(InfiniteListRefreshRequested(address: b));
    await _flush();
    final AccountBlock current = _block(b, 2);
    calls[1].answer(<AccountBlock>[current]);
    await _flush();
    calls[0].answer(<AccountBlock>[_block(a, 1)]);
    await _flush();
    expect(reader.state.data, <AccountBlock>[current]);
    expect(reader.state.status, InfiniteListStatus.success);
  });

  test(
    'switching away and back never restores the original read owner',
    () async {
      reader.add(InfiniteListRequested(address: a));
      await _flush();
      kSelectedAddress = b.toString();
      reader.add(InfiniteListRefreshRequested(address: b));
      await _flush();
      kSelectedAddress = a.toString();
      reader.add(InfiniteListRefreshRequested(address: a));
      await _flush();
      calls[0].answer(<AccountBlock>[_block(a, 1)]);
      calls[1].answer(<AccountBlock>[_block(b, 2)]);
      await _flush();
      expect(reader.state.status, InfiniteListStatus.initial);
      final AccountBlock current = _block(a, 3);
      calls[2].answer(<AccountBlock>[current]);
      await _flush();
      expect(reader.state.data, <AccountBlock>[current]);
    },
  );

  test(
    'a node announcement revokes synchronously before its queued refresh',
    () async {
      reader.add(InfiniteListRequested(address: a));
      await _flush();
      NodeChange.announce();
      expect(reader.state.status, InfiniteListStatus.initial);
      calls[0].answer(<AccountBlock>[_block(a, 1)]);
      await _flush();
      expect(reader.state.data, isNull);
      expect(calls, hasLength(2));
      final AccountBlock current = _block(a, 2);
      calls[1].answer(<AccountBlock>[current]);
      await _flush();
      expect(reader.state.data, <AccountBlock>[current]);
    },
  );

  test('a changed reported chain cannot admit an old response', () async {
    reader.add(InfiniteListRequested(address: a));
    await _flush();
    kNodeChainId = 999;
    calls.single.answer(<AccountBlock>[_block(a, 1)]);
    await _flush();
    expect(reader.state.data, isNull);
    expect(reader.state.status, InfiniteListStatus.initial);
  });

  test(
    'refresh invalidates an old page and duplicate More asks do not queue',
    () async {
      reader.add(InfiniteListRequested(address: a));
      await _flush();
      calls[0].answer(<AccountBlock>[_block(a, 1)]);
      await _flush();
      reader
        ..add(InfiniteListMoreRequested(address: a))
        ..add(InfiniteListMoreRequested(address: a));
      await _flush();
      expect(calls, hasLength(2));
      expect(calls[1].page, 1);
      reader.add(InfiniteListRefreshRequested(address: a));
      await _flush();
      final AccountBlock current = _block(a, 3);
      calls[2].answer(<AccountBlock>[current]);
      await _flush();
      calls[1].answer(<AccountBlock>[_block(a, 2)]);
      await _flush();
      expect(reader.state.data, <AccountBlock>[current]);
      reader.add(InfiniteListMoreRequested(address: a));
      await _flush();
      expect(calls[3].page, 1);
    },
  );

  test('an overlapping page advances the RPC index independently', () async {
    final AccountBlock same = _block(a, 1);
    reader.add(InfiniteListRequested(address: a));
    await _flush();
    calls[0].answer(<AccountBlock>[same]);
    await _flush();
    for (int page = 1; page <= 2; page++) {
      reader.add(InfiniteListMoreRequested(address: a));
      await _flush();
      expect(calls[page].page, page);
      calls[page].answer(<AccountBlock>[same]);
      await _flush();
    }
    expect(reader.state.data, hasLength(3));
  });

  test(
    'wrong-address and wrong-chain rows fail without invented emptiness',
    () async {
      for (final bool wrongChain in <bool>[false, true]) {
        reader.add(InfiniteListRefreshRequested(address: a));
        await _flush();
        calls.last.answer(<AccountBlock>[
          _block(
            wrongChain ? a : b,
            1,
            chain: wrongChain ? getChainIdentifier() + 1 : null,
          ),
        ]);
        await _flush();
        expect(reader.state.status, InfiniteListStatus.failure);
        expect(reader.state.data, isNull);
      }
    },
  );

  test('only matching scoped cache rows can be restored', () async {
    final AccountBlock block = _block(a, 1);
    reader.add(InfiniteListRequested(address: a));
    await _flush();
    calls.single.answer(<AccountBlock>[block]);
    await _flush();
    final Map<String, dynamic> saved = reader.toJson(reader.state);
    expect(reader.fromJson(saved)!.data!.single.hash, block.hash);
    final Map<String, dynamic> legacy = Map<String, dynamic>.of(saved)
      ..remove('context');
    expect(reader.fromJson(legacy), isNull);
    kSelectedAddress = b.toString();
    expect(reader.fromJson(saved), isNull);
    kSelectedAddress = a.toString();
    kCurrentNode = 'ws://127.0.0.1:55998';
    expect(reader.fromJson(saved), isNull);
    kCurrentNode = 'ws://127.0.0.1:45998';
    kNodeChainId = 999;
    expect(reader.fromJson(saved), isNull);
  });

  test('empty successful caches still require a matching owner', () async {
    reader.add(InfiniteListRequested(address: a));
    await _flush();
    calls.single.answer(<AccountBlock>[]);
    await _flush();
    final Map<String, dynamic> saved = reader.toJson(reader.state);
    expect(reader.fromJson(saved)!.data, isEmpty);
    kSelectedAddress = b.toString();
    expect(reader.fromJson(saved), isNull);
  });

  test(
    'close revokes pending reads without reopening or refreshing them',
    () async {
      reader.add(InfiniteListRequested(address: a));
      await _flush();
      await reader.close();
      calls.single.answer(<AccountBlock>[_block(a, 1)]);
      await _flush();
      NodeChange.announce();
      reader.add(InfiniteListRequested(address: a));
      await _flush();
      expect(reader.state.data, isNull);
      expect(calls, hasLength(1));
    },
  );
}
