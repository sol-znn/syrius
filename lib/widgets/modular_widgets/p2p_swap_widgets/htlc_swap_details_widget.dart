import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/detail_row.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/p2p_swaps_list_item.dart'
    show swapListShortId;

/// Public identifier details, without retaining the private legacy model.
class HtlcSwapDetailsWidget extends StatelessWidget {
  /// Copies public addresses and deposit identifiers without retaining secrets.
  HtlcSwapDetailsWidget({required HtlcSwap swap, super.key})
    : _self = swap.selfAddress,
      _counterparty = swap.counterpartyAddress,
      _ownId = swap.direction == P2pSwapDirection.outgoing
          ? swap.initialHtlcId
          : swap.counterHtlcId,
      _counterpartyId = swap.direction == P2pSwapDirection.incoming
          ? swap.initialHtlcId
          : swap.counterHtlcId;
  final String _self;
  final String _counterparty;
  final String? _ownId;
  final String? _counterpartyId;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return RowDetail(
      keyPrefix: 'htlc_public_details',
      row: Padding(
        padding: tokens.swapCellPadding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              context.l10n.swapListDetails,
              style: tokens.compactText.copyWith(color: tokens.dim),
            ),
            SizedBox(width: tokens.fieldLabelGap),
            const RowDetailChevron(),
          ],
        ),
      ),
      detail: (BuildContext context) => Padding(
        padding: tokens.swapDetailPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DetailRow(
              label: context.l10n.swapListYourAddress,
              value: _self,
              valueToShow: swapListShortId(_self),
            ),
            DetailRow(
              label: context.l10n.swapListCounterparty,
              value: _counterparty,
              valueToShow: swapListShortId(_counterparty),
            ),
            if (_ownId != null)
              DetailRow(
                label: context.l10n.swapListYourDepositId,
                value: _ownId,
                valueToShow: swapListShortId(_ownId),
              ),
            if (_counterpartyId != null)
              DetailRow(
                label: context.l10n.swapListCounterpartyDepositId,
                value: _counterpartyId,
                valueToShow: swapListShortId(_counterpartyId),
              ),
          ],
        ),
      ),
    );
  }
}
