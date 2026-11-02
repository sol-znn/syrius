import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_owner_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/model/pillar_owner_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/view/pillar_owner_panel.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _OwnerAuthority {
  _OwnerAuthority(
    this.reader,
    this.read,
    this.context,
    this.pillar,
    this.boundary,
  );

  final PillarsByOwnerBloc reader;
  final Object read;
  final WalletActionContext context;
  final PillarInfo pillar;
  final DateTime? boundary;
  final Object? page = kCurrentPage;
}

/// Supplies facts and existing actions to the inline owner presentation.
class PillarOwnerCard extends StatefulWidget {
  /// The caller owns the panel's visibility and any notification navigation.
  const PillarOwnerCard({
    required this.onClose,
    required this.onStepperNotificationSeeMorePressed,
    this.nowForTesting,
    super.key,
  });

  /// Removes the panel without cancelling an admitted publication.
  final VoidCallback onClose;

  /// Retains the existing stepper notification destination.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// A deterministic clock shared by the root guard and its owner panel.
  @visibleForTesting
  final DateTime Function()? nowForTesting;

  @override
  State<PillarOwnerCard> createState() => _PillarOwnerCardState();
}

class _PillarOwnerCardState extends State<PillarOwnerCard> {
  _OwnerAuthority? _authority;
  PillarOwnerFact<BigInt> _deposit = const PillarOwnerFact<BigInt>.loading();
  PillarOwnerFact<BigInt> _cost = const PillarOwnerFact<BigInt>.loading();
  bool _deciding = false;
  bool _visible = true;
  bool _stepperOpen = false;
  int _epoch = 0;
  FrostedDialogRoute<String>? _qsrRoute;
  NavigatorState? _qsrNavigator;

