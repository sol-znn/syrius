import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/clipboard_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/detail_row.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';

/// Shared column proportions for the swap header and every rendered public row.
const List<int> kP2pSwapColumnFlex = <int>[4, 3, 3, 4, 4];

/// One public historical record, with fresh proof kept separate from its label.
class P2pSwapsListItem extends StatelessWidget {
  /// Renders one immutable public row with exact-row action callbacks.
  const P2pSwapsListItem({
    required this.row,
    required this.onOpen,
    required this.onDelete,
    required this.canAct,
    super.key,
  });

  /// Public history plus independently matched chain facts.
  final SwapListRow row;

  /// Opens this exact record after the enclosing owner rechecks it.
  final ValueChanged<SwapListRecord> onOpen;

  /// Requests guarded deletion of this exact inactive record.
  final ValueChanged<SwapListRecord> onDelete;

  /// Whether the original source currently admits row actions.
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final SwapListRecord record = row.record;
    final TextStyle data = tokens.dataText;
    final String? expiry = _expiry(context);
    return RowDetail(
      id: record.id,
      keyPrefix: 'swap_${record.id}',
      row: ConstrainedBox(
        constraints: BoxConstraints(minHeight: tokens.swapRowHeight),
        child: Padding(
          padding: tokens.swapCellPadding,
          child: Row(
            children: <Widget>[
              Expanded(
                flex: kP2pSwapColumnFlex[0],
                child: _buildStatus(context),
              ),
              Expanded(
                flex: kP2pSwapColumnFlex[1],
                child: AmountText(
                  record.fromAmount,
                  decimals: record.fromDecimals,
                  symbol: record.fromSymbol,
                  style: data,
                ),
              ),
              Expanded(
                flex: kP2pSwapColumnFlex[2],
                child: row.receiving == null
                    ? Text(
                        context.l10n.swapListUnknown,
                        style: tokens.compactText.copyWith(color: tokens.dim),
                      )
                    : AmountText(
                        row.receiving!.amount,
                        decimals: row.receiving!.decimals,
                        symbol: row.receiving!.symbol,
                        style: data,
                      ),
              ),
              Expanded(
                flex: kP2pSwapColumnFlex[3],
                child: Tooltip(
                  message: record.counterpartyAddress,
                  child: Text(
                    swapListShortId(record.counterpartyAddress),
                    textDirection: TextDirection.ltr,
                    textAlign: ltrTextAlign(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: data.copyWith(color: tokens.dim),
                  ),
                ),
              ),
              Expanded(
                flex: kP2pSwapColumnFlex[4],
                child: Text(
                  expiry ?? context.l10n.swapListUnknown,
                  textDirection: expiry == null ? null : TextDirection.ltr,
                  textAlign: expiry == null ? null : ltrTextAlign(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: expiry == null
                      ? tokens.compactText.copyWith(color: tokens.dim)
                      : data.copyWith(color: tokens.dim),
                ),
              ),
              SizedBox(
                width: tokens.swapChevronWidth,
                child: const RowDetailChevron(),
              ),
            ],
          ),
        ),
      ),
      detail: _buildDetails,
    );
  }

  Widget _buildStatus(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final (
      IconData icon,
      String label,
      Color color,
    ) = switch (row.record.state) {
      P2pSwapState.pending => (
        Icons.schedule,
        context.l10n.swapListStarting,
        tokens.qsrInk,
      ),
      P2pSwapState.active => (
        Icons.schedule,
        row.record.receiveDepositId == null
            ? context.l10n.swapListWaiting
            : context.l10n.swapListActive,
        tokens.qsrInk,
      ),
      P2pSwapState.completed => (
        Icons.check,
        context.l10n.swapListCompleted,
        tokens.znnInk,
      ),
      P2pSwapState.reclaimable => (
        Icons.replay,
        context.l10n.swapListReclaimable,
        tokens.warn,
      ),
      P2pSwapState.unsuccessful => (
        Icons.close,
        context.l10n.swapListUnsuccessful,
        tokens.dim,
      ),
      P2pSwapState.error => (
        Icons.help_outline,
        context.l10n.swapListUnknown,
        tokens.dim,
      ),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.inlineGap,
          vertical: tokens.fieldLabelGap,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(tokens.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: tokens.settingsIconSize),
            SizedBox(width: tokens.fieldLabelGap),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.captionText.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final SwapListRecord record = row.record;
    final String? own = record.ownDepositId;
    final String? counterparty = record.receiveDepositId;
    final Widget left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DetailRow(
          label: context.l10n.swapListYourDepositId,
          value: own ?? context.l10n.swapListUnknown,
          valueToShow: own == null ? null : swapListShortId(own),
          canBeCopied: own != null,
          ledger: true,
          trailing: own == null
              ? null
              : TextButton(
                  key: ValueKey<String>('swap_copy_${record.id}'),
                  onPressed: () => ClipboardUtils.copyToClipboard(own, context),
                  child: Text(context.l10n.swapListCopyForThem),
                ),
        ),
        DetailRow(
          label: context.l10n.swapListRate,
          value: row.rate ?? context.l10n.swapListUnknown,
          canBeCopied: false,
          ledger: true,
        ),
        DetailRow(
          label: context.l10n.swapListStarted,
          value: FormatUtils.formatDateTime(record.started * 1000),
          canBeCopied: false,
          ledger: true,
        ),
      ],
    );
    final Widget right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DetailRow(
          label: context.l10n.swapListCounterparty,
          value: record.counterpartyAddress,
          canBeCopied: false,
          ledger: true,
        ),
        DetailRow(
          label: context.l10n.swapListCounterpartyDepositId,
          value: counterparty ?? context.l10n.swapListUnknown,
          valueToShow: counterparty == null
              ? null
              : swapListShortId(counterparty),
          canBeCopied: counterparty != null,
          ledger: true,
        ),
        Wrap(
          spacing: tokens.inlineGap,
          children: <Widget>[
            TextButton(
              key: ValueKey<String>('swap_open_${record.id}'),
              onPressed: canAct ? () => onOpen(record) : null,
              child: Text(
                record.state == P2pSwapState.reclaimable
                    ? context.l10n.swapListReclaim
                    : context.l10n.swapListOpen,
              ),
            ),
            if (record.canDelete)
              IconButton(
                tooltip: context.l10n.swapListDelete,
                onPressed: canAct ? () => onDelete(record) : null,
                icon: Icon(Icons.delete_outline, size: tokens.railIconSize),
              ),
          ],
        ),
      ],
    );
    return Padding(
      padding: tokens.swapDetailPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (record.state == P2pSwapState.active &&
              record.receiveDepositId == null)
            Container(
              margin: EdgeInsetsDirectional.only(bottom: tokens.cardGap),
              padding: tokens.swapNoticePadding,
              decoration: BoxDecoration(
                color: tokens.card3,
                borderRadius: BorderRadius.circular(tokens.compactRadius),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: tokens.settingsIconSize,
                    color: tokens.qsrInk,
                  ),
                  SizedBox(width: tokens.swapNoticeGap),
                  Expanded(
                    child: Text(
                      context.l10n.swapListWaitingNotice,
                      style: tokens.compactText,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: left),
              SizedBox(width: tokens.swapDetailColumnGap),
              Expanded(child: right),
            ],
          ),
        ],
      ),
    );
  }

  String? _expiry(BuildContext context) {
    final int? expiration = row.currentExpiration;
    final int? time = row.chainTime;
    if (expiration == null || time == null) return null;
    if (expiration <= time) return context.l10n.swapListExpired;
    return FormatUtils.formatDataShort((expiration - time) * 1000);
  }
}

/// Copies always retain the exact original identifier behind this short label.
String swapListShortId(String value) => value.length <= 14
    ? value
    : '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
