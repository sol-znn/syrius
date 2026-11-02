import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/address_owned_fetch_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The two existing reward contracts exposed by Nodes.
enum NodeRewardSource {
  /// Pillar and delegation rewards.
  pillar,

  /// Sentinel rewards.
  sentinel,
}

/// Immutable amounts and the completed read that the user saw before pressing.
class NodeCollectionSnapshot {
  /// Copies values instead of retaining a mutable SDK reward response.
  const NodeCollectionSnapshot({
    required this.ticket,
    required this.address,
    required this.znn,
    required this.qsr,
  });

  /// The reader's opaque completed request identity.
  final Object ticket;

  /// The exact original account.
  final String address;

  /// ZNN in its smallest units.
  final BigInt znn;

  /// QSR in its smallest units.
  final BigInt qsr;

  /// Rejects foreign, negative or empty fresh answers.
  bool matches(UncollectedReward reward) =>
      reward.address.toString() == address &&
      reward.znnAmount == znn &&
      reward.qsrAmount == qsr &&
      znn >= BigInt.zero &&
      qsr >= BigInt.zero &&
      (znn > BigInt.zero || qsr > BigInt.zero);
}

/// Retains the original request and outcome, including an unavailable result.
class NodeCollectionAttempt {
  /// No later read or surface replaces this request's response.
  const NodeCollectionAttempt({
    required this.requestId,
    required this.snapshot,
    required this.result,
    required this.hash,
    required this.accepted,
  });

  /// The exact admitted request.
  final Object requestId;

  /// The immutable original displayed values and reader ticket.
  final NodeCollectionSnapshot snapshot;

  /// The original sender response or original failure.
  final SendRequestResult result;

  /// Captured before any UI callback can change a returned template.
  final Hash? hash;

  /// True only for an exact account, chain and nonempty returned hash.
  final bool accepted;
}

/// One retained source/account hold on the existing shared sender.
class NodeCollectionController extends ChangeNotifier {
  /// The exact tracker belongs to the captured wallet and chain.
  NodeCollectionController({
    required this.sender,
    required this.flight,
    required this.address,
    required this.chainId,
  });

  /// Reopening a panel cannot discard an uncertain admitted attempt.
  factory NodeCollectionController.retained({
    required SendTransactionBloc sender,
    required NodeRewardSource source,
    required InFlightBlocks flight,
    required String address,
    required int chainId,
  }) {
    final Map<(NodeRewardSource, int, String), NodeCollectionController>
    owners = _retained[sender] ??=
        <(NodeRewardSource, int, String), NodeCollectionController>{};
    return owners.putIfAbsent(
      (source, chainId, address),
      () => NodeCollectionController(
        sender: sender,
        flight: flight,
        address: address,
        chainId: chainId,
      ),
    );
  }

  static final Expando<
    Map<(NodeRewardSource, int, String), NodeCollectionController>
  >
  _retained =
      Expando<Map<(NodeRewardSource, int, String), NodeCollectionController>>();

  /// The wallet's existing publication admission.
  final SendTransactionBloc sender;

  /// Confirmation evidence for this wallet and chain.
  final InFlightBlocks flight;

  /// The account whose rewards are being collected.
  final String address;

  /// The chain captured with this controller.
  final int chainId;
  bool _busy = false;
  Object? _consumedTicket;
  NodeCollectionAttempt? _attempt;

  /// Own preparation or publication only. Other sends do not animate Collect.
  bool get busy => _busy;

  /// The original admitted result survives widget disposal.
  NodeCollectionAttempt? get attempt => _attempt;

  /// An error is uncertainty, never evidence that collection did not happen.
  bool get uncertain => _attempt != null && !_attempt!.accepted;

  /// A new displayed read and exact confirmation precede explicit rearm.
  bool canCollect(NodeCollectionSnapshot? snapshot) =>
      !_busy &&
      !sender.busy.value &&
      snapshot != null &&
      snapshot.address == address &&
      snapshot.znn >= BigInt.zero &&
      snapshot.qsr >= BigInt.zero &&
      (snapshot.znn > BigInt.zero || snapshot.qsr > BigInt.zero) &&
      !identical(snapshot.ticket, _consumedTicket) &&
      (_attempt == null ||
          (_attempt!.accepted && flight.hasConfirmed(_attempt!.hash!)));

