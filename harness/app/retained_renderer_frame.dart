import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'capture_protocol.dart';
import 'client_window.dart';
import 'logical_capture.dart';
import 'retained_png.dart';

/// Owns an actual raster image while the original view keeps animating.
/// The image, rather than two equal live observations, pins the encoded frame.
final class RetainedRendererFrame {
  RetainedRendererFrame._(
    this.view,
    this._flutterView,
    this.metrics,
    this._layer,
    this._image,
    this._sourceCurrent,
  );

  /// The exact renderer captured before the readback started.
  final RenderView view;
  final ui.FlutterView _flutterView;

  /// Physical metrics and scale belong to that original rendered client.
  final ClientMetrics metrics;
  final LayerHandle<OffsetLayer> _layer;
  final ui.Image _image;
  final bool Function() _sourceCurrent;
  Future<Uint8List>? _encoding;
  Future<ByteData?>? _originalEncoding;
  Future<Uint8List>? _originalPngEncoding;
  final Completer<void> _encodingSettled = Completer<void>();
  Future<void>? _releaseFuture;
  bool _held = false;
  bool _released = false;

  /// Raster readback is awaited to its actual result, including after source
  /// loss. A changed source disposes the returned image without adopting it.
  static Future<RetainedRendererFrame> capture({
    required RenderView view,
    required Size expectedSize,
    required bool Function() sourceCurrent,
  }) async {
    final ui.FlutterView flutterView = view.flutterView;
    final ClientMetrics metrics = ClientMetrics(
      flutterView.physicalSize,
      flutterView.devicePixelRatio,
    );
    // The harness needs the painted layer in profile and release builds too.
    // ignore: invalid_use_of_protected_member
    final Layer? painted = view.layer;
    if (!view.attached ||
        painted is! OffsetLayer ||
        !metrics.matches(expectedSize) ||
        !sourceCurrent()) {
      throw const CaptureRefused('original-renderer-unavailable');
    }
    final LayerHandle<OffsetLayer> layer = LayerHandle<OffsetLayer>(painted);
    ui.Image? image;
    try {
      image = await captureLogicalView(view, painted);
      final RetainedRendererFrame frame = RetainedRendererFrame._(
        view,
        flutterView,
        metrics,
        layer,
        image,
        sourceCurrent,
      );
      if (!frame.isCurrent ||
          image.width != expectedSize.width ||
          image.height != expectedSize.height) {
        throw const CaptureRefused('original-renderer-changed');
      }
      return frame;
    } on Object {
      image?.dispose();
      layer.layer = null;
      rethrow;
    }
  }

  /// The image is private; callers cannot dispose or replace its raster handle.
  int get width => _image.width;
  int get height => _image.height;

  /// The actual engine readback Future retains straight RGBA bytes.
  Future<ByteData?>? get originalEncoding => _originalEncoding;

  /// The one PNG worker Future, absent until the readback was admitted.
  Future<Uint8List>? get originalPngEncoding => _originalPngEncoding;

  /// True only after the owned image and layer handle have been released.
  bool get released => _released;

  /// A lost original cannot become valid again when metrics return to equality.
  bool get isCurrent {
    if (_held || _released || _releaseFuture != null) return false;
    try {
      final bool valid =
          view.attached &&
          identical(view.flutterView, _flutterView) &&
          // Check the same retained layer outside debug-only APIs.
          // ignore: invalid_use_of_protected_member
          identical(view.layer, _layer.layer) &&
          _layer.layer != null &&
          _flutterView.physicalSize == metrics.physicalSize &&
          _flutterView.devicePixelRatio == metrics.devicePixelRatio &&
          view.configuration.devicePixelRatio == metrics.devicePixelRatio &&
          metrics.matches(view.size) &&
          _sourceCurrent();
      if (!valid) _held = true;
      return valid;
    } on Object {
      _held = true;
      rethrow;
    }
  }

  /// There is one encoding attempt. Repeated callers observe its same result.
  Future<Uint8List> encodePng() {
    final Future<Uint8List>? retained = _encoding;
    if (retained != null) return retained;
    final Completer<Uint8List> result = Completer<Uint8List>();
    _encoding = result.future;
    unawaited(
      _encode().then<void>(result.complete, onError: result.completeError),
    );
    return result.future;
  }

  Future<Uint8List> _encode() async {
    try {
      if (!isCurrent) {
        throw const CaptureRefused('original-frame-unavailable');
      }
      if (_image.colorSpace != ui.ColorSpace.sRGB) {
        throw const CaptureRefused('original-frame-color-space-unproven');
      }
      final Future<ByteData?> original = _image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      _originalEncoding = original;
      final ByteData? rgba = await original;
      if (!isCurrent || rgba == null) {
        throw const CaptureRefused('original-frame-encoding-unproven');
      }
      final Future<Uint8List> encoded = encodeRetainedRgba(
        rgba,
        width: width,
        height: height,
      );
      _originalPngEncoding = encoded;
      final Uint8List png = await encoded;
      if (!isCurrent) {
        throw const CaptureRefused('original-frame-encoding-unproven');
      }
      return png;
    } on Object {
      _held = true;
      rethrow;
    } finally {
      _encodingSettled.complete();
    }
  }

  /// Disposal waits for the original readback and PNG worker outcomes.
  /// A deadline cannot release an image while either operation remains pending.
  Future<void> release() {
    final Future<void>? retained = _releaseFuture;
    if (retained != null) return retained;
    final Completer<void> result = Completer<void>();
    _releaseFuture = result.future;
    unawaited(
      _release().then<void>(result.complete, onError: result.completeError),
    );
    return result.future;
  }

  Future<void> _release() async {
    if (_encoding != null) await _encodingSettled.future;
    try {
      _image.dispose();
    } finally {
      _layer.layer = null;
    }
    _released = true;
  }
}
