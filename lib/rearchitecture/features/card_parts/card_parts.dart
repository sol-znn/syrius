import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/color_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// What the cards of the Transfer, Pillars, Sentinels, Staking, Plasma and
/// Tokens pages share inside a `Panel`: the body padding, the quiet states,
/// the field and button looks.
///
/// These cards used to sit in `NewCardScaffold`, which wrapped each one in a
/// second theme (Material's default face, outlined buttons, filled fields).
/// In a `Panel` they inherit the app theme, where every OutlinedButton is the
/// filled primary action and fields are not filled; the parts below put back
/// what a card needs and nothing else.

/// Padding around a panel's body.
const EdgeInsets kCardBodyPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);

/// The gap between two fields, or two rows, of a card.
///
/// The same value as `AppTokens.cardGap`, kept for the places that need a
/// constant. With a context at hand, read the token.
const double kCardGap = 10;

/// The height of a field, and of a button that sits beside one.
const double kCardFieldHeight = 48;

/// The line colour of the theme in use.
Color cardLineColor(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return theme.dividerTheme.color ?? theme.dividerColor;
}

/// Secondary text: the label beside a value, a note.
TextStyle cardDimStyle(BuildContext context) =>
    (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontSize: 14,
    );

/// Primary text of a card body.
TextStyle cardValueStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 14,
    );

/// An amount as text: thousands grouped, no trailing zeros, nothing rounded,
/// then the symbol. `120450000000`, 8 decimals, ZNN is `1,204.5 ZNN`.
///
/// The string carries no direction mark, so that it can be copied. A
/// [Figure] draws it left to right by itself; any other `Text` of it takes
/// `textDirection: TextDirection.ltr`, or a right-to-left interface draws
/// `ZNN 1,204.5`.
String cardAmount(BigInt raw, int decimals, String symbol) {
  final (String head, _) = splitAmount(raw, decimals);
  return symbol.isEmpty ? head : '$head $symbol';
}

/// The value of a [Figure]: mono, 20 px, in [color] when given.
TextStyle cardFigureStyle(BuildContext context, {Color? color}) =>
    monoStyle(Theme.of(context).textTheme.headlineSmall).copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: color,
    );

/// A [Figure] of an amount in a token's ink; faint when it is zero.
Figure cardAmountFigure(
  BuildContext context, {
  required String label,
  required BigInt amount,
  required int decimals,
  required String symbol,
  required Color ink,
}) => Figure(
  label: label,
  value: cardAmount(amount, decimals, symbol),
  valueStyle: cardFigureStyle(
    context,
    color: amount == BigInt.zero ? AppTokens.of(context).faint : ink,
  ),
);

/// The head of a rewards card: what the address can collect, and the one
/// button that collects it.
class CardCollect extends StatelessWidget {
  /// Creates the strip.
  const CardCollect({required this.figures, required this.button, super.key});

  /// One [Figure] per coin.
  final List<Widget> figures;

  /// The Collect button.
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                for (int i = 0; i < figures.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 28),
                  Flexible(child: figures[i]),
                ],
              ],
            ),
          ),
          SizedBox(width: AppTokens.of(context).cardGap),
          button,
        ],
      ),
    );
  }
}

/// The least a colour may differ in luminance from the card to be used as
/// text on it: about 3 to 1, against the dark card and against the light.
const double _kDarkestInkOnDark = 0.16;
const double _kLightestInkOnLight = 0.30;

/// [own] as text or as a line on a card: itself when it can be read there,
/// the ordinary text colour when it cannot.
///
/// A colour that was not chosen for this theme can be anything. Near black
/// cannot be read on a dark card, near white on a light one.
Color cardReadableInk(BuildContext context, Color own) {
  final ThemeData theme = Theme.of(context);
  final double luminance = own.computeLuminance();
  final bool readable = theme.brightness == Brightness.dark
      ? luminance >= _kDarkestInkOnDark
      : luminance <= _kLightestInkOnLight;
  return readable
      ? own
      : theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
}

/// A token's colour as text or as a line: the one rule for every symbol.
///
/// ZNN and QSR take the theme's inks. A ZTS token's colour is the last three
/// bytes of its token standard, so it goes through [cardReadableInk]: the
/// empty standard of a block with no token gives black, and another token
/// may give near white.
///
/// Pass [context]. Without one the theme is not known, and the answer is
/// the one this function gave before it had the rule: QSR's dark-theme ink,
/// and any other token's own colour, readable or not.
Color cardTokenInk(TokenStandard tokenStandard, [BuildContext? context]) {
  if (context == null) {
    return tokenStandard == kQsrCoin.tokenStandard
        ? AppColors.qsrInk
        : ColorUtils.getTokenColor(tokenStandard);
  }
  if (tokenStandard == kZnnCoin.tokenStandard) {
    return AppTokens.of(context).znnInk;
  }
  if (tokenStandard == kQsrCoin.tokenStandard) {
    return AppTokens.of(context).qsrInk;
  }
  return cardReadableInk(context, ColorUtils.getTokenColor(tokenStandard));
}

