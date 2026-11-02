import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../integration_test/support/devnet_pillar_observation.dart';
import '../../integration_test/support/devnet_registration_host.dart';
import '../../integration_test/support/devnet_test_context.dart';
import '../helpers/hydrated_bloc.dart';

class _Node extends Mock implements Zenon {}

class _Ledger extends Mock implements LedgerApi {}

class _Stats extends Mock implements StatsApi {}

class _Socket extends Mock implements WsClient {}

class _Embedded extends Mock implements EmbeddedApi {}

class _Pillar extends Mock implements PillarApi {}

class _HostBalances extends Mock implements MultipleBalanceBloc {}

class _Wallet extends Mock implements Wallet {}

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

class _NoSignerFile extends DevnetWalletFile {
  _NoSignerFile(super._wallet);
  int acquisitions = 0;
  int releases = 0;

  @override
  Future<Wallet> open() {
    acquisitions++;
    throw StateError('Offline fixture must not acquire a signer');
  }

  @override
  Future<void> close() async {
    releases++;
  }
}

Future<T> _finish<T>(WidgetTester tester, Future<T> original) async {
  T? value;
  Object? error;
  StackTrace? trace;
  bool finished = false;
  unawaited(
    original.then<void>(
      (T result) {
        value = result;
        finished = true;
      },
      onError: (Object failure, StackTrace stack) {
        error = failure;
        trace = stack;
        finished = true;
      },
    ),
  );
  for (int turn = 0; turn < 30 && !finished; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(finished, isTrue, reason: 'The original future must finish');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return value as T;
}

Future<DevnetPillarFailure> _refusal(Future<Object?> original) async {
  try {
    await original;
  } on DevnetPillarFailure catch (failure) {
    return failure;
  }
  fail('The original observation must refuse');
}

void main() {
  initHydratedStorage();
  const String owner = DevnetTestContext.testPillarOwnerAddress;
  final String other = DevnetTestContext.fundedDevAddresses[8]!;
  const String endpoint = 'ws://127.0.0.1:35998';
  const List<String> kinds = <String>[
    'block',
    'pending',
    'height',
    'frontier',
    'pillar',
  ];
  late Zenon? previousNode;
  late _Node node;
  late _Ledger ledger;
  late _Stats stats;
  late _Socket socket;
  late _Embedded embedded;
  late _Pillar pillar;
  late _Wallet wallet;
  late _NoSignerFile file;
  late DevnetWalletBinding binding;
  late WalletFlightRegistry registry;
  late RegistrationConfirmation confirmation;
  late SendTransactionBloc sender;
  late RegistrationPublisher publisher;
  late List<AccountBlockTemplate> published;
  late List<String> calls;
  late List<Hash> queriedHashes;
  late Object scenario;
  late Future<AccountBlock?> Function() blockRead;
  late Future<AccountBlockList> Function() pendingRead;
  late Future<AccountBlockList> Function() heightRead;
  late Future<Momentum> Function() frontierRead;
  late Future<PillarInfo?> Function() pillarRead;
  late Future<Object?> injectedOriginal;
  int frontierNumber = 10;

  AccountBlockTemplate draft() => PillarApi().register(
    DevnetTestContext.testPillarName,
    Address.parse(DevnetTestContext.testPillarProducerAddress),
    Address.parse(DevnetTestContext.testPillarRewardAddress),
    DevnetTestContext.testPillarMomentumReward,
    DevnetTestContext.testPillarDelegationReward,
  );

  AccountBlock observed({
    Hash? hash,
    int? chain,
    String? address,
    bool confirmed = true,
  }) => AccountBlock.fromJson(<String, dynamic>{
    ...published.single.toJson(),
    'hash': (hash ?? published.single.hash).toString(),
    'chainIdentifier': chain ?? DevnetTestContext.chainId,
    'address': address ?? owner,
    'descendantBlocks': const <dynamic>[],
    'basePlasma': 0,
    'usedPlasma': 0,
    'changesHash': emptyHash.toString(),
    'confirmationDetail': confirmed
        ? <String, dynamic>{
            'numConfirmations': 1,
            'momentumHeight': 11,
            'momentumHash': 'cd' * 32,
            'momentumTimestamp': 123,
          }
        : null,
  });

  PillarInfo info() => PillarInfo.fromJson(const <String, dynamic>{
    'name': DevnetTestContext.testPillarName,
    'rank': 1,
    'type': PillarInfo.regularPillarType,
    'ownerAddress': owner,
    'producerAddress': DevnetTestContext.testPillarProducerAddress,
    'withdrawAddress': DevnetTestContext.testPillarRewardAddress,
    'giveMomentumRewardPercentage': DevnetTestContext.testPillarMomentumReward,
    'giveDelegateRewardPercentage':
        DevnetTestContext.testPillarDelegationReward,
    'isRevocable': true,
    'revokeCooldown': 0,
    'revokeTimestamp': 0,
    'currentStats': <String, dynamic>{
      'producedMomentums': 0,
      'expectedMomentums': 0,
    },
    'weight': '0',
  });

  Momentum frontier() {
    frontierNumber++;
    return Momentum(
      1,
      DevnetTestContext.chainId,
      Hash.parse(frontierNumber.toRadixString(16).padLeft(64, '0')),
      emptyHash,
      frontierNumber,
      frontierNumber * 10,
      <int>[],
      <AccountHeader>[],
      emptyHash,
      '',
      '',
      Address.parse(owner),
    );
  }

  setUpAll(() {
    registerFallbackValue(emptyHash);
    registerFallbackValue(emptyAddress);
    registerFallbackValue(
      AccountBlockTemplate(blockType: BlockTypeEnum.userSend.index),
    );
    registerFallbackValue(() => true);
  });

  setUp(() {
    previousNode = app.zenon;
    node = _Node();
    ledger = _Ledger();
    stats = _Stats();
    socket = _Socket();
    embedded = _Embedded();
    pillar = _Pillar();
    wallet = _Wallet();
    file = _NoSignerFile(wallet);
    when(() => node.ledger).thenReturn(ledger);
    when(() => node.stats).thenReturn(stats);
    when(() => node.wsClient).thenReturn(socket);
    when(() => node.embedded).thenReturn(embedded);
    when(() => embedded.pillar).thenReturn(pillar);
    when(() => ledger.client).thenReturn(socket);
    when(() => stats.client).thenReturn(socket);
    when(() => pillar.client).thenReturn(socket);
    when(() => socket.url).thenReturn(endpoint);
    when(socket.isClosed).thenReturn(false);
    when(socket.status).thenReturn(WebsocketStatus.running);
    app.zenon = node;
    binding = DevnetWalletBinding.install(
      walletFile: file,
      addresses: <String>[owner, other],
      selectedAddress: owner,
      nodeUrl: endpoint,
      verifiedChainId: DevnetTestContext.chainId,
    );
    scenario = Object();
    published = <AccountBlockTemplate>[];
    calls = <String>[];
    queriedHashes = <Hash>[];
    frontierNumber = 10;
    blockRead = () async => observed();
    pendingRead = () async => AccountBlockList(list: <AccountBlock>[]);
    heightRead = () async => AccountBlockList(list: <AccountBlock>[]);
    frontierRead = () async => frontier();
    pillarRead = () async => info();
    when(() => ledger.getAccountBlockByHash(any())).thenAnswer((
      Invocation call,
    ) {
      calls.add('block');
      queriedHashes.add(call.positionalArguments.single as Hash);
      return blockRead();
    });
    when(
      () => ledger.getUnconfirmedBlocksByAddress(
        any(),
        pageIndex: any(named: 'pageIndex'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((Invocation call) {
      expect(call.positionalArguments.single, Address.parse(owner));
      expect(call.namedArguments[#pageIndex], 0);
      expect(call.namedArguments[#pageSize], 100);
      calls.add('pending');
      return pendingRead();
    });
    when(() => ledger.getAccountBlocksByHeight(any(), any(), any())).thenAnswer(
      (Invocation call) {
        expect(call.positionalArguments, <Object>[
          Address.parse(owner),
          published.single.height,
          1,
        ]);
        calls.add('height');
        return heightRead();
      },
    );
    when(ledger.getFrontierMomentum).thenAnswer((_) {
      calls.add('frontier');
      return frontierRead();
    });
    when(() => pillar.getByName(any())).thenAnswer((Invocation call) {
      expect(call.positionalArguments.single, DevnetTestContext.testPillarName);
      calls.add('pillar');
      return pillarRead();
    });
    registry = WalletFlightRegistry(
      currentChainId: getChainIdentifier,
      lookup: (int _, Hash _) async => false,
    );
    confirmation = RegistrationConfirmation(
      context: WalletActionContext.capture(owner),
      chainId: DevnetTestContext.chainId,
      walletAddresses: <String>[owner, other],
      registry: registry,
    );
    final _Blocks blocks = _Blocks();
    final _Balances balances = _Balances();
    when(balances.refreshBalance).thenAnswer((_) {});
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        canPublish: any(named: 'canPublish'),
      ),
    ).thenAnswer((Invocation call) {
      final AccountBlockTemplate original =
          AccountBlockTemplate.fromJson(
              (call.positionalArguments.first as AccountBlockTemplate).toJson(),
            )
            ..address = Address.parse(owner)
            ..height = 7
            ..hash = Hash.parse('ab' * 32);
      return OriginalPublications.runForOwners<AccountBlockTemplate>(
        <Object>[file, node],
        (OriginalPublication<AccountBlockTemplate> operation) async {
          operation.retainPublicationHash(original.hash.toString());
          published.add(original);
          return original;
        },
      );
    });
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
    );
    publisher = RegistrationPublisher(
      sender: sender,
      confirmation: confirmation,
    );
  });

  tearDown(() {
    try {
      kWalletFile = file;
      binding.restore();
      confirmation.dispose();
      registry.dispose();
      expect(file.acquisitions, 0);
      expect(file.releases, 0);
      verifyZeroInteractions(wallet);
      verifyNever(() => socket.initialize(any(), retry: any(named: 'retry')));
      verifyNever(socket.stop);
      verifyNever(() => socket.sendRequest(any(), any()));
    } finally {
      app.zenon = previousNode;
    }
  });

  Future<DevnetPillarObservation> publish(
    WidgetTester tester, {
    bool retain = true,
  }) async {
    await tester.pumpWidget(
      DevnetRegistrationHost(
        balances: _HostBalances(),
        createSender: () => sender,
        child: const SizedBox(),
      ),
    );
    final AccountBlockTemplate expected = draft();
    final DevnetPillarObservation observer = DevnetPillarObservation.capture(
      scenario: scenario,
      sender: sender,
      ownerAddress: owner,
      expectedRegistration: expected,
    )..requireCurrent();
    final AccountBlockTemplate original = await _finish(
      tester,
      publisher.createAccountBlock(expected, 'Offline registration fixture'),
    );
    if (retain) observer.retain(original);
    return observer;
  }

  Future<void> closeOwned(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _finish(tester, sender.close());
    expect(published, hasLength(1));
  }

  void prepare(String kind) {
    if (kind != 'block' && kind != 'pillar') {
      blockRead = () async => null;
    }
  }

  Object valueFor(String kind) {
    switch (kind) {
      case 'block':
        return observed();
      case 'pending':
      case 'height':
        return AccountBlockList(list: <AccountBlock>[]);
      case 'frontier':
        return frontier();
      case 'pillar':
        return info();
    }
    throw StateError('Unknown offline read kind');
  }

  void inject(String kind, Future<Object?> Function() action) {
    Future<T> original<T>() {
      final Future<T> read = action().then<T>((Object? value) => value as T);
      injectedOriginal = read;
      return read;
    }

    switch (kind) {
      case 'block':
        blockRead = original<AccountBlock?>;
        return;
      case 'pending':
        pendingRead = original<AccountBlockList>;
        return;
      case 'height':
        heightRead = original<AccountBlockList>;
        return;
      case 'frontier':
        frontierRead = original<Momentum>;
        return;
      case 'pillar':
        pillarRead = original<PillarInfo?>;
        return;
      default:
        throw StateError('Unknown offline read kind');
    }
  }

  Future<Object?> attempt(
    WidgetTester tester,
    DevnetPillarObservation observer,
    String kind,
  ) async {
    final AccountBlock block = await observer.readBlock(
      tester,
      timeout: const Duration(seconds: 2),
      requestTimeout: const Duration(milliseconds: 300),
      maxPolls: 2,
    );
    return kind == 'pillar' ? observer.readPillar(tester) : block;
  }

  void staysRefused(
    DevnetPillarObservation observer,
    DevnetPillarFailure failure,
    int count,
  ) {
    expect(observer.requireCurrent, throwsA(same(failure)));
    expect(calls, hasLength(count));
    expect(failure.toString(), contains(failure.code.name));
    expect(failure.toString(), isNot(contains(owner)));
    expect(failure.toString(), isNot(contains(endpoint)));
    expect(
      failure.toString(),
      isNot(contains(published.single.hash.toString())),
    );
  }

  testWidgets('exact original block and pillar data preserve success', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      expect(DevnetPillarObservation.forScenario(scenario), same(observer));
      observer.originalBlock.hash = emptyHash;
      expect(observer.originalBlock.hash, published.single.hash);
      final AccountBlock block = await observer.readBlock(tester);
      final PillarInfo pillarInfo = await observer.readPillar(tester);
      expect(block.hash, published.single.hash);
      expect(block.height, published.single.height);
      expect(block.address, Address.parse(owner));
      expect(pillarInfo.name, DevnetTestContext.testPillarName);
      expect(calls, <String>['block', 'pillar']);
      expect(queriedHashes, <Hash>[published.single.hash]);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  void confirmCachedOriginal() {
    final AccountBlockTemplate original = published.single;
    final InFlightBlocks flights =
        registry.forWallet(
            DevnetTestContext.chainId,
            <String>[owner, other],
          )
          ..sent(hash: original.hash, amount: original.amount)
          ..settle(original.hash);
    expect(flights.hasConfirmed(original.hash), isTrue);
  }

  testWidgets('exact unconfirmed hash waits for positive confirmation', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      final AccountBlock unconfirmed = observed(confirmed: false);
      final AccountBlock confirmed = observed();
      int reads = 0;
      blockRead = () async => reads++ == 0 ? unconfirmed : confirmed;
      final AccountBlock block = await observer.readBlock(
        tester,
        timeout: const Duration(seconds: 2),
        requestTimeout: const Duration(milliseconds: 300),
        maxPolls: 2,
      );
      expect(block, same(confirmed));
      expect(await observer.readPillar(tester), isA<PillarInfo>());
      expect(reads, 2);
      expect(
        queriedHashes.every((Hash hash) => hash == published.single.hash),
        isTrue,
      );
      final List<DevnetPillarRead> originals = observer.originalReads
          .where((DevnetPillarRead read) => read.kind == 'block')
          .toList();
      expect(originals.first.value, same(unconfirmed));
      expect(originals.last.value, same(confirmed));
      expect(calls, <String>[
        'block',
        'pending',
        'height',
        'frontier',
        'block',
        'pillar',
      ]);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('unconfirmed hash cannot use matching registry data', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      confirmCachedOriginal();
      blockRead = () async => observed(confirmed: false);
      pendingRead = () async => AccountBlockList(
        list: <AccountBlock>[observed(confirmed: false)],
      );
      heightRead = () async => AccountBlockList(
        list: <AccountBlock>[observed(confirmed: false)],
      );
      final PillarInfo matching = info();
      pillarRead = () async => matching;
      final DevnetPillarFailure failure = await _refusal(
        attempt(tester, observer, 'pillar'),
      );
      expect(failure.code, DevnetPillarFailureCode.unresolved);
      expect(observer.diagnostics['pendingSeen'], isTrue);
      expect(observer.diagnostics['heightSeen'], isTrue);
      expect(observer.diagnostics['frontierAdvanced'], isTrue);
      expect(calls.where((String kind) => kind == 'pillar'), isEmpty);
      final int count = calls.length;
      expect(
        await _refusal(observer.readPillar(tester)),
        same(failure),
      );
      staysRefused(observer, failure, count);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final String field in <String>[
    'confirmations',
    'height',
    'timestamp',
    'hash',
  ]) {
    testWidgets('invalid confirmation $field cannot admit an effect read', (
      WidgetTester tester,
    ) async {
      try {
        final DevnetPillarObservation observer = await publish(tester);
        blockRead = () async {
          final AccountBlock block = observed();
          final AccountBlockConfirmationDetail detail =
              block.confirmationDetail!;
          if (field == 'confirmations') detail.numConfirmations = 0;
          if (field == 'height') detail.momentumHeight = 0;
          if (field == 'timestamp') detail.momentumTimestamp = 0;
          if (field == 'hash') detail.momentumHash = emptyHash;
          return block;
        };
        final DevnetPillarFailure failure = await _refusal(
          attempt(tester, observer, 'pillar'),
        );
        expect(failure.code, DevnetPillarFailureCode.unresolved);
        expect(calls.where((String kind) => kind == 'pillar'), isEmpty);
        expect(
          queriedHashes.every((Hash hash) => hash == published.single.hash),
          isTrue,
        );
        staysRefused(observer, failure, calls.length);
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  testWidgets('late positive confirmation cannot revive a timed out read', (
    WidgetTester tester,
  ) async {
    final Completer<AccountBlock?> held = Completer<AccountBlock?>();
    try {
      final DevnetPillarObservation observer = await publish(tester);
      int reads = 0;
      blockRead = () {
        reads++;
        return reads == 1
            ? Future<AccountBlock?>.value(observed(confirmed: false))
            : held.future;
      };
      final DevnetPillarFailure failure = await _refusal(
        attempt(tester, observer, 'pillar'),
      );
      expect(failure.code, DevnetPillarFailureCode.deadline);
      expect(reads, 2);
      final int count = calls.length;
      final DevnetPillarRead original = observer.originalReads.last;
      expect(original.kind, 'block');
      expect(original.original, same(held.future));
      expect(original.completed, isFalse);
      final AccountBlock confirmed = observed();
      held.complete(confirmed);
      for (int turn = 0; turn < 10 && !original.completed; turn++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(original.completed, isTrue);
      expect(original.value, same(confirmed));
      expect(original.error, isNull);
      confirmCachedOriginal();
      expect(
        await _refusal(observer.readPillar(tester)),
        same(failure),
      );
      expect(calls.where((String kind) => kind == 'pillar'), isEmpty);
      staysRefused(observer, failure, count);
    } finally {
      if (!held.isCompleted) held.completeError(StateError('Fixture closed'));
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a copied Done result cannot replace the original', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(
        tester,
        retain: false,
      );
      expect(
        () => observer.retain(
          AccountBlockTemplate.fromJson(published.single.toJson()),
        ),
        throwsA(isA<DevnetPillarFailure>()),
      );
      expect(calls, isEmpty);
      expect(
        () => observer.retain(published.single),
        throwsA(isA<DevnetPillarFailure>()),
      );
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final String mismatch in <String>['hash', 'chain', 'owner']) {
    testWidgets('wrong original $mismatch refuses before effect reads', (
      WidgetTester tester,
    ) async {
      try {
        final DevnetPillarObservation observer = await publish(tester);
        blockRead = () async => observed(
          hash: mismatch == 'hash' ? Hash.parse('ef' * 32) : null,
          chain: mismatch == 'chain' ? 321 : null,
          address: mismatch == 'owner' ? other : null,
        );
        final DevnetPillarFailure failure = await _refusal(
          attempt(tester, observer, 'block'),
        );
        expect(failure.code, DevnetPillarFailureCode.observationMismatch);
        staysRefused(observer, failure, 1);
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  for (final bool pending in <bool>[false, true]) {
    testWidgets('missing hash remains unresolved with pending $pending', (
      WidgetTester tester,
    ) async {
      try {
        final DevnetPillarObservation observer = await publish(tester);
        blockRead = () async => null;
        pendingRead = () async => AccountBlockList(
          list: pending
              ? <AccountBlock>[observed(confirmed: false)]
              : <AccountBlock>[],
        );
        heightRead = () async => AccountBlockList(
          list: <AccountBlock>[
            observed(hash: pending ? null : Hash.parse('ef' * 32)),
          ],
        );
        final DevnetPillarFailure failure = await _refusal(
          attempt(tester, observer, 'block'),
        );
        expect(failure.code, DevnetPillarFailureCode.unresolved);
        expect(observer.diagnostics['pendingSeen'], pending);
        expect(observer.diagnostics['heightSeen'], pending);
        expect(observer.diagnostics['heightConflict'], !pending);
        expect(observer.diagnostics['frontierAdvanced'], isTrue);
        expect(calls.where((String kind) => kind == 'pillar'), isEmpty);
        staysRefused(observer, failure, calls.length);
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  for (final String kind in kinds) {
    testWidgets('original $kind SDK error identity is retained', (
      WidgetTester tester,
    ) async {
      try {
        final DevnetPillarObservation observer = await publish(tester);
        prepare(kind);
        final StateError error = StateError('Offline SDK read failed');
        inject(kind, () => Future<Object?>.error(error));
        final DevnetPillarFailure failure = await _refusal(
          attempt(tester, observer, kind),
        );
        expect(failure.code, DevnetPillarFailureCode.readFailed);
        expect(failure.originalError, same(error));
        expect(failure.toString(), isNot(contains('Offline SDK read failed')));
        final DevnetPillarRead evidence = observer.originalReads.last;
        expect(evidence.original, same(injectedOriginal));
        expect(evidence.error, same(error));
        expect(evidence.stackTrace, isNotNull);
        staysRefused(observer, failure, calls.length);
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    for (final bool lateError in <bool>[false, true]) {
      testWidgets('stalled $kind retains late error $lateError once', (
        WidgetTester tester,
      ) async {
        final Completer<Object?> held = Completer<Object?>();
        try {
          final DevnetPillarObservation observer = await publish(tester);
          prepare(kind);
          inject(kind, () => held.future);
          final DevnetPillarFailure failure = await _refusal(
            attempt(tester, observer, kind),
          );
          expect(failure.code, DevnetPillarFailureCode.deadline);
          final int count = calls.length;
          final DevnetPillarRead evidence = observer.originalReads.last;
          expect(evidence.original, same(injectedOriginal));
          expect(evidence.completed, isFalse);
          final StateError error = StateError('Late offline SDK error');
          final Object value = valueFor(kind);
          if (lateError) {
            held.completeError(error);
          } else {
            held.complete(value);
          }
          for (int turn = 0; turn < 10 && !evidence.completed; turn++) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump();
          }
          expect(evidence.completed, isTrue);
          expect(evidence.error, lateError ? same(error) : isNull);
          expect(evidence.value, lateError ? isNull : same(value));
          staysRefused(observer, failure, count);
        } finally {
          if (!held.isCompleted) {
            held.completeError(StateError('Fixture closed'));
          }
          await closeOwned(tester);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));
    }

    testWidgets('$kind context loss cannot revive after restoration', (
      WidgetTester tester,
    ) async {
      try {
        final DevnetPillarObservation observer = await publish(tester);
        prepare(kind);
        inject(kind, () {
          kSelectedAddress = other;
          return Future<Object?>.value(valueFor(kind));
        });
        final DevnetPillarFailure failure = await _refusal(
          attempt(tester, observer, kind),
        );
        expect(failure.code, DevnetPillarFailureCode.contextChanged);
        kSelectedAddress = owner;
        staysRefused(observer, failure, calls.length);
      } finally {
        kSelectedAddress = owner;
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  testWidgets('a second observation cannot start more reads', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      await observer.readBlock(tester);
      final DevnetPillarFailure failure = await _refusal(
        observer.readBlock(tester),
      );
      expect(failure.code, DevnetPillarFailureCode.alreadyAttempted);
      staysRefused(observer, failure, 1);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('mutating an original cannot replace its frozen identity', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      final Hash hash = published.single.hash;
      published.single.hash = emptyHash;
      expect(observer.requireCurrent, throwsA(isA<DevnetPillarFailure>()));
      published.single.hash = hash;
      expect(observer.requireCurrent, throwsA(isA<DevnetPillarFailure>()));
      expect(calls, isEmpty);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('original host sender closure permanently refuses observation', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _finish(tester, sender.close());
      expect(observer.requireCurrent, throwsA(isA<DevnetPillarFailure>()));
      expect(calls, isEmpty);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('an unrelated original lane result is never adopted', (
    WidgetTester tester,
  ) async {
    try {
      final DevnetPillarObservation observer = await publish(tester);
      await OriginalPublications.runForOwners<AccountBlockTemplate>(
        <Object>[file, node],
        (OriginalPublication<AccountBlockTemplate> _) async => published.single,
      );
      expect(observer.requireCurrent, throwsA(isA<DevnetPillarFailure>()));
      expect(calls, isEmpty);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
