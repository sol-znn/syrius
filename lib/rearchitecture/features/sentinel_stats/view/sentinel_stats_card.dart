import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_owner_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillar_parts/pillar_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/view/sentinel_values.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The selected owner's facts and the existing Spawn and disassemble flows.
class SentinelStatsCard extends StatelessWidget {
  /// Reuses the page's exact completed owner read when one is supplied.
  const SentinelStatsCard({
    required this.onStepperNotificationSeeMorePressed,
    this.ownerReader,
    this.sender,
    this.stepperBuilderForTesting,
    super.key,
  });

  /// Preserves the existing stepper notification destination.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// The Nodes page retains this reader and its read identity.
  final SentinelsByOwnerBloc? ownerReader;

  /// The application sender shared with Transfer and collection.
  final SendTransactionBloc? sender;

  /// Replaces only the legacy stepper body in isolated publication tests.
  @visibleForTesting
  final Widget Function(AccountBlockUtils, Zenon)? stepperBuilderForTesting;

  @override
  Widget build(BuildContext context) {
    final Widget child = _View(
      sender: sender,
      stepperBuilderForTesting: stepperBuilderForTesting,
      onStepperNotificationSeeMorePressed: onStepperNotificationSeeMorePressed,
    );
    final SentinelsByOwnerBloc? reader = ownerReader;
    if (reader != null) {
      return BlocProvider<SentinelsByOwnerBloc>.value(
        value: reader,
        child: child,
      );
    }
    return BlocProvider<SentinelsByOwnerBloc>(
      create: (_) {
        final SentinelsByOwnerBloc reader = SentinelsByOwnerBloc(zenon: zenon!);
        final String? owner = kSelectedAddress;
        if (owner != null) {
          reader.add(FetchRequestData(address: Address.parse(owner)));
        }
        return reader;
      },
      child: child,
    );
  }
}

class _SpawnSnapshot {
  _SpawnSnapshot(this.reader, this.read, this.context, this.epoch);

  final SentinelsByOwnerBloc reader;
  final Object read;
  final WalletActionContext context;
  final int epoch;
  final Object? page = kCurrentPage;
  bool used = false;
  bool revoked = false;
}

class _View extends StatefulWidget {
  const _View({
    required this.onStepperNotificationSeeMorePressed,
    required this.sender,
    required this.stepperBuilderForTesting,
  });

