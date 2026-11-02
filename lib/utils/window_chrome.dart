import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Other desktop platforms keep their existing native titlebars and layout.
bool get usesAppWindowFrame =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Runs after the original manager initializes, before the app builds.
/// This changes the original Windows HWND's chrome, never its title or owner.
Future<void> configureAppWindowChrome() async {
  if (usesAppWindowFrame) {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  }
}

/// The original native window's operations. The test seam creates no window.
abstract class AppWindowBackend {
  /// Observe events from this same original window.
  void addListener(WindowListener listener);

  /// Remove only the listener admitted by this owner.
  void removeListener(WindowListener listener);

  /// Read actual native maximized state.
  Future<bool> isMaximized();

  /// Request maximization without asserting the resulting mode.
  Future<void> maximize();

  /// Request restoration of a maximized window.
  Future<void> unmaximize();

  /// Request native minimization.
  Future<void> minimize();

  /// Start the original native drag operation.
  Future<void> startDragging();

  /// Open the original Windows system menu.
  Future<void> popUpWindowMenu();

  /// Request the application's original native close protocol.
  Future<void> close();
}

class _NativeWindowBackend implements AppWindowBackend {
  _NativeWindowBackend() : _window = windowManager;

  final WindowManager _window;

  @override
  void addListener(WindowListener listener) => _window.addListener(listener);

  @override
  void removeListener(WindowListener listener) =>
      _window.removeListener(listener);

  @override
  Future<bool> isMaximized() => _window.isMaximized();

  @override
  Future<void> maximize() => _window.maximize();

  @override
  Future<void> unmaximize() => _window.unmaximize();

  @override
  /// Admit one native minimize request without changing observed mode.
  Future<void> minimize() => _window.minimize();

  @override
  /// Admit one drag through the captured original native window.
  Future<void> startDragging() => _window.startDragging();

  @override
  Future<void> popUpWindowMenu() => _window.popUpWindowMenu();

  @override
  Future<void> close() => _window.close();
}

/// An immutable observation of one caption owner's current operation state.
/// It grants no native action authority and does not assert process completion.
@immutable
class AppWindowStatus {
  /// Captures finite facts without retaining an action interface.
  const AppWindowStatus({
    required this.owner,
    required this.attached,
    required this.maximized,
    required this.queryPending,
    required this.queryFailed,
    required this.actionPending,
    required this.actionHeld,
    required this.closing,
    required this.closePending,
    required this.closeFailed,
  });

  /// Stable opaque identity of the original caption controller.
  final Object owner;

  /// Whether that original controller has not been disposed.
  final bool attached;

  /// Last positively observed native mode, or unknown.
  final bool? maximized;

  /// Whether an original state query remains unsettled.
  final bool queryPending;

  /// Whether the last accepted state query failed.
  final bool queryFailed;

  /// Whether a conflicting native action remains unsettled.
  final bool actionPending;

  /// Whether a failed native action permanently holds conflicting controls.
  final bool actionHeld;

  /// Whether close was admitted or observed, without claiming process exit.
  final bool closing;

  /// Whether this controller's original close Future remains unsettled.
  final bool closePending;

  /// Whether that original close Future failed.
  final bool closeFailed;
}

/// Serializes caption actions on one captured backend. A void acknowledgement
/// never establishes native mode. Close remains the original application's
/// prevent-close callback; it never destroys or shuts down a window.
class AppWindowController extends ChangeNotifier with WindowListener {
  AppWindowController._(this._window) {
    _window.addListener(this);
    unawaited(refreshMaximized());
  }

  /// Capture the existing singleton and attach one additional listener.
  factory AppWindowController.native() =>
      AppWindowController._(_NativeWindowBackend());

  /// Attach to a caller-owned fake without initializing a native window.
  @visibleForTesting
  factory AppWindowController.forTesting(AppWindowBackend window) =>
      AppWindowController._(window);

  final AppWindowBackend _window;
  final Object _identity = Object();
  bool _disposed = false;
  bool _queryPending = false;
  bool _actionPending = false;
  bool _refreshQueued = false;
  bool _closing = false;
  bool _closePending = false;
  int _revision = 0;
  bool? _maximized;

  // Retain only the latest original Futures and failures.
  // They remain private and bounded.
  late Future<bool> _query;
  late Future<void> _action;
  late Future<void> _close;
  Object? _queryError;
  Object? _actionError;
  Object? _closeError;

  /// Current immutable facts from this same controller.
  AppWindowStatus get status => AppWindowStatus(
    owner: _identity,
    attached: !_disposed,
    maximized: _maximized,
    queryPending: _queryPending,
    queryFailed: queryFailed,
    actionPending: _actionPending,
    actionHeld: actionHeld,
    closing: _closing,
    closePending: _closePending,
    closeFailed: closeFailed,
  );

