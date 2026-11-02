import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'client_window.dart';

/// RenderView's root layer and paintBounds are physical. Cancelling that
/// root transform captures the complete client at one output pixel per
/// logical pixel, including on a desktop with display scaling enabled.
Future<ui.Image> captureLogicalView(RenderView view, OffsetLayer layer) {
  final ClientMetrics metrics = ClientMetrics(
    view.flutterView.physicalSize,
    view.flutterView.devicePixelRatio,
  );
  if (!metrics.matches(view.size) ||
      view.configuration.devicePixelRatio != metrics.devicePixelRatio) {
    throw StateError('the painted view has not caught up with client metrics');
  }
  return layer.toImage(
    view.paintBounds,
    pixelRatio: 1 / metrics.devicePixelRatio,
  );
}

Rect logicalClientRect(RenderBox box) => MatrixUtils.transformRect(
  // A null target excludes RenderView's physical root transform. Pointer
  // events and hitTestInView both consume these logical coordinates.
  box.getTransformTo(null),
  Offset.zero & box.size,
);
