import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../integration_test/support/devnet_deposit_confirmation.dart';
import '../../integration_test/support/devnet_registration_host.dart';
import '../../integration_test/support/devnet_test_context.dart';
import '../helpers/hydrated_bloc.dart';

class _Node extends Mock implements Zenon {}

class _Ledger extends Mock implements LedgerApi {}

class _AccountInfo extends Mock implements AccountInfo {}

class _Stats extends Mock implements StatsApi {}

class _Socket extends Mock implements WsClient {}

class _Embedded extends Mock implements EmbeddedApi {}

class _Sentinel extends Mock implements SentinelApi {}

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
  expect(finished, isTrue, reason: 'The exact original future must finish');
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return value as T;
}

void main() {
  initHydratedStorage();
  const String owner = DevnetTestContext.testPillarOwnerAddress;
  final String other = DevnetTestContext.fundedDevAddresses[8]!;
  final List<String> addresses = <String>[owner, other];
  const String endpoint = 'ws://127.0.0.1:35998';
  late Zenon? previousNode;
  late _Node node;
  late _Ledger ledger;
  late _Stats stats;
  late _Socket socket;
  late _Embedded embedded;
  late _Sentinel sentinelApi;
  late _Wallet wallet;
  late _NoSignerFile file;
  late DevnetWalletBinding binding;
  late WalletFlightRegistry registry;
  late RegistrationConfirmation confirmation;
  late SendTransactionBloc sender;
  late RegistrationPublisher publisher;
  late List<AccountBlockTemplate> published;
  late List<Hash> reads;
  late Future<AccountBlock?> Function(Hash) read;
  late Future<BigInt> Function(Address) effectRead;
  late List<Address> effectReads;
  late AccountInfo accountInfo;
  late Future<AccountInfo> Function(Address) accountRead;
  late List<Address> accountReads;
  final List<DevnetDepositConfirmation> observers =
      <DevnetDepositConfirmation>[];

  AccountBlock observed(
    AccountBlockTemplate original, {
    int? chain,
    String? address,
    Hash? hash,
    bool confirmed = true,
  }) => AccountBlock.fromJson(<String, dynamic>{
    ...original.toJson(),
    'chainIdentifier': chain ?? original.chainIdentifier,
    'address': address ?? original.address.toString(),
    'hash': (hash ?? original.hash).toString(),
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

  setUpAll(() {
    registerFallbackValue(emptyHash);
    registerFallbackValue(emptyAddress);
    registerFallbackValue(
      AccountBlockTemplate(
        blockType: BlockTypeEnum.userSend.index,
      ),
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
    sentinelApi = _Sentinel();
    wallet = _Wallet();
    file = _NoSignerFile(wallet);
    when(() => node.ledger).thenReturn(ledger);
    when(() => node.stats).thenReturn(stats);
    when(() => node.wsClient).thenReturn(socket);
    when(() => node.embedded).thenReturn(embedded);
    when(() => embedded.sentinel).thenReturn(sentinelApi);
    when(() => sentinelApi.client).thenReturn(socket);
    when(() => ledger.client).thenReturn(socket);
    when(() => stats.client).thenReturn(socket);
    when(() => socket.url).thenReturn(endpoint);
    when(socket.isClosed).thenReturn(false);
    when(socket.status).thenReturn(WebsocketStatus.running);
    app.zenon = node;
    binding = DevnetWalletBinding.install(
      walletFile: file,
      addresses: addresses,
      selectedAddress: owner,
      nodeUrl: endpoint,
      verifiedChainId: DevnetTestContext.chainId,
    );
    published = <AccountBlockTemplate>[];
    reads = <Hash>[];
    effectReads = <Address>[];
    accountInfo = _AccountInfo();
    accountReads = <Address>[];
    accountRead = (_) async => accountInfo;
    when(() => ledger.getAccountInfoByAddress(any())).thenAnswer((
      Invocation call,
    ) {
      final Address owner = call.positionalArguments.single as Address;
      accountReads.add(owner);
      return accountRead(owner);
    });
    effectRead = (_) async => sentinelRegisterQsrAmount;
    when(() => sentinelApi.getDepositedQsr(any())).thenAnswer((
      Invocation call,
    ) {
      final Address owner = call.positionalArguments.single as Address;
      effectReads.add(owner);
      return effectRead(owner);
    });
    read = (_) async => observed(published.single);
    when(() => ledger.getAccountBlockByHash(any())).thenAnswer((
      Invocation call,
    ) {
      final Hash hash = call.positionalArguments.single as Hash;
      reads.add(hash);
      return read(hash);
    });
    registry = WalletFlightRegistry(
      currentChainId: getChainIdentifier,
      lookup: (int chain, Hash hash) async {
        final AccountBlock? block = await ledger.getAccountBlockByHash(hash);
        return block?.hash == hash &&
            block?.chainIdentifier == chain &&
            block?.confirmationDetail != null;
      },
    );
    confirmation = RegistrationConfirmation(
      context: WalletActionContext.capture(owner),
      chainId: DevnetTestContext.chainId,
      walletAddresses: addresses,
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
    ).thenAnswer((Invocation call) async {
      final AccountBlockTemplate input =
          call.positionalArguments.first as AccountBlockTemplate;
      final AccountBlockTemplate original =
          AccountBlockTemplate.fromJson(input.toJson())
            ..address = Address.parse(owner)
            ..height = published.length + 7
            ..hash = Hash.parse(
              (published.length + 1).toRadixString(16).padLeft(64, '0'),
            );
      published.add(original);
      registry.published(original, addresses);
      return original;
    });
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
    );
    publisher = RegistrationPublisher(
      sender: sender,
      confirmation: confirmation,
    );
    observers.clear();
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

  AccountBlockTemplate draft({bool sentinel = false}) => sentinel
      ? SentinelApi().depositQsr(BigInt.from(13))
      : PillarApi().depositQsr(BigInt.from(13));

  AccountBlockTemplate nextDraft([int marker = 9]) =>
      AccountBlockTemplate.callContract(
        pillarAddress,
        znnZts,
        BigInt.one,
        <int>[marker],
      );

  DevnetDepositConfirmation capture(AccountBlockTemplate expected) {
    final DevnetDepositConfirmation observer =
        DevnetDepositConfirmation.capture(
          sender: sender,
          ownerAddress: owner,
          expectedDeposit: expected,
          registry: registry,
        );
    observers.add(observer);
    return observer;
  }

  Future<AccountBlockTemplate> submit(AccountBlockTemplate block) =>
      publisher.createAccountBlock(block, 'Offline contract fixture');

  Future<void> closeOwned(WidgetTester tester) async {
    for (final DevnetDepositConfirmation observer in observers) {
      await observer.close(tester);
    }
    await _finish(tester, sender.close());
  }

  Future<void> refuseNext() async {
    await expectLater(
      submit(nextDraft()),
      throwsA(isA<FailureException>()),
    );
    expect(published, hasLength(1));
  }

  for (final bool sentinel in <bool>[false, true]) {
    testWidgets(
      'exact original confirmation admits one next contract action '
      'for ${sentinel ? 'sentinel' : 'pillar'}',
      (WidgetTester tester) async {
        try {
          final AccountBlockTemplate expected = draft(sentinel: sentinel);
          final DevnetDepositConfirmation observer = capture(expected);
          final AccountBlockTemplate original = await _finish(
            tester,
            submit(expected),
          );
          await refuseNext();
          await observer.confirm(
            tester,
            reportedBlock: sentinel ? null : original,
          );
          await observer.close(tester);
          observer.requireCurrent();
          expect(
            registry.forWallet(69, addresses).hasConfirmed(original.hash),
            isTrue,
          );
          expect(reads, isNotEmpty);
          expect(reads.every((Hash hash) => hash == original.hash), isTrue);
          final AccountBlockTemplate registration = sentinel
              ? SentinelApi().register()
              : PillarApi().register(
                  'offlinePillar',
                  Address.parse(owner),
                  Address.parse(owner),
                );
          final AccountBlockTemplate next = await _finish(
            tester,
            submit(registration),
          );
          expect(next.hash, isNot(original.hash));
          await expectLater(
            submit(nextDraft(8)),
            throwsA(isA<FailureException>()),
          );
          expect(published, hasLength(2));
        } finally {
          await closeOwned(tester);
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  testWidgets('a copied Pillar Done block cannot replace the original', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      final AccountBlockTemplate original = await _finish(
        tester,
        submit(expected),
      );
      await expectLater(
        observer.confirm(
          tester,
          reportedBlock: AccountBlockTemplate.fromJson(original.toJson()),
        ),
        throwsA(isA<DevnetDepositFailure>()),
      );
      expect(reads, isEmpty);
      await refuseNext();
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final String missing in <String>['null', 'unconfirmed']) {
    testWidgets('pending $missing evidence never admits registration', (
      WidgetTester tester,
    ) async {
      try {
        final AccountBlockTemplate expected = draft();
        final DevnetDepositConfirmation observer = capture(expected);
        final AccountBlockTemplate original = await _finish(
          tester,
          submit(expected),
        );
        read = (_) async =>
            missing == 'null' ? null : observed(original, confirmed: false);
        await expectLater(
          observer.confirm(tester, maxPolls: 1),
          throwsA(isA<DevnetDepositFailure>()),
        );
        expect(
          registry.forWallet(69, addresses).hasConfirmed(original.hash),
          isFalse,
        );
        await refuseNext();
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  for (final String mismatch in <String>['hash', 'chain', 'owner', 'amount']) {
    testWidgets('wrong $mismatch is refused before registry checking', (
      WidgetTester tester,
    ) async {
      try {
        final AccountBlockTemplate expected = draft();
        final DevnetDepositConfirmation observer = capture(expected);
        final AccountBlockTemplate original = await _finish(
          tester,
          submit(expected),
        );
        final AccountBlock wrong = observed(
          original,
          hash: mismatch == 'hash' ? Hash.parse('ef' * 32) : null,
          chain: mismatch == 'chain' ? 70 : null,
          address: mismatch == 'owner' ? other : null,
        );
        if (mismatch == 'amount') wrong.amount += BigInt.one;
        read = (_) async => wrong;
        await expectLater(
          observer.confirm(tester),
          throwsA(isA<DevnetDepositFailure>()),
        );
        expect(reads, hasLength(1));
        expect(
          registry.forWallet(69, addresses).hasConfirmed(original.hash),
          isFalse,
        );
        await refuseNext();
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  for (final String changed in <String>[
    'wallet',
    'selection',
    'signing chain',
    'node chain',
    'node',
    'transport',
    'socket',
    'lock',
    'transition',
    'round trip',
  ]) {
    testWidgets('original authority refuses $changed changes', (
      WidgetTester tester,
    ) async {
      NodeTransitionLease? transition;
      try {
        final AccountBlockTemplate expected = draft();
        final DevnetDepositConfirmation observer = capture(expected);
        final AccountBlockTemplate original = await _finish(
          tester,
          submit(expected),
        );
        read = (_) async {
          switch (changed) {
            case 'wallet':
              kWalletPath = 'other-fixture';
            case 'selection':
              kSelectedAddress = other;
            case 'signing chain':
              setChainIdentifier(chainIdentifier: 70);
            case 'node chain':
              kNodeChainId = 70;
            case 'node':
              kCurrentNode = 'ws://127.0.0.1:45998';
            case 'transport':
              when(() => ledger.client).thenReturn(_Socket());
            case 'socket':
              when(socket.isClosed).thenReturn(true);
            case 'lock':
              kCurrentPage = Tabs.lock;
            case 'transition':
              transition = NodeTransitions.begin();
            case 'round trip':
              WalletContextRevision.invalidate();
              WalletContextRevision.invalidate();
          }
          return observed(original);
        };
        await expectLater(
          observer.confirm(tester),
          throwsA(isA<DevnetDepositFailure>()),
        );
        expect(reads, hasLength(1));
        expect(published, hasLength(1));
        expect(observer.requireCurrent, throwsA(isA<DevnetDepositFailure>()));
      } finally {
        transition?.complete();
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  testWidgets('a late original read cannot resume a timed-out confirmation', (
    WidgetTester tester,
  ) async {
    final Completer<AccountBlock?> originalRead = Completer<AccountBlock?>();
    try {
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      final AccountBlockTemplate original = await _finish(
        tester,
        submit(expected),
      );
      read = (_) => originalRead.future;
      await expectLater(
        observer.confirm(
          tester,
          requestTimeout: const Duration(milliseconds: 200),
        ),
        throwsA(
          isA<DevnetDepositFailure>().having(
            (DevnetDepositFailure error) => error.code,
            'fixed reason',
            DevnetDepositFailureCode.deadline,
          ),
        ),
      );
      originalRead.complete(observed(original));
      await _finish(tester, originalRead.future);
      expect(reads, hasLength(1));
      expect(
        registry.forWallet(69, addresses).hasConfirmed(original.hash),
        isFalse,
      );
      expect(observer.requireCurrent, throwsA(isA<DevnetDepositFailure>()));
      await refuseNext();
    } finally {
      if (!originalRead.isCompleted) originalRead.complete(null);
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('read errors retain identity without rendering private details', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      await _finish(tester, submit(expected));
      final StateError original = StateError('private-fixture-diagnostic');
      read = (_) async => throw original;
      await expectLater(
        observer.confirm(tester),
        throwsA(
          isA<DevnetDepositFailure>()
              .having(
                (DevnetDepositFailure error) => error.originalError,
                'original error',
                same(original),
              )
              .having(
                (DevnetDepositFailure error) => error.toString(),
                'safe diagnostic',
                isNot(contains('private-fixture-diagnostic')),
              ),
        ),
      );
      expect(reads, hasLength(1));
      await refuseNext();
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a ledger response alone cannot replace registry confirmation', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      final AccountBlockTemplate original = await _finish(
        tester,
        submit(expected),
      );
      int requests = 0;
      read = (_) async => requests++ == 0 ? observed(original) : null;
      await expectLater(
        observer.confirm(tester, maxPolls: 1),
        throwsA(isA<DevnetDepositFailure>()),
      );
      expect(reads, hasLength(2));
      expect(
        registry.forWallet(69, addresses).hasConfirmed(original.hash),
        isFalse,
      );
      await refuseNext();
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('another sender request makes the original window ambiguous', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      await _finish(tester, submit(expected));
      final Object reservation = Object();
      expect(sender.tryReserve(reservation), isTrue);
      final SendRequestHandle? otherRequest = sender.trySubmitOwned(
        owner: reservation,
        requestId: Object(),
        block: draft(sentinel: true),
        fromAddress: owner,
        reasonForGeneratingPlasma: 'Offline competing request',
        origin: SendTransactionOrigin.contract,
      );
      expect(otherRequest, isNotNull);
      await _finish(tester, otherRequest!.result);
      sender.releaseReservation(reservation);
      await expectLater(
        observer.confirm(tester),
        throwsA(
          isA<DevnetDepositFailure>().having(
            (DevnetDepositFailure error) => error.code,
            'fixed reason',
            DevnetDepositFailureCode.originalAmbiguous,
          ),
        ),
      );
      expect(reads, isEmpty);
      expect(observer.requireCurrent, throwsA(isA<DevnetDepositFailure>()));
      expect(published, hasLength(2));
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  Future<AccountBlockTemplate> registerAfter(
    DevnetDepositConfirmation observer,
  ) async {
    observer.requireCurrent();
    return submit(SentinelApi().register());
  }

  testWidgets('a confirmed receipt refuses original host sender disposal', (
    WidgetTester tester,
  ) async {
    final _HostBalances balances = _HostBalances();
    try {
      await tester.pumpWidget(
        DevnetRegistrationHost(
          balances: balances,
          createSender: () => sender,
          child: const SizedBox(),
        ),
      );
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      final AccountBlockTemplate original = await _finish(
        tester,
        submit(expected),
      );
      await observer.confirm(tester, reportedBlock: original);
      await observer.close(tester);
      observer.requireCurrent();
      expect(confirmation.isCurrent, isTrue);
      expect(
        registry.forWallet(69, addresses).hasConfirmed(original.hash),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(sender.isClosed, isTrue);
      expect(confirmation.isCurrent, isTrue);
      expect(
        RegistrationPublisher.originalResultsFor(sender).last.block,
        same(original),
      );
      await expectLater(
        registerAfter(observer),
        throwsA(
          isA<DevnetDepositFailure>().having(
            (DevnetDepositFailure error) => error.code,
            'permanent original sender refusal',
            DevnetDepositFailureCode.closed,
          ),
        ),
      );
      expect(observer.requireCurrent, throwsA(isA<DevnetDepositFailure>()));
      expect(published, hasLength(1));
      verifyNever(balances.close);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('exact Sentinel effect permits one guarded next admission', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft(sentinel: true);
      final DevnetDepositConfirmation observer = capture(expected);
      await _finish(tester, submit(expected));
      await observer.confirm(tester);
      final BigInt originalAmount = await observer.waitForSentinelDeposit(
        tester,
      );
      expect(originalAmount, sentinelRegisterQsrAmount);
      expect(effectReads, <Address>[Address.parse(owner)]);
      await observer.close(tester);
      await _finish(tester, registerAfter(observer));
      expect(published, hasLength(2));
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final bool totalDeadline in <bool>[false, true]) {
    testWidgets(
      'stalled Sentinel effect permanently refuses '
      '${totalDeadline ? 'total deadline' : 'request deadline'}',
      (WidgetTester tester) async {
        final Completer<BigInt> originalRead = Completer<BigInt>();
        try {
          final AccountBlockTemplate expected = draft(sentinel: true);
          final DevnetDepositConfirmation observer = capture(expected);
          final AccountBlockTemplate original = await _finish(
            tester,
            submit(expected),
          );
          await observer.confirm(tester);
          effectRead = (_) => originalRead.future;
          DevnetDepositFailure? held;
          await expectLater(
            observer.waitForSentinelDeposit(
              tester,
              timeout: totalDeadline
                  ? const Duration(milliseconds: 300)
                  : const Duration(seconds: 90),
              requestTimeout: totalDeadline
                  ? const Duration(seconds: 5)
                  : const Duration(milliseconds: 200),
            ),
            throwsA(
              isA<DevnetDepositFailure>()
                  .having(
                    (DevnetDepositFailure error) => error.code,
                    'fixed deadline refusal',
                    DevnetDepositFailureCode.deadline,
                  )
                  .having(
                    (DevnetDepositFailure error) {
                      held = error;
                      return true;
                    },
                    'retained refusal',
                    isTrue,
                  ),
            ),
          );
          expect(effectReads, <Address>[Address.parse(owner)]);
          expect(
            registry.forWallet(69, addresses).hasConfirmed(original.hash),
            isTrue,
          );
          originalRead.complete(sentinelRegisterQsrAmount);
          await _finish(tester, originalRead.future);
          effectRead = (_) async => sentinelRegisterQsrAmount;
          await expectLater(
            observer.waitForSentinelDeposit(tester),
            throwsA(same(held)),
          );
          await expectLater(registerAfter(observer), throwsA(same(held)));
          expect(observer.requireCurrent, throwsA(same(held)));
          expect(effectReads, hasLength(1));
          expect(published, hasLength(1));
        } finally {
          if (!originalRead.isCompleted) originalRead.complete(BigInt.zero);
          await closeOwned(tester);
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  testWidgets('Sentinel guard failure is rethrown once and remains permanent', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft(sentinel: true);
      final DevnetDepositConfirmation observer = capture(expected);
      await _finish(tester, submit(expected));
      await observer.confirm(tester);
      final DevnetDepositFailure original = DevnetDepositFailure(
        DevnetDepositFailureCode.contextChanged,
        originalError: StateError('private-effect-fixture'),
      );
      effectRead = (_) async => throw original;
      await expectLater(
        observer.waitForSentinelDeposit(tester),
        throwsA(same(original)),
      );
      effectRead = (_) async => sentinelRegisterQsrAmount;
      await expectLater(
        observer.waitForSentinelDeposit(tester),
        throwsA(same(original)),
      );
      await expectLater(registerAfter(observer), throwsA(same(original)));
      expect(effectReads, hasLength(1));
      expect(published, hasLength(1));
      expect(original.toString(), isNot(contains('private-effect-fixture')));
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    'pending Sentinel amount cannot regain authority after its limit',
    (
      WidgetTester tester,
    ) async {
      try {
        final AccountBlockTemplate expected = draft(sentinel: true);
        final DevnetDepositConfirmation observer = capture(expected);
        await _finish(tester, submit(expected));
        await observer.confirm(tester);
        effectRead = (_) async => BigInt.zero;
        await expectLater(
          observer.waitForSentinelDeposit(tester, maxPolls: 2),
          throwsA(isA<DevnetDepositFailure>()),
        );
        effectRead = (_) async => sentinelRegisterQsrAmount;
        await expectLater(
          observer.waitForSentinelDeposit(tester),
          throwsA(isA<DevnetDepositFailure>()),
        );
        await expectLater(
          registerAfter(observer),
          throwsA(isA<DevnetDepositFailure>()),
        );
        expect(effectReads, hasLength(2));
        expect(published, hasLength(1));
      } finally {
        await closeOwned(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets('replaced Sentinel transport stays refused after restoration', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft(sentinel: true);
      final DevnetDepositConfirmation observer = capture(expected);
      await _finish(tester, submit(expected));
      await observer.confirm(tester);
      when(() => sentinelApi.client).thenReturn(_Socket());
      await expectLater(
        observer.waitForSentinelDeposit(tester),
        throwsA(isA<DevnetDepositFailure>()),
      );
      when(() => sentinelApi.client).thenReturn(socket);
      expect(observer.requireCurrent, throwsA(isA<DevnetDepositFailure>()));
      await expectLater(
        observer.waitForSentinelDeposit(tester),
        throwsA(isA<DevnetDepositFailure>()),
      );
      await expectLater(
        registerAfter(observer),
        throwsA(isA<DevnetDepositFailure>()),
      );
      expect(effectReads, isEmpty);
      expect(published, hasLength(1));
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a sender result outside the publisher journal is not adopted', (
    WidgetTester tester,
  ) async {
    try {
      final AccountBlockTemplate expected = draft();
      final DevnetDepositConfirmation observer = capture(expected);
      final Object reservation = Object();
      expect(sender.tryReserve(reservation), isTrue);
      final SendRequestHandle? original = sender.trySubmitOwned(
        owner: reservation,
        requestId: Object(),
        block: expected,
        fromAddress: owner,
        reasonForGeneratingPlasma: 'Offline unrelated request',
        origin: SendTransactionOrigin.contract,
      );
      expect(original, isNotNull);
      await _finish(tester, original!.result);
      sender.releaseReservation(reservation);
      await expectLater(
        observer.confirm(tester),
        throwsA(isA<DevnetDepositFailure>()),
      );
      expect(reads, isEmpty);
      expect(RegistrationPublisher.originalResultsFor(sender), isEmpty);
      expect(observer.requireCurrent, throwsA(isA<DevnetDepositFailure>()));
      expect(published, hasLength(1));
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  Future<DevnetDepositFailure> preflightFailure(Future<Object> original) async {
    try {
      await original;
    } on DevnetDepositFailure catch (error) {
      return error;
    }
    throw StateError('Expected permanent preflight refusal');
  }

  Future<AccountBlockTemplate> advanceAfterPreflight(
    DevnetSentinelPreflight preflight,
    List<String> actions,
  ) async {
    preflight.requireReady();
    actions.add('Next');
    preflight.requireReady();
    final AccountBlockTemplate result = await submit(SentinelApi().register());
    actions.add('Register');
    return result;
  }

  testWidgets('funded Sentinel preflight works before any host is mounted', (
    WidgetTester tester,
  ) async {
    final List<String> actions = <String>[];
    try {
      final DevnetSentinelPreflight preflight = DevnetSentinelPreflight.capture(
        owner,
      );
      final AccountInfo originalAccount = await preflight.readAccountInfo(
        tester,
      );
      final BigInt originalDeposit = await preflight.readDepositedQsr(tester);
      expect(originalAccount, same(accountInfo));
      expect(originalDeposit, sentinelRegisterQsrAmount);
      expect(accountReads, <Address>[Address.parse(owner)]);
      expect(effectReads, <Address>[Address.parse(owner)]);
      expect(published, isEmpty);
      await _finish(tester, advanceAfterPreflight(preflight, actions));
      expect(actions, <String>['Next', 'Register']);
      expect(published, hasLength(1));
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Sentinel preflight returns one original partial deposit', (
    WidgetTester tester,
  ) async {
    try {
      final BigInt originalAmount = BigInt.from(13);
      effectRead = (_) async => originalAmount;
      final DevnetSentinelPreflight preflight = DevnetSentinelPreflight.capture(
        owner,
      );
      await preflight.readAccountInfo(tester);
      expect(await preflight.readDepositedQsr(tester), same(originalAmount));
      preflight.requireReady();
      expect(accountReads, hasLength(1));
      expect(effectReads, hasLength(1));
      expect(published, isEmpty);
    } finally {
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final bool accountStage in <bool>[true, false]) {
    for (final String lateOutcome in <String>['success', 'error']) {
      final String stage = accountStage ? 'account' : 'deposit';
      testWidgets(
        'stalled Sentinel $stage preflight retains late $lateOutcome',
        (WidgetTester tester) async {
          final Completer<AccountInfo> accountOriginal =
              Completer<AccountInfo>();
          final Completer<BigInt> depositOriginal = Completer<BigInt>();
          final List<String> actions = <String>[];
          try {
            final DevnetSentinelPreflight preflight =
                DevnetSentinelPreflight.capture(owner);
            if (accountStage) {
              accountRead = (_) => accountOriginal.future;
            } else {
              await preflight.readAccountInfo(tester);
              effectRead = (_) => depositOriginal.future;
            }
            final Future<Object> original = accountStage
                ? preflight.readAccountInfo(
                    tester,
                    timeout: const Duration(milliseconds: 200),
                  )
                : preflight.readDepositedQsr(
                    tester,
                    timeout: const Duration(milliseconds: 200),
                  );
            final DevnetDepositFailure held = await preflightFailure(original);
            expect(held.code, DevnetDepositFailureCode.deadline);
            final StateError lateError = StateError('private-preflight-late');
            if (accountStage) {
              if (lateOutcome == 'error') {
                accountOriginal.completeError(lateError);
                await expectLater(
                  _finish(tester, accountOriginal.future),
                  throwsA(same(lateError)),
                );
              } else {
                accountOriginal.complete(accountInfo);
                expect(
                  await _finish(tester, accountOriginal.future),
                  same(accountInfo),
                );
              }
            } else if (lateOutcome == 'error') {
              depositOriginal.completeError(lateError);
              await expectLater(
                _finish(tester, depositOriginal.future),
                throwsA(same(lateError)),
              );
            } else {
              depositOriginal.complete(sentinelRegisterQsrAmount);
              expect(
                await _finish(tester, depositOriginal.future),
                sentinelRegisterQsrAmount,
              );
            }
            expect(preflight.requireReady, throwsA(same(held)));
            await expectLater(
              preflight.readAccountInfo(tester),
              throwsA(same(held)),
            );
            await expectLater(
              preflight.readDepositedQsr(tester),
              throwsA(same(held)),
            );
            await expectLater(
              advanceAfterPreflight(preflight, actions),
              throwsA(same(held)),
            );
            expect(accountReads, hasLength(1));
            expect(effectReads, hasLength(accountStage ? 0 : 1));
            expect(actions, isEmpty);
            expect(published, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            if (!accountOriginal.isCompleted) {
              accountOriginal.complete(accountInfo);
            }
            if (!depositOriginal.isCompleted) {
              depositOriginal.complete(BigInt.zero);
            }
            await closeOwned(tester);
          }
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }

  for (final bool accountStage in <bool>[true, false]) {
    for (final bool typedFailure in <bool>[false, true]) {
      final String stage = accountStage ? 'account' : 'deposit';
      final String kind = typedFailure ? 'typed' : 'SDK';
      testWidgets(
        'Sentinel $stage preflight preserves original $kind error identity',
        (WidgetTester tester) async {
          final List<String> actions = <String>[];
          try {
            final Object original = typedFailure
                ? DevnetDepositFailure(
                    DevnetDepositFailureCode.readFailed,
                    originalError: StateError('private-preflight-error'),
                  )
                : StateError('private-preflight-error');
            final DevnetSentinelPreflight preflight =
                DevnetSentinelPreflight.capture(owner);
            if (accountStage) {
              accountRead = (_) => Future<AccountInfo>.error(original);
            } else {
              await preflight.readAccountInfo(tester);
              effectRead = (_) => Future<BigInt>.error(original);
            }
            final DevnetDepositFailure held = await preflightFailure(
              accountStage
                  ? preflight.readAccountInfo(tester)
                  : preflight.readDepositedQsr(tester),
            );
            if (typedFailure) {
              expect(held, same(original));
            } else {
              expect(held.originalError, same(original));
            }
            expect(held.toString(), isNot(contains('private-preflight-error')));
            expect(preflight.requireReady, throwsA(same(held)));
            await expectLater(
              preflight.readAccountInfo(tester),
              throwsA(same(held)),
            );
            await expectLater(
              preflight.readDepositedQsr(tester),
              throwsA(same(held)),
            );
            await expectLater(
              advanceAfterPreflight(preflight, actions),
              throwsA(same(held)),
            );
            expect(accountReads, hasLength(1));
            expect(effectReads, hasLength(accountStage ? 0 : 1));
            expect(actions, isEmpty);
            expect(published, isEmpty);
          } finally {
            await closeOwned(tester);
          }
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }

  testWidgets(
    'Sentinel preflight rejects transport loss before its first read',
    (
      WidgetTester tester,
    ) async {
      final List<String> actions = <String>[];
      try {
        final DevnetSentinelPreflight preflight =
            DevnetSentinelPreflight.capture(owner);
        when(() => ledger.client).thenReturn(_Socket());
        final DevnetDepositFailure held = await preflightFailure(
          preflight.readAccountInfo(tester),
        );
        expect(held.code, DevnetDepositFailureCode.contextChanged);
        when(() => ledger.client).thenReturn(socket);
        expect(preflight.requireCurrent, throwsA(same(held)));
        await expectLater(
          preflight.readAccountInfo(tester),
          throwsA(same(held)),
        );
        await expectLater(
          advanceAfterPreflight(preflight, actions),
          throwsA(same(held)),
        );
        expect(accountReads, isEmpty);
        expect(effectReads, isEmpty);
        expect(actions, isEmpty);
        expect(published, isEmpty);
      } finally {
        await closeOwned(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets('an original account read cannot survive a wallet round trip', (
    WidgetTester tester,
  ) async {
    final Completer<AccountInfo> original = Completer<AccountInfo>();
    final List<String> actions = <String>[];
    try {
      final DevnetSentinelPreflight preflight = DevnetSentinelPreflight.capture(
        owner,
      );
      accountRead = (_) {
        WalletContextRevision.invalidate();
        WalletContextRevision.invalidate();
        return original.future;
      };
      final DevnetDepositFailure held = await preflightFailure(
        preflight.readAccountInfo(tester),
      );
      expect(held.code, DevnetDepositFailureCode.contextChanged);
      original.complete(accountInfo);
      await _finish(tester, original.future);
      expect(WalletActionContext.capture(owner)?.isCurrent, isTrue);
      expect(preflight.requireReady, throwsA(same(held)));
      await expectLater(
        advanceAfterPreflight(preflight, actions),
        throwsA(same(held)),
      );
      expect(accountReads, hasLength(1));
      expect(effectReads, isEmpty);
      expect(actions, isEmpty);
      expect(published, isEmpty);
    } finally {
      if (!original.isCompleted) original.complete(accountInfo);
      await closeOwned(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    'funded Sentinel preflight stays refused after chain restoration',
    (
      WidgetTester tester,
    ) async {
      final List<String> actions = <String>[];
      try {
        final DevnetSentinelPreflight preflight =
            DevnetSentinelPreflight.capture(owner);
        await preflight.readAccountInfo(tester);
        await preflight.readDepositedQsr(tester);
        preflight.requireReady();
        kNodeChainId = 70;
        DevnetDepositFailure? held;
        expect(
          preflight.requireReady,
          throwsA(
            isA<DevnetDepositFailure>().having(
              (DevnetDepositFailure error) {
                held = error;
                return error.code;
              },
              'original chain refusal',
              DevnetDepositFailureCode.contextChanged,
            ),
          ),
        );
        kNodeChainId = DevnetTestContext.chainId;
        await expectLater(
          advanceAfterPreflight(preflight, actions),
          throwsA(same(held)),
        );
        expect(preflight.requireReady, throwsA(same(held)));
        expect(accountReads, hasLength(1));
        expect(effectReads, hasLength(1));
        expect(actions, isEmpty);
        expect(published, isEmpty);
      } finally {
        await closeOwned(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  for (final bool repeatAccount in <bool>[true, false]) {
    final String stage = repeatAccount ? 'account' : 'deposit';
    testWidgets('successful Sentinel $stage preflight never invokes a retry', (
      WidgetTester tester,
    ) async {
      final List<String> actions = <String>[];
      try {
        final DevnetSentinelPreflight preflight =
            DevnetSentinelPreflight.capture(owner);
        await preflight.readAccountInfo(tester);
        if (!repeatAccount) await preflight.readDepositedQsr(tester);
        final DevnetDepositFailure held = await preflightFailure(
          repeatAccount
              ? preflight.readAccountInfo(tester)
              : preflight.readDepositedQsr(tester),
        );
        expect(held.code, DevnetDepositFailureCode.closed);
        await expectLater(
          advanceAfterPreflight(preflight, actions),
          throwsA(same(held)),
        );
        expect(preflight.requireReady, throwsA(same(held)));
        expect(accountReads, hasLength(1));
        expect(effectReads, hasLength(repeatAccount ? 0 : 1));
        expect(actions, isEmpty);
        expect(published, isEmpty);
      } finally {
        await closeOwned(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  testWidgets(
    'Sentinel deposit preflight requires the original account result',
    (
      WidgetTester tester,
    ) async {
      final List<String> actions = <String>[];
      try {
        final DevnetSentinelPreflight preflight =
            DevnetSentinelPreflight.capture(owner);
        final DevnetDepositFailure held = await preflightFailure(
          preflight.readDepositedQsr(tester),
        );
        expect(held.code, DevnetDepositFailureCode.originalMissing);
        await expectLater(
          preflight.readAccountInfo(tester),
          throwsA(same(held)),
        );
        await expectLater(
          advanceAfterPreflight(preflight, actions),
          throwsA(same(held)),
        );
        expect(accountReads, isEmpty);
        expect(effectReads, isEmpty);
        expect(actions, isEmpty);
        expect(published, isEmpty);
      } finally {
        await closeOwned(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
