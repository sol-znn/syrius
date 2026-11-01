import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';

/// The desktop's semantic values, including the surfaces used by Material.
/// Surfaces and motion follow `mockups/redesign/src/00-head.html`; brand
/// fills follow the owner-selected `docs/design/RULES.md` palette. Every
/// root custom property has a named counterpart here:
///
/// | Mockup | Token |
/// | --- | --- |
/// | `--bg` | [background] |
/// | `--card` | [card] |
/// | `--card2` | [card2] |
/// | `--card3` | [card3] |
/// | `--line` | [line] |
/// | `--fg` | [foreground] |
/// | `--dim` | [dim] |
/// | `--faint` | [faint] |
/// | `--znn` | [znn] |
/// | `--znn-ink` | [znnInk] |
/// | `--qsr` | [qsr] |
/// | `--qsr-ink` | [qsrInk] |
/// | `--pink` | [pink] |
/// | `--pink-ink` | [pinkInk] |
/// | `--err` | [error] |
/// | `--warn` | [warn] |
/// | `--page` | [page] |
/// | `--on-znn` | [onZnn] |
/// | `--glass` | [glass] |
/// | `--sans` | [sansFontFamily], the bundled SpaceGrotesk alias |
/// | `--mono` | [monoFontFamily], the bundled JetBrainsMono alias |
/// | `--r` | [cardRadius] |
/// | `--ease` | [ease] |
/// | `--spring` | [spring] |
/// | `--plasma` | [plasma] |
///
/// The named type styles, measures, shadows and blur values below come from
/// the same file's component rules. Those measures are shared by both
/// themes because the CSS only overrides colours. The review-only [page]
/// colour stays separate from the wallet's [background].
///
/// They are a [ThemeExtension] and not constants for two reasons. A constant
/// is the same in both themes, and several of these must not be: the green
/// that reads on a dark card is too pale to be text on a white one, and so
/// are the dark theme's QSR blue and warning yellow. And an extension has a
/// [lerp], so a change of theme moves these with every other colour instead
/// of jumping at the end.
///
/// Read them with [AppTokens.of]:
///
/// ```dart
/// final AppTokens tokens = AppTokens.of(context);
/// Text('QSR', style: TextStyle(color: tokens.qsrInk));
/// ```
///
/// The statics on [AppColors] keep their dark-theme values for the code that
/// still reads them.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Creates a set of tokens.
  const AppTokens({
    required this.faint,
    required this.znnInk,
    required this.qsrInk,
    required this.warn,
    required this.hover,
    required this.focusRing,
    required this.panelGap,
    required this.cardGap,
    required this.cardRadius,
    this.background = AppColors.backgroundDark,
    this.card = AppColors.darkPrimary,
    this.card2 = AppColors.darkPrimaryContainer,
    this.card3 = AppColors.darkCard3,
    this.line = AppColors.darkDividerColor,
    this.foreground = AppColors.foregroundDark,
    this.dim = AppColors.subtitleColor,
    this.znn = AppColors.znnColor,
    this.qsr = AppColors.qsrColor,
    this.pink = AppColors.plasmaPink,
    this.pinkInk = AppColors.darkPinkInk,
    this.error = AppColors.errorColor,
    this.page = AppColors.pageDark,
    this.onZnn = AppColors.onZnn,
    this.glass = AppColors.glassDark,
    this.sansFontFamily = kSansFontFamily,
    this.monoFontFamily = kMonoFontFamily,
    this.ease = const Cubic(0.4, 0, 0.2, 1),
    this.spring = const Cubic(0.2, 0.8, 0.2, 1),
    this.plasma = kPlasmaGradient,
  });

  /// One qualified Zap receipt paints this many decorative sparks.
  static const int zapSparkCount = 28;

  /// The complete receive effect follows the Home motion table.
  static const Duration zapSparkDuration = Duration(milliseconds: 900);

  /// The original dot diameter before its outward fade.
  static const double zapSparkDiameter = 6;

  /// The nearest final radial destination in logical pixels.
  static const double zapSparkMinDistance = 120;

  /// The farthest final radial destination in logical pixels.
  static const double zapSparkMaxDistance = 280;

  /// The final spark scale at the end of its fade.
  static const double zapSparkEndScale = 0.2;

  /// The tokens of the theme in use. A theme that carries none (a bare
  /// MaterialApp in a test) gets the set for its brightness.
  static AppTokens of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.light ? light : dark);
  }

  /// The dark theme's tokens: the values the `AppColors` statics hold.
  static const AppTokens dark = AppTokens(
    faint: AppColors.faint,
    znnInk: AppColors.znnColor,
    qsrInk: AppColors.qsrInk,
    warn: AppColors.warn,
    hover: Color(0x0DFFFFFF),
    focusRing: AppColors.znnColor,
    panelGap: 14,
    cardGap: 10,
    cardRadius: kCardRadius,
  );

  /// The light theme's values, including the quieter faint tone from the
  /// mockup. Main text, token inks and faint text keep distinct roles.
  static const AppTokens light = AppTokens(
    faint: Color(0xFF858A85),
    znnInk: Color(0xFF168A35),
    qsrInk: Color(0xFF0058D6),
    warn: Color(0xFF93700A),
    hover: Color(0x0A000000),
    focusRing: Color(0xFF168A35),
    panelGap: 14,
    cardGap: 10,
    cardRadius: kCardRadius,
    background: AppColors.backgroundLight,
    card: AppColors.lightPrimaryContainer,
    card2: AppColors.lightCard2,
    card3: AppColors.lightCard3,
    line: AppColors.lightDividerColor,
    foreground: AppColors.foregroundLight,
    dim: AppColors.lightSubtitleColor,
    pinkInk: AppColors.lightPinkInk,
    error: AppColors.lightErrorColor,
    page: AppColors.pageLight,
    glass: AppColors.glassLight,
  );

  /// Text that is present but secondary: units, ledger labels, quiet icons.
  final Color faint;

  /// ZNN green as text or as a line. The brand green itself
  /// ([AppColors.znnColor]) stays the fill of the primary button in both
  /// themes.
  final Color znnInk;

  /// QSR blue as text.
  final Color qsrInk;

  /// Needs the person: an update, a missed momentum.
  final Color warn;

  /// Laid over a surface under the pointer: a table row, a menu item.
  final Color hover;

  /// The line round a control that has the keyboard focus.
  final Color focusRing;

  /// The gap between panels on a page.
  final double panelGap;

  /// The gap between two fields, or two rows, inside a card.
  final double cardGap;

  /// The corner radius of a card and of a field. Buttons are pills.
  final double cardRadius;

  /// The wallet window's background.
  final Color background;

  /// The first raised surface: cards and the status strip.
  final Color card;

  /// A field, an expanded row, or a second raised surface.
  final Color card2;

  /// The selected segment and the highest quiet surface.
  final Color card3;

  /// A divider or the outline of a control.
  final Color line;

  /// The main text and ordinary amounts.
  final Color foreground;

  /// Secondary prose, addresses and inactive controls.
  final Color dim;

  /// The ZNN fill; token ink is [znnInk].
  final Color znn;

  /// The QSR fill; token ink is [qsrInk].
  final Color qsr;

  /// The reserved accent fill; accent text uses [pinkInk].
  final Color pink;

  /// The reserved accent as text.
  final Color pinkInk;

  /// A refused operation or an error, distinct from [pink].
  final Color error;

  /// The review page behind the wallet window.
  final Color page;

  /// The dark mark on a ZNN token fill.
  final Color onZnn;

  /// The card colour with the mockup's glass opacity included.
  final Color glass;

  /// The bundled interface face.
  final String sansFontFamily;

  /// The bundled data face.
  final String monoFontFamily;

  /// The curve for colour and shadow changes.
  final Curve ease;

  /// The curve for movement.
  final Curve spring;

  /// The fill reserved for the primary action or active surface.
  final LinearGradient plasma;

  /// The fixed component measures in `00-head.html`, in logical pixels.
  double get pageGap => 12;

  /// The genuine Windows client caption, shared by every production route.
  double get windowCaptionHeight => 32;

  /// Each native action has the mockup's fixed target width.
  double get windowControlWidth => 44;

  /// The compact caption glyph edge.
  double get windowControlIconSize => 12;

  /// Caption placement stays physical left to right on Windows.
  EdgeInsets get windowCaptionPadding => const EdgeInsets.fromLTRB(14, 0, 4, 0);

  /// The frame follows the active theme without painting a second surface.
  Color get windowCaptionBackground => background;

  /// The close hover uses the semantic error colour.
  Color get windowCloseHover => error.withValues(alpha: 0.12);

  /// The reference's .34em tracking at its 12 px caption size.
  double get windowTitleTracking => 4.08;

  /// Native captures place the ink 2 px right and its center 2.5 px low.
  /// Move its paint toward the reference without moving caption hit targets.
  Offset get windowWordmarkPaintOffset =>
      Offset(-windowTitleTracking / 2, -2.5);

  /// The mockup's quiet tracked wordmark; the native window title stays intact.
  TextStyle get windowTitleText => bodyText.copyWith(
    fontSize: 12,
    letterSpacing: windowTitleTracking,
    color: faint,
  );

  /// The icon-only rail's width.
  double get railCollapsedWidth => 56;

  /// The rail's width with labels shown.
  double get railExpandedWidth => 200;

  /// The rail glyph's edge.
  double get railIconSize => 18;

  /// The inset around the rail's items.
  EdgeInsetsDirectional get railPadding =>
      const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 12);

  /// The height of a rail destination.
  double get railItemHeight => 40;

  /// The height of the rail's chevron row.
  double get railToggleHeight => 32;

  /// The gap between adjacent rail items.
  double get railItemGap => 2;

  /// The content inset inside each rail pill.
  double get railItemInset => 11;

  /// The space between a rail glyph and its label.
  double get railLabelGap => 12;

  /// The edge of the bell's unseen mark.
  double get railDotSize => 7;

  /// The unseen mark's position within its rail item.
  double get railDotStart => 24;

  /// The unseen mark's distance from the item's top.
  double get railDotTop => 10;

  /// The background ring separating the unseen mark from its glyph.
  double get railDotRingWidth => 2;

  /// The width of a keyboard focus outline.
  double get focusWidth => 2;

  /// The clock for opening or closing the rail.
  Duration get railWidthDuration => const Duration(milliseconds: 200);

  /// The label fade after the rail has finished opening.
  Duration get railLabelDuration => const Duration(milliseconds: 150);

  /// The inset of the tooltip beside the rail.
  EdgeInsets get railTooltipPadding =>
      const EdgeInsets.symmetric(horizontal: 10, vertical: 5);

  /// The short label in the tooltip beside the rail.
  TextStyle get railTooltipText => bodyText.copyWith(fontSize: 12.5);

  /// The inset around a keyboard chord in an overlay hint.
  EdgeInsets get keyboardHintPadding =>
      const EdgeInsets.symmetric(horizontal: 6, vertical: 1);

  /// The corner radius of the small keyboard hint outline.
  double get keyboardHintRadius => 4;

  /// The keyboard chord shown in a tooltip or palette.
  TextStyle get keyboardHintText => dataText.copyWith(fontSize: 11, color: dim);

  /// The section menu drawn inside Settings.
  double get settingsMenuWidth => 200;

  /// The balance header's content inset.
  EdgeInsetsDirectional get heroPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 24, vertical: 20);

  /// The separation between balances, plasma and actions.
  double get heroGap => 36;

  /// The gap when a scaled header wraps into another line.
  double get heroStackGap => 20;

  /// The separation between headline balance rows.
  double get heroBalanceGap => 5;

  /// The plasma column's measured desktop width.
  double get heroPlasmaWidth => 220;

  /// The space between transfer entry pills.
  double get heroActionGap => 10;

  /// The transfer entry pills' horizontal inset.
  EdgeInsetsDirectional get heroActionPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16);

  /// The space before a balance's dollar estimate.
  double get heroDollarGap => 12;

  /// The separation when a balance estimate wraps.
  double get heroBalanceRunGap => 4;

  /// The space between an amount and its visible symbol.
  double get heroSymbolGap => 6;

  /// The separation when address controls wrap.
  double get heroAddressRunGap => 2;

  /// The transfer entry and address-choice glyph size.
  double get heroIconSize => 18;

  /// The quiet address-copy glyph size.
  double get heroCopyIconSize => 14;

  /// Home's address controls follow the reference's small inline icons.
  double get heroAddressIconSize => 14;

  /// Hidden balances place the original eye beside the primary amount.
  double get heroHiddenEyeSize => 20;

  /// Home uses the reference's tighter gap around its body panels.
  double get homePanelGap => 12;

  /// The compact side-card heading follows the mockup's table header.
  EdgeInsetsDirectional get homeSideHeaderPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 11, 16, 11);

  /// Side-card headings grow with scaled text from this minimum.
  double get homeSideHeaderHeight => 44;

  /// The token mark remains secondary to its exact balance.
  double get homeTokenBadgeSize => 26;

  /// The token mark's mono initial.
  TextStyle get homeTokenBadgeText => dataText.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: foreground,
  );

  /// The gap between token-row content.
  double get homeTokenRowGap => 8;

  /// Side-card figures use the compact data role.
  TextStyle get homeSideAmountText =>
      dataText.copyWith(fontSize: 13, color: dim);

  /// The compact Collect all pill's horizontal inset.
  EdgeInsetsDirectional get homeSideButtonPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 12);

  /// Activity preserves a compact, aligned ledger at the default text scale.
  EdgeInsetsDirectional get activityRowPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 9);

  /// The activity title shares the side-card heading baseline.
  EdgeInsetsDirectional get activityHeaderPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 11);

  /// The direction mark remains secondary to the data.
  double get activityIconSize => 14;

  /// Activity headings and rows can grow with scaled text.
  double get activityHeaderHeight => 44;

  /// The minimum activity row height.
  double get activityRowHeight => 40;

  /// The quiet Message pill's horizontal inset.
  EdgeInsetsDirectional get activityMessagePadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 10);

  /// Separates the activity's logical columns.
  double get activityColumnGap => 12;

  /// The entry card stays centered at the mockup's width.
  double get lockCardWidth => 420;

  /// The launch film is cropped into a still black well.
  double get lockWellHeight => 118;

  /// Preserve the launch film's original aspect ratio before cropping.
  double get lockFilmWidth => 640;

  /// The launch film's corresponding height.
  double get lockFilmHeight => 360;

  /// The lock controls follow the entry card's inner margins.
  EdgeInsetsDirectional get lockContentPadding =>
      const EdgeInsetsDirectional.fromSTEB(28, 20, 28, 22);

  /// Keeps the lock card reachable in a short window.
  EdgeInsetsDirectional get lockPagePadding =>
      const EdgeInsetsDirectional.all(24);

  /// Password and wallet controls use matching horizontal insets.
  EdgeInsetsDirectional get lockFieldPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 12);

  /// The entry action remains a compact gradient pill.
  double get lockActionHeight => 46;

  /// The entry action's interface type.
  TextStyle get lockActionText =>
      bodyText.copyWith(fontSize: 16, fontWeight: FontWeight.w600);

  /// Auxiliary entry links stay secondary to unlocking.
  TextStyle get lockLinkText => bodyText.copyWith(fontSize: 12.5, color: dim);

  /// The selected wallet's available address uses the data role.
  TextStyle get lockAddressText =>
      dataText.copyWith(fontSize: 12.5, color: dim);

  /// Entry glyphs share a common size.
  double get lockGlyphSize => 16;

  /// The entry surface has a deeper drop over the dark field.
  List<BoxShadow> get lockCardShadow => <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(
        alpha: background.computeLuminance() < 0.5 ? 0.4 : 0.14,
      ),
      offset: const Offset(0, 20),
      blurRadius: 60,
    ),
  ];

  /// The original launch artwork always occupies a black stage.
  Color get launchStageBackground => Colors.black;

  /// The one launch stage settles into the measured lock well.
  Duration get launchSettleDuration => const Duration(milliseconds: 400);

  /// Matches the entry container transform in the original mockup.
  Curve get launchSettleCurve => Easing.emphasizedDecelerate;

  /// The genuine lock card rises as the black movie stage shrinks.
  double get launchLockRise => 12;

  /// Waiting for startup keeps the last frame on screen above this line.
  double get launchWaitingWidth => 120;

  /// The startup indicator remains secondary to the original wordmark.
  double get launchWaitingHeight => 2;

  /// The skip instruction keeps the original inset on the black movie stage.
  double get launchHintBottomInset => 26;

  /// This hint is painted on the original black art in both themes.
  TextStyle get launchHintText => const TextStyle(
    fontFamily: kSansFontFamily,
    fontSize: 12,
    letterSpacing: .48,
    color: Color(0xFF5A5F5A),
  );

  /// Full-size registration art is reserved for a confirmed original block.
  double get registrationArtSize => 340;

  /// The retained registration steps keep their own ledger column.
  double get registrationRailWidth => 300;

  /// Separates the original object from its result labels.
  double get registrationGap => 6;

  /// Leaves a clear boundary before the result actions.
  double get registrationActionGap => 14;

  /// The registration ledger's inset follows the stepper mockup.
  double get registrationInset => 20;

  /// The result content keeps its horizontal breathing room.
  double get registrationBodyInset => 28;

  /// Confirmation detail remains secondary to the object and its heading.
  TextStyle get registrationCaptionText =>
      bodyText.copyWith(fontSize: 14, color: dim);

  /// The confirmed object's short result heading.
  TextStyle get registrationHeadingText =>
      bodyText.copyWith(fontSize: 22, fontWeight: FontWeight.w600);

  /// Aligns the result's heading with the original assembled object.
  double get registrationHeadingOffset => -18;

  /// Leaves room for the result actions below the object.
  EdgeInsetsDirectional get registrationPadding =>
      const EdgeInsetsDirectional.fromSTEB(28, 8, 28, 28);

  /// The Plasma well is distinct from the beneficiary's owned-fusion list.
  double get plasmaWellWidth => 340;

  /// The original Plasma mark's resting size in its dark well.
  double get plasmaMarkSize => 200;

  /// Keeps the mark legible in the minimum window.
  double get plasmaMarkMinSize => 96;

  /// Reserves room for the actual beneficiary plasma and level.
  double get plasmaFiguresHeight => 116;

  /// Other addresses may use this fraction of the well column.
  double get plasmaOtherShare => .45;

  /// The check column does not shift exact fusion amounts.
  double get plasmaCheckboxWidth => 36;

  /// Separates the available and aggregate owner-fused figures.
  double get plasmaStripGap => 28;

  /// Insets the original mark without enlarging its painted bounds.
  EdgeInsetsDirectional get plasmaMarkPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 22, 16, 14);

  /// The beneficiary's plasma remains an exact mono number.
  TextStyle get plasmaAmountText => dataText.copyWith(fontSize: 30);

  /// Separates the glow, exact figure and level label.
  double get plasmaLevelGap => 8;

  /// Keeps the Fused list useful before the page scrolls.
  double get plasmaTableMinHeight => 220;

  /// Actual generation brightens the existing heatmap's inner field.
  double get plasmaGeneratingInnerGlow => .7;

  /// The outer field remains subordinate to the beneficiary's level.
  double get plasmaGeneratingOuterGlow => .4;

  /// A real generation token alone selects the brighter contour.
  double get plasmaGeneratingContour => .65;

  /// Exact token balances retain a consistent row baseline.
  double get tokenRowHeight => 56;

  /// The compact token ledger header's minimum height.
  double get tokenHeaderHeight => 34;

  /// Search stays secondary to the Held, Favorites and All modes.
  double get tokenSearchWidth => 260;

  /// The token search field matches the compact page heading.
  double get tokenSearchHeight => 30;

  /// Reserves space for each token's exact available units.
  double get tokenBalanceWidth => 140;

  /// The supply column may include the genuine maximum.
  double get tokenSupplyWidth => 200;

  /// Owner identifiers retain their dedicated mono column.
  double get tokenOwnerWidth => 160;

  /// Horizontal scrolling preserves all token columns in a narrow window.
  double get tokenTableMinWidth => 1000;

  /// The compact Fuse form keeps its fields on one desktop line.
  EdgeInsetsDirectional get plasmaFuseFormPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 14);

  /// The eligibility note sits directly below the Fuse fields.
  EdgeInsetsDirectional get plasmaFuseNotePadding =>
      const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 12);

  /// The entered QSR remains exact mono data.
  TextStyle get plasmaFuseAmountText => dataText.copyWith(fontSize: 18);

  /// The selected beneficiary and eligibility note stay secondary.
  TextStyle get plasmaFuseHintText =>
      bodyText.copyWith(fontSize: 12.5, color: dim);

  /// The one Fuse action aligns with the compact fields.
  double get plasmaFuseActionHeight => 42;

  /// Other-address meters do not compete with the beneficiary's main meter.
  double get plasmaOtherMeterWidth => 90;

  /// Other addresses form a compact list within the well.
  double get plasmaOtherRowHeight => 30;

  /// The address list follows the well's directional inset.
  EdgeInsetsDirectional get plasmaOtherListPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 12);

  /// Token details align below their identity column.
  double get tokenDetailIndent => 50;

  /// The expanded token leaves room below its retained action form.
  double get tokenDetailBottomInset => 21;

  /// Separates independent token facts.
  double get tokenDetailFactGap => 28;

  /// Separates labels and values in the token fact grid.
  double get tokenDetailColumnGap => 16;

  /// Keeps each token fact's lines together.
  double get tokenDetailLabelGap => 4;

  /// Token actions remain subordinate to their expanded row.
  double get tokenActionFormWidth => 720;

  /// The inline action surface uses the compact form inset.
  EdgeInsetsDirectional get tokenActionFormPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12);

  /// Separates facts, action fields and the factual note.
  double get tokenDetailBodyGap => 12;

  /// Separates exact fields from the one inline action.
  double get tokenActionGap => 10;

  /// Token action fields and their button share one baseline.
  double get tokenActionHeight => 42;

  /// Smallest-unit token amounts keep the data font.
  TextStyle get tokenActionAmountText => dataText.copyWith(fontSize: 16);

  /// Four-step token creation uses one readable form column.
  double get tokenCreateBodyMaxWidth => 620;

  /// The creation body retains room above and below each step.
  double get tokenCreateVerticalInset => 24;

  /// The four-step rail separates progress from its facts.
  double get tokenCreateRailGap => 18;

  /// Numbered step marks share the mockup's compact geometry.
  double get tokenCreateStepMarkSize => 22;

  /// Review labels do not shift exact values when text changes.
  double get tokenCreateReviewLabelWidth => 176;

  /// The wallet menu sits just below its field.
  double get walletPickerMenuGap => 4;

  /// Menu rows keep their own compact pointer target.
  double get walletPickerRowHeight => 34;

  /// Menu contents align with the selected wallet's field.
  EdgeInsetsDirectional get walletPickerRowPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 7);

  /// The menu separates its first and last rows from its border.
  EdgeInsetsDirectional get walletPickerMenuPadding =>
      const EdgeInsetsDirectional.symmetric(vertical: 4);

  /// Menu names retain the ordinary interface role.
  TextStyle get walletPickerNameText => bodyText.copyWith(fontSize: 13);

  /// Wallet identifiers remain mono within the compact menu.
  TextStyle get walletPickerAddressText =>
      dataText.copyWith(fontSize: 12, color: dim);

  /// The reference main column's directional page and status margins.
  EdgeInsetsDirectional get shellPadding =>
      const EdgeInsetsDirectional.fromSTEB(4, 4, 16, 14);

  /// The rail sits beside the main column, which owns its content inset.
  double get shellRailGap => 0;

  /// The status stays separate from the page surface.
  double get shellStatusGap => 12;

  /// The entry field fills the page while its status keeps an outer inset.
  EdgeInsetsDirectional get lockedStatusPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 14);

  /// Hidden amount dots retain the shared privacy tracking.
  double get hiddenAmountTrackingEm => 0.08;

  /// The secondary headline balance, preserving every significant digit.
  TextStyle get heroSecondaryAmountText => dataText.copyWith(
    fontSize: 18,
    height: 1.1,
    letterSpacing: 0,
    color: dim,
  );

  /// Coin symbols remain readable when the amounts are hidden.
  TextStyle get heroSymbolText =>
      bodyText.copyWith(fontSize: 18, fontWeight: FontWeight.w500);

  /// The first balance read's short state label.
  TextStyle get heroLoadingText => bodyText.copyWith(fontSize: 15, color: dim);

  /// A Settings section's compact navigation row.
  double get settingsItemHeight => 38;

  /// The glyph beside a Settings section name.
  double get settingsIconSize => 14;

  /// The space between a compact form label and its field.
  double get fieldLabelGap => 6;

  /// The shell's fixed background-state row.
  double get statusStripHeight => 44;

  /// The background-state row's content inset.
  EdgeInsets get statusStripPadding =>
      const EdgeInsets.symmetric(horizontal: 16, vertical: 9);

  /// The separation between background-state groups.
  double get statusStripGap => 22;

  /// The connection mark's visible diameter.
  double get statusDotSize => 8;

  /// The pulse's furthest halo beyond the connection mark.
  double get statusDotHalo => 7;

  /// One complete connection-status halo cycle.
  Duration get statusPulseDuration => const Duration(milliseconds: 2400);

  /// The inset of one compact Settings row.
  EdgeInsets get settingsRowPadding =>
      const EdgeInsets.symmetric(horizontal: 16, vertical: 9);

  /// The quiet explanation under a setting's name.
  TextStyle get settingsHintText =>
      bodyText.copyWith(fontSize: 12.5, color: dim);

  /// The compact switch's track width.
  double get settingsSwitchWidth => 38;

  /// The compact switch's track height.
  double get settingsSwitchHeight => 22;

  /// The compact switch's thumb diameter.
  double get settingsSwitchThumb => 16;

  /// The thumb inset at either end of its track.
  double get settingsSwitchInset => 3;

  /// The thumb's movement, from the original switch CSS.
  Duration get settingsSwitchDuration => const Duration(milliseconds: 180);

  /// The small outlined language and explorer choices in Settings.
  double get settingsMenuHeight => 30;

  /// Separation of actions that wrap when a Settings form is scaled.
  double get settingsActionGap => 10;

  /// Compact actions beside Security rows.
  double get securitySettingsButtonHeight => 26;

  /// Keeps exact account identifiers and balances readable when scrolled.
  double get addressesTableMinWidth => 920;

  /// Space for the selected-account indicator.
  double get addressesChoiceWidth => 36;

  /// One complete asset balance column in the address table.
  double get addressesBalanceWidth => 168;

  /// Compact account row actions.
  double get addressesActionsWidth => 112;

  /// Contact names precede their full identifiers.
  double get addressesContactNameWidth => 132;

  /// The last committed send fact in a contact row.
  double get addressesLastSentWidth => 200;

  /// Minimum account row height before text scaling adds space.
  double get addressesRowMinHeight => 57;

  /// Minimum contact row height before text scaling adds space.
  double get addressesContactMinHeight => 50;

  /// Exact account identifiers use the data font.
  TextStyle get addressesAddressText => dataText.copyWith(fontSize: 12);

  /// The selected account's quiet label.
  TextStyle get addressesSelectedText => bodyText.copyWith(fontSize: 11);

  /// Directional inset shared by address and contact rows.
  EdgeInsetsDirectional get addressesTablePadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 9, 16, 9);

  /// About labels leave room for their original local values.
  double get aboutInfoLabelWidth => 170;

  /// The height reserved for each closed About disclosure.
  double get aboutGroupHeaderHeight => 44;

  /// Copy and open actions in About metadata rows.
  double get aboutInfoActionSize => 30;

  /// The licence registry remains scrollable in a short window.
  double get aboutLicencesMinHeight => 220;

  /// Separation between Apps rows and grouped connection facts.
  double get appsSettingsGap => 12;

  /// A connected site's compact origin mark.
  double get appsSettingsSiteMarkSize => 22;

  /// Keeps site identifiers and connection actions readable in short windows.
  double get appsSettingsTableMinWidth => 640;

  /// The quiet discovery field below the last licence.
  double get originalsDiscoveryWidth => 132;

  /// Height of the quiet discovery field.
  double get originalsDiscoveryHeight => 34;

  /// Horizontal inset inside the unlabelled field.
  double get originalsFieldInset => 10;

  /// Vertical inset keeps the original field at its specified height.
  double get originalsFieldVerticalInset => 6;

  /// The field sits below the real licence list with its original inset.
  EdgeInsetsDirectional get originalsDiscoveryPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 22, 16, 26);

  /// Internal padding of the original artwork card.
  EdgeInsetsDirectional get originalsBodyPadding =>
      const EdgeInsetsDirectional.all(16);

  /// Space between the six large originals.
  double get originalsTileGap => 12;

  /// Tiles wrap before their captions become unreadable.
  double get originalsTileMinWidth => 120;

  /// The original gallery artwork viewport.
  double get originalsArtHeight => 112;

  /// Caption separation below each original.
  double get originalsTileCaptionGap => 8;

  /// Separation before the original small marks.
  double get originalsBodyGap => 14;

  /// Group spacing for the three small originals.
  double get originalsMiniGroupGap => 26;

  /// Space between a small original and its use in the wallet.
  double get originalsMiniMarkGap => 8;

  /// The plasma and eye originals' compact viewport.
  double get originalsMiniMarkSize => 22;

  /// The original empty-list mark's viewport.
  double get originalsEmptyMarkSize => 18;

  /// The original eye is cropped to its compact gallery viewport.
  double get originalsEyeSize => 96;

  /// The globe is cropped from the original wide composition.
  double get originalsGlobeWidth => 206;

  /// The map keeps the original wide composition.
  double get originalsMapWidth => 250;

  /// Aspect ratio of the original launch, globe and map art.
  double get originalsWideArtAspect => 16 / 9;

  /// The assembling pillar and sentinel keep their original gallery size.
  double get originalsObjectSize => 108;

  /// The original ZTS gallery size.
  double get originalsZtsSize => 104;

  /// Quiet titles beneath the gallery art.
  TextStyle get originalsTileTitleText =>
      bodyText.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600);

  /// Width of the final onboarding card over the original map.
  double get readyCardWidth => 540;

  /// Width of the import and seed confirmation card.
  double get entryCardWidth => 620;

  /// Inner margins of the import and seed confirmation card.
  EdgeInsetsDirectional get entryCardPadding =>
      const EdgeInsetsDirectional.fromSTEB(28, 24, 28, 26);

  /// Vertical rhythm within an import card.
  double get entryGap => 16;

  /// Vertical rhythm within a seed confirmation card.
  double get entryQuizGap => 18;

  /// Space between the entry back control and title.
  double get entryHeadingGap => 10;

  /// Includes the reference ghost button's transparent one-pixel side borders.
  EdgeInsetsDirectional get entryBackPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 11, vertical: 3);

  /// Retains tabular digits while compensating their measured label advances.
  EdgeInsets get importWordChoicePadding =>
      const EdgeInsets.symmetric(horizontal: 13.25, vertical: 5);

  /// The compact onboarding card's title.
  TextStyle get entryHeadingText =>
      bodyText.copyWith(fontSize: 18, fontWeight: FontWeight.w600);

  /// Diameter of one numbered onboarding step.
  double get entryStepSize => 22;

  /// Separation within a numbered step.
  double get entryStepGap => 8;

  /// Inset of the line between onboarding stages.
  double get entryStepLineInset => 10;

  /// Minimum length of an onboarding stage connector.
  double get entryStepLineMinWidth => 24;

  /// Each step can wrap without losing its vertical inset.
  EdgeInsetsDirectional get entryStepPadding =>
      const EdgeInsetsDirectional.symmetric(vertical: 4);

  /// Labels of the compact onboarding stages.
  TextStyle get entryStepText => bodyText.copyWith(fontSize: 13);

  /// Numeric onboarding position uses the data role.
  TextStyle get entryStepNumberText =>
      dataText.copyWith(fontSize: 11, fontWeight: FontWeight.w500);

  /// Horizontal inset of Import's ordinary primary action.
  EdgeInsetsDirectional get importContinuePadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16);

  /// Inset of the import file drop area.
  double get importDropPadding => 22;

  /// Separation of the import file's icon and hint.
  double get importDropGap => 10;

  /// The original file drop icon's size.
  double get importDropIconSize => 28;

  /// Weight of the original file drop boundary.
  double get importDropLineWidth => 1.5;

  /// Measured alternating lengths of the file drop boundary.
  List<double> get importDropDashPattern => const <double>[3, 2];

  /// Minimum seed entry area height before text scaling.
  double get importSeedMinHeight => 72;

  /// Separation between seed quiz questions.
  double get seedQuizRowGap => 14;

  /// Separation between distinct word choices.
  double get seedQuizChoiceGap => 8;

  /// Minimum seed choice height before text scaling.
  double get seedQuizChoiceHeight => 26;

  /// Seed choice's horizontal and vertical insets.
  EdgeInsetsDirectional get seedQuizChoicePadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 3);

  /// Seed choices retain the mono data role.
  TextStyle get seedQuizChoiceText => dataText.copyWith(fontSize: 12);

  /// One quiet line beneath an entry action.
  TextStyle get entryFooterText =>
      bodyText.copyWith(fontSize: 12.5, color: faint);

  /// Inner margins of the map's glass card.
  EdgeInsetsDirectional get readyCardPadding =>
      const EdgeInsetsDirectional.fromSTEB(32, 26, 32, 24);

  /// Vertical rhythm of the final onboarding view.
  double get readyGap => 16;

  /// Space above the ready heading.
  double get readyTitleGap => 6;

  /// Separation between the first address and its ledger label.
  double get readyAddressGap => 4;

  /// Separation between completed entry stages.
  double get readyStepGap => 12;

  /// The final entry heading's original type scale.
  TextStyle get readyTitleText =>
      bodyText.copyWith(fontSize: 22, fontWeight: FontWeight.w600);

  /// The first initialized address uses the mono data role.
  TextStyle get readyAddressText => dataText.copyWith(fontSize: 13.5);

  /// The project's voting column keeps its original measured width.
  double get acceleratorVoteAsideWidth => 320;

  /// Insets around project metadata and phases.
  EdgeInsetsDirectional get acceleratorDetailBodyPadding =>
      const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 20);

  /// Insets within the independent voting column.
  EdgeInsets get acceleratorVoteAsidePadding => const EdgeInsets.all(20);

  /// Phase rows can grow around scaled text.
  double get acceleratorPhaseMinHeight => 60;

  /// Separation between independent project facts.
  double get acceleratorDetailFactsGap => 28;

  /// Native-coin budgets in a phase row.
  double get acceleratorPhaseBudgetWidth => 140;

  /// Exact vote tallies within a phase row.
  double get acceleratorPhaseVotesWidth => 300;

  /// Status text within a phase row.
  double get acceleratorPhaseStatusWidth => 108;

  /// Project facts, phase columns and voting aside share one scrollable width.
  double get acceleratorDetailMinWidth => 1140;

  /// Width of the original Start and Join dialog.
  double get swapActionWidth => 480;

  /// Start and Join title-row insets.
  EdgeInsetsDirectional get swapActionHeaderPadding =>
      const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 14);

  /// Start and Join form insets.
  EdgeInsetsDirectional get swapActionBodyPadding =>
      const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 20);

  /// The inset around each side of the exchange.
  EdgeInsetsDirectional get swapActionRowPadding =>
      const EdgeInsetsDirectional.all(14);

  /// Separation within the compact exchange form.
  double get swapActionGap => 10;

  /// Exchange amounts use the data role without decorative movement.
  TextStyle get swapActionAmountText => dataText.copyWith(fontSize: 30);

  /// The transfer-shaped dialog's primary action height.
  double get swapActionPrimaryHeight => 58;

  /// The transfer-shaped dialog's primary label.
  TextStyle get swapActionPrimaryText =>
      bodyText.copyWith(fontSize: 17, fontWeight: FontWeight.w600);

  /// The dedicated dollar line below an amount.
  double get swapActionDollarHeight => 20;

  /// The token selector's minimum height.
  double get swapActionTokenHeight => 34;

  /// The token mark remains separate from the amount.
  double get swapActionTokenIconSize => 20;

  /// Compact lettering inside a native coin circle.
  TextStyle get swapActionCoinText =>
      dataText.copyWith(fontSize: 9, fontWeight: FontWeight.w700);

  /// Ink used by the non-ZNN native coin circle.
  Color get swapActionCoinForeground => Colors.white;

  /// The direction mark's viewport between exchange sides.
  double get swapActionArrowSize => 32;

  /// Color and background state transitions.
  Duration get swapActionStateDuration => const Duration(milliseconds: 180);

  /// Existing deposit details open under the form.
  Duration get swapActionDetailsDuration => const Duration(milliseconds: 240);

  /// The details disclosure's direction mark.
  Duration get swapActionChevronDuration => const Duration(milliseconds: 220);

  /// Vertical travel of the details disclosure.
  double get swapActionDetailsRise => 8;

  /// The original welcome globe's full display size.
  double get welcomeGlobeSize => 470;

  /// The original globe composition's wide viewport.
  double get welcomeFilmWidth => 836;

  /// The original globe composition's viewport height.
  double get welcomeFilmHeight => 470;

  /// Width of the three welcome actions.
  double get welcomeColumnWidth => 400;

  /// Separation between the globe and entry choices.
  double get welcomeColumnGap => 36;

  /// Separation between welcome action rows.
  double get welcomeRowGap => 12;

  /// Separation between welcome heading and supporting text.
  double get welcomeTextGap => 12;

  /// Space after the welcome introduction.
  double get welcomeIntroBottomGap => 8;

  /// Space above the later Settings hint.
  double get welcomeFooterTopGap => 6;

  /// Minimum height of a welcome action before text scaling.
  double get welcomeRowHeight => 70;

  /// Directional inset of each welcome action.
  EdgeInsetsDirectional get welcomeRowPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14);

  /// Viewport around a welcome action glyph.
  double get welcomeIconSize => 40;

  /// Separation between the welcome glyph and its label.
  double get welcomeIconGap => 14;

  /// The original welcome row glyph.
  double get welcomeGlyphSize => 18;

  /// The welcome row's trailing direction mark.
  double get welcomeChevronSize => 14;

  /// The welcome surface's outer directional inset.
  EdgeInsetsDirectional get welcomePagePadding =>
      const EdgeInsetsDirectional.all(24);

  /// Focus and outline state changes on welcome rows.
  Duration get welcomeStateDuration => const Duration(milliseconds: 150);

  /// The welcome heading preserves the mockup type scale.
  TextStyle get welcomeHeadingText =>
      bodyText.copyWith(fontSize: 28, fontWeight: FontWeight.w600);

  /// The welcome introduction stays secondary to its actions.
  TextStyle get welcomeSubtitleText =>
      bodyText.copyWith(fontSize: 14, color: dim);

  /// The primary title of an entry choice.
  TextStyle get welcomeActionText =>
      bodyText.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  /// The entry choices' short descriptions.
  TextStyle get welcomeHintText => bodyText.copyWith(fontSize: 13, color: dim);

  /// The quiet hint beneath the entry choices.
  TextStyle get welcomeFooterText =>
      bodyText.copyWith(fontSize: 12.5, color: faint);

  /// Complete swap identifiers remain readable in a horizontal viewport.
  double get swapTableMinWidth => 1000;

  /// Minimum height of a swap row.
  double get swapRowHeight => 44;

  /// The swap table's quiet column header.
  double get swapHeaderHeight => 34;

  /// Directional inset shared by swap table cells.
  EdgeInsetsDirectional get swapCellPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 9);

  /// Expanded swap facts retain the original row's horizontal inset.
  EdgeInsetsDirectional get swapDetailPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20);

  /// Separation between the two captured deposit columns.
  double get swapDetailColumnGap => 20;

  /// Width of swap fact labels.
  double get swapDetailLabelWidth => 128;

  /// Separation between expanded swap facts.
  double get swapDetailRowGap => 6;

  /// Directional inset inside a swap state notice.
  EdgeInsetsDirectional get swapNoticePadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10);

  /// Space between the swap state mark and its explanation.
  double get swapNoticeGap => 10;

  /// The swap status mark.
  double get swapStatusDotSize => 6;

  /// Width reserved for the swap detail control.
  double get swapChevronWidth => 28;

  /// The compact swap filter's minimum width.
  double get swapFilterWidth => 110;

  /// The Accelerator fund strip's minimum height.
  double get acceleratorStripHeight => 70;

  /// Minimum height of Accelerator search and sort controls.
  double get acceleratorToolbarHeight => 60;

  /// Minimum height of a project row before text scaling.
  double get acceleratorRowHeight => 60;

  /// The project table's quiet column header.
  double get acceleratorHeaderHeight => 34;

  /// The complete Accelerator table remains horizontally scrollable.
  double get acceleratorTableMinWidth => 1000;

  /// The two project budget figures share one column.
  double get acceleratorBudgetWidth => 144;

  /// Space for votes and the proportional vote bar.
  double get acceleratorVotesWidth => 353;

  /// Unknown quorum is kept separate from recorded vote totals.
  double get acceleratorQuorumWidth => 135;

  /// The current project status column.
  double get acceleratorStatusWidth => 199;

  /// The project row's trailing detail control.
  double get acceleratorChevronWidth => 39;

  /// Width of the Accelerator search field.
  double get acceleratorSearchWidth => 220;

  /// The recorded votes' proportional bar.
  double get acceleratorVoteBarWidth => 140;

  /// Height of the recorded vote bar.
  double get acceleratorVoteBarHeight => 6;

  /// Directional inset of Accelerator table cells.
  EdgeInsetsDirectional get acceleratorCellPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 10);

  /// The project row's container transform into its detail page.
  Duration get acceleratorTransformDuration =>
      const Duration(milliseconds: 300);

  /// Horizontal inset inside Security row actions.
  double get securitySettingsButtonInset => 10;

  /// Quiet identifiers in expanded Security groups.
  TextStyle get securitySettingsLabelText =>
      dataText.copyWith(fontSize: 12, color: dim);

  /// Explanations under Security choices.
  TextStyle get securitySettingsHintText =>
      bodyText.copyWith(fontSize: 12.5, color: dim);

  /// The node endpoint's quiet identifier role.
  TextStyle get nodeSettingsSubtitleText =>
      dataText.copyWith(fontSize: 12, color: dim);

  /// Current node facts beside the Nodes heading.
  TextStyle get nodeSettingsSummaryText =>
      bodyText.copyWith(fontSize: 12.5, color: dim);

  /// Separation between independent node summary facts.
  double get nodeSettingsSummaryGap => 16;

  /// The node row's selection mark.
  double get nodeSettingsChoiceSize => 16;

  /// The compact node status chip's base height.
  double get nodeSettingsChipHeight => 26;

  /// The node table's compact action height.
  double get nodeSettingsCompactButtonHeight => 26;

  /// Horizontal inset inside a compact node action.
  double get nodeSettingsCompactButtonInset => 10;

  /// The keyboard palette's width and placement at its default client size.
  double get goToWidth => 560;

  /// The keyboard palette's top edge at the reference client size.
  double get goToTopInset => 120;

  /// Minimum space around the palette in a smaller or scaled viewport.
  double get goToEdgeInset => 24;

  /// A palette result's base height before text scaling.
  double get goToRowHeight => 40;

  /// A palette category heading's base height.
  double get goToHeadingHeight => 28;

  /// The list's inset inside the palette surface.
  double get goToListInset => 6;

  /// The result's horizontal content inset.
  double get goToRowInset => 10;

  /// The search header's content inset.
  EdgeInsetsDirectional get goToHeaderPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12);

  /// The category heading's content inset.
  EdgeInsetsDirectional get goToHeadingPadding =>
      const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 4);

  /// The palette's shortcut footer inset.
  EdgeInsetsDirectional get goToFooterPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12);

  /// The distance between palette shortcut hints.
  double get goToFooterGap => 14;

  /// The palette query's text.
  TextStyle get goToQueryText => bodyText.copyWith(fontSize: 16);

  /// Exact identifiers in the result's secondary line.
  TextStyle get goToIdentifierText =>
      dataText.copyWith(fontSize: 13, color: dim);

  /// The space between a control's icon and label.
  double get inlineGap => 8;

  /// The radius of a compact menu item or tooltip.
  double get compactRadius => 6;

  /// The radius of an ordinary dialog.
  double get dialogRadius => 12;

  /// The radius of an event toast.
  double get toastRadius => 10;

  /// The floating toast's width.
  double get toastWidth => 300;

  /// The toast's distance from the top of the page.
  double get toastTop => 44;

  /// The toast's distance from the page's reading end.
  double get toastEdge => 24;

  /// The notification panel's width at the reading edge.
  double get bellPanelWidth => 380;

  /// The content inset of a floating toast.
  EdgeInsetsDirectional get toastPadding =>
      const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 10);

  /// A full rounding for buttons, chips and segmented controls.
  double get pillRadius => 999;

  /// The height of an ordinary text field.
  double get fieldHeight => 42;

  /// The height of an ordinary primary or secondary pill.
  double get buttonHeight => 38;

  /// The opacity of a disabled primary action in the mockup.
  double get disabledOpacity => 0.45;

  /// The height of the mockup's compact button.
  double get compactButtonHeight => 30;

  /// The height of the smallest inline action.
  double get smallButtonHeight => 26;

  /// The primary pill uses a slightly darker ink than the token's mark.
  Color get primaryButtonForeground => const Color(0xFF04140A);

  /// The transfer shape's larger radii, shared by its action dialogs.
  double get transferCardRadius => 24;

  /// The transfer shape's field and row radius.
  double get transferControlRadius => 14;

  /// Inner margins of the shared Transfer form.
  EdgeInsetsDirectional get transferFormPadding =>
      const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 20);

  /// Space between the form's logical groups.
  double get transferFormGap => 12;

  /// Space between fields in one group.
  double get transferFieldGap => 10;

  /// Space between compact recipient chips.
  double get transferRecentGap => 6;

  /// Field content shares a quiet, consistent inset.
  EdgeInsetsDirectional get transferFieldPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10);

  /// Recent-recipient chips keep their compact line height.
  EdgeInsetsDirectional get transferChipPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 3);

  /// Token selection stays secondary to the amount.
  double get transferTokenWidth => 170;

  /// Exact amounts use the data typeface.
  TextStyle get transferAmountText => dataText.copyWith(fontSize: 20);

  /// The form action uses the drawn Transfer size.
  double get transferActionHeight => 46;

  /// The action remains legible without competing with the amount.
  TextStyle get transferActionText =>
      bodyText.copyWith(fontSize: 16, fontWeight: FontWeight.w600);

  /// Insets for an address comparison.
  EdgeInsetsDirectional get transferWarningPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12);

  /// Insets for the observed node-lag notice.
  EdgeInsetsDirectional get transferSyncPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 10);

  /// Supporting availability and price text.
  TextStyle get transferCaptionText =>
      bodyText.copyWith(fontSize: 13, color: dim);

  /// A quiet caution surface derived from the theme's semantic warning.
  Color get transferWarningTint => warn.withValues(alpha: 0.08);

  /// A caution outline with the same meaning in both themes.
  Color get transferWarningLine => warn.withValues(alpha: 0.35);

  /// Receive keeps room for the full address and optional request.
  EdgeInsetsDirectional get receiveFormPadding =>
      const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 20);

  /// Space between Receive sections.
  double get receiveGap => 14;

  /// Space between Receive fields.
  double get receiveFieldGap => 10;

  /// Space between Receive actions.
  double get receiveActionGap => 8;

  /// Space between closely related labels.
  double get receiveMicroGap => 6;

  /// The request's QR image size before its quiet border.
  double get receiveQrSize => 150;

  /// QR pixels keep a clear border.
  double get receiveQrInset => 12;

  /// The optional QR rises a small distance as it opens.
  double get receiveQrSlide => 8;

  /// A full address may use most of the shared card's width.
  double get receiveAddressWidth => 520;

  /// Request token selection is compact.
  double get receiveTokenWidth => 150;

  /// Addresses preserve the data typeface.
  TextStyle get receiveAddressText => dataText.copyWith(fontSize: 17);

  /// The expanded QR keeps its address readable beneath the image.
  TextStyle get receiveQrAddressText => dataText.copyWith(fontSize: 14);

  /// Optional request amounts remain secondary to the full address.
  TextStyle get receiveAmountText => dataText.copyWith(fontSize: 18);

  /// Request controls use quiet supporting text.
  TextStyle get receiveRequestText =>
      bodyText.copyWith(fontSize: 13.5, color: dim);

  /// Zap's two coin amounts share an exact data role.
  TextStyle get zapAmountText => dataText.copyWith(fontSize: 18);

  /// Byte counts and block explanations stay secondary.
  TextStyle get zapCaptionText =>
      bodyText.copyWith(fontSize: 12.5, color: faint);

  /// The message field can grow with text and text scaling.
  double get zapMessageMinHeight => 72;

  /// A small coin mark beside each amount.
  double get zapCoinSize => 22;

  /// Fallback coin lettering is compact and monospaced.
  TextStyle get zapCoinText => dataText.copyWith(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// Zap's leading control glyph.
  double get zapGlyphSize => 18;

  /// Zap's inline supporting glyph.
  double get zapSmallGlyphSize => 14;

  /// The message has the same horizontal field inset.
  EdgeInsetsDirectional get zapMessagePadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10);

  /// Search is constrained beside the Nodes tabs.
  double get pillarSearchWidth => 200;

  /// A card title or tab row starts at the same compact height.
  double get panelHeaderHeight => 48;

  /// Ordinary card titles retain their wider leading inset.
  EdgeInsetsDirectional get panelHeaderPadding =>
      const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0);

  /// Heading tabs share the mockup's inset with the trailing actions.
  EdgeInsetsDirectional get tabHeaderPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 8);

  /// Space between the measured heading tabs.
  double get tabGap => 2;

  /// Heading label insets, before the underline's own thickness.
  EdgeInsetsDirectional get tabPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 12);

  /// A reported count stays separate from its heading label.
  double get tabCountGap => 6;

  /// Nested count spans inherit the mockup's horizontal tab inset.
  EdgeInsetsDirectional get tabCountPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 10);

  /// The selected heading meets the card's divider with one brand line.
  double get tabUnderlineThickness => 2;

  /// Compact search beside the Nodes tabs.
  double get pillarSearchHeight => 30;

  /// Node list values share the mockup's row inset.
  EdgeInsetsDirectional get pillarCellPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 9);

  /// Column headings remain quieter than row values.
  EdgeInsetsDirectional get pillarHeadingPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8);

  /// Details align beyond the disclosure arrow.
  double get pillarDetailIndent => 26;

  /// The detail grid separates independent facts.
  double get pillarColumnGap => 20;

  /// Delegation actions fit within the compact table.
  double get pillarActionHeight => 26;

  /// A known owned row has a compact factual label.
  double get pillarOwnedChipHeight => 22;

  /// The original owner object plays once within the opened panel.
  double get pillarOwnerObjectSize => 132;

  /// Owner actions keep their column separate from values.
  double get pillarOwnerActionsWidth => 170;

  /// The inline owner panel follows the Nodes card inset.
  EdgeInsetsDirectional get pillarOwnerPanelPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 16);

  /// Object, facts and owner actions have independent space.
  double get pillarOwnerGap => 28;

  /// Owner facts share the detail grid's column spacing.
  double get pillarOwnerFactColumnGap => 20;

  /// An owner name is a heading rather than an amount.
  TextStyle get pillarOwnerNameText => bodyText.copyWith(fontSize: 17);

  /// The inset around the content of an ordinary card.
  EdgeInsets get cardPadding =>
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  /// The page strip's inset, distinct from an ordinary card.
  EdgeInsetsDirectional get stripPadding =>
      const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 12);

  /// The overlay and glass surfaces have different blur strengths.
  double get overlayBlur => 6;

  /// The blur within a glass dialog.
  double get dialogBlur => 10;

  /// The blur within a panel or toast.
  double get panelBlur => 12;

  /// The blur within a floating menu.
  double get menuBlur => 10;

  /// The top edge is painted separately from the outward drop shadow;
  /// Flutter's BoxShadow cannot express the mockup's inset shadow.
  BorderSide get glassTopEdge =>
      const BorderSide(color: Color.fromRGBO(255, 255, 255, 0.06));

  /// The tint behind a dialog, over the blurred page.
  Color get overlayScrim => const Color.fromRGBO(0, 0, 0, 0.35);

  /// The outward drop below a dialog; the top edge is separate.
  BoxShadow get dialogShadow => const BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.45),
    offset: Offset(0, 20),
    blurRadius: 60,
  );

  /// The inward-facing drop of the panel at the right window edge.
  BoxShadow get panelShadow => const BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.35),
    offset: Offset(-20, 0),
    blurRadius: 50,
  );

  /// The drop beneath a floating event toast.
  BoxShadow get toastShadow => const BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.4),
    offset: Offset(0, 12),
    blurRadius: 36,
  );

  /// The drop beneath a floating menu.
  BoxShadow get menuShadow => const BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.4),
    offset: Offset(0, 10),
    blurRadius: 30,
  );

  /// The smaller drop beneath a rail tooltip.
  BoxShadow get tooltipShadow => const BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.35),
    offset: Offset(0, 6),
    blurRadius: 18,
  );

  /// The wallet window's body is 14 px; the surrounding review page is 15.
  /// Tabular figures apply to numbers even when they occur in interface text.
  TextStyle get bodyText => TextStyle(
    fontFamily: sansFontFamily,
    fontFamilyFallback: kFontFamilyFallback,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    fontSize: 14,
    fontWeight: FontWeight.w400,
    // CSS uses normal tracking. An omitted value inherits Material tracking.
    letterSpacing: 0,
    height: 1.45,
    // CSS line boxes distribute the extra leading equally above and below.
    leadingDistribution: TextLeadingDistribution.even,
    color: foreground,
  );

  /// The semibold label at the head of a card.
  TextStyle get headingText => bodyText.copyWith(fontWeight: FontWeight.w600);

  /// The primary and secondary pill label.
  TextStyle get buttonText => headingText;

  /// Secondary interface prose and compact action labels.
  TextStyle get compactText => bodyText.copyWith(fontSize: 13);

  /// Quiet captions, counts and small supporting labels.
  TextStyle get captionText => bodyText.copyWith(fontSize: 12, color: faint);

  /// The base for amounts and identifiers, with the interface's fallbacks.
  TextStyle get dataText => bodyText.copyWith(fontFamily: monoFontFamily);

  /// CSS tracking is in em; Flutter's value is in logical pixels.
  TextStyle get ledgerText => dataText.copyWith(
    fontSize: 11,
    letterSpacing: 0.66,
    color: faint,
  );

  /// The headline amount in the Home hero.
  TextStyle get heroAmountText => dataText.copyWith(
    fontSize: 34,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.34,
    height: 1.1,
  );

  /// A headline figure in a page's status strip.
  TextStyle get stripAmountText => dataText.copyWith(fontSize: 19);

  /// The quiet dollar estimate following a coin amount.
  TextStyle get dollarText => dataText.copyWith(fontSize: 13, color: faint);

  @override
  AppTokens copyWith({
    Color? faint,
    Color? znnInk,
    Color? qsrInk,
    Color? warn,
    Color? hover,
    Color? focusRing,
    double? panelGap,
    double? cardGap,
    double? cardRadius,
    Color? background,
    Color? card,
    Color? card2,
    Color? card3,
    Color? line,
    Color? foreground,
    Color? dim,
    Color? znn,
    Color? qsr,
    Color? pink,
    Color? pinkInk,
    Color? error,
    Color? page,
    Color? onZnn,
    Color? glass,
    String? sansFontFamily,
    String? monoFontFamily,
    Curve? ease,
    Curve? spring,
    LinearGradient? plasma,
  }) {
    return AppTokens(
      faint: faint ?? this.faint,
      znnInk: znnInk ?? this.znnInk,
      qsrInk: qsrInk ?? this.qsrInk,
      warn: warn ?? this.warn,
      hover: hover ?? this.hover,
      focusRing: focusRing ?? this.focusRing,
      panelGap: panelGap ?? this.panelGap,
      cardGap: cardGap ?? this.cardGap,
      cardRadius: cardRadius ?? this.cardRadius,
      background: background ?? this.background,
      card: card ?? this.card,
      card2: card2 ?? this.card2,
      card3: card3 ?? this.card3,
      line: line ?? this.line,
      foreground: foreground ?? this.foreground,
      dim: dim ?? this.dim,
      znn: znn ?? this.znn,
      qsr: qsr ?? this.qsr,
      pink: pink ?? this.pink,
      pinkInk: pinkInk ?? this.pinkInk,
      error: error ?? this.error,
      page: page ?? this.page,
      onZnn: onZnn ?? this.onZnn,
      glass: glass ?? this.glass,
      sansFontFamily: sansFontFamily ?? this.sansFontFamily,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
      ease: ease ?? this.ease,
      spring: spring ?? this.spring,
      plasma: plasma ?? this.plasma,
    );
  }

  @override
  AppTokens lerp(covariant ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) {
      return this;
    }
    return AppTokens(
      faint: Color.lerp(faint, other.faint, t)!,
      znnInk: Color.lerp(znnInk, other.znnInk, t)!,
      qsrInk: Color.lerp(qsrInk, other.qsrInk, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      panelGap: lerpDouble(panelGap, other.panelGap, t)!,
      cardGap: lerpDouble(cardGap, other.cardGap, t)!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      card2: Color.lerp(card2, other.card2, t)!,
      card3: Color.lerp(card3, other.card3, t)!,
      line: Color.lerp(line, other.line, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      znn: Color.lerp(znn, other.znn, t)!,
      qsr: Color.lerp(qsr, other.qsr, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      pinkInk: Color.lerp(pinkInk, other.pinkInk, t)!,
      error: Color.lerp(error, other.error, t)!,
      page: Color.lerp(page, other.page, t)!,
      onZnn: Color.lerp(onZnn, other.onZnn, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      sansFontFamily: t < 0.5 ? sansFontFamily : other.sansFontFamily,
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
      ease: t < 0.5 ? ease : other.ease,
      spring: t < 0.5 ? spring : other.spring,
      plasma: LinearGradient.lerp(plasma, other.plasma, t)!,
    );
  }

  // By value: ThemeData compares its extensions, and a lerp builds a new
  // object. By identity, a theme that settled on the same tokens would
  // still count as changed and rebuild everything under it.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppTokens &&
        other.faint == faint &&
        other.znnInk == znnInk &&
        other.qsrInk == qsrInk &&
        other.warn == warn &&
        other.hover == hover &&
        other.focusRing == focusRing &&
        other.panelGap == panelGap &&
        other.cardGap == cardGap &&
        other.cardRadius == cardRadius &&
        other.background == background &&
        other.card == card &&
        other.card2 == card2 &&
        other.card3 == card3 &&
        other.line == line &&
        other.foreground == foreground &&
        other.dim == dim &&
        other.znn == znn &&
        other.qsr == qsr &&
        other.pink == pink &&
        other.pinkInk == pinkInk &&
        other.error == error &&
        other.page == page &&
        other.onZnn == onZnn &&
        other.glass == glass &&
        other.sansFontFamily == sansFontFamily &&
        other.monoFontFamily == monoFontFamily &&
        other.ease == ease &&
        other.spring == spring &&
        other.plasma == plasma;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    faint,
    znnInk,
    qsrInk,
    warn,
    hover,
    focusRing,
    panelGap,
    cardGap,
    cardRadius,
    background,
    card,
    card2,
    card3,
    line,
    foreground,
    dim,
    znn,
    qsr,
    pink,
    pinkInk,
    error,
    page,
    onZnn,
    glass,
    sansFontFamily,
    monoFontFamily,
    ease,
    spring,
    plasma,
  ]);
}

