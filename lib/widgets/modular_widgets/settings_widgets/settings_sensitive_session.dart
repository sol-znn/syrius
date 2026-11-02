import 'package:material_ui/material_ui.dart';

/// Seed actions use only their captured original wallet and route guard.
abstract interface class SettingsSensitiveSession {
  /// Includes wallet identity, initialization, revision and section epoch.
  bool get isCurrent;

  /// Hardware seeds never leave their device.
  bool get isHardwareWallet;

  /// Authenticates the original file, then releases its exact acquisition.
  Future<List<String>> revealSeed(
    String password, {
    required bool Function() isCurrent,
  });

  /// Retains the existing unlocked-wallet Seed Vault action.
  Future<String> readExportSeed({required bool Function() isCurrent});

  /// False is picker cancellation. True is an original completed write.
  Future<bool> exportVault({
    required String seed,
    required String password,
    required bool Function() isCurrent,
  });
}

/// A test-injected owned password action. Production has no default backend.
abstract interface class SettingsPasswordSession {
  /// The original action must still own the child and wallet.
  bool get isCurrent;

  /// Owns the entire operation; no legacy close/reopen helper is invoked.
  Future<void> changePassword(String currentPassword, String newPassword);
}

/// Owns one sensitive route chain, including its intentional child coverage.
class SettingsSensitiveRoutes {
  SettingsRouteLease? _active;
  bool _closed = false;

  /// A second saved callback cannot overwrite the original owned route.
  bool get busy => _active != null;

  /// Reserves the route synchronously, before Navigator can notify observers.
  Future<void> open({
    required NavigatorState navigator,
    required bool Function() isCurrent,
    required Widget Function(SettingsRouteLease lease) builder,
  }) async {
    if (_closed || busy || !navigator.mounted || !isCurrent()) {
      return;
    }
    final SettingsRouteLease lease = SettingsRouteLease._(
      navigator,
      isCurrent,
    );
    _active = lease;
    try {
      await lease.push(builder);
    } finally {
      lease.close();
      if (identical(_active, lease)) {
        _active = null;
      }
    }
  }

  /// Removes only this owner's exact routes, never an unrelated covering one.
  void close() {
    _closed = true;
    _active?.close();
  }
}

/// Exact route receipts shared by the two existing Seed Vault steps.
class SettingsRouteLease {
  SettingsRouteLease._(this._navigator, this._isCurrent);

  /// Adopts an existing export step and owns only its exact child chain.
  SettingsRouteLease.attached({
    required this._navigator,
    required Route<void> route,
    required this._isCurrent,
  }) {
    _routes.add(route);
  }

  final NavigatorState _navigator;
  final bool Function() _isCurrent;
  final List<Route<void>> _routes = <Route<void>>[];
  bool _closed = false;
  int _epoch = 0;

  /// Coverage by an owned child is allowed; unrelated coverage is refused.
  bool get isCurrent =>
      !_closed &&
      _navigator.mounted &&
      _isCurrent() &&
      _routes.isNotEmpty &&
      _routes.last.isCurrent;

  /// Binds an operation to the exact current child, never a later child.
  bool Function() capture() {
    final Route<void>? route = _routes.isEmpty ? null : _routes.last;
    final int epoch = _epoch;
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            epoch != _epoch || !isCurrent || !identical(route, _routes.last));
  }

  /// Pushes the next owned step while retaining the preceding Back route.
  Future<void> push(Widget Function(SettingsRouteLease lease) builder) async {
    if (_closed || !_navigator.mounted || !_isCurrent()) {
      return;
    }
    if (_routes.isNotEmpty && !_routes.last.isCurrent) {
      return;
    }
    final MaterialPageRoute<void> route = MaterialPageRoute<void>(
      builder: (BuildContext _) => builder(this),
    );
    _epoch++;
    _routes.add(route);
    try {
      await _navigator.push<void>(route);
      await route.completed;
    } finally {
      _epoch++;
      _routes.remove(route);
    }
  }

  /// Back refuses a covering route, even from a retained old callback.
  void back(bool Function() isCurrent) {
    if (isCurrent() && this.isCurrent) {
      _navigator.pop();
    }
  }

  /// A completed export removes only this exact owned route chain.
  void complete(bool Function() isCurrent) {
    if (!isCurrent() || !this.isCurrent) {
      return;
    }
    close();
  }

  /// Revokes before scheduling removal, so no late secret can be displayed.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _epoch++;
    final List<Route<void>> owned = List<Route<void>>.of(_routes.reversed);
    WidgetsBinding.instance
      ..addPostFrameCallback((Duration _) {
        if (_navigator.mounted) {
          for (final Route<void> route in owned) {
            if (route.isActive) {
              _navigator.removeRoute(route);
            }
          }
        }
      })
      ..scheduleFrame();
  }
}

/// Captures the exact current screen and denies unobserved route round trips.
class SettingsScreenScope {
  /// The mounted predicate belongs to the original State object.
  SettingsScreenScope({required this._mounted});

  final bool Function() _mounted;
  ModalRoute<void>? _route;
  NavigatorState? _navigator;
  SettingsRouteLease? _lease;
  bool Function()? _source;
  bool? _wasCurrent;
  int _epoch = 0;

  /// Call from didChangeDependencies so route coverage revokes saved actions.
  void bind(
    BuildContext context, {
    SettingsRouteLease? lease,
    bool Function()? isCurrent,
  }) {
    final ModalRoute<void>? route = ModalRoute.of<void>(context);
    final bool current = route?.isCurrent ?? false;
    if (!identical(route, _route) || _wasCurrent != current) {
      _epoch++;
    }
    _route = route;
    _navigator = Navigator.of(context);
    _wasCurrent = current;
    _lease = lease;
    _source = isCurrent;
  }

  /// Also revoke when a widget replaces its injected original session.
  void revoke() => _epoch++;

  /// The closure freezes the source rather than reading a replacement widget.
  bool Function() capture() {
    final int epoch = _epoch;
    final ModalRoute<void>? route = _route;
    final NavigatorState? navigator = _navigator;
    final bool Function()? source = _source;
    final bool Function()? owned = _lease?.capture();
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            !_mounted() ||
            epoch != _epoch ||
            route == null ||
            !route.isCurrent ||
            navigator == null ||
            !navigator.mounted ||
            (source != null && !source()) ||
            (owned != null && !owned()));
  }

  /// Removes the captured screen only while it is still the current route.
  void back(bool Function() isCurrent) {
    if (isCurrent()) {
      _navigator?.pop();
    }
  }
}
