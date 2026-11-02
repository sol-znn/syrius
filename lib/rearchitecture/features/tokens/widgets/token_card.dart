import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/view/token_favorite.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_inline_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_row_action.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/clipboard_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The height of a token row.
const double kTokenRowHeight = 60;

/// The width of the supply column of the token list.
const double kTokenSupplyColumnWidth = 120;

/// The width of the owner column of the token list.
const double kTokenOwnerColumnWidth = 110;

/// Existing permission-scoped entry actions plus the row's disclosure.
const double kTokenActionsColumnWidth = 4 * kTokenRowActionSize;

/// The gap between two columns of the token list.
const double kTokenColumnGap = 12;

/// Below this width a row drops its owner column.
const double kTokenOwnerColumnMinRowWidth = 640;

/// The padding at both ends of a token row, and of the list's header.
const EdgeInsets kTokenRowPadding = EdgeInsets.symmetric(horizontal: 16);

/// One token of the list: what it is, how much of it exists, who owns it,
/// and what the selected address may do with it.
///
/// Its exact ZTS owns one disclosure; the forms stay inside the ledger.
class TokenCard extends StatefulWidget {
  /// Creates a [TokenCard].
  const TokenCard({
    required this._token,
    required this._favoritesCallback,
    this.balance,
    this.isCurrent,
    this.favoriteRepository,
    this.detailIsCurrent,
    this.onSendToken,
    this.publisher,
    this.question,
    super.key,
  });

  final Token _token;
  final VoidCallback _favoritesCallback;

  /// Null is unavailable. Only a complete current account establishes zero.
  final BigInt? balance;

  /// Rechecked when an existing money action is activated.
  final bool Function()? isCurrent;

  /// Shared committed membership for the one list and its stars.
  final FavoriteTokensRepository? favoriteRepository;

  /// The list revokes every old opening before another row can take over.
  final bool Function()? detailIsCurrent;

  /// Routes the exact standard into Send without publishing.
  final ValueChanged<String>? onSendToken;

  /// Synthetic sources can exercise the actual disclosure without a wallet.
  final TokenActionPublisher? publisher;

  /// A finite injected question for source widget qualification.
  final TokenActionQuestion? question;

  @override
  State<TokenCard> createState() => _TokenCardState();
}

class _TokenCardState extends State<TokenCard> {
  bool _ownOpen = false;
  bool _wasOpen = false;
  int _epoch = 0;
  TokenActionMode _mode = TokenActionMode.mint;
  RowDetailGroupState? _group;