/// CSS 100 degrees is ten degrees clockwise from a left-to-right fill.
/// Rotation keeps that angle in canvas space when a button is very wide.
const LinearGradient kPlasmaGradient = LinearGradient(
  transform: GradientRotation(0.17453292519943295),
  colors: <Color>[
    AppColors.znnColor,
    AppColors.plasmaMiddle,
    AppColors.qsrColor,
  ],
  stops: <double>[0, 0.55, 1],
);

/// A one-pixel line with no additional vertical or horizontal inset.
const DividerThemeData kDefaultDividerThemeData = DividerThemeData(
  thickness: 1,
  indent: 0,
  endIndent: 0,
  space: 1,
);

/// The interface face. Numbers and identifiers use [kMonoFontFamily].
const String kSansFontFamily = 'SpaceGrotesk';

/// The original full faces behind the mockup-derived semibold subset.
const String kSansCoverageFontFamily = 'SpaceGroteskCoverage';

/// Amounts, addresses, hashes and heights: mono with tabular figures, so
/// columns line up and a changing value does not jitter.
const String kMonoFontFamily = 'JetBrainsMono';

/// The bundled face for Arabic: Noto Sans Arabic.
const String kArabicFontFamily = 'NotoSansArabic';

/// The bundled face for Hindi: Noto Sans Devanagari.
const String kDevanagariFontFamily = 'NotoSansDevanagari';