/// What an error says to the person. A closed client is the one failure
/// common enough to deserve plain words.
String cardErrorText(Object error) {
  final String text = error.toString();
  // The literal is json_rpc_2's own text and is never translated, so it can
  // be matched in any language.
  return text.toLowerCase().contains('bad state: the client is closed')
      ? currentL10n.commonNotConnectedError
      : text;
}

/// A card that is waiting: a thin line under the title row.
class CardLoading extends StatelessWidget {
  /// Creates the loading state.
  const CardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topCenter,
      child: LinearProgressIndicator(
        minHeight: 2,
        color: AppColors.znnColor,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

/// A card with nothing to show, or with an error: one quiet line.
class CardNote extends StatelessWidget {
  /// Creates a note reading [text].
  const CardNote(this.text, {super.key});

  /// Creates a note from an [error].
  CardNote.error(Object error, {super.key}) : text = cardErrorText(error);

  /// What the note says.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: kCardBodyPadding,
        child: Tooltip(
          message: text.length > 80 ? text : '',
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: cardDimStyle(context),
          ),
        ),
      ),
    );
  }
}

/// A line of a card: a dim label on the left, its value on the right.
class CardRow extends StatelessWidget {
  /// Creates a row of [label] and [value].
  const CardRow({required this.label, required this.value, super.key});

  /// Says what the value is.
  final String label;

  /// The value, usually an amount in mono.
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cardDimStyle(context),
            ),
          ),
          SizedBox(width: AppTokens.of(context).cardGap),
          Flexible(child: value),
        ],
      ),
    );
  }
}

/// Gives the fields under it the look of a card's form: filled, one height,
/// no border until focused.
///
/// The app theme sets a fill colour but not `filled`, so a bare TextField in
/// a `Panel` would be invisible.
class CardFields extends StatelessWidget {
  /// Creates the scope.
  const CardFields({required this.child, super.key});

  /// The form.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color faint = AppTokens.of(context).faint;
    final InputDecorationThemeData fields = theme.inputDecorationTheme.copyWith(
      filled: true,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      constraints: const BoxConstraints(minHeight: kCardFieldHeight),
      prefixIconColor: faint,
      suffixIconColor: faint,
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: fields,
        // A DropdownMenu that sets no decoration of its own reads this one,
        // and so matches the text fields beside it.
        dropdownMenuTheme: DropdownMenuThemeData(inputDecorationTheme: fields),
      ),
      child: child,
    );
  }
}

/// What a form can spend: a ledger label and the amount, on one line.
class CardAvailable extends StatelessWidget {
  /// Creates the line for [amount] smallest units of a token.
  const CardAvailable({
    required this.amount,
    required this.decimals,
    required this.symbol,
    this.symbolColor,
    super.key,
  });

  /// The balance in the smallest unit.
  final BigInt amount;

  /// The token's decimals.
  final int decimals;

  /// The token's symbol.
  final String symbol;

  /// The symbol's colour.
  final Color? symbolColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          context.l10n.cardAvailableLabel,
          style: ledgerLabelStyle(context),
        ),
        SizedBox(width: AppTokens.of(context).cardGap),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: AmountText(
              amount,
              decimals: decimals,
              style: cardValueStyle(context),
              symbol: symbol,
              symbolColor: symbolColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// A word inside a field that acts on it, such as Max: plain text, so the
/// card keeps one filled button.
class CardFieldAction extends StatelessWidget {
  /// Creates the action.
  const CardFieldAction({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// The word shown.
  final String label;

  /// Null while the action cannot be taken.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: tokens.znnInk,
          disabledForegroundColor: tokens.faint,
          minimumSize: const Size(44, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: kTextButtonTextStyle,
        ),
        child: Text(label),
      ),
    );
  }
}

/// A small secondary card or row action on the raised surface with a line.
/// Ordinary actions and xs table controls supply their own size and type.
///
/// [line] colours the border; pass the error colour for an action that
/// undoes something (revoke, cancel, undelegate).
ButtonStyle cardSecondaryButtonStyle(BuildContext context, {Color? line}) {
  final ThemeData theme = Theme.of(context);
  final Color ink =
      theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
  return OutlinedButton.styleFrom(
    foregroundColor: ink,
    iconColor: line ?? ink,
    backgroundColor: theme.colorScheme.primaryContainer,
    disabledBackgroundColor: Colors.transparent,
    side: BorderSide(color: line ?? cardLineColor(context)),
    shape: const StadiumBorder(),
    minimumSize: Size(0, AppTokens.of(context).compactButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    textStyle: kTextButtonTextStyle,
  );
}

/// Makes every OutlinedButton under it a secondary action.
///
/// For the buttons a table repeats on each row, and for the second button of
/// a card that already has its main action.
class CardSecondaryButtons extends StatelessWidget {
  /// Creates the scope.
  const CardSecondaryButtons({required this.child, this.line, super.key});

  /// What holds the buttons.
  final Widget child;

  /// The border colour; the theme's line when null.
  final Color? line;

  @override
  Widget build(BuildContext context) {
    return OutlinedButtonTheme(
      data: OutlinedButtonThemeData(
        style: cardSecondaryButtonStyle(context, line: line),
      ),
      child: child,
    );
  }
}
