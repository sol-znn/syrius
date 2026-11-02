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
  late SendTransactionBloc sender;
  late RegistrationConfirmation confirmation;
  late RegistrationPublisher publisher;
  late WalletFlightRegistry registry;
  late _Context context;
  late bool confirmed;
  late int submissions;
  late Future<AccountBlockTemplate> Function(AccountBlockTemplate) publish;

  AccountBlockTemplate draft() => AccountBlockTemplate(
    blockType: BlockTypeEnum.userSend.index,
    data: List<int>.of(const <int>[1, 2]),
    amount: BigInt.from(7),
  )..chainIdentifier = 321;

  AccountBlockTemplate response(
    AccountBlockTemplate block, {
    String digit = '9',
  }) => AccountBlockTemplate.fromJson(block.toJson())
    ..address = emptyAddress
    ..hash = Hash.parse(List<String>.filled(64, digit).join());

  RegistrationConfirmation ownerConfirmation() => RegistrationConfirmation(
    context: context,
    chainId: 321,
    walletAddresses: <String>[owner],
    registry: registry,
  );

  Future<AccountBlockTemplate> start() => publisher.createAccountBlock(
    draft(),
    'Registration',
    waitForRequiredPlasma: true,
  );

  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(emptyAddress);
    registerFallbackValue(() => true);
  });

  setUp(() {
    confirmed = false;
    submissions = 0;
    context = _Context();
    when(() => context.ownerAddress).thenReturn(owner);
    when(() => context.isCurrent).thenReturn(true);
    registry = WalletFlightRegistry(
      currentChainId: () => 321,
      lookup: (_, _) async => confirmed,
    );
    confirmation = ownerConfirmation();
    final _Blocks blocks = _Blocks();
    final _Balances balances = _Balances();
    when(balances.refreshBalance).thenAnswer((_) {});
    publish = (AccountBlockTemplate block) async => response(block);
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        canPublish: any(named: 'canPublish'),
      ),
    ).thenAnswer((Invocation call) {
      submissions++;
      return publish(call.positionalArguments.first as AccountBlockTemplate);
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

  test(
    'an uncertain original is retained across retry and route replacement',
    () async {
      final StateError failure = StateError('Original publication uncertainty');
      publish = (_) async => throw failure;
      final Future<AccountBlockTemplate> original = start();
      await expectLater(original, throwsA(same(failure)));
      final SendRequestResult result = publisher.lastResult!;
      expect(result.error, same(failure));
      expect(publisher.isUncertain, isTrue);
      expect(publisher.canStartNewAttempt, isFalse);
      expect(start(), same(original));
      await expectLater(start(), throwsA(same(failure)));
      confirmation.dispose();
      confirmation = ownerConfirmation();
      publisher = RegistrationPublisher(
        sender: sender,
        confirmation: confirmation,
      );
      final Future<AccountBlockTemplate> reopened = start();
      expect(reopened, same(original));
      await expectLater(reopened, throwsA(same(failure)));
      expect(publisher.lastResult, same(result));
      expect(submissions, 1);
      expect(
        RegistrationPublisher.originalResultsFor(sender),
        <SendRequestResult>[result],
      );
    },
  );

  for (final bool uncertain in <bool>[false, true]) {
    test(
      'a changed draft cannot bypass an owner hold, uncertain=$uncertain',
      () async {
        final StateError failure = StateError(
          'Original publication uncertainty',
        );
        if (uncertain) publish = (_) async => throw failure;
        final Future<AccountBlockTemplate> original = start();
        if (uncertain) {
          await expectLater(original, throwsA(same(failure)));
        } else {
          await original;
        }
        final SendRequestResult result = publisher.lastResult!;
        final Matcher refusal = uncertain
            ? same(failure)
            : isA<FailureException>();
        Future<AccountBlockTemplate> changed() => publisher.createAccountBlock(
          draft()..data[0] = 8,
          'Registration',
          waitForRequiredPlasma: true,
        );
        await expectLater(changed(), throwsA(refusal));
        expect(publisher.lastResult, same(result));
        confirmation.dispose();
        confirmation = ownerConfirmation();
        publisher = RegistrationPublisher(
          sender: sender,
          confirmation: confirmation,
        );
        expect(publisher.canStartNewAttempt, isFalse);
        expect(publisher.isUncertain, uncertain);
        expect(publisher.lastResult, same(result));
        await expectLater(changed(), throwsA(refusal));
        expect(submissions, 1);
        expect(
          RegistrationPublisher.originalResultsFor(sender),
          <SendRequestResult>[result],
        );
      },
    );
  }

  test('a known busy refusal does not create an uncertain original', () async {
    final Object other = Object();
    expect(sender.tryReserve(other), isTrue);
    await expectLater(start(), throwsA(isA<FailureException>()));
    expect(publisher.isUncertain, isFalse);
    expect(publisher.canStartNewAttempt, isTrue);
    expect(submissions, 0);
    sender.releaseReservation(other);
    final AccountBlockTemplate accepted = await start();
    expect(accepted.hash, isNot(emptyHash));
    expect(submissions, 1);
  });

  test(
    'pending and accepted originals cannot be signed again on a new route',
    () async {
      final Completer<AccountBlockTemplate> pending =
          Completer<AccountBlockTemplate>();
      final Completer<AccountBlockTemplate> started =
          Completer<AccountBlockTemplate>();
      publish = (AccountBlockTemplate block) {
        started.complete(block);
        return pending.future;
      };
      final Future<AccountBlockTemplate> original = start();
      // Drain the owned deferred operation even if an assertion fails.
      final Future<void> settled = original.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        final AccountBlockTemplate block = await started.future.timeout(
          const Duration(seconds: 1),
        );
        await expectLater(start(), throwsA(isA<FailureException>()));
        await expectLater(
          publisher.createAccountBlock(draft()..data[0] = 8, 'Registration'),
          throwsA(isA<FailureException>()),
        );
        final AccountBlockTemplate accepted = response(block);
        pending.complete(accepted);
        expect(await original, same(accepted));
        confirmation.dispose();
        confirmation = ownerConfirmation();
        publisher = RegistrationPublisher(
          sender: sender,
          confirmation: confirmation,
        );
        final Future<AccountBlockTemplate> reopened = start();
        expect(reopened, same(original));
        expect(await reopened, same(accepted));
        expect(publisher.canStartNewAttempt, isFalse);
        expect(publisher.isUncertain, isFalse);
        expect(submissions, 1);
      } finally {
        if (!pending.isCompleted) pending.complete(response(draft()));
        await settled.timeout(const Duration(seconds: 1));
      }
    },
  );

  test(
    'positive exact confirmation permits the next explicit registration',
    () async {
      final AccountBlockTemplate first = await start();
      final SendRequestResult original = publisher.lastResult!;
      confirmed = true;
      confirmation.accept(RegistrationPublication(accountBlock: first));
      await confirmation.check();
      expect(confirmation.isConfirmed, isTrue);
      expect(
        confirmation.hasConfirmedOriginal(
          hash: first.hash.toString(),
          owner: owner,
          chainId: 1,
        ),
        isFalse,
      );
      expect(
        confirmation.hasConfirmedOriginal(
          hash: first.hash.toString(),
          owner: kZnnCoin.owner.toString(),
          chainId: 321,
        ),
        isFalse,
      );
      expect(confirmation.resetForAnother(), isTrue);
      expect(publisher.canStartNewAttempt, isTrue);
      publish = (AccountBlockTemplate block) async =>
          response(block, digit: '8');
      final AccountBlockTemplate second = await start();
      expect(second.hash, isNot(first.hash));
      expect(submissions, 2);
      final List<SendRequestResult> results =
          RegistrationPublisher.originalResultsFor(sender);
      expect(results, hasLength(2));
      expect(results.first, same(original));
      expect(results.first.block, same(first));
      expect(results.last.block, same(second));
    },
  );

  for (final String mismatch in <String>['owner', 'hash', 'payload']) {
    test(
      'a mismatched accepted $mismatch remains an original uncertain hold',
      () async {
        late AccountBlockTemplate returned;
        publish = (AccountBlockTemplate block) async {
          returned = response(block);
          switch (mismatch) {
            case 'owner':
              returned.address = kZnnCoin.owner;
            case 'hash':
              returned.hash = emptyHash;
            case 'payload':
              returned.data[0] = 9;
          }
          return returned;
        };
        final Future<AccountBlockTemplate> original = start();
        await expectLater(original, throwsA(isA<FailureException>()));
        expect(publisher.lastResult!.accepted, isTrue);
        expect(publisher.lastResult!.block, same(returned));
        expect(publisher.isUncertain, isTrue);
        expect(publisher.canStartNewAttempt, isFalse);
        expect(start(), same(original));
        await expectLater(start(), throwsA(isA<FailureException>()));
        expect(submissions, 1);
      },
    );
  }
}
