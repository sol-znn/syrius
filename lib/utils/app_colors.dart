import 'package:material_ui/material_ui.dart';

/// The selected design-rule palette and compatibility colours.
class AppColors {
  /// The brand and success green shared by both themes.
  static const Color znnColor = Color(0xFF00D557);

  /// The information and pending blue shared by both themes.
  static const Color qsrColor = Color(0xFF0061EB);

  /// The legacy token ink, separate from the plasma accent.
  static const Color ztsColor = Color(0xFFFC54AE);

  /// The Zenon design system's pink, the hot end of the plasma glow's ramp
  /// (`assets/shaders/heatmap.frag`) and one light of the hero field. For
  /// plasma surfaces only: [ztsColor] stays the ink for tokens.
  static const Color plasmaPink = Color(0xFFF91690);

  /// The middle stop of the mockup's primary-action gradient.
  static const Color plasmaMiddle = Color(0xFF35B7A0);

  /// The reserved accent as text on a dark surface.
  static const Color darkPinkInk = Color(0xFFFF5FB3);

  /// The reserved accent as text on a light surface.
  static const Color lightPinkInk = Color(0xFFD92F8C);

  /// The dark theme's crimson for errors and refused operations.
  static const Color errorColor = Color(0xFFF40442);

  /// The light theme's crimson for errors and refused operations.
  static const Color lightErrorColor = Color(0xFFD40037);

  /// The light wallet window background.
  static const Color backgroundLight = Color(0xFFEAEAEA);

  /// The dark wallet window background.
  static const Color backgroundDark = Color(0xFF1B1C1B);

  /// The primary text ink on light surfaces.
  static const Color foregroundLight = Color(0xFF141614);

  /// The primary text ink on dark surfaces.
  static const Color foregroundDark = Color(0xFFF1F4F1);

  /// The review page's background, outside the wallet window.
  static const Color pageLight = Color(0xFFDCDDDC);

  /// The dark review page behind the wallet window.
  static const Color pageDark = Color(0xFF121312);

  /// The dark mark drawn on a ZNN token fill.
  static const Color onZnn = Color(0xFF06230D);

  /// The light card colour with glass opacity included.
  static const Color glassLight = Color.fromRGBO(246, 247, 246, 0.88);

  /// The dark card colour with glass opacity included.
  static const Color glassDark = Color.fromRGBO(38, 39, 38, 0.86);

  /// Secondary prose and quiet addresses on dark surfaces.
  static const Color subtitleColor = Color(0xFFA5AAA5);

  /// Secondary prose and quiet addresses on light surfaces.
  static const Color lightSubtitleColor = Color(0xFF535853);

  /// The legacy outline of the Max amount control.
  static const Color maxAmountBorder = Color(0xFF474747);

  /// The legacy inactive icon tone in the light theme.
  static const Color lightSecondary = Color(0xFFB3B3B3);

  /// The legacy light-theme unselected-control ink.
  static const Color lightSecondaryContainer = Color(0xFF545454);

  /// The legacy dark secondary surface.
  static const Color darkSecondary = Color(0xFF3F3F3F);

  /// The legacy dark unselected-control surface.
  static const Color darkSecondaryContainer = Color.fromRGBO(46, 46, 46, 1);

  /// The legacy notification attention colour.
  static const Color alertNotification = Color(0xFFDAE240);

  /// The legacy surface behind wallet-access controls.
  static const Color accessWalletContainersGray = Color.fromRGBO(46, 46, 46, 1);

  /// The legacy inactive icon and disabled-control tone.
  static const Color inactiveIconsGray = Color.fromRGBO(51, 51, 51, 1);

  /// The dark theme's card surface.
  static const Color darkPrimary = Color(0xFF262726);

  /// The dark theme's field and expanded-row surface.
  static const Color darkPrimaryContainer = Color(0xFF2E302E);

  /// The light theme's card surface.
  static const Color lightPrimaryContainer = Color(0xFFF6F7F6);

  /// The light theme's field and expanded-row surface.
  static const Color lightCard2 = Color(0xFFFFFFFF);

  /// The light theme's selected-segment surface.
  static const Color lightCard3 = Color(0xFFEEF0EE);

  /// The dark theme's selected-segment surface.
  static const Color darkCard3 = Color(0xFF363836);

  /// The light theme's divider and outline.
  static const Color lightDividerColor = Color(0xFFD5D8D5);

  /// The dark theme's divider and outline.
  static const Color darkDividerColor = Color(0xFF383A38);

  /// The compatibility name for the light field surface.
  static const Color lightTextFormFieldFill = lightCard2;

  /// The compatibility name for the dark field surface.
  static const Color darkTextFormFieldFill = darkPrimaryContainer;

  /// The legacy dark hint ink for unmigrated field callers.
  static const Color darkHintTextColor = Color.fromRGBO(99, 99, 99, 1);

  /// The legacy light hint ink for unmigrated field callers.
  static const Color lightHintTextColor = Color.fromRGBO(179, 179, 179, 1);

  /// The underline beneath a seed-word input.
  static const Color seedUnderlineBorderColor = Color.fromRGBO(99, 99, 99, 1);

  /// The legacy ink of an unselected seed-word choice.
  static const Color unselectedSeedChoiceColor = Color(0xFF636363);

  /// The legacy fill of a selected seed-word choice.
  static const Color selectedSeedChoiceColor = Color(0xFF292929);

  /// Text that is present but secondary: units, insignificant zeros, labels.
  static const Color faint = Color(0xFF717671);

  /// QSR as text on a dark card; [qsrColor] is too dark to read there.
  static const Color qsrInk = Color(0xFF5B9DFF);

  /// Needs the person: an update, a missed momentum.
  static const Color warn = Color(0xFFDAB544);
}
