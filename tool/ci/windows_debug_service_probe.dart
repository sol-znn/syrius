// The qualification tool uses vm_service already pinned in pubspec.lock.
// It adds no application dependency and runs only in an isolated CI profile.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart' as vm;

const int _messageCap = 2 * 1024 * 1024;
const int _serviceCap = 8 * 1024 * 1024;
const Duration _requestLimit = Duration(seconds: 10);

final class _Refused implements Exception {
  const _Refused(this.code);

  final String code;
}

void _need(bool value, String code) {
  if (!value) throw _Refused(code);
}

void _admit(List<String> arguments) {
  final Map<String, String> env = Platform.environment;
  final String root = Directory.current.absolute.path;
  final String separator = Platform.pathSeparator;
  final String prefix =
      '$root$separator.harness${separator}ci-windows-debug-';
  final String? profile = env['SYRIUS_WINDOWS_DEBUG_PROFILE'];
  _need(
    arguments.isEmpty &&
        Platform.isWindows &&
        env['GITHUB_ACTIONS'] == 'true' &&
        env['RUNNER_OS'] == 'Windows' &&
        env['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
        env['GITHUB_WORKSPACE'] == root &&
        RegExp(r'^[0-9a-f]{40}$').hasMatch(env['GITHUB_SHA'] ?? '') &&
        profile != null &&
        profile.startsWith(prefix) &&
        RegExp(r'^[0-9a-f]{24}$').hasMatch(
          profile.substring(prefix.length),
        ) &&
        env['HOME'] == profile &&
        env['USERPROFILE'] == profile &&
        env['APPDATA'] ==
            '$profile${separator}AppData${separator}Roaming' &&
        env['LOCALAPPDATA'] ==
            '$profile${separator}AppData${separator}Local' &&
        env['TEMP'] == '$profile${separator}Temp' &&
        env['TMP'] == '$profile${separator}Temp',
    'ENVIRONMENT_REFUSED',
  );
}

String _serviceAddress(Object? value) {
  _need(value is String && value.length <= 4096, 'ENDPOINT_REFUSED');
  final String original = value! as String;
  final Uri address = Uri.parse(original);
  _need(
    address.scheme == 'ws' &&
        address.host == '127.0.0.1' &&
        address.userInfo.isEmpty &&
        address.hasPort &&
        address.port >= 1024 &&
        address.port <= 65535 &&
        !address.hasQuery &&
        !address.hasFragment &&
        address.pathSegments.length == 2 &&
        RegExp(r'^[A-Za-z0-9_=-]{1,256}$').hasMatch(
          address.pathSegments.first,
        ) &&
        address.pathSegments.last == 'ws',
    'ENDPOINT_REFUSED',
  );
  return original;
}

final class _OriginalService {
  WebSocket? _socket;
  vm.VmService? _service;
  StreamSubscription<dynamic>? _subscription;
  int _received = 0;
  bool _bound = false;
  int? _pid;
  String? _isolate;
  String? _library;
  String? _rootUri;
  String _phase = 'new';

  Future<void> _root() async {
    final vm.VmService service = _service!;
    final vm.VM machine = await service.getVM().timeout(_requestLimit);
    _need(machine.pid == _pid, 'PID_REFUSED');
    final List<vm.IsolateRef> references =
        machine.isolates ?? <vm.IsolateRef>[];
    _need(references.isNotEmpty && references.length <= 32, 'ISOLATE_REFUSED');
    final String expected = File(
      'harness/app/main.dart',
    ).absolute.uri.toString().toLowerCase();
    final List<vm.Isolate> matches = <vm.Isolate>[];
    for (final vm.IsolateRef reference in references) {
      final String? identifier = reference.id;
      if (identifier == null || reference.isSystemIsolate == true) continue;
      final vm.Isolate isolate = await service.getIsolate(
        identifier,
      ).timeout(_requestLimit);
      if (isolate.rootLib?.uri?.toLowerCase() == expected &&
          isolate.runnable == true) {
        matches.add(isolate);
      }
    }
    _need(matches.length == 1 && matches.single.rootLib?.id != null,
        'ISOLATE_REFUSED');
    _isolate = matches.single.id;
    _library = matches.single.rootLib!.id;
    _rootUri = matches.single.rootLib!.uri;
  }

  Future<void> bind(Map<String, dynamic> command) async {
    _need(!_bound && _socket == null, 'SEQUENCE_REFUSED');
    final Object? requestedPid = command['pid'];
    _need(
      requestedPid is int && requestedPid > 0 && requestedPid < 0x100000000,
      'PID_REFUSED',
    );
    final String address = _serviceAddress(command['wsUri']);
    final WebSocket socket = await WebSocket.connect(
      address,
    ).timeout(_requestLimit);
    _socket = socket;
    final StreamController<dynamic> input = StreamController<dynamic>();
    final Completer<void> closed = Completer<void>();
    _subscription = socket.listen(
      (dynamic data) {
        if (data is! String) {
          input.addError(const _Refused('SERVICE_OUTPUT_REFUSED'));
          unawaited(socket.close());
          return;
        }
        final int size = utf8.encode(data).length;
        _received += size;
        if (size > _messageCap || _received > _serviceCap) {
          input.addError(const _Refused('SERVICE_OUTPUT_REFUSED'));
          unawaited(socket.close());
          return;
        }
        input.add(data);
      },
      onError: (Object _) {
        input.addError(const _Refused('SERVICE_IO_REFUSED'));
      },
      onDone: () {
        if (!closed.isCompleted) closed.complete();
        unawaited(input.close());
      },
    );
    final vm.VmService service = vm.VmService.defaultFactory(
      inStream: input.stream,
      writeMessage: (String message) {
        _need(utf8.encode(message).length <= 32768, 'SERVICE_OUTPUT_REFUSED');
        socket.add(message);
      },
      disposeHandler: socket.close,
      streamClosed: closed.future,
      wsUri: address,
    );
    _service = service;
    _pid = requestedPid! as int;
    await _root();
    _bound = true;
    _phase = 'bound';
  }

  Future<vm.Response> _invoke() => _service!.invoke(
        _isolate!, _library!, 'harnessDebugLoopMarker', <String>[],
        disableBreakpoints: false,
      ).timeout(_requestLimit);

  void _value(vm.Response value, String expected) {
    _need(value is vm.InstanceRef && value.valueAsString == expected,
        'MARKER_REFUSED');
  }

  Future<void> breakpoint() async {
    _need(_phase == 'bound', 'SEQUENCE_REFUSED');
    final vm.VmService service = _service!;
    final List<String> lines = await File('harness/app/main.dart').readAsLines();
    final List<int> candidates = <int>[
      for (int index = 0; index < lines.length; index++)
        if (lines[index].endsWith('// SYRIUS_DEBUG_BREAKPOINT')) index + 1,
    ];
    _need(candidates.length == 1, 'SOURCE_REFUSED');
    await service.streamListen('Debug').timeout(_requestLimit);
    final vm.Breakpoint point = await service.addBreakpointWithScriptUri(
      _isolate!, _rootUri!, candidates.single,
    ).timeout(_requestLimit);
    _need(point.id != null, 'BREAKPOINT_REFUSED');
    final Completer<void> hit = Completer<void>();
    final StreamSubscription<vm.Event> events = service.onDebugEvent.listen(
      (vm.Event event) {
        if (event.kind == 'PauseBreakpoint' && event.isolate?.id == _isolate &&
            (event.pauseBreakpoints ?? <vm.Breakpoint>[]).any(
              (vm.Breakpoint actual) => actual.id == point.id,
            ) && !hit.isCompleted) {
          hit.complete();
        }
      },
    );
    bool resumed = false;
    try {
      final Future<vm.Response> invocation = _invoke();
      // Consume a failed invocation while waiting for its corresponding event.
      unawaited(
        invocation.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (!hit.isCompleted) {
              hit.completeError(const _Refused('BREAKPOINT_REFUSED'));
            }
          },
        ),
      );
      await hit.future.timeout(_requestLimit);
      await service
          .removeBreakpoint(_isolate!, point.id!)
          .timeout(_requestLimit);
      await service.resume(_isolate!).timeout(_requestLimit);
      resumed = true;
      _value(await invocation, '1');
      _phase = 'breakpoint';
    } finally {
      if (!resumed) {
        final vm.Isolate isolate = await service
            .getIsolate(_isolate!)
            .timeout(_requestLimit);
        if (isolate.pauseEvent?.kind == 'PauseBreakpoint') {
          await service.resume(_isolate!).timeout(_requestLimit);
        }
      }
      await events.cancel();
    }
  }

  Future<void> observe(String phase) async {
    _need((phase == 'reload' && _phase == 'breakpoint') ||
        (phase == 'restart' && _phase == 'reload'), 'SEQUENCE_REFUSED');
    final String? previous = _isolate;
    await _root();
    _need(phase == 'reload' ? _isolate == previous : _isolate != previous,
        'ISOLATE_REFUSED');
    _value(await _invoke(), phase == 'reload' ? '2' : '1');
    _phase = phase;
  }

  Future<void> close() async {
    await _service?.dispose().timeout(_requestLimit);
    await _subscription?.cancel().timeout(_requestLimit);
    await _socket?.close().timeout(_requestLimit);
  }
}

