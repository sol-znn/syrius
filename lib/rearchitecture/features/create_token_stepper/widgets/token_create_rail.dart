import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_preflight.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The four real stages and the captured fee facts beside the live draft.
class TokenCreateRail extends StatelessWidget {
  /// No standard is invented for a token that has not been issued.
  const TokenCreateRail({
    required this.step,
    required this.preflight,
    required this.name,
    required this.symbol,
    required this.onRetry,
    this.busy = false,
    super.key,
  });

  /// One of exactly four visible step marks.
  final int step;

  /// Fresh original account facts, with explicit unknown states.
  final TokenCreatePreflight preflight;

  /// Text still being edited in the retained name field.
  final String name;

  /// Text still being edited in the retained symbol field.
  final String symbol;

  /// Reads again only after an explicit user action.
  final VoidCallback onRetry;

  /// A pending action closes the retry control.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<String> labels = <String>[
      context.l10n.tokenCreateNameAndSymbol,
      context.l10n.tokensSupply,
      context.l10n.tokenCreateOptions,
      context.l10n.tokenCreateIssue,
    ];
    final BigInt? balance = preflight.znn;
    final bool current = preflight.isCurrent;
    final String status = !current
        ? context.l10n.publicationSessionChanged
        : preflight.failed
        ? context.l10n.commonSomethingWentWrong
        : preflight.plasma == null
        ? context.l10n.homeAmountUnknown
        : preflight.plasma! < kIssueTokenPlasmaAmountNeeded
        ? context.l10n.sendNotEnough(context.l10n.plasma)
        : balance != null && balance < tokenZtsIssueFeeInZnn
        ? context.l10n.sendNotEnough(kZnnCoin.symbol)
        : context.l10n.sufficientPlasma;
    return Container(
      key: const Key('token_create_rail'),
      width: tokens.registrationRailWidth,
      decoration: BoxDecoration(
        border: BorderDirectional(end: BorderSide(color: tokens.line)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.registrationInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tokens.tokenCreateRailGap,
          children: <Widget>[
            Column(
              spacing: tokens.registrationActionGap,
              children: <Widget>[
                for (int i = 0; i < labels.length; i++)
                  Row(
                    key: ValueKey<String>('token_create_step_$i'),
                    children: <Widget>[
                      Container(
                        width: tokens.tokenCreateStepMarkSize,
                        height: tokens.tokenCreateStepMarkSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == step ? tokens.znn : tokens.card3,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: tokens.dataText.copyWith(
                            color: i == step ? tokens.onZnn : tokens.dim,
                          ),
                        ),
                      ),
                      SizedBox(width: tokens.inlineGap),
                      Expanded(
                        child: Text(
                          labels[i],
                          style: tokens.registrationCaptionText.copyWith(
                            color: i == step ? tokens.znnInk : tokens.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Divider(color: tokens.line),
            Column(
              spacing: tokens.registrationGap,
              children: <Widget>[
                _Fact(
                  label: context.l10n.tokenCreateFee,
                  value: Wrap(
                    spacing: tokens.inlineGap,
                    children: <Widget>[
                      AmountText(
                        tokenZtsIssueFeeInZnn,
                        decimals: coinDecimals,
                        symbol: kZnnCoin.symbol,
                        style: tokens.dataText,
                      ),
                      Text(
                        context.l10n.tokenCreateBurned,
                        style: tokens.registrationCaptionText,
                      ),
                    ],
                  ),
                ),
                _Fact(
                  label: context.l10n.tokenCreateHave,
                  value: balance == null
                      ? Text('-', style: tokens.dataText)
                      : AmountText(
                          balance,
                          decimals: coinDecimals,
                          symbol: kZnnCoin.symbol,
                          style: tokens.dataText,
                        ),
                ),
                Row(
                  children: <Widget>[
                    Icon(
                      preflight.loading
                          ? Icons.hourglass_empty
                          : preflight.sufficient
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: tokens.tokenCreateStepMarkSize,
                      color: preflight.sufficient ? tokens.znnInk : tokens.dim,
                    ),
                    SizedBox(width: tokens.inlineGap),
                    Expanded(
                      child: Text(
                        status,
                        style: tokens.registrationCaptionText,
                      ),
                    ),
                  ],
                ),
                if (current)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('token_create_retry'),
                      onPressed: busy || preflight.loading ? null : onRetry,
                      child: Text(
                        preflight.failed
                            ? context.l10n.commonRetry
                            : context.l10n.commonRefresh,
                      ),
                    ),
                  ),
              ],
            ),
            Container(
              padding: EdgeInsets.all(tokens.pageGap),
              decoration: BoxDecoration(
                color: tokens.card2,
                borderRadius: BorderRadius.circular(tokens.cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: tokens.inlineGap,
                children: <Widget>[
                  Text(
                    context.l10n.tokenCreatePreview.toUpperCase(),
                    style: tokens.ledgerText,
                  ),
                  Row(
                    children: <Widget>[
                      Icon(Icons.token_outlined, color: tokens.pinkInk),
                      SizedBox(width: tokens.inlineGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.bodyText,
                            ),
                            Text(
                              symbol,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: tokens.dataText.copyWith(
                                color: tokens.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: Text(
          label,
          style: AppTokens.of(context).registrationCaptionText,
        ),
      ),
      Flexible(flex: 2, child: value),
    ],
  );
}