/// Where a character goes that [kSansFontFamily] and [kMonoFontFamily] do
/// not have, in this order. Neither has one Han, Devanagari or Arabic glyph.
///
/// Without the list Flutter asks the operating system for each character.
/// A minimal Linux then draws empty boxes, and a Han character can come
/// back in a Japanese or Traditional face, whichever the system lists first.
///
/// Arabic and Devanagari are bundled, so they come first and look the same
/// everywhere. The two files have no Latin letters, so they take nothing
/// from the faces above.
/// The full Space Grotesk alias follows them: symbols outside the derived
/// semibold subset keep their bundled glyphs before asking the system.
///
/// No Chinese face is bundled: one is 8 to 17 MB, several times the rest of
/// the installer's assets. Han comes from the system instead, and naming
/// the Simplified faces is what keeps it Simplified: Windows, then macOS,
/// then the ones a Linux desktop carries.
///
/// The last four are the system's own Arabic and Devanagari faces, behind
/// the bundled ones should an asset fail to load.
///
/// A style that sets a family of its own takes this list only if it is
/// built on a theme style or with [monoStyle]. One built from nothing, and
/// used where nothing is merged into it (a button's `textStyle`, a nested
/// `TextSpan`), names the list itself. The engine reads a family and its
/// fallbacks as one list, so a family set without them drops them; and a
/// list given to a style with no family replaces the system face, Latin
/// included, with the first face here that has the letter.
const List<String> kFontFamilyFallback = <String>[
  kArabicFontFamily,
  kDevanagariFontFamily,
  kSansCoverageFontFamily,
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
  'Segoe UI',
  'Nirmala UI',
  'Geeza Pro',
  'Kohinoor Devanagari',
];

