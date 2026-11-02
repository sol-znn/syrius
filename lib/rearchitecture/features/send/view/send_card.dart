import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';

/// The send form of the Transfer page.
class SendCard extends StatelessWidget {
  /// Creates a new instance.
  const SendCard({
    this.embedded = false,
    this.showSender = true,
    this.showSyncNotice = true,
    this.contacts,
    this.priceFeed,
    this.syncCubit,
    super.key,
  });

  /// Omits the standalone panel when Transfer supplies the shared card.
  final bool embedded;

  /// False when Transfer supplies the sender selector in its shared header.
  final bool showSender;

  /// False when Transfer places the same notice above its shared header.
  final bool showSyncNotice;

  /// The existing address book when omitted.
  final ContactsStore? contacts;

  /// The shared price feed when omitted.
  final PriceFeed? priceFeed;

  /// The session's existing sync cubit when omitted.
  final NodeSyncStatusCubit? syncCubit;

  @override
  Widget build(BuildContext context) {
    final Widget body = BlocBuilder<MultipleBalanceBloc, MultipleBalanceState>(
      builder: (_, MultipleBalanceState state) => switch (state.status) {
        MultipleBalanceStatus.failure => SendError(error: state.error!),
        MultipleBalanceStatus.initial => const SendEmpty(),
        MultipleBalanceStatus.loading => const SendLoading(),
        MultipleBalanceStatus.success
            when embedded &&
                kDefaultAddressList.whereType<String>().any(
                  (String address) =>
                      !(state.data?.containsKey(address) ?? false),
                ) =>
          const SendLoading(),
        MultipleBalanceStatus.success when state.data?.isNotEmpty ?? false =>
          SendPopulated(
            key: const Key('send_form_ready'),
            balances: state.data!,
            showSender: showSender,
            showSyncNotice: showSyncNotice,
            contacts: contacts,
            priceFeed: priceFeed,
            syncCubit: syncCubit,
          ),
        MultipleBalanceStatus.success => const SendEmpty(),
      },
    );
    if (embedded) return body;
    return Panel(
      title: context.l10n.send,
      actions: <Widget>[
        RefreshButton(
          onPressed: () {
            sl.get<MultipleBalanceBloc>().add(
              MultipleBalanceFetch(
                addresses: kDefaultAddressList.map((String? e) => e!).toList(),
              ),
            );
          },
        ),
      ],
      child: body,
    );
  }
}
