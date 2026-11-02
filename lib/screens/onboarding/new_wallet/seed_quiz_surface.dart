import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_card_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

/// A three-row quiz view that cannot construct a wallet or generate a seed.
class SeedQuizSurface extends StatelessWidget {
  /// Presents the existing quiz and actions without deriving private material.
  const SeedQuizSurface({
    required this.quiz,
    required this.onSelected,
    required this.onBack,
    required this.onContinue,
    this.background,
    super.key,
  });

  /// The owner's validated snapshot, or null for an unavailable original seed.
  final SeedQuiz? quiz;

  /// Sends a question index and one of that question's displayed choices.
  final void Function(int, String) onSelected;

  /// The guarded action returning to the existing seed owner.
  final VoidCallback onBack;

  /// The guarded next-step action, absent until all answers are correct.
  final VoidCallback? onContinue;

  /// Optional inert background for isolated presentation fixtures.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final SeedQuiz? current = quiz;
    return EntryCardSurface(
      marker: const Key('seed_quiz_screen_marker'),
      quiz: true,
      title: context.l10n.seedQuizTitle,
      steps: <String>[
        context.l10n.seedQuizSeed,
        context.l10n.seedQuizConfirm,
        context.l10n.password,
        context.l10n.entryReady,
      ],
      step: 1,
      onBack: onBack,
      background: background,
      footer: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: tokens.entryGap,
        runSpacing: tokens.entryGap,
        children: <Widget>[
          Text(
            context.l10n.seedQuizProgress(current?.correct ?? 0),
            style: tokens.entryFooterText,
          ),
          PrimaryPill(
            key: const Key('seed_quiz_continue'),
            onPressed: onContinue,
            child: Text(context.l10n.continueText),
          ),
        ],
      ),
      child: current == null
          ? Text(
              context.l10n.seedQuizInvalid,
              style: tokens.entryFooterText.copyWith(color: tokens.error),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: tokens.seedQuizRowGap,
              children: <Widget>[
                for (
                  int index = 0;
                  index < current.questions.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) Divider(color: tokens.line, height: 1),
                  _buildQuestion(context, tokens, current, index),
                ],
                if (current.selected(current.unlocked) != null &&
                    !current.complete)
                  Text(
                    context.l10n.seedQuizInvalid,
                    style: tokens.entryFooterText.copyWith(color: tokens.error),
                  ),
              ],
            ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    AppTokens tokens,
    SeedQuiz current,
    int index,
  ) {
    final SeedQuizQuestion question = current.questions[index];
    final bool enabled = index <= current.unlocked;
    final Widget choices = enabled
        ? Wrap(
            spacing: tokens.seedQuizChoiceGap,
            runSpacing: tokens.seedQuizChoiceGap,
            children: <Widget>[
              for (int choice = 0; choice < question.choices.length; choice++)
                _SeedChoice(
                  key: ValueKey<String>('seed_quiz_${index}_$choice'),
                  word: question.choices[choice],
                  selected: current.selected(index) == question.choices[choice],
                  onPressed: () => onSelected(index, question.choices[choice]),
                ),
            ],
          )
        : Text(
            '…',
            style: tokens.seedQuizChoiceText.copyWith(color: tokens.faint),
          );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget label = Text(
          context.l10n.seedQuizWord(question.position + 1),
          style: tokens.dataText.copyWith(
            color: enabled ? tokens.foreground : tokens.dim,
          ),
        );
        final TextPainter labelMeasure = TextPainter(
          text: TextSpan(
            text: context.l10n.seedQuizWord(question.position + 1),
            style: tokens.dataText,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        double requiredWidth = labelMeasure.width + tokens.seedQuizChoiceGap;
        labelMeasure.dispose();
        if (enabled) {
          requiredWidth +=
              (question.choices.length - 1) * tokens.seedQuizChoiceGap;
          for (final String word in question.choices) {
            final TextPainter measure = TextPainter(
              text: TextSpan(text: word, style: tokens.seedQuizChoiceText),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            requiredWidth +=
                measure.width + tokens.seedQuizChoicePadding.horizontal;
            measure.dispose();
          }
        }
        if (constraints.maxWidth < requiredWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: tokens.seedQuizChoiceGap,
            children: <Widget>[label, choices],
          );
        }
        return Row(
          children: <Widget>[
            label,
            SizedBox(width: tokens.seedQuizChoiceGap),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: choices,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SeedChoice extends StatelessWidget {
  const _SeedChoice({
    required this.word,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String word;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.standard,
        minimumSize: Size(0, tokens.seedQuizChoiceHeight),
        padding: tokens.seedQuizChoicePadding,
        foregroundColor: selected ? tokens.foreground : tokens.dim,
        backgroundColor: selected ? tokens.card2 : Colors.transparent,
        side: BorderSide(color: selected ? tokens.faint : tokens.line),
        textStyle: tokens.seedQuizChoiceText,
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(word),
    );
  }
}