  DateTime get _now => (widget.nowForTesting?.call() ?? DateTime.now()).toUtc();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (_visible && !visible && !_stepperOpen) {
      _epoch++;
      _dismissQsr();
    }
    _visible = visible;
  }

  void _dismissQsr() {
    final FrostedDialogRoute<String>? route = _qsrRoute;
    final NavigatorState? navigator = _qsrNavigator;
    _qsrRoute = null;
    _qsrNavigator = null;
    if (route == null || navigator == null) return;
    scheduleMicrotask(() {
      if (navigator.mounted &&
          identical(route.navigator, navigator) &&
          route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _epoch++;
    _dismissQsr();
    super.dispose();
  }

  bool _current(_OwnerAuthority authority) =>
      authority.context.isCurrent &&
      authority.page == kCurrentPage &&
      authority.reader.ownsRead(
        authority.read,
        authority.context.ownerAddress,
      );

  bool _visibleCurrent(PillarOwnerSnapshot snapshot) =>
      mounted &&
      TickerMode.valuesOf(context).enabled &&
      identical(_authority, snapshot.authority) &&
      _current(snapshot.authority as _OwnerAuthority);

  void _refresh() {
    if (!mounted || _deciding) return;
    final String? address = kSelectedAddress;
    if (address == null) return;
    context.read<PillarsByOwnerBloc>().add(
      FetchRequestData(address: Address.parse(address)),
    );
  }

  void _capture(PillarsByOwnerBloc reader, PillarInfo pillar) {
    final Object? read = reader.readOwner;
    if (read == null || identical(read, _authority?.read)) return;
    final WalletActionContext? owner = WalletActionContext.capture(
      pillar.ownerAddress.toString(),
    );
    if (owner == null) return;
    final PillarInfo copy = PillarInfo.fromJson(pillar.toJson());
    final _OwnerAuthority authority = _OwnerAuthority(
      reader,
      read,
      owner,
      copy,
      copy.revokeCooldown > 0
          ? _now.add(Duration(seconds: copy.revokeCooldown))
          : null,
    );
    _authority = authority;
    _deposit = const PillarOwnerFact<BigInt>.loading();
    _cost = const PillarOwnerFact<BigInt>.loading();
    unawaited(_readFact(authority, deposit: true));
    unawaited(_readFact(authority, deposit: false));
  }

  Future<void> _readFact(
    _OwnerAuthority authority, {
    required bool deposit,
  }) async {
    PillarOwnerFact<BigInt> fact;
    try {
      final BigInt amount = deposit
          ? await authority.context.client.embedded.pillar.getDepositedQsr(
              Address.parse(authority.context.ownerAddress),
            )
          : await authority.context.client.embedded.pillar
                .getQsrRegistrationCost();
      fact = amount >= BigInt.zero
          ? PillarOwnerFact<BigInt>.available(amount)
          : const PillarOwnerFact<BigInt>.unavailable();
    } on Object {
      fact = const PillarOwnerFact<BigInt>.unavailable();
    }
    if (!mounted || !identical(_authority, authority) || !_current(authority)) {
      return;
    }
    setState(() {
      if (deposit) {
        _deposit = fact;
      } else {
        _cost = fact;
      }
    });
  }

  PillarOwnerSnapshot _snapshot(_OwnerAuthority authority) {
    final PillarInfo pillar = authority.pillar;
    return (
      authority: authority,
      ownerAddress: authority.context.ownerAddress,
      name: pillar.name,
      producerAddress: pillar.producerAddress.toString(),
      rewardAddress: pillar.withdrawAddress.toString(),
      weight: pillar.weight,
      lockedZnn: null,
      depositedQsr: _deposit,
      registrationCostQsr: _cost,
      momentumRewardPercent: pillar.giveMomentumRewardPercentage,
      delegateRewardPercent: pillar.giveDelegateRewardPercentage,
      producedMomentums: pillar.producedMomentums,
      expectedMomentums: pillar.expectedMomentums,
      isRevocable: pillar.isRevocable,
      revocationBoundaryUtc: authority.boundary,
    );
  }

  Future<bool> _verify(_OwnerAuthority authority, {bool revoke = false}) async {
    if (!_current(authority)) return false;
    final List<PillarInfo> rows = await authority.context.client.embedded.pillar
        .getByOwner(
          Address.parse(authority.context.ownerAddress),
        );
    if (!_current(authority)) return false;
    return rows.any(
      (PillarInfo row) =>
          row.ownerAddress.toString() == authority.context.ownerAddress &&
          row.name == authority.pillar.name &&
          (!revoke || row.isRevocable),
    );
  }

  NodeOwnerPublisher _publisher(
    _OwnerAuthority authority, {
    bool revoke = false,
    BigInt? withdrawDeposit,
  }) {
    final int epoch = _epoch;
    return NodeOwnerPublisher(
      sender: context.read<SendTransactionBloc>(),
      context: authority.context,
      verifyOwner: () async {
        if (!await _verify(authority, revoke: revoke)) return false;
        if (withdrawDeposit == null) return true;
        final BigInt currentDeposit = await authority
            .context
            .client
            .embedded
            .pillar
            .getDepositedQsr(
              Address.parse(authority.context.ownerAddress),
            );
        return _current(authority) && currentDeposit == withdrawDeposit;
      },
      // SDK preparation can outlast both questions and the captured window.
      isCurrent: () =>
          mounted &&
          epoch == _epoch &&
          (_visible || _stepperOpen) &&
          _current(authority) &&
          (!revoke || (authority.boundary?.isAfter(_now) ?? false)),
    );
  }

  Future<void> _act(
    PillarOwnerAction action,
    PillarOwnerSnapshot snapshot,
  ) async {
    if (_deciding || !_visibleCurrent(snapshot)) return;
    final SendTransactionBloc sender = context.read<SendTransactionBloc>();
    if (sender.busy.value) return;
    final _OwnerAuthority authority = snapshot.authority as _OwnerAuthority;
    setState(() => _deciding = true);
    try {
      switch (action) {
        case PillarOwnerAction.update:
          final NodeOwnerPublisher publisher = _publisher(authority);
          _stepperOpen = true;
          try {
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => StepperScreen(
                  stepper: UpdatePillarStepperPage(
                    pillarInfo: PillarInfo.fromJson(authority.pillar.toJson()),
                    accountBlockUtils: publisher,
                    client: authority.context.client,
                  ),
                  onStepperNotificationSeeMorePressed:
                      widget.onStepperNotificationSeeMorePressed,
                ),
              ),
            );
          } finally {
            _stepperOpen = false;
          }
        case PillarOwnerAction.depositQsr:
        case PillarOwnerAction.withdrawQsr:
          final bool withdraw = action == PillarOwnerAction.withdrawQsr;
          final BigInt? displayedDeposit = snapshot.depositedQsr.value;
          final int epoch = _epoch;
          final String? amount = await _askQsr(authority, withdraw: withdraw);
          if (!mounted ||
              !_visible ||
              epoch != _epoch ||
              !_current(authority) ||
              amount == null ||
              sender.busy.value) {
            return;
          }
          final BigInt? units = withdraw
              ? null
              : parseSendAmount(amount, kQsrCoin.decimals);
          if (!withdraw && units == null) return;
          if (withdraw && displayedDeposit == null) return;
          await _publisher(
            authority,
            withdrawDeposit: withdraw ? displayedDeposit : null,
          ).createAccountBlock(
            withdraw
                ? authority.context.client.embedded.pillar.withdrawQsr()
                : authority.context.client.embedded.pillar.depositQsr(units!),
            withdraw
                ? PlasmaPurpose.withdrawQsrFromPillarSlot.message
                : PlasmaPurpose.depositQsrForPillarSlot.message,
            address: Address.parse(authority.context.ownerAddress),
            waitForRequiredPlasma: true,
          );
        case PillarOwnerAction.revokeConfirmed:
          await _publisher(authority, revoke: true).createAccountBlock(
            authority.context.client.embedded.pillar.revoke(snapshot.name),
            PlasmaPurpose.disassemblePillar.message,
            address: Address.parse(snapshot.ownerAddress),
            waitForRequiredPlasma: true,
          );
      }
    } on Object {
      if (mounted && _current(authority)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.sendOutcomeUncertain)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deciding = false);
        if (_current(authority)) _refresh();
      }
    }
  }

  Future<void> _spawn(PillarsByOwnerBloc reader, String address) async {
    final FetchState<List<PillarInfo>> state = reader.state;
    final Object? read = reader.readOwner;
    final WalletActionContext? owner = WalletActionContext.capture(address);
    final SendTransactionBloc sender = context.read<SendTransactionBloc>();
    if (_deciding ||
        !_visible ||
        read == null ||
        owner == null ||
        sender.busy.value ||
        !reader.ownsRead(read, address) ||
        state is! FetchPopulated<List<PillarInfo>> ||
        state.data.isNotEmpty) {
      return;
    }
    final int epoch = _epoch;
    final Object? page = kCurrentPage;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        (_visible || _stepperOpen) &&
        page == kCurrentPage &&
        owner.isCurrent &&
        reader.ownsRead(read, address);
    final NodeOwnerPublisher publisher = NodeOwnerPublisher(
      sender: sender,
      context: owner,
      isCurrent: current,
      verifyOwner: () async {
        if (!current()) return false;
        final List<PillarInfo> rows = await owner.client.embedded.pillar
            .getByOwner(Address.parse(address));
        return current() && rows.isEmpty;
      },
    );
    setState(() => _deciding = true);
    _stepperOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StepperScreen(
            stepper: CreatePillarStepperPage(
              accountBlockUtils: publisher,
              client: owner.client,
            ),
            onStepperNotificationSeeMorePressed:
                widget.onStepperNotificationSeeMorePressed,
          ),
        ),
      );
    } finally {
      _stepperOpen = false;
      if (mounted) {
        setState(() => _deciding = false);
        if (owner.isCurrent) _refresh();
      }
    }
  }

  Future<String?> _askQsr(
    _OwnerAuthority authority, {
    required bool withdraw,
  }) async {
    final BigInt? deposit = _deposit.value;
    if (withdraw && deposit == null) return null;
    final TextEditingController amount = TextEditingController();
    final int epoch = _epoch;
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    bool decided = false;
    late final FrostedDialogRoute<String> route;
    route = FrostedDialogRoute<String>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (BuildContext dialog, _, _) => themes.wrap(
        Builder(
          builder: (BuildContext dialog) {
            bool canConfirm() =>
                mounted &&
                _visible &&
                epoch == _epoch &&
                identical(_qsrRoute, route) &&
                _current(authority);
            void decide(String? value) {
              if (decided ||
                  !dialog.mounted ||
                  !route.isCurrent ||
                  !identical(route.navigator, navigator)) {
                return;
              }
              if (value != null &&
                  (!canConfirm() ||
                      !withdraw &&
                          parseSendAmount(value, kQsrCoin.decimals) == null)) {
                return;
              }
              decided = true;
              navigator.pop(value);
            }

            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: amount,
              builder: (_, TextEditingValue value, _) => DialogCard(
                title: withdraw
                    ? dialog.l10n.pillarOwnerWithdrawQsr
                    : dialog.l10n.pillarOwnerDepositQsr,
                body: withdraw
                    ? HiddenAmount(
                        child: Ltr(
                          child: AmountText(
                            deposit!,
                            decimals: kQsrCoin.decimals,
                            symbol: kQsrCoin.symbol,
                            style: AppTokens.of(dialog).dataText,
                          ),
                        ),
                      )
                    : TextField(
                        key: const Key('pillar_owner_qsr_amount'),
                        controller: amount,
                        textDirection: TextDirection.ltr,
                        style: AppTokens.of(dialog).transferAmountText,
                        decoration: InputDecoration(
                          labelText: dialog.l10n.amount,
                          suffixText: 'QSR',
                        ),
                        onSubmitted: decide,
                      ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => decide(null),
                    child: Text(dialog.l10n.cancel),
                  ),
                  TextButton(
                    key: const Key('pillar_owner_qsr_confirm'),
                    onPressed:
                        canConfirm() &&
                            (withdraw ||
                                parseSendAmount(
                                      value.text,
                                      kQsrCoin.decimals,
                                    ) !=
                                    null)
                        ? () => decide(withdraw ? '' : value.text)
                        : null,
                    child: Text(
                      withdraw
                          ? dialog.l10n.pillarOwnerWithdrawQsr
                          : dialog.l10n.pillarOwnerDepositQsr,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    _qsrRoute = route;
    _qsrNavigator = navigator;
    try {
      return await navigator.push<String>(route);
    } finally {
      decided = true;
      if (identical(_qsrRoute, route)) {
        _qsrRoute = null;
        _qsrNavigator = null;
      }
      await route.completed;
      amount.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PillarsByOwnerBloc reader = context.watch<PillarsByOwnerBloc>();
    final String? selected = kSelectedAddress;
    final FetchState<List<PillarInfo>> state = reader.state;
    final AppTokens tokens = AppTokens.of(context);
    if (selected != null &&
        reader.isCurrentFor(selected) &&
        state is FetchPopulated<List<PillarInfo>> &&
        state.data.isNotEmpty) {
      _capture(reader, state.data.first);
      final _OwnerAuthority? authority = _authority;
      if (authority != null && _current(authority)) {
        return ValueListenableBuilder<bool>(
          valueListenable: context.read<SendTransactionBloc>().busy,
          builder: (_, bool busy, _) => PillarOwnerPanel(
            snapshot: _snapshot(authority),
            busy: busy || _deciding,
            enabledActions: <PillarOwnerAction>{
              PillarOwnerAction.update,
              PillarOwnerAction.depositQsr,
              if (_deposit.value != null && _deposit.value! > BigInt.zero)
                PillarOwnerAction.withdrawQsr,
              if (authority.pillar.isRevocable)
                PillarOwnerAction.revokeConfirmed,
            },
            stillCurrent: _visibleCurrent,
            onAction: _act,
            onClose: widget.onClose,
            onRefresh: _refresh,
            nowForTesting: widget.nowForTesting,
          ),
        );
      }
    }
    return Panel(
      title: context.l10n.nodesYourPillar,
      shrinkWrap: true,
      actions: <Widget>[
        RefreshButton(onPressed: _refresh),
        TextButton(
          onPressed: widget.onClose,
          child: Text(context.l10n.commonClose),
        ),
      ],
      child: Padding(
        padding: tokens.pillarOwnerPanelPadding,
        child:
            state is FetchInitial<List<PillarInfo>> ||
                selected == null ||
                !reader.isCurrentFor(selected)
            ? const SkeletonRows(rows: 2)
            : state is FetchPopulated<List<PillarInfo>> && state.data.isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(context.l10n.nodesNoneYet),
                  SizedBox(height: tokens.cardGap),
                  OutlinedButton.icon(
                    key: const Key('nodes_spawn_pillar'),
                    onPressed: _deciding
                        ? null
                        : () => _spawn(reader, selected),
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.spawn),
                  ),
                ],
              )
            : Text(context.l10n.nodesUnavailable),
      ),
    );
  }
}
