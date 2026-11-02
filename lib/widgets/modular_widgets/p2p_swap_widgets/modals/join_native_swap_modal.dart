import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _JoinRead {
  _JoinRead(this.initial, this.receiving, this.funds);
  final HtlcInfo initial;
  final Token receiving;
  final SwapFunds funds;
}

/// The real Join flow reads and deposits against one captured initial deposit.
class JoinNativeSwapModal extends StatefulWidget {
  /// Opens exact-deposit lookup and explicit counterdeposit confirmation.
  const JoinNativeSwapModal({
    required this.onJoinedSwap,
    this.source,
    this.sourceIsCurrent,
    this.dollars = swapLiveDollars,
    super.key,
  });

  /// Receives the original swap key only after accepted current-view Join.
  final ValueChanged<String> onJoinedSwap;

  /// Original wallet, chain readers and signer admission capabilities.
  final SwapActionOrigin? source;

  /// Caller guard for the exact original route source.
  final bool Function()? sourceIsCurrent;

  /// Dollar-line renderer with finite injection for offline fixtures.
  final SwapDollarBuilder dollars;
  @override
  State<JoinNativeSwapModal> createState() => _JoinNativeSwapModalState();
}

class _JoinNativeSwapModalState extends State<JoinNativeSwapModal>
    with CapturedSwapModal<JoinNativeSwapModal> {
  @override
  SwapActionOrigin? get providedOrigin => widget.source;
  @override
  bool Function()? get providedIsCurrent => widget.sourceIsCurrent;
  final TextEditingController _id = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  late final ValueChanged<String> _onOpened;
  _JoinRead? _deposit;
  Future<_JoinRead>? _read;
  Token _from = kZnnCoin;
  bool _reading = false;
  bool _readFailed = false;

  @override
  void initState() {
    super.initState();
    _onOpened = widget.onJoinedSwap;
  }

  bool _editable(SwapViewLease lease) =>
      owns(lease) && !busy && !held && !_reading;
  List<Token> get _choices => <String, Token>{
    kZnnCoin.tokenStandard.toString(): kZnnCoin,
    kQsrCoin.tokenStandard.toString(): kQsrCoin,
    for (final Token token in _deposit?.funds.tokens ?? <Token>[])
      token.tokenStandard.toString(): token,
  }.values.toList(growable: false);
  BigInt? get _parsed => swapAmount(_amount.text, _from.decimals);
  bool get _funded =>
      _deposit != null &&
      _parsed != null &&
      _parsed! > BigInt.zero &&
      _deposit!.funds.balance(_from) >= _parsed!;

  Future<_JoinRead> _readDeposit(SwapActionOrigin original, Hash id) async {
    final HtlcInfo initial = HtlcInfo.fromJson(
      (await SwapActions.initial(original, id)).toJson(),
    );
    original.requireCurrent();
    final Token? token = await original.readToken(
      initial.tokenStandard.toString(),
    );
    original.requireCurrent();
    if (token == null ||
        token.tokenStandard != initial.tokenStandard ||
        token.decimals < 0 ||
        token.decimals > 255) {
      throw const SwapActionRefused('token');
    }
    final SwapFunds funds = await SwapFunds.read(
      original,
      initial.hashLocked.toString(),
    );
    original.requireCurrent();
    return _JoinRead(initial, Token.fromJson(token.toJson()), funds);
  }

  Future<void> _find(SwapViewLease lease) async {
    final Hash? id = swapDepositId(_id.text);
    if (!_editable(lease) || id == null || origin == null) return;
    final SwapActionOrigin original = origin!;
    final String input = _id.text;
    setState(() {
      _reading = true;
      _readFailed = false;
    });
    final Future<_JoinRead> read = _readDeposit(original, id);
    _read = read;
    try {
      final _JoinRead deposit = await read;
      if (!owns(lease) || !identical(_read, read) || _id.text != input) return;
      setState(() {
        _deposit = deposit;
        _from = _choices.firstWhere(
          (Token token) => token.tokenStandard == _from.tokenStandard,
        );
        epoch = Object();
      });
    } on Object {
      if (owns(lease) && identical(_read, read)) {
        setState(() => _readFailed = true);
      }
    } finally {
      if (mounted && identical(_read, read)) setState(() => _reading = false);
    }
  }

  Future<void> _join(SwapViewLease lease) async {
    final _JoinRead? deposit = _deposit;
    if (!_editable(lease) || deposit == null || !_funded || origin == null) {
      return;
    }
    final SwapActionOrigin original = origin!;
    final HtlcInfo initial = HtlcInfo.fromJson(deposit.initial.toJson());
    final Token from = Token.fromJson(_from.toJson());
    final Token to = Token.fromJson(deposit.receiving.toJson());
    final BigInt amount = _parsed!;
    await submit(
      lease,
      () => SwapActions.join(
        original,
        initialDeposit: initial,
        fromToken: from,
        toToken: to,
        amount: amount,
      ),
    );
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
        title: context.l10n.swapListJoin,
        marker: const Key('swap_join_screen_marker'),
        onClose: close(lease),
        notice: resultNotice(context),
        child: const SizedBox.shrink(),
      );
    }
    final bool current = owns(lease);
    final bool editable = _editable(lease);
    final _JoinRead? deposit = _deposit;
    final Widget? notice =
        resultNotice(context) ??
        (_readFailed
            ? SwapNotice(context.l10n.swapActionReadFailed, error: true)
            : null);
    if (deposit == null) {
      return SwapDialogSurface(
        title: context.l10n.swapListJoin,
        marker: const Key('swap_join_screen_marker'),
        onClose: close(lease),
        notice: notice,
        primary: SwapPrimaryAction(
          key: const Key('swap_find_deposit'),
          label: _reading
              ? context.l10n.swapActionSearching
              : swapDepositId(_id.text) == null
              ? context.l10n.swapActionEnterDepositId
              : context.l10n.swapActionFindDeposit,
          busy: _reading,
          onPressed: !editable || swapDepositId(_id.text) == null
              ? null
              : () => unawaited(_find(lease)),
        ),
        child: SwapTextEntry(
          controller: _id,
          fieldKey: const Key('swap_deposit_id_input'),
          label: context.l10n.swapListDepositId,
          onChanged: !editable
              ? null
              : (_) => change(lease, () => _readFailed = false),
          onSubmitted: !editable ? null : (_) => unawaited(_find(lease)),
          onPaste: !editable ? null : () => unawaited(paste(lease, _id)),
        ),
      );
    }
    final SwapActionResult? result = shownResult;
    final String? exactId = result?.status == SwapActionStatus.submitted
        ? result?.swap?.id
        : null;
    final String label = busy
        ? context.l10n.swapActionSending
        : result?.status == SwapActionStatus.unknown
        ? context.l10n.swapActionChainPending
        : _parsed == null || _parsed! <= BigInt.zero
        ? context.l10n.swapActionEnterAmount
        : !_funded
        ? context.l10n.swapActionNotEnough
        : context.l10n.swapListJoin;
    return SwapTransferSurface(
      title: context.l10n.swapListJoin,
      marker: const Key('swap_join_screen_marker'),
      onClose: close(lease),
      notice: notice,
      send: SwapAmountPane(
        label: context.l10n.swapListYouSend,
        token: _from,
        controller: _amount,
        visible: current,
        hideBalances: hidden,
        balance: deposit.funds.balance(_from),
        choices: _choices,
        dollars: widget.dollars,
        canInteract: () => _editable(lease),
        onChanged: !editable ? null : (_) => change(lease, () {}),
        onToken: !editable
            ? null
            : (String standard) => change(lease, () {
                _from = _choices.firstWhere(
                  (Token token) => token.tokenStandard.toString() == standard,
                );
              }),
        onMax: !editable
            ? null
            : () => change(lease, () {
                _amount.text = swapAmountInput(
                  deposit.funds.balance(_from),
                  _from.decimals,
                );
              }),
      ),
      receive: SwapAmountPane(
        label: context.l10n.swapListYouReceive,
        token: deposit.receiving,
        amount: deposit.initial.amount,
        visible: current,
        hideBalances: hidden,
        dollars: widget.dollars,
        party: SwapIdentifier(deposit.initial.hashLocked.toString()),
      ),
      counterparty: SwapIdentifier(deposit.initial.timeLocked.toString()),
      rate: SwapRate(
        fromAmount: _parsed,
        fromToken: _from,
        toAmount: deposit.initial.amount,
        toToken: deposit.receiving,
      ),
      timing: context.l10n.swapActionTiming(
        kInitialHtlcDuration.inHours,
        kCounterHtlcDuration.inHours,
      ),
      primary: SwapPrimaryAction(
        key: const Key('swap_join_deposit'),
        label: exactId == null ? label : context.l10n.swapListOpen,
        busy: busy,
        onPressed: !current || busy
            ? null
            : exactId != null
            ? () {
                if (owns(lease) && identical(shownResult, result)) {
                  _onOpened(exactId);
                }
              }
            : !editable || !_funded
            ? null
            : () => unawaited(_join(lease)),
      ),
      details: SwapActionDetails(
        summary: context.l10n.swapActionDepositVerified,
        onToggle: () => !_reading && toggleDetails(lease),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwapFactRow(
              label: context.l10n.swapListYourAddress,
              value: SwapIdentifier(deposit.initial.hashLocked.toString()),
            ),
            SwapFactRow(
              label: context.l10n.swapListDepositId,
              value: SwapIdentifier(deposit.initial.id.toString()),
            ),
            SwapFactRow(
              label: context.l10n.swapListTokenStandard,
              value: SwapIdentifier(deposit.receiving.tokenStandard.toString()),
            ),
            Text(
              context.l10n.swapActionDiscovery(
                kMinSafeTimeToFindPreimage.inHours,
                kMinSafeTimeToCompleteSwap.inMinutes,
              ),
              style: tokens.captionText,
            ),
            if (!held)
              TextButton(
                key: const Key('swap_change_deposit'),
                onPressed: !editable
                    ? null
                    : () => change(lease, () {
                        _deposit = null;
                        _amount.clear();
                      }),
                child: Text(context.l10n.swapActionFindDeposit),
              ),
          ],
        ),
      ),
    );
  });

  @override
  void dispose() {
    _id.dispose();
    _amount.dispose();
    super.dispose();
  }
}
