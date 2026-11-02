import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show splitAmount;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

// The small parts the Accelerator pages share: a pill for a status or a
// filter, a thin meter, the compact buttons of a list row, and the form
// parts of the four steppers. They belong in the shared page parts once
// another page needs them.

/// The gap between two fields of a stepper form.
const double kAccFieldGap = 14;

/// The neutral pill at the size used inside a list row: the shared
/// secondary look, smaller.
ButtonStyle accCompactQuietStyle(BuildContext context) =>
    secondaryButtonStyle(context).copyWith(
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 30)),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      textStyle: const WidgetStatePropertyAll<TextStyle>(kTextButtonTextStyle),
    );

/// The primary action at the size of a panel's title row.
ButtonStyle accCompactPrimaryStyle() => OutlinedButton.styleFrom(
  minimumSize: const Size(0, 32),
  padding: const EdgeInsets.symmetric(horizontal: 14),
  textStyle: kTextButtonTextStyle,
);

/// The colour of a status: amber is voting, the state that needs a Pillar;
/// green is accepted or paid; blue is completed; red is rejected.
Color accStatusColor(AcceleratorProjectStatus status) => switch (status) {
  AcceleratorProjectStatus.voting => AppColors.warn,
  AcceleratorProjectStatus.active => AppColors.znnColor,
  AcceleratorProjectStatus.paid => AppColors.znnColor,
  AcceleratorProjectStatus.completed => AppColors.qsrInk,
  AcceleratorProjectStatus.closed => AppColors.errorColor,
};

/// The word for a status, in sentence case.
String accStatusLabel(AcceleratorProjectStatus status) => switch (status) {
  AcceleratorProjectStatus.voting => 'Voting',
  AcceleratorProjectStatus.active => 'Accepted',
  AcceleratorProjectStatus.paid => 'Paid',
  AcceleratorProjectStatus.completed => 'Completed',
  AcceleratorProjectStatus.closed => 'Rejected',
};

/// An amount as text for a note or a step's summary: thousands grouped, no
/// trailing zeros, nothing rounded, then the symbol.
String accAmount(BigInt raw, int decimals, String symbol) =>
    '${splitAmount(raw, decimals).$1} $symbol';

/// The text colour of the theme in force. The steppers run under a theme
/// whose text styles are Material's, so the colour is read, not assumed.
Color accInkOf(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
}

/// What is typed into a stepper field. Amounts are [mono].
TextStyle accFieldTextStyle(BuildContext context, {bool mono = false}) {
  final TextStyle style = kBodyLargeTextStyle.copyWith(
    fontFamily: kSansFontFamily,
    color: accInkOf(context),
  );
  return mono ? monoStyle(style) : style;
}

/// A pill: a hairline outline, a coloured dot or an icon, a short label.
///
/// With [onPressed] it is a filter that toggles; [selected] then raises it,
/// and the change of tone is animated.
class AccChip extends StatelessWidget {
  /// Creates a pill.
  const AccChip({
    required this.label,
    this.dotColor,
    this.icon,
    this.selected = false,
    this.onPressed,
    this.tooltip,
    this.filled = false,
    super.key,
  });

  /// The text, in sentence case.
  final String label;

  /// The dot's colour, or the icon's when there is an icon.
  final Color? dotColor;

  /// Shown in place of the dot.
  final IconData? icon;

  /// Whether a filter pill is on.
  final bool selected;

  /// Makes the pill a toggle.
  final VoidCallback? onPressed;

  /// Explains the pill on hover.
  final String? tooltip;

  /// A semantic status tint, independent of the selected-filter surface.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final Color ink = selected ? accInkOf(context) : dimColorOf(context);
    final Color line = lineColorOf(context);
    Widget pill = AnimatedContainer(
      duration: Durations.short3,
      curve: Easing.standard,
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: ShapeDecoration(
        // Transparent, not null: a colour can be animated to and from.
        color: filled && dotColor != null
            ? dotColor!.withValues(alpha: 0.12)
            : selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.primaryContainer.withValues(alpha: 0),
        shape: StadiumBorder(
          side: filled
              ? BorderSide.none
              : BorderSide(color: selected ? tokens.faint : line),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: dotColor ?? ink),
            const SizedBox(width: 6),
          ] else if (dotColor != null) ...<Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: Durations.short3,
              curve: Easing.standard,
              style: kBodySmallTextStyle.copyWith(
                fontFamily: kSansFontFamily,
                fontFamilyFallback: kFontFamilyFallback,
                color: filled ? dotColor ?? ink : ink,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
    if (onPressed != null) {
      pill = Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          mouseCursor: SystemMouseCursors.click,
          onTap: onPressed,
          child: pill,
        ),
      );
    }
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

/// The status of a project or phase as a pill.
class AccStatusChip extends StatelessWidget {
  /// Creates the pill of [status].
  const AccStatusChip(this.status, {super.key});

