import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One paginated owned list. Beneficiary Plasma is a separate source.
class FusedPlasmaCard extends StatefulWidget {
  /// Creates one owned list with shared admission and an exact frozen question.
  const FusedPlasmaCard({
    required this.owner,
    required this.captureSession,
    required this.isCurrent,
    this.onSubmitted,
    super.key,
  });

  /// Retains the original owner's rows, selection and per-hash results.
  final PlasmaOwnerController owner;

  /// Captures current account and transport authority before the question.
  final PlasmaSession? Function() captureSession;

  /// Whether this original page can still authorize preparation.
  final bool Function() isCurrent;

  /// Requests an owner refresh after at least one exact accepted submission.
  final VoidCallback? onSubmitted;

  @override
  State<FusedPlasmaCard> createState() => _FusedPlasmaCardState();
}

class _FusedPlasmaCardState extends State<FusedPlasmaCard> {
  final ScrollController _scroll = ScrollController();
  Route<bool>? _questionRoute;
  bool _visible = true;
  int _visibilityEpoch = 0;

  bool get _current => mounted && _visible && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (_visible && !visible) _visibilityEpoch++;
    _visible = visible;
  }

  @override
  void dispose() {
    _scroll.dispose();
    final Route<bool>? route = _questionRoute;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < _scroll.position.viewportDimension) {
      unawaited(widget.owner.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlasmaOwnerController owner = widget.owner;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[owner, owner.sender.busy]),
      builder: (BuildContext context, _) {
        final AppTokens tokens = AppTokens.of(context);
        final PlasmaOwnerRead? read = owner.displayRead;
        final List<PlasmaFusion> entries = read?.entries ?? <PlasmaFusion>[];
        final bool enabled =
            _current &&
            !owner.busy &&
            !owner.questioning &&
            !owner.sender.busy.value;
        final PlasmaCancellationBatch? batch = owner.lastBatch;
        return Panel(
          key: const Key('plasma_fused_list'),
          heading: Padding(
            padding: EdgeInsetsDirectional.only(start: tokens.cardGap),
            child: Row(
              children: <Widget>[
                Text(
                  context.l10n.plasmaPageFused,
                  style: panelTitleStyle(context),
                ),
                SizedBox(width: tokens.tabCountGap),
                if (read != null)
                  Text(
                    '${read.count}',
                    key: const Key('plasma_fused_count'),
                    style: tokens.ledgerText,
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            if (owner.selected.isNotEmpty) ...<Widget>[
              Text(
                context.l10n.plasmaPageSelected(owner.selected.length),
                style: tokens.dollarText,
              ),
              SizedBox(width: tokens.cardGap),
              OutlinedButton(
                key: const Key('plasma_cancel_selected'),
                style: _cancelButtonStyle(context),
                onPressed: enabled ? () => unawaited(_confirm()) : null,
                child: Text(
                  context.l10n.plasmaPageCancelFuses(owner.selected.length),
                ),
              ),
            ] else
              Text(
                batch == null
                    ? context.l10n.plasmaPageSelectHint
                    : context.l10n.plasmaPageCancelFusesDone(
                        batch.submitted,
                        batch.intent.entries.length,
                      ),
                key: const Key('plasma_batch_summary'),
                style: tokens.dollarText,
              ),
          ],
          child: ListEntrance(
            itemKeys: <LocalKey>[
              for (final PlasmaFusion entry in entries)
                ValueKey<String>(entry.hash),
            ],
            child: switch (owner.status) {
              PlasmaOwnerStatus.failure when read == null => Center(
                child: Text(
                  context.l10n.plasmaPageUnknown,
                  style: tokens.bodyText,
                ),
              ),
              _ when read == null => const Padding(
                padding: kCardBodyPadding,
                child: SkeletonRows(),
              ),
              _ when entries.isEmpty => Center(
                child: EmptyNote.line(text: context.l10n.noItemsFound),
              ),
              _ => Column(
                children: <Widget>[
                  Padding(
                    padding: tokens.pillarHeadingPadding,
                    child: _columns(
                      check: const SizedBox.shrink(),
                      amount: Text(
                        context.l10n.amount.toUpperCase(),
                        style: tokens.ledgerText,
                      ),
                      beneficiary: Text(
                        context.l10n.beneficiaryAddress.toUpperCase(),
                        style: tokens.ledgerText,
                      ),
                      expires: Text(
                        context.l10n.expiration.toUpperCase(),
                        style: tokens.ledgerText,
                      ),
                      action: SizedBox(width: tokens.plasmaCheckboxWidth * 2),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.separated(
                      key: const Key('plasma_fused_rows'),
                      controller: _scroll,
                      itemCount: entries.length + (read.hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (BuildContext context, int index) {
                        if (index == entries.length) {
                          return TextButton(
                            key: const Key('plasma_fused_more'),
                            onPressed: owner.moreLoading
                                ? null
                                : () => unawaited(owner.loadMore()),
                            child: owner.moreLoading
                                ? const SyriusLoadingWidget(size: 16)
                                : Text(context.l10n.commonShowMore),
                          );
                        }
                        final PlasmaFusion entry = entries[index];
                        return ListEntranceItem(
                          key: ValueKey<String>(entry.hash),
                          child: _buildRow(entry, read),
                        );
                      },
                    ),
                  ),
                ],
              ),
            },
          ),
        );
      },
    );
  }

  Widget _columns({
    required Widget check,
    required Widget amount,
    required Widget beneficiary,
    required Widget expires,
    required Widget action,
  }) => Row(
    children: <Widget>[
      SizedBox(width: AppTokens.of(context).plasmaCheckboxWidth, child: check),
      Expanded(flex: 2, child: amount),
      Expanded(flex: 4, child: beneficiary),
      Expanded(flex: 3, child: expires),
      action,
    ],
  );

  Widget _buildRow(PlasmaFusion entry, PlasmaOwnerRead read) {
    final AppTokens tokens = AppTokens.of(context);
    final PlasmaOwnerController owner = widget.owner;
    final bool eligible = widget.isCurrent() && owner.canSelect(entry);
    return Container(
      key: ValueKey<String>('plasma_row_${entry.hash}'),
      color: owner.selected.contains(entry.hash) ? tokens.card2 : tokens.card,
      padding: tokens.pillarCellPadding,
      child: _columns(
        check: Checkbox(
          key: ValueKey<String>('plasma_select_${entry.hash}'),
          value: owner.selected.contains(entry.hash),
          onChanged: eligible
              ? (bool? selected) =>
                    owner.select(entry, selected: selected ?? false)
              : null,
        ),
        amount: Tooltip(
          message: entry.hash,
          child: ValueFlash(
            value: entry.amount,
            color: tokens.qsrInk,
            child: HiddenAmount(
              style: tokens.dataText,
              child: AmountText(
                entry.amount,
                decimals: coinDecimals,
                style: tokens.dataText,
                symbol: 'QSR',
              ),
            ),
          ),
        ),
        beneficiary: _Beneficiary(address: entry.beneficiary),
        expires: Align(
          alignment: AlignmentDirectional.centerStart,
          child: _Expiry(
            entry: entry,
            read: read,
            current: owner.read != null,
            outcome: owner.displayOutcome(entry.hash),
          ),
        ),
        action: SizedBox(
          width: tokens.plasmaCheckboxWidth * 2,
          child: Tooltip(
            message: entry.hash,
            child: OutlinedButton(
              key: ValueKey<String>('plasma_cancel_${entry.hash}'),
              style: _cancelButtonStyle(context),
              onPressed: eligible
                  ? () => unawaited(_confirm(entry.hash))
                  : null,
              child: Text(context.l10n.cancel),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm([String? hash]) async {
    if (!_current) return;
    final int visibilityEpoch = _visibilityEpoch;
    final bool Function() pageIsCurrent = widget.isCurrent;
    // Returning to this mounted page cannot revive its original question.
    bool stillCurrent() =>
        mounted &&
        _visible &&
        visibilityEpoch == _visibilityEpoch &&
        pageIsCurrent();
    final PlasmaSession? session = widget.captureSession();
    if (session == null) return;
    final PlasmaOwnerController owner = widget.owner;
    final PlasmaCancelIntent? intent = owner.beginCancellation(
      session: session,
      hash: hash,
      isCurrent: stillCurrent,
    );
    if (intent == null) return;
    try {
      final bool? confirmed = await _ask(intent);
      if (!(confirmed ?? false) || !stillCurrent()) return;
      final PlasmaCancellationBatch? batch = await owner.cancel(intent);
      if (!stillCurrent() || !session.isCurrent || batch == null) return;
      if (batch.submitted > 0) widget.onSubmitted?.call();
    } finally {
      owner.finishQuestion(intent);
    }
  }

  Future<bool?> _ask(PlasmaCancelIntent intent) {
    bool settled = false;
    Widget buildDialog(BuildContext dialogContext) {
      final ModalRoute<bool>? route = ModalRoute.of<bool>(dialogContext);
      _questionRoute = route;
      void answer({required bool accepted}) {
        if (settled ||
            !mounted ||
            !dialogContext.mounted ||
            route == null ||
            !route.isCurrent) {
          return;
        }
        if (accepted && (!intent.session.isCurrent || !intent.isCurrent())) {
          return;
        }
        settled = true;
        Navigator.of(dialogContext).pop(accepted);
      }

      final AppTokens tokens = AppTokens.of(dialogContext);
      return DialogCard(
        key: const Key('plasma_cancel_confirmation'),
        title: dialogContext.l10n.plasmaPageCancelFuses(intent.entries.length),
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height / 2,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  dialogContext.l10n.plasmaPageCancelFusesConfirm(
                    intent.entries.length,
                    cardAmount(intent.total, coinDecimals, 'QSR'),
                  ),
                ),
                for (final PlasmaFusion entry in intent.entries)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: SelectableText(
                          entry.hash,
                          textDirection: TextDirection.ltr,
                          style: tokens.dataText,
                        ),
                      ),
                      CopyToClipboardButton(
                        entry.hash,
                        tooltip: dialogContext.l10n.plasmaPageCopyFusion,
                        iconSize: tokens.heroCopyIconSize,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('plasma_cancel_decline'),
            style: quietButtonStyle(dialogContext),
            onPressed: () => answer(accepted: false),
            child: Text(dialogContext.l10n.commonNo),
          ),
          OutlinedButton(
            key: const Key('plasma_cancel_accept'),
            onPressed: () => answer(accepted: true),
            child: Text(dialogContext.l10n.commonYes),
          ),
        ],
      );
    }

    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    final FrostedDialogRoute<bool> route = FrostedDialogRoute<bool>(
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
            Widget child,
          ) => FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: child,
          ),
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
          ) => themes.wrap(SafeArea(child: Builder(builder: buildDialog))),
    );
    // Store the exact route before its first build so early disposal owns it.
    _questionRoute = route;
    return navigator.push<bool>(route);
  }
}

class _Beneficiary extends StatelessWidget {
  const _Beneficiary({required this.address});
  final String address;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? label = kAddressLabelMap[address];
    return Tooltip(
      message: address,
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label ?? Address.parse(address).toShortString(),
              style: label == null ? tokens.dataText : tokens.bodyText,
              textDirection: label == null ? TextDirection.ltr : null,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CopyToClipboardButton(address, iconSize: tokens.heroCopyIconSize),
        ],
      ),
    );
  }
}

