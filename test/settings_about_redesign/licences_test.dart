import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/licences.dart';

import 'support.dart';

Future<void> _open(WidgetTester tester, String package) async {
  final Finder toggle = find.byKey(
    ValueKey<String>('about_licence_${package}_toggle'),
  );
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
}

void main() {
  for (final (bool, bool, double) variant in <(bool, bool, double)>[
    (false, false, 1),
    (true, true, 1.5),
  ]) {
    aboutTestWidgets(
      'genuine packages and complete paragraphs in variant $variant',
      (WidgetTester tester) async {
        prepareAboutViewport(tester);
        const String firstText =
            'A complete synthetic licence paragraph. '
            'Every word stays available without truncating the legal text.';
        const String secondText =
            'A second independent notice for the same package.';
        await tester.pumpWidget(
          aboutHost(
            Licences(
              loadLicences: () => Stream<LicenseEntry>.fromIterable(
                <LicenseEntry>[
                  FixtureLicence(
                    <String>['zeta', 'alpha'],
                    const <LicenseParagraph>[
                      LicenseParagraph(
                        'Synthetic notice title',
                        LicenseParagraph.centeredIndent,
                      ),
                      LicenseParagraph(firstText, 1),
                    ],
                  ),
                  FixtureLicence(
                    <String>['alpha', 'alpha'],
                    const <LicenseParagraph>[LicenseParagraph(secondText, 0)],
                  ),
                  FixtureLicence(
                    <String>['Fixture Font'],
                    const <LicenseParagraph>[
                      LicenseParagraph(
                        'Synthetic font terms. Preserve these words.',
                        0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            light: variant.$1,
            rtl: variant.$2,
            scale: variant.$3,
            width: 700,
            height: 500,
          ),
        );
        await tester.pump();
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('zeta'), findsOneWidget);
        expect(find.text('Fixture Font'), findsOneWidget);
        expect(find.text('MIT'), findsNothing);
        await _open(tester, 'alpha');
        expect(find.text(firstText), findsOneWidget);
        expect(find.text(secondText), findsOneWidget);
        final SelectableText title = tester.widget<SelectableText>(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is SelectableText &&
                widget.data == 'Synthetic notice title',
          ),
        );
        expect(title.textAlign, TextAlign.center);
        expect(title.maxLines, isNull);
        final SelectableText paragraph = tester.widget<SelectableText>(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is SelectableText && widget.data == firstText,
          ),
        );
        expect(paragraph.maxLines, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  aboutTestWidgets(
    'end hook waits for complete enumeration and follows final row',
    (
      WidgetTester tester,
    ) async {
      prepareAboutViewport(tester);
      final StreamController<LicenseEntry> entries =
          StreamController<LicenseEntry>();
      int hookBuilds = 0;
      await tester.pumpWidget(
        aboutHost(
          Licences(
            loadLicences: () => entries.stream,
            trailingBuilder: (_) {
              hookBuilds++;
              return const SizedBox(
                height: 44,
                child: Text('Fixture final hook', key: Key('fixture_hook')),
              );
            },
          ),
          width: 700,
          height: 240,
        ),
      );
      for (int index = 0; index < 30; index++) {
        entries.add(
          FixtureLicence(
            <String>['package-${index.toString().padLeft(2, '0')}'],
            const <LicenseParagraph>[LicenseParagraph('Fixture terms', 0)],
          ),
        );
      }
      await tester.pump();
      expect(find.byKey(const Key('about_licences_loading')), findsOneWidget);
      expect(hookBuilds, 0);
      await observeAboutFuture(
        tester,
        entries.close(),
        operation: 'complete registry close',
      );
      await tester.pump();
      expect(find.byKey(const Key('fixture_hook')).hitTestable(), findsNothing);
      final Finder scrollable = find.descendant(
        of: find.byKey(const Key('about_licences_list')),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('fixture_hook')),
        200,
        scrollable: scrollable,
        maxScrolls: 20,
      );
      expect(hookBuilds, greaterThan(0));
      final Finder hook = find.byKey(const Key('fixture_hook'));
      final Finder finalRow = find.byKey(
        const Key('about_licence_package-29'),
      );
      expect(hook.hitTestable(), findsOneWidget);
      final double hookTop = tester.getTopLeft(hook).dy;
      final double rowBottom = tester.getBottomLeft(finalRow).dy;
      expect(
        hookTop - rowBottom,
        greaterThanOrEqualTo(-precisionErrorTolerance),
      );
      expect(tester.takeException(), isNull);
    },
  );

  aboutTestWidgets(
    'failed enumeration exposes no partial end hook and can retry',
    (
      WidgetTester tester,
    ) async {
      prepareAboutViewport(tester);
      int attempts = 0;
      int hookBuilds = 0;
      await tester.pumpWidget(
        aboutHost(
          Licences(
            loadLicences: () {
              attempts++;
              if (attempts == 1) {
                return Stream<LicenseEntry>.error(
                  StateError('synthetic private diagnostic'),
                );
              }
              return Stream<LicenseEntry>.value(
                FixtureLicence(
                  <String>['retried-package'],
                  const <LicenseParagraph>[
                    LicenseParagraph('Complete fixture terms', 0),
                  ],
                ),
              );
            },
            trailingBuilder: (_) {
              hookBuilds++;
              return const Text('Fixture final hook');
            },
          ),
          width: 700,
          height: 240,
        ),
      );
      await tester.pump();
      expect(find.text('Could not load licences. Try again.'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(hookBuilds, 0);
      await tester.tap(find.byKey(const Key('about_licences_retry')));
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('retried-package'), findsOneWidget);
      expect(find.text('Fixture final hook'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  aboutTestWidgets('source replacement cancels the original subscription', (
    WidgetTester tester,
  ) async {
    prepareAboutViewport(tester);
    int cancelled = 0;
    final StreamController<LicenseEntry> original =
        StreamController<LicenseEntry>(
          onCancel: () => cancelled++,
        );
    Stream<LicenseEntry> originalSource() => original.stream;
    Stream<LicenseEntry> replacement() => Stream<LicenseEntry>.value(
      FixtureLicence(
        <String>['replacement-package'],
        const <LicenseParagraph>[LicenseParagraph('Replacement terms', 0)],
      ),
    );
    await tester.pumpWidget(aboutHost(Licences(loadLicences: originalSource)));
    original.add(
      FixtureLicence(
        <String>['old-partial-package'],
        const <LicenseParagraph>[LicenseParagraph('Old partial terms', 0)],
      ),
    );
    await tester.pump();
    await tester.pumpWidget(aboutHost(Licences(loadLicences: replacement)));
    await tester.pump();
    expect(cancelled, 1);
    expect(find.text('replacement-package'), findsOneWidget);
    expect(find.text('old-partial-package'), findsNothing);
    await observeAboutFuture(
      tester,
      original.close(),
      operation: 'replaced registry close',
    );
    expect(tester.takeException(), isNull);
  });

  aboutTestWidgets('unmount cancels an unfinished registry read', (
    WidgetTester tester,
  ) async {
    prepareAboutViewport(tester);
    int cancelled = 0;
    final StreamController<LicenseEntry> entries =
        StreamController<LicenseEntry>(
          onCancel: () => cancelled++,
        );
    await tester.pumpWidget(
      aboutHost(Licences(loadLicences: () => entries.stream)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancelled, 1);
    await observeAboutFuture(
      tester,
      entries.close(),
      operation: 'unmounted registry close',
    );
    expect(tester.takeException(), isNull);
  });

  aboutTestWidgets('empty registry is honest and has no hidden end content', (
    WidgetTester tester,
  ) async {
    prepareAboutViewport(tester);
    int hookBuilds = 0;
    await tester.pumpWidget(
      aboutHost(
        Licences(
          loadLicences: () => const Stream<LicenseEntry>.empty(),
          trailingBuilder: (_) {
            hookBuilds++;
            return const Text('Fixture final hook');
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('None yet'), findsOneWidget);
    expect(hookBuilds, 0);
    expect(tester.takeException(), isNull);
  });
}
