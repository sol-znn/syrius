import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Recorded terms and current positive deposits remain separate facts.
class NativeP2pSwapModal extends StatefulWidget {
  /// Opens exact original history and independently refreshed public deposits.
  const NativeP2pSwapModal({
    required this.swapId,
    this.onSwapStarted,
    this.source,
    this.sourceIsCurrent,
    this.dollars = swapLiveDollars,
    super.key,
  });

  /// Exact original key; changing it cannot retarget this mounted view.
  final String swapId;

  /// Legacy accepted-start callback retained for constructor compatibility.
  final ValueChanged<String>? onSwapStarted;

  /// Original wallet and chain capabilities retained by this route.
  final SwapActionOrigin? source;

  /// Caller-owned exact-row or catalogue guard.
  final bool Function()? sourceIsCurrent;

  /// Dollar-line renderer, independent of financial-action authority.
  final SwapDollarBuilder dollars;
  @override
  State<NativeP2pSwapModal> createState() => _NativeP2pSwapModalState();
}

enum _DetailAction { unlock, reclaim }

class _NativeP2pSwapModalState extends State<NativeP2pSwapModal>
    with CapturedSwapModal<NativeP2pSwapModal> {
  @override
  SwapActionOrigin? get providedOrigin => widget.source;
  @override
  bool Function()? get providedIsCurrent => widget.sourceIsCurrent;
  late final String _originalId;
  SwapDetailRead? _details;
  Future<SwapDetailRead>? _read;
  bool _attempted = false;
  bool _reading = false;
  bool _readFailed = false;
  bool _checkedAmounts = false;
  _DetailAction? _action;

  @override
  void initState() {
    super.initState();
    _originalId = widget.swapId;
  }

  bool _owns(SwapViewLease lease) =>
      owns(lease) && widget.swapId == _originalId;

  Future<void> _refresh(SwapViewLease lease) async {
    if (!_owns(lease) || busy || _reading || origin == null) return;
    final SwapActionOrigin original = origin!;
    final String id = _originalId;
    setState(() {
      _reading = true;
      _readFailed = false;
      _checkedAmounts = false;
    });
    final Future<SwapDetailRead> read = SwapDetailRead.read(original, id);
    _read = read;
    try {
      final SwapDetailRead details = await read;
      if (!_owns(lease) || !identical(_read, read)) return;
      setState(() {
        _details = details;
        epoch = Object();
      });
    } on Object {
      if (_owns(lease) && identical(_read, read)) {
        setState(() {
          _details = null;
          _readFailed = true;
          epoch = Object();
        });
      }
    } finally {
      if (mounted && identical(_read, read)) setState(() => _reading = false);
    }
  }

  bool _canUnlock(SwapDetailRead details) =>
      details.ownMatches &&
      details.otherMatches &&
      !details.own!.expired &&
      details.original.preimage != null &&
      details.other!.expires - details.other!.chainTime >
          kMinSafeTimeToCompleteSwap.inSeconds;
  bool _canReclaim(SwapDetailRead details) =>
      details.ownMatches && details.own!.expired;

  Future<void> _unlock(SwapViewLease lease, SwapDetailRead details) async {
    if (!_owns(lease) ||
        busy ||
        held ||
        _reading ||
        !_checkedAmounts ||
        !identical(_details, details) ||
        !_canUnlock(details) ||
        origin == null) {
      return;
    }
    final SwapActionOrigin original = origin!;
    final HtlcSwap exact = HtlcSwap.fromJson(details.original.toJson());
    _action = _DetailAction.unlock;
    await submit(lease, () => SwapActions.complete(original, exact));
  }

  Future<void> _reclaim(SwapViewLease lease, SwapDetailRead details) async {
    if (!_owns(lease) ||
        busy ||
        held ||
        _reading ||
        !identical(_details, details) ||
        !_canReclaim(details) ||
        origin == null) {
      return;
    }
    final SwapActionOrigin original = origin!;
    final Hash id = Hash.parse(details.own!.id);
    final String signer = details.original.selfAddress;
    _action = _DetailAction.reclaim;
    await submit(lease, () => SwapActions.reclaim(original, id, signer));
  }

  @override
  Widget build(BuildContext context) => captured((
    BuildContext context,
    SwapViewLease lease, {
    required bool hidden,
  }) {
    final AppTokens tokens = AppTokens.of(context);
    if (!sourceCurrent || widget.swapId != _originalId) {
      return SwapDialogSurface(
        title: context.l10n.swapActionTitle,
        marker: const Key('swap_detail_screen_marker'),
        onClose: close(lease),
        notice: SwapNotice(context.l10n.swapListSourceChanged, error: true),
        child: const SizedBox.shrink(),
      );
    }
    final bool current = _owns(lease);
    if (current && !_attempted) {
      _attempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_owns(lease)) unawaited(_refresh(lease));
      });
    }
    final SwapDetailRead? details = _details;
    final SwapDepositFact? own = details?.ownMatches == true
        ? details?.own
        : null;
    final SwapDepositFact? other = details?.other;
    final Widget? notice = !current
        ? resultNotice(context)
        : shownResult?.status == SwapActionStatus.submitted
        ? SwapNotice(
            _action == _DetailAction.unlock
                ? context.l10n.swapActionUnlockSubmitted
                : context.l10n.swapActionReclaimSubmitted,
            waiting: true,
          )
        : resultNotice(context) ??
              (_readFailed || (other != null && details?.otherMatches != true)
                  ? SwapNotice(context.l10n.swapActionReadFailed, error: true)
                  : own == null
                  ? SwapNotice(
                      context.l10n.swapActionChainPending,
                      waiting: true,
                    )
                  : SwapNotice(
                      own.expired
                          ? context.l10n.swapActionCanReclaim
                          : context.l10n.swapActionDepositLive,
                      waiting: !own.expired,
                    ));
    final bool reclaim = details != null && _canReclaim(details);
    final bool unlock = details != null && _canUnlock(details);
    return SwapDialogSurface(
      title: context.l10n.swapActionTitle,
      marker: const Key('swap_detail_screen_marker'),
      onClose: close(lease),
      notice: notice,
      primary: !reclaim && !unlock
          ? null
          : SwapPrimaryAction(
              key: const Key('swap_detail_action'),
              label: busy
                  ? context.l10n.swapActionSending
                  : reclaim
                  ? context.l10n.swapListReclaim
                  : context.l10n.swapActionUnlock,
              busy: busy,
              onPressed:
                  !current ||
                      busy ||
                      held ||
                      _reading ||
                      (!reclaim && !_checkedAmounts)
                  ? null
                  : reclaim
                  ? () => unawaited(_reclaim(lease, details))
                  : () => unawaited(_unlock(lease, details)),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (details != null) ...<Widget>[
            SwapTransferPanes(
              send: SwapAmountPane(
                label: context.l10n.swapListYouSend,
                token: own?.token ?? details.sending,
                amount: own?.amount ?? details.original.fromAmount,
                visible: current,
                hideBalances: hidden,
                dollars: widget.dollars,
                party: Text(
                  own == null
                      ? context.l10n.swapActionRecorded
                      : context.l10n.swapActionDepositVerified,
                  style: tokens.captionText,
                ),
              ),
              receive: other != null
                  ? SwapAmountPane(
                      label: context.l10n.swapListYouReceive,
                      token: other.token,
                      amount: other.amount,
                      visible: current,
                      hideBalances: hidden,
                      dollars: widget.dollars,
                      party: Text(
                        context.l10n.swapActionDepositVerified,
                        style: tokens.captionText,
                      ),
                    )
                  : details.receiving == null
                  ? SwapUnknownPane(label: context.l10n.swapListYouReceive)
                  : SwapAmountPane(
                      label: context.l10n.swapListYouReceive,
                      token: details.receiving!,
                      amount: details.original.toAmount,
                      visible: current,
                      hideBalances: hidden,
                      dollars: widget.dollars,
                      party: Text(
                        context.l10n.swapActionRecorded,
                        style: tokens.captionText,
                      ),
                    ),
            ),
            SizedBox(height: tokens.swapActionGap),
            SwapFactRow(
              label: context.l10n.swapListCounterparty,
              value: SwapIdentifier(details.original.counterpartyAddress),
            ),
            if (other != null)
              SwapFactRow(
                label: context.l10n.swapListRate,
                value: SwapRate(
                  fromAmount: own?.amount ?? details.original.fromAmount,
                  fromToken: own?.token ?? details.sending,
                  toAmount: other.amount,
                  toToken: other.token,
                ),
              ),
            if (unlock)
              CheckboxListTile(
                key: const Key('swap_check_amounts'),
                value: _checkedAmounts,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  context.l10n.swapActionConfirmAmount,
                  style: tokens.transferCaptionText,
                ),
                onChanged: !current || busy || held || _reading
                    ? null
                    : (bool? value) =>
                          change(lease, () => _checkedAmounts = value == true),
              ),
            SwapActionDetails(
              summary: context.l10n.swapActionRecorded,
              onToggle: () => _owns(lease) && !_reading && toggleDetails(lease),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SwapFactRow(
                    label: context.l10n.swapListYourAddress,
                    value: SwapIdentifier(details.original.selfAddress),
                  ),
                  SwapFactRow(
                    label: context.l10n.swapListInitialDepositId,
                    value: SwapIdentifier(details.original.initialHtlcId),
                  ),
                  OutlinedButton.icon(
                    key: const Key('p2p_copy_deposit_id'),
                    onPressed: !current
                        ? null
                        : () => unawaited(
                            copy(lease, details.original.initialHtlcId),
                          ),
                    icon: Icon(
                      Icons.copy_outlined,
                      size: tokens.swapActionTokenIconSize,
                    ),
                    label: Text(context.l10n.swapListCopyForThem),
                  ),
                  if (details.original.counterHtlcId != null)
                    SwapFactRow(
                      label: context.l10n.swapListCounterpartyDepositId,
                      value: SwapIdentifier(details.original.counterHtlcId!),
                    ),
                  SwapFactRow(
                    label: context.l10n.swapListTokenStandard,
                    value: SwapIdentifier(
                      details.sending.tokenStandard.toString(),
                    ),
                  ),
                  if (other != null)
                    SwapFactRow(
                      label: context.l10n.swapListTokenStandard,
                      value: SwapIdentifier(
                        other.token.tokenStandard.toString(),
                      ),
                    ),
                  Text(
                    context.l10n.swapActionTiming(
                      kInitialHtlcDuration.inHours,
                      kCounterHtlcDuration.inHours,
                    ),
                    style: tokens.captionText,
                  ),
                  Text(
                    context.l10n.swapActionDiscovery(
                      kMinSafeTimeToFindPreimage.inHours,
                      kMinSafeTimeToCompleteSwap.inMinutes,
                    ),
                    style: tokens.captionText,
                  ),
                ],
              ),
            ),
          ],
          TextButton(
            key: const Key('swap_detail_refresh'),
            onPressed: !current || busy || _reading
                ? null
                : () => unawaited(_refresh(lease)),
            child: Text(
              _reading
                  ? context.l10n.swapActionSearching
                  : context.l10n.swapActionFreshDetails,
            ),
          ),
        ],
      ),
    );
  });
}
