import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/plasma_status.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/priority_row.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/sync.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/update_slot.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

export 'strip/flight.dart';
export 'strip/plasma_status.dart';
export 'strip/priority_row.dart';
export 'strip/sync.dart';

/// The one place for background state, always in view: sync and height,
/// node, chain and peers, a block in flight, plasma generation, and whatever
/// notice the shell hands it.
///
/// Its parts change on their own clocks: the height every momentum, the node
/// and chain when the node is changed, the bolt thirty times a second while
/// plasma is generated, the chip when a block is sent. Each listens for
/// itself, and those that repaint often have a layer of their own, so a new
/// height repaints a few digits and not the strip.
///
/// Together the parts are wider than the smallest window, so the row hands
/// out its room by importance (see [PriorityRow]): the dot and the height
/// first, then the notice, a node that is behind, plasma and the block in
/// flight; the node's name, the chain and the peers go first, last of these
/// soonest.
class StatusStrip extends StatelessWidget {
  /// Creates the strip over the shell's sync cubit and page notifier.
  const StatusStrip({
    required this.syncCubit,
    required this.page,
    this.flight,
    this.showFlight = true,
    this.peers,
    this.plasma,
    this.trailing = const WalletUpdateSlot(),
    super.key,
  });

  /// The node's sync state, polled by the shell.
  final NodeSyncStatusCubit syncCubit;

  /// Notifies on a change of page. Changing the node ends on Home, so this
  /// is when the node's name is read again; the sync cubit's next answer
  /// would catch it a few seconds later.
  final Listenable page;

  /// The sends waiting for a momentum; [InFlightBlocks.wallet] when null.
  final InFlightBlocks? flight;

  /// Hides publication details while locked without discarding or settling
  /// unresolved hashes. Confirmation checks keep their existing ownership.
  final bool showFlight;

  /// The node's peer count. No "Peers" part without it, and none while it
  /// holds null.
  final ValueListenable<int?>? peers;

  /// The plasma mark; a [GenerationStatus] over the wallet's own when null.
  final Widget? plasma;

  /// The disabled wallet-update slot by default; null omits the slot.
  /// A supplied notice must fit on one short line and describe actual data.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle dim = theme.textTheme.titleMedium!.copyWith(
      fontSize: 13,
      color: tokens.dim,
    );
    final TextStyle mono = monoStyle(dim);
    final InFlightBlocks flight = this.flight ?? InFlightBlocks.wallet;
    final ValueListenable<int?>? peers = this.peers;
    final Widget? trailing = this.trailing;
    return Material(
      color: tokens.card,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      child: SizedBox(
        height: tokens.statusStripHeight,
        child: Padding(
          padding: tokens.statusStripPadding,
          child: PriorityRow(
            gap: tokens.statusStripGap,
            children: <Prioritized>[
              Prioritized(
                priority: 0,
                shrink: true,
                // The height can shorten, but the connection dot stays visible.
                minWidth: tokens.statusDotSize * 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    BlocBuilder<NodeSyncStatusCubit, NodeSyncStatusState>(
                      bloc: syncCubit,
                      builder: (BuildContext context, NodeSyncStatusState s) =>
                          SyncDot(state: s),
                    ),
                    // Selected, so the height is rebuilt when it changes
                    // and not each time the node is asked how far it has
                    // synced.
                    Flexible(
                      child: RepaintBoundary(
                        child:
                            BlocSelector<
                              NodeSyncStatusCubit,
                              NodeSyncStatusState,
                              int
                            >(
                              bloc: syncCubit,
                              selector: (NodeSyncStatusState state) =>
                                  state.data?.second.currentHeight ?? 0,
                              builder: (BuildContext context, int height) =>
                                  _buildHeight(
                                    height,
                                    mono,
                                    tokens.cardGap,
                                    context,
                                  ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              Prioritized(
                priority: 3,
                child:
                    BlocSelector<
                      NodeSyncStatusCubit,
                      NodeSyncStatusState,
                      int?
                    >(
                      bloc: syncCubit,
                      selector: momentumsBehind,
                      builder: (BuildContext context, _) =>
                          SyncBehind(state: syncCubit.state),
                    ),
              ),
              Prioritized(
                priority: 6,
                shrink: true,
                // The label and a dozen characters of the address; with
                // less, the name says nothing and its label overflows.
                minWidth: 140,
                child: _onNodeChange(
                  (BuildContext context) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('${context.l10n.stripNode} ', style: dim),
                      Flexible(
                        child: ValueFlash(
                          value: kCurrentNode,
                          child: Text(
                            kCurrentNode ?? '',
                            key: const Key('strip_node'),
                            style: mono,
                            textDirection: TextDirection.ltr,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Prioritized(
                priority: 7,
                child: _onNodeChange((BuildContext context) {
                  final int chainId = getChainIdentifier();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('${context.l10n.stripChain} ', style: dim),
                      ValueFlash(
                        value: chainId,
                        child: Ltr(
                          child: Text(
                            '$chainId',
                            key: const Key('strip_chain'),
                            style: mono,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
              if (peers != null)
                Prioritized(
                  priority: 8,
                  child: ValueListenableBuilder<int?>(
                    valueListenable: peers,
                    builder: (BuildContext context, int? count, _) =>
                        count == null
                        ? const SizedBox.shrink()
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text('${context.l10n.stripPeers} ', style: dim),
                              Ltr(
                                child: Text(
                                  '$count',
                                  key: const Key('strip_peers'),
                                  style: mono,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              Prioritized(
                priority: 5,
                shrink: true,
                minWidth: 120,
                // A block is confirmed by a momentum, so a new height is
                // when to ask; no timer of the chip's own.
                child: BlocListener<NodeSyncStatusCubit, NodeSyncStatusState>(
                  bloc: syncCubit,
                  listenWhen:
                      (NodeSyncStatusState before, NodeSyncStatusState after) =>
                          before.data?.second.currentHeight !=
                          after.data?.second.currentHeight,
                  listener: (BuildContext context, _) =>
                      unawaited(flight.check()),
                  child: showFlight
                      ? FlightChip(blocks: flight)
                      : const SizedBox.shrink(),
                ),
              ),
              Prioritized(
                priority: 4,
                shrink: true,
                // The mark alone.
                minWidth: tokens.statusDotSize * 2.25,
                end: true,
                child: RepaintBoundary(
                  child: plasma ?? const GenerationStatus(),
                ),
              ),
              if (trailing != null)
                Prioritized(
                  priority: 2,
                  end: true,
                  child: trailing,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeight(
    int height,
    TextStyle mono,
    double gap,
    BuildContext context,
  ) => height <= 0
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsetsDirectional.only(start: gap),
          child: Tooltip(
            message: context.l10n.stripMomentumHeight(height),
            child: ValueFlash(
              value: height,
              child: Ltr(
                child: Text(
                  '#${splitAmount(BigInt.from(height), 0).$1}',
                  key: const Key('strip_height'),
                  style: mono,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );

  /// Builds what reads the node's name or its chain: on a change of page
  /// and on each answer of the node, as before.
  Widget _onNodeChange(WidgetBuilder builder) => ListenableBuilder(
    listenable: page,
    builder: (BuildContext context, _) =>
        BlocBuilder<NodeSyncStatusCubit, NodeSyncStatusState>(
          bloc: syncCubit,
          builder: (BuildContext context, _) => builder(context),
        ),
  );
}