/// The interface languages not written in Latin letters: Arabic, Hindi and
/// Chinese.
const Set<String> kNonLatinLanguages = <String>{'ar', 'hi', 'zh'};

/// Whether the interface language is written in Latin letters.
///
/// The small labels are spaced capitals. Letter spacing pulls the joined
/// letters of Arabic apart and does nothing for Devanagari or Han, and none
/// of the three has capitals, so a label asks this before it does either.
/// Without a locale above [context] the answer is yes.
bool usesLatinScript(BuildContext context) => !kNonLatinLanguages.contains(
  Localizations.maybeLocaleOf(context)?.languageCode,
);

/// The radius of a card. Buttons and chips are pills.
const double kCardRadius = 8;

/// A mono style for data, built on [base].
TextStyle monoStyle(TextStyle? base) => (base ?? const TextStyle()).copyWith(
  fontFamily: kMonoFontFamily,
  fontFamilyFallback: kFontFamilyFallback,
  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
);

/// The legacy filled pill, retained for existing ElevatedButton callers.
final ButtonStyle kElevatedButtonStyle = ElevatedButton.styleFrom(
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: const StadiumBorder(),
  minimumSize: const Size(55, 42),
  backgroundColor: AppColors.znnColor,
);

/// The text on a filled green button.
const Color kOnZnnColor = Color(0xFF06230D);

