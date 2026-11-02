import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/model/pillar_owner_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/skeleton.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// Replaces only the questions in an isolated lifecycle test.
typedef PillarOwnerConfirmation =
    Future<bool?> Function({
      required PillarOwnerSnapshot snapshot,
      required bool finalConfirmation,
    });

/// The owner's copied facts and management entry points, without a sender.
///
/// The caller retains the action hold and accepted result after this panel
/// closes. An opaque authority ticket binds both questions to the same read;
/// the caller must independently check it again at transaction admission.
class PillarOwnerPanel extends StatefulWidget {
  /// Creates the presentation of one completed ownership read.
  const PillarOwnerPanel({
    required this.snapshot,
    required this.busy,
    required this.enabledActions,
    required this.stillCurrent,
    required this.onAction,
    required this.onClose,
    required this.onRefresh,
    this.confirmForTesting,
    this.nowForTesting,
    super.key,
  });

  /// Copied source facts and the root-owned admission ticket.
  final PillarOwnerSnapshot snapshot;

  /// A hold shared by all entry points into the owner's existing actions.
  final bool busy;

  /// Actions the caller can currently offer from these facts.
  final Set<PillarOwnerAction> enabledActions;

  /// Checks the ticket against the current owner, wallet, node and chain.
  final bool Function(PillarOwnerSnapshot) stillCurrent;

  /// Admits an existing flow after checking its captured authority again.
  final Future<void> Function(PillarOwnerAction, PillarOwnerSnapshot) onAction;

  /// Closes the inline panel; the caller keeps any admitted operation alive.
  final VoidCallback onClose;

  /// Reads the captured owner's facts again when its countdown expires.
  final VoidCallback onRefresh;

  /// Questions supplied by a test. Production creates its own dialog routes.
  @visibleForTesting
  final PillarOwnerConfirmation? confirmForTesting;

  /// A deterministic clock for an isolated revocation-expiry test.
  @visibleForTesting
  final DateTime Function()? nowForTesting;

  @override
  State<PillarOwnerPanel> createState() => _PillarOwnerPanelState();
}

class _PillarOwnerPanelState extends State<PillarOwnerPanel> {
  int _epoch = 0;
  bool _disposed = false;
  bool _visible = true;
  bool _refreshRequested = false;
  Object? _operation;
  Timer? _timer;
  ModalRoute<dynamic>? _pageRoute;
  FrostedDialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;

  DateTime get _now => (widget.nowForTesting?.call() ?? DateTime.now()).toUtc();

