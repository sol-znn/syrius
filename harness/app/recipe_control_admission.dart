import 'dart:ui' show Rect;

import 'package:flutter/widgets.dart' show Element;

/// Labels an exact original-control refusal without exporting its geometry.
///
/// Every changed center remains refused. The subpixel label describes the
/// failure; it does not introduce a tolerance or approve a different point.
String? recipeControlChange({
  required Element original,
  required Element current,
  required Rect originalRect,
  required Rect currentRect,
}) {
  if (!identical(current, original)) {
    return 'wallet-recipe-original-control-replaced';
  }
  if (currentRect.center == originalRect.center) return null;
  if (currentRect.size != originalRect.size) {
    return 'wallet-recipe-original-control-resized';
  }
  final double dx = currentRect.center.dx - originalRect.center.dx;
  final double dy = currentRect.center.dy - originalRect.center.dy;
  if (dx.abs() < 1 && dy.abs() < 1) {
    return 'wallet-recipe-original-control-moved-subpixel';
  }
  return 'wallet-recipe-original-control-moved';
}
