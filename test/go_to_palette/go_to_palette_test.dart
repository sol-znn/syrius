import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

const Key _field = Key('go_to_field');
const Key _results = Key('go_to_results');

Finder _row(Object id) => find.byKey(ValueKey<Object?>(id));

Finder _rowRichText(Object id, String label) => find.descendant(
  of: _row(id),
  matching: find.byWidgetPredicate(
    (Widget widget) =>
        widget is RichText &&
        widget.text.toPlainText(includeSemanticsLabels: false) == label,
  ),
);

Finder _tooltip(Finder owner) => find.descendant(
  of: owner,
  matching: find.byType(Tooltip),
);

Semantics _rowSemantics(WidgetTester tester, Object id) =>
    tester.widget<Semantics>(
      find.descendant(
        of: _row(id),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.button == true,
        ),
      ),
    );

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _open<T>(
  WidgetTester tester,
  List<GoToEntry<T>> entries, {
  List<T?>? answers,
  ValueNotifier<List<GoToEntry<T>>>? liveEntries,
  String chordName = 'Ctrl',
}) async {
  tester.view
    ..physicalSize = const Size(1200, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _host(
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async {
            final T? answer;
            if (liveEntries == null) {
              answer = await showGoToPalette<T>(
                context: context,
                entries: entries,
                chordName: chordName,
              );
            } else {
              answer = await showFrostedDialog<T>(
                context: context,
                builder: (BuildContext context) =>
                    ValueListenableBuilder<List<GoToEntry<T>>>(
                      valueListenable: liveEntries,
                      builder:
                          (
                            BuildContext context,
                            List<GoToEntry<T>> entries,
                            Widget? child,
                          ) => GoToPalette<T>(
                            entries: entries,
                            chordName: chordName,
                          ),
                    ),
              );
            }
            answers?.add(answer);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('row hints stay at the trailing edge with loose text', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final bool dark in <bool>[true, false]) {
      for (final TextDirection direction in TextDirection.values) {
        for (final double scale in <double>[1, 2]) {
          // Only fixed fixture labels and the two declared scales are printed.
          // ignore: avoid_print
          print('CI_GOTO_GEOMETRY_CASE:'
              '${dark ? 'dark' : 'light'}:${direction.name}:${scale.toInt()}');
          await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Directionality(
              textDirection: direction,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(1200, 780),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 560,
                      child: GoToPalette<int>(entries: <GoToEntry<int>>[
                        const GoToEntry<int>(
                          id: 'short', value: 1, label: 'Delegation',
                          detail: 'Nodes', shortcut: 'Ctrl 4',
                          icon: Icons.layers,
                        ),
                        GoToEntry<int>(
                          id: 'long', value: 2,
                          label: 'Long destination ' * 24,
                          detail: 'Context ' * 20, shortcut: 'Ctrl D',
                          category: GoToCategory.actions,
                          icon: Icons.layers,
                        ),
                        GoToEntry<int>(
                          id: 'address', value: 3, label: 'Contact ' * 20,
                          identifier: 'synthetic' * 12,
                          detail: 'Send to destination ' * 20,
                          category: GoToCategory.addresses,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          final AppTokens tokens = AppTokens.of(tester.element(_row('short')));
          for (final String id in <String>['short', 'long']) {
            final Icon icon = tester.widget<Icon>(find.descendant(
              of: _row(id), matching: find.byType(Icon),
            ));
            expect(icon.color, tokens.foreground);
            final RichText label = tester.widget<RichText>(_rowRichText(
              id, id == 'short' ? 'Delegation' : 'Long destination ' * 24,
            ));
            expect(label.text.style?.color, tokens.foreground);
          }
          for (final MapEntry<String, String> pair in <String, String>{
            'short': 'Ctrl 4', 'long': 'Ctrl D',
          }.entries) {
            final Rect row = tester.getRect(_row(pair.key));
            final Rect hint = tester.getRect(find.descendant(
              of: _row(pair.key), matching: find.text(pair.value),
            ));
            final EdgeInsets padding =
                tokens.keyboardHintPadding.resolve(direction);
            if (direction == TextDirection.ltr) {
              expect(hint.right,
                  closeTo(row.right - tokens.goToRowInset - padding.right, 1));
            } else {
              expect(hint.left,
                  closeTo(row.left + tokens.goToRowInset + padding.left, 1));
            }
            expect(hint.top, greaterThanOrEqualTo(row.top));
            expect(hint.bottom, lessThanOrEqualTo(row.bottom));
          }
          final Rect label = tester.getRect(
            _rowRichText('short', 'Delegation'),
          );
          final Rect detail = tester.getRect(_rowRichText('short', 'Nodes'));
          expect(direction == TextDirection.ltr
              ? detail.left - label.right : label.left - detail.right,
              closeTo(tokens.inlineGap, 1));
          expect(_rowSemantics(tester, 'address').properties.label,
              contains('synthetic' * 12));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('groups pages, actions and contacts in source order', (
    WidgetTester tester,
  ) async {
    await _open<int>(tester, const <GoToEntry<int>>[
      GoToEntry<int>(
        id: 'contact',
        value: 3,
        label: 'Sample contact',
        category: GoToCategory.addresses,
      ),
      GoToEntry<int>(
        id: 'action',
        value: 2,
        label: 'Delegate to a pillar',
        category: GoToCategory.actions,
      ),
      GoToEntry<int>(
        id: 'page',
        value: 1,
        label: 'Delegation',
        detail: 'Nodes',
      ),
    ]);
    expect(find.text('PAGES'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.text('ADDRESSES'), findsOneWidget);
    expect(
      tester.getTopLeft(_row('page')).dy,
      lessThan(tester.getTopLeft(_row('action')).dy),
    );
    expect(
      tester.getTopLeft(_row('action')).dy,
      lessThan(tester.getTopLeft(_row('contact')).dy),
    );
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('↑↓'), findsOneWidget);
    expect(find.text('↵'), findsOneWidget);
    expect(find.text('Ctrl 8'), findsOneWidget);
    expect(find.text('Ctrl R'), findsOneWidget);
  });

  testWidgets(
    'prefixes precede substrings and visible matches are emphasized',
    (
      WidgetTester tester,
    ) async {
      await _open<int>(tester, const <GoToEntry<int>>[
        GoToEntry<int>(id: 'contains', value: 1, label: 'Redelegate'),
        GoToEntry<int>(id: 'prefix', value: 2, label: 'Delegate to a pillar'),
      ]);
      await tester.enterText(find.byKey(_field), '  DeL  ');
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(_row('prefix')).dy,
        lessThan(tester.getTopLeft(_row('contains')).dy),
      );
      final RichText label = tester.widget<RichText>(
        _rowRichText('prefix', 'Delegate to a pillar'),
      );
      expect(label.text.toPlainText(), 'Delegate to a pillar');
      final List<TextSpan> spans = <TextSpan>[];
      label.text.visitChildren((InlineSpan span) {
        if (span is TextSpan && span.text != null) {
          spans.add(span);
        }
        return true;
      });
      final TextSpan first = spans.first;
      expect(first.text, 'Del');
      expect(first.style!.fontWeight, FontWeight.w600);
      expect(_rowSemantics(tester, 'prefix').properties.selected, isTrue);
    },
  );

  testWidgets('aliases and contextual labels participate in filtering', (
    WidgetTester tester,
  ) async {
    await _open<int>(tester, const <GoToEntry<int>>[
      GoToEntry<int>(
        id: 'nodes',
        value: 1,
        label: 'Nodes',
        searchTerms: <String>['Delegation', 'Pillars'],
      ),
      GoToEntry<int>(
        id: 'cache',
        value: 2,
        label: 'Delete cache',
        detail: 'Settings',
        category: GoToCategory.actions,
      ),
    ]);
    await tester.enterText(find.byKey(_field), 'delegation');
    await tester.pumpAndSettle();
    expect(_row('nodes'), findsOneWidget);
    expect(_row('cache'), findsNothing);
    await tester.enterText(find.byKey(_field), 'settings');
    await tester.pumpAndSettle();
    expect(_row('cache'), findsOneWidget);
    expect(_row('nodes'), findsNothing);
    await tester.enterText(find.byKey(_field), 'unknown');
    await tester.pumpAndSettle();
    expect(find.text('None yet'), findsOneWidget);
    expect(find.text('PAGES'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(_field), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'equal display names and shortened ends retain exact identities',
    (
      WidgetTester tester,
    ) async {
      const String first = 'z1same00000000000000000000000000000000tail';
      const String second = 'z1same11111111111111111111111111111111tail';
      final List<String?> answers = <String?>[];
      await _open<String>(
        tester,
        const <GoToEntry<String>>[
          GoToEntry<String>(
            id: 'first',
            value: first,
            label: 'Friend',
            identifier: first,
            category: GoToCategory.addresses,
          ),
          GoToEntry<String>(
            id: 'second',
            value: second,
            label: 'Friend',
            identifier: second,
            category: GoToCategory.addresses,
          ),
        ],
        answers: answers,
      );
      expect(find.text('z1same…tail', findRichText: true), findsNWidgets(2));
      expect(tester.widget<Tooltip>(_tooltip(_row('first'))).message, first);
      expect(tester.widget<Tooltip>(_tooltip(_row('second'))).message, second);
      expect(
        _rowSemantics(tester, 'second').properties.label,
        contains(second),
      );
      await tester.enterText(find.byKey(_field), second);
      await tester.pumpAndSettle();
      expect(_row('first'), findsNothing);
      expect(_row('second'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(answers, <String?>[second]);
    },
  );

  testWidgets(
    'live replacements retain query and identity but answer new value',
    (
      WidgetTester tester,
    ) async {
      const List<GoToEntry<int>> initial = <GoToEntry<int>>[
        GoToEntry<int>(id: 'first', value: 1, label: 'Delegate'),
        GoToEntry<int>(id: 'kept', value: 2, label: 'Delete cache'),
      ];
      final ValueNotifier<List<GoToEntry<int>>> entries =
          ValueNotifier<List<GoToEntry<int>>>(initial);
      addTearDown(entries.dispose);
      final List<int?> answers = <int?>[];
      await _open<int>(tester, initial, liveEntries: entries, answers: answers);
      await tester.enterText(find.byKey(_field), 'del');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_rowSemantics(tester, 'kept').properties.selected, isTrue);
      final GestureDetector previousRow = tester.widget<GestureDetector>(
        find.descendant(
          of: _row('kept'),
          matching: find.byType(GestureDetector),
        ),
      );
      entries.value = const <GoToEntry<int>>[
        GoToEntry<int>(id: 'kept', value: 99, label: 'Delete cache now'),
        GoToEntry<int>(id: 'first', value: 1, label: 'Delegate'),
      ];
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_field)).controller!.text,
        'del',
      );
      expect(_rowSemantics(tester, 'kept').properties.selected, isTrue);
      previousRow.onTap!();
      await tester.pumpAndSettle();
      expect(answers, <int?>[99]);
    },
  );

  testWidgets(
    'removing the highlighted entry chooses an available replacement',
    (
      WidgetTester tester,
    ) async {
      const List<GoToEntry<int>> initial = <GoToEntry<int>>[
        GoToEntry<int>(id: 'first', value: 1, label: 'Home'),
        GoToEntry<int>(id: 'second', value: 2, label: 'Transfer'),
      ];
      final ValueNotifier<List<GoToEntry<int>>> entries =
          ValueNotifier<List<GoToEntry<int>>>(initial);
      addTearDown(entries.dispose);
      await _open<int>(tester, initial, liveEntries: entries);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final GestureDetector removedRow = tester.widget<GestureDetector>(
        find.descendant(
          of: _row('second'),
          matching: find.byType(GestureDetector),
        ),
      );
      entries.value = const <GoToEntry<int>>[
        GoToEntry<int>(id: 'first', value: 1, label: 'Home'),
      ];
      await tester.pumpAndSettle();
      removedRow.onTap!();
      await tester.pumpAndSettle();
      expect(find.byKey(_field), findsOneWidget);
      expect(_rowSemantics(tester, 'first').properties.selected, isTrue);
      entries.value = const <GoToEntry<int>>[];
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('None yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard scrolling counts headings and query changes reset it', (
    WidgetTester tester,
  ) async {
    await _open<int>(tester, <GoToEntry<int>>[
      for (int i = 0; i < 24; i++)
        GoToEntry<int>(
          id: 'entry_$i',
          value: i,
          label: 'Entry $i',
          category: i < 8
              ? GoToCategory.pages
              : i < 16
              ? GoToCategory.actions
              : GoToCategory.addresses,
        ),
    ]);
    for (int i = 0; i < 23; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final Rect viewport = tester.getRect(find.byKey(_results));
    final Rect last = tester.getRect(_row('entry_23'));
    expect(last.top, greaterThanOrEqualTo(viewport.top));
    expect(last.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(_rowSemantics(tester, 'entry_23').properties.selected, isTrue);
    await tester.enterText(find.byKey(_field), 'Entry 0');
    await tester.pumpAndSettle();
    final ListView list = tester.widget<ListView>(find.byKey(_results));
    expect(list.controller!.offset, 0);
    expect(_rowSemantics(tester, 'entry_0').properties.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_rowSemantics(tester, 'entry_0').properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composition keeps Enter until the text is committed', (
    WidgetTester tester,
  ) async {
    final List<int?> answers = <int?>[];
    await _open<int>(
      tester,
      const <GoToEntry<int>>[
        GoToEntry<int>(id: 'delegate', value: 1, label: 'Delegate'),
      ],
      answers: answers,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'del',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(answers, isEmpty);
    expect(find.byKey(_field), findsOneWidget);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'del',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answers, <int?>[1]);
  });

  testWidgets('a stale row callback answers once and never invokes its value', (
    WidgetTester tester,
  ) async {
    int invoked = 0;
    void action() => invoked++;
    final List<VoidCallback?> answers = <VoidCallback?>[];
    await _open<VoidCallback>(
      tester,
      <GoToEntry<VoidCallback>>[
        GoToEntry<VoidCallback>(id: 'action', value: action, label: 'Send'),
      ],
      answers: answers,
    );
    final GestureDetector row = tester.widget<GestureDetector>(
      find.descendant(
        of: _row('action'),
        matching: find.byType(GestureDetector),
      ),
    );
    row.onTap!();
    row.onTap!();
    await tester.pumpAndSettle();
    expect(answers, hasLength(1));
    expect(answers.single, same(action));
    expect(invoked, 0);
    expect(find.text('Open'), findsOneWidget);
  });

  for (final Seam seam in Seam.values) {
    testWidgets('${seam.name} refuses taps, indirect selection and Enter', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        final List<int?> answers = <int?>[];
        await _open<int>(
          tester,
          <GoToEntry<int>>[
            GoToEntry<int>(
              id: 'missing',
              value: 1,
              label: 'Missing action',
              seam: seam,
              category: GoToCategory.actions,
            ),
          ],
          answers: answers,
        );
        final Finder gate = find.byType(SeamGate);
        expect(gate, findsOneWidget);
        expect(tester.widget<Tooltip>(_tooltip(gate)).message, 'Not yet');
        final SemanticsNode disabled = tester.getSemantics(gate);
        expect(
          disabled,
          isSemantics(
            label: 'Not yet',
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        expect(
          disabled.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        final GestureDetector row = tester.widget<GestureDetector>(
          find.descendant(
            of: _row('missing'),
            matching: find.byType(GestureDetector),
          ),
        );
        await tester.tapAt(tester.getCenter(_row('missing')));
        row.onTap!();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(answers, isEmpty);
        expect(find.byKey(_field), findsOneWidget);
        expect(_rowSemantics(tester, 'missing').properties.selected, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(answers, <int?>[null]);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('arrows wrap around available rows and skip a missing action', (
    WidgetTester tester,
  ) async {
    await _open<int>(tester, const <GoToEntry<int>>[
      GoToEntry<int>(id: 'first', value: 1, label: 'First'),
      GoToEntry<int>(
        id: 'missing',
        value: 2,
        label: 'Missing',
        seam: Seam.zapSend,
      ),
      GoToEntry<int>(id: 'last', value: 3, label: 'Last'),
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowSemantics(tester, 'last').properties.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowSemantics(tester, 'first').properties.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_rowSemantics(tester, 'last').properties.selected, isTrue);
  });

  testWidgets(
    'Escape restores the surviving field and reopening clears query',
    (
      WidgetTester tester,
    ) async {
      final FocusNode previous = FocusNode();
      addTearDown(previous.dispose);
      late BuildContext opener;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (BuildContext context) {
              opener = context;
              return TextField(focusNode: previous, autofocus: true);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(previous.hasPrimaryFocus, isTrue);
      final Future<int?> answer = showGoToPalette<int>(
        context: opener,
        entries: const <GoToEntry<int>>[
          GoToEntry<int>(id: 'home', value: 1, label: 'Home'),
        ],
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_field), 'ho');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer, isNull);
      expect(previous.hasPrimaryFocus, isTrue);
      final Future<int?> reopened = showGoToPalette<int>(
        context: opener,
        entries: const <GoToEntry<int>>[
          GoToEntry<int>(id: 'home', value: 1, label: 'Home'),
        ],
        chordName: 'Cmd',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(_field)).controller!.text,
        isEmpty,
      );
      expect(find.text('Cmd 8'), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(await reopened, isNull);
    },
  );
}
