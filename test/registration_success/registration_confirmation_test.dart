import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Context extends Mock implements WalletActionContext {}

void main() {
  final String owner = emptyAddress.toString();
  final String anchor = kZnnCoin.owner.toString();
  final Hash originalHash = Hash.parse(List<String>.filled(64, '3').join());
  final Hash anotherHash = Hash.parse(List<String>.filled(64, '4').join());
  late _Context context;
  late bool current;
  late int chain;
  late WalletFlightRegistry registry;
  late RegistrationConfirmation confirmation;
  late List<(int, Hash)> requests;
  late List<Completer<bool>> replies;

  AccountBlockTemplate block({Hash? hash}) =>
      AccountBlockTemplate(
          blockType: BlockTypeEnum.userSend.index,
          amount: BigInt.from(15),
        )
        ..hash = hash ?? Hash.parse(originalHash.toString())
        ..address = Address.parse(owner)
        ..chainIdentifier = 321;

  setUp(() {
    current = true;
    chain = 321;
    context = _Context();
    when(() => context.ownerAddress).thenReturn(owner);
    when(() => context.isCurrent).thenAnswer((_) => current);
    requests = <(int, Hash)>[];
    replies = <Completer<bool>>[];
    registry = WalletFlightRegistry(
      currentChainId: () => chain,
      lookup: (int chainId, Hash hash) {
        requests.add((chainId, hash));
        final Completer<bool> reply = Completer<bool>();
        replies.add(reply);
        return reply.future;
      },
    );
    confirmation = RegistrationConfirmation(
      context: context,
      chainId: 321,
      walletAddresses: <String>[anchor, owner],
      registry: registry,
    );
  });

  tearDown(() async {
    final Future<void> pending = confirmation.check();
    for (final Completer<bool> reply in replies) {
      if (!reply.isCompleted) reply.complete(false);
    }
    await pending;
    confirmation.dispose();
    registry.dispose();
  });

  test('the exact original hash needs positive chain-bound evidence', () async {
    final AccountBlockTemplate accepted = block();
    final RegistrationPublication publication = RegistrationPublication(
      accountBlock: accepted,
      name: 'pillar',
    );
    expect(confirmation.accept(publication), isTrue);
    expect(confirmation.publication!.accountBlock, same(accepted));
    expect(confirmation.isConfirmed, isFalse);
    expect(requests, <(int, Hash)>[(321, originalHash)]);
    expect(confirmation.resetForAnother(), isFalse);
    replies.single.complete(true);
    await confirmation.check();
    expect(confirmation.isConfirmed, isTrue);
    expect(
      registry
          .forWallet(321, <String>[anchor, owner])
          .hasConfirmed(originalHash),
      isTrue,
    );
  });

  test('pending absence and another hash never confirm the original', () async {
    confirmation.accept(RegistrationPublication(accountBlock: block()));
    final InFlightBlocks flights =
        registry.forWallet(321, <String>[
            anchor,
            owner,
          ])
          ..sent(hash: anotherHash, amount: BigInt.zero)
          ..settle(anotherHash);
    expect(confirmation.isConfirmed, isFalse);
    flights.clear();
    replies.single.complete(true);
    await confirmation.check();
    expect(flights.value, isEmpty);
    expect(flights.hasConfirmed(originalHash), isFalse);
    expect(confirmation.isConfirmed, isFalse);
  });

  test(
    'a lookup error retains waiting and the original accepted result',
    () async {
      final AccountBlockTemplate accepted = block();
      confirmation.accept(RegistrationPublication(accountBlock: accepted));
      replies.single.completeError(StateError('unavailable'));
      await confirmation.check();
      expect(confirmation.isConfirmed, isFalse);
      expect(confirmation.publication!.accountBlock, same(accepted));
      expect(confirmation.resetForAnother(), isFalse);
      expect(requests, hasLength(1));
    },
  );

  test(
    'an already confirmed exact hash is retained without a second send',
    () async {
      final InFlightBlocks flights =
          registry.forWallet(321, <String>[
              anchor,
              owner,
            ])
            ..sent(hash: originalHash, amount: BigInt.one)
            ..settle(originalHash);
      confirmation.accept(RegistrationPublication(accountBlock: block()));
      await confirmation.check();
      expect(confirmation.isConfirmed, isTrue);
      expect(flights.value, isEmpty);
      expect(requests, isEmpty);
    },
  );

  test(
    'missing captured authority retains acceptance without lookup or art',
    () async {
      final RegistrationConfirmation unbound = RegistrationConfirmation(
        context: null,
        chainId: 321,
        walletAddresses: <String>[anchor, owner],
        registry: registry,
      );
      addTearDown(unbound.dispose);
      final AccountBlockTemplate accepted = block();
      unbound.accept(RegistrationPublication(accountBlock: accepted));
      await unbound.check();
      expect(unbound.publication!.accountBlock, same(accepted));
      expect(unbound.isConfirmed, isFalse);
      expect(requests, isEmpty);
    },
  );

  test('late confirmation cannot revive a departed context', () async {
    confirmation.accept(RegistrationPublication(accountBlock: block()));
    current = false;
    expect(confirmation.isCurrent, isFalse);
    replies.single.complete(true);
    await confirmation.check();
    current = true;
    expect(confirmation.isCurrent, isFalse);
    expect(confirmation.isConfirmed, isFalse);
    expect(confirmation.publication!.hash, originalHash);
  });

  test('a different chain refuses a late positive response', () async {
    confirmation.accept(RegistrationPublication(accountBlock: block()));
    chain = 1;
    replies.single.complete(true);
    await confirmation.check();
    expect(confirmation.isConfirmed, isFalse);
    expect(confirmation.publication!.chainId, 321);
    expect(requests, <(int, Hash)>[(321, originalHash)]);
  });

  test(
    'the shared revision synchronously revokes retained confirmation paint',
    () async {
      confirmation.accept(RegistrationPublication(accountBlock: block()));
      replies.single.complete(true);
      await confirmation.check();
      expect(confirmation.isConfirmed, isTrue);
      int changes = 0;
      confirmation.addListener(() => changes++);
      current = false;
      WalletContextRevision.invalidate();
      expect(changes, 1);
      expect(confirmation.isConfirmed, isFalse);
      current = true;
      expect(confirmation.isConfirmed, isFalse);
      expect(confirmation.publication!.hash, originalHash);
    },
  );

  for (final String mismatch in <String>['account', 'chain', 'empty hash']) {
    test(
      '$mismatch cannot borrow a confirmation from another identity',
      () async {
        final AccountBlockTemplate accepted = block();
        if (mismatch == 'account') accepted.address = Address.parse(anchor);
        if (mismatch == 'chain') accepted.chainIdentifier = 1;
        if (mismatch == 'empty hash') accepted.hash = emptyHash;
        confirmation.accept(RegistrationPublication(accountBlock: accepted));
        await confirmation.check();
        expect(confirmation.isConfirmed, isFalse);
        expect(requests, isEmpty);
        expect(confirmation.publication!.accountBlock, same(accepted));
      },
    );
  }

  test(
    'SDK mutations do not change the retained receipt or queried hash',
    () async {
      final AccountBlockTemplate accepted = block();
      final RegistrationPublication publication = RegistrationPublication(
        accountBlock: accepted,
        name: 'original',
        qsrCost: BigInt.from(7),
      );
      confirmation.accept(publication);
      accepted
        ..hash.getBytes()![0] = 255
        ..address = Address.parse(anchor)
        ..chainIdentifier = 1
        ..amount = BigInt.from(99);
      expect(
        () => publication.hash.getBytes()![1] = 255,
        throwsUnsupportedError,
      );
      expect(publication.hash, originalHash);
      expect(publication.ownerAddress, owner);
      expect(publication.chainId, 321);
      expect(publication.amount, BigInt.from(15));
      expect(publication.qsrCost, BigInt.from(7));
      expect(publication.name, 'original');
      replies.single.complete(true);
      await confirmation.check();
      expect(confirmation.isConfirmed, isTrue);
      expect(requests, <(int, Hash)>[(321, originalHash)]);
      expect(publication.accountBlock, same(accepted));
    },
  );

  test(
    'the first accepted result survives repeated completion callbacks',
    () async {
      final RegistrationPublication original = RegistrationPublication(
        accountBlock: block(),
      );
      confirmation.accept(original);
      expect(
        confirmation.accept(
          RegistrationPublication(accountBlock: block(hash: anotherHash)),
        ),
        isFalse,
      );
      expect(confirmation.publication, same(original));
      replies.single.complete(true);
      await confirmation.check();
      expect(confirmation.isConfirmed, isTrue);
      expect(confirmation.accept(original), isFalse);
      expect(requests, hasLength(1));
      expect(confirmation.resetForAnother(), isTrue);
      expect(confirmation.publication, isNull);
      expect(confirmation.isConfirmed, isFalse);
      final RegistrationPublication next = RegistrationPublication(
        accountBlock: block(hash: anotherHash),
      );
      expect(confirmation.accept(next), isTrue);
      expect(confirmation.publication, same(next));
      expect(confirmation.isConfirmed, isFalse);
      expect(requests.last, (321, anotherHash));
      replies.last.complete(false);
      await confirmation.check();
    },
  );
}
