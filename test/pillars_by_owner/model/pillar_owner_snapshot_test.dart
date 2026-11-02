import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/model/pillar_owner_snapshot.dart';

void main() {
  test('unavailable and pending balances do not establish zero', () {
    const PillarOwnerFact<BigInt> unavailable =
        PillarOwnerFact<BigInt>.unavailable();
    const PillarOwnerFact<BigInt> loading = PillarOwnerFact<BigInt>.loading();
    final PillarOwnerFact<BigInt> actualZero =
        PillarOwnerFact<BigInt>.available(
          BigInt.zero,
        );

    expect(unavailable.state, PillarOwnerFactState.unavailable);
    expect(loading.state, PillarOwnerFactState.loading);
    expect(unavailable.value, isNull);
    expect(loading.value, isNull);
    expect(actualZero.state, PillarOwnerFactState.available);
    expect(actualZero.value, BigInt.zero);
  });

  test('a known registration cost establishes no deposited balance', () {
    final PillarOwnerFact<BigInt> cost = PillarOwnerFact<BigInt>.available(
      BigInt.from(150000) * BigInt.from(100000000),
    );
    const PillarOwnerFact<BigInt> deposit =
        PillarOwnerFact<BigInt>.unavailable();

    expect(cost.value, isNotNull);
    expect(deposit.state, PillarOwnerFactState.unavailable);
    expect(deposit.value, isNull);
  });
}