Future<void> main(List<String> arguments) async {
  final _OriginalService original = _OriginalService();
  bool closed = false;
  try {
    _admit(arguments);
    int bytes = 0;
    final Stream<List<int>> bounded = stdin.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (List<int> data, EventSink<List<int>> sink) {
          bytes += data.length;
          if (bytes > 32768) {
            sink.addError(const _Refused('INPUT_REFUSED'));
          } else {
            sink.add(data);
          }
        },
      ),
    );
    await for (final String line in bounded
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 90))) {
      final Object? decoded = jsonDecode(line);
      _need(decoded is Map<String, dynamic>, 'INPUT_REFUSED');
      final Map<String, dynamic> command = decoded! as Map<String, dynamic>;
      if (command['action'] == 'bind') {
        await original.bind(command);
        stdout.writeln(
          jsonEncode(<String, Object>{
            'ok': true,
            'phase': 'bound',
            'pidMatched': true,
            'rootMatched': true,
            'debugLoopQualified': false,
          }),
        );
      } else if (command['action'] == 'breakpoint' ||
          command['action'] == 'reload' || command['action'] == 'restart') {
        final String phase = command['action'] as String;
        if (phase == 'breakpoint') {
          await original.breakpoint();
        } else {
          await original.observe(phase);
        }
        stdout.writeln(jsonEncode(<String, Object>{
          'ok': true, 'phase': phase, 'debugLoopQualified': false,
        }));
      } else if (command['action'] == 'close') {
        _need(original._bound, 'SEQUENCE_REFUSED');
        await original.close();
        closed = true;
        stdout.writeln(
          jsonEncode(<String, Object>{'ok': true, 'phase': 'closed'}),
        );
        break;
      } else {
        throw const _Refused('INPUT_REFUSED');
      }
    }
    _need(closed, 'CLOSE_UNCONFIRMED');
  } on Object catch (error) {
    exitCode = 1;
    stdout.writeln(
      jsonEncode(<String, Object>{
        'ok': false,
        'code': error is _Refused ? error.code : 'INTERNAL_ERROR',
      }),
    );
  } finally {
    if (!closed) {
      try {
        await original.close();
      } on Object {
        exitCode = 1;
      }
    }
  }
}