/// The main action of a card (Send, Stake, Collect, Delegate, Fuse). The app
/// builds these as OutlinedButtons; in the refreshed interface the main
/// action is a filled green pill, and one that cannot be pressed yet is an
/// empty outline, so "not ready" reads at a glance.
ButtonStyle primaryButtonStyle({required Color disabledLine}) =>
    OutlinedButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      textStyle: kOutlinedButtonTextStyle,
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => states.contains(WidgetState.disabled)
            ? Colors.transparent
            : states.contains(WidgetState.hovered)
            ? const Color(0xFF63DB78)
            : AppColors.znnColor,
      ),
      side: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => states.contains(WidgetState.disabled)
            ? BorderSide(color: disabledLine)
            : BorderSide.none,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.disabled) ? disabledLine : kOnZnnColor,
      ),
    );

/// The legacy outlined pill used by callers outside the primary action.
final ButtonStyle kOutlinedButtonStyle = OutlinedButton.styleFrom(
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: const StadiumBorder(),
  side: const BorderSide(
    color: AppColors.znnColor,
  ),
  textStyle: kOutlinedButtonTextStyle,
);

/// The compact display style retained by existing screen widgets.
const TextStyle kDisplaySmallTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
);

/// An ordinary card's legacy 14 px body style.
const TextStyle kBodyLargeTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
);

