import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

void main() {
  for (final MapEntry<String, ThemeData> entry in <String, ThemeData>{
    'dark': AppTheme.darkTheme,
    'light': AppTheme.lightTheme,
  }.entries) {
    final ThemeData theme = entry.value;
    final AppTokens tokens = entry.key == 'dark'
        ? AppTokens.dark
        : AppTokens.light;

    group('${entry.key} semantic theme', () {
      test('Material surfaces and foregrounds follow their tokens', () {
        expect(theme.extension<AppTokens>(), tokens);
        expect(theme.scaffoldBackgroundColor, tokens.background);
        expect(theme.colorScheme.surface, tokens.background);
        expect(theme.colorScheme.onSurface, tokens.foreground);
        expect(theme.colorScheme.primary, tokens.card);
        expect(theme.colorScheme.primary, isNot(tokens.znn));
        expect(theme.colorScheme.primaryContainer, tokens.card2);
        expect(theme.colorScheme.onPrimary, tokens.foreground);
        expect(theme.colorScheme.onPrimaryContainer, tokens.foreground);
        expect(theme.colorScheme.surfaceContainerLow, tokens.card);
        expect(theme.colorScheme.surfaceContainer, tokens.card2);
        expect(theme.colorScheme.surfaceContainerHigh, tokens.card3);
        expect(theme.colorScheme.outline, tokens.line);
        expect(theme.colorScheme.onSurfaceVariant, tokens.dim);
        expect(theme.dividerTheme.color, tokens.line);
        expect(theme.iconTheme.color, tokens.dim);
        expect(theme.hoverColor, tokens.hover);
      });

      test('field and error roles remain distinct in each theme', () {
        final InputDecorationThemeData input = theme.inputDecorationTheme;
        expect(input.filled, isTrue);
        expect(input.fillColor, tokens.card2);
        expect(input.hintStyle!.color, tokens.faint);
        expect(input.errorStyle!.color, tokens.error);
        expect(theme.colorScheme.error, tokens.error);
        expect(tokens.error, isNot(tokens.pink));
        expect(input.enabledBorder!.borderSide.color, tokens.line);
        expect(input.focusedBorder!.borderSide.color, tokens.faint);
        expect(input.errorBorder!.borderSide.color, tokens.error);
        expect(input.focusedErrorBorder!.borderSide.color, tokens.error);
      });

      test('interface text keeps its bundled face and numeric features', () {
        final TextTheme text = theme.textTheme;
        expect(text.bodyMedium!.fontSize, 14);
        expect(text.bodyMedium!.color, tokens.foreground);
        expect(text.titleMedium!.color, tokens.dim);
        expect(text.labelLarge!.fontWeight, FontWeight.w600);
        expect(text.displayLarge!.fontSize, tokens.heroAmountText.fontSize);
        for (final TextStyle? style in <TextStyle?>[
          text.displayLarge,
          text.displayMedium,
          text.displaySmall,
          text.headlineLarge,
          text.headlineMedium,
          text.headlineSmall,
          text.titleLarge,
          text.titleMedium,
          text.titleSmall,
          text.bodyLarge,
          text.bodyMedium,
          text.bodySmall,
          text.labelLarge,
          text.labelMedium,
          text.labelSmall,
        ]) {
          expect(style!.fontFamily, kSansFontFamily);
          expect(style.fontFamilyFallback, kFontFamilyFallback);
          expect(
            style.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
        }
      });
    });
  }

  test('light errors use their own crimson rather than the dark value', () {
    expect(AppTheme.lightTheme.colorScheme.error, const Color(0xFFD40037));
    expect(AppTheme.darkTheme.colorScheme.error, const Color(0xFFF40442));
  });
}
