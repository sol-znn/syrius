import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// What the Pillars and Sentinels pages and their steppers share: the node
/// animation, the loading and countdown pieces of the cards, and the parts a
/// step of a stepper is made of.
///
/// Imported by path. It is not in `features.dart` because nothing outside
/// these two pages needs it.

/// The widest a step's form grows. A field that spans a 1500 px window is
/// harder to read than one the length of what goes in it.
const double kStepMaxWidth = 520;

/// The space between two blocks of a step: a group of fields, a note, the
/// buttons.
const double kStepGap = 16;

/// The edge of the node animation on a card.
const double kNodeObjectSize = 104;

/// The pillar or sentinel animation, kept from the old interface.
///
/// It plays once. It sits on its own layer, so the frames it paints while it
/// plays do not repaint the card round it.
class NodeObject extends StatelessWidget {
  /// The pillar.
  const NodeObject.pillar({this.size = kNodeObjectSize, super.key})
    : _asset = AppLottieAsset.pillar;

  /// The sentinel.
  const NodeObject.sentinel({this.size = kNodeObjectSize, super.key})
    : _asset = AppLottieAsset.sentinel;

  final AppLottieAsset _asset;

  /// Its width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    return AppLottie(_asset, size: size, repeat: false);
  }
}

/// A card that is waiting for its first answer: bars where its rows will be.
class NodeCardSkeleton extends StatelessWidget {
  /// Creates [rows] bars in the card's padding.
  const NodeCardSkeleton({this.rows = 3, this.padding, super.key});

  /// How many bars.
  final int rows;

  /// Round the bars; the card body's padding when null.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: padding ?? kCardBodyPadding,
        child: SkeletonRows(rows: rows),
      ),
    );
  }
}

/// A `Figure` whose value has not arrived: its label over a bar the size of
/// the value, so the strip keeps its height.
class FigureSkeleton extends StatelessWidget {
  /// Creates the placeholder under [label].
  const FigureSkeleton({required this.label, super.key});

  /// The figure's label; shown in capitals.
  final String label;

  static const double _width = 120;

  /// The line height of a figure's 20 px value.
  static const double _valueHeight = 26;
  static const double _barHeight = 14;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label.toUpperCase(), style: ledgerLabelStyle(context)),
        const SizedBox(height: 4),
        const SizedBox(
          height: _valueHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Skeleton(width: _width, height: _barHeight),
          ),
        ),
      ],
    );
  }
}

/// The body of a card, cross-fading between its states: loading, populated,
/// empty, error.
///
/// [state] names the state shown; the fade runs when it changes and not
/// when the same state is rebuilt with new data.
class CardStates extends StatelessWidget {
  /// Creates the body showing [child] for [state].
  const CardStates({
    required this.state,
    required this.child,
    this.fill = true,
    super.key,
  });

  /// What tells one state from another: an enum value, a type, a word.
  final Object state;

  /// The state's widget.
  final Widget child;

  /// Whether each state takes the whole body. False where the body has no
  /// fixed height, such as inside a scroll view.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final ValueKey<Object> key = ValueKey<Object>(state);
    return StateSwitcher(
      child: fill
          ? SizedBox.expand(key: key, child: child)
          : KeyedSubtree(key: key, child: child),
    );
  }
}

/// A state as a dot and a word: green when [on], red when not.
class StatusDot extends StatelessWidget {
  /// Creates the mark.
  const StatusDot({required this.on, required this.label, super.key});

  /// Whether the thing is in its good state.
  final bool on;

  /// The word beside the dot.
  final String label;

  static const double _size = 8;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedContainer(
          duration: Durations.medium1,
          curve: Easing.standard,
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AppColors.znnColor : AppColors.errorColor,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: cardValueStyle(context)),
      ],
    );
  }
}

/// How long until a pillar or sentinel can be disassembled, or how long the
/// window stays open: a ledger label over the time, in mono.
///
/// It replaces the red and green bordered pill. The time counts down every
/// second; [onFinished] is called once when it reaches zero, so the owner
/// can read the new window.
class RevokeCountdown extends StatefulWidget {
  /// Creates a countdown of [seconds].
  const RevokeCountdown({
    required this.seconds,
    required this.open,
    required this.onFinished,
    this.alignment = CrossAxisAlignment.center,
    super.key,
  });

  /// Seconds left when the value was read from the chain.
  final int seconds;

