import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz.dart';

// Synthetic labels exercise construction without creating mnemonic material.
List<String> fixtureWords(int count) =>
    List<String>.generate(count, (int index) => 'fixture-$index');

SeedQuiz fixtureQuiz({
  int count = 12,
  List<String>? words,
  Random? random,
  bool Function(String)? member,
  bool Function(List<String>)? checksum,
}) => SeedQuiz(
  words ?? fixtureWords(count),
  random: random ?? Random(7),
  isValidWord: member ?? (_) => true,
  validateMnemonic: checksum ?? (_) => true,
);

class _ZeroRandom implements Random {
  int calls = 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) {
    calls++;
    return 0;
  }
}

void main() {
  for (final int count in <int>[12, 24]) {
    test(
      '$count words produce three distinct positions and four unique choices',
      () {
        final SeedQuiz quiz = fixtureQuiz(count: count);
        expect(quiz.questions, hasLength(3));
        expect(
          quiz.questions.map((SeedQuizQuestion row) => row.position).toSet(),
          hasLength(3),
        );
        for (final SeedQuizQuestion row in quiz.questions) {
          expect(row.position, inInclusiveRange(0, count - 1));
          expect(row.choices, hasLength(4));
          expect(row.choices.toSet(), hasLength(4));
          expect(row.choices, contains(quiz.seedWords[row.position]));
          expect(row.answer, quiz.seedWords[row.position]);
        }
      },
    );
  }

  test('repeated seed words and a degenerate random source stay finite', () {
    final _ZeroRandom random = _ZeroRandom();
    final SeedQuiz quiz = fixtureQuiz(
      words: List<String>.filled(12, 'fixture-repeat'),
      random: random,
    );
    expect(
      quiz.questions.map((SeedQuizQuestion row) => row.position).toSet(),
      hasLength(3),
    );
    for (final SeedQuizQuestion row in quiz.questions) {
      expect(row.choices.toSet(), hasLength(4));
      expect(
        row.choices.where((String value) => value == 'fixture-repeat'),
        hasLength(1),
      );
    }
    expect(random.calls, lessThan(256));
  });

  test('fallback candidates pass the supplied public membership boundary', () {
    final Set<String> allowed = <String>{
      'fixture-repeat',
      'ability',
      'able',
      'about',
    };
    final List<String> checked = <String>[];
    final SeedQuiz quiz = fixtureQuiz(
      words: List<String>.filled(24, 'fixture-repeat'),
      member: (String value) {
        checked.add(value);
        return allowed.contains(value);
      },
    );
    expect(checked, containsAll(<String>['ability', 'able', 'about']));
    for (final SeedQuizQuestion row in quiz.questions) {
      expect(row.choices.toSet(), allowed);
    }
  });

  test(
    'an insufficient valid decoy pool refuses without a random retry loop',
    () {
      final _ZeroRandom random = _ZeroRandom();
      expect(
        () => fixtureQuiz(
          words: List<String>.filled(12, 'fixture-repeat'),
          random: random,
          member: (String value) => value == 'fixture-repeat',
        ),
        throwsStateError,
      );
      expect(random.calls, lessThan(24));
    },
  );

  test(
    'unsupported lengths, nonmembers and failed checksums refuse a quiz',
    () {
      expect(() => fixtureQuiz(count: 11), throwsFormatException);
      expect(() => fixtureQuiz(member: (_) => false), throwsFormatException);
      expect(() => fixtureQuiz(checksum: (_) => false), throwsFormatException);
    },
  );

  test('source words and all choice lists are immutable snapshots', () {
    final List<String> source = fixtureWords(12);
    final SeedQuiz quiz = fixtureQuiz(words: source);
    source[0] = 'replacement';
    expect(quiz.seedWords.first, 'fixture-0');
    expect(() => quiz.seedWords[0] = 'replacement', throwsUnsupportedError);
    expect(() => quiz.questions.first.choices.clear(), throwsUnsupportedError);
  });

  test('only exact ordered answers unlock the next row and Continue', () {
    final SeedQuiz quiz = fixtureQuiz();
    expect(quiz.select(-1, 'not-a-choice'), isFalse);
    expect(quiz.select(3, 'not-a-choice'), isFalse);
    expect(quiz.select(1, quiz.questions[1].answer), isFalse);
    expect(quiz.select(0, 'not-a-choice'), isFalse);
    final SeedQuizQuestion first = quiz.questions.first;
    final String wrong = first.choices.firstWhere(
      (String word) => word != first.answer,
    );
    expect(quiz.select(0, wrong), isTrue);
    expect(quiz.correct, 0);
    expect(quiz.complete, isFalse);
    for (int index = 0; index < 3; index++) {
      expect(quiz.select(index, quiz.questions[index].answer), isTrue);
    }
    expect(quiz.complete, isTrue);
    expect(quiz.correct, 3);
    expect(quiz.select(0, first.answer), isFalse);
    expect(quiz.complete, isTrue);
    quiz.select(0, wrong);
    expect(quiz.complete, isFalse);
    expect(quiz.selected(1), isNull);
    expect(quiz.selected(2), isNull);
    expect(quiz.unlocked, 0);
  });
}
