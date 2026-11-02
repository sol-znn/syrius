import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The quoted offer is gated; the existing one-sided deposit stays explicit.
class StartNativeSwapModal extends StatefulWidget {
  /// Opens the explicit one-sided native deposit flow on a captured wallet.
  const StartNativeSwapModal({
    required this.onSwapStarted,
    this.source,
    this.sourceIsCurrent,
    this.dollars = swapLiveDollars,
    super.key,
  });

  /// Receives the exact accepted deposit identifier only on a current view.
  final ValueChanged<String> onSwapStarted;

  /// Original wallet and chain capabilities, captured before route opening.
  final SwapActionOrigin? source;

  /// Caller guard for original list resources retained across route awaits.
  final bool Function()? sourceIsCurrent;

  /// Dollar-line rendering capability; finite fixtures may replace price reads.
  final SwapDollarBuilder dollars;
  @override
  State<StartNativeSwapModal> createState() => _StartNativeSwapModalState();
}

class _StartNativeSwapModalState extends State<StartNativeSwapModal>
    with CapturedSwapModal<StartNativeSwapModal> {
  @override
  SwapActionOrigin? get providedOrigin => widget.source;
  @override
  bool Function()? get providedIsCurrent => widget.sourceIsCurrent;
  final TextEditingController _counterparty = TextEditingController();
  final TextEditingController _send = TextEditingController();
  final TextEditingController _receive = TextEditingController();
  late String? _signer = origin?.ownerAddress;
  Token _from = kZnnCoin;
  Token _to = kQsrCoin;
  SwapFunds? _funds;
  Future<SwapFunds>? _fundsFuture;
  Future<bool>? _release;
  bool _fundsAttempted = false;
  bool _reading = false;
  bool _readFailed = false;
  bool _releaseFailed = false;
  String? _submittedSigner;
  late final ValueChanged<String> _onOpened;

  @override
  void initState() {
    super.initState();
    _onOpened = widget.onSwapStarted;
  }

  bool _editable(SwapViewLease lease) =>
      owns(lease) && !busy && !held && !_reading;

  Future<void> _load(SwapViewLease lease, String signer) async {
    if (!owns(lease) || busy || held || _reading || origin == null) return;
    setState(() {
      _reading = true;
      _readFailed = false;
    });
    final Future<SwapFunds> original = SwapFunds.read(origin!, signer);
    _fundsFuture = original;
    try {
      final SwapFunds funds = await original;
      if (!owns(lease) ||
          !identical(_fundsFuture, original) ||
          _signer != signer) {
        return;
      }
      setState(() {
        _funds = funds;
        final List<Token> choices = _choices;
        _from = choices.firstWhere(
          (Token token) => token.tokenStandard == _from.tokenStandard,
          orElse: () => choices.first,
        );
        epoch = Object();
      });
    } on Object {
      if (owns(lease) && identical(_fundsFuture, original)) {
        setState(() => _readFailed = true);
      }
    } finally {
      if (mounted && identical(_fundsFuture, original)) {
        setState(() => _reading = false);
      }
    }
  }

  List<Token> get _choices {
    final Map<String, Token> tokens = <String, Token>{
      kZnnCoin.tokenStandard.toString(): kZnnCoin,
      kQsrCoin.tokenStandard.toString(): kQsrCoin,
      for (final Token token in _funds?.tokens ?? <Token>[])
        token.tokenStandard.toString(): token,
    };
    return List<Token>.unmodifiable(tokens.values);
  }

  bool get _validAddress =>
      origin != null && swapCounterparty(_counterparty.text, origin!.members);
  BigInt? get _amount => swapAmount(_send.text, _from.decimals);
  bool get _funded =>
      _funds != null &&
      _signer != null &&
      _funds!.address == _signer &&
      _amount != null &&
      _amount! > BigInt.zero &&
      _funds!.balance(_from) >= _amount!;

  Future<void> _createDeposit(SwapViewLease lease) async {
    if (!_editable(lease) || !_validAddress || !_funded) return;
    final SwapActionOrigin original = origin!;
    final String signer = _signer!;
    final String counterparty = _counterparty.text;
    final Token from = Token.fromJson(_from.toJson());
    final BigInt amount = _amount!;
    _submittedSigner = signer;
    // The receive draft is deliberately absent from this real legacy call.
    await submit(
      lease,
      () => SwapActions.start(
        original,
        selfAddress: signer,
        counterparty: counterparty,
        fromToken: from,
        amount: amount,
        hashType: htlcHashTypeSha3,
      ),
    );
  }

  Future<void> _newDeposit(SwapViewLease lease) async {
    final String? signer = _submittedSigner;
    final SwapActionResult? result = shownResult;
    if (!owns(lease) ||
        busy ||
        signer == null ||
        origin == null ||
        result?.status != SwapActionStatus.submitted) {
      return;
    }
    setState(() {
      busy = true;
      _releaseFailed = false;
    });
    final Future<bool> original = SwapActions.releaseConfirmedStart(
      origin!,
      signer,
    );
    _release = original;
    bool released = false;
    try {
      released = await original;
    } on Object {
      /* Retain the original submission. */
    }
    if (!mounted || !identical(_release, original)) return;
    final bool current = owns(lease);
    setState(() {
      busy = false;
      if (current && released && identical(shownResult, result)) {
        shownResult = null;
        activeRun = null;
        _submittedSigner = null;
        _send.clear();
        _receive.clear();
        epoch = Object();
      } else if (current) {
        _releaseFailed = true;
      }
    });
  }

  Future<void> _offer(SwapViewLease lease) async {
    if (!owns(lease) || busy || held) return;
    try {
      await const UnbuiltSwapTermsService().start();
    } on SeamNotBuilt {
      /* The typed direct path refuses the same missing terms. */
    }
  }

  @override
  Widget build(BuildContext context) => captured((
    BuildContext context,
    SwapViewLease lease, {
    required bool hidden,
  }) {
    final AppTokens tokens = AppTokens.of(context);
    if (!sourceCurrent) {
      return SwapDialogSurface(
        title: context.l10n.swapListStart,
        marker: const Key('swap_start_screen_marker'),
        onClose: close(lease),
        notice: resultNotice(context),
        child: const SizedBox.shrink(),
      );
    }
    final bool current = owns(lease);
    final bool editable = _editable(lease);
    if (current && !_fundsAttempted && _signer != null) {
      _fundsAttempted = true;
      final String signer = _signer!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (owns(lease) && _signer == signer) unawaited(_load(lease, signer));
      });
    }
    final String label = !_validAddress
        ? context.l10n.swapActionEnterAddress
        : _amount == null || _amount! <= BigInt.zero
        ? context.l10n.swapActionEnterAmount
        : !_funded
        ? context.l10n.swapActionNotEnough
        : context.l10n.swapActionCreateDeposit;
    final SwapActionResult? result = shownResult;
    final String? exactId = result?.status == SwapActionStatus.submitted
        ? result?.swap?.id
        : null;
    final Widget primary = exactId == null
        ? SeamGate(
            seam: Seam.swapTerms,
            child: SwapPrimaryAction(
              label: context.l10n.swapListStart,
              onPressed: () => unawaited(_offer(lease)),
            ),
          )
        : SwapPrimaryAction(
            label: context.l10n.swapListOpen,
            onPressed: !current || busy
                ? null
                : () {
                    if (owns(lease) && identical(shownResult, result)) {
                      _onOpened(exactId);
                    }
                  },
          );
    return SwapTransferSurface(
      title: context.l10n.swapListStart,
      marker: const Key('swap_start_screen_marker'),
      onClose: close(lease),
      send: SwapAmountPane(
        label: context.l10n.swapListYouSend,
        token: _from,
        controller: _send,
        visible: current,
        balance: _funds?.balance(_from),
        hideBalances: hidden,
        dollars: widget.dollars,
        choices: _choices,
        canInteract: () => _editable(lease),
        onChanged: !editable ? null : (_) => change(lease, () {}),
        onToken: !editable
            ? null
            : (String standard) => change(lease, () {
                _from = _choices.firstWhere(
                  (Token token) => token.tokenStandard.toString() == standard,
                );
              }),
        onMax: !editable || _funds == null
            ? null
            : () => change(lease, () {
                _send.text = swapAmountInput(
                  _funds!.balance(_from),
                  _from.decimals,
                );
              }),
      ),
      receive: SwapAmountPane(
        label: context.l10n.swapListYouReceive,
        token: _to,
        controller: _receive,
        visible: current,
        hideBalances: hidden,
        dollars: widget.dollars,
        choices: _choices,
        canInteract: () => _editable(lease),
        onChanged: !editable ? null : (_) => change(lease, () {}),
        onToken: !editable
            ? null
            : (String standard) => change(lease, () {
                _to = _choices.firstWhere(
                  (Token token) => token.tokenStandard.toString() == standard,
                );
              }),
      ),
      counterparty: SwapTextEntry(
        controller: _counterparty,
        fieldKey: const Key('swap_counterparty_input'),
        label: context.l10n.swapActionEnterAddress,
        onChanged: !editable ? null : (_) => change(lease, () {}),
        onPaste: !editable
            ? null
            : () => unawaited(paste(lease, _counterparty)),
      ),
      rate: SwapRate(
        fromAmount: _amount,
        fromToken: _from,
        toAmount: swapAmount(_receive.text, _to.decimals),
        toToken: _to,
      ),
      timing: context.l10n.swapActionTiming(
        kInitialHtlcDuration.inHours,
        kCounterHtlcDuration.inHours,
      ),
      primary: primary,
      notice: _releaseFailed
          ? SwapNotice(context.l10n.swapActionChainPending, waiting: true)
          : resultNotice(context) ??
                (_readFailed
                    ? SwapNotice(context.l10n.swapActionReadFailed, error: true)
                    : null),
      details: SwapActionDetails(
        summary: context.l10n.swapActionDepositOnly,
        onToggle: () => !_reading && toggleDetails(lease),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_signer != null)
              SwapChoice(
                label: context.l10n.swapListYourAddress,
                value: _signer!,
                choices: <String, Widget>{
                  for (final String address in origin!.members)
                    address: SwapIdentifier(address),
                },
                canInteract: () => _editable(lease),
                onSelected: !editable
                    ? null
                    : (String address) {
                        change(lease, () {
                          _signer = address;
                          _funds = null;
                          _send.clear();
                          _fundsAttempted = false;
                        });
                      },
              ),
            Text(
              context.l10n.swapActionDiscovery(
                kMinSafeTimeToFindPreimage.inHours,
                kMinSafeTimeToCompleteSwap.inMinutes,
              ),
              style: tokens.captionText,
            ),
            SizedBox(height: tokens.swapActionGap),
            if (result?.status == SwapActionStatus.submitted)
              OutlinedButton(
                key: const Key('swap_new_deposit'),
                onPressed: !current || busy
                    ? null
                    : () => unawaited(_newDeposit(lease)),
                child: Text(context.l10n.swapActionNewDeposit),
              )
            else if (result?.status != SwapActionStatus.unknown)
              OutlinedButton(
                key: const Key('swap_create_deposit'),
                onPressed: !editable || !_validAddress || !_funded
                    ? null
                    : () => unawaited(_createDeposit(lease)),
                child: Text(busy ? context.l10n.swapActionSending : label),
              ),
            if (!held)
              TextButton(
                key: const Key('swap_refresh_funds'),
                onPressed: !current || busy || _reading || _signer == null
                    ? null
                    : () => unawaited(_load(lease, _signer!)),
                child: Text(context.l10n.swapListRefresh),
              ),
          ],
        ),
      ),
    );
  });

  @override
  void dispose() {
    _counterparty.dispose();
    _send.dispose();
    _receive.dispose();
    super.dispose();
  }
}
