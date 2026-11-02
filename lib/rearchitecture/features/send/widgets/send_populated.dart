import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_sync_status/node_sync_status.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_scope.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/widgets/send_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'send_contacts_picker.dart';
part 'send_recipient_warning.dart';

/// How a party to a send is named in a notification: its label, else its
/// address with the middle cut out, so the line fits a notification row.
String sentPartyName(String address, Map<String, String> labels) {
  final String? label = labels[address];
  if (label != null && label.isNotEmpty) {
    return label;
  }
  return address.length <= 16
      ? address
      : '${address.substring(0, 8)}…${address.substring(address.length - 6)}';
}

/// The title of the notification for a send that was published.
///
/// Every part comes from the published block, never from the form. A balance
/// refresh while the block waits for plasma replaces the form with its
/// loading state, and the form that comes back is empty: read from its
/// fields, the title was "Sent  ZNN from Address 2 to".
String sentNotificationTitle({
  required AppLocalizations l10n,
  required BigInt amount,
  required int decimals,
  required String symbol,
  required String sender,
  required String recipient,
  required Map<String, String> labels,
}) => l10n.sentDetails(
  // Without trailing zeros, whatever was typed.
  amount.addDecimals(decimals),
  sentPartyName(recipient, labels),
  sentPartyName(sender, labels),
  symbol,
);

/// Read-only ownership of the original form and its actual open review.
abstract interface class SendFormOrigin {
  /// The sender captured by this form's State, before any provider replacement.
  SendTransactionBloc get originalSender;

  /// Current draft facts; reading them performs no wallet operation.
  String get draftSender;

  /// The draft's current asset identifier, without exposing a mutable token.
  String get draftToken;

  /// Requires this form's identical review and unchanged draft.
  bool matchesOriginalReview(SendIntent intent);
}

/// A widget with multiple [DropdownMenu] and [TextField] that allow the user
/// to select and input the information needed for sending a transaction
class SendPopulated extends StatefulWidget {
  /// Creates a new instance.
  const SendPopulated({
    required this.balances,
    this.showSender = true,
    this.showSyncNotice = true,
    this.contacts,
    this.priceFeed,
    this.syncCubit,
    this.captureSession,
    this.confirm,
    this.onOriginalResult,
    super.key,
  });

  /// A map with wallet addresses as keys, and account info objects as values
  final Map<String, AccountInfo> balances;

  /// False when Transfer keeps this selector in its shared header.
  final bool showSender;

  /// False when the shared Transfer header already shows this notice.
  final bool showSyncNotice;

  /// The existing address book, injectable without opening storage.
  final ContactsStore? contacts;

  /// The shared feed, injectable without making a network request.
  final PriceFeed? priceFeed;

  /// The existing session sync owner; no second timer is created here.
  final NodeSyncStatusCubit? syncCubit;

  /// Isolates session qualification without opening wallet files in tests.
  final SendSession? Function()? captureSession;

  /// The actual dialog when omitted; injectable for deferred lifecycle checks.
  final Future<bool> Function(SendIntent intent, SendSession session)? confirm;

  /// Observes a settled result without changing its publication outcome.
  final SendResultObserver? onOriginalResult;

  @override
  State<SendPopulated> createState() => _SendPopulatedState();
}

