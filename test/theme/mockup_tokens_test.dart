import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

Map<String, String> _properties(String css, String selector) {
  final RegExpMatch block = RegExp(
    '${RegExp.escape(selector)}\\{([^}]+)\\}',
  ).firstMatch(css)!;
  return <String, String>{
    for (final RegExpMatch property in RegExp(
      r'(--[\w-]+)\s*:\s*([^;]+);',
    ).allMatches(block.group(1)!))
      property.group(1)!: property.group(2)!.trim(),
  };
}

Color _color(String css) {
  if (css.startsWith('#')) {
    return Color(0xFF000000 | int.parse(css.substring(1), radix: 16));
  }
  final List<String> channels = RegExp(
    r'^rgba\(([^)]+)\)$',
  ).firstMatch(css)!.group(1)!.split(',');
  return Color.fromRGBO(
    int.parse(channels[0]),
    int.parse(channels[1]),
    int.parse(channels[2]),
    double.parse(channels[3]),
  );
}

Map<String, Color> _colors(AppTokens tokens) => <String, Color>{
  '--bg': tokens.background,
  '--card': tokens.card,
  '--card2': tokens.card2,
  '--card3': tokens.card3,
  '--line': tokens.line,
  '--fg': tokens.foreground,
  '--dim': tokens.dim,
  '--faint': tokens.faint,
  '--znn': tokens.znn,
  '--znn-ink': tokens.znnInk,
  '--qsr': tokens.qsr,
  '--qsr-ink': tokens.qsrInk,
  '--pink': tokens.pink,
  '--pink-ink': tokens.pinkInk,
  '--err': tokens.error,
  '--warn': tokens.warn,
  '--page': tokens.page,
  '--on-znn': tokens.onZnn,
  '--glass': tokens.glass,
};

Curve _curve(String css) {
  final List<double> points = RegExp(
    r'^cubic-bezier\(([^)]+)\)$',
  ).firstMatch(css)!.group(1)!.split(',').map(double.parse).toList();
  return Cubic(points[0], points[1], points[2], points[3]);
}

