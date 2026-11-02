import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/zap/cubit/zap_draft_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// What is actually known about the missing recipient discovery operation.
enum ZapRecipientStatus {
  /// Discovery has not run and no candidate count is known.
  unavailable,

  /// A caller explicitly knows the result is empty.
  empty,
}

/// The Zap body inside Transfer's retained card, with local composition only.
///
/// Discovery, recipient copying and sending remain behind [Seam.zapSend].
/// There is no ready-recipient state: adding one requires the missing service,
/// rather than supplying an example address to this presentation widget.
class ZapForm extends StatefulWidget {
  /// Draws a retained draft without acquiring a wallet or starting Zap work.
  const ZapForm({
    required this.draft,
    required this.active,
    this.busy = false,
    this.priceFeed,
    this.visibility,
    this.recipientStatus = ZapRecipientStatus.unavailable,
    super.key,
  });

  /// The session-owned holder. The shell clears it on lock and closes it.
  final ZapDraftCubit draft;

  /// Whether this retained mode is visible and allowed to own local input.
  ///
  /// DollarText must be removed while inactive: an offstage listener would
  /// otherwise keep the shared price feed polling after leaving this mode.
  final bool active;

  /// Holds local input while another wallet operation owns publication.
  final bool busy;

  /// The existing shared feed, or a caller's no-network feed in tests.
  final PriceFeed? priceFeed;

  /// The shared privacy state, injectable without persisted preferences.
  final BalanceVisibility? visibility;

  /// Unavailable is the production default while discovery is unbuilt.
  final ZapRecipientStatus recipientStatus;

  @override
  State<ZapForm> createState() => _ZapFormState();
}

class _ZapFormState extends State<ZapForm> {
  final TextEditingController _znn = TextEditingController();
  final TextEditingController _qsr = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final FocusNode _formFocus = FocusNode(debugLabel: 'Zap composition');
  final FocusNode _znnFocus = FocusNode(debugLabel: 'Zap ZNN amount');
  final FocusNode _qsrFocus = FocusNode(debugLabel: 'Zap QSR amount');
  final FocusNode _messageFocus = FocusNode(debugLabel: 'Zap message');
  late StreamSubscription<ZapDraft> _draftSubscription;
  bool _synchronizing = false;
  bool _hasLocalization = false;
  bool _focusClearScheduled = false;

  bool get _interactive => widget.active && !widget.busy;

  @override
  void initState() {
    super.initState();
    _znn.addListener(_save);
    _qsr.addListener(_save);
    _message.addListener(_save);
    _znnFocus.addListener(_focusChanged);
    _qsrFocus.addListener(_focusChanged);
    _messageFocus.addListener(_focusChanged);
    _attachDraft();
    _scheduleFocusClear();
  }

