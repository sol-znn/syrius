import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Balances and published-block status beside Home's activity.
///
/// The session owns collection admission, results and unresolved attempts.
/// Rebuilding or leaving this view cannot start a second collection. [flight]
/// must be the originating wallet and chain's published-block registry, never
/// the list of inbound blocks that can be received.
/// Give this view a new key when its wallet, chain or selected address changes.
class HomeSideCards extends StatelessWidget {
  /// Draws the last real snapshot and the session's exact published hashes.
  const HomeSideCards({
    required this.snapshot,
    required this.collectEnabled,
    required this.collectBusy,
    required this.onCollectAll,
    required this.flight,
    this.failed = false,
    this.collectionNotice,
    this.visibility,
    this.priceFeed,
    super.key,
  });

  /// The last successful read, absent before a real answer has arrived.
  final HomeSnapshot? snapshot;

  /// Whether the session owner can admit another collection now.
  final bool collectEnabled;

  /// The session's shared hold, including its unresolved collection attempt.
  final bool collectBusy;

  /// Requests collection from the existing owner, which rechecks admission.
  final VoidCallback? onCollectAll;

  /// Unresolved node-accepted publications for the current wallet and chain.
  final ValueListenable<List<InFlightBlock>> flight;

  /// A failed refresh retains its figures but cannot admit collection.
  final bool failed;

  /// A factual notice about an unresolved attempt, retained by the owner.
  final String? collectionNotice;

  /// The shared privacy setting; injectable for isolated widget checks.
  final BalanceVisibility? visibility;

  /// The existing shared price feed, with no price source added by this view.
  final PriceFeed? priceFeed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final BalanceVisibility balances = visibility ?? BalanceVisibility.instance;
    return ValueListenableBuilder<List<InFlightBlock>>(
      valueListenable: flight,
      builder:
          (BuildContext context, List<InFlightBlock> blocks, Widget? child) =>
              CustomScrollView(
                key: const Key('home_side_cards'),
                primary: false,
                slivers: <Widget>[
                  SliverToBoxAdapter(child: child),
                  if (blocks.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsetsDirectional.only(top: tokens.pageGap),
                      sliver: SliverLayoutBuilder(
                        builder:
                            (
                              BuildContext context,
                              SliverConstraints constraints,
                            ) => SliverToBoxAdapter(
                              child: _PendingCard(
                                blocks: blocks,
                                visibility: balances,
                                minimumOpenHeight: math.max(
                                  0,
                                  constraints.viewportMainAxisExtent -
                                      constraints.precedingScrollExtent,
                                ),
                              ),
                            ),
                      ),
                    ),
                ],
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CollectCard(
            snapshot: snapshot,
            failed: failed,
            enabled: collectEnabled,
            busy: collectBusy,
            onCollect: onCollectAll,
            notice: collectionNotice,
            visibility: balances,
            priceFeed: priceFeed ?? PriceFeed.instance,
          ),
          SizedBox(height: tokens.pageGap),
          _TokensCard(
            snapshot: snapshot,
            failed: failed,
            visibility: balances,
          ),
        ],
      ),
    );
  }
}

class _CollectCard extends StatelessWidget {
  const _CollectCard({
    required this.snapshot,
    required this.failed,
    required this.enabled,
    required this.busy,
    required this.onCollect,
    required this.notice,
    required this.visibility,
    required this.priceFeed,
  });