  final VoidCallback onStepperNotificationSeeMorePressed;
  final SendTransactionBloc? sender;
  final Widget Function(AccountBlockUtils, Zenon)? stepperBuilderForTesting;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  int _epoch = 0;
  bool _visible = true;
  bool _stepperOpen = false;
  bool _opening = false;
  bool _disposed = false;
  Object? _copiedRead;
  late SentinelInfo _sentinel;
  ModalRoute<dynamic>? _pageRoute;
  MaterialPageRoute<void>? _stepperRoute;
  NavigatorState? _stepperNavigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (!identical(route, _pageRoute) ||
        _visible && !visible && !_stepperOpen) {
      _epoch++;
    }
    _pageRoute = route;
    _visible = visible;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }

  void _refresh() {
    if (!mounted || _opening || !_visible) return;
    final String? owner = kSelectedAddress;
    if (owner == null) return;
    context.read<SentinelsByOwnerBloc>().add(
      FetchRequestData(address: Address.parse(owner)),
    );
  }

  bool _current(_SpawnSnapshot snapshot) {
    if (snapshot.revoked) return false;
    if (!mounted ||
        _disposed ||
        snapshot.epoch != _epoch ||
        snapshot.page != kCurrentPage ||
        !snapshot.context.isCurrent ||
        !snapshot.reader.ownsRead(
          snapshot.read,
          snapshot.context.ownerAddress,
        ) ||
        !identical(snapshot.reader, context.read<SentinelsByOwnerBloc>()) ||
        !(_pageRoute?.isActive ?? true)) {
      snapshot.revoked = true;
      return false;
    }
    final FetchState<List<SentinelInfo>> state = snapshot.reader.state;
    if (state is! FetchPopulated<List<SentinelInfo>> || state.data.isNotEmpty) {
      snapshot.revoked = true;
      return false;
    }
    if (_stepperOpen) {
      final MaterialPageRoute<void>? route = _stepperRoute;
      final bool valid =
          route != null &&
          identical(route.navigator, _stepperNavigator) &&
          route.isCurrent;
      if (!valid) snapshot.revoked = true;
      return valid;
    }
    final bool valid = _visible && (_pageRoute?.isCurrent ?? true);
    if (!valid) snapshot.revoked = true;
    return valid;
  }

  Future<bool> _verifyEmpty(_SpawnSnapshot snapshot) async {
    if (!_current(snapshot)) return false;
    final SentinelInfo? actual = await snapshot.context.client.embedded.sentinel
        .getByOwner(Address.parse(snapshot.context.ownerAddress));
    return _current(snapshot) && actual == null;
  }

  Future<void> _spawn(
    _SpawnSnapshot snapshot,
    SendTransactionBloc sender,
  ) async {
    if (snapshot.used || _opening || sender.busy.value || !_current(snapshot)) {
      return;
    }
    snapshot.used = true;
    final NavigatorState navigator = Navigator.of(context);
    final NodeOwnerPublisher publisher = NodeOwnerPublisher(
      sender: sender,
      context: snapshot.context,
      verifyOwner: () => _verifyEmpty(snapshot),
      isCurrent: () => _current(snapshot),
    );
    final MaterialPageRoute<void> route = MaterialPageRoute<void>(
      builder: (_) =>
          widget.stepperBuilderForTesting?.call(
            publisher,
            snapshot.context.client,
          ) ??
          StepperScreen(
            stepper: CreateSentinelStepperPage(
              accountBlockUtils: publisher,
              client: snapshot.context.client,
            ),
            onStepperNotificationSeeMorePressed:
                widget.onStepperNotificationSeeMorePressed,
          ),
    );
    _stepperRoute = route;
    _stepperNavigator = navigator;
    _stepperOpen = true;
    setState(() => _opening = true);
    try {
      await navigator.push<void>(route);
    } finally {
      _stepperOpen = false;
      _stepperRoute = null;
      _stepperNavigator = null;
      _epoch++;
      if (mounted && !_disposed) {
        setState(() => _opening = false);
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          if (mounted &&
              snapshot.context.isCurrent &&
              snapshot.reader.ownsRead(
                snapshot.read,
                snapshot.context.ownerAddress,
              ) &&
              (_pageRoute?.isCurrent ?? true)) {
            _refresh();
          }
        });
      }
    }
  }

  Widget _buildState(SentinelsByOwnerBloc reader) {
    final String? owner = kSelectedAddress;
    final FetchState<List<SentinelInfo>> state = reader.state;
    final AppTokens tokens = AppTokens.of(context);
    if (owner == null ||
        state is FetchInitial<List<SentinelInfo>> ||
        !reader.isCurrentFor(owner)) {
      return const SkeletonRows();
    }
    if (state is! FetchPopulated<List<SentinelInfo>>) {
      return Text(context.l10n.nodesUnavailable, style: tokens.compactText);
    }
    final Object? read = reader.readOwner;
    if (state.data.isEmpty && read != null) {
      final WalletActionContext? captured = WalletActionContext.capture(owner);
      final _SpawnSnapshot? snapshot = captured == null
          ? null
          : _SpawnSnapshot(reader, read, captured, _epoch);
      final SendTransactionBloc sender =
          widget.sender ?? context.read<SendTransactionBloc>();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(context.l10n.nodesNoneYet, style: tokens.compactText),
          SizedBox(height: tokens.cardGap),
          ValueListenableBuilder<bool>(
            valueListenable: sender.busy,
            builder: (_, bool busy, _) => OutlinedButton.icon(
              key: const Key('sentinel_owner_spawn'),
              onPressed:
                  !busy && !_opening && snapshot != null && _current(snapshot)
                  ? () => unawaited(_spawn(snapshot, sender))
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.spawn),
            ),
          ),
        ],
      );
    }
    final SentinelInfo? actual = state.data
        .where((SentinelInfo item) => item.owner.toString() == owner)
        .firstOrNull;
    if (actual == null || state.data.length != 1) {
      return Text(context.l10n.nodesUnavailable, style: tokens.compactText);
    }
    if (!identical(read, _copiedRead)) {
      _copiedRead = read;
      _sentinel = SentinelInfo.fromJson(actual.toJson());
    }
    final SentinelInfo sentinel = _sentinel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Fact(
          label: context.l10n.nodesOwner,
          value: SentinelOwnerText(
            key: const Key('sentinel_owner_address'),
            address: sentinel.owner.toString(),
          ),
        ),
        SizedBox(height: tokens.cardGap),
        _Fact(
          label: context.l10n.nodesStatus,
          value: SentinelStatusChip(active: sentinel.active, compact: true),
        ),
        SizedBox(height: tokens.cardGap),
        _Fact(
          label: context.l10n.nodesRegistered,
          value: SentinelRegistrationTime(
            timestamp: sentinel.registrationTimestamp,
          ),
        ),
        if (sentinel.active) ...<Widget>[
          SizedBox(height: tokens.cardGap),
          _Fact(
            label: context.l10n.nodesRevocable,
            value: SentinelRevocationTime(
              key: ValueKey<(String, Object?)>(('clock', read)),
              sentinel: sentinel,
              onRefresh: _refresh,
            ),
          ),
          SizedBox(height: tokens.cardGap),
          RevokeSentinelButton(
            key: ValueKey<(String, Object?)>(('revoke', read)),
            sentinel: sentinel,
            ownerReader: reader,
            sender: widget.sender,
            onRevoked: _refresh,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Panel(
      title: context.l10n.nodesYourSentinel,
      shrinkWrap: true,
      actions: <Widget>[RefreshButton(onPressed: _refresh)],
      child: Padding(
        padding: tokens.pillarOwnerPanelPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NodeObject.sentinel(size: tokens.pillarOwnerObjectSize),
            SizedBox(height: tokens.cardGap),
            BlocBuilder<SentinelsByOwnerBloc, FetchState<List<SentinelInfo>>>(
              builder: (_, _) =>
                  _buildState(context.read<SentinelsByOwnerBloc>()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: Text(label, style: AppTokens.of(context).compactText)),
      Flexible(child: value),
    ],
  );
}