  /// Verifies fresh exact rewards, then follows only this request's handle.
  Future<SendRequestResult?> collect({
    required NodeCollectionSnapshot snapshot,
    required WalletActionContext context,
    required bool Function() ownsRead,
    required bool Function() isCurrent,
    required Future<UncollectedReward> Function() freshRead,
    required AccountBlockTemplate Function() buildBlock,
    required String purpose,
  }) async {
    bool current() =>
        context.ownerAddress == address &&
        context.isCurrent &&
        ownsRead() &&
        isCurrent();

    if (!canCollect(snapshot) || !current()) return null;
    // Snapshot encoding before any reservation listener can reenter the UI.
    final AccountBlockTemplate block = AccountBlockTemplate.fromJson(
      buildBlock().toJson(),
    );
    final Object owner = Object();
    if (!sender.tryReserve(owner)) return null;
    _busy = true;
    _consumedTicket = snapshot.ticket;
    try {
      _changed();
      if (!current()) return null;
      // This read starts after exact confirmation when rearming an acceptance.
      final UncollectedReward fresh = await freshRead();
      if (!current() || !snapshot.matches(fresh)) return null;
      final Object requestId = Object();
      final SendRequestHandle? handle = sender.trySubmitOwned(
        owner: owner,
        requestId: requestId,
        block: block,
        fromAddress: address,
        reasonForGeneratingPlasma: purpose,
        canStart: current,
        canPublish: current,
      );
      if (handle == null) return null;
      final SendRequestResult result = await handle.result;
      final AccountBlockTemplate? accepted = result.block;
      final Hash? returnedHash = accepted?.hash;
      final Hash? hash = returnedHash == null
          ? null
          : Hash.fromBytes(
              List<int>.unmodifiable(returnedHash.hash),
            );
      final bool exact =
          result.accepted &&
          accepted != null &&
          hash != null &&
          hash != emptyHash &&
          accepted.address.toString() == address &&
          accepted.chainIdentifier == chainId;
      _attempt = NodeCollectionAttempt(
        requestId: requestId,
        snapshot: snapshot,
        result: result,
        hash: hash,
        accepted: exact,
      );
      if (exact) {
        try {
          flight.sent(hash: hash, amount: accepted.amount);
        } on Object {
          // A display observer cannot change the original accepted result.
        }
      }
      return result;
    } finally {
      _busy = false;
      sender.releaseReservation(owner);
      _changed();
    }
  }

  void _changed() {
    try {
      notifyListeners();
    } on Object {
      // Optional UI observers cannot strand an original sender reservation.
    }
  }
}

/// Shares collection implementation while preserving both public adapters.
class NodeCollectButton extends StatefulWidget {
  /// [enabled] remains an additional presentation gate.
  const NodeCollectButton({
    required this.enabled,
    required this.source,
    super.key,
  });

  /// The existing adapter's presentation gate.
  final bool enabled;

  /// The existing reward RPC and block builder to use.
  final NodeRewardSource source;

  @override
  State<NodeCollectButton> createState() => _NodeCollectButtonState();
}

