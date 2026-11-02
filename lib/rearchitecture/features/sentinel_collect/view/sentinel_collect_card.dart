import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_collect_button.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Provides what [SentinelCollect] needs: the selected address's uncollected
/// sentinel rewards, and a bloc to send the collect block.
///
/// It wraps the whole rewards card rather than the strip alone, so the
/// card's refresh button reaches the uncollected amounts too.
class SentinelCollectScope extends StatelessWidget {
  /// Creates the scope around [child].
  const SentinelCollectScope({required this.child, this.sender, super.key});

  /// The rewards card.
  final Widget child;

  /// The shell owns the sender supplied by the retained Nodes page.
  final SendTransactionBloc? sender;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<UncollectedSentinelRewardsBloc>(
          create: (_) => UncollectedSentinelRewardsBloc(zenon: zenon!)
            ..add(
              FetchRequestData(address: Address.parse(kSelectedAddress!)),
            ),
        ),
        if (sender case final SendTransactionBloc value)
          BlocProvider<SendTransactionBloc>.value(value: value)
        else
          BlocProvider<SendTransactionBloc>(
            create: (_) => SendTransactionBloc(),
          ),
      ],
      child: child,
    );
  }
}

/// What the selected address can collect as a sentinel, in ZNN and QSR, and
/// the button that collects it. The head of the sentinel rewards card.
class SentinelCollect extends StatelessWidget {
  /// Creates the strip. Needs a [SentinelCollectScope] above it.
  const SentinelCollect({super.key});

  @override
  Widget build(BuildContext context) {
    const String label = 'To collect';
    final AppTokens tokens = AppTokens.of(context);
    return BlocBuilder<
      UncollectedSentinelRewardsBloc,
      FetchState<UncollectedReward>
    >(
      builder: (_, FetchState<UncollectedReward> state) {
        final UncollectedReward? due =
            state is FetchPopulated<UncollectedReward> ? state.data : null;
        final bool any =
            due != null &&
            (due.znnAmount > BigInt.zero || due.qsrAmount > BigInt.zero);
        return CardCollect(
          figures: <Widget>[
            if (state is FetchFailure<UncollectedReward>)
              Figure(
                label: label,
                value: cardErrorText(state.exception),
                valueStyle: cardDimStyle(context),
              )
            else ...<Widget>[
              // The label is said once, over the first figure.
              _CollectFigure(
                coin: 'znn',
                label: label,
                amount: due?.znnAmount,
                decimals: kZnnCoin.decimals,
                symbol: kZnnCoin.symbol,
                ink: tokens.znnInk,
              ),
              _CollectFigure(
                coin: 'qsr',
                label: '',
                amount: due?.qsrAmount,
                decimals: kQsrCoin.decimals,
                symbol: kQsrCoin.symbol,
                ink: tokens.qsrInk,
              ),
            ],
          ],
          button: NodeCollectButton(
            enabled: any,
            source: NodeRewardSource.sentinel,
          ),
        );
      },
    );
  }
}

/// One coin of the strip: a bar while the amounts load, then the amount,
/// which flashes when a refresh or a collect changes it.
class _CollectFigure extends StatelessWidget {
  const _CollectFigure({
    required this.coin,
    required this.label,
    required this.amount,
    required this.decimals,
    required this.symbol,
    required this.ink,
  });

  /// Tells the two flashes apart.
  final String coin;
  final String label;

  /// Null until the amounts arrive.
  final BigInt? amount;
  final int decimals;
  final String symbol;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final BigInt? amount = this.amount;
    final bool known = amount != null;
    return ValueFlash(
      // A flash per load state: the first value is not a change.
      key: ValueKey<(String, bool)>((coin, known)),
      value: amount,
      color: ink,
      child: known
          ? cardAmountFigure(
              context,
              label: label,
              amount: amount,
              decimals: decimals,
              symbol: symbol,
              ink: ink,
            )
          : FigureSkeleton(label: label),
    );
  }
}

/// The existing collection action for the compact Nodes strip.
///
/// Only the original collect handle can notify or refresh the reward chart.
class SentinelCollectAction extends StatelessWidget {
  /// Creates the action under a [SentinelCollectScope].
  const SentinelCollectAction({required this.enabled, super.key});

  /// True only when a known reward contains an amount to collect.
  final bool enabled;

  @override
  Widget build(BuildContext context) => NodeCollectButton(
    enabled: enabled,
    source: NodeRewardSource.sentinel,
  );
}
