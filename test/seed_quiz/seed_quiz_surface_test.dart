import 'dart:math';

import 'package:flutter/foundation.dart' as foundation show TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/new_wallet/seed_quiz_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

import '../import_redesign/support.dart';

SeedQuiz _quiz() => SeedQuiz(
  List<String>.generate(12, (int index) => 'fixture-$index'),
  random: Random(9),
  isValidWord: (_) => true,
  validateMnemonic: (_) => true,
);

class _Fixture extends StatefulWidget {
  const _Fixture({
    required this.quiz,
    required this.onContinue,
    this.onBack,
  });

  final SeedQuiz quiz;
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  Object _source = Object();

  @override
  void didUpdateWidget(_Fixture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.quiz, widget.quiz)) _source = Object();
  }

  @override
  Widget build(BuildContext context) => EntryActionBoundary(
    source: _source,
    builder: (_, EntryActionLease lease) => SeedQuizSurface(
      quiz: widget.quiz,
      onSelected: (int question, String word) {
        if (lease.isCurrent && widget.quiz.select(question, word)) {
          setState(() => _source = Object());
        }
      },
      onBack: lease.guard(widget.onBack ?? () {}),
      onContinue: widget.quiz.complete ? lease.guard(widget.onContinue) : null,
      background: const SizedBox.expand(),
    ),
  );
}

Finder _choice(SeedQuiz quiz, int question, String word) => find.byKey(
  ValueKey<String>(
    'seed_quiz_${question}_${quiz.questions[question].choices.indexOf(word)}',
  ),
);

