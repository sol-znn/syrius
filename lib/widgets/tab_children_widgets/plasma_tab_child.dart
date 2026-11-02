import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/view/fuse_plasma_disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Beneficiary Plasma at the left, owned fusions and their aggregate at right.
class PlasmaTabChild extends StatelessWidget {
  /// Creates a Plasma page scoped to the selected account and wallet revision.
  const PlasmaTabChild({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<SelectedAddressNotifier>();
    return ListenableBuilder(
      listenable: WalletContextRevision.changes,
      builder: (BuildContext context, _) => _buildScope(context),
    );
  }

  Widget _buildScope(BuildContext context) {
    final String? address = kSelectedAddress;
    final WalletActionContext? action = address == null
        ? null
        : WalletActionContext.capture(address);
    if (action == null) {
      return Center(child: Text(context.l10n.plasmaPageUnknown));
    }
    return _PlasmaPage(
      key: ValueKey<Object>((
        address,
        WalletContextRevision.value,
        kCurrentNode,
        getChainIdentifier(),
        action.client,
      )),
      session: PlasmaSession.wallet(action),
    );
  }
}

class _PlasmaPage extends StatefulWidget {
  const _PlasmaPage({required this.session, super.key});
  final PlasmaSession session;

  @override
  State<_PlasmaPage> createState() => _PlasmaPageState();
}

class _PlasmaPageState extends State<_PlasmaPage> {
  final DisclosureController _form = DisclosureController();
  final List<Timer> _followUp = <Timer>[];
  late final PlasmaOwnerController _owner;
  StreamSubscription<MultipleBalanceState>? _balances;
  bool _visible = true;
  int _visibilityEpoch = 0;

  bool get _current => mounted && _visible && widget.session.isCurrent;

  @override
  void initState() {
    super.initState();
    _owner = PlasmaOwnerController.retained(
      sender: context.read<SendTransactionBloc>(),
      address: widget.session.address,
      chainId: widget.session.chainId,
    );
    unawaited(_owner.load(widget.session));
    _balances = context.read<MultipleBalanceBloc>().stream.listen(
      (MultipleBalanceState state) {
        // The shell's ordinary Refresh already requests balances. Follow its
        // successful boundary without adding a second list or sender.
        if (state.status != MultipleBalanceStatus.success ||
            !_current ||
            _owner.busy ||
            _owner.questioning) {
          return;
        }
        final PlasmaSession? session = _captureSession();
        if (session != null) unawaited(_owner.load(session));
      },
    );
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
    _visibilityEpoch++;
    for (final Timer timer in _followUp) {
      timer.cancel();
    }
    unawaited(_balances?.cancel());
    _form.dispose();
    // The sender retains original admitted outcomes after this page leaves.
    super.dispose();
  }

  PlasmaSession? _captureSession() {
    if (!_current) return null;
    final WalletActionContext? action = WalletActionContext.capture(
      widget.session.address,
    );
    return action == null ? null : PlasmaSession.wallet(action);
  }

