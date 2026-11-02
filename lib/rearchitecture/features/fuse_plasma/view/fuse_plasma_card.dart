import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/view/fuse_plasma_form.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_fuse_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Fuses QSR from the selected address for a captured wallet beneficiary or
/// an address entered by the user.
class FusePlasmaCard extends StatelessWidget {
  /// Uses the real balance provider and retains one form for its exact owner.
  const FusePlasmaCard({
    required this.onPlasmaFused,
    this.isCurrent,
    this.bloc,
    this.ownerAddress,
    this.beneficiaries,
    this.captureSession,
    this.refreshBalances,
    super.key,
  });

  /// Reloads the original owner's page after an accepted original result.
  final VoidCallback onPlasmaFused;

  /// An externally owned adapter allows an offline owning-card regression.
  final FusePlasmaBloc? bloc;

  /// An explicitly captured owner; production otherwise reads selection.
  final String? ownerAddress;

  /// Captured wallet choices; an absent injection uses the real wallet list.
  final List<FusePlasmaBeneficiary>? beneficiaries;

  /// Captures an original session without substituting a failed injection.
  final PlasmaSession? Function(String owner)? captureSession;

  /// An optional owned refresh boundary, independent of global service lookup.
  final VoidCallback? refreshBalances;

  /// Includes the page visibility and the opening of the form that admitted
  /// the action. Closing either surface revokes its old callbacks.
  final bool Function()? isCurrent;

  @override
  Widget build(BuildContext context) {
    if (ownerAddress == null) {
      context.watch<SelectedAddressNotifier>();
    }
    final String? owner = ownerAddress ?? kSelectedAddress;
    final Widget view = _View(
      key: ValueKey<String?>(owner),
      owner: owner,
      onPlasmaFused: onPlasmaFused,
      isCurrent: isCurrent,
      beneficiaries: beneficiaries,
      captureSession: captureSession,
      refreshBalances: refreshBalances ?? _fetchBalance,
    );
    final FusePlasmaBloc? supplied = bloc;
    return supplied != null
        ? BlocProvider<FusePlasmaBloc>.value(value: supplied, child: view)
        : BlocProvider<FusePlasmaBloc>(
            create: (_) => FusePlasmaBloc(
              accountBlockUtils: AccountBlockUtils(),
              zenon: zenon!,
              zenonAddressUtils: ZenonAddressUtils(),
              sender: context.read<SendTransactionBloc>(),
            ),
            child: view,
          );
  }
}

class _View extends StatefulWidget {
  const _View({
    required this.owner,
    required this.onPlasmaFused,
    required this.isCurrent,
    required this.beneficiaries,
    required this.captureSession,
    required this.refreshBalances,
    super.key,
  });
  final String? owner;
  final VoidCallback onPlasmaFused;
  final bool Function()? isCurrent;
  final List<FusePlasmaBeneficiary>? beneficiaries;
  final PlasmaSession? Function(String owner)? captureSession;
  final VoidCallback refreshBalances;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  AccountInfo? _retained;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: BlocBuilder<MultipleBalanceBloc, MultipleBalanceState>(
        builder: (_, MultipleBalanceState state) {
          final String? owner = widget.owner;
          final AccountInfo? accountInfo = state.data?[owner];
          final BigInt? available = owner == null
              ? null
              : plasmaAvailableQsr(state, owner);
          if (accountInfo != null && available != null) {
            _retained = AccountInfo.fromJson(accountInfo.toJson());
          }
          final AccountInfo? retained = _retained;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              StateSwitcher(
                child: retained != null && owner != null
                    ? _Populated(
                        key: const ValueKey<String>('form'),
                        owner: owner,
                        accountInfo: retained,
                        onPlasmaFused: widget.onPlasmaFused,
                        isCurrent: widget.isCurrent,
                        beneficiaries: widget.beneficiaries,
                        captureSession: widget.captureSession,
                        refreshBalances: widget.refreshBalances,
                      )
                    : const _Loading(key: ValueKey<String>('loading')),
              ),
              if (state.status == MultipleBalanceStatus.failure)
                CardNote.error(state.error ?? FailureException()),
            ],
          );
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    Widget field() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Skeleton(width: 48),
        SizedBox(height: tokens.transferRecentGap),
        Skeleton(height: tokens.fieldHeight, radius: tokens.cardRadius),
      ],
    );
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: tokens.plasmaFuseFormPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(flex: 10, child: field()),
                SizedBox(width: tokens.pageGap),
                Expanded(flex: 14, child: field()),
                SizedBox(width: tokens.pageGap),
                Skeleton(
                  width: 104,
                  height: tokens.plasmaFuseActionHeight,
                  radius: tokens.pillRadius,
                ),
              ],
            ),
          ),
          Padding(
            padding: tokens.plasmaFuseNotePadding,
            child: const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Skeleton(width: 220),
            ),
          ),
        ],
      ),
    );
  }
}