void main() {
  final String css = File(
    'mockups/redesign/src/00-head.html',
  ).readAsStringSync();
  final String rules = File('docs/design/RULES.md').readAsStringSync();
  final RegExpMatch brand = RegExp(
    r'Green `(#[\da-fA-F]{6})` is brand and success, '
    r'blue `(#[\da-fA-F]{6})` is info and pending',
  ).firstMatch(rules)!;
  // The owner selected the rules for brand fills. Keep the original mockup
  // source intact and retain its separate, theme-specific readable inks.
  final Map<String, String> dark = <String, String>{
    ..._properties(css, ':root'),
    '--znn': brand.group(1)!,
    '--znn-ink': brand.group(1)!,
    '--qsr': brand.group(2)!,
  };
  final Map<String, String> light = <String, String>{
    ...dark,
    ..._properties(css, ':root[data-theme="light"]'),
  };

  test('system light and explicit light use the same overrides', () {
    expect(
      _properties(css, ':root:not([data-theme="dark"])'),
      _properties(css, ':root[data-theme="light"]'),
    );
  });

  for (final MapEntry<String, AppTokens> theme in <String, AppTokens>{
    'dark': AppTokens.dark,
    'light': AppTokens.light,
  }.entries) {
    final Map<String, String> source = theme.key == 'dark' ? dark : light;
    final AppTokens tokens = theme.value;

    group('${theme.key} design tokens', () {
      test('every root property has a token', () {
        expect(source.keys.toSet(), <String>{
          ..._colors(tokens).keys,
          '--sans',
          '--mono',
          '--r',
          '--ease',
          '--spring',
          '--plasma',
        });
      });

      test('surface and ink values follow the selected sources', () {
        for (final MapEntry<String, Color> token in _colors(tokens).entries) {
          expect(token.value, _color(source[token.key]!), reason: token.key);
        }
        expect(tokens.error, isNot(tokens.pink));
      });

      test('bundled family aliases match the inline font families', () {
        String firstFamily(String property) => RegExp(
          '^"([^"]+)"',
        ).firstMatch(source[property]!)!.group(1)!.replaceAll(' ', '');
        expect(tokens.sansFontFamily, firstFamily('--sans'));
        expect(tokens.monoFontFamily, firstFamily('--mono'));
        expect(tokens.cardRadius, double.parse(source['--r']!.split('px')[0]));
      });

      test('colour and movement curves follow the CSS control points', () {
        for (final MapEntry<String, Curve> entry in <String, Curve>{
          '--ease': tokens.ease,
          '--spring': tokens.spring,
        }.entries) {
          final Curve expected = _curve(source[entry.key]!);
          for (final double t in <double>[0, 0.1, 0.25, 0.5, 0.75, 1]) {
            expect(entry.value.transform(t), expected.transform(t));
          }
        }
      });

      test('the primary gradient keeps its colours, stop and angle', () {
        final RegExpMatch gradient = RegExp(
          r'^linear-gradient\(([\d.]+)deg,var\(--znn\),'
          r'(#[\da-fA-F]{6}) ([\d.]+)%,var\(--qsr\)\)$',
        ).firstMatch(source['--plasma']!)!;
        expect(tokens.plasma.colors, <Color>[
          _color(source['--znn']!),
          _color(gradient.group(2)!),
          _color(source['--qsr']!),
        ]);
        expect(tokens.plasma.stops, <double>[
          0,
          double.parse(gradient.group(3)!) / 100,
          1,
        ]);
        expect(tokens.plasma.begin, Alignment.centerLeft);
        expect(tokens.plasma.end, Alignment.centerRight);
        final GradientRotation rotation =
            tokens.plasma.transform! as GradientRotation;
        expect(
          rotation.radians,
          closeTo(
            (double.parse(gradient.group(1)!) - 90) * math.pi / 180,
            1e-12,
          ),
        );
      });

      test('data and ledger styles keep mono, figures and tracking', () {
        expect(tokens.bodyText.fontFamily, kSansFontFamily);
        expect(tokens.bodyText.fontSize, 14);
        expect(tokens.bodyText.height, 1.45);
        expect(tokens.bodyText.letterSpacing, 0);
        expect(tokens.headingText.fontWeight, FontWeight.w600);
        expect(tokens.buttonText.fontWeight, FontWeight.w600);
        for (final TextStyle style in <TextStyle>[
          tokens.dataText,
          tokens.heroAmountText,
          tokens.stripAmountText,
          tokens.ledgerText,
          tokens.dollarText,
        ]) {
          expect(style.fontFamily, kMonoFontFamily);
          expect(style.fontFamilyFallback, kFontFamilyFallback);
          expect(
            style.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
        }
        expect(tokens.heroAmountText.fontSize, 34);
        expect(tokens.heroAmountText.height, 1.1);
        expect(tokens.heroAmountText.letterSpacing, -0.34);
        expect(tokens.stripAmountText.fontSize, 19);
        expect(tokens.ledgerText.fontSize, 11);
        expect(tokens.ledgerText.letterSpacing, 0.66);
        expect(tokens.dollarText.fontSize, 13);
        expect(tokens.dollarText.color, tokens.faint);
        expect(tokens.dataText.color, tokens.foreground);
      });

      test('component measures keep the mockup shape and glass layers', () {
        expect(tokens.pageGap, 12);
        expect(tokens.cardGap, 10);
        expect(tokens.inlineGap, 8);
        expect(
          tokens.cardPadding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );
        expect(tokens.dialogRadius, 12);
        expect(tokens.toastRadius, 10);
        expect(tokens.compactRadius, 6);
        expect(tokens.pillRadius, 999);
        expect(tokens.fieldHeight, 42);
        expect(tokens.buttonHeight, 38);
        expect(tokens.compactButtonHeight, 30);
        expect(tokens.smallButtonHeight, 26);
        expect(tokens.overlayBlur, 6);
        expect(tokens.dialogBlur, 10);
        expect(tokens.panelBlur, 12);
        expect(tokens.menuBlur, 10);
        expect(tokens.overlayScrim, const Color.fromRGBO(0, 0, 0, 0.35));
        expect(
          tokens.glassTopEdge.color,
          const Color.fromRGBO(255, 255, 255, 0.06),
        );
        expect(tokens.dialogShadow.offset, const Offset(0, 20));
        expect(tokens.dialogShadow.blurRadius, 60);
        expect(tokens.panelShadow.offset, const Offset(-20, 0));
        expect(tokens.toastShadow.blurRadius, 36);
        expect(tokens.menuShadow.blurRadius, 30);
        expect(tokens.tooltipShadow.blurRadius, 18);
        expect(tokens.primaryButtonForeground, const Color(0xFF04140A));
      });
    });
  }
}
