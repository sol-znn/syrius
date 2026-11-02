import 'dart:async';

import 'package:flutter/foundation.dart';

/// A peer count only while its connection and lookup belong to this epoch.
/// The shell supplies the existing network lookup and refreshes on sync or
/// node changes; this adapter owns no polling timer or network client.
class PeerCount extends ValueNotifier<int?> {
  /// Creates an unknown count with explicit data and connection sources.
  PeerCount({
    required this._lookup,
    required this._isConnected,
  }) : super(null);

  final Future<int> Function() _lookup;
  final bool Function() _isConnected;

  int _epoch = 0;
  Future<void>? _pending;
  bool _disposed = false;

  /// Coalesces concurrent requests within an epoch. A failed lookup, invalid
  /// count or disconnected node is unknown, never an invented zero.
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    bool connected;
    try {
      connected = _isConnected();
    } on Object {
      connected = false;
    }
    if (!connected) {
      reset();
      return Future<void>.value();
    }
    final Future<void>? pending = _pending;
    if (pending != null) return pending;
    final Completer<void> done = Completer<void>();
    _pending = done.future;
    unawaited(
      _fetch(_epoch).then(
        (_) => done.complete(),
        onError: done.completeError,
      ),
    );
    return done.future;
  }

  Future<void> _fetch(int epoch) async {
    try {
      final int count = await _lookup();
      if (!_disposed && epoch == _epoch) {
        value = _isConnected() && count >= 0 ? count : null;
      }
    } on Object {
      if (!_disposed && epoch == _epoch) value = null;
    } finally {
      if (!_disposed && epoch == _epoch) _pending = null;
    }
  }

  /// Starts a new node/connection epoch without adopting an old response.
  void reset() {
    if (_disposed) return;
    _epoch++;
    _pending = null;
    value = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _pending = null;
    super.dispose();
  }
}
