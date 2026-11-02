import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/new_wallet_password_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_step_route.dart';

/// Confirms the owner's existing mnemonic without generating another seed.
class NewWalletConfirmSeedScreen extends StatefulWidget {
  /// Freezes a quiz snapshot of the original seed when this step is mounted.
  const NewWalletConfirmSeedScreen(this.seedWords, {super.key});

  /// Original private seed words passed by the existing creation owner.
  final List<String> seedWords;

  @override
  State<NewWalletConfirmSeedScreen> createState() =>
      _NewWalletConfirmSeedScreenState();
}

class _NewWalletConfirmSeedScreenState
    extends State<NewWalletConfirmSeedScreen> {
  late List<String> _seed;
  SeedQuiz? _quiz;
  Object _source = Object();

  @override
  void initState() {
    super.initState();
    _replaceSeed();
  }

  void _replaceSeed() {
    _source = Object();
    _seed = List<String>.unmodifiable(widget.seedWords);
    try {
      _quiz = SeedQuiz(_seed);
    } on Object {
      _quiz = null;
    }
  }

  @override
  void didUpdateWidget(NewWalletConfirmSeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_seed, widget.seedWords)) _replaceSeed();
  }

  bool get _sameSeed => listEquals(_seed, widget.seedWords);

  @override
  Widget build(BuildContext context) => EntryActionBoundary(
    source: _source,
    builder: (BuildContext context, EntryActionLease lease) {
      final Object source = _source;
      final SeedQuiz? quiz = _quiz;
      return SeedQuizSurface(
        quiz: quiz,
        onBack: lease.guard(() => Navigator.pop(context)),
        onSelected: (int question, String word) {
          if (!lease.isCurrent ||
              !identical(source, _source) ||
              !_sameSeed ||
              !identical(quiz, _quiz) ||
              quiz == null) {
            return;
          }
          if (quiz.select(question, word)) setState(() => _source = Object());
        },
        onContinue: (quiz?.complete ?? false)
            ? lease.guard(() {
                if (!identical(source, _source) ||
                    !_sameSeed ||
                    !identical(quiz, _quiz) ||
                    !quiz!.complete) {
                  return;
                }
                final List<String> seed = List<String>.unmodifiable(_seed);
                Navigator.of(context).push<void>(
                  OnboardingStepRoute<void>(
                    builder: (_) => NewWalletPasswordScreen(seed),
                  ),
                );
              })
            : null,
      );
    },
  );

  @override
  void dispose() {
    _source = Object();
    super.dispose();
  }
}
