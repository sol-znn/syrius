import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' hide zenon;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_receive_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

part 'node_sync_status_cubit.g.dart';
part 'node_sync_status_state.dart';

/// Cubit responsible for fetching the sync state - [SyncState] - and sending
/// the states update - [NodeSyncStatusState] - back to the widget
///
/// [SyncState] is not related to [NodeSyncStatusState], doesn't handle UI
/// updates.
///
/// [NodeSyncStatusState] along with [TimerStatus] updates the UI of the
/// [NodeSyncStatusIcon] widget
class NodeSyncStatusCubit
    extends TimerCubit<Pair<SyncState, SyncInfo>, NodeSyncStatusState> {
  /// Creates a NodeSyncStatusCubit using the super-initializer parameters
  NodeSyncStatusCubit({
    required super.zenon,
    super.initialState = const NodeSyncStatusState(),
  }) : super(
         refreshInterval: kNodeSyncStatusRefreshInterval,
       );

  SyncState _lastSyncState = SyncState.unknown;
  Timer? _receiveScanTimer;

  @override
  Future<Pair<SyncState, SyncInfo>> fetch() async {
    final AutoReceiveTxWorker? worker = sl.isRegistered<AutoReceiveTxWorker>()
        ? sl<AutoReceiveTxWorker>()
        : null;
    final ReceiveOrigin? origin = worker?.captureOrigin(
      sourceIsCurrent: () => !isClosed,
    );
    final StatsApi source = zenon.stats;
    if (zenon.wsClient.status() == WebsocketStatus.running) {
      final SyncInfo syncInfo = await source.syncInfo();
      if (isClosed ||
          !identical(source, zenon.stats) ||
          (origin != null && !origin.isCurrent)) {
        return _unknownSync();
      }
      if (_lastSyncState != syncInfo.state &&
          (syncInfo.state == SyncState.syncDone ||
              (syncInfo.targetHeight > 0 &&
                  syncInfo.currentHeight > 0 &&
                  (syncInfo.targetHeight - syncInfo.currentHeight) > 3))) {
        _lastSyncState = syncInfo.state;
        if (syncInfo.state == SyncState.syncDone && origin != null) {
          _receiveScanTimer?.cancel();
          _receiveScanTimer = Timer(const Duration(seconds: 5), () {
            if (isClosed || !origin.isCurrent) return;
            unawaited(
              _scanOriginal(worker!, origin).onError<Object>(
                (Object _, StackTrace _) {},
              ),
            );
          });
        }
      }
      return Pair<SyncState, SyncInfo>(_lastSyncState, syncInfo);
    }

    return _unknownSync();
  }

  Pair<SyncState, SyncInfo> _unknownSync() {
    _lastSyncState = SyncState.unknown;
    final SyncInfo placeholderSyncInfo = SyncInfo.fromJson(<String, dynamic>{
      'state': 0,
      'currentHeight': 0,
      'targetHeight': 0,
    });
    return Pair<SyncState, SyncInfo>(SyncState.unknown, placeholderSyncInfo);
  }

  Future<void> _scanOriginal(
    AutoReceiveTxWorker worker,
    ReceiveOrigin origin,
  ) async {
    await NodeReceiveBinding.scan(worker: worker, origin: origin);
    if (!isClosed && origin.isCurrent) await worker.autoReceive();
  }

  @override
  Future<void> close() {
    _receiveScanTimer?.cancel();
    return super.close();
  }

  @override
  NodeSyncStatusState? fromJson(Map<String, dynamic> json) =>
      NodeSyncStatusState.fromJson(
        json,
      );

  @override
  Map<String, dynamic>? toJson(NodeSyncStatusState state) => state.toJson();
}