class _NodeCollectButtonState extends State<NodeCollectButton> {
  final GlobalKey<LoadingButtonState> _button = GlobalKey();
  Timer? _refreshTimer;
  int _visibilityEpoch = 0;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (_visible && !visible) _visibilityEpoch++;
    _visible = visible;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  LoadingButton _buildButton(VoidCallback? onPressed) => LoadingButton.stepper(
    key: _button,
    text: context.l10n.collect,
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    final String? address = kSelectedAddress;
    final WalletActionContext? action = address == null
        ? null
        : WalletActionContext.capture(address);
    if (action == null) return _buildButton(null);
    final AddressOwnedFetchCubit<UncollectedReward> reader = switch (widget
        .source) {
      NodeRewardSource.pillar => context.read<UncollectedPillarRewardsBloc>(),
      NodeRewardSource.sentinel =>
        context.read<UncollectedSentinelRewardsBloc>(),
    };
    final SendTransactionBloc sender = context.read<SendTransactionBloc>();
    final int chainId = getChainIdentifier();
    final InFlightBlocks flight = WalletFlightRegistry.instance.forWallet(
      chainId,
      kDefaultAddressList.whereType<String>(),
    );
    final NodeCollectionController owner = NodeCollectionController.retained(
      sender: sender,
      source: widget.source,
      flight: flight,
      address: action.ownerAddress,
      chainId: chainId,
    );
    return StreamBuilder<FetchState<UncollectedReward>>(
      stream: reader.stream,
      initialData: reader.state,
      builder: (BuildContext context, _) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[sender.busy, owner, flight]),
        builder: (BuildContext context, _) {
          final FetchState<UncollectedReward> state = reader.state;
          final Object? ticket = reader.readOwner;
          final NodeCollectionSnapshot? snapshot =
              state is FetchPopulated<UncollectedReward> &&
                  ticket != null &&
                  reader.ownsRead(ticket, action.ownerAddress)
              ? NodeCollectionSnapshot(
                  ticket: ticket,
                  address: action.ownerAddress,
                  znn: state.data.znnAmount,
                  qsr: state.data.qsrAmount,
                )
              : null;
          final LoadingButton button = _buildButton(
            _visible &&
                    widget.enabled &&
                    action.isCurrent &&
                    owner.canCollect(snapshot)
                ? () => unawaited(_collect(owner, reader, snapshot!, action))
                : null,
          );
          return Tooltip(
            message: owner.uncertain
                ? context.l10n.homeCollectionUncertain
                : '',
            child: button,
          );
        },
      ),
    );
  }

  Future<void> _collect(
    NodeCollectionController owner,
    AddressOwnedFetchCubit<UncollectedReward> reader,
    NodeCollectionSnapshot snapshot,
    WalletActionContext action,
  ) async {
    if (!mounted ||
        !_visible ||
        !widget.enabled ||
        !owner.canCollect(snapshot)) {
      return;
    }
    final int epoch = _visibilityEpoch;
    final Object? page = kCurrentPage;
    final NodeRewardSource source = widget.source;
    final Address address = Address.parse(snapshot.address);
    final AppLocalizations l10n = context.l10n;
    final bool pillar = source == NodeRewardSource.pillar;
    _button.currentState?.animateForward();
    try {
      final SendRequestResult? result = await owner.collect(
        snapshot: snapshot,
        context: action,
        ownsRead: () => reader.ownsRead(snapshot.ticket, snapshot.address),
        isCurrent: () =>
            mounted &&
            _visible &&
            epoch == _visibilityEpoch &&
            page == kCurrentPage &&
            widget.enabled &&
            widget.source == source,
        freshRead: () => pillar
            ? action.client.embedded.pillar.getUncollectedReward(address)
            : action.client.embedded.sentinel.getUncollectedReward(address),
        buildBlock: () => pillar
            ? action.client.embedded.pillar.collectReward()
            : action.client.embedded.sentinel.collectReward(),
        purpose: pillar
            ? l10n.plasmaPurposeCollectPillarRewards
            : l10n.plasmaPurposeCollectSentinelRewards,
      );
      if (!mounted || !action.isCurrent || result == null) return;
      if (owner.attempt?.accepted ?? false) {
        _button.currentState?.landed();
        try {
          await sl.get<NotificationsBloc>().addNotification(
            WalletNotification(
              title: pillar
                  ? l10n.pillarRewardsBlockCreated
                  : l10n.sentinelRewardsBlockCreated,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              details: l10n.hashValue(owner.attempt!.hash.toString()),
              type: NotificationType.paymentSent,
            ),
          );
        } on Object {
          // Notification storage cannot replace the original acceptance.
        }
        if (!mounted || !action.isCurrent) return;
        _refreshTimer?.cancel();
        _refreshTimer = Timer(kDelayAfterAccountBlockCreationCall, () {
          if (!mounted || !action.isCurrent || reader.isClosed) return;
          reader.add(FetchRequestData(address: address));
          if (pillar) {
            context.read<PillarRewardsHistoryBloc>().add(
              FetchRequestData(address: address),
            );
          } else {
            context.read<SentinelRewardsHistoryBloc>().add(
              FetchRequestData(address: address),
            );
          }
        });
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l10n.homeCollectionUncertain)),
        );
      }
    } on Object {
      if (mounted && action.isCurrent) {
        try {
          await NotificationUtils.sendNotificationError(
            FailureException(),
            pillar
                ? l10n.errorCollectingPillarRewards
                : l10n.errorCollectingSentinelRewards,
          );
        } on Object {
          // The sender's original failure remains authoritative.
        }
      }
    } finally {
      if (mounted) _button.currentState?.animateReverse();
    }
  }
}
