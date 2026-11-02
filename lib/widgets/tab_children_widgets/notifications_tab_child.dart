import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/services/pending_session_approval.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/copy_to_clipboard_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

/// The shared bell content. The shell owns its store and privacy boundary.
/// A legacy direct destination without a controller exposes no wallet history.
class NotificationsTabChild extends StatefulWidget {
  /// Shares shell-owned history when [controller] is supplied.
  const NotificationsTabChild({this.controller, super.key});

  /// The current wallet bell, absent for a legacy unscoped destination.
  final BellController? controller;

  @override
  State<NotificationsTabChild> createState() => _NotificationsTabChildState();
}

class _NotificationsTabChildState extends State<NotificationsTabChild> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BellController? controller = widget.controller;
    if (controller == null) {
      return Center(child: Text(context.l10n.bellHistoryFailed));
    }
    return BlocBuilder<BellController, BellState>(
      bloc: controller,
      builder: (BuildContext context, BellState state) {
        if (state.private) return const SizedBox.shrink();
        final Set<String> rendered = state.identities;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || controller.isClosed) return;
          final ModalRoute<dynamic>? route = ModalRoute.of(context);
          if ((route?.isCurrent ?? true) &&
              (route?.animation == null ||
                  route!.animation!.status == AnimationStatus.completed)) {
            controller.markSeen(rendered);
          }
        });
        final List<Widget> rows = <Widget>[];
        if (state.approvals.isNotEmpty) {
          rows.add(_Heading(context.l10n.bellNeedsYou));
          for (int i = 0; i < state.approvals.length; i++) {
            final PendingSessionApproval proposal = state.approvals[i];
            rows.add(
              _ApprovalCard(
                key: ValueKey<String>(proposal.identity),
                proposal: proposal,
                controller: controller.approvals!,
                primary: i == 0,
              ),
            );
          }
        }
        if (state.historyFailed) {
          rows.add(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.l10n.bellHistoryFailed,
                      style: AppTokens.of(context).compactText,
                    ),
                  ),
                  TextButton(
                    onPressed: controller.refresh,
                    child: Text(context.l10n.commonRetry),
                  ),
                ],
              ),
            ),
          );
        }
        String? previousDay;
        for (final BellRun run in state.runs) {
          final String? day = _day(context, run.latest.notification.timestamp);
          if (day != null && day != previousDay) {
            rows.add(_Heading(day));
          }
          previousDay = day;
          rows.add(
            _HistoryRun(
              key: ValueKey<String>('run_${run.records.last.identity}'),
              run: run,
              controller: controller,
            ),
          );
        }
        if (rows.isEmpty) {
          rows.add(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.bellNoneYet,
                style: AppTokens.of(context).compactText.copyWith(
                  color: AppTokens.of(context).dim,
                ),
              ),
            ),
          );
        }
        return ListView(
          key: const PageStorageKey<String>('bell_history'),
          padding: EdgeInsets.zero,
          children: rows,
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 6),
    child: Text(label.toUpperCase(), style: AppTokens.of(context).ledgerText),
  );
}

class _HistoryRun extends StatelessWidget {
  const _HistoryRun({required this.run, required this.controller, super.key});

  final BellRun run;
  final BellController controller;

  @override
  Widget build(BuildContext context) {
    if (!run.folded) {
      return _HistoryEvent(record: run.latest, controller: controller);
    }
    final AppTokens tokens = AppTokens.of(context);
    return RowDetail(
      keyPrefix: 'bell_run_${run.records.last.identity}',
      row: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 9, 16, 9),
        child: Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 16, color: tokens.faint),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.l10n.bellBlockPublished,
                style: tokens.bodyText.copyWith(color: tokens.dim),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.bellFoldCount(run.records.length),
              style: tokens.dataText.copyWith(color: tokens.dim),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: context.l10n.bellExpand,
              child: const RowDetailChevron(size: 12),
            ),
            const Spacer(),
            _Stamp(run.latest.notification.timestamp),
          ],
        ),
      ),
      detail: (_) => Column(
        children: <Widget>[
          for (final BellRecord record in run.records)
            _HistoryEvent(
              key: ValueKey<String>(record.identity),
              record: record,
              controller: controller,
            ),
        ],
      ),
    );
  }
}

