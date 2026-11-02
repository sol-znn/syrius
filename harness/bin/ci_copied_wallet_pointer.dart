// One closed hosted copy; never an ordinary wallet entry point.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';

import 'copied_wallet_pointer.dart';

/// The listener remains active during Hive operations so parent EOF is visible.
final class CopiedPointerInput {
  CopiedPointerInput(Stream<List<int>> source) {
    _subscription = source.listen(_add, onError: (Object _) => _refuse(),
      onDone: () { _alive = false; _signal(); });
  }

  late final StreamSubscription<List<int>> _subscription;
  final Queue<String> _lines = Queue<String>();
  final List<int> _pending = <int>[];
  Completer<void>? _changed;
  bool _alive = true;
  bool _failed = false;
  bool _reading = false;
  int _bytes = 0;
  int _records = 0;

  bool get alive => _alive && !_failed;

  void _signal() {
    final Completer<void>? changed = _changed;
    _changed = null;
    if (changed != null && !changed.isCompleted) changed.complete();
  }

  void _refuse() {
    _failed = true;
    _signal();
  }

  void _add(List<int> chunk) {
    if (!alive) return;
    _bytes += chunk.length;
    if (_bytes > 4 * 32768) { _refuse(); return; }
    for (final int byte in chunk) {
      if (byte < 0 || byte > 255 || _pending.length >= 32768) {
        _refuse(); return;
      }
      if (byte == 10) {
        if (_pending.isEmpty || ++_records > 4 || _lines.length >= 2) {
          _refuse(); return;
        }
        try {
          _lines.add(utf8.decode(_pending));
        } on FormatException {
          _refuse(); return;
        }
        _pending.clear();
        _signal();
      } else {
        _pending.add(byte);
      }
    }
  }

  Future<String> read() async {
    if (!alive || _reading) {
      throw const FormatException('private input refused');
    }
    _reading = true;
    try {
      while (alive && _lines.isEmpty) {
        _changed ??= Completer<void>();
        await _changed!.future;
      }
      if (!alive) throw const FormatException('private input refused');
      return _lines.removeFirst();
    } finally {
      _reading = false;
    }
  }

  Future<void> close() async {
    _alive = false;
    _signal();
    await _subscription.cancel();
  }
}

/// Fixed labels retain the failing step without formatting private errors.
String copiedPointerFailureMarker(String phase, Object error) {
  const Set<String> phases = <String>{'gate', 'input', 'binding', 'finish'};
  final String stage = phases.contains(phase) ? phase : 'unknown';
  final String detail = error is CopiedWalletPointerRefused
      ? error.phase.name
      : 'unknown';
  return 'CI_POINTER_ERROR:$stage:$detail';
}

Future<void> main() async {
  CopiedPointerInput? input;
  String phase = 'gate';
  try {
    final Map<String, String> env = Platform.environment;
    if (!Platform.isWindows || env['GITHUB_ACTIONS'] != 'true' ||
        env['GITHUB_EVENT_NAME'] != 'workflow_dispatch' ||
        env['SYRIUS_HOSTED_RUNNER'] != 'github-hosted' ||
        env['GITHUB_REPOSITORY'] != 'edgepillar/syrius' ||
        env['SYRIUS_COPIED_POINTER_BINDING'] != 'true') {
      throw const FormatException('hosted gate refused');
    }
    final CopiedPointerInput originalInput = CopiedPointerInput(stdin);
    input = originalInput;
    Future<void> marker(String value) async {
      stdout.writeln(value);
      await stdout.flush();
    }
    if (await originalInput.read() != 'START') {
      throw const FormatException('ownership gate refused');
    }
    await marker('CI_POINTER_READY');
    phase = 'input';
    final Object? decoded = jsonDecode(await originalInput.read());
    const Set<String> fields = <String>{
      'originalHome', 'restoredHome', 'cacheRelative', 'originalWallet',
    };
    if (decoded is! Map<String, dynamic> || decoded.length != fields.length ||
        !decoded.keys.toSet().containsAll(fields) ||
        !decoded.values.every((dynamic value) => value is String &&
          value.isNotEmpty && value.length <= 4096)) {
      throw const FormatException('private paths refused');
    }
    phase = 'binding';
    bool claimed = false;
    await bindCopiedWalletPointer(hive: Hive,
      originalHome: decoded['originalHome'] as String,
      restoredHome: decoded['restoredHome'] as String,
      originalWallet: decoded['originalWallet'] as String,
      cacheRelative: decoded['cacheRelative'] as String,
      closed: () => originalInput.alive && phase == 'binding',
      claim: () async {
        if (claimed || !originalInput.alive) {
          throw const FormatException('claim refused');
        }
        claimed = true;
        await marker('CI_POINTER_CLAIM');
        if (await originalInput.read() != 'APPROVE') {
          throw const FormatException('claim refused');
        }
      });
    if (!claimed || !originalInput.alive) {
      throw const FormatException('binding unconfirmed');
    }
    phase = 'finish';
    await marker('CI_POINTER_DONE');
    if (await originalInput.read() != 'FINISH') {
      throw const FormatException('closure unconfirmed');
    }
  } on Object catch (error) {
    stdout.writeln(copiedPointerFailureMarker(phase, error));
    await stdout.flush();
    exitCode = 1;
  } finally {
    await input?.close();
  }
}
