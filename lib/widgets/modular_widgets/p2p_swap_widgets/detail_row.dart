import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/copy_to_clipboard_button.dart';

/// A public identifier or amount. Unlock material must never be passed here.
class DetailRow extends StatelessWidget {
  /// Displays one public value with optional truncation and full-value copying.
  const DetailRow({
    required this.label,
    required this.value,
    this.valueToShow,
    this.prefixWidget,
    this.canBeCopied = true,
    this.ledger = false,
    this.trailing,
    super.key,
  });

  /// Localized description of the public value.
  final String label;

  /// Full tooltip and clipboard value; never pass unlock material here.
  final String value;

  /// Optional shortened visible value, preserving [value] for copying.
  final String? valueToShow;

  /// Optional leading public mark or token icon.
  final Widget? prefixWidget;

  /// Whether the full public value has an explicit copy action.
  final bool canBeCopied;

  /// Whether to use the compact ledger-label treatment.
  final bool ledger;

  /// Optional trailing action owned by the enclosing flow.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        vertical: tokens.swapDetailRowGap / 2,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: ledger
                ? tokens.swapDetailLabelWidth
                : tokens.tokenCreateReviewLabelWidth,
            child: Text(
              ledger && usesLatinScript(context) ? label.toUpperCase() : label,
              style: ledger
                  ? ledgerLabelStyle(context)
                  : tokens.compactText.copyWith(color: tokens.dim),
            ),
          ),
          SizedBox(width: tokens.inlineGap),
          Expanded(
            child: Row(
              children: <Widget>[
                if (prefixWidget != null) ...<Widget>[
                  prefixWidget!,
                  SizedBox(width: tokens.fieldLabelGap),
                ],
                Flexible(
                  child: Tooltip(
                    message: value,
                    child: Text(
                      valueToShow ?? value,
                      maxLines: 1,
                      textDirection: ltrUnlessRtl(valueToShow ?? value),
                      textAlign: ltrTextAlign(context),
                      overflow: TextOverflow.ellipsis,
                      style: tokens.dataText.copyWith(color: tokens.dim),
                    ),
                  ),
                ),
                if (canBeCopied)
                  CopyToClipboardButton(
                    value,
                    iconSize: tokens.heroCopyIconSize,
                  ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
