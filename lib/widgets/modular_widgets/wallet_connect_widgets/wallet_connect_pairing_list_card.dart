import 'package:material_ui/material_ui.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/wallet_connect_pairings_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/wallet_connect_sessions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

/// WalletConnect pairings: the secure link a site made first, under which
/// its sessions run. Disconnecting a pairing does not delete its sessions.
class WalletConnectPairingsCard extends StatefulWidget {
  /// Displays actual pairing records separately from active session records.
  const WalletConnectPairingsCard({super.key});

  @override
  State<WalletConnectPairingsCard> createState() =>
      _WalletConnectPairingsCardState();
}

class _WalletConnectPairingsCardState extends State<WalletConnectPairingsCard> {
  final WalletConnectPairingsBloc _pairingsBloc = sl
      .get<WalletConnectPairingsBloc>();

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Pairings',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          iconSize: 18,
          icon: const Icon(Icons.refresh, color: AppColors.faint),
          onPressed: _pairingsBloc.refreshResults,
        ),
      ],
      child: _buildPairingsTable(),
    );
  }

  Widget _buildPairingsTable() {
    return InfiniteScrollTable<PairingInfo>(
      disposeBloc: false,
      bloc: _pairingsBloc,
      headerColumns: const <InfiniteScrollTableHeaderColumn>[
        InfiniteScrollTableHeaderColumn(
          columnName: 'Site',
        ),
        InfiniteScrollTableHeaderColumn(
          columnName: 'URL',
          flex: 2,
        ),
        InfiniteScrollTableHeaderColumn(
          columnName: 'Topic',
        ),
        InfiniteScrollTableHeaderColumn(
          columnName: 'Expires',
        ),
        InfiniteScrollTableHeaderColumn(
          columnName: 'Active',
        ),
        InfiniteScrollTableHeaderColumn(
          columnName: '',
        ),
      ],
      generateRowCells: (PairingInfo pairingInfo, bool isSelected) {
        return <Widget>[
          InfiniteScrollTableCell.withText(
            context,
            pairingInfo.peerMetadata?.name ?? '-',
          ),
          InfiniteScrollTableCell(
            _buildTableUrlWidget(pairingInfo),
            flex: 2,
          ),
          if (isSelected)
            InfiniteScrollTableCell.withMarquee(
              pairingInfo.topic,
            )
          else
            InfiniteScrollTableCell.withText(
              context,
              pairingInfo.topic.short,
              textStyle: settingMonoStyle(context),
            ),
          InfiniteScrollTableCell.withText(
            context,
            _formatExpiryDateTime(pairingInfo.expiry),
            textStyle: settingMonoStyle(context),
          ),
          InfiniteScrollTableCell.withText(
            context,
            pairingInfo.active ? 'Yes' : 'No',
          ),
          InfiniteScrollTableCell(
            _buildDeactivatePairingIcon(pairingInfo),
          ),
        ];
      },
    );
  }

  Widget _buildDeactivatePairingIcon(PairingInfo pairingInfo) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: context.l10n.appsSettingsDisconnectPairing,
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        icon: const Icon(Icons.close, color: AppColors.faint),
        onPressed: () => _onDeactivatePairingIconPressed(pairingInfo),
      ),
    );
  }

  Widget _buildTableUrlWidget(PairingInfo pairingInfo) {
    final String? url = pairingInfo.peerMetadata?.url;
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            url ?? '-',
            overflow: TextOverflow.ellipsis,
            style: settingMonoStyle(context),
          ),
        ),
        if (url != null) LinkIcon(url: url),
      ],
    );
  }

  String _formatExpiryDateTime(int expirySeconds) =>
      FormatUtils.formatDayMonthTime(expirySeconds * 1000);

  Future<void> _onDeactivatePairingIconPressed(PairingInfo pairingInfo) async {
    final IWeb3WalletService service = sl<IWeb3WalletService>();
    final WalletConnectSessionsBloc sessions = sl<WalletConnectSessionsBloc>();
    final NotificationsBloc notifications = sl<NotificationsBloc>();
    final String failureMessage = context.l10n.appsSettingsFailed;
    final String disconnectLabel = context.l10n.appsSettingsDisconnectPairing;
    bool current() =>
        mounted &&
        sl.isRegistered<IWeb3WalletService>() &&
        identical(service, sl<IWeb3WalletService>());
    if (!current() ||
        !service.pairings.value.any(
          (PairingInfo pairing) => identical(pairing, pairingInfo),
        )) {
      return;
    }
    try {
      await service.deactivatePairing(
        topic: pairingInfo.topic,
      );
      if (!current()) return;
      _pairingsBloc.refreshResults();
      sessions.refreshResults();
    } on Object {
      if (!current()) return;
      await notifications.addErrorNotification(
        failureMessage,
        disconnectLabel,
      );
    }
  }
}