  final HomeSnapshot? snapshot;
  final bool failed;
  final bool enabled;
  final bool busy;
  final VoidCallback? onCollect;
  final String? notice;
  final BalanceVisibility visibility;
  final PriceFeed priceFeed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final HomeSnapshot? current = snapshot;
    BigInt znn = BigInt.zero;
    BigInt qsr = BigInt.zero;
    if (current != null) {
      for (final UncollectedReward reward in current.rewards.values) {
        znn += reward.znnAmount;
        qsr += reward.qsrAmount;
      }
    }
    final bool any = znn > BigInt.zero || qsr > BigInt.zero;
    final bool canCollect =
        current != null && any && !failed && enabled && !busy && notice == null;
    final Widget summary = current == null
        ? Text(
            failed
                ? context.l10n.homeNodeNotAnswering
                : context.l10n.homeLoading,
            key: const Key('home_collect_status'),
            style: tokens.compactText.copyWith(color: tokens.dim),
          )
        : !any
        ? Text(
            context.l10n.homeNoneYet,
            key: const Key('home_collect_empty'),
            style: tokens.compactText.copyWith(color: tokens.dim),
          )
        : _CollectAmounts(
            key: const Key('home_collect_amounts'),
            znn: znn,
            qsr: qsr,
            visibility: visibility,
            priceFeed: priceFeed,
          );
    final Widget button = Semantics(
      value: busy ? context.l10n.homeLoading : null,
      child: OutlinedButton(
        key: const Key('home_collect_all'),
        onPressed: canCollect ? onCollect : null,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: Size(0, tokens.compactButtonHeight),
          padding: tokens.homeSideButtonPadding,
          textStyle: tokens.compactText,
          foregroundColor: tokens.foreground,
          disabledForegroundColor: tokens.faint,
          side: BorderSide(color: tokens.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.pillRadius),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(context.l10n.homeCollectAll),
            if (busy) ...<Widget>[
              SizedBox(width: tokens.inlineGap),
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: tokens.compactText.fontSize,
                  child: CircularProgressIndicator(
                    strokeWidth: tokens.focusWidth,
                    color: tokens.dim,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Panel(
      key: const Key('home_collect_card'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: tokens.homeSideHeaderPadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    tokens.homeSideHeaderHeight -
                    tokens.homeSideHeaderPadding.vertical,
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget title = Text(
                    context.l10n.homeToCollect,
                    style: panelTitleStyle(context),
                  );
                  final double controls =
                      _textWidth(
                        context,
                        context.l10n.homeToCollect,
                        panelTitleStyle(context),
                      ) +
                      _textWidth(
                        context,
                        context.l10n.homeCollectAll,
                        tokens.compactText,
                      ) +
                      tokens.homeSideButtonPadding.horizontal +
                      (busy
                          ? tokens.inlineGap + tokens.compactText.fontSize!
                          : 0) +
                      2 * tokens.inlineGap;
                  // Ordinary figures stay on the mockup's one line. Large type
                  // keeps the action reachable and gives exact amounts room.
                  if (constraints.maxWidth <
                      controls + 2 * tokens.compactButtonHeight) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(child: title),
                            SizedBox(width: tokens.inlineGap),
                            button,
                          ],
                        ),
                        SizedBox(height: tokens.homeTokenRowGap),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _HorizontalSummary(child: summary),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      title,
                      SizedBox(width: tokens.inlineGap),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _HorizontalSummary(child: summary),
                        ),
                      ),
                      SizedBox(width: tokens.inlineGap),
                      button,
                    ],
                  );
                },
              ),
            ),
          ),
          if (notice case final String message)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: tokens.homeSideHeaderPadding.start,
                end: tokens.homeSideHeaderPadding.end,
                bottom: tokens.homeSideHeaderPadding.bottom,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  key: const Key('home_collection_notice'),
                  style: tokens.compactText.copyWith(color: tokens.dim),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }
}

/// The full amount remains scrollable when a holding outgrows the side column.
class _HorizontalSummary extends StatelessWidget {
  const _HorizontalSummary({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: false,
    scrollDirection: Axis.horizontal,
    child: child,
  );
}

class _CollectAmounts extends StatelessWidget {
  const _CollectAmounts({
    required this.znn,
    required this.qsr,
    required this.visibility,
    required this.priceFeed,
    super.key,
  });

