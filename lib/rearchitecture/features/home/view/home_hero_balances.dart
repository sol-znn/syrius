part of 'home_hero.dart';

// Measure one interior mono space with the mask's tracking and text scale.
// The width never depends on the private amount or trailing-space trimming.
double _homeHiddenSymbolGap(BuildContext context, TextStyle amountStyle) {
  final AppTokens tokens = AppTokens.of(context);
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: '0 0',
      style: monoStyle(amountStyle).copyWith(
        letterSpacing:
            amountStyle.fontSize! * tokens.hiddenAmountTrackingEm,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final ui.TextBox space = painter.getBoxesForSelection(
    const TextSelection(baseOffset: 1, extentOffset: 2),
  ).single;
  final double width = space.right - space.left;
  painter.dispose();
  return width;
}

class _HomeHeroBalances extends StatelessWidget {
  const _HomeHeroBalances({
    required this.snapshot,
    required this.visibility,
    required this.feed,
    this.eye,
  });

  final HomeSnapshot snapshot;
  final BalanceVisibility visibility;
  final PriceFeed feed;
  final Widget? eye;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return ListenableBuilder(
      // This listener starts the shared feed before its first answer. Dollar
      // children exist only when priced, so their gaps also disappear when
      // Display turns dollars off. Leaving Home removes every listener.
      listenable: feed,
      builder: (BuildContext context, Widget? child) => ListenableBuilder(
        listenable: visibility,
        builder: (BuildContext context, Widget? child) {
          final bool znnPriced = feed.priceOf(PricedCoin.znn) != null;
          final bool qsrPriced = feed.priceOf(PricedCoin.qsr) != null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _HomeHeroBalanceLine(
                keyPrefix: 'home_znn',
                amount: snapshot.znn,
                decimals: kZnnCoin.decimals,
                symbol: kZnnCoin.symbol,
                symbolColor: tokens.znnInk,
                coin: PricedCoin.znn,
                primary: true,
                eye: eye,
                priced: znnPriced,
                visibility: visibility,
                feed: feed,
              ),
              SizedBox(height: tokens.heroBalanceGap),
              _HomeHeroBalanceLine(
                keyPrefix: 'home_qsr',
                amount: snapshot.qsr,
                decimals: kQsrCoin.decimals,
                symbol: kQsrCoin.symbol,
                symbolColor: tokens.qsrInk,
                coin: PricedCoin.qsr,
                primary: false,
                priced: qsrPriced,
                visibility: visibility,
                feed: feed,
              ),
              if (znnPriced && qsrPriced) ...<Widget>[
                SizedBox(height: tokens.heroBalanceGap),
                DollarText.sum(
                  <CoinAmount>[
                    (
                      amount: snapshot.znn,
                      decimals: kZnnCoin.decimals,
                      coin: PricedCoin.znn,
                    ),
                    (
                      amount: snapshot.qsr,
                      decimals: kQsrCoin.decimals,
                      coin: PricedCoin.qsr,
                    ),
                  ],
                  key: const Key('home_total_dollars'),
                  hidden: visibility.hidden,
                  color: tokens.dim,
                  feed: feed,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HomeHeroBalanceLine extends StatelessWidget {
  const _HomeHeroBalanceLine({
    required this.keyPrefix,
    required this.amount,
    required this.decimals,
    required this.symbol,
    required this.symbolColor,
    required this.coin,
    required this.primary,
    required this.priced,
    required this.visibility,
    required this.feed,
    this.eye,
  });

  final String keyPrefix;
  final BigInt amount;
  final int decimals;
  final String symbol;
  final Color symbolColor;
  final PricedCoin coin;
  final bool primary;
  final bool priced;
  final BalanceVisibility visibility;
  final PriceFeed feed;
  final Widget? eye;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle amountStyle = primary
        ? tokens.heroAmountText
        : tokens.heroSecondaryAmountText;
    return Wrap(
      spacing: visibility.hidden
          ? tokens.heroHiddenEyeGap
          : tokens.heroDollarGap,
      runSpacing: tokens.heroBalanceRunGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Ltr(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: ValueFlash(
                  value: amount,
                  color: primary ? null : tokens.qsrInk,
                  child: HiddenAmount(
                    key: ValueKey<String>('${keyPrefix}_value'),
                    visibility: visibility,
                    style: amountStyle,
                    child: AmountText(
                      amount,
                      key: ValueKey<String>(keyPrefix),
                      decimals: decimals,
                      style: amountStyle,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: visibility.hidden
                    ? _homeHiddenSymbolGap(context, amountStyle)
                    : tokens.heroSymbolGap,
              ),
              Text(
                symbol,
                key: ValueKey<String>('${keyPrefix}_symbol'),
                style: tokens.heroSymbolText.copyWith(color: symbolColor),
              ),
            ],
          ),
        ),
        if (eye case final Widget control)
          SizedBox(
            key: const Key('home_hidden_eye_slot'),
            width: tokens.heroHiddenEyeSlotWidth,
            height: tokens.heroHiddenEyeSize,
            child: Center(child: control),
          ),
        if (priced && !visibility.hidden)
          DollarText(
            key: ValueKey<String>('${keyPrefix}_dollars'),
            amount: amount,
            decimals: decimals,
            coin: coin,
            hidden: visibility.hidden,
            feed: feed,
          ),
      ],
    );
  }
}