/// The legacy 13 px body style used by explicit compact labels.
const TextStyle kBodyMediumTextStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w400,
);

/// The legacy 12 px supporting text style.
const TextStyle kBodySmallTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
);

/// The large interface heading retained by existing entry screens.
const TextStyle kHeadlineLargeTextStyle = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w500,
);

/// The medium interface heading retained by existing dialogs.
const TextStyle kHeadlineMediumTextStyle = TextStyle(
  fontSize: 24,
  fontWeight: FontWeight.w500,
);

/// The small interface heading retained by existing cards.
const TextStyle kHeadlineSmallTextStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w400,
);

/// The label of a main action, and of any button at its size.
///
/// A button's `textStyle` replaces the theme's label style, so this names
/// the face and [kFontFamilyFallback] itself; without them the label was
/// drawn in the operating system's face. The bundled semibold supplies the
/// mockup's 600 weight directly.
const TextStyle kOutlinedButtonTextStyle = TextStyle(
  fontFamily: kSansFontFamily,
  fontFamilyFallback: kFontFamilyFallback,
  fontSize: 14,
  fontWeight: FontWeight.w600,
);

/// The label of a TextButton and of the compact buttons; a complete style,
/// as [kOutlinedButtonTextStyle] is.
const TextStyle kTextButtonTextStyle = TextStyle(
  fontFamily: kSansFontFamily,
  fontFamilyFallback: kFontFamilyFallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

/// A legacy secondary title; the light theme supplies its own ink.
const TextStyle kTitleMediumTextStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w400,
  color: AppColors.subtitleColor,
);