class _Expiry extends StatelessWidget {
  const _Expiry({
    required this.entry,
    required this.read,
    required this.current,
    required this.outcome,
  });
  final PlasmaFusion entry;
  final PlasmaOwnerRead read;
  final bool current;
  final PlasmaCancellationOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool eligible = entry.eligibleAt(read.frontierHeight);
    final PlasmaCancellationStatus? status = outcome?.status;
    final String label = switch (status) {
      PlasmaCancellationStatus.submitted => context.l10n.plasmaPageSubmitted,
      PlasmaCancellationStatus.publishing => context.l10n.plasmaPageSubmitting,
      PlasmaCancellationStatus.unknown ||
      PlasmaCancellationStatus.refused => context.l10n.plasmaPageUnknown,
      null when !current => context.l10n.plasmaPageUnknown,
      null when eligible => context.l10n.plasmaPageCancelable,
      null => FormatUtils.formatDuration(
        context.l10n,
        kIntervalBetweenMomentums *
            (entry.expirationHeight - read.frontierHeight + 1),
      ),
    };
    final bool unknown =
        status == PlasmaCancellationStatus.unknown ||
        status == PlasmaCancellationStatus.refused ||
        (status == null && !current);
    final Color color = unknown
        ? tokens.warn
        : eligible && status == null
        ? tokens.znnInk
        : tokens.qsrInk;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(tokens.pillRadius),
      ),
      child: Padding(
        padding: tokens.keyboardHintPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              status == null && !eligible
                  ? Icons.lock_outline
                  : unknown
                  ? Icons.help_outline
                  : Icons.check,
              size: tokens.heroCopyIconSize,
              color: color,
            ),
            SizedBox(width: tokens.heroBalanceRunGap),
            Text(label, style: tokens.dollarText.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

ButtonStyle _cancelButtonStyle(BuildContext context) =>
    cardSecondaryButtonStyle(context).copyWith(
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(0, AppTokens.of(context).smallButtonHeight),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        kTextButtonTextStyle.copyWith(fontSize: 12),
      ),
    );