  /// Last positively observed native maximized state.
  bool? get maximized => _maximized;

  /// A failed native action blocks further conflicting effects.
  bool get actionHeld => _actionError != null;

  /// A query failure disables toggle without disabling independent close.
  bool get queryFailed => _queryError != null;

  /// Whether the one admitted close failed.
  bool get closeFailed => _closeError != null;

  /// A close has been admitted or observed; no replay is allowed.
  bool get closing => _closing;

  /// An original state query is still pending.
  bool get queryPending => _queryPending;

  /// An original mutation is still pending.
  bool get actionPending => _actionPending;

  /// The independently admitted original close is still pending.
  bool get closePending => _closePending;

  /// Close can be admitted once even when another action is held.
  bool get canClose => !_disposed && !_closing;

  /// No conflicting or failed native mutation is held.
  bool get canMinimize =>
      !_disposed && !_closing && !_actionPending && !actionHeld;

  /// A positive mode observation additionally permits toggle.
  bool get canToggleMaximize =>
      canMinimize && !_queryPending && _maximized != null;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// One actual observation, also used after a genuine native mode event.
  Future<void> refreshMaximized() async {
    if (_disposed || _closing || _queryPending || _actionPending) {
      return;
    }
    _queryPending = true;
    final int revision = _revision;
    _notify();
    try {
      _query = _window.isMaximized();
      final bool observed = await _query;
      if (!_disposed && !_closing && revision == _revision) {
        _maximized = observed;
        _queryError = null;
      }
    } on Object catch (error) {
      if (!_disposed && revision == _revision) {
        _maximized = null;
        _queryError = error;
      }
    } finally {
      _queryPending = false;
      _notify();
      _drainModeEvent();
    }
  }

  void _drainModeEvent() {
    if (_refreshQueued &&
        !_disposed &&
        !_closing &&
        !_actionPending &&
        !_queryPending) {
      _refreshQueued = false;
      unawaited(refreshMaximized());
    }
  }

  void _modeChanged() {
    if (_disposed || _closing) {
      return;
    }
    _revision++;
    _maximized = null;
    _refreshQueued = true;
    _notify();
    _drainModeEvent();
  }

  @override
  void onWindowClose() {
    if (_disposed || _closing) {
      return;
    }
    _closing = true;
    _notify();
    // The original application listener alone owns the shutdown sequence.
  }

  @override
  void onWindowMaximize() => _modeChanged();

  @override
  void onWindowUnmaximize() => _modeChanged();

  @override
  void onWindowRestore() => _modeChanged();

  /// Query afresh, act once, then observe actual mode independently.
  Future<void> toggleMaximize() async {
    if (!canToggleMaximize) {
      return;
    }
    _actionPending = true;
    _revision++;
    _maximized = null;
    _notify();
    final int revision = _revision;
    _queryPending = true;
    bool? observed;
    try {
      _query = _window.isMaximized();
      observed = await _query;
      _queryError = null;
    } on Object catch (error) {
      _queryError = error;
    } finally {
      _queryPending = false;
    }
    if (revision != _revision) {
      observed = null;
    }
    if (!_disposed && !_closing && observed != null) {
      try {
        _action = observed ? _window.unmaximize() : _window.maximize();
        await _action;
      } on Object catch (error) {
        _actionError = error;
      }
    }
    _actionPending = false;
    _notify();
    // Observe the result; neither the requested mode nor void acknowledgement
    // is evidence of the actual original window's maximized state.
    if (!_disposed && !_closing && observed != null && !actionHeld) {
      _refreshQueued = false;
      await refreshMaximized();
    } else {
      _drainModeEvent();
    }
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (!canMinimize) {
      return;
    }
    _actionPending = true;
    _revision++;
    // A concurrent older read cannot describe the result of this new action.
    if (_queryPending) {
      _refreshQueued = true;
    }
    _notify();
    try {
      _action = operation();
      await _action;
    } on Object catch (error) {
      _actionError = error;
    } finally {
      _actionPending = false;
      _notify();
      _drainModeEvent();
    }
  }

  /// Admit one native minimize request without changing observed mode.
  Future<void> minimize() => _perform(_window.minimize);

  /// Admit one drag through the captured original native window.
  Future<void> startDragging() => _perform(_window.startDragging);

  /// Admit the original system menu without taking over its actions.
  Future<void> showMenu() => _perform(_window.popUpWindowMenu);

  /// Independently admit one original close even if another action is held.
  Future<void> close() async {
    if (!canClose) {
      return;
    }
    _closing = true;
    _closePending = true;
    _notify();
    try {
      _close = _window.close();
      await _close;
    } on Object catch (error) {
      _closeError = error;
    } finally {
      _closePending = false;
      _notify();
    }
    // A failed or pending close is never replayed or reported as process exit.
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _window.removeListener(this);
    super.dispose();
  }
}
