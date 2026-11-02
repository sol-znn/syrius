import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show IconButton;
import 'package:zenon_syrius_wallet_flutter/utils/window_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/window_frame.dart';

/// A finite harness refusal; original failures stay private to this observer.
final class CaptionRefused implements Exception {
  /// Describes only a fixed protocol outcome.
  const CaptionRefused(this.code);

  /// A fixed code, never native diagnostics or owner identity.
  final String code;
}

/// Observes three genuine caption taps and one ordinary native restore.
/// This harness-only owner never invokes the production controller directly.
final class EntryCaptionObserver {
  /// Capture only read-only entry/native facts and an actual pointer adapter.
  EntryCaptionObserver({
    required Map<String, Object?> Function() readEntry,
    required Future<Map<String, Object?>> Function({
      required bool geometry,
    })
    readWindow,
    required Future<void> Function(Element, VoidCallback, VoidCallback) tap,
    Duration Function()? elapsed,
  }) : this._(readEntry, readWindow, tap, elapsed);

  EntryCaptionObserver._(
    this._readEntry,
    this._readWindow,
    this._tap,
    this._elapsed,
  ) {
    _clock.start();
  }

  final Map<String, Object?> Function() _readEntry;
  final Future<Map<String, Object?>> Function({
    required bool geometry,
  })
  _readWindow;
  final Future<void> Function(Element, VoidCallback, VoidCallback) _tap;
  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch();
  final Map<String, Element> _wrappers = <String, Element>{};
  final Map<String, Element> _buttons = <String, Element>{};
  StatefulElement? _element;
  AppWindowFrameState? _state;
  Object? _owner;
  Object? _failure;
  Map<String, Object?>? _baseline;
  late Future<Map<String, Object?>> _nativeRead;
  Future<void>? _restoreOriginal;
  late Future<void> _pointerOriginal;
  bool _restorePending = false;
  bool _nativePending = false;
  bool _pendingObserved = false;
  bool _geometryReserved = false;
  int _stage = 0;
  int _observations = 0;

  /// The exact original restore Future, for offline identity fixtures only.
  @visibleForTesting
  Future<void>? get originalRestoreForTest => _restoreOriginal;

  /// Only fixed refusal codes cross the harness boundary; originals stay held.
  String get publicFailureCode {
    const Map<String, String> codes = <String, String>{
      'caption-baseline-refused': 'CAPTION_BASELINE_REFUSED',
      'caption-control-changed': 'CAPTION_CONTROL_CHANGED',
      'caption-control-refused': 'CAPTION_CONTROL_REFUSED',
      'caption-entry-refused': 'CAPTION_ENTRY_REFUSED',
      'caption-native-invalid': 'CAPTION_NATIVE_INVALID',
      'caption-native-pending': 'CAPTION_NATIVE_PENDING',
      'caption-original-changed': 'CAPTION_ORIGINAL_CHANGED',
      'caption-pending': 'CAPTION_PENDING',
      'caption-pending-unobserved': 'CAPTION_PENDING_UNOBSERVED',
      'caption-replay-refused': 'CAPTION_REPLAY_REFUSED',
      'caption-restore-refused': 'CAPTION_RESTORE_REFUSED',
      'caption-timeout': 'CAPTION_TIMEOUT',
      'caption-tree-capacity-refused': 'CAPTION_TREE_CAPACITY_REFUSED',
      'caption-tree-refused': 'CAPTION_TREE_REFUSED',
      'caption-tree-unmounted': 'CAPTION_TREE_UNMOUNTED',
      'caption-unavailable': 'CAPTION_UNAVAILABLE',
    };
    final Object? original = _failure;
    return original is CaptionRefused
        ? codes[original.code] ?? 'CAPTION_HELD'
        : 'CAPTION_HELD';
  }

  /// Keep a private original failure permanently without granting recovery.
  void hold(Object original) {
    _failure ??= original;
  }

  Never _refuse(String code, [Object? original]) {
    _failure ??= original ?? CaptionRefused(code);
    throw CaptionRefused(code);
  }

  Duration _remaining() {
    if (_failure != null) {
      throw const CaptionRefused('caption-held');
    }
    final Duration remaining =
        const Duration(seconds: 20) - (_elapsed?.call() ?? _clock.elapsed);
    if (remaining <= Duration.zero) {
      _refuse('caption-timeout');
    }
    return remaining;
  }

