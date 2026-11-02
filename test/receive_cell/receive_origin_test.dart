import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import '../publication_session/support.dart';
import 'support.dart';

class _Client extends Client {
  _Client(this.reply);
  final Future<Object?> Function(String) reply;
  final List<String> methods = <String>[];

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) {
    methods.add(method);
    return reply(method);
  }
}

class _Socket extends WsClient {
  int calls = 0;

  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) async {
    calls++;
    throw StateError('A fixture socket must never dispatch');
  }
}

class _Balances extends Mock implements MultipleBalanceBloc {}

class _Latest extends Mock implements LatestTransactionsBloc {}

class _Pending extends Mock implements PendingTransactionsBloc {}

void main() {
  initHydratedStorage();
  late ReceiveFixture fixture;
  late AutoReceiveTxWorker worker;
  late PublicationGlobals globals;
  late MockPublicationZenon node;
  late LedgerApi ledger;
  late StatsApi stats;
  late _Client client;
  final Hash hash = receiveHash(1);

  setUpAll(() {
    registerFallbackValue(const MultipleBalanceFetch(addresses: <String>[]));
    registerFallbackValue(
      InfiniteListRefreshRequested(address: emptyAddress),
    );
  });

  setUp(() {
    globals = PublicationGlobals();
    fixture = ReceiveFixture();
    node = MockPublicationZenon();
    client = _Client((String method) async {
      if (method == 'ledger.getAccountBlockByHash') {
        return receiveInbound(hash).toJson();
      }
      if (method == 'stats.syncInfo') return receiveSync().toJson();
      throw StateError('Unexpected synthetic read');
    });
    ledger = LedgerApi()..setClient(client);
    stats = StatsApi()..setClient(client);
    when(() => node.ledger).thenReturn(ledger);
    when(() => node.stats).thenReturn(stats);
    app.zenon = node;
    kWalletFile = MockPublicationFile();
    kWalletPath = 'isolated-receive-wallet';
    kSelectedAddress = emptyAddress.toString();
    kDefaultAddressList = <String?>[
      emptyAddress.toString(),
      tokenAddress.toString(),
    ];
    kCurrentPage = Tabs.dashboard;
    kWalletInitCompleted = true;
    kCurrentNode = 'isolated-receive-node';
    kNodeChainId = receiveChain;
    setChainIdentifier(chainIdentifier: receiveChain);
    worker = AutoReceiveTxWorker(
      automaticEnabled: () => true,
      otherWorkerBusy: () => false,
      onFailure: (_) {},
    );
    app.sl.pushNewScope();
    app.sl.registerSingleton<AutoReceiveTxWorker>(worker);
    worker.attachSender(fixture.sender);
  });

  tearDown(() async {
    worker.dispose();
    await app.sl.popScope();
    await fixture.close();
    globals.restore();
    WalletContextRevision.invalidate();
  });

  test(
    'production origin copies ordered members and binds independent APIs',
    () {
      final ReceiveOrigin origin = worker.captureOrigin()!;
      expect(origin.addresses, kDefaultAddressList);
      expect(() => origin.addresses.add('unknown'), throwsUnsupportedError);
      expect(origin.selectedAddress, emptyAddress.toString());
      expect(origin.chainId, receiveChain);
      expect(origin.nodeChainId, receiveChain);
      expect(origin.ledger, isNot(same(ledger)));
      expect(origin.stats, isNot(same(stats)));
      expect(origin.ledger.client, same(client));
      expect(origin.stats.client, same(client));
      expect(origin.isCurrent, isTrue);
      expect(client.methods, isEmpty);
    },
  );

  test('a returning receive proof cannot erase nested revocation', () {
    bool current = true;
    bool reenter = false;
    final List<bool> nested = <bool>[];
    late final ReceiveOrigin origin;
    origin = ReceiveOrigin(
      sender: fixture.sender,
      ledger: ledger,
      stats: stats,
      chainId: receiveChain,
      nodeChainId: receiveChain,
      selectedAddress: emptyAddress.toString(),
      addresses: <String>[emptyAddress.toString(), tokenAddress.toString()],
      isCurrent: () {
        final bool accepted = current;
        if (reenter) {
          reenter = false;
          current = false;
          nested.add(origin.isCurrent);
          current = true;
        }
        return accepted;
      },
    );
    expect(origin.isCurrent, isTrue);
    reenter = true;
    expect(origin.isCurrent, isFalse);
    expect(nested, <bool>[false]);
    expect(current, isTrue);
    expect(origin.isCurrent, isFalse);
    expect(origin.readSync, throwsA(isA<ReceiveRefused>()));
    expect(() => origin.readInbound(hash), throwsA(isA<ReceiveRefused>()));
    expect(() => origin.receiveBlock(hash), throwsA(isA<ReceiveRefused>()));
    expect(client.methods, isEmpty);
    expect(fixture.transport.calls, isEmpty);
  });

  final Map<String, void Function()> mutations = <String, void Function()>{
    'wallet file': () => kWalletFile = MockPublicationFile(),
    'wallet path': () => kWalletPath = 'another-isolated-wallet',
    'wallet lock': () => kCurrentPage = Tabs.lock,
    'wallet readiness': () => kWalletInitCompleted = false,
    'selected account': () => kSelectedAddress = tokenAddress.toString(),
    'ordered accounts': () =>
        kDefaultAddressList = kDefaultAddressList.reversed.toList(),
    'member account': () => kDefaultAddressList = <String?>[
      emptyAddress.toString(),
    ],
    'node': () => kCurrentNode = 'another-isolated-node',
    'node chain': () => kNodeChainId = 1,
    'signing chain': setChainIdentifier,
    'wallet revision round trip': WalletContextRevision.invalidate,
    'SDK owner': () => app.zenon = MockPublicationZenon(),
  };
  for (final MapEntry<String, void Function()> mutation in mutations.entries) {
    test('${mutation.key} revokes the original before fresh reads', () {
      final ReceiveOrigin origin = worker.captureOrigin()!;
      mutation.value();
      expect(origin.isCurrent, isFalse);
      expect(origin.readSync, throwsA(isA<ReceiveRefused>()));
      expect(
        () => origin.readInbound(hash),
        throwsA(isA<ReceiveRefused>()),
      );
      expect(client.methods, isEmpty);
    });
  }

  for (final int? invalid in <int?>[null, 0, 1]) {
    test('unknown or mismatched node chain $invalid refuses capture', () {
      kNodeChainId = invalid;
      expect(worker.captureOrigin(), isNull);
      expect(client.methods, isEmpty);
    });
  }

  test('nullable or duplicate account lists refuse capture', () {
    kDefaultAddressList.add(null);
    expect(worker.captureOrigin(), isNull);
    kDefaultAddressList = <String?>[
      emptyAddress.toString(),
      emptyAddress.toString(),
    ];
    expect(worker.captureOrigin(), isNull);
  });

  test(
    'replacement registered worker revokes retained original callbacks',
    () async {
      final ReceiveOrigin origin = worker.captureOrigin()!;
      await app.sl.unregister<AutoReceiveTxWorker>();
      app.sl.registerSingleton<AutoReceiveTxWorker>(fixture.worker);
      expect(origin.isCurrent, isFalse);
      expect(origin.readSync, throwsA(isA<ReceiveRefused>()));
      expect(worker.captureOrigin(), isNull);
      expect(client.methods, isEmpty);
    },
  );

  test('a shared API rebind cannot redirect a delayed original read', () async {
    final Completer<Object?> reply = Completer<Object?>();
    final _Client original = _Client((_) => reply.future);
    final _Client replacement = _Client((_) async {
      throw StateError('Replacement must never read');
    });
    ledger.setClient(original);
    stats.setClient(original);
    final ReceiveOrigin origin = worker.captureOrigin()!;
    final Future<AccountBlock?> read = origin.readInbound(hash);
    ledger.setClient(replacement);
    stats.setClient(replacement);
    reply.complete(receiveInbound(hash).toJson());
    expect((await read)!.hash, hash);
    expect(origin.isCurrent, isFalse);
    ledger.setClient(original);
    stats.setClient(original);
    expect(origin.isCurrent, isFalse);
    expect(original.methods, <String>['ledger.getAccountBlockByHash']);
    expect(replacement.methods, isEmpty);
    expect(origin.readSync, throwsA(isA<ReceiveRefused>()));
  });

  test(
    'same socket with a different URL cannot restore old authority',
    () async {
      final _Socket socket = _Socket()..url = 'ws://fixture.invalid/original';
      ledger.setClient(socket);
      stats.setClient(socket);
      try {
        final ReceiveOrigin origin = worker.captureOrigin()!;
        socket.url = 'ws://fixture.invalid/replacement';
        expect(origin.isCurrent, isFalse);
        socket.url = 'ws://fixture.invalid/original';
        expect(origin.isCurrent, isFalse);
        expect(origin.readSync, throwsA(isA<ReceiveRefused>()));
        expect(socket.calls, 0);
      } finally {
        await socket.restartedStreamController.close();
      }
    },
  );

  test('explicit receive construction uses its captured chain', () {
    final ReceiveOrigin origin = fixture.capture();
    setChainIdentifier();
    final AccountBlockTemplate block = origin.receiveBlock(hash);
    expect(block.chainIdentifier, receiveChain);
    expect(block.fromBlockHash, hash);
    expect(block.blockType, BlockTypeEnum.userReceive.index);
  });

  test(
    'captured refresh observers never redirect to replacement blocs',
    () async {
      final _Pending old = _Pending();
      final _Pending replacement = _Pending();
      app.sl.registerSingleton<PendingTransactionsBloc>(old);
      final ReceiveOrigin origin = worker.captureOrigin()!;
      await app.sl.unregister<PendingTransactionsBloc>();
      app.sl.registerSingleton<PendingTransactionsBloc>(replacement);
      await worker.addHash(
        hash,
        origin: origin,
        toAddress: origin.selectedAddress,
      );
      await worker.autoReceive();
      expect(worker.originals.single.result!.accepted, isTrue);
      verifyNever(() => old.add(any()));
      verifyNever(() => replacement.add(any()));
    },
  );

  test('a reentrant original refresh revokes later observers', () async {
    final _Balances balances = _Balances();
    final _Latest latest = _Latest();
    final _Pending pending = _Pending();
    app.sl.registerSingleton<MultipleBalanceBloc>(balances);
    app.sl.registerSingleton<LatestTransactionsBloc>(latest);
    app.sl.registerSingleton<PendingTransactionsBloc>(pending);
    when(() => balances.add(any())).thenAnswer((_) {
      WalletContextRevision.invalidate();
    });
    final Future<AccountBlockTemplate?> request = worker
        .autoReceiveTransactionHash(hash);
    final AccountBlockTemplate? block = await request;
    await receiveTurnsUntil(() => !worker.running);
    expect(worker.originals.single.result!.block, same(block));
    verify(() => balances.add(any())).called(1);
    verifyNever(() => latest.add(any()));
    verifyNever(() => pending.add(any()));
    expect(worker.autoReceiveTransactionHash(hash), same(request));
  });
}
