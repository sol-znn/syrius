import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/address_owned_fetch_cubit.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Fetches the sentinel owned by an address.
///
/// The nullable SDK response becomes a list with explicit current ownership.
class SentinelsByOwnerBloc extends AddressOwnedFetchCubit<List<SentinelInfo>> {
  /// {@macro default_constructor}
  SentinelsByOwnerBloc({required super.zenon});

  @override
  Future<List<SentinelInfo>> getData({required Address address}) async {
    final SentinelInfo? sentinelInfo = await zenon.embedded.sentinel.getByOwner(
      address,
    );

    return sentinelInfo == null
        ? <SentinelInfo>[]
        : List<SentinelInfo>.unmodifiable(<SentinelInfo>[sentinelInfo]);
  }

  @override
  bool accepts(List<SentinelInfo> data, Address address) => data.every(
    (SentinelInfo sentinel) => sentinel.owner.toString() == address.toString(),
  );
}