Widget _desktopHost(
  Widget child, {
  required bool light,
  double scale = 1,
  Size size = const Size(1280, 780),
}) => entryHost(
  Theme(
    data: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
      platform: foundation.TargetPlatform.windows,
      visualDensity: VisualDensity.compact,
    ),
    child: child,
  ),
  light: light,
  scale: scale,
  size: size,
);

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets(
      '${light ? 'light' : 'dark'} quiz reveals four choices per active row',
      (
        WidgetTester tester,
      ) async {
        prepareEntryViewport(tester);
        final SeedQuiz quiz = _quiz();
        await tester.pumpWidget(
          entryHost(
            _Fixture(quiz: quiz, onContinue: () {}),
            light: light,
          ),
        );
        expect(
          tester
              .getSize(find.byKey(const Key('seed_quiz_screen_marker')))
              .width,
          620,
        );
        for (final String word in quiz.questions.first.choices) {
          expect(_choice(quiz, 0, word), findsOneWidget);
        }
        expect(_choice(quiz, 1, quiz.questions[1].answer), findsNothing);
        expect(find.text('0 of 3 done.'), findsOneWidget);
        await tester.tap(_choice(quiz, 0, quiz.questions[0].answer));
        await tester.pump();
        for (final String word in quiz.questions[1].choices) {
          expect(_choice(quiz, 1, word), findsOneWidget);
        }
        expect(_choice(quiz, 2, quiz.questions[2].answer), findsNothing);
        expect(find.text('1 of 3 done.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${light ? 'light' : 'dark'} desktop Back and choices keep 26 px',
      (WidgetTester tester) async {
        prepareEntryViewport(tester);
        final SeedQuiz quiz = _quiz();
        int backs = 0;
        int continuations = 0;
        await tester.pumpWidget(
          _desktopHost(
            _Fixture(
              quiz: quiz,
              onBack: () => backs++,
              onContinue: () => continuations++,
            ),
            light: light,
          ),
        );
        final Finder back = find.byKey(const Key('entry_back'));
        final Rect originalBack = tester.getRect(back);
        final ThemeData theme = Theme.of(tester.element(back));
        expect(theme.platform, foundation.TargetPlatform.windows);
        expect(theme.visualDensity, VisualDensity.compact);
        expect(originalBack.height, 26);
        for (final String word in quiz.questions.first.choices) {
          expect(tester.getSize(_choice(quiz, 0, word)).height, 26);
        }
        final FocusNode backFocus = Focus.of(
          tester.element(
            find.descendant(of: back, matching: find.byType(Text)),
          ),
        )..requestFocus();
        await tester.pump();
        expect(backFocus.hasFocus, isTrue);
        expect(tester.getRect(back), originalBack);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(backs, 1);
        expect(quiz.selected(0), isNull);
        await tester.tap(_choice(quiz, 0, quiz.questions[0].answer));
        await tester.pump();
        expect(quiz.selected(0), quiz.questions[0].answer);
        expect(quiz.correct, 1);
        for (int question = 0; question < 2; question++) {
          for (final String word in quiz.questions[question].choices) {
            expect(tester.getSize(_choice(quiz, question, word)).height, 26);
          }
        }
        expect(tester.getSize(back).height, 26);
        expect(continuations, 0);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      '${light ? 'light' : 'dark'} scaled desktop choices grow and wrap',
      (WidgetTester tester) async {
        const Size size = Size(540, 600);
        prepareEntryViewport(tester, size: size);
        final SeedQuiz quiz = _quiz();
        int backs = 0;
        int continuations = 0;
        await tester.pumpWidget(
          _desktopHost(
            _Fixture(
              quiz: quiz,
              onBack: () => backs++,
              onContinue: () => continuations++,
            ),
            light: light,
            scale: 2.5,
            size: size,
          ),
        );
        final Finder back = find.byKey(const Key('entry_back'));
        final ThemeData theme = Theme.of(tester.element(back));
        expect(theme.platform, foundation.TargetPlatform.windows);
        expect(theme.visualDensity, VisualDensity.compact);
        final Rect backBounds = tester.getRect(back);
        final Rect backLabel = tester.getRect(
          find.descendant(of: back, matching: find.byType(Text)),
        );
        expect(backBounds.height, greaterThan(26));
        expect(backBounds.top, lessThanOrEqualTo(backLabel.top));
        expect(backBounds.bottom, greaterThanOrEqualTo(backLabel.bottom));
        final List<Rect> choices = <Rect>[];
        for (final String word in quiz.questions.first.choices) {
          final Finder choice = _choice(quiz, 0, word);
          final Rect bounds = tester.getRect(choice);
          final Rect label = tester.getRect(
            find.descendant(of: choice, matching: find.byType(Text)),
          );
          expect(bounds.height, greaterThan(26));
          expect(bounds.top, lessThanOrEqualTo(label.top));
          expect(bounds.bottom, greaterThanOrEqualTo(label.bottom));
          choices.add(bounds);
        }
        expect(
          choices.any((Rect bounds) => bounds.top > choices.first.top),
          isTrue,
        );
        for (int question = 0; question < 3; question++) {
          final Finder answer = _choice(
            quiz,
            question,
            quiz.questions[question].answer,
          );
          await tester.ensureVisible(answer);
          await tester.pump();
          expect(tester.getSize(answer).height, greaterThan(26));
          await tester.tap(answer);
          await tester.pump();
          expect(quiz.selected(question), quiz.questions[question].answer);
        }
        expect(quiz.correct, 3);
        await tester.ensureVisible(back);
        await tester.pump();
        await tester.tap(back);
        expect(backs, 1);
        expect(continuations, 0);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
    'wrong answers stay put and three exact answers enable Continue',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final SeedQuiz quiz = _quiz();
      int continuations = 0;
      await tester.pumpWidget(
        entryHost(_Fixture(quiz: quiz, onContinue: () => continuations++)),
      );
      final String wrong = quiz.questions[0].choices.firstWhere(
        (String word) => word != quiz.questions[0].answer,
      );
      await tester.tap(_choice(quiz, 0, wrong));
      await tester.pump();
      expect(find.text('Check your seed before continuing.'), findsOneWidget);
      expect(
        tester
            .widget<PrimaryPill>(find.byKey(const Key('seed_quiz_continue')))
            .onPressed,
        isNull,
      );
      for (int question = 0; question < 3; question++) {
        await tester.tap(
          _choice(quiz, question, quiz.questions[question].answer),
        );
        await tester.pump();
      }
      expect(find.text('3 of 3 done.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('seed_quiz_continue')));
      expect(continuations, 1);
    },
  );

  testWidgets(
    'keyboard traversal selects a visible word through the real chip button',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final SeedQuiz quiz = _quiz();
      await tester.pumpWidget(
        entryHost(_Fixture(quiz: quiz, onContinue: () {})),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(quiz.selected(0), quiz.questions[0].choices.first);
    },
  );

  testWidgets(
    'a replacement quiz revokes saved choice and continuation callbacks',
    (
      WidgetTester tester,
    ) async {
      prepareEntryViewport(tester);
      final SeedQuiz first = _quiz();
      int continuations = 0;
      Widget host(SeedQuiz quiz) =>
          entryHost(_Fixture(quiz: quiz, onContinue: () => continuations++));
      await tester.pumpWidget(host(first));
      final Finder firstButton = find.descendant(
        of: _choice(first, 0, first.questions[0].answer),
        matching: find.byType(OutlinedButton),
      );
      final VoidCallback oldChoice = tester
          .widget<OutlinedButton>(firstButton)
          .onPressed!;
      for (int question = 0; question < 3; question++) {
        await tester.tap(
          _choice(first, question, first.questions[question].answer),
        );
        await tester.pump();
      }
      final VoidCallback oldContinue = tester
          .widget<PrimaryPill>(find.byKey(const Key('seed_quiz_continue')))
          .onPressed!;
      final SeedQuiz second = _quiz();
      await tester.pumpWidget(host(second));
      oldChoice();
      oldContinue();
      expect(second.selected(0), isNull);
      expect(continuations, 0);
    },
  );

  testWidgets(
    'the scaled RTL quiz wraps words and keeps its action reachable',
    (
      WidgetTester tester,
    ) async {
      const Size size = Size(540, 360);
      prepareEntryViewport(tester, size: size);
      final SeedQuiz quiz = _quiz();
      for (int question = 0; question < 3; question++) {
        quiz.select(question, quiz.questions[question].answer);
      }
      int continuations = 0;
      await tester.pumpWidget(
        entryHost(
          _Fixture(quiz: quiz, onContinue: () => continuations++),
          size: size,
          scale: 2.5,
          rtl: true,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('seed_quiz_continue')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('seed_quiz_continue')));
      expect(continuations, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