  String get _standard => widget._token.tokenStandard.toString();
  bool get _open => _group == null ? _ownOpen : _group!.openId == _standard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _group = RowDetailGroup.maybeOf(context);
    if (_wasOpen && !_open) _epoch++;
    _wasOpen = _open;
  }

  void _toggle(bool open) {
    if (!mounted) return;
    _epoch++;
    if (_group != null) {
      if (open) {
        _group!.open(_standard);
      } else {
        _group!.close(_standard);
      }
    } else {
      setState(() => _ownOpen = open);
    }
    _wasOpen = open;
  }

  void _select(TokenActionMode mode) {
    if (!(widget.isCurrent?.call() ?? true)) return;
    setState(() => _mode = mode);
    if (!_open) _toggle(true);
  }

  @override
  Widget build(BuildContext context) {
    final Token token = widget._token;
    final AppTokens theme = AppTokens.of(context);
    final int epoch = _epoch;
    final bool Function()? originalDetailCurrent = widget.detailIsCurrent;
    bool current() =>
        mounted &&
        _open &&
        epoch == _epoch &&
        (widget.isCurrent?.call() ?? true) &&
        (originalDetailCurrent?.call() ?? true);
    return RowDetail(
      id: _standard,
      keyPrefix: 'token_$_standard',
      open: _open,
      onToggle: _toggle,
      detail: (BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(
          start: theme.tokenDetailIndent,
          end: theme.pageGap,
          bottom: theme.tokenDetailBottomInset,
        ),
        child: TokenInlineActions(
          token: token,
          isCurrent: current,
          initialMode: _mode,
          onSendToken: widget.onSendToken,
          publisher: widget.publisher,
          question: widget.question,
          authorityEpoch: epoch,
        ),
      ),
      row: SizedBox(
        height: theme.tokenRowHeight,
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: AppTokens.of(context).pageGap,
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool wide =
                  constraints.maxWidth >=
                  AppTokens.of(context).tokenTableMinWidth;
              final AppTokens tokens = AppTokens.of(context);
              return Row(
                children: <Widget>[
                  RowDetailIgnore(
                    child: TokenFavorite(
                      token: token,
                      callback: widget._favoritesCallback,
                      repository: widget.favoriteRepository,
                    ),
                  ),
                  SizedBox(width: tokens.inlineGap),
                  Container(
                    width: tokens.homeTokenBadgeSize,
                    height: tokens.homeTokenBadgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.faint,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      token.symbol.isEmpty ? '' : token.symbol.substring(0, 1),
                      style: tokens.homeTokenBadgeText,
                    ),
                  ),
                  SizedBox(width: tokens.inlineGap),
                  // Without its column the owner moves under the name, so
                  // its address can still be copied in a narrow window.
                  Expanded(
                    child: _Identity(token: token, showOwner: !wide),
                  ),
                  SizedBox(width: tokens.pageGap),
                  SizedBox(
                    width: tokens.tokenBalanceWidth,
                    child: _Balance(balance: widget.balance, token: token),
                  ),
                  SizedBox(width: tokens.pageGap),
                  SizedBox(
                    width: tokens.tokenSupplyWidth,
                    child: _Supply(token: token),
                  ),
                  if (wide)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: tokens.pageGap,
                      ),
                      child: SizedBox(
                        width: tokens.tokenOwnerWidth,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _Owner(owner: token.owner),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: kTokenActionsColumnWidth,
                    child: _Actions(
                      token: token,
                      isCurrent: widget.isCurrent,
                      onSelect: _select,
                      onToggle: () => _toggle(!_open),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }
}

/// A token's colour as text or as a line: the rule is `cardTokenInk`.
Color _tokenInk(BuildContext context, TokenStandard tokenStandard) =>
    cardTokenInk(tokenStandard, context);

/// The symbol and name over the token standard.
class _Identity extends StatelessWidget {
  const _Identity({required this.token, required this.showOwner});

  final Token token;

  /// Whether the owner goes on the second line, after the token standard.
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String standard = token.tokenStandard.toString();
    final bool isOwn = kDefaultAddressList.contains(token.owner.toString());
    final Widget standardText = _CopyText(
      text: standard,
      shown: standard.length > 16
          ? '${standard.substring(0, 8)}…'
                '${standard.substring(standard.length - 4)}'
          : standard,
      tooltip: context.l10n.tokensCopyStandard,
      style: monoStyle(
        cardDimStyle(context).copyWith(fontSize: 12, color: tokens.faint),
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                token.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cardValueStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isOwn)
              _Badge(
                icon: Icons.person_outline,
                color: tokens.znnInk,
                message: context.l10n.ownZtsToken,
              ),
            if (token.isUtility)
              _Badge(
                icon: Icons.settings_outlined,
                color: tokens.faint,
                message: context.l10n.utilityToken,
              ),
          ],
        ),
        const SizedBox(height: 2),
        if (showOwner)
          Row(
            children: <Widget>[
              Flexible(flex: 2, child: standardText),
              const SizedBox(width: kTokenColumnGap),
              Flexible(child: _Owner(owner: token.owner, fontSize: 12)),
            ],
          )
        else
          Row(
            children: <Widget>[
              Text(
                '${token.symbol} · ',
                textDirection: TextDirection.ltr,
                style: tokens.captionText.copyWith(
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
              Flexible(child: standardText),
            ],
          ),
      ],
    );
  }
}

/// A small mark after a token's name, explained by its tooltip.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: message,
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}

/// Text that copies [text] when pressed: an identifier too long to retype.
class _CopyText extends StatelessWidget {
  const _CopyText({
    required this.text,
    required this.shown,
    required this.tooltip,
    required this.style,
  });