  bool get _onPage => _pageRoute?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (!identical(route, _pageRoute) || _visible && !visible) {
      _invalidate();
    }
    _pageRoute = route;
    _visible = visible;
    _startClock();
  }

  @override
  void didUpdateWidget(PillarOwnerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot ||
        !oldWidget.busy && widget.busy ||
        oldWidget.enabledActions.contains(PillarOwnerAction.revokeConfirmed) &&
            !widget.enabledActions.contains(
              PillarOwnerAction.revokeConfirmed,
            )) {
      _invalidate();
    }
    if (oldWidget.snapshot != widget.snapshot) {
      _refreshRequested = false;
      _startClock();
    }
  }

  void _invalidate() {
    _epoch++;
    _dismissOwnedConfirmation();
  }

  bool _current(PillarOwnerSnapshot snapshot, int epoch) =>
      mounted &&
      !_disposed &&
      _visible &&
      epoch == _epoch &&
      (_pageRoute?.isActive ?? true) &&
      identical(snapshot.authority, widget.snapshot.authority) &&
      snapshot == widget.snapshot &&
      widget.stillCurrent(snapshot);

  bool _revocable(PillarOwnerSnapshot snapshot) {
    final DateTime? boundary = snapshot.revocationBoundaryUtc;
    return snapshot.isRevocable && boundary != null && boundary.isAfter(_now);
  }

  bool _allowed(PillarOwnerAction action, PillarOwnerSnapshot snapshot) =>
      !widget.busy &&
      widget.enabledActions.contains(action) &&
      (action != PillarOwnerAction.revokeConfirmed || _revocable(snapshot));

  bool _canStart(
    PillarOwnerAction action,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) =>
      _current(snapshot, epoch) &&
      _onPage &&
      _operation == null &&
      _allowed(action, snapshot);

  bool _canContinue(
    Object operation,
    PillarOwnerAction action,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) =>
      _current(snapshot, epoch) &&
      _onPage &&
      identical(_operation, operation) &&
      _allowed(action, snapshot);

  Future<void> _runAction(
    PillarOwnerAction action,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) async {
    if (!_canStart(action, snapshot, epoch)) return;
    final Object operation = Object();
    final Future<void> Function(PillarOwnerAction, PillarOwnerSnapshot) admit =
        widget.onAction;
    setState(() => _operation = operation);
    try {
      if (action == PillarOwnerAction.revokeConfirmed) {
        final bool? first = await _confirm(
          snapshot,
          epoch,
          operation,
          finalConfirmation: false,
        );
        if (first != true ||
            !_canContinue(operation, action, snapshot, epoch)) {
          return;
        }
        final bool? second = await _confirm(
          snapshot,
          epoch,
          operation,
          finalConfirmation: true,
        );
        // Read the clock here as well: an answer cannot extend the window.
        if (second != true ||
            !_canContinue(operation, action, snapshot, epoch)) {
          return;
        }
      }
      if (!_canContinue(operation, action, snapshot, epoch)) return;
      await admit(action, snapshot);
    } finally {
      if (mounted && !_disposed && identical(_operation, operation)) {
        setState(() => _operation = null);
      }
    }
  }

  Future<bool?> _confirm(
    PillarOwnerSnapshot snapshot,
    int epoch,
    Object operation, {
    required bool finalConfirmation,
  }) async {
    final PillarOwnerConfirmation? injected = widget.confirmForTesting;
    if (injected != null) {
      return injected(
        snapshot: snapshot,
        finalConfirmation: finalConfirmation,
      );
    }
    final NavigatorState navigator = Navigator.of(context);
    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    late final FrostedDialogRoute<bool> route;
    bool answered = false;
    void answer({required bool accepted}) {
      // A saved callback must never pop a different dialog above this one.
      if (!mounted ||
          _disposed ||
          answered ||
          !identical(_confirmationRoute, route) ||
          !identical(route.navigator, navigator) ||
          !route.isCurrent) {
        return;
      }
      answered = true;
      final bool valid =
          _current(snapshot, epoch) &&
          identical(_operation, operation) &&
          _allowed(PillarOwnerAction.revokeConfirmed, snapshot);
      navigator.pop(accepted && valid);
    }

    route = FrostedDialogRoute<bool>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder:
          (
            BuildContext routeContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => themes.wrap(
            SafeArea(
              child: Builder(
                builder: (BuildContext dialogContext) => DialogCard(
                  key: Key(
                    finalConfirmation
                        ? 'pillar_owner_revoke_final_dialog'
                        : 'pillar_owner_revoke_first_dialog',
                  ),
                  title: finalConfirmation
                      ? dialogContext.l10n.pillarOwnerRevokeFinalTitle
                      : dialogContext.l10n.pillarOwnerDisassemble,
                  body: Text(
                    finalConfirmation
                        ? dialogContext.l10n.pillarOwnerRevokeConsequence(
                            snapshot.name,
                          )
                        : dialogContext.l10n.pillarOwnerRevokeQuestion(
                            snapshot.name,
                          ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      key: const Key('pillar_owner_revoke_cancel'),
                      style: quietButtonStyle(dialogContext),
                      onPressed: () => answer(accepted: false),
                      child: Text(dialogContext.l10n.cancel),
                    ),
                    OutlinedButton(
                      key: const Key('pillar_owner_revoke_accept'),
                      style: secondaryButtonStyle(dialogContext),
                      onPressed: () => answer(accepted: true),
                      child: Text(
                        finalConfirmation
                            ? dialogContext.l10n.pillarOwnerDisassemble
                            : dialogContext.l10n.continueText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    _confirmationRoute = route;
    _confirmationNavigator = navigator;
    try {
      return await navigator.push<bool>(route);
    } finally {
      answered = true;
      if (identical(_confirmationRoute, route)) {
        _confirmationRoute = null;
        _confirmationNavigator = null;
      }
    }
  }

  void _dismissOwnedConfirmation() {
    final FrostedDialogRoute<bool>? route = _confirmationRoute;
    final NavigatorState? navigator = _confirmationNavigator;
    _confirmationRoute = null;
    _confirmationNavigator = null;
    if (route == null || navigator == null) return;
    // Updates and disposal can occur while the navigator is building.
    scheduleMicrotask(() {
      if (navigator.mounted &&
          identical(route.navigator, navigator) &&
          route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  void _startClock() {
    _timer?.cancel();
    if (!_visible || widget.snapshot.revocationBoundaryUtc == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _disposed || !_visible) return;
      final PillarOwnerSnapshot snapshot = widget.snapshot;
      final DateTime? boundary = snapshot.revocationBoundaryUtc;
      if (boundary == null) return;
      setState(() {});
      if (!boundary.isAfter(_now) &&
          !_refreshRequested &&
          _operation == null &&
          !widget.busy &&
          _onPage &&
          _current(snapshot, _epoch)) {
        _refreshRequested = true;
        widget.onRefresh();
      }
    });
  }

  void _close(PillarOwnerSnapshot snapshot, int epoch) {
    if (!_current(snapshot, epoch) || !_onPage) return;
    _invalidate();
    widget.onClose();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _invalidate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final PillarOwnerSnapshot snapshot = widget.snapshot;
    final int epoch = _epoch;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _close(snapshot, epoch),
      },
      child: FocusTraversalGroup(
        child: Material(
          key: const Key('pillar_owner_panel'),
          color: tokens.card,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: tokens.pillarOwnerPanelPadding,
            child: ListenableBuilder(
              listenable: BalanceVisibility.instance,
              builder: (BuildContext context, Widget? child) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    label: '${context.l10n.nodesYourPillar}: ${snapshot.name}',
                    image: true,
                    child: AppLottie(
                      AppLottieAsset.pillar,
                      key: const Key('pillar_owner_object'),
                      size: tokens.pillarOwnerObjectSize,
                      repeat: false,
                    ),
                  ),
                  SizedBox(width: tokens.pillarOwnerGap),
                  Expanded(child: _buildFacts(context, snapshot, epoch)),
                  SizedBox(width: tokens.pillarOwnerGap),
                  SizedBox(
                    width: tokens.pillarOwnerActionsWidth,
                    child: _buildActions(context, snapshot, epoch),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFacts(
    BuildContext context,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final List<(String, Widget)> left = <(String, Widget)>[
      (
        context.l10n.pillarOwnerLocked,
        snapshot.lockedZnn == null
            ? _unavailable(context)
            : _amount(context, snapshot.lockedZnn!, qsr: false),
      ),
      (
        context.l10n.pillarOwnerProducer,
        _address(context, snapshot.producerAddress, snapshot, epoch),
      ),
      (
        context.l10n.pillarOwnerReward,
        _address(context, snapshot.rewardAddress, snapshot, epoch),
      ),
      (
        context.l10n.pillarOwnerMomentums,
        Ltr(
          child: Text(
            context.l10n.pillarOwnerProduction(
              snapshot.producedMomentums,
              snapshot.expectedMomentums,
            ),
            style: tokens.dataText,
          ),
        ),
      ),
    ];
    final List<(String, Widget)> right = <(String, Widget)>[
      (
        context.l10n.pillarOwnerDeposited,
        _qsrFact(context, snapshot.depositedQsr),
      ),
      (context.l10n.pillarOwnerRevocable, _revocation(context, snapshot)),
      (
        context.l10n.pillarOwnerSharing,
        Ltr(
          child: Text(
            context.l10n.pillarOwnerShares(
              snapshot.momentumRewardPercent,
              snapshot.delegateRewardPercent,
            ),
            style: tokens.dataText,
          ),
        ),
      ),
      (context.l10n.weight, _amount(context, snapshot.weight, qsr: false)),
      (
        context.l10n.pillarOwnerSlotCost,
        _qsrFact(context, snapshot.registrationCostQsr),
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < tokens.pillarOwnerActionsWidth * 2) {
          return _factColumn(context, <(String, Widget)>[...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _factColumn(context, left)),
            SizedBox(width: tokens.pillarOwnerFactColumnGap),
            Expanded(child: _factColumn(context, right)),
          ],
        );
      },
    );
  }

  Widget _factColumn(BuildContext context, List<(String, Widget)> facts) {
    final AppTokens tokens = AppTokens.of(context);
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: <int, TableColumnWidth>{
        0: const IntrinsicColumnWidth(),
        1: FixedColumnWidth(tokens.cardGap),
        2: const FlexColumnWidth(),
      },
      children: <TableRow>[
        for (final (String label, Widget value) in facts)
          TableRow(
            children: <Widget>[
              Padding(
                padding: EdgeInsetsDirectional.only(bottom: tokens.cardGap),
                child: Text(label.toUpperCase(), style: tokens.ledgerText),
              ),
              const SizedBox.shrink(),
              Padding(
                padding: EdgeInsetsDirectional.only(bottom: tokens.cardGap),
                child: value,
              ),
            ],
          ),
      ],
    );
  }

  Widget _unavailable(BuildContext context) => Text(
    context.l10n.pillarOwnerUnavailable,
    style: AppTokens.of(context).compactText.copyWith(
      color: AppTokens.of(context).faint,
    ),
  );

  Widget _qsrFact(BuildContext context, PillarOwnerFact<BigInt> fact) =>
      switch (fact.state) {
        PillarOwnerFactState.loading => const Skeleton(),
        PillarOwnerFactState.unavailable => _unavailable(context),
        PillarOwnerFactState.available => _amount(
          context,
          fact.value!,
          qsr: true,
        ),
      };

  Widget _amount(BuildContext context, BigInt amount, {required bool qsr}) {
    final AppTokens tokens = AppTokens.of(context);
    return HiddenAmount(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: AmountText(
          amount,
          decimals: qsr ? kQsrCoin.decimals : kZnnCoin.decimals,
          symbol: qsr ? kQsrCoin.symbol : kZnnCoin.symbol,
          symbolColor: qsr ? tokens.qsrInk : tokens.znnInk,
          style: tokens.dataText,
        ),
      ),
    );
  }

  Widget _address(
    BuildContext context,
    String address,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final String short = address.length > 14
        ? '${address.substring(0, 7)}…${address.substring(address.length - 6)}'
        : address;
    final bool enabled = _current(snapshot, epoch) && _onPage;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Tooltip(
            message: address,
            child: Ltr(
              child: Text(
                short,
                style: tokens.dataText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        ExcludeFocus(
          excluding: !enabled,
          child: IconButton(
            tooltip: context.l10n.commonCopy,
            visualDensity: VisualDensity.compact,
            iconSize: tokens.settingsIconSize,
            style: IconButton.styleFrom(
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: enabled
                ? () {
                    if (!_current(snapshot, epoch) || !_onPage) return;
                    unawaited(Clipboard.setData(ClipboardData(text: address)));
                  }
                : null,
            icon: Icon(Icons.copy_outlined, color: tokens.faint),
          ),
        ),
      ],
    );
  }

  Widget _revocation(BuildContext context, PillarOwnerSnapshot snapshot) {
    final AppTokens tokens = AppTokens.of(context);
    final DateTime? boundary = snapshot.revocationBoundaryUtc;
    if (boundary == null) return _unavailable(context);
    final Duration remaining = boundary.difference(_now);
    final bool open = _revocable(snapshot);
    return Tooltip(
      message: snapshot.isRevocable
          ? context.l10n.revocationWindowOpen
          : context.l10n.untilRevocationWindowOpens,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            open ? Icons.check_circle_outline : Icons.schedule,
            color: open ? tokens.znnInk : tokens.warn,
            size: tokens.settingsIconSize,
          ),
          SizedBox(width: tokens.fieldLabelGap),
          Flexible(
            child: Ltr(
              child: Text(
                FormatUtils.formatCountdownClock(
                  context.l10n,
                  remaining.isNegative ? Duration.zero : remaining,
                ),
                style: tokens.dataText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final List<(PillarOwnerAction, IconData, String)> actions =
        <(PillarOwnerAction, IconData, String)>[
          (PillarOwnerAction.update, Icons.edit_outlined, context.l10n.update),
          (
            PillarOwnerAction.depositQsr,
            Icons.south,
            context.l10n.pillarOwnerDepositQsr,
          ),
          (
            PillarOwnerAction.withdrawQsr,
            Icons.north,
            context.l10n.pillarOwnerWithdrawQsr,
          ),
          (
            PillarOwnerAction.revokeConfirmed,
            Icons.delete_outline,
            context.l10n.pillarOwnerDisassemble,
          ),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: tokens.inlineGap),
          _actionButton(context, actions[i], snapshot, epoch),
        ],
      ],
    );
  }

  Widget _actionButton(
    BuildContext context,
    (PillarOwnerAction, IconData, String) item,
    PillarOwnerSnapshot snapshot,
    int epoch,
  ) {
    final (PillarOwnerAction action, IconData icon, String label) = item;
    final AppTokens tokens = AppTokens.of(context);
    final bool enabled = _canStart(action, snapshot, epoch);
    final bool destructive = action == PillarOwnerAction.revokeConfirmed;
    final ButtonStyle style = secondaryButtonStyle(context).copyWith(
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(0, tokens.compactButtonHeight),
      ),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsetsDirectional.symmetric(horizontal: tokens.inlineGap),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle>(tokens.compactText),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: destructive
          ? WidgetStateProperty.resolveWith<Color>(
              (Set<WidgetState> states) => states.contains(WidgetState.disabled)
                  ? tokens.faint
                  : tokens.error,
            )
          : null,
    );
    return ExcludeFocus(
      excluding: !enabled,
      child: IgnorePointer(
        ignoring: !enabled,
        child: OutlinedButton.icon(
          key: ValueKey<String>('pillar_owner_${action.name}'),
          style: style,
          onPressed: enabled
              ? () => unawaited(_runAction(action, snapshot, epoch))
              : null,
          icon: Icon(icon, size: tokens.settingsIconSize),
          label: Text(label),
        ),
      ),
    );
  }
}
