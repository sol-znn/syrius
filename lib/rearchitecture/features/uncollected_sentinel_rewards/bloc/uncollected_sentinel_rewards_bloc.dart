import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/address_owned_fetch_cubit.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A bloc responsible for fetching and managing the state of
/// uncollected sentinel rewards for a specific address.
class UncollectedSentinelRewardsBloc
    extends AddressOwnedFetchCubit<UncollectedReward> {
  /// {@macro default_constructor}
  UncollectedSentinelRewardsBloc({
    required super.zenon,
  });

  @override
  Future<UncollectedReward> getData({required Address address}) =>
      zenon.embedded.sentinel.getUncollectedReward(address);

  @override
  bool accepts(UncollectedReward data, Address address) =>
      data.address == address &&
      data.znnAmount >= BigInt.zero &&
      data.qsrAmount >= BigInt.zero;
}
