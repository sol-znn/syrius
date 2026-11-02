import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';

/// Shares presentation ownership, never the action engine or wallet selection.
mixin CapturedSwapModal<W extends StatefulWidget> on State<W> {
  /// Original action source supplied before this state mounts.
  SwapActionOrigin? get providedOrigin;

  /// Optional caller-owned guard for the original route or rendered row.
  bool Function()? get providedIsCurrent;

  /// Source captured once in initState, never rediscovered after an await.
  late final SwapActionOrigin? origin;
  late final bool Function()? _caller;

  /// Presentation generation replaced when inputs or details change.
  Object epoch = Object();

  /// Whether this view observes an admitted action's original Future.
  bool busy = false;
  bool _revoked = false;
  bool _departed = false;
  final List<SwapUiRun> _runs = <SwapUiRun>[];
  final List<Object> _clipboard = <Object>[];

  /// Exact original operation currently observed by the view.
  SwapUiRun? activeRun;

  /// Result deliverable to this current presentation generation.
  SwapActionResult? shownResult;

  @override
  void initState() {
    super.initState();
    // An absent capture stays absent. No route builder resolves globals later.
    origin = providedOrigin;
    _caller = providedIsCurrent;
  }

  /// Monotonic source and view ownership; departure cannot be reversed by ABA.
  bool get sourceCurrent {
    if (_revoked || _departed || !mounted) return false;
    try {
      _revoked =
          origin == null ||
          !identical(origin, providedOrigin) ||
          origin?.isCurrent != true ||
          !(_caller?.call() ?? true);
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Requires both the exact presentation lease and original source ownership.
  bool owns(SwapViewLease lease) => mounted && lease.isCurrent && sourceCurrent;

  /// Whether an accepted, uncertain or departed action keeps editing blocked.
  bool get held =>
      shownResult?.status == SwapActionStatus.submitted ||
      shownResult?.status == SwapActionStatus.unknown ||
      _departed;

  /// Builds guarded input with the shared balance-visibility state.
  Widget captured(
    Widget Function(BuildContext, SwapViewLease, {required bool hidden})
    builder,
  ) => ListenableBuilder(
    listenable: BalanceVisibility.instance,
    builder: (BuildContext context, Widget? child) => SwapActionBoundary(
      source: epoch,
      builder: (BuildContext context, SwapViewLease lease) => PopScope(
        canPop: !busy,
        child: builder(
          context,
          lease,
          hidden: BalanceVisibility.instance.hidden,
        ),
      ),
    ),
  );

  /// Applies one current, unheld edit and revokes all older input callbacks.
  void change(SwapViewLease lease, VoidCallback update) {
    if (!owns(lease) || busy || held) return;
    setState(() {
      update();
      epoch = Object();
      shownResult = null;
    });
  }

  /// Admits disclosure changes only on a current, idle original view.
  bool toggleDetails(SwapViewLease lease) {
    if (!owns(lease) || busy) return false;
    setState(() => epoch = Object());
    return true;
  }

  /// Returns an exact-generation route close action when no action is pending.
  VoidCallback? close(SwapViewLease lease) => busy
      ? null
      : lease.guard(() {
          if (!busy) Navigator.of(context).pop();
        });

  /// Observes one original operation without canceling or retrying it when this
  /// view departs; late results remain retained outside stale presentation.
  Future<void> submit(
    SwapViewLease lease,
    Future<SwapActionResult> Function() operation,
  ) async {
    if (!owns(lease) || busy || held) return;
    setState(() {
      busy = true;
      shownResult = null;
    });
    final SwapUiRun run = SwapUiRun(operation);
    _runs.add(run);
    activeRun = run;
    final SwapActionResult result = await run.completion;
    if (!mounted || !identical(activeRun, run)) return;
    final bool current = owns(lease);
    setState(() {
      busy = false;
      if (current) {
        shownResult = result;
      } else {
        _departed = true;
      }
    });
  }

  /// Clipboard operations are exact, finite and do not toast after departure.
  Future<void> paste(
    SwapViewLease lease,
    TextEditingController controller,
  ) async {
    if (!owns(lease) || busy || held) return;
    final String original = controller.text;
    late final Future<ClipboardData?> read;
    try {
      read = Clipboard.getData('text/plain');
    } on Object {
      return;
    }
    _clipboard.add(read);
    try {
      final ClipboardData? value = await read;
      if (!owns(lease) || busy || held || controller.text != original) {
        return;
      }
      final String? pasted = value?.text;
      if (pasted == null || pasted.length > 256) {
        return;
      }
      change(lease, () => controller.text = pasted);
    } on Object {
      // Platform diagnostics remain private; a failed paste changes no draft.
    }
  }

  /// Copies only a canonical public deposit identifier from the exact lease.
  Future<void> copy(SwapViewLease lease, String id) async {
    if (!owns(lease) || swapDepositId(id) == null) return;
    late final Future<void> write;
    try {
      write = Clipboard.setData(ClipboardData(text: id));
    } on Object {
      return;
    }
    _clipboard.add(write);
    try {
      await write;
    } on Object {
      /* No stale or raw platform notice. */
    }
  }

  /// Maps source and action states to fixed localized text, never raw errors.
  Widget? resultNotice(BuildContext context) {
    if (!sourceCurrent) {
      return SwapNotice(context.l10n.swapListSourceChanged, error: true);
    }
    final SwapActionResult? result = shownResult;
    if (result == null) return null;
    return switch (result.status) {
      SwapActionStatus.refused => SwapNotice(
        context.l10n.swapActionRefused,
        error: true,
      ),
      SwapActionStatus.unknown => SwapNotice(
        context.l10n.swapActionUnknown,
        waiting: true,
      ),
      SwapActionStatus.submitted => SwapNotice(
        context.l10n.swapActionSubmitted,
        waiting: true,
      ),
    };
  }

  @override
  void dispose() {
    epoch = Object();
    _departed = true;
    // Original runs remain owned by SwapActions and finish without this view.
    super.dispose();
  }
}