  /// The status shown.
  final AcceleratorProjectStatus status;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Color color = switch (status) {
      AcceleratorProjectStatus.voting => tokens.qsrInk,
      AcceleratorProjectStatus.active ||
      AcceleratorProjectStatus.paid => tokens.znnInk,
      AcceleratorProjectStatus.completed => tokens.qsrInk,
      AcceleratorProjectStatus.closed => tokens.error,
    };
    final String label = switch (status) {
      AcceleratorProjectStatus.voting => context.l10n.acceleratorVoting,
      AcceleratorProjectStatus.active => context.l10n.acceleratorAccepted,
      AcceleratorProjectStatus.paid => context.l10n.acceleratorPaid,
      AcceleratorProjectStatus.completed => context.l10n.acceleratorCompleted,
      AcceleratorProjectStatus.closed => context.l10n.acceleratorRejected,
    };
    return AccChip(
      label: label,
      dotColor: color,
      filled: true,
      icon: switch (status) {
        AcceleratorProjectStatus.voting => Icons.schedule,
        AcceleratorProjectStatus.active ||
        AcceleratorProjectStatus.paid ||
        AcceleratorProjectStatus.completed => Icons.check,
        AcceleratorProjectStatus.closed => Icons.close,
      },
    );
  }
}

/// A 6 px meter: shares of a whole, left to right, on the divider tone.
///
/// A share that changes, after a vote or a payment, slides to its new
/// length; on first build it is drawn at its length, so a list that
/// scrolls does not animate every row it brings in.
class AccMeter extends StatelessWidget {
  /// Creates a meter of [parts]: fractions of the whole and their colours.
  const AccMeter({required this.parts, super.key});

  /// Each share as a fraction of the whole, with its colour.
  final List<(double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    // Each share is drawn as a layer from the left edge to where it ends,
    // the last share at the bottom, so no layout can overflow while two
    // shares animate at once.
    final List<double> ends = <double>[];
    double sum = 0;
    for (final (double share, Color _) in parts) {
      sum += share.isNaN ? 0 : share;
      ends.add(sum.clamp(0, 1).toDouble());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: ColoredBox(
          color: lineColorOf(context),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              for (int i = parts.length - 1; i >= 0; i--)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: ends[i], end: ends[i]),
                  duration: const Duration(milliseconds: 150),
                  curve: AppTokens.of(context).ease,
                  builder: (_, double end, Widget? child) =>
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: end,
                        child: child,
                      ),
                  child: ColoredBox(color: parts[i].$2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One field of a stepper form: a ledger label, an optional help mark, and
/// the field under them.
///
/// The label sits above the field, so every field of a step starts and ends
/// on the same two edges whether or not it has help.
class AccField extends StatelessWidget {
  /// Creates a labelled field.
  const AccField({
    required this.label,
    required this.child,
    this.help,
    super.key,
  });

  /// What the field holds, in sentence case; shown in capitals.
  final String label;

  /// Shown on hover of a help mark beside the label; no mark when null.
  final String? help;

  /// The field.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label.toUpperCase(), style: ledgerLabelStyle(context)),
            if (help != null) ...<Widget>[
              const SizedBox(width: 6),
              Tooltip(
                message: help,
                child: const Icon(
                  Icons.help_outline,
                  size: 14,
                  color: AppColors.faint,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// What an address holds of one coin, under the field that spends it: mono,
/// faint, no trailing zeros.
class AccBalanceLine extends StatelessWidget {
  /// Creates the line for [token] of [accountInfo].
  const AccBalanceLine(this.token, this.accountInfo, {super.key});

  /// The coin.
  final Token token;

  /// The address's balances.
  final AccountInfo accountInfo;

  @override
  Widget build(BuildContext context) {
    final BigInt balance = accountInfo.getBalance(token.tokenStandard);
    return AccHintLine(
      '${accAmount(balance, token.decimals, token.symbol)} available',
    );
  }
}

/// A figure under a field that bounds what may be typed into it: mono and
/// faint.
class AccHintLine extends StatelessWidget {
  /// Creates the line.
  const AccHintLine(this.text, {super.key});

  /// What it says: an amount and what it is.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoStyle(
          kBodySmallTextStyle.copyWith(color: AppColors.faint),
        ),
      ),
    );
  }
}

/// What a step works on, as one ledger line: a faint label, an optional
/// name, and the id in mono.
class AccIdLine extends StatelessWidget {
  /// Creates the line for [id].
  const AccIdLine({
    required this.label,
    required this.id,
    this.name,
    super.key,
  });

  /// What the id belongs to: "Project" or "Phase".
  final String label;

  /// Its name, shown before the id.
  final String? name;

  /// The id; shown shortened.
  final Hash id;

  @override
  Widget build(BuildContext context) {
    final TextStyle value = kBodySmallTextStyle.copyWith(
      fontFamily: kSansFontFamily,
      color: dimColorOf(context),
    );
    final TextStyle faint = value.copyWith(color: AppColors.faint);
    return Padding(
      padding: const EdgeInsets.only(bottom: kAccFieldGap),
      child: Tooltip(
        message: id.toString(),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '$label ', style: faint),
              if (name != null && name!.isNotEmpty) ...<InlineSpan>[
                TextSpan(text: name, style: value),
                TextSpan(text: '  ·  ', style: faint),
              ],
              TextSpan(text: 'ID ', style: faint),
              TextSpan(text: id.toShortString(), style: monoStyle(value)),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
        ),
      ),
    );
  }
}

/// The two actions under a step: the filled primary on the fields' left
/// edge, and one quiet text action beside it.
///
/// The order is set here and nowhere else, so the four steppers cannot
/// disagree.
class AccStepActions extends StatelessWidget {
  /// Creates the row. [primary] is the step's one filled button.
  const AccStepActions({
    required this.primary,
    required this.secondaryLabel,
    required this.onSecondary,
    super.key,
  });

