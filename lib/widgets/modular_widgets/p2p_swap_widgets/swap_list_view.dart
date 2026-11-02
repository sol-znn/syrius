import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/toast_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/join_native_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/native_p2p_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/p2p_swap_warning_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/recover_deposit_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/start_native_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/p2p_swap_options_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/p2p_swaps_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/dialogs.dart';

/// Keeps modal handoffs on the original owner instead of following globals.
class SwapListView extends StatefulWidget {
  /// Observes the original presenter and owns modal delivery and busy state.
  const SwapListView({
    required this.presenter,
    required this.onRefresh,
    this.onStart,
    this.onJoin,
    this.onOpen,
    this.onRecover,
    this.onBusyChanged,
    super.key,
  });

  /// Original complete catalogue presenter, or null for unavailable history.
  final SwapListPresenter? presenter;

  /// Requests a fresh complete capture after a modal or history action.
  final VoidCallback onRefresh;

  /// Optional finite Start-flow injection, without changing signer authority.
  final VoidCallback? onStart;

  /// Optional finite Join-flow injection.
  final VoidCallback? onJoin;

  /// Optional detail-flow injection receiving the exact rendered public record.
  final ValueChanged<SwapListRecord>? onOpen;

  /// Optional recovery-flow injection.
  final VoidCallback? onRecover;

  /// Reports owned modal activity so the parent defers replacing its presenter.
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<SwapListView> createState() => _SwapListViewState();
}

class _SwapListViewState extends State<SwapListView> {
  final List<SwapListOutcome> _preferenceOutcomes = <SwapListOutcome>[];
  bool _opening = false;
  int _dialogs = 0;

  void _dialogStarted() {
    _dialogs++;
    widget.onBusyChanged?.call(true);
  }

