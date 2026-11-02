import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_collect_button.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

class _Context extends Mock implements WalletActionContext {}

UncollectedReward _reward({
  String znn = '7',
  String qsr = '3',
  Address? owner,
}) => UncollectedReward.fromJson(<String, dynamic>{
  'address': (owner ?? emptyAddress).toString(),
  'znnAmount': znn,
  'qsrAmount': qsr,
});

AccountBlockTemplate _accepted() => AccountBlockTemplate(blockType: 1)
  ..address = emptyAddress
  ..chainIdentifier = 321
  ..hash = Hash.parse('7' * 64);

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(emptyAddress);
    registerFallbackValue(() => true);
  });

  late SendTransactionBloc sender;
  late InFlightBlocks flight;
  late NodeCollectionController controller;
  late _Context context;
  late bool current;
  late bool ownsRead;
  late bool visible;
  late int publications;
  late int reads;
  late Object ticket;
  late Future<UncollectedReward> Function() read;
  late Future<AccountBlockTemplate> Function(AccountBlockTemplate) publish;
  late AccountBlockTemplate template;
  final String address = emptyAddress.toString();

  setUp(() {
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
      publications++;
      final bool Function() guard =
          call.namedArguments[#canPublish]! as bool Function();
      if (!guard()) throw StateError('Preparation revoked');
      return publish(call.positionalArguments.first as AccountBlockTemplate);
    });
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
    );
    current = true;
    ownsRead = true;
    visible = true;
    publications = 0;
    reads = 0;
    ticket = Object();
    template = AccountBlockTemplate(blockType: 1, amount: BigInt.from(7));
    read = () async => _reward();
    publish = (_) async => _accepted();
    context = _Context();
    when(() => context.ownerAddress).thenReturn(address);
    when(() => context.isCurrent).thenAnswer((_) => current);
    flight = InFlightBlocks(lookup: (_) async => false);
    controller = NodeCollectionController(
      sender: sender,
      flight: flight,
      address: address,
      chainId: 321,
    );
  });

  tearDown(() async {
    await sender.close();
    controller.dispose();
    flight.dispose();
  });

  NodeCollectionSnapshot snapshot({Object? readTicket}) =>
      NodeCollectionSnapshot(
        ticket: readTicket ?? ticket,
        address: address,
        znn: BigInt.from(7),
        qsr: BigInt.from(3),
      );

  Future<SendRequestResult?> collect({NodeCollectionSnapshot? due}) =>
      controller.collect(
        snapshot: due ?? snapshot(),
        context: context,
        ownsRead: () => ownsRead,
        isCurrent: () => visible,
        freshRead: () {
          reads++;
          return read();
        },
        buildBlock: () => template,
        purpose: 'Collect rewards',
      );

  test(
    'fresh exact rewards reserve shared admission before publication',
    () async {
      final Completer<UncollectedReward> fresh = Completer<UncollectedReward>();
      read = () => fresh.future;
      final Future<SendRequestResult?> result = collect();
      expect(controller.busy, isTrue);
      expect(sender.busy.value, isTrue);
      expect(sender.tryReserve(Object()), isFalse);
      expect(publications, 0);
      fresh.complete(_reward());
      expect((await result)!.accepted, isTrue);
      expect(controller.attempt!.accepted, isTrue);
      expect(controller.attempt!.hash, _accepted().hash);
      expect(sender.state.origin, SendTransactionOrigin.collection);
      expect(publications, 1);
      expect(reads, 1);
      expect(sender.busy.value, isFalse);
    },
  );

  test(
    'the original receipt hash survives mutable SDK response bytes',
    () async {
      final AccountBlockTemplate accepted = _accepted();
      publish = (_) async => accepted;
      final SendRequestResult? original = await collect();
      final Hash expected = Hash.parse('7' * 64);
      accepted.hash.hash[0] = 0;
      expect(original!.block, same(accepted));
      expect(controller.attempt!.hash, expected);
      expect(controller.attempt!.hash!.hash, isNot(accepted.hash.hash));
      final NodeCollectionSnapshot fresh = snapshot(readTicket: Object());
      flight.settle(accepted.hash);
      expect(controller.canCollect(fresh), isFalse);
      flight.settle(expected);
      expect(controller.canCollect(fresh), isTrue);
    },
  );

  for (final MapEntry<String, UncollectedReward> different
      in <String, UncollectedReward>{
        'ZNN': _reward(znn: '8'),
        'QSR': _reward(qsr: '4'),
        'negative': _reward(znn: '-1'),
        'foreign': _reward(owner: kZnnCoin.owner),
      }.entries) {
    test('${different.key} fresh amounts refuse before publication', () async {
      read = () async => different.value;
      expect(await collect(), isNull);
      expect(publications, 0);
      expect(controller.attempt, isNull);
      expect(controller.canCollect(snapshot()), isFalse);
      expect(sender.busy.value, isFalse);
    });
  }

  for (final String boundary in <String>['context', 'ticket', 'surface']) {
    test('$boundary revocation during the fresh read refuses', () async {
      final Completer<UncollectedReward> fresh = Completer<UncollectedReward>();
      read = () => fresh.future;
      final Future<SendRequestResult?> result = collect();
      if (boundary == 'context') current = false;
      if (boundary == 'ticket') ownsRead = false;
      if (boundary == 'surface') visible = false;
      fresh.complete(_reward());
      expect(await result, isNull);
      expect(publications, 0);
      expect(sender.busy.value, isFalse);
    });
  }

  test('the encoded operation precedes reentrant sender observers', () async {
    sender.busy.addListener(() {
      if (sender.busy.value) template.amount = BigInt.from(999);
    });
    publish = (AccountBlockTemplate block) async {
      expect(block.amount, BigInt.from(7));
      return _accepted();
    };
    await collect();
    expect(publications, 1);
  });

  test(
    'unrelated original results cannot mutate collection ownership',
    () async {
      final Object other = Object();
      expect(sender.tryReserve(other), isTrue);
      final SendRequestHandle handle = sender.trySubmitOwned(
        owner: other,
        requestId: Object(),
        block: template,
        fromAddress: address,
        reasonForGeneratingPlasma: 'Other owner action',
        origin: SendTransactionOrigin.contract,
        canPublish: () => true,
      )!;
      await handle.result;
      sender.releaseReservation(other);
      expect(controller.busy, isFalse);
      expect(controller.attempt, isNull);
      expect(controller.uncertain, isFalse);
      expect(flight.value, isEmpty);
      expect(controller.canCollect(snapshot()), isTrue);
    },
  );

  test(
    'reservation observers revoke before fresh reads or publication',
    () async {
      sender.busy.addListener(() {
        if (sender.busy.value) current = false;
      });
      expect(await collect(), isNull);
      expect(publications, 0);
      expect(reads, 0);
      expect(sender.busy.value, isFalse);
    },
  );

  test(
    'uncertain admitted failures retain their identity and block rearm',
    () async {
      final StateError error = StateError('Outcome unavailable');
      publish = (_) async => throw error;
      final SendRequestResult result = (await collect())!;
      expect(result.error, same(error));
      expect(controller.attempt!.result, same(result));
      expect(controller.uncertain, isTrue);
      final Object request = controller.attempt!.requestId;
      expect(await collect(due: snapshot(readTicket: Object())), isNull);
      expect(controller.attempt!.requestId, same(request));
      expect(publications, 1);
    },
  );

  test(
    'accepted rearm needs exact confirmation and a new read '
    'before verification',
    () async {
      await collect();
      final NodeCollectionSnapshot fresh = snapshot(readTicket: Object());
      expect(controller.canCollect(snapshot()), isFalse);
      expect(controller.canCollect(fresh), isFalse);
      flight.settle(Hash.parse('8' * 64));
      expect(controller.canCollect(fresh), isFalse);
      flight.settle(_accepted().hash);
      expect(controller.canCollect(snapshot()), isFalse);
      expect(controller.canCollect(fresh), isTrue);
      await collect(due: fresh);
      expect(reads, 2);
      expect(publications, 2);
    },
  );

  test(
    'a late original acceptance survives surface revocation and close',
    () async {
      final Completer<void> began = Completer<void>();
      final Completer<AccountBlockTemplate> reply =
          Completer<AccountBlockTemplate>();
      publish = (_) {
        began.complete();
        return reply.future;
      };
      final Future<SendRequestResult?> result = collect();
      await began.future;
      visible = false;
      current = false;
      final Future<void> closed = sender.close();
      final AccountBlockTemplate accepted = _accepted();
      reply.complete(accepted);
      expect((await result)!.block, same(accepted));
      expect(controller.attempt!.result.block, same(accepted));
      expect(controller.attempt!.hash, accepted.hash);
      await closed;
      expect(publications, 1);
    },
  );

  test(
    'a foreign returned block remains uncertain without flight evidence',
    () async {
      publish = (_) async => _accepted()..chainIdentifier = 1;
      await collect();
      expect(controller.uncertain, isTrue);
      expect(flight.value, isEmpty);
      expect(controller.canCollect(snapshot(readTicket: Object())), isFalse);
    },
  );

  test('retained ownership is shared only by the same source and account', () {
    final NodeCollectionController first = NodeCollectionController.retained(
      sender: sender,
      source: NodeRewardSource.pillar,
      flight: flight,
      address: address,
      chainId: 321,
    );
    expect(
      NodeCollectionController.retained(
        sender: sender,
        source: NodeRewardSource.pillar,
        flight: flight,
        address: address,
        chainId: 321,
      ),
      same(first),
    );
    expect(
      NodeCollectionController.retained(
        sender: sender,
        source: NodeRewardSource.sentinel,
        flight: flight,
        address: address,
        chainId: 321,
      ),
      isNot(same(first)),
    );
  });
}
