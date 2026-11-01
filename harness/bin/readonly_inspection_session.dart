import 'dart:convert';

import '../app/readonly_native_mode.dart';
import 'screen_capture.dart';
import 'wallet_recipe.dart' show WalletRecipeSend;

/// A fixed refusal label never carries private input or response diagnostics.
enum ReadonlyInspectionReason { process, retired, command, reply, binding }

/// No uncertain command can be replayed through this inspection session.
class ReadonlyInspectionRefused
    implements Exception, ScreenCaptureReplyFailure {
  /// The reason is source-defined rather than copied from an original error.
  const ReadonlyInspectionRefused(this.reason, {this._captureReply});

  /// The missing admission, without a profile, address, token or error text.
  final ReadonlyInspectionReason reason;
  final ScreenCaptureReplyCode? _captureReply;

  @override
  ScreenCaptureReplyCode? get captureReply => _captureReply;
}

/// Checks every original reply without rewriting the actual harness mode.
/// The caller retains the original loopback endpoint and process ownership.
class ReadonlyInspectionSession {
  /// Production supplies the original transport; tests own isolated actors.
  ReadonlyInspectionSession({
    required int processId,
    required WalletRecipeSend original,
  }) : this._(processId, original);

  ReadonlyInspectionSession._(this.processId, this._original) {
    if (processId <= 0) {
      _refuse(ReadonlyInspectionReason.process);
    }
  }

  static const Set<String> _commands = <String>{
    'ping', 'state', 'readonly-state', 'readonly-entry', 'lock-view',
    'entry-caption', 'entry-state', 'entry-check', 'entry-capture',
    'tree', 'tap', 'hover', 'type', 'key', 'scroll', 'drag', 'drop',
    'wait', 'assert', 'shot', 'theme', 'logs', 'stalls', 'window', 'quit',
  };

  /// The same native process must answer every subsequent original command.
  final int processId;
  final WalletRecipeSend _original;
  bool _held = false;
  bool _running = false;
  bool _binding = false;
  bool _bindingReserved = false;
  bool _walletBound = false;
  ScreenCaptureReplyCode? _heldReply;

  /// The wallet scope begins only after the actual bind command completes.
  bool get walletBound => _walletBound;

  /// A negative reply is returned unchanged, then permanently holds the lane.
  /// Original exceptions and their traces propagate without another request.
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command,
    Duration timeout,
  ) async {
    if (_held || _running) {
      _refuse(ReadonlyInspectionReason.retired);
    }
    _running = true;
    try {
      final Object? name = command['cmd'];
      if (!_commands.contains(name) &&
          !(name == 'readonly-wallet-bind' && _binding)) {
        _refuse(ReadonlyInspectionReason.command);
      }
      // Nested input must not change while the original HTTP request awaits.
      final Map<String, Object?> retained = Map<String, Object?>.unmodifiable(
        jsonDecode(jsonEncode(command)) as Map<String, dynamic>,
      );
      if (_held) {
        _refuse(ReadonlyInspectionReason.retired);
      }
      final Map<String, dynamic> reply = await _original(retained, timeout);
      if (reply['ok'] != true) {
        _held = true;
        _heldReply = classifyScreenCaptureReply(
          reply['error'], reply['detail'],
        );
        return reply;
      }
      if (_held || !harnessReadonlyNativeLaunchMatches(reply, processId) ||
          (_walletBound &&
              !harnessReadonlyNativeWalletMatches(reply, processId))) {
        _refuse(ReadonlyInspectionReason.reply);
      }
      return reply;
    } on Object {
      _held = true;
      rethrow;
    } finally {
      _running = false;
    }
  }

  /// Reads one completed rail width from the original positive tree reply.
  /// Text is folded into buttons; it is not a separate label-key node.
  Future<bool> railExpanded() async {
    if (!_walletBound) _refuse(ReadonlyInspectionReason.binding);
    final Map<String, dynamic> reply = await send(
      <String, Object?>{'cmd': 'tree'}, const Duration(seconds: 30),
    );
    final Object? nodes = reply['nodes'];
    if (reply['ok'] != true || nodes is! List || nodes.length > 16384) {
      _refuse(ReadonlyInspectionReason.reply);
    }
    Map<String, dynamic>? toggle;
    for (final Object? node in nodes) {
      if (node is! Map<String, dynamic> || node['kind'] == 'error') {
        _refuse(ReadonlyInspectionReason.reply);
      }
      if (node['key'] == 'rail_toggle') {
        if (toggle != null || node['kind'] != 'button' ||
            (node['enabled'] != null && node['enabled'] != true)) {
          _refuse(ReadonlyInspectionReason.reply);
        }
        toggle = node;
      }
    }
    if (toggle == null) _refuse(ReadonlyInspectionReason.reply);
    final Object? rect = toggle['rect'];
    // Original AppTokens widths 56/200, minus the two 8-pixel rail insets.
    // The original agent emits logical [left, top, width, height] integers.
    if (rect is! List || rect.length != 4 ||
        rect.any((Object? value) => value is! int ||
            value < 0 || value > 32768) ||
        rect[3] != 32 || (rect[2] != 40 && rect[2] != 184)) {
      _refuse(ReadonlyInspectionReason.reply);
    }
    return rect[2] == 184;
  }

  /// Prepares only the already opened Home in this bound native session.
  Future<void> prepareScreenHome() => restoreScreenRail(expanded: false);

  /// Restores the Home rail through positive replies from the same process.
  /// A failed script on another page is held rather than navigated blindly.
  Future<void> restoreScreenRail({required bool expanded}) async {
    await _requireScreenHome();
    if (await railExpanded() != expanded) {
      await send(<String, Object?>{'cmd': 'tap', 'key': 'rail_toggle'},
          const Duration(seconds: 30));
      if (await railExpanded() != expanded) {
        _refuse(ReadonlyInspectionReason.reply);
      }
    }
    await _requireScreenHome();
  }

  Future<void> _requireScreenHome() async {
    if (!_walletBound) _refuse(ReadonlyInspectionReason.binding);
    final Map<String, dynamic> state = await send(
      <String, Object?>{'cmd': 'state'}, const Duration(seconds: 30),
    );
    final Object? tabs = state['tabs'];
    if (state['ok'] != true || state['walletUnlocked'] != true ||
        state['walletInitCompleted'] != true ||
        state['tab'] != 'dashboard' || state['locale'] != 'en' ||
        state['direction'] != 'ltr' || tabs is! List ||
        tabs.isEmpty || tabs.length > 16 ||
        tabs.any((Object? value) => value is! String) ||
        tabs.toSet().length != tabs.length || !tabs.contains('dashboard')) {
      _refuse(ReadonlyInspectionReason.reply);
    }
  }

  /// Reserves one original native frame/wallet bind before any transport call.
  Future<Map<String, dynamic>> bindWallet() async {
    if (_held || _running || _bindingReserved) {
      _refuse(ReadonlyInspectionReason.binding);
    }
    _bindingReserved = true;
    _binding = true;
    try {
      final Map<String, dynamic> reply = await send(
        <String, Object?>{'cmd': 'readonly-wallet-bind'},
        const Duration(seconds: 30),
      );
      if (_held || reply['ok'] != true ||
          !harnessReadonlyNativeWalletMatches(reply, processId)) {
        _refuse(ReadonlyInspectionReason.binding);
      }
      _walletBound = true;
      return reply;
    } finally {
      _binding = false;
    }
  }

  Never _refuse(ReadonlyInspectionReason reason) {
    _held = true;
    throw ReadonlyInspectionRefused(reason, captureReply: _heldReply);
  }
}