  void _dialogFinished() {
    _dialogs--;
    if (_dialogs == 0) widget.onBusyChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final SwapListPresenter? presenter = widget.presenter;
    final SwapListSnapshot? snapshot = presenter?.isCurrent == true
        ? presenter?.snapshot
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        P2pSwapOptionsCard(
          snapshot: snapshot,
          binding: presenter?.binding,
          onStart: _opening ? null : () => _startOrJoin(join: false),
          onJoin: _opening ? null : () => _startOrJoin(join: true),
        ),
        SizedBox(height: tokens.pageGap),
        Expanded(
          child: P2pSwapsCard(
            presenter: presenter,
            onRefresh: widget.onRefresh,
            onOpen: _open,
            onDelete: (SwapListRecord record) =>
                unawaited(_delete(<SwapListRecord>[record])),
            onClear: () {
              final SwapListPresenter? original = widget.presenter;
              if (original?.isCurrent != true) return;
              final List<SwapListRecord> rows =
                  original!.snapshot?.rows
                      .map((SwapListRow row) => row.record)
                      .where((SwapListRecord row) => row.canDelete)
                      .toList() ??
                  <SwapListRecord>[];
              unawaited(_delete(rows, clear: true));
            },
            onRecover: _recover,
            onTutorial: () =>
                unawaited(NavigationUtils.openUrl(kP2pSwapTutorialLink)),
          ),
        ),
      ],
    );
  }

  bool _owns(SwapListPresenter original) =>
      mounted && original.binding.ownsResources();

  SwapActionOrigin? _captureAction(bool Function() current) {
    try {
      return SwapActionOrigin.capture(sourceIsCurrent: current);
    } on Object {
      return null;
    }
  }

  void _open(SwapListRecord record) {
    final SwapListPresenter? original = widget.presenter;
    if (original == null || !_owns(original) || !original.canOpen(record)) {
      return;
    }
    if (widget.onOpen != null) {
      widget.onOpen!(record);
      return;
    }
    bool sourceCurrent() =>
        original.binding.ownsResources() &&
        original.binding.rowIsCurrent(record);
    final SwapActionOrigin? source = _captureAction(sourceCurrent);
    if (source == null) return;
    _dialogStarted();
    unawaited(
      showCustomDialog(
        context: context,
        content: NativeP2pSwapModal(
          swapId: record.id,
          source: source,
          sourceIsCurrent: () =>
              original.binding.ownsResources() &&
              original.binding.rowIsCurrent(record),
        ),
      ).whenComplete(_dialogFinished),
    );
  }

  void _recover() {
    final SwapListPresenter? original = widget.presenter;
    if (original == null || !_owns(original)) return;
    if (widget.onRecover != null) {
      widget.onRecover!();
      return;
    }
    final SwapActionOrigin? source = _captureAction(
      original.binding.ownsResources,
    );
    if (source == null) return;
    _dialogStarted();
    unawaited(
      showCustomDialog(
        context: context,
        content: RecoverDepositModal(
          source: source,
          sourceIsCurrent: original.binding.ownsResources,
        ),
      ).whenComplete(_dialogFinished),
    );
  }

  Future<void> _delete(
    List<SwapListRecord> records, {
    bool clear = false,
  }) async {
    final SwapListPresenter? original = widget.presenter;
    if (original == null ||
        !_owns(original) ||
        records.isEmpty ||
        records.any((SwapListRecord row) => !original.canOpen(row))) {
      return;
    }
    _dialogStarted();
    try {
      final bool? confirmed = await showDialogWithNoAndYesOptions(
        context: context,
        isBarrierDismissible: true,
        title: clear
            ? context.l10n.swapListClearHistory
            : context.l10n.swapListDelete,
        description: clear
            ? context.l10n.swapListClearWarning
            : context.l10n.swapListDeleteWarning,
      );
      if (confirmed != true || !mounted || !_owns(original)) return;
      final SwapListOutcome? outcome = await original.delete(records);
      if (outcome == null || !mounted || !_owns(original)) return;
      if (outcome.error != null) {
        ToastUtils.showToast(context, context.l10n.swapListUnavailable);
      }
    } finally {
      _dialogFinished();
      if (mounted) widget.onRefresh();
    }
  }

  void _startOrJoin({required bool join}) {
    final SwapListPresenter? original = widget.presenter;
    if (_opening || original == null || !_owns(original)) return;
    final VoidCallback? injected = join ? widget.onJoin : widget.onStart;
    if (injected != null) {
      injected();
      return;
    }
    unawaited(_openFlow(original, join: join));
  }

  Future<void> _openFlow(
    SwapListPresenter original, {
    required bool join,
  }) async {
    // Capture before the warning, preference write or route builder awaits.
    final SwapActionOrigin? source = _captureAction(
      original.binding.ownsResources,
    );
    if (source == null) return;
    final SharedPrefsService? preferences = app.sharedPrefsService;
    if (preferences == null || !Hive.isBoxOpen(kSharedPrefsBox)) return;
    final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
    bool revoked = false;
    bool current() {
      if (revoked) return false;
      revoked =
          !_owns(original) ||
          !source.isCurrent ||
          !identical(app.sharedPrefsService, preferences) ||
          !box.isOpen ||
          !Hive.isBoxOpen(kSharedPrefsBox) ||
          !identical(Hive.box<dynamic>(kSharedPrefsBox), box);
      return !revoked;
    }

    if (!current()) return;
    _dialogStarted();
    setState(() => _opening = true);
    try {
      final Object? warning = box.get(
        kHasReadP2pSwapWarningKey,
        defaultValue: kHasReadP2pSwapWarningDefaultValue,
      );
      if (warning is! bool) return;
      if (!warning) {
        bool accepted = false;
        await showCustomDialog(
          context: context,
          content: Builder(
            builder: (BuildContext dialogContext) => P2PSwapWarningModal(
              onAccepted: () {
                if (!dialogContext.mounted ||
                    !current() ||
                    ModalRoute.of(dialogContext)?.isCurrent != true) {
                  return;
                }
                accepted = true;
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
        );
        if (!accepted || !mounted || !current()) return;
        late Future<void> write;
        try {
          write = box.put(kHasReadP2pSwapWarningKey, true);
        } on Object catch (value, trace) {
          write = Future<void>.error(value, trace);
        }
        final SwapListOutcome outcome = SwapListOutcome(write);
        _preferenceOutcomes.add(outcome);
        try {
          await outcome.settle();
        } on Object {
          if (mounted && current()) {
            ToastUtils.showToast(context, context.l10n.swapListUnavailable);
          }
          return;
        }
      }
      if (!mounted || !current()) return;
      String? created;
      await showCustomDialog(
        context: context,
        content: Builder(
          builder: (BuildContext dialogContext) {
            void completed(String id) {
              if (!dialogContext.mounted ||
                  !current() ||
                  ModalRoute.of(dialogContext)?.isCurrent != true) {
                return;
              }
              created = id;
              Navigator.of(dialogContext).pop();
            }

            return join
                ? JoinNativeSwapModal(
                    onJoinedSwap: completed,
                    source: source,
                    sourceIsCurrent: original.binding.ownsResources,
                  )
                : StartNativeSwapModal(
                    onSwapStarted: completed,
                    source: source,
                    sourceIsCurrent: original.binding.ownsResources,
                  );
          },
        ),
      );
      final String? exactCreatedId = created;
      if (exactCreatedId == null || !mounted || !current()) return;
      await showCustomDialog(
        context: context,
        content: NativeP2pSwapModal(
          swapId: exactCreatedId,
          source: source,
          sourceIsCurrent: original.binding.ownsResources,
        ),
      );
    } finally {
      _dialogFinished();
      if (mounted) setState(() => _opening = false);
    }
  }
}