void _fetchBalance() {
  sl.get<MultipleBalanceBloc>().add(
    MultipleBalanceFetch(
      addresses: kDefaultAddressList.map((String? e) => e!).toList(),
    ),
  );
}

class _Populated extends StatefulWidget {
  const _Populated({
    required this.owner,
    required this.accountInfo,
    required this.onPlasmaFused,
    required this.isCurrent,
    required this.beneficiaries,
    required this.captureSession,
    required this.refreshBalances,
    super.key,
  });
  final String owner;
  final AccountInfo accountInfo;
  final VoidCallback onPlasmaFused;
  final bool Function()? isCurrent;
  final List<FusePlasmaBeneficiary>? beneficiaries;
  final PlasmaSession? Function(String owner)? captureSession;
  final VoidCallback refreshBalances;

  @override
  State<_Populated> createState() => _PopulatedState();
}

class _PopulatedState extends State<_Populated> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _beneficiaryController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  final GlobalKey<LoadingButtonState> _fuseButtonKey = GlobalKey();
  late final List<FusePlasmaBeneficiary> _beneficiaries;
  late final SendTransactionBloc _sender;
  late final PlasmaSession? _session;
  late final Listenable _formChanges;
  PlasmaFuseDraft? _draft;
  int _draftEpoch = 0;
  bool _submitting = false;
  String? _submittedAmount;
  String? _submittedBeneficiary;
  PlasmaSession? _submittedSession;
  bool Function()? _submittedAuthority;

  late final Listenable _inputs = Listenable.merge(<Listenable>[
    _amountController,
    _beneficiaryController,
  ]);

  BigInt get _maxQsrAmount =>
      widget.accountInfo.getBalance(kQsrCoin.tokenStandard);
  String get _amount => _amountController.text;
  String get _beneficiary => _beneficiaryController.text;
  BigInt? get _rawAmount => parsePlasmaQsr(_amount);

  String? get _amountError => _amount.isEmpty
      ? null
      : _rawAmount == null
      ? context.l10n.validatorInvalidAmount
      : InputValidators.correctValue(
          _amount,
          _maxQsrAmount,
          kQsrCoin.decimals,
          fuseMinQsrAmount,
          canBeEqualToMin: true,
        );

  String? get _beneficiaryError =>
      _beneficiary.isEmpty ? null : InputValidators.checkAddress(_beneficiary);

  bool get _isInputValid =>
      (widget.isCurrent?.call() ?? true) &&
      _session != null &&
      PlasmaFusePublisher.allowsDraft(_sender, _session, _draft) &&
      _amount.isNotEmpty &&
      _amountError == null &&
      _beneficiary.isNotEmpty &&
      _beneficiaryError == null;

  @override
  void initState() {
    super.initState();
    _sender = context.read<SendTransactionBloc>();
    final PlasmaSession? Function(String owner)? capture =
        widget.captureSession;
    if (capture != null) {
      _session = capture(widget.owner);
    } else {
      final WalletActionContext? action = WalletActionContext.capture(
        widget.owner,
      );
      _session = action == null ? null : PlasmaSession.wallet(action);
    }
    final PlasmaSession? session = _session;
    _formChanges = Listenable.merge(<Listenable>[
      _inputs,
      if (session != null) PlasmaFusePublisher.changesFor(_sender, session),
      if (session != null && session.confirmationChanges != null)
        session.confirmationChanges!,
    ]);
    // This is the wallet's existing catalog, not a lookup or a proposed
    // address. The captured wallet action separately binds its lifetime.
    _beneficiaries = List<FusePlasmaBeneficiary>.unmodifiable(
      widget.beneficiaries ??
          <FusePlasmaBeneficiary>[
            for (final String address
                in kDefaultAddressList.whereType<String>().toSet())
              FusePlasmaBeneficiary(
                address: address,
                label:
                    kAddressLabelMap[address] ??
                    Address.parse(address).toShortString(),
                isAddress: !kAddressLabelMap.containsKey(address),
              ),
          ],
    );
    _beneficiaryController
      ..text = context.read<PlasmaBeneficiaryAddressCubit>().state ?? ''
      ..addListener(_onBeneficiaryTyped);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _beneficiaryController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool Function()? authority = widget.isCurrent;
    final int draftEpoch = _draftEpoch;
    bool current() =>
        mounted && draftEpoch == _draftEpoch && (authority?.call() ?? true);
    return MultiBlocListener(
      listeners: <BlocListener<dynamic, dynamic>>[
        BlocListener<FusePlasmaBloc, FusePlasmaState>(
          listener: (_, FusePlasmaState state) => _onFuseStateChanged(state),
        ),
        BlocListener<PlasmaBeneficiaryAddressCubit, String?>(
          listener: (_, String? address) => _onBeneficiaryPicked(address),
        ),
      ],
      child: ListenableBuilder(
        listenable: _formChanges,
        builder: (_, _) {
          final PlasmaSession? session = _session;
          final bool held =
              session != null &&
              PlasmaFusePublisher.heldOutcome(_sender, session) != null &&
              !PlasmaFusePublisher.allowsDraft(_sender, session, _draft);
          return FusePlasmaForm(
            amountController: _amountController,
            beneficiaryController: _beneficiaryController,
            amountFocusNode: _amountFocusNode,
            buttonKey: _fuseButtonKey,
            beneficiaries: _beneficiaries,
            amount: _rawAmount ?? BigInt.zero,
            decimals: kQsrCoin.decimals,
            amountEnabled: _maxQsrAmount > BigInt.zero,
            inputValid: _isInputValid,
            amountError: _amountError,
            beneficiaryError: _beneficiaryError,
            isCurrent: current,
            onMax: _onMaxPressed,
            onSubmit: () => _onFusePressed(draftEpoch, current),
            showAnother: held,
            onAnother:
                held &&
                    current() &&
                    PlasmaFusePublisher.canRearm(_sender, session)
                ? () => _onAnother(draftEpoch, current)
                : null,
          );
        },
      ),
    );
  }

  void _onFusePressed(int epoch, bool Function() authority) {
    final FusePlasmaBloc bloc = context.read<FusePlasmaBloc>();
    // Enter and retained button callbacks share the same admission guard.
    if (!_isInputValid ||
        _submitting ||
        bloc.state is FusePlasmaLoading ||
        epoch != _draftEpoch ||
        !authority()) {
      return;
    }
    final PlasmaSession? session = _session;
    if (session == null || session.address != widget.owner) return;
    _draft ??= PlasmaFusePublisher.beginDraft(
      sender: _sender,
      session: session,
      isCurrent: authority,
    );
    if (_draft == null) return;
    _submitting = true;
    _submittedAmount = _amount;
    _submittedBeneficiary = _beneficiary;
    _submittedSession = session;
    _submittedAuthority = authority;
    bloc.add(
      FusePlasmaRequested(
        beneficiaryAddress: _beneficiary,
        amount: _rawAmount!,
        session: session,
        draft: _draft,
        isCurrent: () =>
            mounted && identical(_submittedSession, session) && authority(),
      ),
    );
  }

  void _onAnother(int epoch, bool Function() authority) {
    final PlasmaSession? session = _session;
    if (session == null ||
        epoch != _draftEpoch ||
        !authority() ||
        !PlasmaFusePublisher.canRearm(_sender, session)) {
      return;
    }
    final bool Function()? opening = widget.isCurrent;
    _draftEpoch++;
    final int nextEpoch = _draftEpoch;
    final PlasmaFuseDraft? next = PlasmaFusePublisher.another(
      sender: _sender,
      session: session,
      isCurrent: () =>
          mounted && nextEpoch == _draftEpoch && (opening?.call() ?? true),
    );
    setState(() => _draft = next);
    if (next != null) {
      _amountController.clear();
      _amountFocusNode.requestFocus();
    }
  }

  void _onMaxPressed() {
    _amountController.text = _maxQsrAmount.addDecimals(coinDecimals);
  }

  void _onBeneficiaryTyped() {
    final PlasmaBeneficiaryAddressCubit cubit = context
        .read<PlasmaBeneficiaryAddressCubit>();
    final String? typed = _beneficiary.isEmpty ? null : _beneficiary;
    if (cubit.state != typed) cubit.changeAddress(typed);
  }

  void _onBeneficiaryPicked(String? address) {
    if (address == null || address == _beneficiary) return;
    _beneficiaryController.text = address;
  }

  void _onFuseStateChanged(FusePlasmaState state) {
    // A replacement owner cannot consume an old form's retained result.
    final PlasmaSession? session = _submittedSession;
    if (!_submitting || session == null) return;
    final bool Function()? authority = _submittedAuthority;
    bool effectsCurrent() =>
        mounted && session.isCurrent && (authority?.call() ?? false);
    if (state is FusePlasmaLoading) {
      _fuseButtonKey.currentState?.animateForward();
    } else if (state is FusePlasmaDone) {
      final bool current = effectsCurrent();
      _submitting = false;
      _fuseButtonKey.currentState?.animateReverse();
      if (!current) return;
      if (_amount == _submittedAmount &&
          _beneficiary == _submittedBeneficiary) {
        _amountController.clear();
      }
      if (effectsCurrent()) widget.refreshBalances();
      if (effectsCurrent()) widget.onPlasmaFused();
    } else if (state is FusePlasmaFailure) {
      // Evaluate before a known refusal advances this form's own draft epoch.
      final bool current = effectsCurrent();
      setState(() {
        _submitting = false;
        if (state.outcome == null) {
          _draft = null;
          _draftEpoch++;
        }
      });
      _fuseButtonKey.currentState?.animateReverse();
      if (!current) return;
      unawaited(
        NotificationUtils.sendNotificationError(
          state.exception,
          context.l10n.errorGeneratingPlasma,
        ),
      );
    }
  }
}
