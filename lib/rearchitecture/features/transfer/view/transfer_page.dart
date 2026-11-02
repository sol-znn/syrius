import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/receive_header_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/zap/zap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'transfer_pending.dart';
part 'transfer_header.dart';

/// The actions the shared transfer card can show.
enum TransferMode {
  /// Send through the existing transaction flow.
  send,

  /// Display an address and request funds.
  receive,

  /// The drawn Zap entry, held by its missing-service seam.
  zap,
}

/// Keeps Transfer's mode above a page switch, without persisting wallet data.
class TransferController extends ValueNotifier<TransferMode> {
  /// Starts in Send unless the session selected another mode.
  TransferController([super._value = TransferMode.send]);

  VoidCallback? _refresh;

  /// Refreshes the mounted mode through its existing live bloc.
  ///
  /// A hidden page has no callback. Zap has no service to refresh.
  void refresh() => _refresh?.call();
}

/// One centered card whose modes keep their fields while another is shown.
class TransferPage extends StatefulWidget {
  /// Creates the page from the wallet blocs already provided by the shell.
  const TransferPage({
    this.controller,
    this.receiveWorker,
    this.priceFeed,
    this.zapDraft,
    super.key,
  });

  /// The mode retained by the session. Owned here when omitted.
  final TransferController? controller;

  /// The wallet's existing worker; injectable without a node in widget tests.
  final AutoReceiveTxWorker? receiveWorker;

  /// Shared in production and injectable without external requests in tests.
  final PriceFeed? priceFeed;

  /// The shell owns production drafts and clears them when the wallet locks.
  final ZapDraftCubit? zapDraft;

  /// The mockup's width, constrained further by a smaller viewport.
  static const double cardWidth = 640;

  /// Mode content fades in place while every form stays mounted.
  static const Duration modeDuration = Duration(milliseconds: 260);

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  late TransferController _controller;
  late bool _ownsController;
  late ZapDraftCubit _zapDraft;
  late bool _ownsZapDraft;
  final ReceiveHeaderController _receiveHeader = ReceiveHeaderController();
  int _receiveEpoch = 0;

  @override
  void initState() {
    super.initState();
    _attachController(TransferMode.send);
    _attachZapDraft();
    _refreshMissingMembers();
  }

  void _refreshMissingMembers() {
    final MultipleBalanceBloc balances = context.read<MultipleBalanceBloc>();
    final MultipleBalanceState state = balances.state;
    final List<String> members =
        kDefaultAddressList.whereType<String>().toList();
    if (state.status == MultipleBalanceStatus.success &&
        members.any((String address) =>
            !(state.data?.containsKey(address) ?? false))) {
      balances.add(MultipleBalanceFetch(addresses: members));
    }
  }

  void _attachZapDraft() {
    final ZapDraftCubit? provided =
        widget.zapDraft ?? context.read<ZapDraftCubit?>();
    _ownsZapDraft = provided == null;
    _zapDraft = provided ?? ZapDraftCubit();
  }

  void _attachController(TransferMode fallback) {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TransferController(fallback);
    _controller
      ..addListener(_modeChanged)
      .._refresh = _refresh;
  }

  void _detachController() {
    _controller.removeListener(_modeChanged);
    if (_controller._refresh == _refresh) _controller._refresh = null;
    if (_ownsController) _controller.dispose();
  }