/// A legacy small secondary title; the light theme supplies its own ink.
const TextStyle kTitleSmallTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
  color: AppColors.subtitleColor,
);

/// The legacy filled TextButton theme, retained during component migration.
final TextButtonThemeData kTextButtonThemeData = TextButtonThemeData(
  style: TextButton.styleFrom(
    textStyle: kTextButtonTextStyle,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(55, 25),
    backgroundColor: AppColors.znnColor,
    shape: const StadiumBorder(),
  ),
);

/// A field hint's base style; each theme supplies its faint ink.
const TextStyle kHintTextStyle = TextStyle(
  fontWeight: FontWeight.w400,
  fontSize: 14,
);

/// A field error's base style; the light theme replaces the dark crimson.
const TextStyle kTextFormFieldErrorStyle = TextStyle(
  color: AppColors.errorColor,
);

/// The shared field shape; each theme supplies state-specific border ink.
const OutlineInputBorder kOutlineInputBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(kCardRadius)),
);

/// The two Material themes built from the desktop mockup's semantic tokens.
class AppTheme {
  AppTheme._();

  // Theme styles describe interface roles. Amounts and identifiers opt in
  // to the mono styles at their component boundary, as monoStyle does.
  static TextTheme _textTheme(AppTokens tokens) => TextTheme(
    displayLarge: tokens.heroAmountText.copyWith(
      fontFamily: tokens.sansFontFamily,
    ),
    displayMedium: tokens.heroAmountText.copyWith(
      fontFamily: tokens.sansFontFamily,
    ),
    displaySmall: tokens.stripAmountText.copyWith(
      fontFamily: tokens.sansFontFamily,
    ),
    headlineLarge: tokens.bodyText.merge(kHeadlineLargeTextStyle),
    headlineMedium: tokens.bodyText.merge(kHeadlineMediumTextStyle),
    headlineSmall: tokens.bodyText.merge(kHeadlineSmallTextStyle),
    titleLarge: tokens.headingText,
    titleMedium: tokens.compactText.copyWith(color: tokens.dim),
    titleSmall: tokens.captionText.copyWith(color: tokens.dim),
    bodyLarge: tokens.bodyText,
    bodyMedium: tokens.bodyText,
    bodySmall: tokens.bodyText.copyWith(fontSize: 12),
    labelLarge: tokens.buttonText,
    labelMedium: tokens.compactText,
    labelSmall: tokens.ledgerText.copyWith(fontFamily: tokens.sansFontFamily),
  );

