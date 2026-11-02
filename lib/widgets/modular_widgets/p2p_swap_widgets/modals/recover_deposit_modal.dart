import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Recovery reclaims only an exact proven expired original-wallet deposit.
class RecoverDepositModal extends StatefulWidget {
  /// Opens exact owned-deposit recovery with no automatic publication.
  const RecoverDepositModal({
    this.source,
    this.sourceIsCurrent,
    this.dollars = swapLiveDollars,
    super.key,
  });

  /// Original member signers, encrypted store and chain readers.
  final SwapActionOrigin? source;

  /// Caller-owned guard retained throughout lookup and confirmation.
  final bool Function()? sourceIsCurrent;

  /// Dollar-line renderer; absent price facts never alter reclaim proof.
  final SwapDollarBuilder dollars;
  @override
  State<RecoverDepositModal> createState() => _RecoverDepositModalState();
}

class _RecoverDepositModalState extends State<RecoverDepositModal>
    with CapturedSwapModal<RecoverDepositModal> {
  @override
  SwapActionOrigin? get providedOrigin => widget.source;
  @override
  bool Function()? get providedIsCurrent => widget.sourceIsCurrent;
  final TextEditingController _id = TextEditingController();
  SwapDepositFact? _deposit;
  Future<SwapDepositFact>? _read;
  bool _reading = false;
  bool _readFailed = false;

  Future<void> _find(SwapViewLease lease) async {
    final Hash? id = swapDepositId(_id.text);
    if (!owns(lease) ||
        busy ||
        held ||
        _reading ||
        id == null ||
        origin == null) {
      return;
    }
    final SwapActionOrigin original = origin!;
    final String input = _id.text;
    setState(() {
      _reading = true;
      _readFailed = false;
      _deposit = null;
    });
    final Future<SwapDepositFact> read = SwapDepositFact.read(original, id);
    _read = read;
    try {
      final SwapDepositFact deposit = await read;
      if (!owns(lease) || !identical(_read, read) || _id.text != input) return;
      if (!original.members.contains(deposit.sender)) {
        throw const SwapActionRefused('signer');
      }
      setState(() {
        _deposit = deposit;
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

  Future<void> _reclaim(SwapViewLease lease, SwapDepositFact deposit) async {
    if (!owns(lease) ||
        busy ||
        held ||
        _reading ||
        !identical(_deposit, deposit) ||
        !deposit.expired ||
        origin == null ||
        !origin!.members.contains(deposit.sender)) {
      return;
    }
    final SwapActionOrigin original = origin!;
    final Hash id = Hash.parse(deposit.id);
    final String signer = deposit.sender;
    await submit(lease, () => SwapActions.reclaim(original, id, signer));
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
        title: context.l10n.swapListRecover,
        marker: const Key('swap_recover_screen_marker'),
        onClose: close(lease),
        notice: resultNotice(context),
        child: const SizedBox.shrink(),
      );
    }
    final bool current = owns(lease);
    final bool editable = current && !busy && !held && !_reading;
    final SwapDepositFact? deposit = _deposit;
    final Widget? notice = shownResult?.status == SwapActionStatus.submitted
        ? SwapNotice(context.l10n.swapActionReclaimSubmitted, waiting: true)
        : resultNotice(context) ??
              (_readFailed
                  ? SwapNotice(context.l10n.swapActionReadFailed, error: true)
                  : null);
    return SwapDialogSurface(
      title: context.l10n.swapListRecover,
      marker: const Key('swap_recover_screen_marker'),
      onClose: close(lease),
      notice: notice,
      primary: SwapPrimaryAction(
        key: const Key('swap_recover_action'),
        label: busy
            ? context.l10n.swapActionSending
            : _reading
            ? context.l10n.swapActionSearching
            : deposit == null
            ? swapDepositId(_id.text) == null
                  ? context.l10n.swapActionEnterDepositId
                  : context.l10n.swapActionFindDeposit
            : context.l10n.swapListReclaim,
        busy: busy || _reading,
        onPressed: !editable
            ? null
            : deposit == null
            ? swapDepositId(_id.text) == null
                  ? null
                  : () => unawaited(_find(lease))
            : !deposit.expired
            ? null
            : () => unawaited(_reclaim(lease, deposit)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwapTextEntry(
            controller: _id,
            fieldKey: const Key('swap_deposit_id_input'),
            label: context.l10n.swapListDepositId,
            onChanged: !editable
                ? null
                : (_) => change(lease, () {
                    _deposit = null;
                    _readFailed = false;
                  }),
            onSubmitted: !editable ? null : (_) => unawaited(_find(lease)),
            onPaste: !editable ? null : () => unawaited(paste(lease, _id)),
          ),
          if (deposit != null) ...<Widget>[
            SizedBox(height: tokens.swapActionGap),
            SwapAmountPane(
              label: context.l10n.deposit,
              token: deposit.token,
              amount: deposit.amount,
              visible: current,
              hideBalances: hidden,
              dollars: widget.dollars,
            ),
            SizedBox(height: tokens.swapActionGap),
            SwapNotice(
              deposit.expired
                  ? context.l10n.swapActionCanReclaim
                  : context.l10n.swapActionDepositLive,
            ),
            SizedBox(height: tokens.swapActionGap),
            SwapActionDetails(
              summary: context.l10n.swapActionDepositVerified,
              onToggle: () => !_reading && toggleDetails(lease),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SwapFactRow(
                    label: context.l10n.swapListSender,
                    value: SwapIdentifier(deposit.sender),
                  ),
                  SwapFactRow(
                    label: context.l10n.swapListRecipient,
                    value: SwapIdentifier(deposit.recipient),
                  ),
                  SwapFactRow(
                    label: context.l10n.swapListTokenStandard,
                    value: SwapIdentifier(
                      deposit.token.tokenStandard.toString(),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!held)
            TextButton(
              key: const Key('swap_recover_refresh'),
              onPressed: !editable || swapDepositId(_id.text) == null
                  ? null
                  : () => unawaited(_find(lease)),
              child: Text(context.l10n.swapActionFreshDetails),
            ),
        ],
      ),
    );
  });

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }
}
