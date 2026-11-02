import 'readonly_sdk_admission.dart';
import 'readonly_wallet_admission.dart';

/// A native command cannot establish its original readonly SDK admission.
class ReadonlyNativeCommandRefused implements Exception {
  /// The refused command supplies no successful native observation.
  const ReadonlyNativeCommandRefused();
}

/// Reserves a fresh native lane before startup receives private commands.
/// Its receipt covers SDK admission; wallet and image acceptance stay separate.
class ReadonlyNativeCommands {
  /// Retains the real agent readiness source and original command callback.
  ReadonlyNativeCommands({
    required bool Function() isBooted,
    required Future<Map<String, Object?>> Function(
      Map<String, dynamic> command,
    ) original,
    Future<ReadonlyWalletAdmission> Function()? bindWallet,
    int? processId,
  }) : this._(isBooted, original, bindWallet, processId);

  ReadonlyNativeCommands._(
    this._isBooted, this._original, this._bindWallet, this._processId,
  );

  static const Set<String> _allowed = <String>{
    'ping',
    'state',
    'lock-view',
    'entry-caption',
    'entry-state',
    'entry-check',
    'entry-capture',
    'tree',
    'tap',
    'hover',
    'type',
    'key',
    'scroll',
    'drag',
    'drop',
    'wait',
    'assert',
    'shot',
    'theme',
    'logs',
    'stalls',
    'window',
    'quit',
    'readonly-entry',
  };

  final bool Function() _isBooted;
  final Future<Map<String, Object?>> Function(
    Map<String, dynamic> command,
  ) _original;
  final Future<ReadonlyWalletAdmission> Function()? _bindWallet;
  final int? _processId;
  ReadonlySdkAdmission? _admission;
  ReadonlyWalletAdmission? _wallet;
  bool _walletReserved = false;
  bool _attachReserved = false;
  bool _held = false;
  bool _running = false;

  /// Attaches one sealed original SDK before reporting native readiness.
  void attach(ReadonlySdkAdmission admission) {
    if (_held || _attachReserved || _running || _booted()) _refuse();
    _attachReserved = true;
    _admission = admission;
    _requireSdk();
  }

  /// Calls an admitted original once, preserving its error and stack trace.
  /// Replacing owners or enabling automatic receive permanently holds the lane.
  Future<Map<String, Object?>> run(Map<String, dynamic> command) async {
    if (_held || _running) _refuse();
    final Map<String, dynamic> retained =
        Map<String, dynamic>.unmodifiable(command);
    final Object? name = retained['cmd'] ?? 'ping';
    final bool booted = _booted();
    if (_admission == null || !booted) {
      if (booted) _refuse();
      if (name != 'ping' ||
          retained.keys.any((String key) => key != 'cmd')) {
        throw const ReadonlyNativeCommandRefused();
      }
      if (_admission != null) _requireSdk();
      return const <String, Object?>{
        'booted': false,
        'harnessMode': 'readonly-native',
        'readOnly': true,
        'readonlyAdmission': <String, Object>{
          'schema': 1,
          'scope': 'readonly_native_sdk_admission',
          'status': 'PENDING',
        },
      };
    }
    _requireReady();
    if (name == 'readonly-wallet-bind') {
      if (retained.keys.any((String key) => key != 'cmd') ||
          _walletReserved || _bindWallet == null) {
        _refuse();
      }
      _walletReserved = true;
      _running = true;
      try {
        final ReadonlyWalletAdmission original = await _bindWallet();
        _wallet = original;
        _requireReady();
        return _receipt();
      } on Object {
        _held = true;
        rethrow;
      } finally {
        _running = false;
      }
    }
    if (name == 'readonly-state') {
      if (retained.keys.any((String key) => key != 'cmd')) {
        throw const ReadonlyNativeCommandRefused();
      }
      return <String, Object?>{
        'booted': true,
        ..._receipt(),
      };
    }
    if (name is! String || !_allowed.contains(name)) {
      throw const ReadonlyNativeCommandRefused();
    }
    _running = true;
    try {
      final Map<String, Object?> result = await _original(retained);
      _requireReady();
      return <String, Object?>{...result, ..._receipt()};
    } on Object {
      // An expected UI refusal can leave the SDK current. If either owner
      // observation fails, it remains held without replacing the UI error.
      try {
        _requireReady();
      } on Object {
        // Keep the original action's exact error and stack trace below.
      }
      rethrow;
    } finally {
      _running = false;
    }
  }

  bool _booted() {
    try {
      return _isBooted();
    } on Object {
      _held = true;
      rethrow;
    }
  }

  void _requireReady() {
    _requireSdk();
    if (!_booted()) _refuse();
    try {
      _wallet?.requireCurrent();
    } on Object {
      _held = true;
      rethrow;
    }
  }

  void _requireSdk() {
    final ReadonlySdkAdmission? admission = _admission;
    if (_held || admission == null) _refuse();
    try {
      admission.requireCurrent();
    } on Object {
      _held = true;
      rethrow;
    }
  }

  Map<String, Object?> _receipt() => <String, Object?>{
    'booted': true,
    if (_processId != null) 'pid': _processId,
    'harnessMode': 'readonly-native',
    'readOnly': true,
    'readonlyAdmission': const <String, Object>{
      'schema': 1,
      'scope': 'readonly_native_sdk_admission',
      'status': 'CURRENT',
      'publicationAdmissionPaused': true,
      'automaticReceiveDisabled': true,
    },
    if (_wallet != null)
      'readonlyWallet': const <String, Object>{
        'schema': 1,
        'scope': 'readonly_native_wallet_admission',
        'status': 'CURRENT',
        'chain': 321,
        'selectedIndex': 1,
        'nativeFrameObserved': true,
      },
  };

  Never _refuse() {
    _held = true;
    throw const ReadonlyNativeCommandRefused();
  }
}
