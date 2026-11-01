import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/select_address.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/hero_field.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/plasma_meter.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/clipboard_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

part 'home_hero_balances.dart';
part 'home_hero_controls.dart';
part 'home_hero_plasma.dart';

/// One address's balances, available plasma and transfer entry points.
///
/// The page owns its snapshot and navigation. Keeping this surface separate
/// lets the activity and side cards change without altering the money header.
class HomeHero extends StatefulWidget {
  /// Draws the current [snapshot], retaining it through a failed refresh.
  const HomeHero({
    required this.address,
    required this.snapshot,
    required this.failed,
    required this.onOpenTransfer,
    this.visibility,
    this.priceFeed,
    this.powStatus,
    super.key,
  });

  /// The selected address, whose label and switcher use the wallet's state.
  final String address;

  /// The last successful read, or null before one has arrived.
  final HomeSnapshot? snapshot;

  /// Whether the node's last read failed.
  final bool failed;

  /// Opens the selected mode of the session's existing Transfer page.
  final ValueChanged<TransferMode> onOpenTransfer;

  /// The shared privacy choice; the wallet's notifier when omitted.
  final BalanceVisibility? visibility;

  /// The existing feed; injectable so isolated previews need no network.
  final PriceFeed? priceFeed;

  /// Owned generation displays; the wallet's live stream by default.
  final Stream<PowGenerationState>? powStatus;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  // One original player keeps its state across privacy and responsive layouts.
  final GlobalKey<State<EyeToggle>> _eyeKey = GlobalKey<State<EyeToggle>>();

  @override
  Widget build(BuildContext context) {
    final BalanceVisibility balances =
        widget.visibility ?? BalanceVisibility.instance;
    final PriceFeed prices = widget.priceFeed ?? PriceFeed.instance;
    final AppTokens tokens = AppTokens.of(context);
    return Panel(
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: IgnorePointer(child: HeroField())),
          Padding(
            padding: tokens.heroPadding,
            child: ListenableBuilder(
              listenable: balances,
              builder: (BuildContext context, Widget? child) => LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double scale = math.max(
                    1,
                    MediaQuery.textScalerOf(context).scale(
                          tokens.heroAmountText.fontSize!,
                        ) /
                        tokens.heroAmountText.fontSize!,
                  );
                  final Widget balancesColumn = _buildBalances(
                    context,
                    balances,
                    prices,
                  );
                  final double plasmaWidth = math.min(
                    tokens.heroPlasmaWidth * scale,
                    constraints.maxWidth,
                  );
                  final double actionsWidth = _actionsWidth(context);
                  final Widget plasma = SizedBox(
                    width: plasmaWidth,
                    child: _HomeHeroPlasma(
                      snapshot: widget.snapshot,
                      status: widget.powStatus ??
                          sl.get<PowGeneratingStatusBloc>().stream,
                    ),
                  );
                  final Widget actions = _HomeHeroActions(
                    onOpenTransfer: widget.onOpenTransfer,
                  );
                  // Keep the measured desktop row at normal type size. Larger
                  // text gets another line instead of clipping an amount or
                  // making one of the actions unreachable.
                  final double requiredWidth =
                      _balanceWidth(context, balances.hidden) +
                      tokens.heroPlasmaWidth * scale +
                      actionsWidth +
                      2 * tokens.heroGap;
                  if (constraints.maxWidth < requiredWidth) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        balancesColumn,
                        SizedBox(height: tokens.heroStackGap),
                        Wrap(
                          spacing: tokens.heroGap,
                          runSpacing: tokens.heroStackGap,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[plasma, actions],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      // Keep the reference balance group at its natural
                      // width, with unused space before the transfer actions.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth -
                              plasmaWidth - actionsWidth - 2 * tokens.heroGap,
                        ),
                        child: balancesColumn,
                      ),
                      SizedBox(width: tokens.heroGap),
                      plasma,
                      SizedBox(width: tokens.heroGap),
                      const Spacer(),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _balanceWidth(BuildContext context, bool hidden) {
    final HomeSnapshot? current = widget.snapshot;
    if (current == null) return 0;
    final AppTokens tokens = AppTokens.of(context);
    // A large holding must not lose its final base unit to the headline's
    // fade. Hidden layout is measured from dots, never from the hidden value.
    final double znn = _textWidth(
      context,
      hidden
          ? kHiddenAmountDots
          : splitAmount(current.znn, kZnnCoin.decimals).$1,
      tokens.heroAmountText.copyWith(
        letterSpacing: hidden
            ? tokens.heroAmountText.fontSize! * tokens.hiddenAmountTrackingEm
            : tokens.heroAmountText.letterSpacing,
      ),
    );
    final double qsr = _textWidth(
      context,
      hidden
          ? kHiddenAmountDots
          : splitAmount(current.qsr, kQsrCoin.decimals).$1,
      tokens.heroSecondaryAmountText.copyWith(
        letterSpacing: hidden
            ? tokens.heroSecondaryAmountText.fontSize! *
                  tokens.hiddenAmountTrackingEm
            : tokens.heroSecondaryAmountText.letterSpacing,
      ),
    );
    final TextStyle symbol = tokens.heroSymbolText;
    final double hiddenEyeWidth = hidden
        ? tokens.heroHiddenEyeGap + tokens.heroHiddenEyeSlotWidth
        : 0;
    final double znnGap = hidden
        ? _homeHiddenSymbolGap(context, tokens.heroAmountText)
        : tokens.heroSymbolGap;
    final double qsrGap = hidden
        ? _homeHiddenSymbolGap(context, tokens.heroSecondaryAmountText)
        : tokens.heroSymbolGap;
    return math.max(
      znn + znnGap + _textWidth(context, kZnnCoin.symbol, symbol) +
          hiddenEyeWidth,
      qsr + qsrGap + _textWidth(context, kQsrCoin.symbol, symbol),
    );
  }

  double _actionsWidth(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle style = tokens.buttonText;
    return _textWidth(context, context.l10n.send, style) +
        _textWidth(context, context.l10n.receive, style) +
        _textWidth(context, context.l10n.transferZap, style) +
        // Per action: horizontal padding, icon and label gap. Two row gaps.
        3 *
            (tokens.heroActionPadding.horizontal +
                tokens.heroIconSize +
                tokens.inlineGap) +
        2 * tokens.heroActionGap;
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  Widget _buildBalances(
    BuildContext context,
    BalanceVisibility balances,
    PriceFeed prices,
  ) {
    final HomeSnapshot? current = widget.snapshot;
    final AppTokens tokens = AppTokens.of(context);
    final bool inAmountRow = balances.hidden && current != null;
    final Widget eye = EyeToggle(
      key: _eyeKey,
      keyPrefix: 'home',
      tooltip: balances.hidden
          ? context.l10n.homeShowBalances
          : context.l10n.displayHideBalances,
      visibility: balances,
      size: inAmountRow
          ? tokens.heroHiddenEyeSize
          : tokens.heroAddressIconSize,
      padding: EdgeInsets.zero,
    );
    return Column(
      key: const Key('home_hero_balances'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _HomeHeroAddress(
          address: widget.address,
          eye: inAmountRow ? null : eye,
        ),
        SizedBox(height: tokens.heroBalanceGap),
        if (current == null)
          Text(
            widget.failed
                ? context.l10n.homeNodeNotAnswering
                : context.l10n.homeLoading,
            key: const Key('home_hero_status'),
            style: tokens.heroLoadingText,
          )
        else
          _HomeHeroBalances(
            snapshot: current,
            visibility: balances,
            feed: prices,
            eye: inAmountRow ? eye : null,
          ),
      ],
    );
  }
}
