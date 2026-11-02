import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

const Key _firstField = Key('retained_form_first');
const Key _secondField = Key('retained_form_second');
const Key _action = Key('retained_form_action');
const LocalKey _arrival = ValueKey<String>('retained_form_arrival');
const Duration _tick = Duration(milliseconds: 1);
const Duration _revealEnd = Duration(milliseconds: 241);
const String _draft = 'Kept draft';
const String _secondDraft = 'Kept second draft';

Widget _host(
  Widget child, {
  required bool light,
  required TextDirection direction,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(width: 420, child: child),
      ),
    ),
  ),
);

Finder _field(Key key) => find.byKey(key, skipOffstage: false);

FocusNode _internalFocus(WidgetTester tester, Key key) {
  expect(tester.widget<TextField>(_field(key)).focusNode, isNull);
  return tester
      .widget<EditableText>(
        find.descendant(
          of: _field(key),
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        ),
      )
      .focusNode;
}

class _InternalFields {
  _InternalFields(WidgetTester tester)
    : first = _internalFocus(tester, _firstField),
      second = _internalFocus(tester, _secondField);

  // Borrow the nodes that the actual TextFields own; the test never supplies
  // or disposes a replacement that could hide an inherited traversal latch.
  final FocusNode first;
  final FocusNode second;

  void expectSame(WidgetTester tester) {
    expect(_internalFocus(tester, _firstField), same(first));
    expect(_internalFocus(tester, _secondField), same(second));
  }
}

Future<void> _expectTraversal(
  WidgetTester tester,
  _InternalFields fields,
) async {
  expect(fields.first.canRequestFocus, isTrue);
  expect(fields.second.canRequestFocus, isTrue);
  expect(fields.first.skipTraversal, isFalse);
  expect(fields.second.skipTraversal, isFalse);
  await tester.tap(find.byKey(_firstField));
  await tester.pump(_tick);
  expect(fields.first.hasPrimaryFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump(_tick);
  expect(fields.second.hasPrimaryFocus, isTrue);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  } finally {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pump(_tick);
  expect(fields.first.hasPrimaryFocus, isTrue);
}

Future<void> _expectInert(
  WidgetTester tester,
  _InternalFields fields,
) async {
  expect(fields.first.hasFocus, isFalse);
  expect(fields.second.hasFocus, isFalse);
  expect(fields.first.canRequestFocus, isFalse);
  expect(fields.second.canRequestFocus, isFalse);
  expect(find.semantics.byFlag(SemanticsFlag.isTextField), findsNothing);
  expect(find.semantics.byLabel('Apply draft'), findsNothing);
  await tester.tapAt(tester.getCenter(_field(_firstField)));
  await tester.tapAt(
    tester.getCenter(find.byKey(_action, skipOffstage: false)),
  );
  fields.first.requestFocus();
  fields.second.requestFocus();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  expect(fields.first.hasFocus, isFalse);
  expect(fields.second.hasFocus, isFalse);
}

Future<void> _enterDraft(WidgetTester tester) async {
  await tester.enterText(find.byKey(_firstField), _draft);
  await tester.enterText(find.byKey(_secondField), _secondDraft);
  await tester.pump(_tick);
}

void _expectRetained(
  WidgetTester tester,
  GlobalKey<_FormProbeState> probe,
  _FormProbeState original,
  _InternalFields fields,
) {
  expect(probe.currentState, same(original));
  expect(original.mounted, isTrue);
  expect(original.disposals, 0);
  expect(original.draft.text, _draft);
  expect(original.secondDraft.text, _secondDraft);
  fields.expectSame(tester);
}

Future<void> _withOwnedForm(
  WidgetTester tester,
  Future<void> Function() body, {
  VoidCallback? afterUnmount,
}) async {
  final SemanticsHandle semantics = tester.ensureSemantics();
  try {
    await body();
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(_tick);
    } finally {
      try {
        semantics.dispose();
      } finally {
        afterUnmount?.call();
      }
    }
  }
}

