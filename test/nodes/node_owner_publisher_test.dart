import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_owner_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

class _Address extends Fake implements Address {}

class _Context extends Mock implements WalletActionContext {}

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(_Address());
    registerFallbackValue(() => true);
  });
  late _Blocks blocks;
  late SendTransactionBloc sender;
  late _Context context;
  late bool current;
  late int publications;
  late Future<bool> Function() verifyOwner;
  late Future<AccountBlockTemplate> Function(AccountBlockTemplate) publish;
  late NodeOwnerPublisher publisher;
  final String owner = emptyAddress.toString();

  setUp(() {
    blocks = _Blocks();
    final _Balances balances = _Balances();
    when(balances.refreshBalance).thenAnswer((_) {});
    current = true;
    publications = 0;
    context = _Context();
    when(() => context.ownerAddress).thenReturn(owner);
    when(() => context.isCurrent).thenAnswer((_) => current);
    when(context.requireCurrent).thenAnswer((_) {
      if (!current) throw FailureException();
    });
    verifyOwner = () async => true;
    publish = (AccountBlockTemplate block) async => block;
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        canPublish: any(named: 'canPublish'),
      ),
    ).thenAnswer((Invocation call) {
      publications++;
      expect((call.namedArguments[#address] as Address).toString(), owner);
      return publish(call.positionalArguments.first as AccountBlockTemplate);
    });
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
    );
    publisher = NodeOwnerPublisher(
      sender: sender,
      context: context,
      verifyOwner: () => verifyOwner(),
    );
  });
  tearDown(() => sender.close());

  Future<AccountBlockTemplate> start([AccountBlockTemplate? block]) =>
      publisher.createAccountBlock(
        block ?? AccountBlockTemplate(blockType: 1),
        'Owner action',
        address: emptyAddress,
        waitForRequiredPlasma: true,
      );

  test('fresh verification holds all shared sender admission', () async {
    final Completer<bool> verified = Completer<bool>();
    verifyOwner = () => verified.future;
    final Future<AccountBlockTemplate> result = start();
    expect(sender.busy.value, isTrue);
    expect(sender.tryReserve(Object()), isFalse);
    expect(publications, 0);
    verified.complete(true);
    await result;
    expect(publications, 1);
    expect(sender.busy.value, isFalse);
    expect(sender.state.origin, SendTransactionOrigin.contract);
  });

  test('the encoded action is copied before verification yields', () async {
    final Completer<bool> verified = Completer<bool>();
    verifyOwner = () => verified.future;
    final AccountBlockTemplate original = AccountBlockTemplate(
      blockType: 1,
      amount: BigInt.from(7),
      data: List<int>.of(const <int>[1, 2]),
    );
    final Future<AccountBlockTemplate> result = start(original);
    original.amount = BigInt.from(999);
    original.data[0] = 9;
    publish = (AccountBlockTemplate block) async {
      expect(block, isNot(same(original)));
      expect(block.amount, BigInt.from(7));
      expect(block.data, <int>[1, 2]);
      return block;
    };
    verified.complete(true);
    await result;
  });

  test(
    'revocation while verification waits refuses before transport',
    () async {
      final Completer<bool> verified = Completer<bool>();
      verifyOwner = () => verified.future;
      final Future<AccountBlockTemplate> result = start();
      final Future<void> refused = expectLater(
        result,
        throwsA(isA<FailureException>()),
      );
      current = false;
      verified.complete(true);
      await refused;
      expect(publications, 0);
      expect(sender.busy.value, isFalse);
    },
  );

  test(
    'a synchronous busy observer cannot rewrite the encoded action',
    () async {
      final AccountBlockTemplate original = AccountBlockTemplate(
        blockType: 1,
        amount: BigInt.from(7),
        data: List<int>.of(const <int>[1, 2]),
      );
      sender.busy.addListener(() {
        if (sender.busy.value) {
          original.amount = BigInt.from(999);
          original.data[0] = 9;
        }
      });
      publish = (AccountBlockTemplate block) async {
        expect(block.amount, BigInt.from(7));
        expect(block.data, <int>[1, 2]);
        return block;
      };
      await start(original);
      expect(publications, 1);
    },
  );

  test('a refused or throwing fresh proof releases its reservation', () async {
    verifyOwner = () async => false;
    await expectLater(start(), throwsA(isA<FailureException>()));
    expect(publications, 0);
    expect(sender.busy.value, isFalse);
    verifyOwner = () async => throw StateError('read failed');
    await expectLater(start(), throwsStateError);
    expect(publications, 0);
    expect(sender.busy.value, isFalse);
  });

  test('a different requested account never verifies or publishes', () async {
    int checks = 0;
    verifyOwner = () async {
      checks++;
      return true;
    };
    final Address other = kZnnCoin.owner;
    await expectLater(
      publisher.createAccountBlock(
        AccountBlockTemplate(blockType: 1),
        'Owner action',
        address: other,
      ),
      throwsA(isA<FailureException>()),
    );
    expect(checks, 0);
    expect(publications, 0);
    expect(sender.busy.value, isFalse);
  });

  test('queued dispatch checks context after reservation listeners', () async {
    sender.busy.addListener(() {
      if (sender.busy.value) current = false;
    });
    await expectLater(start(), throwsA(isA<FailureException>()));
    expect(publications, 0);
    expect(sender.busy.value, isFalse);
  });

  test(
    'an original accepted result survives revocation and sender close',
    () async {
      final Completer<void> began = Completer<void>();
      final Completer<AccountBlockTemplate> reply =
          Completer<AccountBlockTemplate>();
      publish = (_) {
        began.complete();
        return reply.future;
      };
      final Future<AccountBlockTemplate> result = start();
      await began.future;
      current = false;
      final Future<void> closed = sender.close();
      final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1)
        ..hash = Hash.parse('7' * 64);
      reply.complete(accepted);
      expect(await result, same(accepted));
      expect(publisher.lastResult!.block, same(accepted));
      await closed;
      expect(publications, 1);
    },
  );

  test(
    'the exact original failure remains retained beside its mapped UI error',
    () async {
      final StateError original = StateError('transport outcome unavailable');
      publish = (_) async => throw original;
      await expectLater(start(), throwsA(isA<FailureException>()));
      expect(publisher.lastResult!.error, same(original));
      expect(publications, 1);
      expect(sender.busy.value, isFalse);
    },
  );
}
