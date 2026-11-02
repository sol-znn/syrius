import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/explorer_links.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One captured question, injectable so widget cases never sign or use a node.
typedef TokenActionQuestion = Future<bool> Function(TokenActionIntent intent);

/// Retained exact fields and factual flags inside one expanded token row.
class TokenInlineActions extends StatefulWidget {
  /// A legacy dialog selects [fixedMode] and uses this same publication path.
  const TokenInlineActions({
    required this.token,
    required this.isCurrent,
    this.publisher,
    this.initialMode = TokenActionMode.mint,
    this.fixedMode,
    this.onSendToken,
    this.question,
    this.onOutcome,
    this.onBusyChanged,
    this.onSubmission,
    this.showFacts = true,
    this.authorityEpoch,
    this.allowCapture = true,
    super.key,
  });

  /// Display metadata grants no publication authority.
  final Token token;

  /// The row or legacy route's captured presentation generation.
  final bool Function() isCurrent;

  /// Production captures the wallet. Tests inject complete offline sources.
  final TokenActionPublisher? publisher;

  /// A compact row action may open the corresponding retained mode.
  final TokenActionMode initialMode;

  /// Existing dialogs keep their original single action.
  final TokenActionMode? fixedMode;

  /// Presentation-only routing into the existing Send form.
  final ValueChanged<String>? onSendToken;

  /// A finite injected question replaces only the dialog, never publication.
  final TokenActionQuestion? question;

  /// Observes the exact original outcome without owning it.
  final ValueChanged<TokenActionOutcome>? onOutcome;

  /// Optional observation of this form's currently authorized local state.
  final ValueChanged<bool>? onBusyChanged;

  /// Chrome can follow the original Future independently of form visibility.
  final ValueChanged<TokenActionSubmission>? onSubmission;

  /// Legacy dialog chrome already names its token.
  final bool showFacts;

  /// A closure round trip requires a new proof before enabling the form.
  final Object? authorityEpoch;

  /// A failed pre-dialog capture must not be replaced after opening.
  final bool allowCapture;

  @override
  State<TokenInlineActions> createState() => _TokenInlineActionsState();
}