  /// Whether the revocation window is open now.
  final bool open;

  /// Called once, when the time runs out.
  final VoidCallback onFinished;

  /// Where the label and the time sit across the widget.
  final CrossAxisAlignment alignment;

  @override
  State<RevokeCountdown> createState() => _RevokeCountdownState();
}

class _RevokeCountdownState extends State<RevokeCountdown> {
  static const Duration _tick = Duration(seconds: 1);

  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(RevokeCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds || oldWidget.open != widget.open) {
      _left = widget.seconds;
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    if (_left <= 0) return;
    _timer = Timer.periodic(_tick, (Timer timer) {
      if (!mounted) return;
      setState(() => _left -= 1);
      if (_left <= 0) {
        timer.cancel();
        widget.onFinished();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.alignment,
      children: <Widget>[
        Text(
          widget.open ? 'REVOCABLE FOR' : 'REVOCABLE IN',
          style: ledgerLabelStyle(context),
        ),
        const SizedBox(height: 4),
        Text(
          // The days while it is far off, then the clock.
          FormatUtils.formatCountdownClock(
            context.l10n,
            Duration(seconds: _left),
          ),
          maxLines: 1,
          style: monoStyle(cardValueStyle(context)).copyWith(
            color: widget.open ? AppColors.znnColor : null,
          ),
        ),
      ],
    );
  }
}

/// One step of a stepper: its blocks in a column no wider than
/// [kStepMaxWidth], [kStepGap] apart, with the fields looking as they do on
/// a card and Tab going through them before it leaves the step.
class StepBody extends StatelessWidget {
  /// Creates a step of [children].
  const StepBody({required this.children, super.key});

  /// The blocks, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: CardFields(
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kStepMaxWidth),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: kStepGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < children.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: kStepGap),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A step that is waiting for the chain.
class StepLoading extends StatelessWidget {
  /// Creates the loading state.
  const StepLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const StepBody(children: <Widget>[SkeletonRows()]);
  }
}

/// A step that could not read what it needs.
class StepError extends StatelessWidget {
  /// Creates the state for [error].
  const StepError(this.error, {super.key});

  /// What went wrong.
  final Object error;

  @override
  Widget build(BuildContext context) {
    return StepBody(
      children: <Widget>[
        Text(
          cardErrorText(error),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: cardDimStyle(context),
        ),
      ],
    );
  }
}

/// A line of a step: a ledger label on the left, a value on the right.
class StepLine extends StatelessWidget {
  /// Creates the line.
  const StepLine({required this.label, required this.value, super.key});

  /// Says what the value is; shown in capitals.
  final String label;

  /// The value.
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(label.toUpperCase(), style: ledgerLabelStyle(context)),
        const SizedBox(width: kCardGap),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: value),
        ),
      ],
    );
  }
}

/// The address a step acts for: its label when it has one, and the address
/// in mono. The whole address is in the tooltip.
///
/// It was a disabled text field, which looked like something to fill in.
class StepAddress extends StatelessWidget {
  /// Creates the line for [address].
  const StepAddress(this.address, {super.key});

  /// The address, in full.
  final String address;

