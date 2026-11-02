import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/plasma_beneficiary_address_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_view.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Owns the Addresses presenter while the root owns the explicit Send route.
class Addresses extends StatefulWidget {
  /// The legacy statistics argument remains source-compatible for callers.
  const Addresses({
    required this.accountChainStatsBloc,
    this.isCurrent,
    this.senderIsCurrent,
    this.onSend,
    this.binding,
    this.draft,
    this.visibility,
    super.key,
  });

  /// Existing callers may retain their old bloc; this view uses captured reads.
  final AccountChainStatsBloc accountChainStatsBloc;

  /// Root-owned page and Settings-section authority.
  final bool Function()? isCurrent;

  /// The original root sender attachment, independent of page visibility.
  final bool Function()? senderIsCurrent;

  /// Opens Transfer in Send mode after selecting a single exact recipient.
  final VoidCallback? onSend;

  /// Injection never falls back to production when a binding is supplied.
  final AddressesSettingsBinding? binding;

  /// An injected draft permits finite fixtures without the app shell.
  final SendDraftCubit? draft;

  /// Uses the shared hidden-balance choice in production.
  final BalanceVisibility? visibility;

  @override
  State<Addresses> createState() => AddressesState();
}

/// Holds only the disposable view adapter and original provider references.
class AddressesState extends State<Addresses> {
  AddressesSettingsPresenter? _presenter;
  bool _rebindQueued = false;

  @override
  void initState() {
    super.initState();
    WalletContextRevision.changes.addListener(_contextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _presenter ??= _createPresenter();
  }

  AddressesSettingsPresenter _createPresenter() {
    final AddressesSettingsBinding? injected = widget.binding;
    if (injected != null) return AddressesSettingsPresenter(binding: injected);
    // Capture resource-bearing providers before any preference write awaits.
    final SelectedAddressNotifier selected = context
        .read<SelectedAddressNotifier>();
    final PlasmaBeneficiaryAddressCubit beneficiary = context
        .read<PlasmaBeneficiaryAddressCubit>();
    final LatestTransactionsBloc latest = context
        .read<LatestTransactionsBloc>();
    final PendingTransactionsBloc pending = context
        .read<PendingTransactionsBloc>();
    final PillarRewardsHistoryBloc pillarRewards = context
        .read<PillarRewardsHistoryBloc>();
    final SentinelRewardsHistoryBloc sentinelRewards = context
        .read<SentinelRewardsHistoryBloc>();
    final StakingRewardsHistoryBloc stakingRewards = context
        .read<StakingRewardsHistoryBloc>();
    final PillarsByOwnerBloc pillars = context.read<PillarsByOwnerBloc>();
    final DelegationStatsBloc delegation = context.read<DelegationStatsBloc>();
    final Object? file = kWalletFile;
    final String? path = kWalletPath;
    final Zenon? client = app.zenon;
    final int revision = WalletContextRevision.value;
    final List<String?> members = List<String?>.of(kDefaultAddressList);
    bool providersCurrent() =>
        mounted &&
        identical(selected, context.read<SelectedAddressNotifier>()) &&
        identical(beneficiary, context.read<PlasmaBeneficiaryAddressCubit>()) &&
        identical(latest, context.read<LatestTransactionsBloc>()) &&
        identical(pending, context.read<PendingTransactionsBloc>()) &&
        identical(pillarRewards, context.read<PillarRewardsHistoryBloc>()) &&
        identical(
          sentinelRewards,
          context.read<SentinelRewardsHistoryBloc>(),
        ) &&
        identical(stakingRewards, context.read<StakingRewardsHistoryBloc>()) &&
        identical(pillars, context.read<PillarsByOwnerBloc>()) &&
        identical(delegation, context.read<DelegationStatsBloc>());
    return AddressesSettingsPresenter(
      binding: captureAddressesSettingsBinding(
        senderIsCurrent: widget.senderIsCurrent,
        applySelection: (String address, bool Function() sourceCurrent) {
          if (!sourceCurrent() || !providersCurrent()) return;
          selected.changeSelectedAddress(address);
          bool current() =>
              sourceCurrent() &&
              providersCurrent() &&
              identical(file, kWalletFile) &&
              path == kWalletPath &&
              identical(client, app.zenon) &&
              kSelectedAddress == address &&
              WalletContextRevision.value == revision + 1 &&
              listEquals(members, kDefaultAddressList);
          final Address parsed = Address.parse(address);
          final List<VoidCallback> effects = <VoidCallback>[
            () => beneficiary.changeAddress(address),
            () => latest.add(InfiniteListRefreshRequested(address: parsed)),
            () => pending.add(InfiniteListRefreshRequested(address: parsed)),
            () => pillarRewards.add(FetchRequestData(address: parsed)),
            () => sentinelRewards.add(FetchRequestData(address: parsed)),
            () => stakingRewards.add(FetchRequestData(address: parsed)),
            () => pillars.add(FetchRequestData(address: parsed)),
            () => delegation.add(FetchRequestData(address: parsed)),
          ];
          for (final VoidCallback effect in effects) {
            if (!current()) return;
            effect();
          }
        },
      ),
    );
  }

  void _contextChanged() {
    if (!mounted || widget.binding != null || _rebindQueued) return;
    _rebindQueued = true;
    scheduleMicrotask(() {
      _rebindQueued = false;
      if (!mounted || widget.binding != null) return;
      final AddressesSettingsPresenter? original = _presenter;
      setState(() => _presenter = _createPresenter());
      unawaited(original?.close());
    });
  }

  @override
  void didUpdateWidget(Addresses oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.binding, widget.binding)) {
      final AddressesSettingsPresenter? original = _presenter;
      _presenter = _createPresenter();
      unawaited(original?.close());
    }
  }

  @override
  Widget build(BuildContext context) {
    final BalanceVisibility visibility =
        widget.visibility ?? BalanceVisibility.instance;
    final AddressesSettingsPresenter presenter = _presenter!;
    return ListenableBuilder(
      listenable: visibility,
      builder: (BuildContext context, Widget? child) => AddressesSettingsView(
        key: ObjectKey(presenter),
        presenter: presenter,
        draft: widget.draft ?? context.read<SendDraftCubit>(),
        isCurrent: widget.isCurrent ?? () => true,
        senderIsCurrent: widget.senderIsCurrent,
        onSend: widget.onSend,
        hideBalances: visibility.hidden,
      ),
    );
  }

  @override
  void dispose() {
    WalletContextRevision.changes.removeListener(_contextChanged);
    unawaited(_presenter?.close());
    super.dispose();
  }
}