class _TokenInlineActionsState extends State<TokenInlineActions>
    with WidgetsBindingObserver {
  final TextEditingController _mintAmount = TextEditingController();
  final TextEditingController _burnAmount = TextEditingController();
  late final TextEditingController _beneficiary = TextEditingController(
    text: widget.publisher?.session.address ?? kSelectedAddress ?? '',
  );
  final TextEditingController _newOwner = TextEditingController();
  late TokenActionMode _mode = widget.fixedMode ?? widget.initialMode;
  TokenActionPublisher? _publisher;
  TokenActionProof? _proof;
  TokenActionOutcome? _outcome;
  Object? _read;
  Object? _operation;
  Object? _heldObservation;
  bool _loading = true;
  bool _submitting = false;
  bool _rearming = false;
  bool _confirming = false;
  bool _visible = true;
  bool _windowActive = true;
  int _epoch = 0;
  int _modeEpoch = 0;
  bool _attached = false;
  FrostedDialogRoute<bool>? _questionRoute;
  NavigatorState? _questionNavigator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WalletContextRevision.changes.addListener(_authorityChanged);
    for (final TextEditingController field in _fields) {
      field.addListener(_fieldChanged);
    }
  }

  Iterable<TextEditingController> get _fields => <TextEditingController>[
    _mintAmount,
    _burnAmount,
    _beneficiary,
    _newOwner,
  ];

  void _fieldChanged() {
    if (mounted) setState(() {});
  }

  void _authorityChanged() {
    _epoch++;
    _resetLocalWork();
    _read = null;
    _proof = null;
    _loading = false;
    _dismissQuestion();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool wasVisible = _visible;
    final bool ownQuestion =
        _confirming &&
        (_questionRoute?.isCurrent ?? false) &&
        (_questionRoute?.isActive ?? false);
    final bool visible =
        ownQuestion ||
        (TickerMode.valuesOf(context).enabled &&
            (ModalRoute.of(context)?.isCurrent ?? true));
    if (_visible && !visible) {
      _epoch++;
      _resetLocalWork();
      _read = null;
      _proof = null;
      _loading = false;
      _dismissQuestion();
    }
    _visible = visible;
    if (_attached) {
      if (!wasVisible && visible && _windowActive && !_submitting) {
        unawaited(_refresh());
      }
      return;
    }
    _attached = true;
    _publisher = widget.publisher ?? (widget.allowCapture ? _capture() : null);
    unawaited(_refresh());
  }

  TokenActionPublisher? _capture() {
    final String? address = kSelectedAddress;
    if (address == null) return null;
    try {
      return TokenActionPublisher.capture(
        sender: context.read<SendTransactionBloc>(),
        address: address,
      );
    } on Object {
      return null;
    }
  }

  @override
  void didUpdateWidget(TokenInlineActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token.tokenStandard != widget.token.tokenStandard ||
        !identical(oldWidget.publisher, widget.publisher) ||
        oldWidget.authorityEpoch != widget.authorityEpoch) {
      _epoch++;
      _modeEpoch++;
      _dismissQuestion();
      _resetLocalWork();
      _publisher =
          widget.publisher ?? (widget.allowCapture ? _capture() : null);
      _read = null;
      _proof = null;
      if (widget.isCurrent()) {
        unawaited(_refresh());
      } else {
        _loading = false;
      }
    }
    final TokenActionMode requested = widget.fixedMode ?? widget.initialMode;
    if (oldWidget.initialMode != widget.initialMode ||
        oldWidget.fixedMode != widget.fixedMode) {
      _modeEpoch++;
      _dismissQuestion();
      _resetLocalWork();
      _mode = requested;
      _observeCurrentHold();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool active = state == AppLifecycleState.resumed;
    if (_windowActive && !active) {
      _epoch++;
      _resetLocalWork();
      _read = null;
      _proof = null;
      _loading = false;
      _dismissQuestion();
    }
    final bool resumed = !_windowActive && active;
    _windowActive = active;
    if (resumed && _visible && !_submitting) unawaited(_refresh());
    if (mounted) setState(() {});
  }

  bool get _current =>
      mounted &&
      _visible &&
      _windowActive &&
      widget.isCurrent() &&
      (_publisher?.session.isCurrent ?? true);

  void _resetLocalWork() {
    _operation = null;
    _heldObservation = null;
    _confirming = false;
    _submitting = false;
    _rearming = false;
    _outcome = null;
  }

  bool _sameScope(
    TokenActionPublisher publisher,
    TokenStandard standard,
    int epoch,
  ) =>
      mounted &&
      identical(_publisher, publisher) &&
      widget.token.tokenStandard == standard &&
      epoch == _epoch;

  void _observeCurrentHold() {
    final TokenActionPublisher? publisher = _publisher;
    if (publisher != null) {
      _observeHeld(publisher, widget.token.tokenStandard, _epoch);
    }
  }

  void _observeHeld(
    TokenActionPublisher publisher,
    TokenStandard standard,
    int epoch,
  ) {
    if (!_sameScope(publisher, standard, epoch)) return;
    final Object observation = Object();
    _heldObservation = observation;
    final TokenActionOutcome? held = publisher.heldFor(standard);
    _outcome = held;
    final Future<TokenActionOutcome>? settlement = publisher.settlementFor(
      standard,
    );
    if (held?.status != TokenActionStatus.submitting || settlement == null) {
      return;
    }
    unawaited(
      _followHeld(publisher, standard, epoch, observation, settlement),
    );
  }

  Future<void> _followHeld(
    TokenActionPublisher publisher,
    TokenStandard standard,
    int epoch,
    Object observation,
    Future<TokenActionOutcome> settlement,
  ) async {
    final TokenActionOutcome original = await settlement;
    if (!_sameScope(publisher, standard, epoch) ||
        !identical(_heldObservation, observation) ||
        !_current) {
      return;
    }
    setState(() => _outcome = original);
    if (original.status == TokenActionStatus.refused && _operation == null) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final TokenActionPublisher? publisher = _publisher;
    final TokenStandard standard = TokenStandard.parse(
      widget.token.tokenStandard.toString(),
    );
    final int epoch = _epoch;
    final Object read = Object();
    _read = read;
    _proof = null;
    _outcome = publisher?.heldFor(standard);
    _loading = publisher != null;
    if (publisher == null) return;
    _observeHeld(publisher, standard, epoch);
    try {
      final TokenActionProof proof = await publisher.read(standard);
      if (!_sameScope(publisher, standard, epoch) ||
          !identical(_read, read) ||
          !_current ||
          !proof.isCurrent) {
        return;
      }
      setState(() {
        _proof = proof;
        _outcome = publisher.heldFor(standard);
        _loading = false;
        if (widget.fixedMode == null && !proof.permits(_mode)) {
          _mode = proof.permits(TokenActionMode.mint)
              ? TokenActionMode.mint
              : proof.permits(TokenActionMode.burn)
              ? TokenActionMode.burn
              : TokenActionMode.flags;
          _modeEpoch++;
        }
      });
    } on Object {
      if (!_sameScope(publisher, standard, epoch) ||
          !identical(_read, read) ||
          !_current) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  void _select(TokenActionMode mode) {
    if (!_current || mode == _mode || widget.fixedMode != null) return;
    _modeEpoch++;
    _dismissQuestion();
    _resetLocalWork();
    _observeCurrentHold();
    setState(() => _mode = mode);
  }

  String _label(TokenActionMode mode) => switch (mode) {
    TokenActionMode.mint => context.l10n.mint,
    TokenActionMode.burn => context.l10n.burn,
    TokenActionMode.transfer => context.l10n.tokensTransferOwnership,
    TokenActionMode.flags => context.l10n.tokensFlags,
  };

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Token token = _proof?.token ?? widget.token;
    final bool current = _current;
    return PopScope(
      canPop: !_submitting,
      child: IgnorePointer(
        ignoring: !current,
        child: Focus(
          canRequestFocus: false,
          descendantsAreFocusable: current,
          child: ExcludeSemantics(
            excluding: !current,
            child: FocusTraversalGroup(
              child: Column(
                key: ValueKey<String>('token_detail_${token.tokenStandard}'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.showFacts)
                    LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final Widget facts = _TokenFacts(
                              token: token,
                              metadataOnly: _mode == TokenActionMode.flags,
                            );
                            final Widget modes = _buildSegment();
                            if (constraints.maxWidth <
                                    tokens.tokenActionFormWidth ||
                                MediaQuery.textScalerOf(context).scale(1) >
                                    1.3) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  facts,
                                  SizedBox(height: tokens.tokenDetailBodyGap),
                                  modes,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(child: facts),
                                SizedBox(width: tokens.tokenDetailFactGap),
                                Flexible(child: modes),
                              ],
                            );
                          },
                    )
                  else if (widget.fixedMode == null)
                    _buildSegment(),
                  SizedBox(height: tokens.tokenDetailBodyGap),
                  if (_loading)
                    SizedBox(
                      height: tokens.tokenActionHeight,
                      child: const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_proof == null)
                    _buildStatus(TokenActionStatus.refused)
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final TokenActionMode mode
                            in TokenActionMode.values)
                          _TokenModeBody(
                            visible: mode == _mode,
                            child: mode == TokenActionMode.flags
                                ? _TokenFacts(token: token, flagsOnly: true)
                                : _buildForm(mode),
                          ),
                      ],
                    ),
                  if (_mode == TokenActionMode.mint &&
                      _proof != null &&
                      token.isMintable)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        top: tokens.tokenDetailBodyGap,
                      ),
                      child: Text(
                        context.l10n.tokensRemainingSupply(
                          cardAmount(
                            token.maxSupply - token.totalSupply,
                            token.decimals,
                            token.symbol,
                          ),
                        ),
                        style: tokens.captionText.copyWith(
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ),
                  if (_mode == TokenActionMode.transfer)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        top: tokens.tokenDetailBodyGap,
                      ),
                      child: Text(
                        context.l10n.tokensTransferNote,
                        style: tokens.captionText,
                      ),
                    ),
                  if (_outcome != null)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        top: tokens.tokenDetailBodyGap,
                      ),
                      child: _buildOutcome(_outcome!),
                    ),
                  if (widget.showFacts) _buildLinks(token),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegment() => Segment<TokenActionMode>(
    keyPrefix: 'token_action_mode',
    selected: _mode,
    onChanged: _select,
    items: <SegmentItem<TokenActionMode>>[
      for (final TokenActionMode mode in TokenActionMode.values)
        SegmentItem<TokenActionMode>(value: mode, label: _label(mode)),
    ],
  );

  Widget _buildForm(TokenActionMode mode) {
    final AppTokens tokens = AppTokens.of(context);
    final TokenActionProof proof = _proof!;
    final Token token = proof.token;
    final int epoch = _epoch;
    final int modeEpoch = _modeEpoch;
    final bool Function() originalCurrent = widget.isCurrent;
    bool current() =>
        _current &&
        originalCurrent() &&
        epoch == _epoch &&
        modeEpoch == _modeEpoch &&
        mode == _mode;
    final TextEditingController amount = mode == TokenActionMode.mint
        ? _mintAmount
        : _burnAmount;
    final BigInt max = mode == TokenActionMode.mint
        ? token.maxSupply - token.totalSupply
        : proof.balance;
    final BigInt? units = parseTokenActionAmount(amount.text, token.decimals);
    final bool receiverValid =
        mode == TokenActionMode.burn ||
        InputValidators.checkAddress(
              mode == TokenActionMode.mint ? _beneficiary.text : _newOwner.text,
            ) ==
            null;
    final bool permitted =
        proof.permits(mode) &&
        receiverValid &&
        (mode == TokenActionMode.transfer ||
            (units != null && units > BigInt.zero && units <= max));
    final TokenActionOutcome? previous = _outcome;
    final bool held =
        previous != null && previous.status != TokenActionStatus.refused;
    final bool enabled =
        current() &&
        permitted &&
        !_confirming &&
        !_submitting &&
        !_rearming &&
        !held;
    final Widget amountField = TextField(
      key: Key(
        mode == TokenActionMode.mint
            ? 'mint_amount_field'
            : 'burn_amount_field',
      ),
      controller: amount,
      enabled: !_submitting,
      style: tokens.tokenActionAmountText,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: FormatUtils.getAmountTextInputFormatters(amount.text),
      decoration: InputDecoration(
        isDense: true,
        constraints: BoxConstraints(minHeight: tokens.tokenActionHeight),
        hintText: context.l10n.amount,
        suffixText: token.symbol,
        suffixStyle: tokens.dataText.copyWith(
          color: cardTokenInk(token.tokenStandard, context),
        ),
        suffixIcon: TextButton(
          onPressed: current() && max > BigInt.zero && !_submitting
              ? () {
                  if (current()) amount.text = max.addDecimals(token.decimals);
                }
              : null,
          child: Text(context.l10n.max),
        ),
      ),
      onSubmitted: (_) {
        if (current()) unawaited(_submit(mode, epoch, modeEpoch, current));
      },
    );
    final TextEditingController receiver = mode == TokenActionMode.mint
        ? _beneficiary
        : _newOwner;
    final Widget receiverField = TextField(
      key: Key(
        mode == TokenActionMode.mint
            ? 'mint_beneficiary_field'
            : 'transfer_owner_field',
      ),
      controller: receiver,
      enabled: !_submitting,
      style: tokens.dataText,
      textDirection: TextDirection.ltr,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp('[0-9a-z]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        constraints: BoxConstraints(minHeight: tokens.tokenActionHeight),
        hintText: mode == TokenActionMode.mint
            ? context.l10n.beneficiaryAddress
            : context.l10n.newOwnerAddress,
        suffixIcon: mode == TokenActionMode.mint
            ? TextButton(
                onPressed: current() && !_submitting
                    ? () {
                        if (current()) {
                          _beneficiary.text = proof.session.address;
                        }
                      }
                    : null,
                child: Text(context.l10n.tokensThisAddress),
              )
            : null,
      ),
      onSubmitted: (_) {
        if (current()) unawaited(_submit(mode, epoch, modeEpoch, current));
      },
    );
    final Widget action = PrimaryPill(
      key: ValueKey<String>('token_${mode.name}_submit'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, tokens.tokenActionHeight),
        maximumSize: Size(double.infinity, tokens.tokenActionHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: enabled
          ? () => unawaited(_submit(mode, epoch, modeEpoch, current))
          : null,
      child: Text(
        _submitting ? context.l10n.tokensActionSubmitting : _label(mode),
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: tokens.tokenActionFormWidth),
      child: Container(
        padding: tokens.tokenActionFormPadding,
        decoration: BoxDecoration(
          color: tokens.card3,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stacked =
                constraints.maxWidth < tokens.tokenSearchWidth * 2 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (stacked) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (mode != TokenActionMode.transfer) amountField,
                  if (mode == TokenActionMode.mint)
                    SizedBox(height: tokens.tokenActionGap),
                  if (mode != TokenActionMode.burn) receiverField,
                  SizedBox(height: tokens.tokenActionGap),
                  action,
                ],
              );
            }
            return Row(
              children: <Widget>[
                if (mode != TokenActionMode.transfer)
                  Expanded(child: amountField),
                if (mode == TokenActionMode.mint)
                  SizedBox(width: tokens.tokenActionGap),
                if (mode != TokenActionMode.burn)
                  Expanded(flex: 2, child: receiverField),
                SizedBox(width: tokens.tokenActionGap),
                action,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit(
    TokenActionMode mode,
    int epoch,
    int modeEpoch,
    bool Function() originalCurrent,
  ) async {
    final TokenActionProof? proof = _proof;
    final TokenActionPublisher? publisher = _publisher;
    final TokenStandard standard = TokenStandard.parse(
      widget.token.tokenStandard.toString(),
    );
    final TokenActionQuestion? question = widget.question;
    final ValueChanged<bool>? onBusyChanged = widget.onBusyChanged;
    final ValueChanged<TokenActionOutcome>? onOutcome = widget.onOutcome;
    final ValueChanged<TokenActionSubmission>? onSubmission =
        widget.onSubmission;
    bool current() =>
        publisher != null &&
        _sameScope(publisher, standard, epoch) &&
        _current &&
        originalCurrent() &&
        epoch == _epoch &&
        modeEpoch == _modeEpoch &&
        mode == _mode;
    if (!current() ||
        proof == null ||
        publisher == null ||
        _confirming ||
        _submitting ||
        _rearming ||
        (_outcome != null && _outcome!.status != TokenActionStatus.refused)) {
      return;
    }
    final Token token = proof.token;
    final BigInt? amount = mode == TokenActionMode.transfer
        ? BigInt.zero
        : parseTokenActionAmount(
            mode == TokenActionMode.mint ? _mintAmount.text : _burnAmount.text,
            token.decimals,
          );
    if (amount == null) return;
    final Object operation = Object();
    _operation = operation;
    bool ownsOperation() =>
        _sameScope(publisher, standard, epoch) &&
        identical(_operation, operation);
    bool authorized() => ownsOperation() && current();
    final TokenActionIntent intent = TokenActionIntent(
      proof: proof,
      mode: mode,
      amount: amount,
      receiver: switch (mode) {
        TokenActionMode.mint => _beneficiary.text,
        TokenActionMode.transfer => _newOwner.text,
        _ => null,
      },
      isCurrent: authorized,
    );
    if (!intent.accepts(proof)) {
      if (ownsOperation()) _operation = null;
      return;
    }
    final TokenActionOutcome? held = publisher.held(intent);
    if (held != null && held.status != TokenActionStatus.refused) {
      _operation = null;
      setState(() => _observeHeld(publisher, standard, epoch));
      return;
    }
    setState(() => _confirming = true);
    bool confirmed = false;
    try {
      confirmed = question != null
          ? await question(intent)
          : await _ask(intent);
    } on Object {
      confirmed = false;
    } finally {
      if (ownsOperation()) _confirming = false;
    }
    if (!confirmed || !authorized() || !intent.isCurrent) {
      if (ownsOperation()) {
        setState(() => _operation = null);
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      if (authorized()) onBusyChanged?.call(true);
    } on Object {
      // Chrome observers cannot replace or duplicate the original request.
    }
    final Future<TokenActionOutcome> publication = publisher.publish(intent);
    try {
      if (authorized()) {
        onSubmission?.call(
          TokenActionSubmission(
            publisher: publisher,
            intent: intent,
            settlement: publication,
          ),
        );
      }
    } on Object {
      // Chrome observation cannot replace the original publication Future.
    }
    _observeHeld(publisher, standard, epoch);
    final TokenActionOutcome outcome = await publication;
    // The original publisher retains it even after this form has been removed.
    if (!authorized()) return;
    try {
      onBusyChanged?.call(false);
    } on Object {
      // The original outcome remains owned by the publication journal.
    }
    if (!authorized()) return;
    if (outcome.belongsTo(intent) &&
        outcome.status == TokenActionStatus.submitted) {
      unawaited(_notify(outcome));
    }
    try {
      if (authorized() && outcome.belongsTo(intent)) {
        onOutcome?.call(outcome);
      }
    } on Object {
      // Convenience observers cannot change the original result.
    }
    if (!authorized()) return;
    setState(() {
      _outcome = outcome;
      _submitting = false;
      _operation = null;
    });
    if (!current()) return;
    if (outcome.status == TokenActionStatus.refused) {
      // Only a new successful proof can rearm a known pre-admission refusal.
      unawaited(_refresh());
    }
  }

  Future<bool> _ask(TokenActionIntent intent) async {
    final Token token = intent.proof.token;
    final TokenActionMode mode = intent.mode;
    final String title = mode == TokenActionMode.burn
        ? context.l10n.burnTokenConfirm(
            cardAmount(intent.amount, token.decimals, token.symbol),
          )
        : mode == TokenActionMode.transfer
        ? context.l10n.transferTokenConfirm(token.symbol)
        : '${context.l10n.mint} '
              '${cardAmount(intent.amount, token.decimals, token.symbol)}';
    final String description = mode == TokenActionMode.transfer
        ? context.l10n.transferTokenConfirmTo(intent.receiver!)
        : mode == TokenActionMode.burn
        ? context.l10n.cannotBeUndone
        : intent.receiver!;
    final String action = _label(mode);
    final String cancel = context.l10n.cancel;
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    late final FrostedDialogRoute<bool> route;
    bool owns() =>
        mounted &&
        navigator.mounted &&
        identical(_questionRoute, route) &&
        identical(route.navigator, navigator) &&
        route.isActive &&
        route.isCurrent;
    void answer({required bool accepted}) {
      if (!owns()) return;
      if (accepted && !intent.isCurrent) {
        _dismissQuestion();
        return;
      }
      navigator.pop(accepted);
    }

    route = FrostedDialogRoute<bool>(
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => themes.wrap(
            SafeArea(
              child: DialogCard(
                title: title,
                body: Text(description),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => answer(accepted: false),
                    style: quietButtonStyle(context),
                    child: Text(cancel),
                  ),
                  OutlinedButton(
                    onPressed: () => answer(accepted: true),
                    child: Text(action),
                  ),
                ],
              ),
            ),
          ),
    );
    _questionRoute = route;
    _questionNavigator = navigator;
    final bool? accepted = await navigator.push<bool>(route);
    if (identical(_questionRoute, route)) {
      _questionRoute = null;
      _questionNavigator = null;
    }
    return accepted ?? false;
  }

  void _dismissQuestion() {
    final FrostedDialogRoute<bool>? route = _questionRoute;
    final NavigatorState? navigator = _questionNavigator;
    _questionRoute = null;
    _questionNavigator = null;
    if (route == null || navigator == null) return;
    scheduleMicrotask(() {
      if (navigator.mounted &&
          identical(route.navigator, navigator) &&
          route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  Widget _buildStatus(TokenActionStatus status) {
    final AppTokens tokens = AppTokens.of(context);
    final String text = switch (status) {
      TokenActionStatus.refused => context.l10n.tokensActionUnavailable,
      TokenActionStatus.submitting => context.l10n.tokensActionSubmitting,
      TokenActionStatus.submitted => context.l10n.tokensActionSubmitted,
      TokenActionStatus.unknown => context.l10n.tokensActionUnknown,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          status == TokenActionStatus.submitted
              ? Icons.check_circle_outline
              : Icons.info_outline,
          size: tokens.activityIconSize,
          color: tokens.dim,
        ),
        SizedBox(width: tokens.inlineGap),
        Flexible(child: Text(text, style: tokens.captionText)),
      ],
    );
  }

  Widget _buildOutcome(TokenActionOutcome original) {
    final int epoch = _epoch;
    final int modeEpoch = _modeEpoch;
    final bool Function() authority = widget.isCurrent;
    bool current() =>
        _current && authority() && epoch == _epoch && modeEpoch == _modeEpoch;
    Widget receipt() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildStatus(original.status),
        if (original.status == TokenActionStatus.submitted)
          TextButton(
            key: const Key('token_action_another'),
            onPressed:
                current() &&
                    !_confirming &&
                    !_submitting &&
                    !_rearming &&
                    (_publisher?.canStartAnother(original) ?? false)
                ? () {
                    if (current()) {
                      unawaited(_another(original, current));
                    }
                  }
                : null,
            child: Text(context.l10n.tokensAnotherAction),
          ),
      ],
    );

    final Listenable? changes = _publisher?.confirmationChanges;
    return changes == null
        ? receipt()
        : ListenableBuilder(listenable: changes, builder: (_, _) => receipt());
  }

  Future<void> _another(
    TokenActionOutcome original,
    bool Function() originalCurrent,
  ) async {
    final TokenActionPublisher? publisher = _publisher;
    final TokenStandard standard = TokenStandard.parse(
      widget.token.tokenStandard.toString(),
    );
    final int epoch = _epoch;
    final int modeEpoch = _modeEpoch;
    final bool Function() authority = widget.isCurrent;
    bool current() =>
        publisher != null &&
        _sameScope(publisher, standard, epoch) &&
        _current &&
        authority() &&
        originalCurrent() &&
        epoch == _epoch &&
        modeEpoch == _modeEpoch;
    if (!current() ||
        publisher == null ||
        original.intent.standard != standard ||
        _rearming) {
      return;
    }
    final Object operation = Object();
    _operation = operation;
    bool authorized() => current() && identical(_operation, operation);
    setState(() => _rearming = true);
    final TokenActionProof? fresh = await publisher.another(
      original,
      isCurrent: authorized,
    );
    if (!authorized()) return;
    if (fresh != null &&
        identical(fresh.session, publisher.session) &&
        fresh.token.tokenStandard == standard) {
      _epoch++;
      _modeEpoch++;
      _read = null;
      _operation = null;
      _heldObservation = null;
      _mintAmount.clear();
      _burnAmount.clear();
      _newOwner.clear();
      _beneficiary.text = fresh.session.address;
      setState(() {
        _proof = fresh;
        _outcome = null;
        _loading = false;
        _rearming = false;
      });
    } else {
      setState(() {
        _rearming = false;
        _operation = null;
      });
    }
  }

  Widget _buildLinks(Token token) {
    final AppTokens tokens = AppTokens.of(context);
    final int epoch = _epoch;
    final bool Function() originalCurrent = widget.isCurrent;
    bool current() => _current && originalCurrent() && epoch == _epoch;
    final bool live = _proof?.isCurrent ?? false;
    final String standard = token.tokenStandard.toString();
    final TokenActionOutcome? outcome = _outcome;
    final Uri? explorer = outcome?.status == TokenActionStatus.submitted
        ? ExplorerLinks.transaction(
            outcome!.publicationHash!,
            chainId: outcome.intent.proof.session.chainId,
          )
        : null;
    return Padding(
      padding: EdgeInsetsDirectional.only(top: tokens.tokenDetailBodyGap),
      child: Wrap(
        spacing: tokens.tokenActionGap,
        runSpacing: tokens.tokenActionGap,
        children: <Widget>[
          TextButton(
            key: const Key('token_send'),
            onPressed: current() && live && widget.onSendToken != null
                ? () {
                    if (current() && (_proof?.isCurrent ?? false)) {
                      widget.onSendToken!(standard);
                    }
                  }
                : null,
            child: Text(context.l10n.send),
          ),
          TextButton.icon(
            key: const Key('token_domain'),
            onPressed: current() && token.domain.isNotEmpty
                ? () {
                    if (current()) {
                      unawaited(NavigationUtils.openUrl(token.domain));
                    }
                  }
                : null,
            icon: const Icon(Icons.open_in_new),
            label: Text(context.l10n.tokensDomain),
          ),
          if (explorer != null)
            IconButton(
              key: const Key('token_publication_explorer'),
              tooltip: context.l10n.activityExplorer,
              icon: const Icon(Icons.open_in_new),
              onPressed: current()
                  ? () {
                      if (current()) {
                        unawaited(NavigationUtils.openUrl(explorer.toString()));
                      }
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _notify(TokenActionOutcome outcome) async {
    final TokenActionIntent intent = outcome.intent;
    final Token token = intent.proof.token;
    // Mint's ABI amount stays separate from the native transfer amount.
    final String amount = (outcome.requestedMintAmount ?? intent.amount)
        .addDecimals(token.decimals);
    final String title = switch (intent.mode) {
      TokenActionMode.mint => context.l10n.successfullyMinted(
        amount,
        token.symbol,
      ),
      TokenActionMode.burn => context.l10n.successfullyBurned(
        amount,
        token.symbol,
      ),
      TokenActionMode.transfer => context.l10n.transferredTokenOwnership(
        token.name,
      ),
      TokenActionMode.flags => '',
    };
    final String details = switch (intent.mode) {
      TokenActionMode.mint => context.l10n.successfullyMintedRequestedAmount(
        amount,
        outcome.publicationHash!,
        token.symbol,
      ),
      TokenActionMode.burn => context.l10n.successfullyBurnedRequestedAmount(
        amount,
        outcome.publicationHash!,
        token.symbol,
      ),
      TokenActionMode.transfer =>
        context.l10n.transferredTokenOwnershipToAddress(
          intent.receiver!,
          token.name,
        ),
      TokenActionMode.flags => '',
    };
    try {
      if (app.sl.isRegistered<NotificationsBloc>()) {
        await app.sl.get<NotificationsBloc>().addNotification(
          WalletNotification(
            title: title,
            details: details,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            type: intent.mode == TokenActionMode.burn
                ? NotificationType.burnToken
                : NotificationType.paymentSent,
          ),
        );
      }
    } on Object {
      // Notification persistence does not own the accepted SDK outcome.
    }
  }

  @override
  void dispose() {
    _epoch++;
    _modeEpoch++;
    _read = null;
    _operation = null;
    _heldObservation = null;
    _dismissQuestion();
    WidgetsBinding.instance.removeObserver(this);
    WalletContextRevision.changes.removeListener(_authorityChanged);
    for (final TextEditingController field in _fields) {
      field
        ..removeListener(_fieldChanged)
        ..dispose();
    }
    super.dispose();
  }
}

class _TokenFacts extends StatelessWidget {
  const _TokenFacts({
    required this.token,
    this.flagsOnly = false,
    this.metadataOnly = false,
  });

  final Token token;
  final bool flagsOnly;
  final bool metadataOnly;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<(String, String)> facts = <(String, String)>[
      if (!flagsOnly)
        (context.l10n.createTokenDecimalsLabel, token.decimals.toString()),
      if (!flagsOnly) (context.l10n.tokensDomain, token.domain),
      if (!metadataOnly)
        (
          context.l10n.mintable,
          token.isMintable
              ? context.l10n.tokensMintableByOwner
              : context.l10n.tokensNo,
        ),
      if (!metadataOnly)
        (
          context.l10n.tokensBurnable,
          token.isBurnable
              ? context.l10n.tokensBurnableByHolder
              : context.l10n.tokensBurnableByOwner,
        ),
      if (!metadataOnly)
        (
          context.l10n.tokensUtility,
          token.isUtility ? context.l10n.tokensYes : context.l10n.tokensNo,
        ),
    ];
    return Wrap(
      spacing: tokens.tokenDetailColumnGap,
      runSpacing: tokens.tokenDetailLabelGap,
      children: <Widget>[
        for (final (String label, String value) in facts)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label.toUpperCase(), style: tokens.ledgerText),
              SizedBox(width: tokens.tokenDetailColumnGap),
              Flexible(
                child: Text(
                  value,
                  style: tokens.compactText.copyWith(
                    fontFamily:
                        label == context.l10n.createTokenDecimalsLabel ||
                            label == context.l10n.tokensDomain
                        ? tokens.monoFontFamily
                        : null,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Every body stays mounted; closing removes input and semantics immediately.
class _TokenModeBody extends StatefulWidget {
  const _TokenModeBody({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_TokenModeBody> createState() => _TokenModeBodyState();
}

class _TokenModeBodyState extends State<_TokenModeBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.visible ? 1 : 0,
    // Mode feedback always uses its declared clock, independent of OS motion.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(_TokenModeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _fade.forward(from: 0);
      } else {
        _fade.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !widget.visible,
    child: TickerMode(
      enabled: widget.visible,
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: IgnorePointer(
            ignoring: !widget.visible,
            child: FadeTransition(opacity: _fade, child: widget.child),
          ),
        ),
      ),
    ),
  );
}
