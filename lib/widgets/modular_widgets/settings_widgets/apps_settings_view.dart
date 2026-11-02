import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/wallet_connect_widgets/wallet_connect_camera_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/wallet_connect_widgets/wallet_connect_qr_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/wallet_connect_widgets/wallet_connect_uri_card.dart';

/// Presentation accepts only captured facts and guarded original actions.
class AppsSettingsView extends StatefulWidget {
  /// Displays captured connections and delegates effects to the original owner.
  const AppsSettingsView({
    required this.presenter,
    required this.isCurrent,
    super.key,
  });

  /// The presenter that retains this section's original source and journal.
  final AppsSettingsPresenter presenter;

  /// The parent section's current navigation generation.
  final bool Function() isCurrent;

  @override
  State<AppsSettingsView> createState() => _AppsSettingsViewState();
}

class _AppsSettingsViewState extends State<AppsSettingsView>
    with WidgetsBindingObserver {
  final DisclosureController _details = DisclosureController();
  int _epoch = 0;
  int _detailsEpoch = 0;
  bool _visible = true;
  bool _active = true;
  ModalRoute<dynamic>? _route;
  DialogRoute<void>? _pairRoute;
  NavigatorState? _navigator;

  bool get _baseCurrent => mounted && widget.isCurrent();
  bool get _current =>
      _baseCurrent && _visible && _active && (_route?.isCurrent ?? true);

  bool Function() _capture({bool details = false}) {
    final int epoch = _epoch;
    final int detailEpoch = _detailsEpoch;
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            !_current ||
            epoch != _epoch ||
            (details && (!_details.isOpen || detailEpoch != _detailsEpoch)));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _details.addListener(_detailsChanged);
  }

  void _detailsChanged() {
    if (!_details.isOpen) _detailsEpoch++;
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final bool visible =
        TickerMode.valuesOf(context).enabled && (_route?.isCurrent ?? true);
    // The owned connection route may cover this view without replacing it.
    if (_visible && !visible && !(_pairRoute?.isActive ?? false)) _epoch++;
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        !(_pairRoute?.isActive ?? false)) {
      _epoch++;
    }
    _active = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AppsSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter) ||
        !oldWidget.isCurrent()) {
      _epoch++;
    }
  }

  void _setEnabled(bool value) {
    final bool Function() owns = _capture();
    if (!owns()) return;
    unawaited(
      widget.presenter.run(
        (AppsSettingsBinding binding) =>
            binding.setEnabled(enabled: value, visible: owns),
        owns,
      ),
    );
  }

  void _disconnect(AppsConnection row) {
    final bool Function() owns = _capture();
    if (!owns()) return;
    unawaited(
      widget.presenter.run(
        (AppsSettingsBinding binding) => binding.disconnect(row, owns),
        owns,
      ),
    );
  }

  void _disconnectPairing(AppsPairing row) {
    final bool Function() owns = _capture(details: true);
    if (!owns()) return;
    unawaited(
      widget.presenter.run(
        (AppsSettingsBinding binding) => binding.disconnectPairing(row, owns),
        owns,
      ),
    );
  }

  Future<void> _connectByLink() async {
    if (!_current ||
        widget.presenter.binding == null ||
        widget.presenter.state.busy ||
        _pairRoute != null) {
      return;
    }
    final AppsSettingsPresenter presenter = widget.presenter;
    final int epoch = ++_epoch;
    final NavigatorState navigator = Navigator.of(context);
    late final DialogRoute<void> route;
    bool original() =>
        _baseCurrent &&
        epoch == _epoch &&
        identical(widget.presenter, presenter) &&
        identical(_pairRoute, route) &&
        route.isActive;
    route = DialogRoute<void>(
      context: context,
      builder: (BuildContext context) => _AppsPairDialog(
        presenter: presenter,
        isCurrent: original,
        close: () {
          if (original() && route.isCurrent) navigator.removeRoute(route);
        },
      ),
    );
    _pairRoute = route;
    _navigator = navigator;
    try {
      await navigator.push<void>(route);
    } finally {
      if (identical(_pairRoute, route)) {
        _pairRoute = null;
        _navigator = null;
        _epoch++;
      }
      if (mounted && identical(widget.presenter, presenter)) {
        presenter.refresh();
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AppsSettingsPresenter, AppsSettingsState>(
        bloc: widget.presenter,
        builder: (BuildContext context, AppsSettingsState state) {
          final AppTokens tokens = AppTokens.of(context);
          final int buildEpoch = _epoch;
          final int detailEpoch = _detailsEpoch;
          final AppsSettingsPresenter original = widget.presenter;
          bool sourceCurrent() =>
              buildEpoch == _epoch &&
              _current &&
              identical(original, widget.presenter);
          final bool current =
              _current && (widget.presenter.binding?.isCurrent ?? false);
          final AppsSnapshot snapshot = current
              ? state.snapshot
              : AppsSnapshot.unavailable();
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double tableHeight = constraints.hasBoundedHeight
                  ? (constraints.maxHeight - 132)
                        .clamp(176, double.infinity)
                        .toDouble()
                  : 320;
              return SingleChildScrollView(
                key: const Key('apps_settings_page'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Panel(
                      child: _WebAppsSwitch(
                        snapshot: snapshot,
                        busy: state.busy,
                        onChanged:
                            current && snapshot.webAppsAvailable && !state.busy
                            ? (bool value) {
                                if (sourceCurrent()) _setEnabled(value);
                              }
                            : null,
                      ),
                    ),
                    SizedBox(height: tokens.appsSettingsGap),
                    SizedBox(
                      height: tableHeight,
                      child: Panel(
                        key: const Key('apps_settings_connected'),
                        title: context.l10n.appsSettingsConnected,
                        heading: Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                context.l10n.appsSettingsConnected,
                                style: tokens.headingText,
                              ),
                            ),
                            SizedBox(width: tokens.cardGap),
                            Text(
                              snapshot.webAppsAvailable &&
                                      snapshot.walletConnectAvailable
                                  ? '${snapshot.connections.length}'
                                  : context.l10n.appsSettingsUnknown,
                              key: const Key('apps_settings_count'),
                              style: tokens.ledgerText,
                            ),
                          ],
                        ),
                        actions: <Widget>[
                          _AppsButton(
                            key: const Key('apps_settings_connect'),
                            label: context.l10n.appsSettingsConnectByLink,
                            icon: Icons.add,
                            onPressed:
                                current &&
                                    snapshot.walletConnectAvailable &&
                                    !state.busy
                                ? () {
                                    if (sourceCurrent()) {
                                      unawaited(_connectByLink());
                                    }
                                  }
                                : null,
                          ),
                        ],
                        child: _ConnectionsTable(
                          snapshot: snapshot,
                          enabled: current && !state.busy,
                          disconnect: (AppsConnection row) {
                            if (sourceCurrent()) _disconnect(row);
                          },
                        ),
                      ),
                    ),
                    if (state.outcome?.status == AppsActionStatus.failed ||
                        state.outcome?.status == AppsActionStatus.saveFailed)
                      Padding(
                        padding: tokens.settingsRowPadding,
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.error_outline,
                              size: 16,
                              color: tokens.error,
                            ),
                            SizedBox(width: tokens.fieldLabelGap),
                            Flexible(
                              child: Text(
                                state.outcome?.status ==
                                        AppsActionStatus.saveFailed
                                    ? context.l10n.appsSettingsNotSaved
                                    : context.l10n.appsSettingsOutcomeUnknown,
                                style: tokens.captionText.copyWith(
                                  color: tokens.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: tokens.appsSettingsGap),
                    Panel(
                      child: Disclosure(
                        title: context.l10n.appsSettingsWalletConnect,
                        summary: snapshot.walletConnectAvailable
                            ? context.l10n.appsSettingsSummary(
                                snapshot.sessionCount,
                                snapshot.pairings.length,
                              )
                            : context.l10n.appsSettingsUnavailable,
                        controller: _details,
                        keyPrefix: 'apps_settings_details',
                        child: _WalletConnectDetails(
                          snapshot: snapshot,
                          enabled: current && !state.busy && _details.isOpen,
                          disconnectPairing: (AppsPairing row) {
                            if (sourceCurrent() &&
                                detailEpoch == _detailsEpoch &&
                                _details.isOpen) {
                              _disconnectPairing(row);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

  @override
  void dispose() {
    _epoch++;
    _detailsEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _details.removeListener(_detailsChanged);
    _details.dispose();
    final DialogRoute<void>? route = _pairRoute;
    final NavigatorState? navigator = _navigator;
    if (route != null && navigator != null) {
      scheduleMicrotask(() {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    super.dispose();
  }
}

class _WebAppsSwitch extends StatelessWidget {
  const _WebAppsSwitch({
    required this.snapshot,
    required this.busy,
    this.onChanged,
  });
  final AppsSnapshot snapshot;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String status = !snapshot.webAppsAvailable
        ? context.l10n.appsSettingsUnavailable
        : !snapshot.enabled
        ? context.l10n.appsSettingsOff
        : snapshot.port == null
        ? context.l10n.appsSettingsNoFreePort
        : '127.0.0.1:${snapshot.port}';
    return Padding(
      padding: tokens.settingsRowPadding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.l10n.appsSettingsWebApps, style: tokens.bodyText),
                Wrap(
                  spacing: tokens.fieldLabelGap,
                  children: <Widget>[
                    Text(
                      context.l10n.appsSettingsWebAppsHint,
                      style: tokens.settingsHintText,
                    ),
                    Text(
                      status,
                      key: const Key('apps_settings_status'),
                      style: tokens.dataText.copyWith(
                        fontSize: 12.5,
                        color: tokens.dim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SettingsSwitch(
            key: const Key('apps_settings_web_switch'),
            value: snapshot.enabled,
            label: context.l10n.appsSettingsWebApps,
            onChanged: busy ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class _ConnectionsTable extends StatelessWidget {
  const _ConnectionsTable({
    required this.snapshot,
    required this.enabled,
    required this.disconnect,
  });
  final AppsSnapshot snapshot;
  final bool enabled;
  final ValueChanged<AppsConnection> disconnect;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1, double.infinity).toDouble();
        final double minimum = tokens.appsSettingsTableMinWidth * scale;
        final double width = constraints.maxWidth < minimum
            ? minimum
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: tokens.settingsRowPadding,
                  child: _AppsColumns(
                    children: <Widget>[
                      Text(
                        context.l10n.appsSettingsSite,
                        style: tokens.ledgerText,
                      ),
                      Text(context.l10n.address, style: tokens.ledgerText),
                      Text(
                        context.l10n.appsSettingsLastUsed,
                        style: tokens.ledgerText,
                      ),
                      Text(
                        context.l10n.appsSettingsVia,
                        style: tokens.ledgerText,
                      ),
                      const SizedBox.shrink(),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.line),
                Expanded(
                  child: snapshot.connections.isEmpty
                      ? QuietNote(
                          snapshot.webAppsAvailable ||
                                  snapshot.walletConnectAvailable
                              ? context.l10n.appsSettingsNone
                              : context.l10n.appsSettingsUnavailable,
                        )
                      : ListView.separated(
                          key: const PageStorageKey<String>('apps_connections'),
                          itemCount: snapshot.connections.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: tokens.line),
                          itemBuilder: (BuildContext context, int index) {
                            final AppsConnection row =
                                snapshot.connections[index];
                            return Padding(
                              key: Key('apps_connection_$index'),
                              padding: tokens.settingsRowPadding,
                              child: _AppsColumns(
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Container(
                                        width: tokens.appsSettingsSiteMarkSize,
                                        height: tokens.appsSettingsSiteMarkSize,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: tokens.znn.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                        child: Text(
                                          row.site.isEmpty
                                              ? '?'
                                              : String.fromCharCode(
                                                  row.site.runes.first,
                                                ).toUpperCase(),
                                          style: tokens.ledgerText.copyWith(
                                            color: tokens.znnInk,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: tokens.fieldLabelGap),
                                      Expanded(
                                        child: Tooltip(
                                          message: row.site,
                                          child: Text(
                                            row.site.isEmpty
                                                ? context
                                                      .l10n
                                                      .appsSettingsUnknown
                                                : row.site,
                                            overflow: TextOverflow.ellipsis,
                                            style: tokens.bodyText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  _AppsAccounts(
                                    accounts: row.accounts,
                                    labels: snapshot.labels,
                                  ),
                                  Text(
                                    context.l10n.appsSettingsUnknown,
                                    style: tokens.captionText,
                                  ),
                                  Text(switch (row.kind) {
                                    AppsConnectionKind.webApp =>
                                      context.l10n.appsSettingsWebApp,
                                    AppsConnectionKind.link =>
                                      context.l10n.appsSettingsLink,
                                    AppsConnectionKind.walletConnect =>
                                      context.l10n.appsSettingsWalletConnect,
                                  }, style: tokens.captionText),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: _AppsButton(
                                      key: Key('apps_disconnect_$index'),
                                      label:
                                          context.l10n.appsSettingsDisconnect,
                                      onPressed: enabled
                                          ? () => disconnect(row)
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppsColumns extends StatelessWidget {
  const _AppsColumns({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (int index = 0; index < children.length; index++)
        Expanded(
          flex: const <int>[3, 2, 2, 2, 2][index],
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: index == children.length - 1
                  ? 0
                  : AppTokens.of(context).fieldLabelGap,
            ),
            child: children[index],
          ),
        ),
    ],
  );
}

class _AppsAccounts extends StatelessWidget {
  const _AppsAccounts({required this.accounts, required this.labels});
  final List<String> accounts;
  final Map<String, String> labels;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (accounts.isEmpty)
        Text(
          context.l10n.appsSettingsUnknown,
          style: AppTokens.of(context).dataText,
        ),
      for (final String account in accounts)
        Tooltip(
          message: account,
          child: Text(
            _label(account),
            overflow: TextOverflow.ellipsis,
            style: AppTokens.of(context).dataText,
          ),
        ),
    ],
  );
  String _label(String account) {
    return labels[account] ?? _short(account);
  }
}

class _WalletConnectDetails extends StatelessWidget {
  const _WalletConnectDetails({
    required this.snapshot,
    required this.enabled,
    required this.disconnectPairing,
  });
  final AppsSnapshot snapshot;
  final bool enabled;
  final ValueChanged<AppsPairing> disconnectPairing;
  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: tokens.settingsRowPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(context.l10n.appsSettingsSessions, style: tokens.headingText),
          for (final AppsConnection row in snapshot.connections)
            if (row.kind == AppsConnectionKind.walletConnect)
              _SessionDetails(row: row),
          if (snapshot.sessionCount == 0)
            QuietNote(context.l10n.appsSettingsNone),
          Divider(color: tokens.line),
          Text(context.l10n.appsSettingsPairings, style: tokens.headingText),
          if (snapshot.pairings.isEmpty)
            QuietNote(context.l10n.appsSettingsNone),
          for (int index = 0; index < snapshot.pairings.length; index++)
            SettingRow(
              label: snapshot.pairings[index].site.isEmpty
                  ? context.l10n.appsSettingsUnknown
                  : snapshot.pairings[index].site,
              hint: snapshot.pairings[index].url,
              below: Wrap(
                spacing: tokens.settingsActionGap,
                runSpacing: tokens.fieldLabelGap,
                children: <Widget>[
                  _Identifier(
                    label: context.l10n.appsSettingsPairing,
                    value: snapshot.pairings[index].topic,
                  ),
                  _Identifier(
                    label: context.l10n.appsSettingsExpires,
                    value: FormatUtils.formatDayMonthTime(
                      snapshot.pairings[index].expiry * 1000,
                    ),
                  ),
                  Text(
                    '${context.l10n.appsSettingsActive}: '
                    '${_yesNo(context, snapshot.pairings[index].active)}',
                    style: tokens.captionText,
                  ),
                ],
              ),
              trailing: _AppsButton(
                key: Key('apps_pairing_disconnect_$index'),
                label: context.l10n.appsSettingsDisconnectPairing,
                onPressed: enabled
                    ? () => disconnectPairing(snapshot.pairings[index])
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionDetails extends StatelessWidget {
  const _SessionDetails({required this.row});
  final AppsConnection row;
  @override
  Widget build(BuildContext context) => SettingRow(
    label: row.site.isEmpty ? context.l10n.appsSettingsUnknown : row.site,
    hint: row.url,
    below: Wrap(
      spacing: AppTokens.of(context).settingsActionGap,
      runSpacing: AppTokens.of(context).fieldLabelGap,
      children: <Widget>[
        _Identifier(
          label: context.l10n.appsSettingsSession,
          value: row.identity,
        ),
        if (row.pairingTopic != null)
          _Identifier(
            label: context.l10n.appsSettingsPairing,
            value: row.pairingTopic!,
          ),
        if (row.expiry != null)
          _Identifier(
            label: context.l10n.appsSettingsExpires,
            value: FormatUtils.formatDayMonthTime(row.expiry! * 1000),
          ),
        Text(
          '${context.l10n.appsSettingsAcknowledged}: '
          '${_yesNo(context, row.acknowledged == true)}',
          style: AppTokens.of(context).captionText,
        ),
      ],
    ),
  );
}

String _yesNo(BuildContext context, bool value) =>
    value ? context.l10n.commonYes : context.l10n.commonNo;

class _Identifier extends StatelessWidget {
  const _Identifier({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: value,
    child: Text(
      '$label: ${_short(value)}',
      style: AppTokens.of(
        context,
      ).dataText.copyWith(fontSize: 12, color: AppTokens.of(context).dim),
    ),
  );
}

class _AppsButton extends StatelessWidget {
  const _AppsButton({
    required this.label,
    this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.foreground,
        minimumSize: Size(0, tokens.nodeSettingsCompactButtonHeight),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.nodeSettingsCompactButtonInset,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: tokens.captionText.copyWith(color: tokens.foreground),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14),
            SizedBox(width: tokens.fieldLabelGap),
          ],
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

class _AppsPairDialog extends StatefulWidget {
  const _AppsPairDialog({
    required this.presenter,
    required this.isCurrent,
    required this.close,
  });
  final AppsSettingsPresenter presenter;
  final bool Function() isCurrent;
  final VoidCallback close;

  @override
  State<_AppsPairDialog> createState() => _AppsPairDialogState();
}

class _AppsPairDialogState extends State<_AppsPairDialog> {
  int _epoch = 0;
  late final AppsPairAdmission _admit = _pair;

  Future<void> _pair(Uri uri, bool Function() sourceIsCurrent) async {
    final AppsSettingsPresenter presenter = widget.presenter;
    final bool Function() isCurrent = widget.isCurrent;
    final VoidCallback close = widget.close;
    final int epoch = _epoch;
    bool revoked = false;
    bool owns() =>
        !revoked &&
        !(revoked =
            !mounted || epoch != _epoch || !isCurrent() || !sourceIsCurrent());
    if (!owns()) throw StateError('Connection unavailable');
    final AppsActionOutcome outcome = await presenter.run(
      (AppsSettingsBinding binding) => binding.pair(uri, owns),
      owns,
    );
    if (outcome.status != AppsActionStatus.completed) {
      throw StateError('Connection unavailable');
    }
    if (owns()) close();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('apps_pair_dialog'),
    title: Text(context.l10n.appsSettingsConnectByLink),
    content: SizedBox(
      width: AppTokens.of(context).appsSettingsTableMinWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WalletConnectUriCard(
            onPair: _admit,
            isCurrent: widget.isCurrent,
            incomingLink: widget.presenter.binding?.incomingLink,
          ),
          SizedBox(height: AppTokens.of(context).appsSettingsGap),
          Wrap(
            spacing: AppTokens.of(context).settingsActionGap,
            runSpacing: AppTokens.of(context).fieldLabelGap,
            children: <Widget>[
              WalletConnectQrCard(onPair: _admit, isCurrent: widget.isCurrent),
              WalletConnectCameraCard(
                onPair: _admit,
                isCurrent: widget.isCurrent,
              ),
            ],
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: widget.isCurrent() ? widget.close : null,
        child: Text(context.l10n.commonClose),
      ),
    ],
  );

  @override
  void didUpdateWidget(_AppsPairDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter) ||
        !identical(oldWidget.isCurrent, widget.isCurrent)) {
      _epoch++;
    }
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }
}

String _short(String value) => value.length <= 20
    ? value
    : '${value.substring(0, 10)}…${value.substring(value.length - 8)}';
