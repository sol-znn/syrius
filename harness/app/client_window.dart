import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// One finite logical outer bound for native tracking and client correction.
const double harnessMaximumOuterExtent = 32768;

/// Configure only the fresh ordinary Windows harness, before app startup and
/// its original geometry snapshot. Measured client matching remains mandatory.
Future<void> configureHarnessWindowTracking() async {
  await windowManager.ensureInitialized();
  await windowManager.setMaximumSize(
    const Size(harnessMaximumOuterExtent, harnessMaximumOuterExtent),
  );
}

/// Flutter's view metrics are the client area. Native window sizes can also
/// include a title bar and borders, so they cannot establish screenshot size.
class ClientMetrics {
  const ClientMetrics(this.physicalSize, this.devicePixelRatio);

  final Size physicalSize;
  final double devicePixelRatio;

  Size get logicalSize {
    if (!devicePixelRatio.isFinite ||
        devicePixelRatio <= 0 ||
        !physicalSize.width.isFinite ||
        !physicalSize.height.isFinite ||
        physicalSize.width <= 0 ||
        physicalSize.height <= 0) {
      throw StateError('the Flutter view has no usable client metrics');
    }
    return physicalSize / devicePixelRatio;
  }

  bool matches(Size requested) =>
      (logicalSize.width - requested.width).abs() < 0.01 &&
      (logicalSize.height - requested.height).abs() < 0.01;

  Map<String, Object?> toJson() => <String, Object?>{
    'client': <double>[logicalSize.width, logicalSize.height],
    'physical': <double>[physicalSize.width, physicalSize.height],
    'devicePixelRatio': devicePixelRatio,
  };
}

class ClientResizeResult {
  const ClientResizeResult({
    required this.requested,
    required this.observed,
    required this.outer,
    required this.attempts,
  });

  final Size requested;
  final ClientMetrics observed;
  final Size outer;
  final int attempts;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestedClient': <double>[requested.width, requested.height],
    ...observed.toJson(),
    'outer': <double>[outer.width, outer.height],
    'resizeAttempts': attempts,
    'clientMatched': observed.matches(requested),
  };
}

class ClientResizeError implements Exception {
  const ClientResizeError(this.result);

  final ClientResizeResult result;

  @override
  String toString() => 'the requested client area was not observed';
}

/// Corrects by what the engine actually received, with a finite retry budget.
/// A platform constraint or delayed resize remains a refusal, not a rounded
/// claim that a 1280 by 780 screenshot was captured.
Future<ClientResizeResult> resizeClientArea({
  required Size requested,
  required ClientMetrics Function() readMetrics,
  required Future<Size> Function() readOuter,
  required Future<void> Function(Size) setOuter,
  required Future<void> Function() settle,
  int maxAttempts = 5,
}) async {
  if (!requested.width.isFinite ||
      !requested.height.isFinite ||
      requested.width <= 0 ||
      requested.height <= 0 ||
      requested.width > 16384 ||
      requested.height > 16384 ||
      maxAttempts < 1 ||
      maxAttempts > 10) {
    throw ArgumentError('invalid client size or resize budget');
  }
  for (int attempt = 0; ; attempt++) {
    final Size outer = await readOuter();
    final ClientMetrics observed = readMetrics();
    final ClientResizeResult result = ClientResizeResult(
      requested: requested,
      observed: observed,
      outer: outer,
      attempts: attempt,
    );
    if (observed.matches(requested)) return result;
    if (attempt == maxAttempts) throw ClientResizeError(result);
    final Size logical = observed.logicalSize;
    final Size next = Size(
      outer.width + requested.width - logical.width,
      outer.height + requested.height - logical.height,
    );
    if (!next.width.isFinite ||
        !next.height.isFinite ||
        next.width <= 0 ||
        next.height <= 0 ||
        next.width > harnessMaximumOuterExtent ||
        next.height > harnessMaximumOuterExtent) {
      throw ClientResizeError(result);
    }
    await setOuter(next);
    await settle();
  }
}