  final String text;
  final String shown;
  final String tooltip;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$tooltip\n$text',
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AppTokens.of(context).cardRadius),
        onTap: () {
          if (context.mounted) ClipboardUtils.copyToClipboard(text, context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.content_copy,
                size: 12,
                color: AppTokens.of(context).faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exact issued supply. The maximum and flags remain available on hover.
class _Supply extends StatelessWidget {
  const _Supply({required this.token});

  final Token token;

  @override
  Widget build(BuildContext context) {
    final Color ink = _tokenInk(context, token.tokenStandard);
    final String max = cardAmount(
      token.maxSupply,
      token.decimals,
      token.symbol,
    );
    return Tooltip(
      message: <String>[
        '${context.l10n.maxSupply} $max',
        '${context.l10n.createTokenDecimalsLabel} ${token.decimals}',
        if (token.isMintable) context.l10n.mintable,
        if (token.isBurnable) context.l10n.burnableToken,
      ].join('\n'),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ValueFlash(
          value: token.totalSupply,
          color: ink,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: AmountText(
              token.totalSupply,
              decimals: token.decimals,
              style: cardValueStyle(context).copyWith(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.balance, required this.token});

  final BigInt? balance;
  final Token token;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final BigInt? units = balance;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: units == null
          ? Tooltip(
              message: context.l10n.tokensBalanceUnavailable,
              child: Text('-', style: tokens.dataText),
            )
          : ValueFlash(
              value: units,
              child: Tooltip(
                message: cardAmount(units, token.decimals, token.symbol),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: AmountText(
                    units,
                    decimals: token.decimals,
                    style: tokens.dataText,
                  ),
                ),
              ),
            ),
    );
  }
}

/// The owner: the address's label when it is one of this wallet's.
class _Owner extends StatelessWidget {
  const _Owner({required this.owner, this.fontSize = 13});

  final Address owner;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final String address = owner.toString();
    final String? label = kAddressLabelMap[address];
    final TextStyle style = cardDimStyle(context).copyWith(fontSize: fontSize);
    return _CopyText(
      text: address,
      shown: label ?? owner.toShortString(),
      tooltip: context.l10n.tokensCopyOwner,
      style: label == null ? monoStyle(style) : style,
    );
  }
}

/// What the selected address may do with the token, quiet until pointed at.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.token,
    required this.isCurrent,
    required this.onSelect,
    required this.onToggle,
  });

  final Token token;
  final bool Function()? isCurrent;
  final ValueChanged<TokenActionMode> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bool isOwner = kSelectedAddress == token.owner.toString();
    final bool current = isCurrent?.call() ?? true;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (isOwner && token.isMintable && token.totalSupply < token.maxSupply)
          TokenRowAction(
            key: const Key('token_mint_button'),
            tooltip: context.l10n.mint,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: current
                ? () {
                    if (isCurrent?.call() ?? true) {
                      onSelect(TokenActionMode.mint);
                    }
                  }
                : null,
          ),
        if (token.isBurnable || isOwner)
          TokenRowAction(
            key: const Key('token_burn_button'),
            tooltip: context.l10n.burn,
            icon: const Icon(Icons.local_fire_department_outlined),
            onPressed: current
                ? () {
                    if (isCurrent?.call() ?? true) {
                      onSelect(TokenActionMode.burn);
                    }
                  }
                : null,
          ),
        if (isOwner)
          TokenRowAction(
            key: const Key('token_transfer_button'),
            tooltip: context.l10n.transferTokenOwnership,
            icon: const Icon(Icons.swap_horiz),
            onPressed: current
                ? () {
                    if (isCurrent?.call() ?? true) {
                      onSelect(TokenActionMode.transfer);
                    }
                  }
                : null,
          ),
        RowDetailIgnore(
          child: TokenRowAction(
            key: const Key('token_detail_button'),
            tooltip: context.l10n.tokenDetails,
            icon: const RowDetailChevron(),
            onPressed: onToggle,
          ),
        ),
      ],
    );
  }
}

/// The ledger labels over the columns of the token list. Laid out as a
/// [TokenCard] is, so each label sits over its column.
class TokenListHeader extends StatelessWidget {
  /// Creates the header.
  const TokenListHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final TextStyle style = ledgerLabelStyle(context);
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: tokens.pageGap),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => Row(
          children: <Widget>[
            const SizedBox(width: kTokenRowActionSize),
            SizedBox(width: tokens.homeTokenBadgeSize + tokens.inlineGap * 2),
            Expanded(
              child: Text(context.l10n.tokensToken.toUpperCase(), style: style),
            ),
            SizedBox(width: tokens.pageGap),
            SizedBox(
              width: tokens.tokenBalanceWidth,
              child: Text(
                context.l10n.tokensYouHold.toUpperCase(),
                style: style,
                textAlign: TextAlign.end,
              ),
            ),
            SizedBox(width: tokens.pageGap),
            SizedBox(
              width: tokens.tokenSupplyWidth,
              child: Text(
                context.l10n.tokensSupply.toUpperCase(),
                style: style,
                textAlign: TextAlign.end,
              ),
            ),
            if (constraints.maxWidth >= tokens.tokenTableMinWidth)
              Padding(
                padding: EdgeInsetsDirectional.only(start: tokens.pageGap),
                child: SizedBox(
                  width: tokens.tokenOwnerWidth,
                  child: Text(
                    context.l10n.tokensOwner.toUpperCase(),
                    style: style,
                  ),
                ),
              ),
            const SizedBox(width: kTokenActionsColumnWidth),
          ],
        ),
      ),
    );
  }
}