double _entranceOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byKey(_arrival),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      final String variant = '${light ? 'light' : 'dark'} ${direction.name}';

      for (final bool initiallyOpen in <bool>[false, true]) {
        testWidgets(
          'Disclosure retains internal fields from initially open '
          '$initiallyOpen in $variant',
          (WidgetTester tester) async {
            final DisclosureController controller = DisclosureController();
            final GlobalKey<_FormProbeState> probe =
                GlobalKey<_FormProbeState>();
            int actions = 0;
            int submissions = 0;
            await _withOwnedForm(tester, () async {
              await tester.pumpWidget(
                _host(
                  Disclosure.bare(
                    controller: controller,
                    initiallyOpen: initiallyOpen,
                    keepAlive: true,
                    child: _FormProbe(
                      key: probe,
                      onAction: () => actions++,
                      onSubmitted: (_) => submissions++,
                    ),
                  ),
                  light: light,
                  direction: direction,
                ),
              );
              final _FormProbeState original = probe.currentState!;
              final _InternalFields fields = _InternalFields(tester);
              if (!initiallyOpen) {
                expect(find.byKey(_firstField), findsNothing);
                await _expectInert(tester, fields);
                expect(actions, 0);
                expect(submissions, 0);
                expect(original.draft.text, isEmpty);
                expect(original.secondDraft.text, isEmpty);
                controller.open();
                await tester.pump(_tick);
                await tester.pump(_revealEnd);
              }
              fields.expectSame(tester);
              await _expectTraversal(tester, fields);
              await _enterDraft(tester);
              await _expectTraversal(tester, fields);

              controller.close();
              await tester.pump(_tick);
              // The input gate closes before the painted reveal has moved.
              expect(find.byKey(_firstField), findsOneWidget);
              await _expectInert(tester, fields);
              expect(actions, 0);
              expect(submissions, 0);
              _expectRetained(tester, probe, original, fields);
              await tester.pump(_revealEnd);
              expect(find.byKey(_firstField), findsNothing);
              _expectRetained(tester, probe, original, fields);

              controller.open();
              await tester.pump(_tick);
              await tester.pump(_revealEnd);
              _expectRetained(tester, probe, original, fields);
              await _expectTraversal(tester, fields);

              controller.close();
              await tester.pump(_tick);
              await tester.pump(const Duration(milliseconds: 80));
              _expectRetained(tester, probe, original, fields);
              expect(fields.first.canRequestFocus, isFalse);
              controller.open();
              await tester.pump(_tick);
              await tester.pump(const Duration(milliseconds: 40));
              _expectRetained(tester, probe, original, fields);
              expect(fields.first.canRequestFocus, isTrue);
              controller.close();
              await tester.pump(_tick);
              await tester.pump(const Duration(milliseconds: 40));
              _expectRetained(tester, probe, original, fields);
              expect(fields.first.canRequestFocus, isFalse);
              controller.open();
              await tester.pump(_tick);
              await tester.pump(_revealEnd);
              _expectRetained(tester, probe, original, fields);
              await _expectTraversal(tester, fields);
              expect(find.semantics.byLabel('Apply draft'), findsOne);
              await tester.tap(find.byKey(_action));
              expect(actions, 1);
              expect(submissions, 0);
            }, afterUnmount: controller.dispose);
          },
        );
      }

      testWidgets(
        'RowDetail revokes closing actions and reverses in $variant',
        (
          WidgetTester tester,
        ) async {
          final ValueNotifier<bool> open = ValueNotifier<bool>(false);
          final GlobalKey<_FormProbeState> probe = GlobalKey<_FormProbeState>();
          int actions = 0;
          int submissions = 0;
          final Widget form = _FormProbe(
            key: probe,
            onAction: () => actions++,
            onSubmitted: (_) => submissions++,
          );
          await _withOwnedForm(tester, () async {
            await tester.pumpWidget(
              _host(
                ValueListenableBuilder<bool>(
                  valueListenable: open,
                  builder: (BuildContext context, bool value, Widget? child) =>
                      RowDetail(
                        open: value,
                        onToggle: (bool value) => open.value = value,
                        row: const SizedBox(height: 32, child: Text('Details')),
                        detail: (BuildContext context) => form,
                      ),
                ),
                light: light,
                direction: direction,
              ),
            );
            expect(probe.currentState, isNull);
            expect(
              find.byType(EditableText, skipOffstage: false),
              findsNothing,
            );
            open.value = true;
            await tester.pump(_tick);
            await tester.pump(_revealEnd);
            final _FormProbeState original = probe.currentState!;
            final _InternalFields fields = _InternalFields(tester);
            await _expectTraversal(tester, fields);
            await _enterDraft(tester);
            await tester.tap(find.byKey(_action));
            expect(actions, 1);
            await _expectTraversal(tester, fields);

            open.value = false;
            await tester.pump(_tick);
            expect(find.byKey(_action), findsOneWidget);
            await _expectInert(tester, fields);
            expect(actions, 1);
            expect(submissions, 0);
            _expectRetained(tester, probe, original, fields);
            await tester.pump(const Duration(milliseconds: 80));
            _expectRetained(tester, probe, original, fields);
            open.value = true;
            await tester.pump(_tick);
            await tester.pump(const Duration(milliseconds: 40));
            _expectRetained(tester, probe, original, fields);
            expect(fields.first.canRequestFocus, isTrue);
            open.value = false;
            await tester.pump(_tick);
            await tester.pump(const Duration(milliseconds: 40));
            _expectRetained(tester, probe, original, fields);
            expect(fields.first.canRequestFocus, isFalse);
            open.value = true;
            await tester.pump(_tick);
            await tester.pump(_revealEnd);
            _expectRetained(tester, probe, original, fields);
            await _expectTraversal(tester, fields);
            expect(find.semantics.byLabel('Apply draft'), findsOne);

            open.value = false;
            await tester.pump(_tick);
            await tester.pump(_revealEnd);
            expect(probe.currentState, isNull);
            expect(original.mounted, isFalse);
            expect(original.disposals, 1);
            expect(
              find.byType(EditableText, skipOffstage: false),
              findsNothing,
            );
            open.value = true;
            await tester.pump(_tick);
            await tester.pump(_revealEnd);
            final _FormProbeState reopened = probe.currentState!;
            final _InternalFields reopenedFields = _InternalFields(tester);
            expect(reopened, isNot(same(original)));
            expect(reopened.draft.text, isEmpty);
            expect(reopened.secondDraft.text, isEmpty);
            expect(reopenedFields.first, isNot(same(fields.first)));
            expect(reopenedFields.second, isNot(same(fields.second)));
            await _expectTraversal(tester, reopenedFields);
            await tester.tap(find.byKey(_action));
            expect(actions, 2);
            expect(submissions, 0);
          }, afterUnmount: open.dispose);
        },
      );

      testWidgets('ListEntrance releases real field traversal in $variant', (
        WidgetTester tester,
      ) async {
        final GlobalKey<_FormProbeState> probe = GlobalKey<_FormProbeState>();
        int actions = 0;
        int submissions = 0;
        await _withOwnedForm(tester, () async {
          await tester.pumpWidget(
            _host(
              ListEntrance(
                itemKeys: const <LocalKey>[_arrival],
                child: ListEntranceItem(
                  key: _arrival,
                  child: _FormProbe(
                    key: probe,
                    onAction: () => actions++,
                    onSubmitted: (_) => submissions++,
                  ),
                ),
              ),
              light: light,
              direction: direction,
            ),
          );
          final _FormProbeState original = probe.currentState!;
          final _InternalFields fields = _InternalFields(tester);
          expect(_entranceOpacity(tester), 0);
          // No time advances while the zero-opacity controls are challenged.
          await _expectInert(tester, fields);
          expect(_entranceOpacity(tester), 0);
          expect(actions, 0);
          expect(submissions, 0);
          expect(original.draft.text, isEmpty);
          expect(original.secondDraft.text, isEmpty);
          await tester.pump(_tick);
          expect(_entranceOpacity(tester), greaterThan(0));
          expect(_entranceOpacity(tester), lessThan(1));
          fields.expectSame(tester);
          expect(find.semantics.byLabel('Apply draft'), findsOne);
          await _expectTraversal(tester, fields);
          await _enterDraft(tester);
          // Visibility, traversal and typing used five positive 1 ms ticks.
          await tester.pump(const Duration(milliseconds: 155));
          expect(_entranceOpacity(tester), lessThan(1));
          _expectRetained(tester, probe, original, fields);
          await tester.pump(const Duration(milliseconds: 160));
          expect(_entranceOpacity(tester), 1);
          _expectRetained(tester, probe, original, fields);
          await _expectTraversal(tester, fields);
          await tester.tap(find.byKey(_action));
          expect(actions, 1);
          expect(submissions, 0);
        });
      });
    }
  }
}

class _FormProbe extends StatefulWidget {
  const _FormProbe({
    required this.onAction,
    required this.onSubmitted,
    super.key,
  });

  final VoidCallback onAction;
  final ValueChanged<String> onSubmitted;

  @override
  State<_FormProbe> createState() => _FormProbeState();
}

class _FormProbeState extends State<_FormProbe> {
  final TextEditingController draft = TextEditingController();
  final TextEditingController secondDraft = TextEditingController();
  int disposals = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TextField(
        key: _firstField,
        controller: draft,
        textInputAction: TextInputAction.done,
        onSubmitted: widget.onSubmitted,
      ),
      TextField(
        key: _secondField,
        controller: secondDraft,
        textInputAction: TextInputAction.done,
        onSubmitted: widget.onSubmitted,
      ),
      TextButton(
        key: _action,
        onPressed: widget.onAction,
        child: const Text('Apply draft'),
      ),
    ],
  );

  @override
  void dispose() {
    disposals++;
    draft.dispose();
    secondDraft.dispose();
    super.dispose();
  }
}