  /// Existing callers use primary and primaryContainer as raised surfaces.
  /// Brand fills have their own tokens, so a token migration does not turn
  /// every existing card green.
  static ColorScheme _colorScheme(AppTokens tokens, Brightness brightness) =>
      (brightness == Brightness.dark
              ? const ColorScheme.dark()
              : const ColorScheme.light())
          .copyWith(
            primary: tokens.card,
            onPrimary: tokens.foreground,
            primaryContainer: tokens.card2,
            onPrimaryContainer: tokens.foreground,
            secondary: tokens.card3,
            onSecondary: tokens.foreground,
            secondaryContainer: tokens.card2,
            onSecondaryContainer: tokens.foreground,
            error: tokens.error,
            onError: Colors.white,
            surface: tokens.background,
            onSurface: tokens.foreground,
            surfaceContainerLowest: tokens.background,
            surfaceContainerLow: tokens.card,
            surfaceContainer: tokens.card2,
            surfaceContainerHigh: tokens.card3,
            surfaceContainerHighest: tokens.card3,
            onSurfaceVariant: tokens.dim,
            outline: tokens.line,
            outlineVariant: tokens.line,
            surfaceTint: Colors.transparent,
          );

  /// The light wallet theme, with white fields and dark foreground ink.
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    extensions: const <ThemeExtension<dynamic>>[AppTokens.light],
    hoverColor: AppTokens.light.hover,
    textButtonTheme: kTextButtonThemeData,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: primaryButtonStyle(disabledLine: const Color(0xFFB9BCB9)).copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.black38;
            }
            return kOnZnnColor;
          },
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: kElevatedButtonStyle,
    ),
    scaffoldBackgroundColor: AppTokens.light.background,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.znnColor,
      selectionHandleColor: AppColors.znnColor,
    ),
    fontFamily: kSansFontFamily,
    fontFamilyFallback: kFontFamilyFallback,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTokens.light.card2,
      hintStyle: kHintTextStyle.copyWith(
        color: AppTokens.light.faint,
      ),
      errorStyle: kTextFormFieldErrorStyle.copyWith(
        color: AppTokens.light.error,
      ),
      enabledBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(color: AppTokens.light.line),
      ),
      disabledBorder: kOutlineInputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.inactiveIconsGray),
      ),
      focusedBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(color: AppTokens.light.faint),
      ),
      errorBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(
          color: AppTokens.light.error,
          width: 2,
        ),
      ),
      focusedErrorBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(
          color: AppTokens.light.error,
          width: 2,
        ),
      ),
    ),
    dividerTheme: kDefaultDividerThemeData.copyWith(
      color: AppTokens.light.line,
    ),
    iconTheme: IconThemeData(
      color: AppTokens.light.dim,
    ),
    textTheme: _textTheme(AppTokens.light),
    unselectedWidgetColor: AppColors.lightSecondaryContainer,
    // On is the green fill with the dark ink of a filled button as its
    // thumb; off is a quiet track with an outline and a faint thumb. Thumb
    // and track once resolved to the same green when on, which drew a solid
    // pill that could not be read as either state.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        final bool on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on
              ? kOnZnnColor.withValues(alpha: 0.5)
              : AppTokens.light.faint.withValues(alpha: 0.4);
        }
        if (on) {
          return kOnZnnColor;
        }
        return states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? AppColors.lightSubtitleColor
            : AppTokens.light.faint;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        final bool on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on
              ? AppColors.znnColor.withValues(alpha: 0.4)
              : AppColors.lightTextFormFieldFill.withValues(alpha: 0.4);
        }
        if (on) {
          return states.contains(WidgetState.hovered)
              ? const Color(0xFF63DB78)
              : AppColors.znnColor;
        }
        return AppColors.lightTextFormFieldFill;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        final bool on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on
              ? Colors.transparent
              : AppTokens.light.faint.withValues(alpha: 0.4);
        }
        if (states.contains(WidgetState.focused)) {
          return AppTokens.light.focusRing;
        }
        return on ? Colors.transparent : AppTokens.light.faint;
      }),
      trackOutlineWidth: WidgetStateProperty.resolveWith<double?>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.focused) ? 2 : 1,
      ),
      // Named for every state: the default is the scheme's primary, which
      // this app reserves for a card surface.
      overlayColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.focused)) {
          return AppTokens.light.focusRing.withValues(alpha: 0.24);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return AppTokens.light.hover;
        }
        return Colors.transparent;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return AppColors.znnColor;
        }
        return null;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return AppColors.znnColor;
        }
        return null;
      }),
    ),
    colorScheme: _colorScheme(AppTokens.light, Brightness.light),
  );

  /// The dark wallet theme, with raised charcoal surfaces and light ink.
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    extensions: const <ThemeExtension<dynamic>>[AppTokens.dark],
    hoverColor: AppTokens.dark.hover,
    textButtonTheme: kTextButtonThemeData,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: primaryButtonStyle(disabledLine: const Color(0xFF4A4D4A)).copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white38;
            }
            return kOnZnnColor;
          },
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: kElevatedButtonStyle,
    ),
    scaffoldBackgroundColor: AppTokens.dark.background,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: Colors.white.withValues(alpha: 0.1),
      cursorColor: AppColors.znnColor,
      selectionHandleColor: AppColors.znnColor,
    ),
    fontFamily: kSansFontFamily,
    fontFamilyFallback: kFontFamilyFallback,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTokens.dark.card2,
      hintStyle: kHintTextStyle.copyWith(
        color: AppTokens.dark.faint,
      ),
      errorStyle: kTextFormFieldErrorStyle.copyWith(
        color: AppTokens.dark.error,
      ),
      enabledBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(color: AppTokens.dark.line),
      ),
      disabledBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      focusedBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(color: AppTokens.dark.faint),
      ),
      errorBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(
          color: AppTokens.dark.error,
          width: 2,
        ),
      ),
      focusedErrorBorder: kOutlineInputBorder.copyWith(
        borderSide: BorderSide(
          color: AppTokens.dark.error,
          width: 2,
        ),
      ),
    ),
    dividerTheme: kDefaultDividerThemeData.copyWith(
      color: AppTokens.dark.line,
    ),
    iconTheme: IconThemeData(
      color: AppTokens.dark.dim,
    ),
    textTheme: _textTheme(AppTokens.dark),
    unselectedWidgetColor: AppColors.darkSecondaryContainer,
    // The same switch as the light theme's, on this theme's tokens. The
    // disabled thumb keeps its full ink when on: dimmed as well, it would
    // sink into the dimmed green on a dark panel.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        final bool on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on ? kOnZnnColor : AppTokens.dark.faint.withValues(alpha: 0.4);
        }
        if (on) {
          return kOnZnnColor;
        }
        return states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? AppColors.subtitleColor
            : AppTokens.dark.faint;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        final bool on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on
              ? AppColors.znnColor.withValues(alpha: 0.4)
              : AppColors.darkTextFormFieldFill.withValues(alpha: 0.4);
        }
        if (on) {
          return states.contains(WidgetState.hovered)
              ? const Color(0xFF63DB78)
              : AppColors.znnColor;
        }
        return AppColors.darkTextFormFieldFill;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        final bool on = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return on
              ? Colors.transparent
              : AppTokens.dark.faint.withValues(alpha: 0.4);
        }
        if (states.contains(WidgetState.focused)) {
          return AppTokens.dark.focusRing;
        }
        return on ? Colors.transparent : AppTokens.dark.faint;
      }),
      trackOutlineWidth: WidgetStateProperty.resolveWith<double?>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.focused) ? 2 : 1,
      ),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.focused)) {
          return AppTokens.dark.focusRing.withValues(alpha: 0.24);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return AppTokens.dark.hover;
        }
        return Colors.transparent;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return AppColors.znnColor;
        }
        return null;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return AppColors.znnColor;
        }
        return null;
      }),
    ),
    colorScheme: _colorScheme(AppTokens.dark, Brightness.dark),
  );
}