  void _attachDraft() {
    final ZapDraftCubit owner = widget.draft;
    _draftSubscription = owner.stream.listen((ZapDraft value) {
      if (!mounted || widget.draft != owner || value != owner.state) {
        return;
      }
      _synchronize(value);
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasLocalization = true;
    _synchronize(widget.draft.state);
  }

  @override
  void didUpdateWidget(ZapForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      unawaited(_draftSubscription.cancel());
      _attachDraft();
      _synchronize(widget.draft.state);
    }
    _scheduleFocusClear();
  }

  void _synchronize(ZapDraft value) {
    _synchronizing = true;
    try {
      _setText(_znn, value.znn);
      _setText(_qsr, value.qsr);
      _setText(
        _message,
        value.message ??
            (_hasLocalization ? context.l10n.zapDefaultMessage : ''),
      );
    } finally {
      _synchronizing = false;
    }
  }

  void _setText(TextEditingController controller, String text) {
    if (controller.text == text) {
      return;
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _save() {
    if (_synchronizing || widget.draft.isClosed) {
      return;
    }
    final ZapDraft current = widget.draft.state;
    final String currentMessage =
        current.message ??
        (_hasLocalization ? context.l10n.zapDefaultMessage : '');
    if (current.znn == _znn.text &&
        current.qsr == _qsr.text &&
        currentMessage == _message.text) {
      return;
    }
    widget.draft.save(
      znn: _znn.text,
      qsr: _qsr.text,
      message: _message.text,
    );
    setState(() {});
  }

  void _focusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleFocusClear() {
    if (_interactive || _focusClearScheduled) {
      return;
    }
    _focusClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusClearScheduled = false;
      if (mounted && !_interactive && _formFocus.hasFocus) {
        _formFocus.unfocus();
      }
    });
  }

  void _refuseMissingAction() {
    runUnlessSeamed(
      seam: Seam.zapSend,
      // A direct callback must refuse too. Removing this seam without its
      // implementation would still fail explicitly instead of showing success.
      action: () => throw const SeamNotBuilt(Seam.zapSend),
    );
  }

  @override
  void dispose() {
    unawaited(_draftSubscription.cancel());
    _znn
      ..removeListener(_save)
      ..dispose();
    _qsr
      ..removeListener(_save)
      ..dispose();
    _message
      ..removeListener(_save)
      ..dispose();
    for (final FocusNode node in <FocusNode>[
      _znnFocus,
      _qsrFocus,
      _messageFocus,
    ]) {
      node
        ..removeListener(_focusChanged)
        ..dispose();
    }
    _formFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ZapDraft draft = widget.draft.state;
    final int bytes = draft.messageBytes(context.l10n.zapDefaultMessage);
    final String? amountError = _amountError(draft);
    return TickerMode(
      enabled: widget.active,
      child: ExcludeSemantics(
        excluding: !widget.active,
        child: Focus(
          focusNode: _formFocus,
          canRequestFocus: false,
          skipTraversal: true,
          // EditableText retains an inherited traversal refusal on its node.
          // A temporary hold uses focusability so Tab works after returning.
          descendantsAreFocusable: _interactive,
          includeSemantics: false,
          onFocusChange: (_) => _scheduleFocusClear(),
          child: IgnorePointer(
            ignoring: !_interactive,
            child: Padding(
              key: const Key('zap_form_ready'),
              padding: tokens.transferFormPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildRecipientHeading(context),
                  SizedBox(height: tokens.transferFormGap),
                  _buildRecipient(context),
                  SizedBox(height: tokens.transferFormGap),
                  _buildAmounts(context, draft),
                  if (amountError != null) ...<Widget>[
                    SizedBox(height: tokens.fieldLabelGap),
                    Text(
                      amountError,
                      key: const Key('zap_amount_error'),
                      style: tokens.compactText.copyWith(color: tokens.error),
                    ),
                  ],
                  SizedBox(height: tokens.transferFormGap),
                  _buildMessage(context, bytes),
                  if (bytes > ZapDraft.messageLimit) ...<Widget>[
                    SizedBox(height: tokens.fieldLabelGap),
                    Text(
                      context.l10n.zapMessageTooLong,
                      key: const Key('zap_message_error'),
                      style: tokens.compactText.copyWith(color: tokens.error),
                    ),
                  ],
                  SizedBox(height: tokens.transferFormGap),
                  _buildSummary(context, draft),
                  SizedBox(height: tokens.transferFormGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      buildShellSymbol(
                        context,
                        'info',
                        size: tokens.zapSmallGlyphSize,
                      ),
                      SizedBox(width: tokens.inlineGap),
                      Expanded(
                        child: Text(
                          context.l10n.zapNodeNotice,
                          key: const Key('zap_node_notice'),
                          style: tokens.compactText.copyWith(color: tokens.dim),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: tokens.transferFormGap),
                  SeamGate(
                    seam: Seam.zapSend,
                    child: PrimaryPill(
                      key: const Key('zap_submit_button'),
                      onPressed: _refuseMissingAction,
                      icon: buildShellSymbol(
                        context,
                        'zap',
                        size: tokens.zapGlyphSize,
                        color: tokens.primaryButtonForeground,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, tokens.transferActionHeight),
                        textStyle: tokens.transferActionText,
                      ),
                      child: _buildActionLabel(context, draft),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _amountError(ZapDraft draft) {
    if (draft.znnIssue == ZapAmountIssue.precision ||
        draft.qsrIssue == ZapAmountIssue.precision) {
      return context.l10n.validatorTooManyDecimals;
    }
    if (draft.blockCount == null || draft.blockCount == 0) {
      return context.l10n.validatorEnterValidAmount;
    }
    return null;
  }

  Widget _buildRecipientHeading(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool empty = widget.recipientStatus == ZapRecipientStatus.empty;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.inlineGap,
      runSpacing: tokens.fieldLabelGap,
      children: <Widget>[
        Text(
          context.l10n.zapRandomAlien.toUpperCase(),
          style: tokens.ledgerText,
        ),
        Text(
          empty
              ? context.l10n.noItemsFound
              : context.l10n.zapCandidatesUnavailable,
          key: Key(
            empty ? 'zap_candidates_empty' : 'zap_candidates_unavailable',
          ),
          style: tokens.zapCaptionText,
        ),
      ],
    );
  }

  Widget _buildRecipient(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool empty = widget.recipientStatus == ZapRecipientStatus.empty;
    final Widget field = Semantics(
      label: context.l10n.recipientAddress,
      child: Container(
        key: const Key('zap_recipient_field'),
        constraints: BoxConstraints(minHeight: tokens.fieldHeight),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.zapMessagePadding
              .resolve(
                Directionality.of(context),
              )
              .left,
        ),
        decoration: BoxDecoration(
          color: tokens.card2,
          borderRadius: BorderRadius.circular(tokens.transferControlRadius),
          border: Border.all(color: tokens.faint),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                empty ? context.l10n.noItemsFound : context.l10n.notYet,
                key: Key(
                  empty ? 'zap_recipient_empty' : 'zap_recipient_unavailable',
                ),
                style: tokens.dataText.copyWith(color: tokens.faint),
              ),
            ),
            SeamGate(
              seam: Seam.zapSend,
              child: IconButton(
                key: const Key('zap_copy_recipient'),
                tooltip: context.l10n.zapCopyRecipient,
                onPressed: _refuseMissingAction,
                visualDensity: VisualDensity.compact,
                icon: _ZapSymbol(
                  symbol: 'copy',
                  size: tokens.zapSmallGlyphSize,
                  color: tokens.faint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final Widget pick = SeamGate(
      seam: Seam.zapSend,
      child: OutlinedButton.icon(
        key: const Key('zap_pick_another'),
        onPressed: _refuseMissingAction,
        icon: _ZapSymbol(
          symbol: 'dice',
          size: tokens.zapGlyphSize,
          color: tokens.foreground,
        ),
        label: Text(context.l10n.zapPickAnother),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: Size(0, tokens.fieldHeight),
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: tokens.cardPadding.left,
          ),
          textStyle: tokens.buttonText,
          foregroundColor: tokens.foreground,
          backgroundColor: tokens.card2,
          side: BorderSide(color: tokens.line),
          shape: const StadiumBorder(),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double pickWidth =
            _textWidth(
              context,
              context.l10n.zapPickAnother,
              tokens.buttonText,
            ) +
            tokens.zapGlyphSize +
            tokens.inlineGap +
            tokens.cardPadding.horizontal;
        if (constraints.maxWidth <
            pickWidth + tokens.fieldHeight * 2 + tokens.transferFieldGap) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              field,
              SizedBox(height: tokens.transferFieldGap),
              pick,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: field),
            SizedBox(width: tokens.transferFieldGap),
            pick,
          ],
        );
      },
    );
  }

  Widget _buildAmounts(BuildContext context, ZapDraft draft) {
    final AppTokens tokens = AppTokens.of(context);
    final Widget znn = _buildAmountField(
      context,
      coin: kZnnCoin,
      controller: _znn,
      focus: _znnFocus,
      invalid: draft.znnIssue != null || draft.blockCount == 0,
    );
    final Widget qsr = _buildAmountField(
      context,
      coin: kQsrCoin,
      controller: _qsr,
      focus: _qsrFocus,
      invalid: draft.qsrIssue != null || draft.blockCount == 0,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minimum =
            _textWidth(
              context,
              '0.00000001',
              tokens.zapAmountText,
            ) +
            _textWidth(context, kQsrCoin.symbol, tokens.dataText) +
            tokens.zapCoinSize +
            tokens.inlineGap * 2 +
            tokens.zapMessagePadding.horizontal;
        if (constraints.maxWidth < minimum * 2 + tokens.transferFieldGap) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              znn,
              SizedBox(height: tokens.transferFieldGap),
              qsr,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: znn),
            SizedBox(width: tokens.transferFieldGap),
            Expanded(child: qsr),
          ],
        );
      },
    );
  }

  Widget _buildAmountField(
    BuildContext context, {
    required Token coin,
    required TextEditingController controller,
    required FocusNode focus,
    required bool invalid,
  }) {
    final AppTokens tokens = AppTokens.of(context);
    final bool znn = coin.tokenStandard == kZnnCoin.tokenStandard;
    final Color line = invalid
        ? tokens.error
        : focus.hasFocus
        ? tokens.focusRing
        : tokens.faint;
    return Container(
      key: Key(znn ? 'zap_znn_control' : 'zap_qsr_control'),
      constraints: BoxConstraints(minHeight: tokens.fieldHeight),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: tokens.zapMessagePadding
            .resolve(
              Directionality.of(context),
            )
            .left,
      ),
      decoration: BoxDecoration(
        color: tokens.card2,
        borderRadius: BorderRadius.circular(tokens.transferControlRadius),
        border: Border.all(color: line),
      ),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Container(
              width: tokens.zapCoinSize,
              height: tokens.zapCoinSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: znn ? tokens.znn : tokens.qsr,
              ),
              child: Text(
                coin.symbol.substring(0, 1),
                style: znn
                    ? tokens.zapCoinText.copyWith(color: tokens.onZnn)
                    : tokens.zapCoinText,
              ),
            ),
          ),
          SizedBox(width: tokens.inlineGap),
          Expanded(
            child: Semantics(
              label: context.l10n.zapAmountLabel(coin.symbol),
              child: TextField(
                key: Key(znn ? 'zap_znn_amount' : 'zap_qsr_amount'),
                controller: controller,
                focusNode: focus,
                readOnly: !_interactive,
                style: tokens.zapAmountText,
                textDirection: TextDirection.ltr,
                textAlign: ltrTextAlign(context),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _refuseMissingAction(),
                decoration: _fieldDecoration(hint: context.l10n.amount),
              ),
            ),
          ),
          SizedBox(width: tokens.inlineGap),
          ExcludeSemantics(
            child: Ltr(
              child: Text(
                coin.symbol,
                style: tokens.dataText.copyWith(
                  color: znn ? tokens.znnInk : tokens.qsrInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint}) => InputDecoration(
    hintText: hint,
    isDense: true,
    isCollapsed: true,
    filled: false,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  );

  Widget _buildMessage(BuildContext context, int bytes) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      key: const Key('zap_message_area'),
      constraints: BoxConstraints(minHeight: tokens.zapMessageMinHeight),
      padding: tokens.zapMessagePadding,
      decoration: BoxDecoration(
        color: tokens.card2,
        borderRadius: BorderRadius.circular(tokens.transferControlRadius),
        border: Border.all(
          color: bytes > ZapDraft.messageLimit
              ? tokens.error
              : _messageFocus.hasFocus
              ? tokens.focusRing
              : tokens.faint,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            label: context.l10n.activityMessage,
            child: TextField(
              key: const Key('zap_message'),
              controller: _message,
              focusNode: _messageFocus,
              readOnly: !_interactive,
              style: tokens.bodyText,
              textDirection: ltrUnlessRtl(_message.text),
              maxLines: null,
              onSubmitted: (_) => _refuseMissingAction(),
              decoration: _fieldDecoration(hint: context.l10n.activityMessage),
            ),
          ),
          SizedBox(height: tokens.fieldLabelGap),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Ltr(
              child: Text(
                context.l10n.zapBytes(bytes),
                key: const Key('zap_message_bytes'),
                style: tokens.zapCaptionText.copyWith(
                  fontFamily: tokens.monoFontFamily,
                  color: bytes > ZapDraft.messageLimit
                      ? tokens.error
                      : tokens.faint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, ZapDraft draft) {
    final AppTokens tokens = AppTokens.of(context);
    final int? count = draft.blockCount;
    final List<CoinAmount> parts = <CoinAmount>[
      if ((draft.znnBaseUnits ?? BigInt.zero) > BigInt.zero)
        (
          amount: draft.znnBaseUnits!,
          decimals: ZapDraft.decimals,
          coin: PricedCoin.znn,
        ),
      if ((draft.qsrBaseUnits ?? BigInt.zero) > BigInt.zero)
        (
          amount: draft.qsrBaseUnits!,
          decimals: ZapDraft.decimals,
          coin: PricedCoin.qsr,
        ),
    ];
    final String summary = switch (count) {
      1 => context.l10n.zapOneBlock,
      2 => context.l10n.zapTwoBlocks,
      _ => context.l10n.zapBlockPerCoin,
    };
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.inlineGap,
      runSpacing: tokens.fieldLabelGap,
      children: <Widget>[
        Text(
          summary,
          key: const Key('zap_blocks'),
          style: tokens.compactText.copyWith(color: tokens.dim),
        ),
        if (widget.active && count != null && count > 0)
          ListenableBuilder(
            listenable: widget.visibility ?? BalanceVisibility.instance,
            builder: (BuildContext context, Widget? child) => DollarText.sum(
              parts,
              key: const Key('zap_dollars'),
              feed: widget.priceFeed,
              hidden: (widget.visibility ?? BalanceVisibility.instance).hidden,
            ),
          ),
      ],
    );
  }

  Widget _buildActionLabel(BuildContext context, ZapDraft draft) {
    final AppTokens tokens = AppTokens.of(context);
    final BigInt? znn = draft.znnBaseUnits;
    final BigInt? qsr = draft.qsrBaseUnits;
    final String label;
    if (znn == null || qsr == null || draft.blockCount == 0) {
      label = context.l10n.transferZap;
    } else if (znn > BigInt.zero && qsr > BigInt.zero) {
      label = context.l10n.zapActionBoth(
        splitAmount(znn, ZapDraft.decimals).$1,
        splitAmount(qsr, ZapDraft.decimals).$1,
      );
    } else {
      final bool useZnn = znn > BigInt.zero;
      label = context.l10n.zapActionSingle(
        splitAmount(useZnn ? znn : qsr, ZapDraft.decimals).$1,
        useZnn ? kZnnCoin.symbol : kQsrCoin.symbol,
      );
    }
    // The translated action keeps its sans face; every figure within it is
    // exact mono text, including grouped large amounts and fractional units.
    final TextStyle actionStyle = tokens.transferActionText.copyWith(
      color: tokens.primaryButtonForeground,
    );
    final List<InlineSpan> spans = <InlineSpan>[];
    int end = 0;
    for (final RegExpMatch match in RegExp(
      '[0-9][0-9,.]*',
    ).allMatches(label)) {
      if (match.start > end) {
        spans.add(TextSpan(text: label.substring(end, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: monoStyle(actionStyle),
        ),
      );
      end = match.end;
    }
    if (end < label.length) {
      spans.add(TextSpan(text: label.substring(end)));
    }
    return Text.rich(
      TextSpan(style: actionStyle, children: spans),
      textDirection: ltrUnlessRtl(label),
      textAlign: TextAlign.center,
    );
  }
}

double _textWidth(BuildContext context, String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}

// These two canonical symbols are not in the shared shell symbol set yet.
// Keep their source paths rather than substituting differently shaped icons.
const Map<String, String> _zapSymbols = <String, String>{
  'copy': '''
<rect x="9" y="9" width="12" height="12" rx="2"/>
<path d="M5 15V5a2 2 0 0 1 2-2h10"/>
''',
  'dice': '''
<rect x="3" y="3" width="18" height="18" rx="3"/>
<circle cx="8" cy="8" r="1.2"/>
<circle cx="16" cy="8" r="1.2"/>
<circle cx="12" cy="12" r="1.2"/>
<circle cx="8" cy="16" r="1.2"/>
<circle cx="16" cy="16" r="1.2"/>
''',
};

class _ZapSymbol extends StatelessWidget {
  const _ZapSymbol({
    required this.symbol,
    required this.size,
    required this.color,
  });

  final String symbol;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
fill="none" stroke="currentColor" stroke-width="1.8"
stroke-linecap="round" stroke-linejoin="round">
${_zapSymbols[symbol]}
</svg>
''',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}
