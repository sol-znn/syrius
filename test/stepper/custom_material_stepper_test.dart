import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/widgets/token_step_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/step_switcher.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/custom_material_stepper.dart'
    as stepper;

class _DraftBody extends StatefulWidget {
  const _DraftBody({
    required this.index,
    required this.active,
    required this.onMount,
    required this.onDispose,
    required this.onSubmit,
  });

  final int index;
  final bool active;
  final ValueChanged<int> onMount;
  final ValueChanged<int> onDispose;
  final ValueChanged<int> onSubmit;

  @override
  State<_DraftBody> createState() => _DraftBodyState();
}

class _DraftBodyState extends State<_DraftBody> {
  final TextEditingController _draft = TextEditingController();
  final FocusNode _field = FocusNode();
  final FocusNode _submit = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.onMount(widget.index);
  }

  @override
  Widget build(BuildContext context) => TokenStepFrame(
    active: widget.active,
    onSubmit: () => widget.onSubmit(widget.index),
    body: TextField(
      key: ValueKey<String>('draft_${widget.index}'),
      controller: _draft,
      focusNode: _field,
    ),
    primary: OutlinedButton(
      focusNode: _submit,
      onPressed: () => widget.onSubmit(widget.index),
      child: Text('Submit ${widget.index}'),
    ),
  );

  @override
  void dispose() {
    widget.onDispose(widget.index);
    _draft.dispose();
    _field.dispose();
    _submit.dispose();
    super.dispose();
  }
}

Widget _host({
  required int current,
  required stepper.StepperType type,
  required Brightness brightness,
  required ValueChanged<int> onMount,
  required ValueChanged<int> onDispose,
  required ValueChanged<int> onSubmit,
  bool complete = false,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 550,
      child: stepper.Stepper(
        type: type,
        currentStep: current,
        steps: <stepper.Step>[
          for (int i = 0; i < 3; i++)
            stepper.Step(
              title: Text('Step $i'),
              state: complete || i < current
                  ? stepper.StepState.complete
                  : stepper.StepState.indexed,
              content: _DraftBody(
                index: i,
                active: !complete && i == current,
                onMount: onMount,
                onDispose: onDispose,
                onSubmit: onSubmit,
              ),
            ),
        ],
      ),
    ),
  ),
);

Finder _field(int index, {bool skipOffstage = true}) => find.byKey(
  ValueKey<String>('draft_$index'),
  skipOffstage: skipOffstage,
);