  @override
  Widget build(BuildContext context) {
    final String? name = kAddressLabelMap[address];
    final String short = address.length > 12 ? address.short : address;
    return StepLine(
      label: 'Address',
      value: Tooltip(
        message: address,
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              if (name != null && name != address)
                TextSpan(text: '$name  ', style: cardValueStyle(context)),
              TextSpan(
                text: short,
                style: monoStyle(cardDimStyle(context)),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// An amount on a [StepLine]: mono, no trailing zeros, the symbol in the
/// token's ink. It flashes once when the amount changes.
class StepAmountLine extends StatelessWidget {
  /// Creates the line.
  const StepAmountLine({
    required this.label,
    required this.amount,
    required this.decimals,
    required this.symbol,
    required this.ink,
    super.key,
  });

  /// Says what the amount is.
  final String label;

  /// The amount in the smallest unit.
  final BigInt amount;

  /// The token's decimals.
  final int decimals;

  /// The token's symbol.
  final String symbol;

  /// The symbol's colour.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return StepLine(
      label: label,
      value: ValueFlash(
        value: amount,
        color: ink,
        child: AmountText(
          amount,
          decimals: decimals,
          style: cardValueStyle(context),
          symbol: symbol,
          symbolColor: ink,
        ),
      ),
    );
  }
}

/// How much of a cost has been deposited: the two amounts, the share, and a
/// bar that moves to the new share when a deposit lands.
class DepositProgress extends StatelessWidget {
  /// Creates the progress of [deposited] towards [cost].
  const DepositProgress({
    required this.deposited,
    required this.cost,
    required this.decimals,
    required this.symbol,
    required this.ink,
    super.key,
  });

  /// What is deposited so far, in the smallest unit.
  final BigInt deposited;

  /// What the slot costs, in the smallest unit.
  final BigInt cost;

  /// The token's decimals.
  final int decimals;

  /// The token's symbol.
  final String symbol;

  /// The colour of the bar and of the symbol.
  final Color ink;

  static const double _barHeight = 6;

  /// The share deposited, 0 to 1. A slot with no cost is fully paid.
  double get _share {
    if (cost <= BigInt.zero) return 1;
    final double share = deposited / cost;
    return share.isNaN ? 0 : share.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final double share = _share;
    final TextStyle value = cardValueStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text('DEPOSITED', style: ledgerLabelStyle(context)),
            const SizedBox(width: kCardGap),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ValueFlash(
                  value: deposited,
                  color: ink,
                  child: Text.rich(
                    TextSpan(
                      style: monoStyle(value),
                      children: <InlineSpan>[
                        TextSpan(text: cardAmount(deposited, decimals, '')),
                        TextSpan(
                          text: ' / ${cardAmount(cost, decimals, '')}',
                          style: const TextStyle(color: AppColors.faint),
                        ),
                        TextSpan(
                          text: ' $symbol',
                          style: TextStyle(
                            fontFamily: kSansFontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: kCardGap),
            SizedBox(
              width: 44,
              child: Text(
                '${(share * 100).floor()}%',
                textAlign: TextAlign.right,
                style: monoStyle(value).copyWith(
                  color: share >= 1 ? AppColors.znnColor : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: share),
          duration: Durations.long2,
          curve: Easing.standard,
          builder: (BuildContext context, double shown, _) =>
              LinearProgressIndicator(
                value: shown,
                minHeight: _barHeight,
                borderRadius: BorderRadius.circular(_barHeight / 2),
                color: shown >= 1 ? AppColors.znnColor : ink,
                backgroundColor: cardLineColor(context),
              ),
        ),
      ],
    );
  }
}

/// The look of a step's second button (Back, Cancel, Withdraw): a line
/// round plain text, so the step keeps one filled button.
///
/// `cardSecondaryButtonStyle` fills with the theme's container colour, which
/// in the steppers' own theme is a seeded green; here the fill is left out.
ButtonStyle stepSecondaryButtonStyle(BuildContext context, {Color? line}) =>
    cardSecondaryButtonStyle(context, line: line).copyWith(
      backgroundColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(64, AppTokens.of(context).buttonHeight),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        kOutlinedButtonTextStyle,
      ),
    );

/// The buttons of a step: the one filled action first, then the quiet ones.
class StepActions extends StatelessWidget {
  /// Creates the row.
  const StepActions({
    required this.primary,
    this.secondary = const <Widget>[],
    super.key,
  });

  /// The step's one main action.
  final Widget primary;

  /// OutlinedButtons that go back, cancel or undo; drawn as lines.
  final List<Widget> secondary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: kCardGap,
      runSpacing: kCardGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        primary,
        if (secondary.isNotEmpty)
          OutlinedButtonTheme(
            data: OutlinedButtonThemeData(
              style: stepSecondaryButtonStyle(context),
            ),
            child: Wrap(
              spacing: kCardGap,
              runSpacing: kCardGap,
              children: secondary,
            ),
          ),
      ],
    );
  }
}

/// The end of a stepper: the node animation, one line saying what happened,
/// an optional link, and the way on.
class StepDone extends StatelessWidget {
  /// Creates the closing state.
  const StepDone({
    required this.object,
    required this.title,
    required this.actions,
    this.note,
    super.key,
  });

  /// The pillar or sentinel animation.
  final Widget object;

  /// What happened, in a few words.
  final String title;

  /// A line under the title, such as a link to the next thing to do.
  final Widget? note;

  /// The way on: one primary, the rest secondary.
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          object,
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: panelTitleStyle(context),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 6),
            note!,
          ],
          const SizedBox(height: kStepGap),
          actions,
        ],
      ),
    );
  }
}
