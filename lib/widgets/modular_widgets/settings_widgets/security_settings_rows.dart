import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart'
    show buildShellSymbol;

/// The measured Security row, with a control below long or scaled labels.
class SecuritySettingRow extends StatelessWidget {
  /// Keeps a natural height at narrow widths and larger text sizes.
  const SecuritySettingRow({
    required this.label,
    required this.control,
    this.hint,
    super.key,
  });

  /// The setting's localized name.
  final String label;

  /// One short localized explanation, if needed.
  final String? hint;

  /// The choice or action, aligned to the reading end.
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Widget description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: tokens.bodyText),
        if (hint != null) Text(hint!, style: tokens.securitySettingsHintText),
      ],
    );
    return Padding(
      padding: tokens.settingsRowPadding,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 760 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                description,
                SizedBox(height: tokens.cardGap),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: control,
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: description),
              SizedBox(width: tokens.cardGap),
              Flexible(flex: 2, child: control),
            ],
          );
        },
      ),
    );
  }
}

/// The mockup's compact, neutral Security action.
class SecuritySettingsButton extends StatelessWidget {
  /// Creates one text action, optionally with its named icon.
  const SecuritySettingsButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.symbol,
    this.destructive = false,
    this.data = false,
    super.key,
  }) : assert(icon == null || symbol == null, 'Use one icon source');

  /// The localized action.
  final String label;

  /// Null means unavailable without starting a fallback action.
  final VoidCallback? onPressed;

  /// A labeled icon needs no separate tooltip.
  final IconData? icon;

  /// The exact symbol from the mockup's canonical sprite.
  final String? symbol;

  /// Uses the existing error role for wallet removal.
  final bool destructive;

  /// Selected file names use the mono, tabular data role.
  final bool data;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: destructive ? tokens.error : tokens.foreground,
        backgroundColor: tokens.card2,
        disabledForegroundColor: tokens.faint,
        side: BorderSide(color: tokens.line),
        minimumSize: Size(0, tokens.securitySettingsButtonHeight),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.securitySettingsButtonInset,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: data ? tokens.dataText : tokens.bodyText,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (symbol != null || icon != null) ...<Widget>[
            if (symbol != null)
              buildShellSymbol(
                context,
                symbol!,
                size: tokens.zapSmallGlyphSize,
                color: onPressed == null ? tokens.faint : tokens.foreground,
              )
            else
              Icon(icon, size: tokens.zapSmallGlyphSize),
            SizedBox(width: tokens.fieldLabelGap),
          ],
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}
