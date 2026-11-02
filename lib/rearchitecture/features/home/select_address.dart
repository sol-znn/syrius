import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/plasma_beneficiary_address_cubit.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Makes [address] the selected address: stored, announced, and every
/// address-bound list reloaded for it.
///
/// Settings and the home both switch addresses; this is the one place that
/// knows what a switch has to touch.
Future<void> selectWalletAddress(
  BuildContext context,
  String address, {
  bool Function()? isCurrent,
}) async {
  if (isCurrent?.call() == false) return;
  await Hive.box(kSharedPrefsBox).put(kDefaultAddressKey, address);
  if (!context.mounted || isCurrent?.call() == false) return;
  Provider.of<SelectedAddressNotifier>(
    context,
    listen: false,
  ).changeSelectedAddress(address);
  context.read<PlasmaBeneficiaryAddressCubit>().changeAddress(address);

  final Address parsed = Address.parse(address);
  context.read<LatestTransactionsBloc>().add(
    InfiniteListRefreshRequested(address: parsed),
  );
  context.read<PendingTransactionsBloc>().add(
    InfiniteListRefreshRequested(address: parsed),
  );
  context.read<PillarRewardsHistoryBloc>().add(
    FetchRequestData(address: parsed),
  );
  context.read<SentinelRewardsHistoryBloc>().add(
    FetchRequestData(address: parsed),
  );
  context.read<StakingRewardsHistoryBloc>().add(
    FetchRequestData(address: parsed),
  );
  context.read<PillarsByOwnerBloc>().add(
    FetchRequestData(address: parsed),
  );
  context.read<DelegationStatsBloc>().add(
    FetchRequestData(address: parsed),
  );
}