  final BigInt znn;
  final BigInt qsr;
  final BalanceVisibility visibility;
  final PriceFeed priceFeed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<CoinAmount> amounts = <CoinAmount>[
      if (znn > BigInt.zero)
        (amount: znn, decimals: kZnnCoin.decimals, coin: PricedCoin.znn),
      if (qsr > BigInt.zero)
        (amount: qsr, decimals: kQsrCoin.decimals, coin: PricedCoin.qsr),
    ];
    return ListenableBuilder(
      listenable: priceFeed,
      builder: (BuildContext context, Widget? child) => ListenableBuilder(
        listenable: visibility,
        builder: (BuildContext context, Widget? child) => Ltr(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (znn > BigInt.zero)
                _SideAmount(
                  key: const Key('home_collect_znn'),
                  amount: znn,
                  decimals: kZnnCoin.decimals,
                  symbol: kZnnCoin.symbol,
                  visibility: visibility,
                ),
              if (znn > BigInt.zero && qsr > BigInt.zero)
                Padding(
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: tokens.homeTokenRowGap,
                  ),
                  child: Text('·', style: tokens.homeSideAmountText),
                ),
              if (qsr > BigInt.zero)
                _SideAmount(
                  key: const Key('home_collect_qsr'),
                  amount: qsr,
                  decimals: kQsrCoin.decimals,
                  symbol: kQsrCoin.symbol,
                  visibility: visibility,
                ),
              if (amounts.every(
                (CoinAmount part) => priceFeed.priceOf(part.coin!) != null,
              )) ...<Widget>[
                SizedBox(width: tokens.inlineGap),
                DollarText.sum(
                  amounts,
                  key: const Key('home_collect_dollars'),
                  hidden: visibility.hidden,
                  feed: priceFeed,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SideAmount extends StatelessWidget {
  const _SideAmount({
    required this.amount,
    required this.decimals,
    required this.symbol,
    required this.visibility,
    super.key,
  });

  final BigInt amount;
  final int decimals;
  final String symbol;
  final BalanceVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ValueFlash(
          value: amount,
          child: HiddenAmount(
            visibility: visibility,
            style: tokens.homeSideAmountText,
            child: AmountText(
              amount,
              decimals: decimals,
              style: tokens.homeSideAmountText,
            ),
          ),
        ),
        SizedBox(width: tokens.heroSymbolGap),
        Text(symbol, style: tokens.compactText.copyWith(color: tokens.dim)),
      ],
    );
  }
}

class _TokensCard extends StatelessWidget {
  const _TokensCard({
    required this.snapshot,
    required this.failed,
    required this.visibility,
  });

  final HomeSnapshot? snapshot;
  final bool failed;
  final BalanceVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<BalanceInfoListItem> rows =
        snapshot?.tokens ?? const <BalanceInfoListItem>[];
    return Panel(
      key: const Key('home_tokens_card'),
      child: Disclosure(
        title: context.l10n.tokens,
        count: snapshot == null ? null : rows.length,
        keyPrefix: 'home_tokens',
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.line)),
          ),
          child: Padding(
            padding: tokens.cardPadding,
            child: Column(
              key: const Key('home_tokens_body'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (snapshot == null)
                  Text(
                    failed
                        ? context.l10n.homeNodeNotAnswering
                        : context.l10n.homeLoading,
                    style: tokens.compactText.copyWith(color: tokens.dim),
                  )
                else if (rows.isEmpty)
                  Text(
                    context.l10n.homeNoneYet,
                    style: tokens.compactText.copyWith(color: tokens.dim),
                  )
                else
                  for (int i = 0; i < rows.length; i++) ...<Widget>[
                    if (i != 0) SizedBox(height: tokens.homeTokenRowGap),
                    _TokenRow(
                      key: ValueKey<String>(
                        'home_token_'
                        '${rows[i].token?.tokenStandard ?? 'unknown_$i'}',
                      ),
                      item: rows[i],
                      visibility: visibility,
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({
    required this.item,
    required this.visibility,
    super.key,
  });

  final BalanceInfoListItem item;
  final BalanceVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Token? token = item.token;
    final String? standard = token?.tokenStandard.toString();
    final String symbol = token?.symbol ?? '';
    final String name = standard == null
        ? context.l10n.assetCellUnknownStandardTooltip
        : symbol.isNotEmpty
        ? symbol
        : standard.length <= 14
        ? standard
        : '${standard.substring(0, 8)}…'
              '${standard.substring(standard.length - 6)}';
    final BigInt? amount = item.balance;
    final int? decimals = token?.decimals;
    final bool known =
        amount != null && decimals != null && decimals >= 0 && decimals <= 255;
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: tokens.homeTokenBadgeSize,
            height: tokens.homeTokenBadgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.pink,
            ),
            child: Text(
              symbol.isEmpty ? '?' : String.fromCharCode(symbol.runes.first),
              style: tokens.homeTokenBadgeText,
            ),
          ),
        ),
        SizedBox(width: tokens.cardGap),
        Expanded(
          child: Tooltip(
            message: standard ?? context.l10n.assetCellUnknownStandardTooltip,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: symbol.isEmpty ? tokens.dataText : tokens.bodyText,
            ),
          ),
        ),
        SizedBox(width: tokens.inlineGap),
        Flexible(
          child: Ltr(
            child: _HorizontalSummary(
              child: ValueFlash(
                key: ValueKey<bool>(known),
                value: known ? amount : null,
                child: HiddenAmount(
                  visibility: visibility,
                  alignment: AlignmentDirectional.centerEnd,
                  style: tokens.homeSideAmountText,
                  child: known
                      ? AmountText(
                          amount,
                          decimals: decimals,
                          style: tokens.homeSideAmountText.copyWith(
                            color: tokens.foreground,
                          ),
                        )
                      : Text(
                          context.l10n.homeAmountUnknown,
                          style: tokens.homeSideAmountText,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingCard extends StatefulWidget {
  const _PendingCard({
    required this.blocks,
    required this.visibility,
    required this.minimumOpenHeight,
  });

  final List<InFlightBlock> blocks;
  final BalanceVisibility visibility;
  final double minimumOpenHeight;

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard>
    with SingleTickerProviderStateMixin {
  final DisclosureController _disclosure = DisclosureController(open: true);
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
    // The extra height follows the disclosure even when OS motion is off.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void dispose() {
    _disclosure.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _fill,
      builder: (BuildContext context, Widget? child) => ConstrainedBox(
        // Fill the remaining column at rest, while long lists keep their
        // natural height. Closing follows the same clock as the real body.
        constraints: BoxConstraints(
          minHeight:
              tokens.homeSideHeaderHeight +
              math.max(
                    0,
                    widget.minimumOpenHeight - tokens.homeSideHeaderHeight,
                  ) *
                  tokens.spring.transform(_fill.value),
        ),
        child: child,
      ),
      child: Panel(
        key: const Key('home_pending_card'),
        child: Disclosure(
          title: context.l10n.homePending,
          count: widget.blocks.length,
          controller: _disclosure,
          onChanged: (bool open) {
            if (open) {
              _fill.forward();
            } else {
              _fill.reverse();
            }
          },
          keyPrefix: 'home_pending',
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.line)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < widget.blocks.length; i++) ...<Widget>[
                  if (i != 0) Divider(height: 1, color: tokens.line),
                  _PendingRow(
                    key: ValueKey<String>(
                      'home_pending_${widget.blocks[i].hash}',
                    ),
                    block: widget.blocks[i],
                    visibility: widget.visibility,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.block,
    required this.visibility,
    super.key,
  });

  final InFlightBlock block;
  final BalanceVisibility visibility;

  static const String _amountSlot = '\u{FFFC}';

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final int? decimals = block.decimals;
    final String? symbol = block.symbol;
    final bool known =
        block.amount > BigInt.zero &&
        decimals != null &&
        decimals >= 0 &&
        decimals <= 255 &&
        symbol != null &&
        symbol.trim().isNotEmpty;
    final List<String> around = context.l10n
        .stripSending(_amountSlot)
        .split(
          _amountSlot,
        );
    final Widget description = known
        ? Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(around.first, style: tokens.compactText),
              Ltr(
                child: _SideAmount(
                  amount: block.amount,
                  decimals: decimals,
                  symbol: symbol,
                  visibility: visibility,
                ),
              ),
              if (around.length > 1)
                Text(around.last, style: tokens.compactText),
            ],
          )
        : Text(
            context.l10n.stripWaitingConfirmation,
            style: tokens.compactText.copyWith(color: tokens.dim),
          );
    return Padding(
      padding: tokens.cardPadding,
      child: Tooltip(
        message: block.hash.toString(),
        child: Row(
          children: <Widget>[
            Icon(
              known ? Icons.north_east_rounded : Icons.schedule_rounded,
              size: tokens.heroIconSize,
              color: tokens.dim,
            ),
            SizedBox(width: tokens.inlineGap),
            Expanded(child: _HorizontalSummary(child: description)),
            if (known) ...<Widget>[
              SizedBox(width: tokens.inlineGap),
              Tooltip(
                message: context.l10n.stripWaitingConfirmation,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.qsr.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(tokens.pillRadius),
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: tokens.inlineGap,
                      vertical: tokens.heroBalanceGap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.schedule_rounded,
                          size: tokens.heroCopyIconSize,
                          color: tokens.qsrInk,
                        ),
                        SizedBox(width: tokens.heroBalanceGap),
                        Text(
                          context.l10n.homePendingMomentum,
                          style: tokens.captionText.copyWith(
                            color: tokens.qsrInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
