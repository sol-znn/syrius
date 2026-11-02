import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

class _Context extends Mock implements WalletActionContext {}

void main() {
  initHydratedStorage();
  final String owner = emptyAddress.toString();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(emptyAddress);
    registerFallbackValue(() => true);
  });
  late _Blocks blocks;
  late SendTransactionBloc sender;
  late _Context context;
  late RegistrationConfirmation confirmation;
  late WalletFlightRegistry registry;
  late RegistrationPublisher publisher;
  late bool current;
  late List<AccountBlockTemplate> submitted;
  late Future<AccountBlockTemplate> Function(AccountBlockTemplate) publish;

  AccountBlockTemplate draft() => AccountBlockTemplate(
    blockType: BlockTypeEnum.userSend.index,
    data: List<int>.of(const <int>[1, 2]),
    amount: BigInt.from(7),
  )..chainIdentifier = 321;

  AccountBlockTemplate publicationFor(AccountBlockTemplate block) =>
      AccountBlockTemplate.fromJson(block.toJson())
        ..address = Address.parse(owner)
        ..hash = Hash.parse(List<String>.filled(64, '9').join());

  setUp(() {
    current = true;
    submitted = <AccountBlockTemplate>[];
    blocks = _Blocks();
    final _Balances balances = _Balances();
    when(balances.refreshBalance).thenAnswer((_) {});
    context = _Context();
    when(() => context.ownerAddress).thenReturn(owner);
    when(() => context.isCurrent).thenAnswer((_) => current);
    registry = WalletFlightRegistry(
      currentChainId: () => 321,
      lookup: (_, _) async => false,
    );
    confirmation = RegistrationConfirmation(
      context: context,
      chainId: 321,
      walletAddresses: <String>[owner],
      registry: registry,
    );
    publish = (AccountBlockTemplate block) async => publicationFor(block);
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        canPublish: any(named: 'canPublish'),
      ),
    ).thenAnswer((Invocation call) {
      final AccountBlockTemplate block =
          call.positionalArguments.first as AccountBlockTemplate;
      submitted.add(block);
      return publish(block);
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

  tearDown(() async {
    await sender.close();
    confirmation.dispose();
    registry.dispose();
  });

  Future<AccountBlockTemplate> start([AccountBlockTemplate? block]) =>
      publisher.createAccountBlock(
        block ?? draft(),
        'Registration',
        waitForRequiredPlasma: true,
      );

  test(
    'registration shares admission with every existing sender surface',
    () async {
      final Completer<AccountBlockTemplate> accepted =
          Completer<AccountBlockTemplate>();
      final Completer<void> started = Completer<void>();
      publish = (_) {
        started.complete();
        return accepted.future;
      };
      final Future<AccountBlockTemplate> original = start();
      final Future<void> settled = original.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        await started.future.timeout(const Duration(seconds: 1));
        expect(sender.busy.value, isTrue);
        expect(sender.tryReserve(Object()), isFalse);
        await expectLater(start(), throwsA(isA<FailureException>()));
        final AccountBlockTemplate response = publicationFor(draft());
        accepted.complete(response);
        expect(await original, same(response));
        expect(publisher.lastResult!.block, same(response));
        expect(submitted, hasLength(1));
        expect(sender.busy.value, isFalse);
      } finally {
        // Complete only this test's owned operation before sender teardown.
        if (!accepted.isCompleted) accepted.complete(publicationFor(draft()));
        await settled.timeout(const Duration(seconds: 1));
      }
    },
  );

  test('a busy observer cannot rewrite the already captured action', () async {
    final AccountBlockTemplate original = draft();
    sender.busy.addListener(() {
      if (sender.busy.value) {
        original.amount = BigInt.from(99);
        original.data[0] = 9;
      }
    });
    await start(original);
    expect(submitted.single.amount, BigInt.from(7));
    expect(submitted.single.data, <int>[1, 2]);
    expect(submitted.single, isNot(same(original)));
  });

  test(
    'context revocation before queued transport refuses publication',
    () async {
      final Future<AccountBlockTemplate> original = start();
      current = false;
      await expectLater(
        original,
        throwsA(
          isA<StateError>()
              .having(
                (StateError error) =>
                    identical(error, publisher.lastResult!.error),
                'retained original error',
                isTrue,
              )
              .having(
                (StateError error) => error.message,
                'message',
                'Publication context changed before dispatch',
              ),
        ),
      );
      expect(submitted, isEmpty);
      expect(sender.busy.value, isFalse);
    },
  );

  test(
    'a late original result survives context revocation without retry',
    () async {
      final Completer<AccountBlockTemplate> accepted =
          Completer<AccountBlockTemplate>();
      final Completer<void> started = Completer<void>();
      publish = (_) {
        started.complete();
        return accepted.future;
      };
      final Future<AccountBlockTemplate> original = start();
      final Future<void> settled = original.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        await started.future.timeout(const Duration(seconds: 1));
        current = false;
        final AccountBlockTemplate response = publicationFor(draft());
        accepted.complete(response);
        expect(await original, same(response));
        expect(publisher.lastResult!.block, same(response));
        expect(submitted, hasLength(1));
        expect(confirmation.isCurrent, isFalse);
      } finally {
        if (!accepted.isCompleted) accepted.complete(publicationFor(draft()));
        await settled.timeout(const Duration(seconds: 1));
      }
    },
  );

  test(
    'the original sender failure survives without an automatic retry',
    () async {
      final FailureException failure = FailureException(
        message: 'Original refusal',
      );
      publish = (_) async => throw failure;
      await expectLater(start(), throwsA(same(failure)));
      expect(publisher.lastResult!.error, same(failure));
      expect(submitted, hasLength(1));
    },
  );

  test(
    'an accepted waiting registration refuses a second publication',
    () async {
      final AccountBlockTemplate response = await start();
      response
        ..hash = Hash.parse(List<String>.filled(64, '9').join())
        ..address = Address.parse(owner);
      confirmation.accept(RegistrationPublication(accountBlock: response));
      await confirmation.check();
      expect(confirmation.isConfirmed, isFalse);
      await expectLater(start(), throwsA(isA<FailureException>()));
      expect(publisher.lastResult!.block, same(response));
      expect(submitted, hasLength(1));
    },
  );

  test(
    'a different chain or requested account cannot borrow this owner',
    () async {
      await expectLater(
        start(draft()..chainIdentifier = 1),
        throwsA(isA<FailureException>()),
      );
      await expectLater(
        publisher.createAccountBlock(
          draft(),
          'Registration',
          address: kZnnCoin.owner,
        ),
        throwsA(isA<FailureException>()),
      );
      expect(submitted, isEmpty);
    },
  );
}