  @override
  void didUpdateWidget(TransferPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _receiveEpoch += 1;
      _receiveHeader.invalidate();
      final TransferMode previous = _controller.value;
      _detachController();
      _attachController(previous);
    }
    if (oldWidget.zapDraft != widget.zapDraft) {
      if (_ownsZapDraft) unawaited(_zapDraft.close());
      _attachZapDraft();
    }
  }

  void _modeChanged() {
    _receiveEpoch += 1;
    _receiveHeader.invalidate();
    setState(() {});
  }

  void _refresh() {
    switch (_controller.value) {
      case TransferMode.send:
        context.read<MultipleBalanceBloc>().add(
          MultipleBalanceFetch(
            addresses: kDefaultAddressList
                .map((String? address) => address!)
                .toList(),
          ),
        );
      case TransferMode.receive:
        context.read<AllTokensBloc>().add(const AllTokensRequested());
      case TransferMode.zap:
        return;
    }
    final String? selected = kSelectedAddress;
    if (selected != null) {
      context.read<PendingTransactionsBloc>().add(
        InfiniteListRefreshRequested(address: Address.parse(selected)),
      );
    }
  }

  @override
  void dispose() {
    _receiveEpoch += 1;
    _receiveHeader.dispose();
    _detachController();
    if (_ownsZapDraft) unawaited(_zapDraft.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final TransferMode mode = _controller.value;
    final TransferController controller = _controller;
    final int receiveEpoch = _receiveEpoch;
    bool receiveIsCurrent() => mounted &&
        identical(_controller, controller) && _receiveEpoch == receiveEpoch &&
        controller.value == TransferMode.receive;
    return Stack(
      children: <Widget>[
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: TransferPage.cardWidth,
            child: SingleChildScrollView(
              key: const Key('transfer_scroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _TransferSurface(
                    key: const Key('transfer_card'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (mode == TransferMode.send) const SendSyncNotice(),
                        Padding(
                          padding: EdgeInsetsDirectional.symmetric(
                            horizontal: tokens.cardPadding.left,
                            vertical: tokens.cardPadding.top,
                          ),
                          child: _TransferHeader(
                            mode: mode,
                            receiveHeader: _receiveHeader,
                            onChanged: (TransferMode mode) =>
                                _controller.value = mode,
                          ),
                        ),
                        Divider(height: 1, color: tokens.line),
                        Stack(
                          alignment: Alignment.topCenter,
                          children: <Widget>[
                            _TransferBody(
                              key: const ValueKey<TransferMode>(
                                TransferMode.send,
                              ),
                              active: mode == TransferMode.send,
                              child: KeyedSubtree(
                                key: const Key('transfer_send_screen'),
                                child: SendCard(
                                  embedded: true,
                                  showSender: false,
                                  showSyncNotice: false,
                                  priceFeed: widget.priceFeed,
                                ),
                              ),
                            ),
                            _TransferBody(
                              key: const ValueKey<TransferMode>(
                                TransferMode.receive,
                              ),
                              active: mode == TransferMode.receive,
                              child: KeyedSubtree(
                                key: const Key('transfer_receive_screen'),
                                child: ReceiveCard(
                                  embedded: true,
                                  headerController: _receiveHeader,
                                  isCurrent: receiveIsCurrent,
                                ),
                              ),
                            ),
                            _TransferBody(
                              key: const ValueKey<TransferMode>(
                                TransferMode.zap,
                              ),
                              active: mode == TransferMode.zap,
                              child: ValueListenableBuilder<bool>(
                                valueListenable: context
                                    .read<SendTransactionBloc>()
                                    .busy,
                                builder: (_, bool busy, _) => ZapForm(
                                  key: const Key('transfer_zap_screen'),
                                  draft: _zapDraft,
                                  active: mode == TransferMode.zap,
                                  busy: busy,
                                  priceFeed: widget.priceFeed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _TransferPending(
                    showEmpty: mode == TransferMode.receive,
                    worker: widget.receiveWorker ?? sl<AutoReceiveTxWorker>(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TransferHeader extends StatelessWidget {
  const _TransferHeader({
    required this.mode,
    required this.onChanged,
    required this.receiveHeader,
  });

  final TransferMode mode;
  final ValueChanged<TransferMode> onChanged;
  final ReceiveHeaderController receiveHeader;

  @override
  Widget build(BuildContext context) {
    final Widget segment = Segment<TransferMode>(
      keyPrefix: 'transfer_mode',
      selected: mode,
      onChanged: onChanged,
      items: <SegmentItem<TransferMode>>[
        SegmentItem<TransferMode>(
          value: TransferMode.send,
          label: context.l10n.send,
        ),
        SegmentItem<TransferMode>(
          value: TransferMode.receive,
          label: context.l10n.receive,
        ),
        SegmentItem<TransferMode>(
          value: TransferMode.zap,
          label: context.l10n.transferZap,
        ),
      ],
    );
    final Widget? picker = switch (mode) {
      TransferMode.send => const _TransferSender(),
      TransferMode.receive => _TransferReceiver(controller: receiveHeader),
      TransferMode.zap => null,
    };
    return LayoutBuilder(
      builder: (_, BoxConstraints constraints) => constraints.maxWidth < 520
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                segment,
                if (picker != null) ...<Widget>[
                  SizedBox(height: AppTokens.of(context).transferFieldGap),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: picker,
                  ),
                ],
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(child: segment),
                if (picker != null) ...<Widget>[
                  SizedBox(width: AppTokens.of(context).transferFormGap),
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: picker,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TransferSurface extends StatelessWidget {
  const _TransferSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _TransferBody extends StatefulWidget {
  const _TransferBody({required this.active, required this.child, super.key});

  final bool active;
  final Widget child;

  @override
  State<_TransferBody> createState() => _TransferBodyState();
}

class _TransferBodyState extends State<_TransferBody>
    with SingleTickerProviderStateMixin {
  final FocusNode _focus = FocusNode(debugLabel: 'Transfer mode');
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: TransferPage.modeDuration,
    value: 1,
    // Transfer feedback keeps its clock regardless of the OS animation flag.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(_TransferBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _fade.forward(from: 0);
      } else {
        _fade.stop();
        if (_focus.hasFocus) _focus.unfocus();
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !widget.active,
    child: TickerMode(
      enabled: widget.active,
      child: ExcludeSemantics(
        excluding: !widget.active,
        child: Focus(
          focusNode: _focus,
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: widget.active,
          child: IgnorePointer(
            ignoring: !widget.active,
            child: FadeTransition(opacity: _fade, child: widget.child),
          ),
        ),
      ),
    ),
  );
}
