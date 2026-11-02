import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/create_token_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/multiple_balance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Shown for a count that is not known yet. A mark, not a word.
const String _kUnknown = '-';

/// The side of the ZTS coin in the strip.
const double _kCoinSize = 64;

/// The gap between two figures, as on the Accelerator page's top row.
const double _kFigureGap = 40;

/// The top row of the Tokens page: the ZTS coin, what the address holds,
/// what a new token costs, and the page's one primary action.
///
/// It was a card of its own, as tall as the balances beside it, for one
/// button. As a strip it leaves the height to the list.
class CreateTokenCard extends StatelessWidget {
  /// Creates the strip.
  const CreateTokenCard({
    required this._onStepperNotificationSeeMorePressed,
    super.key,
  });

  final VoidCallback _onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 24, 0),
      child: _View(
        onStepperNotificationSeeMorePressed:
            _onStepperNotificationSeeMorePressed,
      ),
    );
  }
}

class _View extends StatefulWidget {
  const _View({required this.onStepperNotificationSeeMorePressed});

  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> with SingleTickerProviderStateMixin {
  // The coin turns once when the page opens, and once more each time the
  // pointer reaches it or the button: it answers, it does not loop.
  late final AnimationController _coin = AnimationController(vsync: this);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        MouseRegion(
          onEnter: (_) => _turnCoin(),
          // On its own layer: a turn of the coin repaints 64 px, not the page.
          child: AppLottie(
            AppLottieAsset.zts,
            controller: _coin,
            size: _kCoinSize,
            onLoaded: (LottieComposition composition) {
              _coin.duration = composition.duration;
              _turnCoin();
            },
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(child: _Figures()),
        const SizedBox(width: 16),
        MouseRegion(
          onEnter: (_) => _turnCoin(),
          child: OutlinedButton.icon(
            key: const Key('tokens_create'),
            onPressed: _openStepper,
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.l10n.createTokenOpenLabel),
          ),
        ),
      ],
    );
  }

  void _turnCoin() {
    if (_coin.duration != null && !_coin.isAnimating) {
      _coin.forward(from: 0);
    }
  }

  void _openStepper() {
    final SendTransactionBloc sender = context.read<SendTransactionBloc>();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => StepperScreen(
          stepper: CreateTokenStepperPage(sender: sender),
          onStepperNotificationSeeMorePressed:
              widget.onStepperNotificationSeeMorePressed,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _coin.dispose();
    super.dispose();
  }
}

class _Figures extends StatelessWidget {
  const _Figures();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          // Only the count is read, so a refresh that changes no count
          // rebuilds nothing here.
          child: BlocSelector<MultipleBalanceBloc, MultipleBalanceState, int?>(
            selector: _tokensHeld,
            builder: (BuildContext context, int? held) {
              final Figure figure = Figure(
                key: const Key('tokens_figure_held'),
                label: context.l10n.createTokenHeldLabel,
                value: held?.toString() ?? _kUnknown,
              );
              // Not while unknown: the first answer is not a change.
              return held == null
                  ? figure
                  : ValueFlash(value: held, child: figure);
            },
          ),
        ),
        const SizedBox(width: _kFigureGap),
        Flexible(
          child: Figure(
            label: context.l10n.createTokenFeeLabel,
            value: cardAmount(
              tokenZtsIssueFeeInZnn,
              coinDecimals,
              kZnnCoin.symbol,
            ),
          ),
        ),
      ],
    );
  }

  /// How many ZTS tokens the selected address holds; null until known.
  static int? _tokensHeld(MultipleBalanceState state) {
    final List<BalanceInfoListItem>? balances =
        state.data?[kSelectedAddress]?.balanceInfoList;
    if (balances == null) {
      return null;
    }
    return balances
        .where(
          (BalanceInfoListItem item) =>
              item.token != null &&
              item.token!.tokenStandard != kZnnCoin.tokenStandard &&
              item.token!.tokenStandard != kQsrCoin.tokenStandard,
        )
        .length;
  }
}
