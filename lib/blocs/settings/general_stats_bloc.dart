import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Reads general node statistics while owning one refresh timer.
class GeneralStatsBloc extends BaseBlocWithRefreshMixin<GeneralStats> {
  Timer? _timer;
  bool _disposed = false;

  @override
  Future<GeneralStats> getDataAsync() async {
    final GeneralStats generalStats = GeneralStats(
      frontierMomentum: await zenon!.ledger.getFrontierMomentum(),
      processInfo: await zenon!.stats.processInfo(),
      networkInfo: await zenon!.stats.networkInfo(),
      osInfo: await zenon!.stats.osInfo(),
    );
    if (!_disposed && (_timer == null || !_timer!.isActive)) {
      _timer = _getTimer();
    }
    return generalStats;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  Timer _getTimer() => Timer(
    kIntervalBetweenMomentums,
    () {
      if (_disposed) return;
      _timer?.cancel();
      _timer = null;
      unawaited(updateStream());
    },
  );
}
