import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/detail_row.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/p2p_swaps_list_item.dart'
    show swapListShortId;
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One public deposit leg. A stored receiving amount does not establish proof.
class HtlcCard extends StatelessWidget {
  /// Renders supplied public facts and leaves unavailable values unknown.
  const HtlcCard({
    required this.title,
    required this.sender,
    required this.htlcId,
    required this.expirationTime,
    required this.recipient,
    required this.amount,
    required this.tokenStandard,
    required this.tokenDecimals,
    required this.tokenSymbol,
    super.key,
  });

  /// Shows the recorded sending leg without inventing a current expiration.
  factory HtlcCard.sending({required HtlcSwap swap}) => HtlcCard(
    title: 'You send',
    sender: swap.selfAddress,
    htlcId: swap.direction == P2pSwapDirection.outgoing
        ? swap.initialHtlcId
        : swap.counterHtlcId,
    expirationTime: null,
    recipient: swap.counterpartyAddress,
    amount: swap.fromAmount,
    tokenStandard: swap.fromTokenStandard,
    tokenDecimals: swap.fromDecimals,
    tokenSymbol: swap.fromSymbol,
  );

  /// Shows public receiving identifiers while leaving unproven amounts unknown.
  factory HtlcCard.receiving({required HtlcSwap swap}) => HtlcCard(
    title: 'You receive',
    sender: swap.counterpartyAddress,
    htlcId: swap.direction == P2pSwapDirection.outgoing
        ? swap.counterHtlcId
        : swap.initialHtlcId,
    expirationTime: null,
    recipient: swap.selfAddress,
    amount: null,
    tokenStandard: null,
    tokenDecimals: null,
    tokenSymbol: null,
  );

  /// Shows live amount metadata only when the supplied token standard matches.
  factory HtlcCard.fromHtlcInfo({
    required String title,
    required HtlcInfo htlc,
    required Token token,
  }) => HtlcCard(
    title: title,
    sender: htlc.timeLocked.toString(),
    htlcId: htlc.id.toString(),
    expirationTime: htlc.expirationTime,
    recipient: htlc.hashLocked.toString(),
    amount: htlc.tokenStandard == token.tokenStandard ? htlc.amount : null,
    tokenStandard: htlc.tokenStandard == token.tokenStandard
        ? token.tokenStandard.toString()
        : null,
    tokenDecimals: htlc.tokenStandard == token.tokenStandard
        ? token.decimals
        : null,
    tokenSymbol: htlc.tokenStandard == token.tokenStandard
        ? token.symbol
        : null,
  );

  /// Public leg label, localized for the built-in sending and receiving modes.
  final String title;

  /// Public sender of the displayed deposit leg.
  final String sender;

  /// Exact deposit identifier, absent before its creation is established.
  final String? htlcId;

  /// Proven current expiration, never derived from an unavailable lookup.
  final int? expirationTime;

  /// Public withdrawal recipient when known.
  final String? recipient;

  /// Exact base-unit amount, displayed only with complete matching metadata.
  final BigInt? amount;

  /// Token standard associated with [amount].
  final String? tokenStandard;

  /// Matching token precision associated with [amount].
  final int? tokenDecimals;

  /// Matching token symbol associated with [amount].
  final String? tokenSymbol;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool knownAmount =
        amount != null &&
        tokenDecimals != null &&
        tokenStandard != null &&
        tokenSymbol != null;
    final String label = switch (title) {
      'You send' => context.l10n.swapListYouSend,
      'You receive' => context.l10n.swapListYouReceive,
      _ => title,
    };
    return Material(
      color: tokens.card2,
      borderRadius: BorderRadius.circular(tokens.compactRadius),
      clipBehavior: Clip.antiAlias,
      child: RowDetail(
        keyPrefix: 'htlc_$title',
        row: Padding(
          padding: tokens.cardPadding,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      usesLatinScript(context) ? label.toUpperCase() : label,
                      style: ledgerLabelStyle(context),
                    ),
                    SizedBox(height: tokens.fieldLabelGap),
                    if (knownAmount)
                      AmountText(
                        amount!,
                        decimals: tokenDecimals!,
                        symbol: tokenSymbol,
                        style: tokens.transferAmountText,
                      )
                    else
                      Text(
                        context.l10n.swapListUnknown,
                        style: tokens.compactText.copyWith(color: tokens.dim),
                      ),
                  ],
                ),
              ),
              const RowDetailChevron(),
            ],
          ),
        ),
        detail: (BuildContext context) => Padding(
          padding: tokens.swapDetailPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (htlcId != null)
                DetailRow(
                  label: context.l10n.swapListDepositId,
                  value: htlcId!,
                  valueToShow: swapListShortId(htlcId!),
                ),
              if (tokenStandard != null)
                DetailRow(
                  label: context.l10n.swapListTokenStandard,
                  value: tokenStandard!,
                ),
              DetailRow(
                label: context.l10n.swapListSender,
                value: sender,
                valueToShow: swapListShortId(sender),
              ),
              if (recipient != null)
                DetailRow(
                  label: context.l10n.swapListRecipient,
                  value: recipient!,
                  valueToShow: swapListShortId(recipient!),
                ),
              if (expirationTime != null)
                DetailRow(
                  label: context.l10n.swapListExpires,
                  value: FormatUtils.formatDateTime(expirationTime! * 1000),
                  canBeCopied: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
