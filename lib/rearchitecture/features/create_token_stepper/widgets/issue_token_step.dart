import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The width of the labels of the review, so the values start on one edge.
/// The longest, "Burnable by any holder", fits in capitals.
const double _kReviewLabelWidth = 176;

/// Final step: what was chosen, the fee, and the action that issues the
/// token.
class IssueTokenStep extends StatefulWidget {
  /// Creates an [IssueTokenStep].
  const IssueTokenStep({
    required this.onBackPressed,
    required this.onIssueDone,
    required this.onIssuePressed,
    required this.tokenData,
    this.active = true,
    this.onPublished,
    this.isCurrent,
    this.registrationRun = 0,
    super.key,
  });

  /// Called when the user wants to go back.
  final VoidCallback onBackPressed;

  /// Called after the issue operation succeeds.
  final VoidCallback onIssueDone;

  /// Retains the original result before optional favorite persistence yields.
  final ValueChanged<RegistrationPublication>? onPublished;

  /// The originating registration context can suppress stale optional display.
  final bool Function()? isCurrent;

  /// Changes only on the explicit Create another token action.
  final int registrationRun;

  /// Called when the user presses create.
  final VoidCallback onIssuePressed;

  /// Token data draft updated by this step.
  final ValueNotifier<NewTokenData> tokenData;

  /// Whether this is the step shown.
  final bool active;

  @override
  State<IssueTokenStep> createState() => _IssueTokenStepState();
}

class _IssueTokenStepState extends State<IssueTokenStep> {
  GlobalKey<LoadingButtonState> _createButtonKey = GlobalKey();

  // From the press until the bloc has failed, or the stepper has moved on.
  // The bloc's own state will not do: it still says done when the stepper
  // is run a second time.
  bool _isSending = false;
  bool _accepted = false;
  String? _submittedName;

  @override
  void didUpdateWidget(IssueTokenStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registrationRun != widget.registrationRun) {
      _accepted = false;
      _isSending = false;
      _createButtonKey = GlobalKey<LoadingButtonState>();
      _submittedName = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<IssueTokenBloc, IssueTokenState>(
      listener: (_, IssueTokenState state) => _onIssueTokenStateChanged(state),
      child: ValueListenableBuilder<NewTokenData>(
        valueListenable: widget.tokenData,
        builder: (BuildContext context, NewTokenData data, _) {
          final AppTokens tokens = AppTokens.of(context);
          return TokenStepFrame(
            active: widget.active,
            busy: _isSending,
            onBack: widget.onBackPressed,
            onSubmit: _isSending || _accepted ? null : _onIssuePressed,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Review(data),
                SizedBox(height: tokens.cardGap),
                TokenStepToggle(
                  checkboxKey: const Key('token_utility_checkbox'),
                  label: context.l10n.utilityToken,
                  help: context.l10n.tokenStatusUtilityTooltip,
                  value: data.isUtility,
                  onChanged: (bool value) {
                    widget.tokenData.value = widget.tokenData.value.copyWith(
                      isUtility: value,
                    );
                  },
                ),
                SizedBox(height: tokens.cardGap),
                DottedBorderInfoWidget(
                  text: context.l10n.burnTokenIssueFee(
                    cardAmount(tokenZtsIssueFeeInZnn, coinDecimals, ''),
                    kZnnCoin.symbol,
                  ),
                  borderColor: tokens.znnInk,
                ),
              ],
            ),
            primary: KeyedSubtree(
              key: const Key('token_create_button'),
              child: LoadingButton(
                onPressed: _accepted ? null : _onIssuePressed,
                text: context.l10n.create,
                circularBorderRadius: kLoadingButtonMinSize.height / 2,
                key: _createButtonKey,
              ),
            ),
          );
        },
      ),
    );
  }

  void _onIssuePressed() {
    if (_isSending ||
        _accepted ||
        !widget.active ||
        !(widget.isCurrent?.call() ?? true)) {
      return;
    }
    _submittedName = widget.tokenData.value.tokenName;
    setState(() {
      _isSending = true;
    });
    widget.onIssuePressed();
  }

  void _onIssueTokenStateChanged(IssueTokenState state) {
    if (_accepted) return;
    if (state is IssueTokenLoading) {
      _createButtonKey.currentState?.animateForward();
      setState(() {
        _isSending = true;
      });
    } else if (state is IssueTokenDone) {
      _accepted = true;
      final String name = _submittedName ?? widget.tokenData.value.tokenName;
      final bool Function()? isCurrent = widget.isCurrent;
      try {
        widget.onPublished?.call(
          RegistrationPublication(accountBlock: state.accountBlock, name: name),
        );
      } on Object {
        // Receipt display cannot replace the accepted result in the bloc.
      }
      _createButtonKey.currentState?.animateReverse();
      setState(() => _isSending = false);
      try {
        widget.onIssueDone();
      } on Object {
        // An optional UI callback cannot turn acceptance into a send failure.
      }
      unawaited(
        _onIssueTokenDone(
          context: context,
          tokenStandard: state.newTokenStandard,
          tokenName: name,
          isCurrent: isCurrent,
        ),
      );
    } else if (state is IssueTokenFailure) {
      _createButtonKey.currentState?.animateReverse();
      setState(() {
        _isSending = false;
      });
      unawaited(
        NotificationUtils.sendNotificationError(
          state.exception,
          context.l10n.errorCreatingToken,
        ),
      );
    }
  }

  Future<void> _onIssueTokenDone({
    required BuildContext context,
    required TokenStandard tokenStandard,
    required String tokenName,
    required bool Function()? isCurrent,
  }) async {
    try {
      if (!context.mounted || !(isCurrent?.call() ?? true)) return;
      await context.read<FavoriteTokensRepository>().add(tokenStandard);
    } on Object catch (error) {
      if (context.mounted && (isCurrent?.call() ?? true)) {
        try {
          await NotificationUtils.sendNotificationError(
            error,
            context.l10n.errorAddingTokenToFavorites(
              tokenName,
            ),
          );
        } on Object {
          // A favorite error display cannot replace accepted issuance.
        }
      }
    }
  }
}

