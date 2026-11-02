import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/address_owned_fetch_cubit.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Reads current ownership without admitting a previous address's cache.
class PillarsByOwnerBloc extends AddressOwnedFetchCubit<List<PillarInfo>> {
  /// {@macro default_constructor}
  PillarsByOwnerBloc({required super.zenon});

  @override
  Future<List<PillarInfo>> getData({required Address address}) async =>
      List<PillarInfo>.unmodifiable(
        await zenon.embedded.pillar.getByOwner(address),
      );

  @override
  bool accepts(List<PillarInfo> data, Address address) => data.every(
    (PillarInfo pillar) => pillar.ownerAddress.toString() == address.toString(),
  );
}