class _SendPopulatedState extends State<SendPopulated>
    implements SendFormOrigin {
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  final FocusNode _recipientFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();

  final GlobalKey<SendButtonState> _sendPaymentButtonKey = GlobalKey();

  final List<Token> _availableAssets = <Token>[];

  Token _selectedToken = kDualCoin.first;

  String _selectedSenderAddress = kSelectedAddress!;

  late final SendTransactionBloc _sender;
  late ContactsStore _contacts;
  NodeSyncStatusCubit? _syncCubit;
  (String, String)? _acceptedLookAlike;
  String _lastRecipient = '';
  bool _confirming = false;
  SendIntent? _originalReview;
  SendDraftCubit? _originalReviewDraftOwner;
  SendDraft? _originalReviewDraft;

  @override
  SendTransactionBloc get originalSender => _sender;
  @override
  String get draftSender => _selectedSenderAddress;
  @override
  String get draftToken => _selectedToken.tokenStandard.toString();
  @override
  bool matchesOriginalReview(SendIntent intent) =>
      mounted && identical(_originalReview, intent) &&
      identical(_draft, _originalReviewDraftOwner) &&
      identical(_draft?.state, _originalReviewDraft) && intent.matches(
        fromAddress: _selectedSenderAddress,
        recipient: _recipient,
        amount: _amount,
        token: _selectedToken,
      );

  // The amount as inputted by the user
  String get _amount => _amountController.text;

  String get _recipient => _recipientController.text;

  AccountInfo get _accountInfo => widget.balances[_selectedSenderAddress]!;

  String? get _recipientErrorText =>
      _recipient.isNotEmpty ? InputValidators.checkAddress(_recipient) : null;

  String? get _amountErrorText => _amountController.text.isNotEmpty
      ? InputValidators.correctValue(
          _amountController.text,
          _accountInfo.getBalance(
            _selectedToken.tokenStandard,
          ),
          _selectedToken.decimals,
          BigInt.zero,
        )
      : null;

  bool get _isInputValid =>
      _recipientErrorText == null &&
      _amountErrorText == null &&
      _amountController.text.isNotEmpty &&
      _recipient.isNotEmpty &&
      (_parsedAmount() ?? BigInt.zero) > BigInt.zero;

  bool get _isValidTransaction => _hasBalance(_accountInfo) && _isInputValid;

  bool get _busy => _confirming || _sender.busy.value;

  LookAlike? get _lookAlike => _recipient.isEmpty || _recipientErrorText != null
      ? null
      : _contacts.lookAlike(
          _recipient,
          ownAddresses: widget.balances.keys,
        );

  bool get _needsRecipientCheck {
    final LookAlike? finding = _lookAlike;
    return finding != null &&
        _acceptedLookAlike != (_recipient, finding.address);
  }

  int? get _nodeLag => sendMomentumsBehind(_syncCubit?.state);

  bool get _canSubmit =>
      !_busy &&
      _nodeLag == null &&
      !_needsRecipientCheck &&
      _isValidTransaction;

  /// Where the form is kept while its page is not shown. Null where nothing
  /// above provides one (a test, another host): the form then forgets, as it
  /// did before.
  SendDraftCubit? _draft;
  bool _applyingRecipient = false;

  @override
  void initState() {
    super.initState();
    _sender = context.read<SendTransactionBloc>();
    _contacts = widget.contacts ?? ContactsStore.instance;
    _syncCubit = widget.syncCubit ?? context.read<NodeSyncStatusCubit?>();
    _draft = context.read<SendDraftCubit?>();
    if (!widget.balances.containsKey(_selectedSenderAddress)) {
      _selectedSenderAddress = widget.balances.keys.first;
    }
    _restoreDraft();
    _lastRecipient = _recipient;
    _recipientController.addListener(_recipientChanged);
    _amountController.addListener(_saveDraft);
    _sender.busy.addListener(_senderChanged);
  }

  @override
  void didUpdateWidget(SendPopulated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.contacts, widget.contacts)) {
      _contacts = widget.contacts ?? ContactsStore.instance;
      _acceptedLookAlike = null;
    }
    _syncCubit = widget.syncCubit ?? context.read<NodeSyncStatusCubit?>();
    if (!widget.balances.containsKey(_selectedSenderAddress)) {
      _selectedSenderAddress = widget.balances.keys.first;
      _selectedToken = kDualCoin.first;
      _acceptedLookAlike = null;
    }
    _availableAssets.clear();
  }

  void _recipientChanged() {
    if (_lastRecipient != _recipient) {
      _lastRecipient = _recipient;
      _acceptedLookAlike = null;
    }
    _saveDraft();
  }

  void _senderChanged() {
    if (!mounted || _busy) return;
    final SendDraft? draft = _draft?.state;
    if (draft != null) _applyDraft(draft);
  }

  void _applyDraft(SendDraft next) {
    // A header or palette selection cannot rewrite the active operation's
    // fields. The latest draft is applied when its original owner is idle.
    if (_busy) return;
    _applyingRecipient = true;
    try {
      setState(() {
        final String? from = next.fromAddress;
        if (from != null &&
            from != _selectedSenderAddress &&
            widget.balances.containsKey(from)) {
          _selectedSenderAddress = from;
          _selectedToken = kDualCoin.first;
          _acceptedLookAlike = null;
          _availableAssets.clear();
        }
        if (_availableAssets.isEmpty) {
          _fillAvailableTokens(
            initialTokens: kDualCoin,
            list: _availableAssets,
            tokensWithBalance: _getTokensWithBalance(_accountInfo),
          );
        }
        for (final Token token in _availableAssets) {
          if (token.tokenStandard.toString() == next.tokenStandard) {
            _selectedToken = token;
          }
        }
        if (_recipient != next.recipient) {
          _recipientController.value = TextEditingValue(
            text: next.recipient,
            selection: TextSelection.collapsed(offset: next.recipient.length),
          );
        }
        if (_amount != next.amount) _amountController.text = next.amount;
      });
    } finally {
      _applyingRecipient = false;
    }
  }

  /// Puts back what was typed before the page was left. A sender or a token
  /// that is no longer on offer is dropped, and the form falls back to its
  /// defaults for that field.
  void _restoreDraft() {
    final SendDraft? draft = _draft?.state;
    if (draft == null || draft.isEmpty) {
      return;
    }
    final String? from = draft.fromAddress;
    if (from != null && widget.balances.containsKey(from)) {
      _selectedSenderAddress = from;
    }
    _fillAvailableTokens(
      initialTokens: kDualCoin,
      list: _availableAssets,
      tokensWithBalance: _getTokensWithBalance(_accountInfo),
    );
    for (final Token token in _availableAssets) {
      if (token.tokenStandard.toString() == draft.tokenStandard) {
        _selectedToken = token;
      }
    }
    _recipientController.text = draft.recipient;
    _amountController.text = draft.amount;
  }

  void _saveDraft() {
    if (_applyingRecipient) return;
    _draft?.save(
      fromAddress: _selectedSenderAddress,
      tokenStandard: _selectedToken.tokenStandard.toString(),
      recipient: _recipient,
      amount: _amount,
    );
  }

  Widget _bindRecipientDraft(Widget child) {
    final SendDraftCubit? draft = _draft;
    if (draft == null) return child;
    return BlocListener<SendDraftCubit, SendDraft>(
      bloc: draft,
      listener: (_, SendDraft next) {
        // Several synchronous field edits can queue older stream events.
        // Replaying one would overwrite the latest text and its review.
        if (identical(draft.state, next)) _applyDraft(next);
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_availableAssets.isEmpty) {
      _fillAvailableTokens(
        initialTokens: kDualCoin,
        list: _availableAssets,
        tokensWithBalance: _getTokensWithBalance(
          widget.balances[_selectedSenderAddress]!,
        ),
      );
    }

    return _bindRecipientDraft(
      _syncCubit == null
          ? _buildObservedForm()
          : BlocBuilder<NodeSyncStatusCubit, NodeSyncStatusState>(
              bloc: _syncCubit,
              builder: (_, _) => _buildObservedForm(),
            ),
    );
  }

  Widget _buildObservedForm() => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[
      _recipientController,
      _amountController,
      _contacts,
      _sender.busy,
      BalanceVisibility.instance,
    ]),
    builder: (_, _) => _buildForm(),
  );

  Widget _buildForm() {
    final AppTokens tokens = AppTokens.of(context);
    final LookAlike? finding = _lookAlike;
    final String typed = _recipient;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.transferControlRadius),
      borderSide: BorderSide(color: tokens.line),
    );
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: tokens.card2,
          isDense: true,
          contentPadding: tokens.transferFieldPadding,
          border: border,
          enabledBorder: border,
          disabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: tokens.faint),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.showSyncNotice) SendSyncNotice(syncCubit: _syncCubit),
          Padding(
            padding: tokens.transferFormPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.showSender) ...<Widget>[
                  _buildDefaultAddressDropdown(),
                  SizedBox(height: tokens.transferFormGap),
                ],
                _buildRecipientField(finding),
                if (_contacts.readFailed) ...<Widget>[
                  SizedBox(height: tokens.transferFormGap),
                  Text(
                    context.l10n.sendContactsUnavailable,
                    key: const Key('send_contacts_unavailable'),
                    style: tokens.transferCaptionText,
                  ),
                ],
                if (finding == null &&
                    _contacts.recent(_selectedSenderAddress).isNotEmpty)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: tokens.transferFormGap,
                    ),
                    child: _buildRecentRecipients(),
                  ),
                if (finding != null) ...<Widget>[
                  SizedBox(height: tokens.transferFormGap),
                  _SendRecipientWarning(
                    finding: finding,
                    typed: _recipient,
                    name: _partyName(finding.address),
                    acknowledged: !_needsRecipientCheck,
                    onUseKnown: _busy
                        ? null
                        : () => _useKnownRecipient(typed, finding.address),
                    onUseTyped: _busy || !_needsRecipientCheck
                        ? null
                        : () => _acknowledgeLookAlike(typed, finding.address),
                  ),
                ],
                SizedBox(height: tokens.transferFormGap),
                LayoutBuilder(
                  key: const Key('send_amount_row'),
                  builder: (_, BoxConstraints constraints) {
                    final Widget amount = _buildAmountField();
                    final Widget token = _buildCoinDropdown();
                    if (constraints.maxWidth < tokens.transferTokenWidth * 2) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          amount,
                          SizedBox(height: tokens.transferFieldGap),
                          token,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: amount),
                        SizedBox(width: tokens.transferFieldGap),
                        SizedBox(
                          width: tokens.transferTokenWidth,
                          child: token,
                        ),
                      ],
                    );
                  },
                ),
                if (finding == null) ...<Widget>[
                  SizedBox(height: tokens.transferFormGap),
                  _buildAvailable(),
                  if (_contacts.lastSent(
                        _recipient,
                        from: _selectedSenderAddress,
                      ) !=
                      null) ...<Widget>[
                    SizedBox(height: tokens.transferFormGap),
                    _buildLastSent(),
                  ],
                ],
                SizedBox(height: tokens.transferFormGap),
                KeyedSubtree(
                  key: const Key('send_submit_button'),
                  child: SendButton(
                    key: _sendPaymentButtonKey,
                    text: _actionLabel(),
                    onPressed: _canSubmit ? _onSendPaymentPressed : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actionLabel() {
    if (_recipient.isEmpty || _recipientErrorText != null) {
      return context.l10n.sendEnterAddress;
    }
    if (_amount.isEmpty) return context.l10n.sendEnterAmount;
    final BigInt? amount = _parsedAmount();
    if (amount != null &&
        amount > _accountInfo.getBalance(_selectedToken.tokenStandard)) {
      return context.l10n.sendNotEnough(_selectedToken.symbol);
    }
    if (_amountErrorText != null || amount == null || amount <= BigInt.zero) {
      return context.l10n.sendEnterAmount;
    }
    if (_nodeLag != null) return context.l10n.sendWaitingForNode;
    if (_needsRecipientCheck) return context.l10n.sendCheckAddress;
    return context.l10n.sendAmount(
      amount.addDecimals(_selectedToken.decimals),
      _selectedToken.symbol,
    );
  }

  BigInt? _parsedAmount() {
    if (_amount.isEmpty ||
        !RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(_amount) ||
        (_amount.contains('.') &&
            _amount.split('.')[1].length > _selectedToken.decimals)) {
      return null;
    }
    return _amount.extractDecimals(_selectedToken.decimals);
  }

  Widget _buildRecipientField(LookAlike? finding) {
    final AppTokens tokens = AppTokens.of(context);
    return TextField(
      key: const Key('send_recipient_field'),
      controller: _recipientController,
      enabled: !_busy,
      style: tokens.dataText,
      textDirection: TextDirection.ltr,
      textAlign: ltrTextAlign(context, TextAlign.start),
      decoration: InputDecoration(
        errorText: _recipientErrorText,
        hintText: context.l10n.recipientAddress,
        enabledBorder: finding == null
            ? null
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  tokens.transferControlRadius,
                ),
                borderSide: BorderSide(color: tokens.transferWarningLine),
              ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              key: const Key('send_address_book'),
              tooltip: context.l10n.sendAddressBook,
              iconSize: tokens.heroCopyIconSize,
              onPressed: _busy ? null : _openContacts,
              icon: const Icon(Icons.menu_book_outlined),
            ),
            if (_recipient.isNotEmpty)
              IconButton(
                key: const Key('send_clear_recipient'),
                tooltip: context.l10n.sendClearRecipient,
                iconSize: tokens.heroCopyIconSize,
                onPressed: _busy ? null : _recipientController.clear,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
      focusNode: _recipientFocusNode,
      onSubmitted: (_) => _amountFocusNode.requestFocus(),
    );
  }

  Widget _buildAmountField() => AmountRefusalScope(
    controller: _amountController,
    builder: (_, String? refusal) => TextField(
      key: const Key('send_amount_field'),
      controller: _amountController,
      enabled: !_busy,
      style: AppTokens.of(context).transferAmountText,
      textDirection: TextDirection.ltr,
      textAlign: ltrTextAlign(context, TextAlign.start),
      decoration: InputDecoration(
        errorText: refusal ?? _amountErrorText,
        hintText: context.l10n.amount,
        suffixIcon: CardFieldAction(
          label: context.l10n.max,
          onPressed: _busy ? null : () => _onMaxPressed(_accountInfo),
        ),
      ),
      focusNode: _amountFocusNode,
      inputFormatters: FormatUtils.getAmountTextInputFormatters(_amount),
      onSubmitted: (_) {
        if (_canSubmit) unawaited(_onSendPaymentPressed());
      },
    ),
  );

  Widget _buildAvailable() {
    final AppTokens tokens = AppTokens.of(context);
    final BigInt? amount = _parsedAmount();
    return Row(
      key: const Key('send_available_line'),
      children: <Widget>[
        Text(context.l10n.sendAvailable, style: tokens.transferCaptionText),
        SizedBox(width: tokens.fieldLabelGap),
        Expanded(
          child: HiddenAmount(
            style: tokens.dataText,
            child: AmountText(
              _accountInfo.getBalance(_selectedToken.tokenStandard),
              decimals: _selectedToken.decimals,
              style: tokens.transferCaptionText.copyWith(
                color: tokens.foreground,
              ),
              symbol: _selectedToken.symbol,
            ),
          ),
        ),
        // Transfer retains its offstage forms. A mounted DollarText would
        // keep its third-party feed active while Receive or Zap is shown.
        if (TickerMode.valuesOf(context).enabled &&
            amount != null &&
            amount > BigInt.zero)
          DollarText(
            key: const Key('send_dollar_estimate'),
            amount: amount,
            decimals: _selectedToken.decimals,
            coin: PricedCoin.ofTokenStandard(
              _selectedToken.tokenStandard.toString(),
            ),
            approx: true,
            hidden: BalanceVisibility.instance.hidden,
            feed: widget.priceFeed,
          ),
      ],
    );
  }

  Widget _buildRecentRecipients() {
    final AppTokens tokens = AppTokens.of(context);
    return Wrap(
      key: const Key('send_recent_recipients'),
      spacing: tokens.transferRecentGap,
      runSpacing: tokens.transferRecentGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(context.l10n.sendRecent, style: tokens.captionText),
        for (final RecentRecipient recent in _contacts.recent(
          _selectedSenderAddress,
        ))
          Tooltip(
            message: recent.address,
            child: OutlinedButton(
              key: ValueKey<String>('send_recent_${recent.address}'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.standard,
                minimumSize: Size(0, tokens.smallButtonHeight),
                padding: tokens.transferChipPadding,
                foregroundColor: _recipient == recent.address
                    ? tokens.foreground
                    : tokens.dim,
                backgroundColor: _recipient == recent.address
                    ? tokens.card2
                    : null,
                textStyle: tokens.captionText,
              ),
              onPressed: _busy ? null : () => _selectRecipient(recent.address),
              child: Text(
                _partyName(recent.address),
                style:
                    _contacts.byAddress(recent.address) == null &&
                        !kAddressLabelMap.containsKey(recent.address)
                    ? tokens.captionText.copyWith(
                        fontFamily: tokens.monoFontFamily,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  String _partyName(String address) =>
      _contacts.byAddress(address)?.name ??
      sentPartyName(address, kAddressLabelMap);

  Widget _buildLastSent() {
    final AppTokens tokens = AppTokens.of(context);
    final DateTime sent = _contacts.lastSent(
      _recipient,
      from: _selectedSenderAddress,
    )!;
    return Row(
      key: const Key('send_last_sent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.info_outline,
          size: tokens.heroCopyIconSize,
          color: tokens.dim,
        ),
        SizedBox(width: tokens.inlineGap),
        Expanded(
          child: Text(
            context.l10n.sendLastSent(
              _partyName(_recipient),
              FormatUtils.formatDateForTable(
                sent.millisecondsSinceEpoch,
                locale: Localizations.localeOf(context),
              ),
            ),
            style: tokens.transferCaptionText,
          ),
        ),
      ],
    );
  }

  void _selectRecipient(String address) {
    if (_busy) return;
    _recipientController.value = TextEditingValue(
      text: address,
      selection: TextSelection.collapsed(offset: address.length),
    );
    _amountFocusNode.requestFocus();
  }

  void _useKnownRecipient(String typed, String known) {
    if (_busy || _recipient != typed || _lookAlike?.address != known) return;
    _selectRecipient(known);
  }

  void _acknowledgeLookAlike(String typed, String known) {
    if (_busy || _recipient != typed || _lookAlike?.address != known) return;
    setState(() => _acceptedLookAlike = (typed, known));
  }

  Future<void> _openContacts() async {
    if (_busy) return;
    final String? selected = await showFrostedDialog<String>(
      context: context,
      builder: (_) => _SendContactsPicker(contacts: _contacts, sender: _sender),
    );
    if (!mounted || _busy || selected == null) return;
    _selectRecipient(selected);
  }

  Future<void> _onSendPaymentPressed() async {
    if (!_canSubmit) return;
    final SendDraftCubit? draftOwner = _draft;
    final SendDraft? originalDraft = draftOwner?.state;
    try {
      final SendIntent intent = SendIntent.capture(
        fromAddress: _selectedSenderAddress,
        recipient: _recipient,
        amount: _amount,
        token: _selectedToken,
      );
      final SendSession? session = widget.captureSession == null
          ? _captureSendSession()
          : widget.captureSession!();
      if (session == null || !session.isCurrent()) return;
      final SendResultObserver observer =
          widget.onOriginalResult ?? _captureResultObserver(session);
      final String? recipientName = _contacts.byAddress(intent.toAddress)?.name;
      final String? senderName = kAddressLabelMap[intent.fromAddress];
      final bool contactsUnavailable = _contacts.readFailed;
      final bool firstTime =
          !contactsUnavailable &&
          _contacts.isFirstTime(intent.fromAddress, intent.toAddress);
      bool decided = false;
      void finishConfirmation(
        BuildContext dialogContext, {
        required bool accepted,
      }) {
        if (decided ||
            !dialogContext.mounted ||
            ModalRoute.of(dialogContext)?.isCurrent != true) {
          return;
        }
        decided = true;
        Navigator.pop(dialogContext, accepted);
      }

      setState(() {
        _confirming = true;
        _originalReview = intent;
        _originalReviewDraftOwner = draftOwner;
        _originalReviewDraft = originalDraft;
      });
      final bool accepted = widget.confirm != null
          ? await widget.confirm!(intent, session)
          : (await showFrostedDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext dialogContext) => SendConfirmation(
                    intent: intent,
                    hardware: session.hardware,
                    recipientName: recipientName,
                    senderName: senderName,
                    contactsUnavailable: contactsUnavailable,
                    firstTime: firstTime,
                    onConfirm: () =>
                        finishConfirmation(dialogContext, accepted: true),
                    onCancel: () =>
                        finishConfirmation(dialogContext, accepted: false),
                  ),
                ) ??
                false);
      if (!mounted ||
          !accepted ||
          !TickerMode.valuesOf(context).enabled ||
          !session.isCurrent() ||
          _sender.busy.value ||
          _nodeLag != null ||
          _needsRecipientCheck ||
          !_isValidTransaction ||
          !identical(draftOwner?.state, originalDraft) ||
          !intent.matches(
            fromAddress: _selectedSenderAddress,
            recipient: _recipient,
            amount: _amount,
            token: _selectedToken,
          )) {
        return;
      }
      final SendRequestHandle? handle = _sender.trySubmitTransfer(
        intent.toEvent(),
        canStart: session.isCurrent,
      );
      if (handle == null) return;
      _sendPaymentButtonKey.currentState?.animateForward();
      unawaited(
        _observeOriginal(handle, intent, draftOwner, originalDraft, observer),
      );
    } on Object {
      // No publication was admitted when confirmation or capture failed.
      // An admitted result is handled independently by _observeOriginal.
    } finally {
      if (mounted) {
        setState(() {
          _confirming = false;
          _originalReview = null;
          _originalReviewDraftOwner = null;
          _originalReviewDraft = null;
        });
        if (!_sender.busy.value && draftOwner != null && !draftOwner.isClosed) {
          _applyDraft(draftOwner.state);
        }
      }
    }
  }

  SendSession? _captureSendSession() {
    final WalletFile? file = kWalletFile;
    final Zenon? client = zenon;
    if (file == null ||
        client == null ||
        !kWalletInitCompleted ||
        kCurrentPage != Tabs.transfer) {
      return null;
    }
    final int revision = WalletContextRevision.value;
    final int chain = getChainIdentifier();
    final int? nodeChain = kNodeChainId;
    final String? node = kCurrentNode;
    final String? address = kSelectedAddress;
    final String sender = _selectedSenderAddress;
    return SendSession(
      hardware: file.isHardwareWallet,
      isCurrent: () =>
          WalletContextRevision.value == revision &&
          identical(kWalletFile, file) &&
          identical(zenon, client) &&
          kWalletInitCompleted &&
          kCurrentPage == Tabs.transfer &&
          kCurrentNode == node &&
          kNodeChainId == nodeChain &&
          kSelectedAddress == address &&
          getChainIdentifier() == chain &&
          kDefaultAddressList.contains(sender),
    );
  }

  Future<void> _observeOriginal(
    SendRequestHandle handle,
    SendIntent intent,
    SendDraftCubit? draft,
    SendDraft? originalDraft,
    SendResultObserver observer,
  ) async {
    final SendRequestResult result = await handle.result;
    try {
      if (result.accepted && draft != null && originalDraft != null) {
        draft.clearIfUnchanged(originalDraft);
      }
      if (mounted) {
        if (result.accepted &&
            (draft == null || draft.state.isEmpty) &&
            intent.matches(
              fromAddress: _selectedSenderAddress,
              recipient: _recipient,
              amount: _amount,
              token: _selectedToken,
            )) {
          _applyingRecipient = true;
          try {
            _amountController.clear();
            _recipientController.clear();
          } finally {
            _applyingRecipient = false;
          }
        }
        _sendPaymentButtonKey.currentState?.animateReverse();
        if (result.accepted) _sendPaymentButtonKey.currentState?.landed();
      }
    } on Object {
      // A draft or animation observer cannot alter the settled result.
    }
    try {
      await observer(intent, result);
    } on Object {
      // The original result was already settled before optional presentation.
    }
  }

  Widget _buildDefaultAddressDropdown() {
    final AppTokens tokens = AppTokens.of(context);
    return DropdownMenu<String>(
      key: const Key('send_sender_field'),
      enabled: !_busy,
      expandedInsets: EdgeInsets.zero,
      initialSelection: _selectedSenderAddress,
      enableFilter: true,
      textStyle: tokens.compactText,
      dropdownMenuEntries: <DropdownMenuEntry<String>>[
        for (final String address in widget.balances.keys)
          DropdownMenuEntry<String>(
            value: address,
            label:
                kAddressLabelMap[address] ??
                sentPartyName(address, const <String, String>{}),
          ),
      ],
      filterCallback:
          (List<DropdownMenuEntry<String>> entries, String filter) => entries
              .where(
                (DropdownMenuEntry<String> entry) =>
                    entry.label.toLowerCase().contains(filter.toLowerCase()) ||
                    entry.value.contains(filter.toLowerCase()),
              )
              .toList(),
      onSelected: (String? value) {
        if (_busy || value == null || !widget.balances.containsKey(value)) {
          return;
        }
        setState(() {
          _selectedSenderAddress = value;
          _selectedToken = kDualCoin.first;
          _availableAssets.clear();
          _acceptedLookAlike = null;
          _saveDraft();
        });
      },
    );
  }

  Widget _buildCoinDropdown() {
    final AppTokens tokens = AppTokens.of(context);
    return DropdownMenu<Token>(
      key: const Key('send_token_field'),
      enabled: !_busy,
      expandedInsets: EdgeInsets.zero,
      initialSelection: _selectedToken,
      textStyle: tokens.bodyText,
      enableFilter: true,
      leadingIcon:
          PricedCoin.ofTokenStandard(
                _selectedToken.tokenStandard.toString(),
              ) ==
              null
          ? null
          : Icon(
              Icons.circle,
              size: tokens.heroIconSize,
              color: _selectedToken.tokenStandard == kZnnCoin.tokenStandard
                  ? tokens.znn
                  : tokens.qsr,
            ),
      dropdownMenuEntries: <DropdownMenuEntry<Token>>[
        for (final Token token in _availableAssets)
          DropdownMenuEntry<Token>(
            value: token,
            label: token.isCoin
                ? token.symbol
                : '${token.symbol} (${token.tokenStandard.toString().short})',
          ),
      ],
      onSelected: (Token? value) {
        if (_busy || value == null || _selectedToken == value) return;
        setState(() {
          _selectedToken = value;
          _saveDraft();
        });
      },
    );
  }

  void _onMaxPressed(AccountInfo accountInfo) {
    if (_busy) return;
    final BigInt maxBalance = accountInfo.getBalance(
      _selectedToken.tokenStandard,
    );

    final BigInt currentBalance = _parsedAmount() ?? BigInt.zero;

    if (currentBalance < maxBalance) {
      _amountController.text = maxBalance.addDecimals(_selectedToken.decimals);
    }
  }

  SendResultObserver _captureResultObserver(
    SendSession session,
  ) {
    final AppLocalizations l10n = context.l10n;
    final Map<String, String> labels = Map<String, String>.of(kAddressLabelMap);
    final int chain = getChainIdentifier();
    final String? scope = bellScopeForWallet(
      chain,
      kDefaultAddressList.whereType<String>(),
    );
    final NotificationsBloc? history = sl.isRegistered<NotificationsBloc>()
        ? sl.get<NotificationsBloc>()
        : null;
    return (SendIntent original, SendRequestResult result) async {
      if (history == null) return;
      final AccountBlockTemplate? block = result.block;
      await history.addNotification(
        WalletNotification(
          title: result.accepted
              ? sentNotificationTitle(
                  l10n: l10n,
                  amount: original.amount,
                  decimals: original.decimals,
                  symbol: original.symbol,
                  sender: original.fromAddress,
                  recipient: original.toAddress,
                  labels: labels,
                )
              : l10n.sendOutcomeUnavailable,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          details: result.accepted && block != null
              ? l10n.hashValue(block.hash.toString())
              : l10n.sendOutcomeUncertain,
          type: result.accepted
              ? NotificationType.paymentSent
              : NotificationType.error,
          eventKind: 'transfer_result',
          walletScope: scope,
          chainId: chain,
          transactionHash: result.accepted ? block?.hash.toString() : null,
        ),
        shouldDisplay: session.isCurrent,
      );
    };
  }

  bool _hasBalance(AccountInfo accountInfo) =>
      accountInfo.getBalance(
        _selectedToken.tokenStandard,
      ) >
      BigInt.zero;

  List<Token> _getTokensWithBalance(AccountInfo accountInfo) {
    final List<Token> tokens = <Token>[];
    final List<BalanceInfoListItem> balanceInfoList =
        accountInfo.balanceInfoList!;

    for (final BalanceInfoListItem balanceInfo in balanceInfoList) {
      final BigInt balance = balanceInfo.balance!;
      final Token token = balanceInfo.token!;
      if (balance > BigInt.zero) {
        tokens.add(token);
      }
    }

    return tokens;
  }

  @override
  void dispose() {
    _sender.busy.removeListener(_senderChanged);
    _recipientController.dispose();
    _amountController.dispose();
    _recipientFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _fillAvailableTokens({
    required List<Token> initialTokens,
    required List<Token> list,
    required List<Token> tokensWithBalance,
  }) {
    final List<Token> emptyList = <Token>[...tokensWithBalance];
    // The available tokens should always contain the two coins
    if (!emptyList.contains(kZnnCoin)) {
      emptyList.insert(0, kZnnCoin);
    }
    if (!emptyList.contains(kQsrCoin)) {
      emptyList.insert(0, kQsrCoin);
    }

    list.addAll(sortAssets(emptyList));
  }
}