  /// Every timer keeps the original owner. Selection never redirects a read.
  void _submitted() {
    if (!_current) return;
    final PlasmaSession? session = _captureSession();
    if (session == null) return;
    final int epoch = _visibilityEpoch;
    void reload() {
      if (!_current || epoch != _visibilityEpoch || !session.isCurrent) return;
      unawaited(_owner.load(session));
      context.read<PlasmaStatsBloc>().add(const InfiniteListRequested());
    }

    for (final Timer timer in _followUp) {
      timer.cancel();
    }
    _followUp
      ..clear()
      ..addAll(kFusionsFollowUpDelays.map((Duration d) => Timer(d, reload)));
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // A later return to the page cannot revive this opening's authority.
    final int visibilityEpoch = _visibilityEpoch;
    return Row(
      key: const Key('plasma_screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: tokens.plasmaWellWidth,
          child: PlasmaStatsCard(
            version: PlasmaStatsWidgetVersion.plasmaTab,
            onAddressPicked: _form.open,
          ),
        ),
        SizedBox(width: tokens.pageGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PlasmaStrip(owner: _owner, form: _form),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: math.max(
                              0,
                              constraints.maxHeight -
                                  tokens.plasmaTableMinHeight,
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: FusePlasmaDisclosure(
                              key: const Key('plasma_fuse_disclosure'),
                              controller: _form,
                              isCurrent: () =>
                                  _current &&
                                  visibilityEpoch == _visibilityEpoch,
                              builder: (_, bool Function() isCurrent) =>
                                  FusePlasmaCard(
                                    onPlasmaFused: _submitted,
                                    isCurrent: isCurrent,
                                  ),
                            ),
                          ),
                        ),
                        SizedBox(height: tokens.pageGap),
                        Expanded(
                          child: FusedPlasmaCard(
                            owner: _owner,
                            captureSession: _captureSession,
                            isCurrent: () => _current,
                            onSubmitted: _submitted,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlasmaStrip extends StatelessWidget {
  const _PlasmaStrip({required this.owner, required this.form});
  final PlasmaOwnerController owner;
  final DisclosureController form;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MultipleBalanceBloc, MultipleBalanceState>(
      builder: (BuildContext context, MultipleBalanceState state) =>
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[owner, form]),
            builder: (BuildContext context, _) {
              final AppTokens tokens = AppTokens.of(context);
              final BigInt? available = plasmaAvailableQsr(
                state,
                owner.address,
              );
              final PlasmaOwnerRead? read = owner.read;
              Widget amount(BigInt? raw, String key) => ValueFlash(
                value: raw,
                color: tokens.qsrInk,
                child: HiddenAmount(
                  style: tokens.stripAmountText,
                  child: raw == null
                      ? Text(
                          context.l10n.plasmaPageUnknown,
                          key: ValueKey<String>(key),
                          style: tokens.dollarText,
                        )
                      : AmountText(
                          raw,
                          key: ValueKey<String>(key),
                          decimals: coinDecimals,
                          style: tokens.stripAmountText,
                          symbol: 'QSR',
                          symbolColor: tokens.qsrInk,
                        ),
                ),
              );
              return PageStrip(
                key: const Key('plasma_strip'),
                figures: <StripFigure>[
                  StripFigure(
                    label: context.l10n.cardAvailableLabel,
                    value: amount(available, 'plasma_qsr_available'),
                  ),
                  StripFigure(
                    label: context.l10n.plasmaPageFusedByYou,
                    value: amount(read?.total, 'plasma_qsr_owned'),
                    trailing: read == null
                        ? null
                        : Text(
                            context.l10n.plasmaPageEntries(read.count),
                            key: const Key('plasma_owned_entries'),
                            style: tokens.dollarText,
                          ),
                  ),
                ],
                actions: <Widget>[
                  if (form.isOpen)
                    OutlinedButton.icon(
                      key: const Key('plasma_close_fuse'),
                      style: cardSecondaryButtonStyle(context).copyWith(
                        minimumSize: WidgetStatePropertyAll<Size>(
                          Size(0, tokens.buttonHeight),
                        ),
                        padding:
                            const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                              EdgeInsets.symmetric(horizontal: 16),
                            ),
                        textStyle: const WidgetStatePropertyAll<TextStyle>(
                          kOutlinedButtonTextStyle,
                        ),
                      ),
                      onPressed: form.close,
                      icon: Icon(Icons.close, size: tokens.heroIconSize),
                      label: Text(context.l10n.commonClose),
                    )
                  else
                    PrimaryPill(
                      key: const Key('plasma_open_fuse'),
                      onPressed: form.open,
                      icon: Icon(
                        Icons.bolt_outlined,
                        size: tokens.heroIconSize,
                      ),
                      child: Text(context.l10n.fuse),
                    ),
                ],
              );
            },
          ),
    );
  }
}
