import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Plasma one plain send costs: an account block's base price in go-zenon.
const int kPlasmaPerSend = 21000;

/// What the home shows for one address, read in one round.
class HomeSnapshot extends Equatable {
  /// Creates a snapshot.
  const HomeSnapshot({
    required this.znn,
    required this.qsr,
    required this.tokens,
    required this.currentPlasma,
    required this.maxPlasma,
    required this.fusedQsr,
    required this.rewards,
  });

  /// Reads everything the home shows for [address] from [zenon].
  static Future<HomeSnapshot> read(Zenon zenon, Address address) async {
    final List<Object> results = await Future.wait(<Future<Object>>[
      zenon.ledger.getAccountInfoByAddress(address),
      zenon.embedded.plasma.get(address),
      zenon.embedded.pillar.getUncollectedReward(address),
      zenon.embedded.sentinel.getUncollectedReward(address),
      zenon.embedded.stake.getUncollectedReward(address),
    ]);
    final AccountInfo account = results[0] as AccountInfo;
    final PlasmaInfo plasma = results[1] as PlasmaInfo;
    return HomeSnapshot(
      znn: account.znn() ?? BigInt.zero,
      qsr: account.qsr() ?? BigInt.zero,
      tokens: <BalanceInfoListItem>[
        for (final BalanceInfoListItem item
            in account.balanceInfoList ?? <BalanceInfoListItem>[])
          if ((item.token == null ||
                  (item.token!.tokenStandard != znnZts &&
                      item.token!.tokenStandard != qsrZts)) &&
              (item.balance ?? BigInt.zero) > BigInt.zero)
            item,
      ],
      currentPlasma: plasma.currentPlasma,
      maxPlasma: plasma.maxPlasma,
      fusedQsr: plasma.qsrAmount,
      rewards: <String, UncollectedReward>{
        'Delegation': results[2] as UncollectedReward,
        'Sentinel': results[3] as UncollectedReward,
        'Staking': results[4] as UncollectedReward,
      },
    );
  }

  /// Balances, smallest unit.
  final BigInt znn;

  /// Balances, smallest unit.
  final BigInt qsr;

  /// Every other token with a balance.
  final List<BalanceInfoListItem> tokens;

  /// Plasma available now.
  final int currentPlasma;

  /// Plasma the fused QSR gives when fully recharged.
  final int maxPlasma;

  /// QSR fused for this address, smallest unit.
  final BigInt fusedQsr;

  /// Uncollected rewards by source. A pillar's delegation rewards and its
  /// own rewards both come from the pillar contract, hence "Delegation".
  final Map<String, UncollectedReward> rewards;

  /// Plain sends the current plasma pays for without proof of work.
  int get sendsCovered => currentPlasma ~/ kPlasmaPerSend;

  /// The rewards that are not zero.
  Map<String, UncollectedReward> get rewardsDue => <String, UncollectedReward>{
    for (final MapEntry<String, UncollectedReward> e in rewards.entries)
      if (e.value.znnAmount > BigInt.zero || e.value.qsrAmount > BigInt.zero)
        e.key: e.value,
  };

  @override
  List<Object?> get props => <Object?>[
    znn,
    qsr,
    tokens,
    currentPlasma,
    maxPlasma,
    fusedQsr,
    rewards,
  ];
}

/// Where a [HomeCubit] is.
enum HomeStatus {
  /// Nothing read yet.
  loading,

  /// [HomeState.snapshot] is current.
  ready,

  /// The last read failed. A snapshot from before may still be shown.
  failed,
}

/// The state of the home for one address.
class HomeState extends Equatable {
  /// Creates a state.
  const HomeState({
    this.status = HomeStatus.loading,
    this.snapshot,
    this.readRevision = 0,
  });

  /// Where the cubit is.
  final HomeStatus status;

  /// The last good read, kept through a failed one so the page does not
  /// blank out when the node drops for a moment.
  final HomeSnapshot? snapshot;

  /// Identifies a completed read even when its values equal the previous read.
  final int readRevision;

  @override
  List<Object?> get props => <Object?>[status, snapshot, readRevision];
}

/// Reads the home's snapshot for one address, then again every [interval].
///
/// One cubit per address: the home makes a new one when the selected
/// address changes, so a late answer for the old address can never be shown
/// under the new one.
class HomeCubit extends Cubit<HomeState> {
  /// Creates a cubit that reads through [read].
  HomeCubit({
    required this.read,
    this.interval = const Duration(seconds: 15),
  }) : super(const HomeState());

  /// Reads one snapshot for this cubit's captured address and client context.
  final Future<HomeSnapshot> Function() read;

  /// Delay between completed reads; manual requests join an active read.
  final Duration interval;
  Timer? _timer;
  Future<void>? _refreshing;

  /// Reads now, and schedules the next read.
  Future<void> refresh() {
    if (isClosed) return Future<void>.value();
    return _refreshing ??= _refresh().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    _timer?.cancel();
    try {
      final HomeSnapshot snapshot = await read();
      if (!isClosed) {
        emit(
          HomeState(
            status: HomeStatus.ready,
            snapshot: snapshot,
            readRevision: state.readRevision + 1,
          ),
        );
      }
    } on Object {
      if (!isClosed) {
        emit(
          HomeState(
            status: HomeStatus.failed,
            snapshot: state.snapshot,
            readRevision: state.readRevision,
          ),
        );
      }
    }
    if (!isClosed) {
      _timer = Timer(interval, refresh);
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
