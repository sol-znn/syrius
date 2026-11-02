import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/entry_field.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// The measured entry card, independent of file, seed and wallet owners.
class EntryCardSurface extends StatelessWidget {
  /// Lays out an entry step using the shared card and step-ledger tokens.
  const EntryCardSurface({
    required this.title,
    required this.steps,
    required this.step,
    required this.onBack,
    required this.child,
    required this.marker,
    this.footer,
    this.background,
    this.quiz = false,
    super.key,
  });

  /// Localized heading for the current entry step.
  final String title;

  /// Localized ordered labels shared by this entry flow.
  final List<String> steps;

  /// Zero-based position of the currently displayed step.
  final int step;

  /// The original entry owner's guarded back action.
  final VoidCallback onBack;

  /// The step's controls, without constructing another entry owner.
  final Widget child;

  /// Stable card identity used by presentation and comparison fixtures.
  final Key marker;

  /// Optional current-step progress and continuation controls.
  final Widget? footer;

  /// Optional inert backdrop for isolated presentation fixtures.
  final Widget? background;

  /// Uses quiz spacing while retaining the same shared entry-card surface.
  final bool quiz;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          background ?? const EntryField(),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: tokens.lockPagePadding,
                        child: Center(
                          child: Container(
                            key: marker,
                            width: tokens.entryCardWidth,
                            padding: tokens.entryCardPadding,
                            decoration: BoxDecoration(
                              color: tokens.card,
                              border: Border.all(color: tokens.line),
                              borderRadius: BorderRadius.circular(
                                tokens.cardRadius,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: quiz
                                  ? tokens.entryQuizGap
                                  : tokens.entryGap,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    TextButton.icon(
                                      key: const Key('entry_back'),
                                      style: quietButtonStyle(context).copyWith(
                                        visualDensity: VisualDensity.standard,
                                        minimumSize:
                                            WidgetStatePropertyAll<Size>(
                                              Size(0, tokens.smallButtonHeight),
                                            ),
                                        padding:
                                            WidgetStatePropertyAll<
                                              EdgeInsetsGeometry
                                            >(tokens.entryBackPadding),
                                        textStyle:
                                            WidgetStatePropertyAll<TextStyle>(
                                              tokens.captionText.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: onBack,
                                      icon: Icon(
                                        Icons.chevron_left,
                                        size: tokens.welcomeChevronSize,
                                      ),
                                      label: Text(context.l10n.entryBack),
                                    ),
                                    SizedBox(width: tokens.entryHeadingGap),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: tokens.entryHeadingText,
                                      ),
                                    ),
                                  ],
                                ),
                                EntryStepPosition(steps: steps, step: step),
                                child,
                                ?footer,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal step ledger that wraps whole labels when text grows.
class EntryStepPosition extends StatelessWidget {
  /// Displays completed, current and future positions without owning actions.
  const EntryStepPosition({required this.steps, required this.step, super.key});

  /// Localized ordered labels for the entry flow.
  final List<String> steps;

  /// Zero-based current position, after the already completed steps.
  final int step;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<Widget> items = <Widget>[
      for (int index = 0; index < steps.length; index++)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: tokens.entryStepSize,
              height: tokens.entryStepSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < step ? tokens.znn : null,
                border: Border.all(
                  color: index <= step ? tokens.znn : tokens.line,
                ),
              ),
              child: Center(
                child: index < step
                    ? Icon(
                        Icons.check,
                        color: tokens.onZnn,
                        size: tokens.welcomeChevronSize,
                      )
                    : Text(
                        '${index + 1}',
                        style: tokens.entryStepNumberText.copyWith(
                          color: index == step ? tokens.znnInk : tokens.faint,
                        ),
                      ),
              ),
            ),
            SizedBox(width: tokens.entryStepGap),
            Flexible(
              child: Text(
                steps[index],
                style: tokens.entryStepText.copyWith(
                  color: index == step ? tokens.foreground : tokens.faint,
                ),
              ),
            ),
          ],
        ),
    ];
    return Padding(
      padding: tokens.entryStepPadding,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double requiredWidth =
              (steps.length - 1) *
              (tokens.entryStepLineMinWidth + 2 * tokens.entryStepLineInset);
          for (final String label in steps) {
            final TextPainter measure = TextPainter(
              text: TextSpan(text: label, style: tokens.entryStepText),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            requiredWidth +=
                tokens.entryStepSize + tokens.entryStepGap + measure.width;
            measure.dispose();
          }
          if (constraints.maxWidth < requiredWidth) {
            return Wrap(
              spacing: tokens.entryStepLineInset,
              runSpacing: tokens.entryStepGap,
              children: items,
            );
          }
          return Row(
            children: <Widget>[
              for (int index = 0; index < items.length; index++) ...<Widget>[
                if (index > 0)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.symmetric(
                        horizontal: tokens.entryStepLineInset,
                      ),
                      child: Divider(color: tokens.line, height: 1),
                    ),
                  ),
                items[index],
              ],
            ],
          );
        },
      ),
    );
  }
}