  /// The step's main action.
  final Widget primary;

  /// The quiet action's text: "Cancel" or "Back".
  final String secondaryLabel;

  /// Runs the quiet action.
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: <Widget>[
          primary,
          const SizedBox(width: 8),
          TextButton(
            style: quietButtonStyle(context),
            onPressed: onSecondary,
            child: Text(secondaryLabel),
          ),
        ],
      ),
    );
  }
}

/// A stepper whose address balance is still loading: bars where the first
/// step's fields will be.
class AccStepperLoading extends StatelessWidget {
  /// Creates the placeholder.
  const AccStepperLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: SizedBox(width: 360, child: SkeletonRows(rows: 5, gap: 22)),
      ),
    );
  }
}

/// What every Accelerator stepper is laid out in: the steps, scrolling; and,
/// once the last step is done, the launch animation and the ways out.
class AccStepperFrame extends StatelessWidget {
  /// Creates the frame round [stepper].
  const AccStepperFrame({
    required this.stepper,
    required this.isDone,
    required this.doneLabel,
    required this.onDone,
    this.againLabel,
    this.onAgain,
    super.key,
  });

  /// The steps.
  final Widget stepper;

  /// Whether the last step has completed.
  final bool isDone;

  /// The primary way out, such as "View projects".
  final String doneLabel;

  /// Leaves the stepper.
  final VoidCallback onDone;

  /// The quiet action that starts the stepper again; none when null.
  final String? againLabel;

  /// Starts the stepper again.
  final VoidCallback? onAgain;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ListView(
          children: <Widget>[
            // The step headers are not buttons here; they take no hover.
            Theme(
              data: Theme.of(context).copyWith(
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: stepper,
            ),
          ],
        ),
        if (isDone)
          const Positioned(
            right: 50,
            child: IgnorePointer(
              child: SizedBox(
                width: 400,
                height: 400,
                child: Center(
                  // The launch animation keeps its own layer, so its frames
                  // do not repaint the stepper under it.
                  child: RepaintBoundary(child: _LaunchAnimation()),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 20,
          right: 0,
          left: 0,
          child: StateSwitcher(
            alignment: Alignment.bottomCenter,
            child: isDone
                ? Row(
                    key: const ValueKey<String>('acc_stepper_done'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (againLabel != null && onAgain != null) ...<Widget>[
                        TextButton.icon(
                          style: quietButtonStyle(context),
                          onPressed: onAgain,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(againLabel!),
                        ),
                        const SizedBox(width: 8),
                      ],
                      OutlinedButton(
                        key: const Key('acc_stepper_leave'),
                        onPressed: onDone,
                        child: Text(doneLabel),
                      ),
                    ],
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('acc_stepper_open'),
                  ),
          ),
        ),
      ],
    );
  }
}

class _LaunchAnimation extends StatelessWidget {
  const _LaunchAnimation();

  @override
  Widget build(BuildContext context) {
    return const AppLottie(AppLottieAsset.zts, size: 400, repeat: false);
  }
}