class _HistoryEvent extends StatelessWidget {
  const _HistoryEvent({
    required this.record,
    required this.controller,
    super.key,
  });

  final BellRecord record;
  final BellController controller;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final WalletNotification event = record.notification;
    return RowDetail(
      keyPrefix: 'bell_event_${record.identity}',
      row: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 9, 16, 9),
        child: Row(
          children: <Widget>[
            Icon(
              bellEventIcon(event),
              size: 16,
              color: bellEventColor(context, event),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    event.title ?? context.l10n.notificationEmptyTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.bodyText,
                  ),
                  if (event.details?.isNotEmpty ?? false)
                    Text(
                      event.details!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.captionText.copyWith(color: tokens.dim),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Stamp(event.timestamp),
          ],
        ),
      ),
      detail: (_) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(42, 2, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SelectableText(
              event.details ?? context.l10n.notificationNoDetails,
              style: tokens.compactText,
            ),
            if (event.transactionHash != null)
              SelectableText(
                event.transactionHash!,
                textDirection: TextDirection.ltr,
                style: tokens.dataText.copyWith(fontSize: 12),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                CopyToClipboardButton(event.details ?? '', iconSize: 16),
                IconButton(
                  key: ValueKey<String>('bell_remove_${record.identity}'),
                  tooltip: context.l10n.bellRemove,
                  onPressed: () => unawaited(
                    controller.removeRecords(
                      <BellRecord>[record],
                    ),
                  ),
                  icon: Icon(Icons.close, size: 16, color: tokens.faint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.proposal,
    required this.controller,
    required this.primary,
    super.key,
  });

  final PendingSessionApproval proposal;
  final PendingApprovalController controller;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Uri? reportedUrl = Uri.tryParse(proposal.url);
    final String name = reportedUrl?.host.isNotEmpty == true
        ? reportedUrl!.host
        : proposal.name;
    return ColoredBox(
      color: tokens.card2,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.link, size: 16, color: tokens.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: proposal.url,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.headingText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.l10n.bellConnectRequest, style: tokens.compactText),
            const SizedBox(height: 8),
            // Accounts are explicit before the decision. They are the copied
            // CAIP accounts the service will actually offer, not selection.
            Text(context.l10n.bellAccounts, style: tokens.ledgerText),
            for (final ApprovalNamespace namespace
                in proposal.approvedNamespaces.values)
              for (final String account in namespace.accounts)
                SelectableText(
                  account,
                  textDirection: TextDirection.ltr,
                  style: tokens.dataText.copyWith(fontSize: 11),
                ),
            RowDetail(
              keyPrefix: 'bell_scope_${proposal.id}',
              row: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    Text(context.l10n.bellRequested, style: tokens.compactText),
                    const SizedBox(width: 6),
                    const RowDetailChevron(size: 12),
                  ],
                ),
              ),
              detail: (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _NamespaceList(
                    title: context.l10n.bellRequired,
                    namespaces: proposal.requiredNamespaces,
                  ),
                  _NamespaceList(
                    title: context.l10n.bellOptional,
                    namespaces: proposal.optionalNamespaces,
                  ),
                  _NamespaceList(
                    title: context.l10n.bellApproved,
                    namespaces: proposal.approvedNamespaces,
                  ),
                ],
              ),
            ),
            if (proposal.failed)
              Text(
                context.l10n.bellApprovalFailed,
                style: tokens.compactText.copyWith(color: tokens.error),
              ),
            SizedBox(
              height: tokens.compactButtonHeight,
              child: Row(
                children: <Widget>[
                  if (primary)
                    PrimaryPill(
                      key: ValueKey<String>('bell_approve_${proposal.id}'),
                      onPressed: proposal.canDecide
                          ? () => unawaited(
                              controller.resolve(proposal.id, accept: true),
                            )
                          : null,
                      style: ButtonStyle(
                        minimumSize: WidgetStatePropertyAll<Size>(
                          Size(0, tokens.compactButtonHeight),
                        ),
                      ),
                      child: Text(
                        proposal.busy
                            ? context.l10n.bellResolving
                            : context.l10n.bellApprove,
                      ),
                    )
                  else
                    OutlinedButton(
                      key: ValueKey<String>('bell_approve_${proposal.id}'),
                      onPressed: proposal.canDecide
                          ? () => unawaited(
                              controller.resolve(proposal.id, accept: true),
                            )
                          : null,
                      child: Text(
                        proposal.busy
                            ? context.l10n.bellResolving
                            : context.l10n.bellApprove,
                      ),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: ValueKey<String>('bell_decline_${proposal.id}'),
                    onPressed: proposal.canDecide
                        ? () => unawaited(
                            controller.resolve(proposal.id, accept: false),
                          )
                        : null,
                    child: Text(context.l10n.bellDecline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NamespaceList extends StatelessWidget {
  const _NamespaceList({required this.title, required this.namespaces});

  final String title;
  final Map<String, ApprovalNamespace> namespaces;

  @override
  Widget build(BuildContext context) {
    if (namespaces.isEmpty) return const SizedBox.shrink();
    final AppTokens tokens = AppTokens.of(context);
    Widget line(String label, List<String> values) => values.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(label, style: tokens.captionText),
                SelectableText(
                  values.join(', '),
                  textDirection: TextDirection.ltr,
                  style: tokens.dataText.copyWith(fontSize: 11),
                ),
              ],
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: tokens.ledgerText),
          for (final MapEntry<String, ApprovalNamespace> entry
              in namespaces.entries) ...<Widget>[
            Text(
              entry.key,
              textDirection: TextDirection.ltr,
              style: tokens.dataText.copyWith(fontSize: 12),
            ),
            line(context.l10n.bellChains, entry.value.chains),
            line(context.l10n.bellMethods, entry.value.methods),
            line(context.l10n.bellEvents, entry.value.events),
          ],
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp(this.timestamp);

  final int? timestamp;

  @override
  Widget build(BuildContext context) {
    final int? stamp = timestamp;
    if (stamp == null) return const SizedBox.shrink();
    final DateTime? date = _date(stamp);
    if (date == null) return const SizedBox.shrink();
    final Duration age = DateTime.now().difference(date);
    final String text = age.isNegative
        ? MaterialLocalizations.of(context).formatShortDate(date)
        : age.inMinutes < 1
        ? context.l10n.bellNow
        : age.inHours < 1
        ? context.l10n.bellMinutesAgo(age.inMinutes)
        : age.inDays < 1
        ? context.l10n.bellHoursAgo(age.inHours)
        : context.l10n.bellDaysAgo(age.inDays);
    return Tooltip(
      message: FormatUtils.formatNotificationStamp(
        stamp,
        locale: Localizations.localeOf(context),
      ),
      child: Text(
        text,
        style: AppTokens.of(context).dataText.copyWith(
          fontSize: 12,
          color: AppTokens.of(context).dim,
        ),
      ),
    );
  }
}

String? _day(BuildContext context, int? timestamp) {
  final DateTime? date = _date(timestamp);
  if (date == null) return null;
  final DateTime now = DateTime.now();
  final DateTime day = DateTime(date.year, date.month, date.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  if (day == today) return context.l10n.bellToday;
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return context.l10n.bellYesterday;
  }
  return MaterialLocalizations.of(context).formatShortDate(date);
}

DateTime? _date(int? timestamp) {
  if (timestamp == null) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  } on Object {
    return null;
  }
}

/// The category icon shared by bell rows and fresh-event toasts.
IconData bellEventIcon(WalletNotification event) => switch (event.type) {
  NotificationType.error => Icons.warning_amber_rounded,
  NotificationType.confirm => Icons.visibility_outlined,
  NotificationType.stakingDeactivated => Icons.warning_amber_rounded,
  NotificationType.paymentReceived => Icons.south_west,
  NotificationType.rewardReceived => Icons.monetization_on_outlined,
  NotificationType.generatingPlasma => Icons.bolt,
  NotificationType.copiedToClipboard => Icons.content_copy,
  _ => Icons.check_circle_outline,
};

/// The theme token for an event's category or explicit publication marker.
Color bellEventColor(BuildContext context, WalletNotification event) {
  final AppTokens tokens = AppTokens.of(context);
  return switch (event.type) {
    NotificationType.error => tokens.error,
    NotificationType.confirm ||
    NotificationType.stakingDeactivated => tokens.warn,
    NotificationType.generatingPlasma => tokens.qsrInk,
    _ => event.eventKind == 'blockPublished' ? tokens.faint : tokens.znnInk,
  };
}
