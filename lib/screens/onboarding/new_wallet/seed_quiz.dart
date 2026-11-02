import 'dart:math';

import 'package:znn_sdk_dart/znn_sdk_dart.dart' show Mnemonic;

// Canonical English BIP39 candidates, each checked through the public SDK API.
const List<String> _fallback = <String>[
  'abandon',
  'ability',
  'able',
  'about',
  'above',
  'absent',
  'absorb',
  'abstract',
  'absurd',
  'abuse',
  'access',
];

/// One position and four unique words, including its exact original answer.
class SeedQuizQuestion {
  /// Freezes the generated choices for one position in the owner's seed.
  SeedQuizQuestion({
    required this.position,
    required this.answer,
    required List<String> choices,
  }) : choices = List<String>.unmodifiable(choices);

  /// Zero-based position in the original private seed.
  final int position;

  /// The exact original word required at [position].
  final String answer;

  /// Four distinct valid words, including [answer], in their displayed order.
  final List<String> choices;
}

/// A bounded three-question snapshot of the owner's already generated seed.
class SeedQuiz {
  /// Validates an existing mnemonic and samples three distinct seed positions.
  SeedQuiz(
    List<String> words, {
    Random? random,
    bool Function(String)? isValidWord,
    bool Function(List<String>)? validateMnemonic,
  }) : seedWords = List<String>.unmodifiable(words) {
    final bool Function(String) member = isValidWord ?? Mnemonic.isValidWord;
    final bool Function(List<String>) checksum =
        validateMnemonic ?? Mnemonic.validateMnemonic;
    if ((seedWords.length != 12 && seedWords.length != 24) ||
        !seedWords.every(member) ||
        !checksum(seedWords)) {
      throw const FormatException('Seed is not valid');
    }
    final Random draw = random ?? Random.secure();
    final List<int> positions = List<int>.generate(
      seedWords.length,
      (int index) => index,
    )..shuffle(draw);
    final List<int> chosen = positions.take(3).toList()..sort();
    final Set<String> pool = <String>{...seedWords, ..._fallback.where(member)};
    if (pool.length < 4) throw StateError('Not enough valid quiz choices');
    questions = List<SeedQuizQuestion>.unmodifiable(<SeedQuizQuestion>[
      for (final int position in chosen) _question(position, pool, draw),
    ]);
  }

  /// The original validated mnemonic; never serialize into a public artifact.
  final List<String> seedWords;

  /// Three fixed questions retained while the owner updates answer selections.
  late final List<SeedQuizQuestion> questions;
  final Map<int, String> _selected = <int, String>{};

  SeedQuizQuestion _question(int index, Set<String> pool, Random draw) {
    final String answer = seedWords[index];
    final List<String> decoys =
        pool.where((String word) => word != answer).toList()..shuffle(draw);
    final List<String> choices = <String>[answer, ...decoys.take(3)]
      ..shuffle(draw);
    return SeedQuizQuestion(position: index, answer: answer, choices: choices);
  }

  /// The displayed choice for a zero-based question, or null before selection.
  String? selected(int question) => _selected[question];

  /// The first unanswered or incorrect question; later rows remain unavailable.
  int get unlocked {
    int next = 0;
    while (next < questions.length &&
        _selected[next] == questions[next].answer) {
      next++;
    }
    return next;
  }

  /// An answer cannot come from a different question's hidden word or source.
  bool select(int question, String choice) {
    if (question < 0 ||
        question >= questions.length ||
        question > unlocked ||
        !questions[question].choices.contains(choice)) {
      return false;
    }
    if (_selected[question] == choice) return false;
    _selected[question] = choice;
    _selected.removeWhere((int index, String _) => index > question);
    return true;
  }

  /// The number of retained selections matching their original answer.
  int get correct => List<int>.generate(
    questions.length,
    (int index) => index,
  ).where((int index) => _selected[index] == questions[index].answer).length;

  /// Whether all three original questions currently have the correct choice.
  bool get complete => correct == questions.length;
}