  Future<T> _bounded<T>(Future<T> original) async {
    // Attach to the original even when it returned after our absolute deadline.
    // A late failure remains private evidence instead of an unhandled Future.
    unawaited(
      original.then<void>(
        (T value) {},
        onError: (Object error, StackTrace stack) {
          hold(error);
        },
      ),
    );
    try {
      final T value = await original.timeout(_remaining());
      _remaining();
      return value;
    } on Object catch (error) {
      _refuse('caption-held', error);
    }
  }

  List<Element> _tree() {
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      _refuse('caption-unavailable');
    }
    final List<Element> all = <Element>[];
    final List<Element> pending = <Element>[root];
    // The application's provider, theme and route ancestry can exceed a
    // recursive depth limit. Bound total work and pending storage explicitly.
    while (pending.isNotEmpty) {
      final Element element = pending.removeLast();
      if (all.length >= 8192) {
        _refuse('caption-tree-capacity-refused');
      }
      if (!element.mounted) {
        _refuse('caption-tree-unmounted');
      }
      all.add(element);
      final List<Element> children = <Element>[];
      element.visitChildElements((Element child) {
        if (all.length + pending.length + children.length >= 8192) {
          _refuse('caption-tree-capacity-refused');
        }
        children.add(child);
      });
      pending.addAll(children.reversed);
    }
    return all;
  }

  AppWindowStatus _current() {
    _remaining();
    final Map<String, Object?> entry = _readEntry();
    if (entry['captures'] != 4 ||
        entry['held'] != false ||
        entry['nativeWindowReady'] != true ||
        entry['startupReady'] != true ||
        entry['welcomeReady'] != true) {
      _refuse('caption-entry-refused');
    }
    final List<Element> all = _tree();
    final List<StatefulElement> frames = all
        .whereType<StatefulElement>()
        .where((StatefulElement e) => e.state is AppWindowFrameState)
        .toList();
    final StatefulElement? original = _element;
    if (frames.length != 1 ||
        original == null ||
        !identical(frames.single, original) ||
        !identical(original.state, _state) ||
        !_state!.mounted) {
      _refuse('caption-original-changed');
    }
    final AppWindowStatus? status = _state!.windowStatus;
    if (status == null ||
        !identical(status.owner, _owner) ||
        !status.attached) {
      _refuse('caption-original-changed');
    }
    if (status.actionHeld ||
        status.queryFailed ||
        status.closing ||
        status.closePending ||
        status.closeFailed) {
      _refuse('caption-held');
    }
    for (final String key in const <String>[
      'window-maximize',
      'window-minimize',
    ]) {
      final List<Element> wrappers = all
          .where((Element e) => e.widget.key == ValueKey<String>(key))
          .toList();
      if (wrappers.length != 1 || !identical(wrappers.single, _wrappers[key])) {
        _refuse('caption-control-changed');
      }
      Element? parent = wrappers.single;
      while (parent != null && !identical(parent, original)) {
        Element? next;
        parent.visitAncestorElements((Element ancestor) {
          next = ancestor;
          return false;
        });
        parent = next;
      }
      if (parent == null) {
        _refuse('caption-control-changed');
      }
      final List<Element> buttons = <Element>[];
      void collect(Element e) {
        if (e.widget is IconButton) {
          buttons.add(e);
        }
        e.visitChildElements(collect);
      }

      collect(wrappers.single);
      if (buttons.length != 1 || !identical(buttons.single, _buttons[key])) {
        _refuse('caption-control-changed');
      }
    }
    return status;
  }

  AppWindowStatus _settled() {
    final AppWindowStatus status = _current();
    if (status.actionPending || status.queryPending || _restorePending) {
      _refuse('caption-pending');
    }
    return status;
  }

  Map<String, Object?> _window(Map<String, Object?> value) {
    List<double> vector(String name, int length, {bool positive = false}) {
      final Object? raw = value[name];
      if (raw is! List ||
          raw.length != length ||
          raw.any(
            (dynamic n) =>
                n is! num ||
                !n.isFinite ||
                n.abs() > 524288 ||
                positive && n <= 0,
          )) {
        _refuse('caption-native-invalid');
      }
      return List<double>.unmodifiable(
        raw.map((dynamic n) => (n as num).toDouble()),
      );
    }

    final List<double> window = vector('window', 4);
    final List<double> client = vector('client', 2, positive: true);
    final List<double> physical = vector('physical', 2, positive: true);
    final Object? ratio = value['devicePixelRatio'];
    if (window[2] <= 0 ||
        window[3] <= 0 ||
        ratio is! num ||
        !ratio.isFinite ||
        ratio <= 0 ||
        ratio > 16 ||
        value['minimized'] is! bool ||
        value['maximized'] is! bool ||
        value['minimized'] == true && value['maximized'] == true ||
        List<int>.generate(2, (int i) => i).any(
          (int i) => (physical[i] - client[i] * ratio).abs() >= 0.01,
        )) {
      _refuse('caption-native-invalid');
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'window': window,
      'client': client,
      'physical': physical,
      'devicePixelRatio': ratio,
      'minimized': value['minimized'],
      'maximized': value['maximized'],
    });
  }

  bool _sameGeometry(Map<String, Object?> actual) {
    final Map<String, Object?> baseline = _baseline!;
    if (!actual.containsKey('window')) {
      return false;
    }
    for (final String key in const <String>['window', 'client', 'physical']) {
      final List<double> a = actual[key]! as List<double>;
      final List<double> b = baseline[key]! as List<double>;
      for (int i = 0; i < a.length; i++) {
        if ((a[i] - b[i]).abs() >= 0.01) {
          return false;
        }
      }
    }
    return actual['devicePixelRatio'] == baseline['devicePixelRatio'];
  }

  Future<Map<String, Object?>> _native({bool geometry = false}) async {
    _current();
    if (_nativePending) {
      _refuse('caption-native-pending');
    }
    _nativePending = true;
    try {
      // Retain the exact original before awaiting; timeout never reopens it.
      _nativeRead = _readWindow(geometry: geometry);
      unawaited(
        _nativeRead.then<void>(
          (_) {
            _nativePending = false;
          },
          onError: (Object error, StackTrace stack) {
            _nativePending = false;
          },
        ),
      );
      final Map<String, Object?> raw = await _bounded(_nativeRead);
      if (raw['minimized'] is! bool ||
          raw['maximized'] is! bool ||
          raw['minimized'] == true && raw['maximized'] == true) {
        _refuse('caption-native-invalid');
      }
      final Map<String, Object?> value;
      if (raw.length == 2 &&
          raw.containsKey('minimized') &&
          raw.containsKey('maximized')) {
        value = Map<String, Object?>.unmodifiable(raw);
      } else {
        value = _window(raw);
      }
      _current();
      return value;
    } on Object catch (error) {
      _refuse('caption-held', error);
    }
  }

  Map<String, Object?> _reply({
    required bool pending,
    required bool settled,
    Map<String, Object?>? window,
  }) => <String, Object?>{
    'captionVersion': 1,
    'stage': _stage,
    'observations': _observations,
    'original': true,
    'held': false,
    'pending': pending,
    'settled': settled,
    'window': window,
  };

  /// Bind once to the actual original frame and both unique keyed controls.
  Future<Map<String, Object?>> bind() async {
    if (_element != null) {
      _refuse('caption-replay-refused');
    }
    final List<Element> all = _tree();
    final List<StatefulElement> frames = all
        .whereType<StatefulElement>()
        .where((StatefulElement e) => e.state is AppWindowFrameState)
        .toList();
    if (frames.length != 1) {
      _refuse('caption-unavailable');
    }
    _element = frames.single;
    _state = frames.single.state as AppWindowFrameState;
    _owner = _state!.windowStatus?.owner;
    for (final String key in const <String>[
      'window-maximize',
      'window-minimize',
    ]) {
      final List<Element> wrappers = all
          .where((Element e) => e.widget.key == ValueKey<String>(key))
          .toList();
      if (wrappers.length != 1) {
        _refuse('caption-control-changed');
      }
      _wrappers[key] = wrappers.single;
      final List<Element> buttons = <Element>[];
      void collect(Element e) {
        if (e.widget is IconButton) {
          buttons.add(e);
        }
        e.visitChildElements(collect);
      }

      collect(wrappers.single);
      if (buttons.length != 1 ||
          (buttons.single.widget as IconButton).onPressed == null) {
        _refuse('caption-control-refused');
      }
      _buttons[key] = buttons.single;
    }
    _settled();
    _baseline = await _native(geometry: true);
    if (!_baseline!.containsKey('client')) {
      _refuse('caption-baseline-refused');
    }
    final List<double> client = _baseline!['client']! as List<double>;
    if (_settled().maximized != false ||
        _baseline!['maximized'] != false ||
        _baseline!['minimized'] != false ||
        (client[0] - 1280).abs() >= 0.01 ||
        (client[1] - 780).abs() >= 0.01) {
      _refuse('caption-baseline-refused');
    }
    _settled();
    return _reply(pending: false, settled: true, window: _baseline);
  }

  /// Admit each real keyed control once, requiring pending in PointerUp's turn.
  Future<Map<String, Object?>> tap(String action) async {
    final int expected = switch (action) {
      'maximize' => 1,
      'restore' => 2,
      'minimize' => 3,
      _ => 0,
    };
    if (expected == 0 ||
        _stage != expected - 1 ||
        _observations != _stage ||
        _baseline == null) {
      _refuse('caption-replay-refused');
    }
    final AppWindowStatus status = _settled();
    if (status.maximized != (expected == 2)) {
      _refuse('caption-control-refused');
    }
    final String key = expected == 3 ? 'window-minimize' : 'window-maximize';
    final Element button = _buttons[key]!;
    if ((button.widget as IconButton).onPressed == null) {
      _refuse('caption-control-refused');
    }
    _stage = expected; // Reserve before any pointer effect.
    _pendingObserved = false;
    try {
      _pointerOriginal = _tap(
        button,
        () {
          final AppWindowStatus fresh = _settled();
          if (fresh.maximized != (expected == 2) ||
              (button.widget as IconButton).onPressed == null) {
            _refuse('caption-control-refused');
          }
        },
        () {
          // Called synchronously after PointerUp, before an await or paint.
          final AppWindowStatus fresh = _current();
          if (!fresh.actionPending) {
            _refuse('caption-pending-unobserved');
          }
          _pendingObserved = true;
        },
      );
      await _bounded(_pointerOriginal);
    } on Object catch (error) {
      _refuse('caption-held', error);
    }
    if (!_pendingObserved) {
      _refuse('caption-pending-unobserved');
    }
    return <String, Object?>{
      'captionVersion': 1,
      'stage': _stage,
      'admitted': true,
      'pendingObserved': true,
    };
  }

  /// Read only retained operation state and independently bounded native facts.
  /// No painted-frame wait occurs here, including while minimized.
  Future<Map<String, Object?>> observe() async {
    final AppWindowStatus status = _current();
    final bool pending =
        status.actionPending || status.queryPending || _restorePending;
    if (pending) {
      return _reply(pending: true, settled: false);
    }
    if (_stage == 0 || _stage < 4 && !_pendingObserved) {
      _refuse('caption-pending-unobserved');
    }
    final Map<String, Object?> native = await _native(
      geometry: _stage == 2 || _stage == 4,
    );
    final AppWindowStatus after = _current();
    if (after.actionPending || after.queryPending || _restorePending) {
      return _reply(pending: true, settled: false);
    }
    final bool maximized = _stage == 1;
    final bool minimized = _stage == 3;
    // Completed native state may precede rebuilding a disabled control.
    // Minimized observation deliberately needs no painted callback.
    final String? nextKey = switch (_stage) {
      1 => 'window-maximize',
      2 => 'window-minimize',
      _ => null,
    };
    final bool nextEnabled =
        nextKey == null ||
        (_buttons[nextKey]!.widget as IconButton).onPressed != null;
    final bool matched =
        after.maximized == maximized &&
        native['maximized'] == maximized &&
        native['minimized'] == minimized &&
        (_stage != 2 && _stage != 4 || _sameGeometry(native)) &&
        nextEnabled;
    if (matched) {
      _observations = _stage;
    }
    return _reply(pending: false, settled: matched, window: native);
  }

  /// One ordinary restore after positive completion of the original minimize.
  /// The original Future is retained even if it fails or outlives this budget.
  Future<Map<String, Object?>> ordinaryRestore(
    Future<void> Function() restore,
  ) async {
    if (_stage != 3 || _observations != 3 || _restoreOriginal != null) {
      _refuse('caption-restore-refused');
    }
    _settled();
    final Map<String, Object?> before = await _native();
    if (before['minimized'] != true || before['maximized'] != false) {
      _refuse('caption-restore-refused');
    }
    _settled();
    _stage = 4;
    _restorePending = true;
    try {
      _restoreOriginal = restore();
      await _bounded(_restoreOriginal!);
      _restorePending = false;
      while (true) {
        final AppWindowStatus status = _current();
        if (!status.actionPending && !status.queryPending) {
          break;
        }
        final Duration remaining = _remaining();
        await Future<void>.delayed(
          remaining < const Duration(milliseconds: 20)
              ? remaining
              : const Duration(milliseconds: 20),
        );
      }
      _settled();
      final Map<String, Object?> after = await _native(geometry: true);
      _settled();
      return after;
    } on Object catch (error) {
      _refuse('caption-held', error);
    }
  }

  /// Reserve the original outer snapshot restoration only after all four facts.
  void requireGeometryRestore() {
    _settled();
    if (_stage != 4 || _observations != 4 || _geometryReserved) {
      _refuse('caption-restore-refused');
    }
    _geometryReserved = true;
  }
}
