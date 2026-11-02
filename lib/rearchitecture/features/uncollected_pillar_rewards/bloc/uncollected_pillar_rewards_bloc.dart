import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/address_owned_fetch_cubit.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A bloc responsible for fetching and managing the state of
/// uncollected rewards for a specific address.
class UncollectedPillarRewardsBloc
    extends AddressOwnedFetchCubit<UncollectedReward> {
  /// {@macro default_constructor}
  UncollectedPillarRewardsBloc({
    required super.zenon,
  });

  @override
  Future<UncollectedReward> getData({required Address address}) =>
      zenon.embedded.pillar.getUncollectedReward(address);

  @override
  bool accepts(UncollectedReward data, Address address) =>
      data.address == address &&
      data.znnAmount >= BigInt.zero &&
      data.qsrAmount >= BigInt.zero;
}
