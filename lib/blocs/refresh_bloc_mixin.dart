import 'dart:async';
import 'dart:ui';

import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Owns one reconnect and node-change subscription for a read model.
mixin RefreshBlocMixin {
  StreamSubscription<bool>? _restartWsStreamSubscription;
  StreamSubscription<void>? _nodeChangeSubscription;
  int _refreshEpoch = 0;

  /// Replaces old listeners; a reconnect never creates another subscription.
  ///
  /// [restarts] and [client] permit lifecycle checks without opening a socket.
  void listenToWsRestart(
    VoidCallback onWsConnectionRestartedCallback, {
    Stream<bool>? restarts,
    WsClient? client,
  }) {
    cancelStreamSubscription();
    final int epoch = _refreshEpoch;
    void refresh() {
      if (epoch == _refreshEpoch) onWsConnectionRestartedCallback();
    }

    _nodeChangeSubscription = NodeChange.stream.listen(
      (_) => refresh(),
    );
    // The pinned SDK getter adds an asBroadcastStream wrapper with no
    // onCancel handler. Its source stays subscribed after our cancellation.
    // The controller is already broadcast; own that source directly.
    _restartWsStreamSubscription =
        (restarts ??
                (client ?? zenon?.wsClient)?.restartedStreamController.stream)
            ?.listen((bool restarted) {
              if (restarted) refresh();
            });
  }

  /// Revokes queued callbacks before requesting asynchronous cancellation.
  void cancelStreamSubscription() {
    _refreshEpoch++;
    unawaited(_restartWsStreamSubscription?.cancel());
    unawaited(_nodeChangeSubscription?.cancel());
    _restartWsStreamSubscription = null;
    _nodeChangeSubscription = null;
  }
}
