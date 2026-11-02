import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

Map<String, Color> _colors(AppTokens tokens) => <String, Color>{
  'background': tokens.background,
  'card': tokens.card,
  'card2': tokens.card2,
  'card3': tokens.card3,
  'line': tokens.line,
  'foreground': tokens.foreground,
  'dim': tokens.dim,
  'faint': tokens.faint,
  'znn': tokens.znn,
  'znnInk': tokens.znnInk,
  'qsr': tokens.qsr,
  'qsrInk': tokens.qsrInk,
  'pink': tokens.pink,
  'pinkInk': tokens.pinkInk,
  'error': tokens.error,
  'warn': tokens.warn,
  'page': tokens.page,
  'onZnn': tokens.onZnn,
  'glass': tokens.glass,
  'hover': tokens.hover,
  'focusRing': tokens.focusRing,
};

void main() {
  test('the original constructor keeps working without new arguments', () {
    const AppTokens legacy = AppTokens(
      faint: AppColors.faint,
      znnInk: AppColors.znnColor,
      qsrInk: AppColors.qsrInk,
      warn: AppColors.warn,
      hover: Color(0x0DFFFFFF),
      focusRing: AppColors.znnColor,
      panelGap: 14,
      cardGap: 11,
      cardRadius: kCardRadius,
    );
    final AppTokens expected = AppTokens.dark.copyWith(cardGap: 11);
    expect(legacy, expected);
    expect(legacy.hashCode, expected.hashCode);
    expect(legacy.card, AppTokens.dark.card);
    expect(legacy.plasma, AppTokens.dark.plasma);
    expect(legacy.sansFontFamily, kSansFontFamily);
  });

  test('all semantic colours move with the ThemeExtension', () {
    final AppTokens end = AppTokens.light.copyWith(
      znn: const Color(0xFF123456),
      qsr: const Color(0xFF345678),
      pink: const Color(0xFF56789A),
      onZnn: const Color(0xFF789ABC),
      panelGap: 30,
      cardGap: 18,
      cardRadius: 16,
    );
    final Map<String, Color> from = _colors(AppTokens.dark);
    final Map<String, Color> to = _colors(end);
    final AppTokens mid = AppTokens.dark.lerp(end, 0.5);
    for (final MapEntry<String, Color> entry in _colors(mid).entries) {
      expect(
        entry.value,
        Color.lerp(from[entry.key], to[entry.key], 0.5),
        reason: entry.key,
      );
    }
    expect(mid.panelGap, 22);
    expect(mid.cardGap, 14);
    expect(mid.cardRadius, 12);
    expect(AppTokens.dark.lerp(end, 0), AppTokens.dark);
    expect(AppTokens.dark.lerp(end, 1), end);
    expect(end.copyWith(), end);
    expect(end.copyWith().hashCode, end.hashCode);
  });

  test('a changed gradient participates in interpolation and equality', () {
    // Both mockup themes keep the same stops while their colours change.
    // CSS colours carry no MaterialColor swatch metadata, which Color.lerp
    // discards even at the end of a gradient interpolation.
    const LinearGradient alternate = LinearGradient(
      transform: GradientRotation(0.17453292519943295),
      colors: <Color>[
        Color(0xFF2196F3),
        Color(0xFF9C27B0),
        Color(0xFFF44336),
      ],
      stops: <double>[0, 0.55, 1],
    );
    final AppTokens end = AppTokens.dark.copyWith(plasma: alternate);
    final AppTokens mid = AppTokens.dark.lerp(end, 0.5);
    expect(end, isNot(AppTokens.dark));
    expect(end.plasma, alternate);
    expect(end.copyWith().hashCode, end.hashCode);
    expect(mid.plasma.stops, <double>[0, 0.55, 1]);
    expect(
      mid.plasma.colors[1],
      Color.lerp(AppColors.plasmaMiddle, alternate.colors[1], 0.5),
    );
    expect(AppTokens.dark.lerp(end, 0).plasma, kPlasmaGradient);
    final AppTokens completed = AppTokens.dark.lerp(end, 1);
    expect(completed, end);
    expect(completed.hashCode, end.hashCode);
  });

  test('families and curves switch at the midpoint without losing copies', () {
    final AppTokens end = AppTokens.dark.copyWith(
      sansFontFamily: 'OtherSans',
      monoFontFamily: 'OtherMono',
      ease: Curves.linear,
      spring: Curves.easeIn,
    );
    final AppTokens before = AppTokens.dark.lerp(end, 0.49);
    final AppTokens after = AppTokens.dark.lerp(end, 0.5);
    expect(before.sansFontFamily, kSansFontFamily);
    expect(before.monoFontFamily, kMonoFontFamily);
    expect(before.ease, AppTokens.dark.ease);
    expect(before.spring, AppTokens.dark.spring);
    expect(after.sansFontFamily, 'OtherSans');
    expect(after.monoFontFamily, 'OtherMono');
    expect(after.ease, Curves.linear);
    expect(after.spring, Curves.easeIn);
    expect(end.bodyText.fontFamily, 'OtherSans');
    expect(end.dataText.fontFamily, 'OtherMono');
    expect(end.copyWith(), end);
    expect(end.copyWith().hashCode, end.hashCode);
  });

  test('ThemeData interpolation carries the complete app token set', () {
    final ThemeData mid = ThemeData.lerp(
      AppTheme.darkTheme,
      AppTheme.lightTheme,
      0.5,
    );
    expect(
      mid.extension<AppTokens>(),
      AppTokens.dark.lerp(AppTokens.light, 0.5),
    );
    expect(AppTokens.dark.lerp(null, 0.5), AppTokens.dark);
  });
}
