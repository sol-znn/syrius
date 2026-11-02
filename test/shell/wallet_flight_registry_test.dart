import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

void main() {
  final String owner = kZnnCoin.owner.toString();
  final String other = emptyAddress.toString();
  final Hash hash = Hash.parse(List<String>.filled(64, '1').join());
  AccountBlockTemplate publication() =>
      AccountBlockTemplate(
          blockType: BlockTypeEnum.userSend.index,
          amount: BigInt.parse('900719925474099300000001'),
          tokenStandard: kZnnCoin.tokenStandard,
        )
        ..hash = hash
        ..address = Address.parse(owner)
        ..chainIdentifier = 321;

  test(
    'wallet anchor retains the exact publication as more addresses are derived',
    () {
      final WalletFlightRegistry registry = WalletFlightRegistry(
        currentChainId: () => 321,
        lookup: (_, _) async => false,
      );
      addTearDown(registry.dispose);
      final AccountBlockTemplate block = publication();
      final Map<String, dynamic> original = block.toJson();
      expect(registry.published(block, <String>[owner]), isTrue);
      expect(registry.published(block, <String>[owner, other]), isTrue);
      final InFlightBlocks model = registry.forWallet(321, <String>[
        owner,
        other,
      ]);
      expect(
        identical(model, registry.forWallet(321, <String>[owner])),
        isTrue,
      );
      expect(model.value, hasLength(1));
      expect(model.value.single.hash, hash);
      expect(model.value.single.amount, block.amount);
      expect(model.value.single.decimals, kZnnCoin.decimals);
      expect(model.value.single.symbol, 'ZNN');
      expect(block.toJson(), original);
      expect(registry.forWallet(1, <String>[owner, other]).value, isEmpty);
      expect(registry.forWallet(321, <String>[other]).value, isEmpty);
    },
  );

  test('unknown units remain unknown and non-publications are ignored', () {
    final WalletFlightRegistry registry = WalletFlightRegistry(
      currentChainId: () => 321,
      lookup: (_, _) async => false,
    );
    addTearDown(registry.dispose);
    final AccountBlockTemplate block = publication()
      ..tokenStandard = TokenStandard.parse(emptyTokenStandard);
    expect(registry.published(block, <String>[other]), isFalse);
    expect(
      registry.published(block..hash = emptyHash, <String>[owner]),
      isFalse,
    );
    block.hash = hash;
    expect(registry.published(block, <String>[owner]), isTrue);
    final InFlightBlock tracked = registry
        .forWallet(321, <String>[owner])
        .value
        .single;
    expect(tracked.decimals, isNull);
    expect(tracked.symbol, isNull);
    expect(tracked.amount, block.amount);
  });

  test(
    'a changed chain leaves the original publication unresolved',
    () async {
      int chain = 321;
      final Completer<bool> answer = Completer<bool>();
      final List<(int, Hash)> requests = <(int, Hash)>[];
      final WalletFlightRegistry registry = WalletFlightRegistry(
        currentChainId: () => chain,
        lookup: (int chainId, Hash requested) {
          requests.add((chainId, requested));
          return answer.future;
        },
      );
      addTearDown(registry.dispose);
      registry.published(publication(), <String>[owner]);
      final InFlightBlocks model = registry.forWallet(321, <String>[owner]);
      final Future<void> pending = model.check();
      chain = 1;
      answer.complete(true);
      await pending;
      expect(requests, <(int, Hash)>[(321, hash)]);
      expect(model.value.single.hash, hash);
      await model.check();
      expect(requests, hasLength(1));
      chain = 321;
      await model.check();
      expect(model.value, isEmpty);
    },
  );
}
