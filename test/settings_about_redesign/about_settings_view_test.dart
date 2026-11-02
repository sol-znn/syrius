import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_information.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/licences.dart';

import 'support.dart';

Future<AboutInformation> _information() async => AboutInformation(
  version: '9.8.7-rc.2',
  buildNumber: '00042',
  details: <AboutField, String>{AboutField.commit: 'abcdef1234567890'},
);

Stream<LicenseEntry> _emptyLicences() => const Stream<LicenseEntry>.empty();

Text _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey<String>(key)));

Future<void> _toggle(WidgetTester tester, String key) async {
  final Finder toggle = find.byKey(ValueKey<String>(key));
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
      'About is full width with closed groups in variant $variant',
      (
        WidgetTester tester,
      ) async {
        prepareAboutViewport(tester);
        int registryReads = 0;
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            aboutHost(
              AboutCard(
                loadInformation: _information,
                loadLicences: () {
                  registryReads++;
                  return _emptyLicences();
                },
              ),
              light: variant.$1,
              rtl: variant.$2,
              scale: variant.$3,
            ),
          );
          await tester.pump();
          expect(
            tester.getSize(find.byKey(const Key('about_strip'))).width,
            1000,
          );
          expect(_text(tester, 'about_version').data, '9.8.7-rc.2');
          expect(_text(tester, 'about_embedded_version').data, 'Unknown');
          expect(_text(tester, 'about_build').data, '00042 · abcdef12');
          expect(find.text('Confirm'), findsNothing);
          expect(find.text('0.3.0 is out'), findsNothing);
          expect(find.text('18'), findsOneWidget);
          expect(registryReads, 0);
          expect(find.byType(Licences), findsNothing);
          final Iterable<Disclosure> groups = tester.widgetList<Disclosure>(
            find.byType(Disclosure),
          );
          expect(groups.length, 3);
          expect(
            groups.every((Disclosure group) => !group.initiallyOpen),
            isTrue,
          );
          expect(
            groups.every((Disclosure group) => group.storeKey == null),
            isTrue,
          );
          expect(
            find.byKey(const Key('about_link_0')).hitTestable(),
            findsNothing,
          );
          expect(find.semantics.byLabel('Open folder'), findsNothing);
          expect(find.byType(SeamGate), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  aboutTestWidgets('all eighteen original URLs stay wired to their own rows', (
    WidgetTester tester,
  ) async {
    prepareAboutViewport(tester);
    final List<String> opened = <String>[];
    const String whitepaper =
        'https://github.com/zenon-network/zenon.network/releases/download/'
        'whitepaper/whitepaper.pdf';
    const List<String> expected = <String>[
      'https://zenon.network',
      'https://forum.zenon.org',
      'https://zenon.tools',
      'https://zenon.org',
      'https://zenonhub.io',
      'https://explorer.zenon.network',
      'https://zenonhub.io/explorer',
      'https://twitter.com/Zenon_Network',
      'https://discord.gg/zenonnetwork',
      'https://t.me/zenonnetwork',
      'https://medium.com/@zenon.network',
      'https://github.com/zenon-network',
      'https://bitcointalk.org/index.php?topic=5279643.msg55303681#msg55303681',
      'https://reddit.com/r/Zenon_Network',
      'https://youtube.com/channel/UCDb8ZtqBt6l5l4HugCnJwhQ',
      'https://wiki.zenon.network',
      'https://docs.zenon.org',
      whitepaper,
    ];
    await tester.pumpWidget(
      aboutHost(
        AboutCard(
          loadInformation: _information,
          loadLicences: _emptyLicences,
          openLink: opened.add,
        ),
      ),
    );
    await _toggle(tester, 'about_links_toggle');
    for (int index = 0; index < expected.length; index++) {
      final Finder row = find.byKey(ValueKey<String>('about_link_$index'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
    }
    expect(opened, expected);
    await _toggle(tester, 'about_links_toggle');
    expect(find.byKey(const Key('about_link_0')).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  aboutTestWidgets('replaced metadata cannot overwrite its successor', (
    WidgetTester tester,
  ) async {
    prepareAboutViewport(tester);
    final Completer<AboutInformation> original = Completer<AboutInformation>();
    final Completer<AboutInformation> replacement =
        Completer<AboutInformation>();
    Future<AboutInformation> oldSource() => original.future;
    Future<AboutInformation> newSource() => replacement.future;
    await tester.pumpWidget(
      aboutHost(
        AboutCard(
          loadInformation: oldSource,
          loadLicences: _emptyLicences,
        ),
      ),
    );
    await tester.pumpWidget(
      aboutHost(
        AboutCard(
          loadInformation: newSource,
          loadLicences: _emptyLicences,
        ),
      ),
    );
    replacement.complete(AboutInformation(version: 'replacement'));
    await tester.pump();
    expect(_text(tester, 'about_version').data, 'replacement');
    original.complete(AboutInformation(version: 'obsolete'));
    await tester.pump();
    expect(_text(tester, 'about_version').data, 'replacement');
    expect(find.text('obsolete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  aboutTestWidgets(
    'metadata failure and completion after disposal stay bounded',
    (
      WidgetTester tester,
    ) async {
      prepareAboutViewport(tester);
      final Completer<AboutInformation> source = Completer<AboutInformation>();
      await tester.pumpWidget(
        aboutHost(
          AboutCard(
            loadInformation: () => Future<AboutInformation>.error(
              StateError('synthetic private diagnostic'),
            ),
            loadLicences: _emptyLicences,
          ),
        ),
      );
      await tester.pump();
      expect(_text(tester, 'about_version').data, 'Unknown');
      expect(_text(tester, 'about_build').data, 'Unknown');
      expect(find.textContaining('private diagnostic'), findsNothing);
      await tester.pumpWidget(
        aboutHost(
          AboutCard(
            loadInformation: () => source.future,
            loadLicences: _emptyLicences,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      source.complete(AboutInformation(version: 'detached'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  aboutTestWidgets(
    'computer actions use actual nonempty paths and safe web origins',
    (WidgetTester tester) async {
      prepareAboutViewport(tester);
      final List<String> folders = <String>[];
      final List<String> links = <String>[];
      await tester.pumpWidget(
        aboutHost(
          AboutCard(
            loadInformation: () async => AboutInformation(
              details: <AboutField, String>{
                AboutField.origin: 'file:fixture-origin',
                AboutField.cache: 'fixture-cache',
                AboutField.wallet: '',
              },
            ),
            loadLicences: _emptyLicences,
            openLink: links.add,
            openFolder: (String path) async => folders.add(path),
          ),
        ),
      );
      await tester.pump();
      await _toggle(tester, 'about_computer_toggle');
      final Finder cache = find.byKey(const Key('about_info_cache'));
      await tester.ensureVisible(cache);
      await tester.tap(
        find.descendant(
          of: cache,
          matching: find.byTooltip('Open folder'),
        ),
      );
      await tester.pump();
      expect(folders, <String>['fixture-cache']);
      expect(links, isEmpty);
      expect(
        find.descendant(
          of: find.byKey(const Key('about_info_wallet')),
          matching: find.byTooltip('Open folder'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('about_info_origin')),
          matching: find.byTooltip('Open link'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  aboutTestWidgets(
    'update actions refuse pointer keyboard and direct activation',
    (
      WidgetTester tester,
    ) async {
      prepareAboutViewport(tester);
      await tester.pumpWidget(
        aboutHost(
          const AboutCard(
            loadInformation: _information,
            loadLicences: _emptyLicences,
          ),
        ),
      );
      await tester.pump();
      final Finder update = find.byKey(const Key('about_what_changed'));
      final OutlinedButton button = tester.widget<OutlinedButton>(update);
      expect(button.onPressed, isNotNull);
      expect(button.onPressed, throwsA(isA<SeamNotBuilt>()));
      await tester.tap(update, warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        find.byKey(const Key('about_link_0')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  aboutTestWidgets(
    'licences read once on opening and retain the end hook on closing',
    (WidgetTester tester) async {
      prepareAboutViewport(tester);
      int reads = 0;
      final Completer<AboutInformation> information =
          Completer<AboutInformation>();
      await tester.pumpWidget(
        aboutHost(
          AboutCard(
            loadInformation: () => information.future,
            loadLicences: () {
              reads++;
              return Stream<LicenseEntry>.value(
                FixtureLicence(
                  <String>['fixture-package'],
                  const <LicenseParagraph>[
                    LicenseParagraph('Fixture licence text', 0),
                  ],
                ),
              );
            },
            licencesTrailingBuilder: (_) => const Text('Fixture end hook'),
            afterLicences: const Text(
              'Fixture separate card',
              key: Key('fixture_after'),
            ),
          ),
        ),
      );
      expect(reads, 0);
      await _toggle(tester, 'about_licences_toggle');
      await tester.pump();
      expect(reads, 1);
      expect(find.text('Fixture end hook'), findsOneWidget);
      final Element originalList = tester.element(find.byType(Licences));
      information.complete(AboutInformation(version: 'late-package-info'));
      await tester.pump();
      expect(
        identical(originalList, tester.element(find.byType(Licences))),
        isTrue,
      );
      expect(find.byKey(const Key('fixture_after')), findsOneWidget);
      await _toggle(tester, 'about_licences_toggle');
      expect(find.text('Fixture end hook').hitTestable(), findsNothing);
      await _toggle(tester, 'about_licences_toggle');
      expect(reads, 1);
      expect(find.text('Fixture end hook'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