void _stepperTestWidgets(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (WidgetTester tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

void main() {
  for (final stepper.StepperType type in stepper.StepperType.values) {
    for (final Brightness brightness in Brightness.values) {
      _stepperTestWidgets(
        '$type keeps drafts, focus and owners in $brightness',
        (
          WidgetTester tester,
        ) async {
          final List<int> mounted = <int>[];
          final List<int> disposed = <int>[];
          final List<int> submitted = <int>[];
          Widget host(int current, {bool complete = false}) => _host(
            current: current,
            type: type,
            brightness: brightness,
            complete: complete,
            onMount: mounted.add,
            onDispose: disposed.add,
            onSubmit: submitted.add,
          );
          await tester.pumpWidget(host(0));
          await tester.pumpAndSettle();
          expect(mounted, <int>[0, 1, 2]);
          expect(submitted, isEmpty);
          await tester.enterText(_field(0), 'Original draft');
          final TextField first = tester.widget<TextField>(_field(0));
          final TextEditingController original = first.controller!;
          expect(first.focusNode!.hasFocus, isTrue);

          await tester.pumpWidget(host(1));
          await tester.pump();
          expect(first.focusNode!.hasFocus, isFalse);
          expect(first.focusNode!.canRequestFocus, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump(const Duration(milliseconds: 150));
          expect(submitted, isEmpty);
          final TextField incoming = tester.widget<TextField>(_field(1));
          expect(incoming.focusNode!.hasFocus, isFalse);
          expect(incoming.focusNode!.canRequestFocus, isFalse);
          final List<SharedAxisTransition> transitions = tester
              .widgetList<SharedAxisTransition>(
                find.byType(SharedAxisTransition, skipOffstage: false),
              )
              .toList();
          expect(transitions, hasLength(3));
          expect(
            transitions.every(
              (SharedAxisTransition transition) =>
                  transition.transitionType ==
                  SharedAxisTransitionType.horizontal,
            ),
            isTrue,
          );
          await tester.pumpAndSettle();
          expect(
            incoming.focusNode!.hasFocus,
            isTrue,
            reason:
                'Incoming focusability: '
                '${incoming.focusNode!.canRequestFocus}; primary: '
                '${FocusManager.instance.primaryFocus?.debugLabel} '
                '(${FocusManager.instance.primaryFocus?.runtimeType})',
          );
          expect(submitted, isEmpty);
          expect(incoming.focusNode!.skipTraversal, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final OutlinedButton action = tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Submit 1'),
          );
          expect(action.focusNode!.hasFocus, isTrue);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(incoming.focusNode!.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(submitted, <int>[1]);

          await tester.pumpWidget(host(0));
          await tester.pumpAndSettle();
          final TextField restored = tester.widget<TextField>(_field(0));
          expect(restored.controller, same(original));
          expect(restored.controller!.text, 'Original draft');
          expect(restored.focusNode!.hasFocus, isTrue);
          expect(mounted, <int>[0, 1, 2]);
          expect(disposed, isEmpty);

          await tester.pumpWidget(host(2, complete: true));
          await tester.pumpAndSettle();
          expect(
            find.byType(_DraftBody, skipOffstage: false),
            findsNWidgets(3),
          );
          expect(_field(0), findsNothing);
          expect(_field(1), findsNothing);
          expect(_field(2), findsNothing);
          expect(disposed, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(submitted, <int>[1]);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(disposed, <int>[0, 1, 2]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final bool complete in <bool>[false, true]) {
    _stepperTestWidgets(
      'queued focus is revoked on ${complete ? 'completion' : 'rapid Back'}',
      (WidgetTester tester) async {
        final List<int> mounted = <int>[];
        final List<int> disposed = <int>[];
        final List<int> submitted = <int>[];
        Widget host(int current, {bool done = false}) => _host(
          current: current,
          type: stepper.StepperType.vertical,
          brightness: Brightness.dark,
          complete: done,
          onMount: mounted.add,
          onDispose: disposed.add,
          onSubmit: submitted.add,
        );
        await tester.pumpWidget(host(0));
        await tester.pumpAndSettle();
        await tester.pumpWidget(host(1));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(host(complete ? 2 : 0, done: complete));
        await tester.pumpAndSettle();

        for (int i = 0; i < 3; i++) {
          final TextField field = tester.widget(
            _field(i, skipOffstage: false),
          );
          expect(field.focusNode!.hasFocus, !complete && i == 0);
          if (complete || i != 0) {
            expect(field.focusNode!.canRequestFocus, isFalse);
          }
        }
        expect(mounted, <int>[0, 1, 2]);
        expect(disposed, isEmpty);
        expect(submitted, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(disposed, <int>[0, 1, 2]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _stepperTestWidgets(
    'held Enter cannot register after focus moves to a review action',
    (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> step = ValueNotifier<int>(0);
      addTearDown(step.dispose);
      int registrations = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: step,
              builder: (BuildContext context, int current, _) =>
                  StepSwitcher.retained(
                    step: current,
                    children: <Widget>[
                      TokenStepFrame(
                        active: current == 0,
                        onSubmit: () => step.value = 1,
                        body: const TextField(),
                        primary: TextButton(
                          onPressed: () => step.value = 1,
                          child: const Text('Continue'),
                        ),
                      ),
                      TokenStepFrame(
                        active: current == 1,
                        body: const Text('Review'),
                        primary: TextButton(
                          onPressed: () => registrations++,
                          child: const Text('Register'),
                        ),
                      ),
                    ],
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(step.value, 1);
      expect(registrations, 0);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(registrations, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(registrations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  _stepperTestWidgets('an inactive frame refuses its own action button', (
    WidgetTester tester,
  ) async {
    int submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TokenStepFrame(
            active: false,
            body: const TextField(),
            onSubmit: () => submissions++,
            primary: OutlinedButton(
              onPressed: () => submissions++,
              child: const Text('Submit'),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.text('Submit')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(submissions, 0);
    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.focusNode.canRequestFocus, isFalse);
    field.focusNode.requestFocus();
    await tester.pump();
    expect(field.focusNode.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
