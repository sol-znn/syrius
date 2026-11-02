import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_collect_button.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Provides what [PillarCollect] needs: the selected address's uncollected
/// pillar rewards, and a bloc to send the collect block.
///
/// It wraps the whole rewards card rather than the strip alone, so the
/// card's refresh button reaches the uncollected amount too.
class PillarCollectScope extends StatelessWidget {
  /// Creates the scope around [child].
  const PillarCollectScope({required this.child, this.sender, super.key});

  /// The rewards card.
  final Widget child;

  /// Nodes shares the shell's existing admission instead of creating another.
  final SendTransactionBloc? sender;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<UncollectedPillarRewardsBloc>(
          create: (_) => UncollectedPillarRewardsBloc(zenon: zenon!)
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

/// What the selected address can collect as a pillar, and the button that
/// collects it. The head of the pillar rewards card; it was a card of its
/// own, which spent a third of the row on one number.
class PillarCollect extends StatelessWidget {
  /// Creates the strip. Needs a [PillarCollectScope] above it.
  const PillarCollect({super.key});

  @override
  Widget build(BuildContext context) {
    const String label = 'To collect';
    return BlocBuilder<
      UncollectedPillarRewardsBloc,
      FetchState<UncollectedReward>
    >(
      builder: (_, FetchState<UncollectedReward> state) {
        final BigInt znn = state is FetchPopulated<UncollectedReward>
            ? state.data.znnAmount
            : BigInt.zero;
        return CardCollect(
          figures: <Widget>[
            switch (state) {
              FetchInitial<UncollectedReward>() => const Figure(
                label: label,
                value: '',
              ),
              FetchFailure<UncollectedReward>() => Figure(
                label: label,
                value: cardErrorText(state.exception),
                valueStyle: cardDimStyle(context),
              ),
              FetchPopulated<UncollectedReward>() => cardAmountFigure(
                context,
                label: label,
                amount: znn,
                decimals: kZnnCoin.decimals,
                symbol: kZnnCoin.symbol,
                ink: AppColors.znnColor,
              ),
            },
          ],
          button: NodeCollectButton(
            enabled:
                state is FetchPopulated<UncollectedReward> &&
                (state.data.znnAmount > BigInt.zero ||
                    state.data.qsrAmount > BigInt.zero),
            source: NodeRewardSource.pillar,
          ),
        );
      },
    );
  }
}

/// The existing collection action for the compact Nodes strip.
///
/// It shares the same owned result and refresh path as [PillarCollect], so a
/// strip does not introduce a second implementation of collection.
class PillarCollectAction extends StatelessWidget {
  /// Creates the action under a [PillarCollectScope].
  const PillarCollectAction({required this.enabled, super.key});

  /// True only when a known reward contains an amount to collect.
  final bool enabled;

  @override
  Widget build(BuildContext context) => NodeCollectButton(
    enabled: enabled,
    source: NodeRewardSource.pillar,
  );
}
