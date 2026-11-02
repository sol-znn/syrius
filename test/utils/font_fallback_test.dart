import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/infinite_scroll_table/infinite_scroll_table.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Pumps [child] under [theme] in [locale] and returns a context below the
/// app's `Material`, where a `Text` would be built.
Future<BuildContext> _pump(
  WidgetTester tester,
  ThemeData theme, {
  Locale locale = const Locale('en'),
  Widget child = const SizedBox.shrink(),
}) async {
  late BuildContext inner;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      locale: locale,
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('es'),
        Locale('ar'),
        Locale('hi'),
        Locale('zh'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Material(
        child: Builder(
          builder: (BuildContext context) {
            inner = context;
            return child;
          },
        ),
      ),
    ),
  );
  return inner;
}

/// The style the engine is handed for the text [data].
TextStyle _paintedStyle(WidgetTester tester, String data) {
  final RichText rich = tester.widget<RichText>(
    find.descendant(of: find.text(data), matching: find.byType(RichText)),
  );
  return rich.text.style!;
}

void main() {
  final Map<String, ThemeData> themes = <String, ThemeData>{
    'dark': AppTheme.darkTheme,
    'light': AppTheme.lightTheme,
  };

  group('the fallback list', () {
    test('opens with the two bundled faces, Arabic first', () {
      expect(kFontFamilyFallback.take(2), <String>[
        kArabicFontFamily,
        kDevanagariFontFamily,
      ]);
    });

    test('names Simplified Chinese before the system faces of the other '
        'two scripts, and no other Han face', () {
      const List<String> han = <String>[
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Source Han Sans SC',
        'WenQuanYi Micro Hei',
      ];
      expect(kFontFamilyFallback[2], kSansCoverageFontFamily);
      expect(kFontFamilyFallback.sublist(3, 3 + han.length), han);
      expect(kFontFamilyFallback.sublist(3 + han.length), <String>[
        'Segoe UI',
        'Nirmala UI',
        'Geeza Pro',
        'Kohinoor Devanagari',
      ]);
    });

    // A family named here and spelt otherwise in the pubspec is no error
    // anywhere: the engine skips a name it does not know.
    test('names its bundled faces as the pubspec declares them, and every '
        'declared file is a font', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final List<String> families = RegExp(
        r'^    - family: (\S+)\s*$',
        multiLine: true,
      ).allMatches(pubspec).map((RegExpMatch m) => m.group(1)!).toList();
      expect(
        families,
        containsAll(<String>[
          kSansFontFamily,
          kSansCoverageFontFamily,
          kMonoFontFamily,
          kArabicFontFamily,
          kDevanagariFontFamily,
        ]),
      );

      final List<String> files = RegExp(
        r'^        - asset: (assets/fonts/\S+)\s*$',
        multiLine: true,
      ).allMatches(pubspec).map((RegExpMatch m) => m.group(1)!).toList();
      for (final String script in <String>['Arabic', 'Devanagari']) {
        for (final String weight in <String>['Regular', 'Medium', 'Bold']) {
          expect(files, contains('assets/fonts/NotoSans$script-$weight.ttf'));
        }
      }
      for (final String path in files) {
        final File file = File(path);
        expect(file.existsSync(), isTrue, reason: path);
        // TrueType outlines, or `OTTO` for CFF.
        expect(
          file.openSync().readSync(4),
          anyOf(equals(<int>[0, 1, 0, 0]), equals('OTTO'.codeUnits)),
          reason: path,
        );
      }
    });

    test('the semibold is a static 600 face and font licenses are bundled', () {
      final ByteData font = ByteData.sublistView(
        File('assets/fonts/SpaceGrotesk-SemiBold.ttf').readAsBytesSync(),
      );
      expect(font.getUint32(0), 0x00010000);
      final int tables = font.getUint16(4);
      int? weight;
      final Set<String> tags = <String>{};
      for (int i = 0; i < tables; i++) {
        final int entry = 12 + 16 * i;
        final String tag = String.fromCharCodes(<int>[
          for (int j = 0; j < 4; j++) font.getUint8(entry + j),
        ]);
        tags.add(tag);
        if (tag == 'OS/2') {
          weight = font.getUint16(font.getUint32(entry + 8) + 4);
        }
      }
      expect(weight, 600);
      expect(tags, isNot(contains('fvar')));
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains(
          'asset: assets/fonts/SpaceGrotesk-SemiBold.ttf\n'
          '          weight: 600',
        ),
      );
      for (final String name in <String>[
        'OFL-SpaceGrotesk.txt',
        'OFL-JetBrainsMono.txt',
        'OFL-NotoSans.txt',
      ]) {
        expect(pubspec, contains('    - assets/fonts/$name\n'));
        expect(File('assets/fonts/$name').readAsStringSync(), contains('1.1'));
      }
    });
  });

  for (final MapEntry<String, ThemeData> entry in themes.entries) {
    group('the ${entry.key} theme', () {
      testWidgets('every text theme style keeps Space Grotesk and carries '
          'the fallback list', (WidgetTester tester) async {
        final BuildContext context = await _pump(tester, entry.value);
        final TextTheme text = Theme.of(context).textTheme;
        final Map<String, TextStyle?> styles = <String, TextStyle?>{
          'displayLarge': text.displayLarge,
          'displayMedium': text.displayMedium,
          'displaySmall': text.displaySmall,
          'headlineLarge': text.headlineLarge,
          'headlineMedium': text.headlineMedium,
          'headlineSmall': text.headlineSmall,
          'titleLarge': text.titleLarge,
          'titleMedium': text.titleMedium,
          'titleSmall': text.titleSmall,
          'bodyLarge': text.bodyLarge,
          'bodyMedium': text.bodyMedium,
          'bodySmall': text.bodySmall,
          'labelLarge': text.labelLarge,
          'labelMedium': text.labelMedium,
          'labelSmall': text.labelSmall,
        };
        for (final MapEntry<String, TextStyle?> style in styles.entries) {
          expect(style.value!.fontFamily, kSansFontFamily, reason: style.key);
          expect(
            style.value!.fontFamilyFallback,
            kFontFamilyFallback,
            reason: style.key,
          );
        }
        expect(text.bodyMedium!.fontFamilyFallback!.take(2), <String>[
          kArabicFontFamily,
          kDevanagariFontFamily,
        ]);
      });

      testWidgets('the default text style carries it', (
        WidgetTester tester,
      ) async {
        final BuildContext context = await _pump(tester, entry.value);
        final TextStyle style = DefaultTextStyle.of(context).style;
        expect(style.fontFamily, kSansFontFamily);
        expect(style.fontFamilyFallback, kFontFamilyFallback);
      });

      // Material picks another geometry for these scripts; it must not
      // take the list with it.
      for (final String language in <String>['ar', 'hi', 'zh']) {
        testWidgets('the list survives the $language locale', (
          WidgetTester tester,
        ) async {
          final BuildContext context = await _pump(
            tester,
            entry.value,
            locale: Locale(language),
          );
          final TextStyle body = Theme.of(context).textTheme.bodyMedium!;
          expect(body.fontFamily, kSansFontFamily);
          expect(body.fontFamilyFallback, kFontFamilyFallback);
        });
      }

      testWidgets('monoStyle keeps JetBrains Mono and carries it, with a '
          'base and without', (WidgetTester tester) async {
        final BuildContext context = await _pump(tester, entry.value);
        for (final TextStyle style in <TextStyle>[
          monoStyle(null),
          monoStyle(Theme.of(context).textTheme.bodyMedium),
          monoStyle(const TextStyle(fontFamily: kSansFontFamily)),
        ]) {
          expect(style.fontFamily, kMonoFontFamily);
          expect(style.fontFamilyFallback, kFontFamilyFallback);
        }
      });

      // The app builds many styles from nothing and names the family in
      // them. In a Text they are merged into the default style, which is
      // what hands them the list.
      testWidgets('a Text whose style names only the family is painted '
          'with the list', (WidgetTester tester) async {
        await _pump(
          tester,
          entry.value,
          child: const Text(
            'label',
            style: TextStyle(fontFamily: kSansFontFamily, fontSize: 12),
          ),
        );
        final TextStyle painted = _paintedStyle(tester, 'label');
        expect(painted.fontFamily, kSansFontFamily);
        expect(painted.fontFamilyFallback, kFontFamilyFallback);
      });

      testWidgets('ledgerLabelStyle is spaced in Latin script only', (
        WidgetTester tester,
      ) async {
        for (final String language in <String>['en', 'es']) {
          final TextStyle style = ledgerLabelStyle(
            await _pump(tester, entry.value, locale: Locale(language)),
          );
          expect(style.letterSpacing, 0.66, reason: language);
          expect(style.fontFamily, kMonoFontFamily);
          expect(style.fontFamilyFallback, kFontFamilyFallback);
          expect(style.fontSize, 11);
        }
        for (final String language in <String>['ar', 'hi', 'zh']) {
          final TextStyle style = ledgerLabelStyle(
            await _pump(tester, entry.value, locale: Locale(language)),
          );
          expect(style.letterSpacing, 0, reason: language);
          expect(style.fontFamilyFallback, kFontFamilyFallback);
          expect(style.fontSize, 11);
        }
      });

      testWidgets('a Figure label is capitals in English and as written in '
          'Arabic', (WidgetTester tester) async {
        await _pump(
          tester,
          entry.value,
          child: const Figure(label: 'Balance', value: '1'),
        );
        expect(find.text('BALANCE'), findsOneWidget);
        expect(_paintedStyle(tester, 'BALANCE').letterSpacing, 0.66);

        // Latin letters, so that a capital would show.
        await _pump(
          tester,
          entry.value,
          locale: const Locale('ar'),
          child: const Figure(label: 'Balance', value: '1'),
        );
        expect(find.text('Balance'), findsOneWidget);
        expect(_paintedStyle(tester, 'Balance').letterSpacing, 0);
      });

      testWidgets('a table head is spaced capitals in English and as '
          'written in Arabic', (WidgetTester tester) async {
        const Widget head = Row(
          children: <Widget>[
            InfiniteScrollTableColumn(
              alignment: MainAxisAlignment.start,
              name: 'Amount',
            ),
          ],
        );
        await _pump(tester, entry.value, child: head);
        expect(find.text('AMOUNT'), findsOneWidget);
        TextStyle painted = _paintedStyle(tester, 'AMOUNT');
        expect(painted.letterSpacing, 0.66);
        expect(painted.fontFamily, kMonoFontFamily);
        expect(painted.fontFamilyFallback, kFontFamilyFallback);

        await _pump(
          tester,
          entry.value,
          locale: const Locale('ar'),
          child: head,
        );
        expect(find.text('Amount'), findsOneWidget);
        painted = _paintedStyle(tester, 'Amount');
        expect(painted.letterSpacing, 0);
        expect(painted.fontFamilyFallback, kFontFamilyFallback);
      });

      // A button's `textStyle` replaces the default style instead of being
      // merged into it. The engine reads family and fallbacks as one list,
      // so the list on a style with no family would put the button's Latin
      // label in the first face of the list that has the letter.
      testWidgets('a button label never has the list without a family', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          entry.value,
          child: Column(
            children: <Widget>[
              TextButton(onPressed: () {}, child: const Text('text')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              ElevatedButton(onPressed: () {}, child: const Text('elevated')),
            ],
          ),
        );
        for (final String label in <String>['text', 'outlined', 'elevated']) {
          final TextStyle painted = _paintedStyle(tester, label);
          if (painted.fontFamilyFallback != null) {
            expect(painted.fontFamily, isNotNull, reason: label);
          }
        }
      });

      // The two button themes set a `textStyle`, which is the whole label
      // style: one without a family was drawn in the system's face. Compact
      // labels use Medium; the main outlined label uses the bundled SemiBold.
      testWidgets('a button label is Space Grotesk with the list', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          entry.value,
          child: Column(
            children: <Widget>[
              TextButton(onPressed: () {}, child: const Text('text')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              ElevatedButton(onPressed: () {}, child: const Text('elevated')),
            ],
          ),
        );
        for (final String label in <String>['text', 'outlined', 'elevated']) {
          final TextStyle painted = _paintedStyle(tester, label);
          expect(painted.fontFamily, kSansFontFamily, reason: label);
          expect(
            painted.fontFamilyFallback,
            kFontFamilyFallback,
            reason: label,
          );
        }
        expect(_paintedStyle(tester, 'text').fontWeight, FontWeight.w500);
        expect(_paintedStyle(tester, 'outlined').fontWeight, FontWeight.w600);
        expect(_paintedStyle(tester, 'text').fontSize, 13);
        expect(_paintedStyle(tester, 'outlined').fontSize, 14);
      });

      testWidgets('cardSecondaryButtonStyle labels are Space Grotesk with '
          'the list', (WidgetTester tester) async {
        final BuildContext context = await _pump(tester, entry.value);
        final TextStyle style = cardSecondaryButtonStyle(
          context,
        ).textStyle!.resolve(<WidgetState>{})!;
        expect(style.fontFamily, kSansFontFamily);
        expect(style.fontFamilyFallback, kFontFamilyFallback);
        expect(style.fontWeight, FontWeight.w500);
        expect(style.fontSize, 13);

        await _pump(
          tester,
          entry.value,
          child: CardSecondaryButtons(
            child: OutlinedButton(
              onPressed: () {},
              child: const Text('secondary'),
            ),
          ),
        );
        final TextStyle painted = _paintedStyle(tester, 'secondary');
        expect(painted.fontFamily, kSansFontFamily);
        expect(painted.fontFamilyFallback, kFontFamilyFallback);
      });
    });
  }
}