/// Every value chosen in the steps before, and what issuing costs.
class _Review extends StatelessWidget {
  const _Review(this.data);

  final NewTokenData data;

  @override
  Widget build(BuildContext context) {
    final TextStyle text = accFieldTextStyle(context);
    final TextStyle mono = accFieldTextStyle(context, mono: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ReviewRow(
          label: context.l10n.address,
          value: Tooltip(
            message: data.address,
            child: Text(
              data.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: ltrTextAlign(context),
              style: mono,
            ),
          ),
        ),
        _ReviewRow(
          label: context.l10n.tokenName,
          value: _ReviewText(data.tokenName, style: text),
        ),
        _ReviewRow(
          label: context.l10n.tokenSymbol,
          value: _ReviewText(data.tokenSymbol, style: text),
        ),
        _ReviewRow(
          label: context.l10n.tokenDomain,
          value: _ReviewText(data.tokenDomain, style: text),
        ),
        _ReviewRow(
          label: context.l10n.createTokenDecimalsLabel,
          value: _ReviewText('${data.decimals}', style: mono),
        ),
        // The token has no standard until it is issued, so its symbol takes
        // the text colour.
        _ReviewRow(
          label: context.l10n.totalSupply,
          value: AmountText(
            data.totalSupply,
            decimals: data.decimals,
            style: text,
            symbol: data.tokenSymbol,
          ),
        ),
        _ReviewRow(
          label: context.l10n.maxSupply,
          value: AmountText(
            data.maxSupply,
            decimals: data.decimals,
            style: text,
            symbol: data.tokenSymbol,
          ),
        ),
        _ReviewRow(
          label: context.l10n.mintable,
          value: _ReviewText(
            data.isMintable ? context.l10n.yes : context.l10n.no,
            style: text,
          ),
        ),
        _ReviewRow(
          label: context.l10n.burnableToken,
          value: _ReviewText(
            data.isBurnable ? context.l10n.yes : context.l10n.no,
            style: text,
          ),
        ),
        _ReviewRow(
          label: context.l10n.createTokenFeeLabel,
          value: AmountText(
            tokenZtsIssueFeeInZnn,
            decimals: coinDecimals,
            style: text,
            symbol: kZnnCoin.symbol,
            symbolColor: cardTokenInk(kZnnCoin.tokenStandard, context),
          ),
        ),
      ],
    );
  }
}

/// One line of the review: a ledger label, then its value.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _kReviewLabelWidth,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ledgerLabelStyle(context),
            ),
          ),
          SizedBox(width: AppTokens.of(context).cardGap),
          Expanded(child: value),
        ],
      ),
    );
  }
}

/// A value of the review that is a word or a name.
class _ReviewText extends StatelessWidget {
  const _ReviewText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
