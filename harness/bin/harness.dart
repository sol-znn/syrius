// The outside half of the harness: builds and launches the harnessed wallet
// in a profile of its own, and sends it commands. Plain Dart, no packages.
//
//   dart harness/bin/harness.dart <command> [arguments] [--flags]
//
// See harness/README.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../app/fixtures/seed_policy.dart';
import '../app/presentation_mode.dart';
import '../app/readonly_native_mode.dart';
import '../home_preparation_observation.dart';
import '../seed/seed_recipe.dart';
import '../seed_preparation_failure.dart' show seedPreparationUiFailureCodes;
import 'build_output.dart';
import 'screen_capture.dart';
import 'wallet_recipe.dart';

final String repo = File.fromUri(Platform.script).parent.parent.parent.path;
final String stateRoot = '$repo${Platform.pathSeparator}.harness';

class Fail implements Exception, ScreenCaptureReplyFailure {
  Fail(this.message, {
    HomeTapReply? homeTapReply, ScreenCaptureReplyCode? captureReply,
  }) : _homeTapReply = homeTapReply, _captureReply = captureReply;
  final String message;
  final HomeTapReply? _homeTapReply;
  final ScreenCaptureReplyCode? _captureReply;
  @override
  ScreenCaptureReplyCode? get captureReply => _captureReply;
  @override
  String toString() => message;
}

class Args {
  Args(List<String> raw) {
    for (int i = 0; i < raw.length; i++) {
      final String a = raw[i];
      if (a.startsWith('--') && a.length > 2) {
        final String name = a.substring(2);
        final int eq = name.indexOf('=');
        final String option = eq > 0 ? name.substring(0, eq) : name;
        if (option == 'chain' && flags.containsKey(option)) {
          throw Fail('the chain option is ambiguous');
        }
        if (eq > 0) {
          flags[name.substring(0, eq)] = name.substring(eq + 1);
        } else if (_valued.contains(name) && i + 1 < raw.length) {
          flags[name] = raw[++i];
        } else {
          flags[name] = 'true';
        }
      } else {
        rest.add(a);
      }
    }
  }

  static const Set<String> _valued = <String>{
    'instance',
    'mode',
    'port',
    'kind',
    'nth',
    'type',
    'key',
    'timeout',
    'min',
    'out',
    'settle',
    'since',
    'limit',
    'levels',
    'password',
    'mnemonic',
    'node',
    'chain',
    'width',
    'height',
    'dir',
    'tab',
    'max',
    'ws',
    'http',
    'counterparty',
    'presentation',
    'metadata',
  };

  final Map<String, String> flags = <String, String>{};
  final List<String> rest = <String>[];

  bool has(String f) => flags.containsKey(f);
  String? operator [](String f) => flags[f];
  int? integer(String f) => flags[f] == null ? null : int.parse(flags[f]!);
}

class Instance {
  Instance(this.name) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(name)) {
      throw Fail('instance names contain only letters, digits, _ and -');
    }
  }

  final String name;

  String get home => '$stateRoot${Platform.pathSeparator}$name';
  File get file => File('$home${Platform.pathSeparator}instance.json');

  Map<String, dynamic>? read() => file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : null;

  Future<Map<String, dynamic>> send(
    Map<String, Object?> cmd, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final Map<String, dynamic>? info = read();
    if (info == null) {
      throw Fail('instance "$name" was never started; run `start`');
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final HttpClientRequest req = await client
          .post(
            '127.0.0.1',
            info['port'] as int,
            '/',
          )
          .timeout(timeout);
      req.headers
        ..set('x-harness-token', info['token'] as String)
        ..contentType = ContentType.json;
      req.write(jsonEncode(cmd));
      final HttpClientResponse res = await req.close().timeout(timeout);
      final String body = await utf8.decoder.bind(res).join().timeout(timeout);
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException {
      throw Fail('instance "$name" is not running; run `start`');
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> alive() async {
    if (read() == null) return false;
    try {
      return (await send(<String, Object?>{
            'cmd': 'ping',
          }, timeout: const Duration(seconds: 3)))['ok'] ==
          true;
    } on Object catch (_) {
      return false;
    }
  }
}

// ------------------------------------------------------------------ selectors

/// `12` or `#12` is a ref from the last tree, `@x,y` a point, anything else
/// text. `--key`, `--type`, `--kind`, `--nth` and `--exact` narrow it.
Map<String, Object?> selector(String? s, Args a) {
  final Map<String, Object?> sel = <String, Object?>{};
  if (s != null && s.isNotEmpty) {
    final RegExpMatch? ref = RegExp(r'^#?(\d+)$').firstMatch(s);
    final RegExpMatch? at = RegExp(r'^@(-?\d+),(-?\d+)$').firstMatch(s);
    if (ref != null) {
      sel['ref'] = int.parse(ref.group(1)!);
    } else if (at != null) {
      sel['at'] = <int>[int.parse(at.group(1)!), int.parse(at.group(2)!)];
    } else {
      sel['text'] = s;
    }
  }
  if (a.has('key')) sel['key'] = a['key'];
  if (a.has('type')) sel['type'] = a['type'];
  if (a.has('kind')) sel['kind'] = a['kind'];
  if (a.has('tab')) sel['tab'] = a['tab'];
  if (a.has('nth')) sel['nth'] = a.integer('nth');
  if (a.has('exact')) sel['exact'] = true;
  if (a.has('force')) sel['force'] = true;
  if (a.has('settle')) sel['settleMs'] = a.integer('settle');
  return sel;
}

String describe(Map<String, dynamic> n) {
  final StringBuffer b = StringBuffer()
    ..write('[${n['ref']}]'.padRight(6))
    ..write((n['kind'] as String).padRight(9));
  String label = (n['label'] as String? ?? '').replaceAll('\n', ' ');
  if (label.length > 110) label = '${label.substring(0, 107)}...';
  if (label.isNotEmpty) b.write('"$label" ');
  for (final String k in <String>[
    'tab',
    'value',
    'hint',
    'labelText',
    'error',
    'tip',
    'checked',
    'icons',
    'key',
  ]) {
    if (n[k] != null) b.write('$k=${jsonEncode(n[k])} ');
  }
  for (final String k in <String>['obscured', 'focused']) {
    if (n[k] == true) b.write('$k ');
  }
  if (n['enabled'] == false) b.write('DISABLED ');
  final List<num> r = (n['rect'] as List<dynamic>).cast<num>();
  final List<dynamic> path = n['path'] as List<dynamic>? ?? <dynamic>[];
  final String where = path.isEmpty || path.last == n['type']
      ? '${n['type']}'
      : '${path.last}>${n['type']}';
  b.write(' $where @${r[0] + r[2] ~/ 2},${r[1] + r[3] ~/ 2}');
  return b.toString();
}

void printTree(Map<String, dynamic> t) {
  final List<dynamic> size = t['size'] as List<dynamic>;
  stdout.writeln('view ${size[0]}x${size[1]}');
  for (final dynamic n in t['nodes'] as List<dynamic>) {
    stdout.writeln(describe(n as Map<String, dynamic>));
  }
}

// ------------------------------------------------------------------- commands

Future<void> build(Args a, {bool isolatedInput = false}) async {
  final String mode = a['mode'] ?? 'release';
  final Process p = await Process.start(
    'flutter',
    <String>[
      'build', 'windows', '--$mode', '-t', 'harness/app/main.dart',
      if (a.has('no-pub')) '--no-pub',
      if (a['metadata'] != null) '--dart-define-from-file=${a['metadata']}',
    ],
    workingDirectory: repo,
    runInShell: true,
    mode: isolatedInput
        ? ProcessStartMode.normal
        : ProcessStartMode.inheritStdio,
  );
  final int code = isolatedInput
      ? await finishIsolatedBuild(p)
      : await p.exitCode;
  if (code != 0) throw Fail('flutter build failed');
  final String cap = mode[0].toUpperCase() + mode.substring(1);
  final Directory from = Directory('$repo/build/windows/x64/runner/$cap');
  final Directory to = Directory('$stateRoot/app/$mode');
  // A copy of its own: the next ordinary `flutter build` overwrites build/.
  // What is in it goes, not the folder: Windows refuses to delete a folder
  // another process still holds open (a shell left standing in it), and
  // that failed a build whose compile had succeeded.
  if (to.existsSync()) {
    for (final FileSystemEntity old in to.listSync()) {
      old.deleteSync(recursive: true);
    }
  }
  int files = 0;
  for (final FileSystemEntity e in from.listSync(recursive: true)) {
    final String rel = e.path.substring(from.path.length);
    if (e is Directory) {
      Directory('${to.path}$rel').createSync(recursive: true);
    } else if (e is File) {
      File('${to.path}$rel').parent.createSync(recursive: true);
      e.copySync('${to.path}$rel');
      files++;
    }
  }
  stdout.writeln('built $mode: ${to.path} ($files files)');
}

Future<int> freePort() async {
  final ServerSocket s = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = s.port;
  await s.close();
  return port;
}

/// A separate CI controller may explicitly select a fresh inspection host.
/// The ordinary command line always retains its default wallet startup.
Future<void> start(
  Instance inst,
  Args a, {
  bool readonlyNative = false,
}) async {
  final String? presentation = harnessPresentationSurface(a['presentation']);
  if (readonlyNative) {
    try {
      requireReadonlyNativeLaunch(
        Platform.environment,
        windows: Platform.isWindows,
        instance: inst.name,
        fresh: a.has('fresh'),
        presentation: presentation,
      );
    } on ReadonlyNativeModeRefused {
      throw Fail(
        'native inspection requires an explicit unused Windows CI profile',
      );
    }
    final FileSystemEntityType parent = FileSystemEntity.typeSync(
      stateRoot,
      followLinks: false,
    );
    if ((parent != FileSystemEntityType.directory &&
            parent != FileSystemEntityType.notFound) ||
        FileSystemEntity.typeSync(inst.home, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw Fail('native inspection needs an unused profile without links');
    }
  }
  if (presentation != null && (inst.name == 'default' || a.has('fresh'))) {
    throw Fail('presentation needs an explicit unused instance, without fresh');
  }
  if (!readonlyNative && await inst.alive()) {
    final Map<String, dynamic> observed = await call(
      inst,
      <String, Object?>{'cmd': 'ping'},
    );
    final Object? expectedPid = inst.read()?['pid'];
    if (expectedPid is! int ||
        !harnessLaunchMatches(
          observed,
          presentation: presentation,
          expectedPid: expectedPid,
          readonlyNative: readonlyNative,
        )) {
      throw Fail('the instance is already running another harness host');
    }
    stdout.writeln('instance "${inst.name}" is already running');
    return;
  }
  if (presentation != null) {
    final FileSystemEntityType parent = FileSystemEntity.typeSync(
      stateRoot,
      followLinks: false,
    );
    if ((parent != FileSystemEntityType.directory &&
            parent != FileSystemEntityType.notFound) ||
        FileSystemEntity.typeSync(inst.home, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw Fail('presentation needs an unused profile without links');
    }
  }
  final String mode = a['mode'] ?? 'release';
  final File exe = File('$stateRoot/app/$mode/syrius.exe');
  if (!exe.existsSync()) {
    throw Fail('no $mode build of the harness; run `build` first');
  }
  // The Windows runner looks for a window titled "s y r i u s" and, finding
  // one, hands over and exits: one wallet per desktop, harnessed or not.
  final ProcessResult running = Process.runSync('tasklist', <String>[
    '/fi',
    'imagename eq syrius.exe',
    '/fo',
    'csv',
    '/nh',
  ]);
  if ((running.stdout as String).toLowerCase().contains('syrius.exe')) {
    throw Fail(
      'a syrius.exe is already running; Syrius is single-instance, close it '
      'first\n${(running.stdout as String).trim()}',
    );
  }
  final Directory home = Directory(inst.home);
  if (!readonlyNative && a.has('fresh') && home.existsSync()) {
    home.deleteSync(recursive: true);
  }
  final String sep = Platform.pathSeparator;
  final String roaming = '${home.path}${sep}AppData${sep}Roaming';
  final String local = '${home.path}${sep}AppData${sep}Local';
  final String temp = '${home.path}${sep}Temp';
  for (final String d in <String>[roaming, local, temp]) {
    Directory(d).createSync(recursive: true);
  }
  final int port = a.integer('port') ?? await freePort();
  final Random rnd = Random.secure();
  final String token = List<String>.generate(
    16,
    (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  // Every place the wallet, its SDK and its embedded node look for a profile
  // goes into the instance home; nothing reads the real %AppData%\znn.
  final Map<String, String> env = harnessLaunchEnvironment(
    Platform.environment,
    profileHome: home.path,
    appData: roaming,
    localAppData: local,
    temporary: temp,
    port: port,
    token: token,
    presentation: presentation,
    readonlyNative: readonlyNative,
    windows: Platform.isWindows,
  );
  final Process p = await Process.start(
    exe.path,
    <String>[],
    environment: env,
    includeParentEnvironment: false,
    workingDirectory: exe.parent.path,
    mode: ProcessStartMode.detached,
  );
  inst.file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'pid': p.pid,
      'port': port,
      'token': token,
      'mode': mode,
      'harnessMode': readonlyNative
          ? 'readonly-native'
          : presentation == null ? 'wallet' : 'presentation',
      'presentationScreen': ?presentation,
      'started': DateTime.now().toUtc().toIso8601String(),
    }),
  );
  final Stopwatch sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 60)) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final Map<String, dynamic> r;
    try {
      r = await inst.send(<String, Object?>{
        'cmd': 'ping',
      }, timeout: const Duration(seconds: 3));
    } on Fail {
      // Not listening yet.
      continue;
    }
    if (r['booted'] == true) {
      if (!harnessLaunchMatches(
        r,
        presentation: presentation,
        expectedPid: p.pid,
        readonlyNative: readonlyNative,
      )) {
        throw Fail('the original process and harness host were not observed');
      }
      stdout.writeln(
        'started "${inst.name}": pid ${p.pid}, port $port, home ${home.path}',
      );
      return;
    }
  }
  throw Fail('the wallet did not come up within 60 s (pid ${p.pid})');
}

bool pidAlive(int pid) =>
    (Process.runSync('tasklist', <String>[
              '/fi',
              'pid eq $pid',
              '/fo',
              'csv',
              '/nh',
            ]).stdout
            as String)
        .contains('"$pid"');

Future<void> stop(Instance inst) async {
  final Map<String, dynamic>? info = inst.read();
  if (info == null) throw Fail('instance "${inst.name}" was never started');
  final int pid = info['pid'] as int;
  if (!pidAlive(pid)) {
    stdout.writeln('not running');
    return;
  }
  try {
    await inst.send(<String, Object?>{'cmd': 'quit'});
  } on Fail {
    // Fall through to the kill.
  }
  final Stopwatch sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 12)) {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!pidAlive(pid)) {
      stdout.writeln('stopped');
      return;
    }
  }
  Process.runSync('taskkill', <String>['/pid', '$pid', '/f', '/t']);
  stdout.writeln('killed (the wallet did not exit on its own)');
}

/// Sends one command and returns the reply, throwing on `ok: false`.
Future<Map<String, dynamic>> call(
  Instance inst,
  Map<String, Object?> cmd,
) async {
  final Map<String, dynamic> r = await inst.send(cmd);
  if (r['ok'] != true) {
    final Object? detail = r['detail'];
    throw Fail(
      '${cmd['cmd']}: ${r['error']}'
      '${detail == null ? '' : ' ${jsonEncode(detail)}'}'
      '${r['stack'] == null ? '' : '\n${r['stack']}'}',
      homeTapReply: classifyHomeTapReply(r['error']),
      captureReply: classifyScreenCaptureReply(r['error'], detail),
    );
  }
  return r;
}

void report(Map<String, dynamic> r, Args a, {String? note}) {
  if (a.has('json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(r));
    return;
  }
  final Map<String, dynamic>? t = r['target'] as Map<String, dynamic>?;
  stdout.writeln(
    <String>[
      'ok',
      ?note,
      if (t != null) describe(t),
    ].join('  '),
  );
}

Map<String, Object?> assertionArgs(Args a) {
  const Set<String> allowed = <String>{
    'key',
    'type',
    'kind',
    'tab',
    'nth',
    'exact',
  };
  if (a.rest.length > 1 ||
      a.flags.keys.any((String f) => !allowed.contains(f))) {
    throw Fail(
      'assert <selector> [--key <key>] uses a stable positive selector',
    );
  }
  final Map<String, Object?> sel = selector(
    a.rest.isEmpty ? null : a.rest.first,
    a,
  );
  if (sel.containsKey('at') ||
      sel.containsKey('ref') ||
      !<String>['text', 'key', 'type', 'tab'].any(sel.containsKey) ||
      (a.integer('nth') ?? 0) < 0) {
    throw Fail(
      'assert needs text, key, type or tab; coordinates and refs expire',
    );
  }
  return <String, Object?>{...sel, 'exact': true};
}

Future<void> run(Instance inst, String command, Args a) async {
  final List<String> r = a.rest;
  String? arg(int i) => i < r.length ? r[i] : null;

  switch (command) {
    case 'build':
      await build(a);
    case 'start':
      await start(inst, a);
    case 'stop':
      await stop(inst);
    case 'status':
      final bool up = await inst.alive();
      stdout.writeln(up ? 'running' : 'stopped');
      if (up) {
        stdout.writeln(
          const JsonEncoder.withIndent(
            '  ',
          ).convert(await call(inst, <String, Object?>{'cmd': 'state'})),
        );
      }
    case 'state':
      stdout.writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(await call(inst, <String, Object?>{'cmd': 'state'})),
      );
    case 'tree':
      final Map<String, dynamic> t = await call(inst, <String, Object?>{
        'cmd': 'tree',
        if (a.has('kind')) 'kind': a['kind'],
      });
      if (a.has('json')) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(t));
      } else {
        printTree(t);
      }
    case 'tap':
    case 'hover':
      report(
        await call(inst, <String, Object?>{
          'cmd': command,
          ...selector(arg(0), a),
          for (final String f in <String>['right', 'long', 'double'])
            if (a.has(f)) f: true,
        }),
        a,
      );
    case 'type':
      // `type <selector> <text>`, or `type <text>` into the focused field.
      final bool aimed = r.length >= 2 || a.has('key') || a.has('type');
      final Map<String, dynamic> out = await call(inst, <String, Object?>{
        'cmd': 'type',
        ...selector(aimed && r.length >= 2 ? r[0] : null, a),
        'value': r.isEmpty ? '' : r.last,
        if (a.has('append')) 'append': true,
        if (a.has('submit')) 'submit': true,
      });
      report(out, a, note: 'value=${jsonEncode(out['value'])}');
    case 'key':
      final Map<String, dynamic> out = await call(inst, <String, Object?>{
        'cmd': 'key',
        'key': arg(0) ?? (throw Fail('key <chord>, e.g. enter, shift+tab')),
        if (a.has('settle')) 'settleMs': a.integer('settle'),
      });
      report(out, a, note: out['handled'] == true ? 'handled' : 'unhandled');
    case 'scroll':
      // `scroll <dy>` at the centre, or `scroll <selector> <dy>`.
      report(
        await call(inst, <String, Object?>{
          'cmd': 'scroll',
          ...selector(r.length >= 2 ? r[0] : null, a),
          'dy': num.parse(r.isEmpty ? '300' : r.last),
        }),
        a,
      );
    case 'drag':
      final List<String> by =
          (arg(1) ?? (throw Fail('drag <selector> <dx,dy>'))).split(',');
      report(
        await call(inst, <String, Object?>{
          'cmd': 'drag',
          ...selector(arg(0), a),
          'by': <num>[num.parse(by[0]), num.parse(by[1])],
        }),
        a,
      );
    case 'drop':
      final String file = arg(1) ?? (throw Fail('drop <selector> <file>'));
      report(
        await call(inst, <String, Object?>{
          'cmd': 'drop',
          ...selector(arg(0), a),
          'path': File(file).absolute.path,
        }),
        a,
      );
    case 'wait':
      final Map<String, dynamic> out = await call(inst, <String, Object?>{
        'cmd': 'wait',
        ...selector(arg(0), a),
        if (a.has('gone')) 'gone': true,
        if (a.has('timeout'))
          'timeoutMs': (num.parse(a['timeout']!) * 1000).round(),
      });
      report(out, a, note: '${out['ms']} ms');
    case 'assert':
      report(
        await call(inst, <String, Object?>{
          'cmd': 'assert',
          ...assertionArgs(a),
        }),
        a,
      );
    case 'theme':
      if (r.length != 1 || (r.first != 'dark' && r.first != 'light')) {
        throw Fail('theme dark|light');
      }
      stdout.writeln(
        jsonEncode(
          await call(inst, <String, Object?>{
            'cmd': 'theme',
            'mode': r.first,
          }),
        ),
      );
    case 'presentation':
      if (r.length != 1 ||
          a.flags.keys.any(
            (String flag) => !<String>{'instance', 'json'}.contains(flag),
          )) {
        throw Fail('presentation <surface> [--instance <name>]');
      }
      final String surface = harnessPresentationSurface(r.single)!;
      stdout.writeln(
        jsonEncode(
          await call(inst, <String, Object?>{
            'cmd': 'presentation',
            'surface': surface,
          }),
        ),
      );
    case 'screens':
      if (r.length != 1 ||
          a.flags.keys.any(
            (String f) => !<String>{'instance', 'dir', 'json'}.contains(f),
          )) {
        throw Fail('screens <id>|all [--dir .harness/<fresh-directory>]');
      }
      if ((await stateOf(inst))['harnessMode'] == 'presentation') {
        throw Fail('presentation previews cannot create wallet capture proof');
      }
      final List<String> paths = await ScreenCapture(
        repository: Directory(repo),
        call: (Map<String, Object?> command) => call(inst, command),
        prepareHome: () => prepareScreenHome(inst),
        runLine: (List<String> words) =>
            run(inst, words.first, Args(words.sublist(1))),
        assertionFor: (List<String> words) =>
            assertionArgs(Args(words.sublist(1))),
        readRailState: () => screenRailExpanded(inst),
        restoreRailState: ({required bool expanded}) =>
            restoreScreenRail(inst, expanded: expanded),
      ).capture(r.first, directory: a['dir']);
      if (a.has('json')) {
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'captures': paths,
            'client': <int>[1280, 780],
            'scale': 1,
          }),
        );
      } else {
        for (final String path in paths) {
          stdout.writeln('$path  1280x780 (logical scale 1)');
        }
      }
    case 'shot':
      final Map<String, dynamic> s = await call(inst, <String, Object?>{
        'cmd': 'shot',
      });
      final String out =
          a['out'] ??
          '${inst.home}${Platform.pathSeparator}shots${Platform.pathSeparator}'
              '${DateTime.now().millisecondsSinceEpoch}.png';
      File(out)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(s['png'] as String));
      stdout.writeln(
        '$out  ${s['width']}x${s['height']} (scale ${s['scale']})',
      );
    case 'logs':
      final Map<String, dynamic> out = await call(inst, <String, Object?>{
        'cmd': 'logs',
        if (a.has('since')) 'since': a.integer('since'),
        if (a.has('limit')) 'limit': a.integer('limit'),
        if (a.has('levels')) 'levels': a['levels']!.split(','),
      });
      if (a.has('json')) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
      } else {
        for (final Map<String, dynamic> l
            in (out['logs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          stdout.writeln(
            '${l['seq']} ${l['time']} ${l['level']} ${l['logger']}: '
            '${l['message']}${l['error'] == null ? '' : ' | ${l['error']}'}',
          );
        }
        stdout.writeln('seq ${out['seq']}');
      }
    case 'stalls':
      final Map<String, dynamic> out = await call(inst, <String, Object?>{
        'cmd': 'stalls',
        if (a.has('reset')) 'reset': true,
        if (a.has('min')) 'min': a.integer('min'),
      });
      if (a.has('brief')) {
        stdout.writeln(
          <String>[
            for (final Map<String, dynamic> s
                in (out['stalls'] as List<dynamic>)
                    .cast<Map<String, dynamic>>())
              '${s['kind']} ${s['ms']}',
          ].join(', '),
        );
      } else {
        for (final Map<String, dynamic> s
            in (out['stalls'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          stdout.writeln('${s['time']} ${s['kind']} ${s['ms']} ms');
        }
      }
      stdout.writeln('longest ${out['longestMs']} ms');
    case 'clipboard':
      stdout.writeln(
        (await call(inst, <String, Object?>{
          'cmd': 'clipboard',
          if (arg(0) != null) 'value': arg(0),
        }))['text'],
      );
    case 'window':
      stdout.writeln(
        jsonEncode(
          await call(inst, <String, Object?>{
            'cmd': 'window',
            if (arg(0) != null) 'do': arg(0),
            if (a.has('width')) 'width': a.integer('width'),
            if (a.has('height')) 'height': a.integer('height'),
          }),
        ),
      );
    case 'run':
      await script(inst, arg(0) ?? (throw Fail('run <file>')), a);
    case 'seed':
      await seed(inst, a);
    case 'lab-send':
      const Set<String> allowed = <String>{'instance', 'ws', 'http', 'json'};
      if (a.rest.isNotEmpty ||
          !a.flags.keys.every(allowed.contains) ||
          a['ws'] != seedWsOrigin || a['http'] != seedHttpOrigin) {
        throw Fail('lab-send requires the exact explicit owned lab origins');
      }
      report(await call(inst, <String, Object?>{
        'cmd': 'lab-send', 'profile': inst.name,
        'ws': seedWsOrigin, 'http': seedHttpOrigin,
      }), a);
    default:
      if (!await recipe(inst, command, a)) {
        throw Fail('unknown command "$command"; see harness/README.md');
      }
  }
  if (a.has('tree') && command != 'tree') {
    printTree(await call(inst, <String, Object?>{'cmd': 'tree'}));
  }
}

/// Only source-defined seed refusal labels may leave an original command.
const Set<String> seedOperationReplyCodes = <String>{
  'advancing-momentum-required',
  'ambiguous-original-publication',
  'bounded-seed-wait-required',
  'close-current-fixture-first',
  'confirmed-token-presentation-required',
  'original-deposit-entry-changed',
  'original-deposit-entry-held',
  'original-deposit-entry-required',
  'original-token-presentation-changed',
  'original-token-presentation-close-pending',
  'original-token-presentation-held',
  'original-token-presentation-required',
  'confirmed-deposit-presentation-required',
  'original-deposit-presentation-changed',
  'original-deposit-presentation-close-pending',
  'original-deposit-presentation-held',
  'original-deposit-presentation-required',
  'confirmed-project-presentation-required',
  'original-project-presentation-changed',
  'original-project-presentation-close-pending',
  'original-project-presentation-held',
  'original-project-presentation-required',
  'earlier-original-unresolved',
  'earlier-seed-attempt-held',
  'enabled-preparation-control-required',
  'enabled-publication-control-required',
  'exact-chain-321-lab-required',
  'exact-confirmation-or-effect-pending',
  'exact-confirmation-pending',
  'exact-confirmation-required',
  'exact-original-lab-transports-required',
  'exact-original-receipt-mismatch',
  'explicit-lab-origins-required',
  'explicit-seed-begin-required',
  'external-lab-counterparty-required',
  'fixture-expired',
  'fixture-publication-refused',
  'fixture-route-changed',
  'fixture-route-unavailable',
  'funded-index-one-required',
  'funded-selected-index-required',
  'invalid-lab-frontier',
  'invalid-original-hash',
  'isolated-checkpoint-prerequisite-required',
  'isolated-unlocked-profile-required',
  'lab-endpoints-disagree',
  'lab-frontier-regressed',
  'lab-http-frontier-incomplete',
  'lab-http-response-refused',
  'lab-http-response-too-large',
  'lab-http-rpc-refused',
  'one-seed-publication-required',
  'original-attempt-held',
  'original-context-changed',
  'original-hash-changed',
  'original-outcome-unknown',
  'original-publication-replaced',
  'original-send-form-changed',
  'original-send-form-required',
  'original-send-review-already-captured',
  'original-send-review-button-changed',
  'original-send-review-center-changed',
  'original-send-review-dialog-changed',
  'original-send-review-draft-changed',
  'original-send-review-intent-changed',
  'original-send-review-required',
  'original-transfer-attempt-held',
  'original-transfer-review-mismatch',
  'original-transfer-review-required',
  'original-transfer-witness-required',
  'owned-isolated-profile-required',
  'recipe-prerequisite-missing',
  'restored-seed-derivation-refused',
  'restored-seed-exact-receipt-required',
  'restored-seed-membership-required',
  'restored-seed-owner-changed',
  'restored-seed-parent-unavailable',
  'restored-seed-session-held',
  'seed-command-refused',
  'seed-journal-held',
  'seed-preparation-selector-refused',
  'seed-preparation-error-widget',
  'seed-preparation-target-covered',
  'seed-preparation-target-disabled',
  'seed-preparation-target-missing',
  'seed-prerequisite-or-read-failed',
  'seed-publication-selector-refused',
  'seed-recipe-prerequisite-missing',
  'seed-script-after-publication-refused',
  'seed-script-command-refused',
  'seed-script-key-refused',
  'seed-script-prerequisite-missing',
  'seed-script-route-refused',
  'seed-script-substitution-refused',
  'token-publication-requires-guarded-publish',
  'unknown-fixture',
  'unknown-recipe',
  'unlocked-wallet-required',
};

/// Exact closed labels, without formatting or returning an unknown payload.
String seedOperationReplyCode(Object? value) {
  if (value is! String || value.length > 128) return 'unknown';
  const String prefix = 'Seed refused: ';
  final String code = value.startsWith(prefix)
      ? value.substring(prefix.length) : value;
  return seedOperationReplyCodes.contains(code) ? code : 'unknown';
}

/// Original seed operations; these labels cannot start or repeat an action.
enum SeedOperationAction {
  source, begin, home, check, prepare, publish, command, finish,
}

/// The last original boundary entered before its first refusal.
enum SeedOperationStep {
  read, parse, resolve, owner, request, reply, navigation, execute,
}

/// Exception families disclose no error text, paths or input material.
enum SeedOperationFailureKind {
  refused, timeout, format, type, filesystem, state, other,
}

/// The immutable finite observation of one original seed failure.
class SeedOperationFailure extends Fail {
  SeedOperationFailure._(Map<String, Object> value)
      : diagnostic = Map<String, Object>.unmodifiable(value),
        super('seed: original operation refused');

  /// A failure receipt carries no publication or retry permission.
  final Map<String, Object> diagnostic;
}

/// Passive state for the current original recipe, with no I/O or callbacks.
class SeedOperationTrace {
  /// Records the source recipe, independently of its private input values.
  SeedOperationTrace(this._recipe);

  final String _recipe;
  SeedOperationAction _action = SeedOperationAction.source;
  SeedOperationStep _step = SeedOperationStep.read;
  int _commandIndex = 0;
  bool _publicationCallEntered = false;
  String _replyCode = 'unknown';
  Map<String, Object>? _confirmation;
  final HomePreparationTrace _homeObservation = HomePreparationTrace();

  /// Marks a boundary without invoking, replacing or waiting on an operation.
  void at(SeedOperationAction action, SeedOperationStep step, {
    int? commandIndex,
  }) {
    _action = action;
    _step = step;
    if (commandIndex != null) _commandIndex = commandIndex;
    _replyCode = 'unknown';
    _confirmation = null;
    _homeObservation.clear();
  }

  /// Marks entry to the original transport call, not delivery or acceptance.
  void publicationCallEntered() => _publicationCallEntered = true;

  /// Retains only an exact code from the already received original reply.
  void refusedReply(Object? value, {Object? confirmation}) {
    _replyCode = seedOperationReplyCode(value);
    _confirmation = seedRecipeIds.contains(_recipe) &&
            _action == SeedOperationAction.publish &&
            _step == SeedOperationStep.reply && _publicationCallEntered &&
            _replyCode == 'exact-confirmation-or-effect-pending'
        ? seedConfirmationProjection(confirmation) : null;
  }

  bool get _homeScope => seedRecipeIds.contains(_recipe) &&
      _action == SeedOperationAction.home &&
      _step == SeedOperationStep.navigation && _commandIndex == 0 &&
      !_publicationCallEntered;

  /// Records only the current original Home call before recipe command one.
  void homeObserved(HomePreparationStep step, {
    Map<String, dynamic>? state, String? target,
  }) {
    if (_homeScope) {
      _homeObservation.observe(step, state: state, target: target);
    }
  }

  /// Freezes metadata without reading the exception's message or stack.
  SeedOperationFailure failure(Object error) {
    final SeedOperationFailureKind kind = switch (error) {
      Fail() || SeedRefused() => SeedOperationFailureKind.refused,
      TimeoutException() => SeedOperationFailureKind.timeout,
      FormatException() => SeedOperationFailureKind.format,
      TypeError() || RangeError() => SeedOperationFailureKind.type,
      FileSystemException() || SocketException() =>
          SeedOperationFailureKind.filesystem,
      StateError() => SeedOperationFailureKind.state,
      _ => SeedOperationFailureKind.other,
    };
    final String observedReason = error is SeedRefused
        ? seedOperationReplyCode(error.code) : _replyCode;
    final bool misplacedPreparation =
        seedPreparationUiFailureCodes.contains(observedReason) &&
        (kind != SeedOperationFailureKind.refused ||
            _action != SeedOperationAction.prepare ||
            _step != SeedOperationStep.reply || _publicationCallEntered);
    final String reason = misplacedPreparation ? 'unknown' : observedReason;
    final Map<String, Object>? homeObservation =
        _homeScope ? _homeObservation.failureSnapshot(
          error is Fail ? error._homeTapReply : null,
        ) : null;
    return SeedOperationFailure._(<String, Object>{
      'schema': 1, 'scope': 'original_seed_operation_failure',
      'recipe': seedRecipeIds.contains(_recipe) ? _recipe : 'unknown',
      'action': _action.name, 'step': _step.name,
      'command_index': _commandIndex >= 0 && _commandIndex <= 96
          ? _commandIndex : 0,
      'publication_call_entered': _publicationCallEntered,
      'kind': kind.name,
      'reason': reason,
      'home': ?homeObservation,
      if (kind == SeedOperationFailureKind.refused &&
          reason == 'exact-confirmation-or-effect-pending' &&
          _confirmation != null) 'confirmation': _confirmation!,
    });
  }
}

SeedOperationAction _seedOperationAction(Object? value) => switch (value) {
  'begin' => SeedOperationAction.begin,
  'check' => SeedOperationAction.check,
  'prepare' => SeedOperationAction.prepare,
  'publish' => SeedOperationAction.publish,
  'finish' => SeedOperationAction.finish,
  _ => SeedOperationAction.source,
};

/// A fixed, preflighted source recipe; no nested script or lifecycle command.
Future<Map<String, dynamic>> seed(
  Instance inst, Args a, {
  Future<void> Function()? requireOwner,
}) async {
  const Set<String> allowed = <String>{
    'instance',
    'ws',
    'http',
    'counterparty',
    'checkpoint-ready',
    'json',
  };
  if (!a.has('instance') ||
      inst.name == 'default' ||
      a['ws'] != seedWsOrigin ||
      a['http'] != seedHttpOrigin ||
      a.flags.keys.any((String flag) => !allowed.contains(flag)) ||
      a.rest.isEmpty) {
    throw Fail(
      'seed requires an explicit nondefault --instance and exact --ws/--http '
      'lab origins; see harness/seed/README.md',
    );
  }
  SeedOperationTrace? trace;
  Future<Map<String, dynamic>> command(Map<String, Object?> fields) async {
    trace?.at(_seedOperationAction(fields['action']), SeedOperationStep.owner);
    await requireOwner?.call();
    trace?.at(_seedOperationAction(fields['action']),
        SeedOperationStep.request);
    if (fields['action'] == 'publish') trace?.publicationCallEntered();
    final Map<String, dynamic> result = await inst
        .send(<String, Object?>{
          'cmd': 'seed',
          ...fields,
        }, timeout: const Duration(seconds: 300))
        .timeout(const Duration(seconds: 305));
    trace?.at(_seedOperationAction(fields['action']), SeedOperationStep.reply);
    if (result['ok'] != true) {
      final Object? detail = result['detail'];
      trace?.refusedReply(result['error'], confirmation:
          detail is Map<String, dynamic> && detail.length == 1
              ? detail['seedConfirmation'] : null);
      throw Fail('seed refused: ${result['error']}');
    }
    return result;
  }

  if (a.rest.first == 'fixture') {
    if (a.rest.length != 2 ||
        !<String>{'sentinel', 'aged-fuse'}.contains(a.rest[1])) {
      throw Fail('seed fixture sentinel|aged-fuse');
    }
    final Map<String, dynamic> result = await command(<String, Object?>{
      'action': 'fixture',
      'kind': a.rest[1],
      'profile': inst.name,
      'ws': a['ws'],
      'http': a['http'],
    });
    stdout.writeln(jsonEncode(result));
    return result;
  }
  if (a.rest.length != 1 ||
      !seedRecipeIds.contains(a.rest.single) ||
      a['checkpoint-ready'] != 'true') {
    throw Fail(
      'seed <recipe> requires a reversible isolated chain/profile checkpoint; '
      'no automatic restore or cleanup',
    );
  }
  final String id = a.rest.single;
  final SeedOperationTrace originalTrace = SeedOperationTrace(id);
  trace = originalTrace;
  try {
    final File file = File('$repo/harness/seed/$id.txt');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        file.lengthSync() > 8192) {
      throw Fail('seed recipe source is missing or held');
    }
    final String source = file.readAsStringSync();
    originalTrace.at(SeedOperationAction.source, SeedOperationStep.parse);
    final SeedRecipe plan = SeedRecipe.parse(id, source);
    final Map<String, dynamic> ready = await command(<String, Object?>{
      'action': 'begin',
      'recipe': id,
      'profile': inst.name,
      'ws': a['ws'],
      'http': a['http'],
      'checkpointReady': true,
      if (a['counterparty'] != null) 'counterparty': a['counterparty'],
    });
    originalTrace.at(SeedOperationAction.source, SeedOperationStep.resolve);
    final Map<String, String> values = <String, String>{
      if (ready['secondaryAddress'] is String)
        r'${secondaryAddress}': ready['secondaryAddress'] as String,
      if (ready['counterparty'] is String)
        r'${counterparty}': ready['counterparty'] as String,
    };
    final List<List<String>> lines = plan.lines
        .map((List<String> words) => plan.resolve(words, values))
        .toList();
    originalTrace.at(SeedOperationAction.home, SeedOperationStep.navigation);
    await prepareScreenHome(inst, observe: originalTrace.homeObserved);
    int commandIndex = 0;
    for (final List<String> words in lines) {
      originalTrace.at(SeedOperationAction.check, SeedOperationStep.owner,
          commandIndex: ++commandIndex);
      await command(<String, Object?>{'action': 'check'});
      if (words.first == 'publish') {
        stdout.writeln(
          jsonEncode(await command(<String, Object?>{'action': 'publish'})),
        );
      } else if (words.first == 'tap') {
        await command(<String, Object?>{
          'action': 'prepare',
          'selector': words.sublist(1),
        });
        stdout.writeln('ok');
      } else {
        originalTrace.at(SeedOperationAction.command, SeedOperationStep.owner);
        await requireOwner?.call();
        originalTrace.at(SeedOperationAction.command,
            SeedOperationStep.execute);
        await run(inst, words.first, Args(words.sublist(1)));
      }
    }
    originalTrace.at(SeedOperationAction.finish, SeedOperationStep.owner,
        commandIndex: 0);
    final Map<String, dynamic> result = await command(<String, Object?>{
      'action': 'finish',
    });
    stdout.writeln(jsonEncode(result));
    return result;
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(originalTrace.failure(error), stack);
  }
}

/// Runs a file of harness command lines, stopping at the first that fails.
/// `#` starts a comment; quotes group words.
Future<void> script(Instance inst, String file, Args outer) async {
  final List<String> lines = File(file).readAsLinesSync();
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    stdout.writeln('> $line');
    try {
      final List<String> words = scriptWords(line);
      await run(inst, words.first, Args(words.sublist(1)));
    } on Object catch (e) {
      throw Fail('$file:${i + 1}: $e');
    }
  }
}

// -------------------------------------------------------------------- recipes

//
// Flows a person does often, made of the same taps and keystrokes as above.

Future<Map<String, dynamic>> stateOf(Instance inst) =>
    call(inst, <String, Object?>{'cmd': 'state'});

Future<void> prepareScreenHome(Instance inst, {
  HomePreparationObserver? observe,
}) async {
  observe?.call(HomePreparationStep.initialState);
  final Map<String, dynamic> state = await stateOf(inst);
  observe?.call(HomePreparationStep.initialReadiness, state: state);
  if (state['booted'] != true ||
      state['walletUnlocked'] != true ||
      state['walletInitCompleted'] != true ||
      state['tab'] == 'lock') {
    throw Fail(
      'screens needs unlocked Home; entry preparation is pending F06/N',
    );
  }
  observe?.call(HomePreparationStep.resolveTarget);
  final List<dynamic> tabs = state['tabs'] as List<dynamic>;
  final String home = tabs.contains('home') ? 'home' : 'dashboard';
  observe?.call(HomePreparationStep.resolveTarget, target: home);
  await goto(inst, home, observe: observe);
  await setScreenRail(inst, expanded: false, observe: observe);
  observe?.call(HomePreparationStep.finalState);
  final Map<String, dynamic> observed = await stateOf(inst);
  observe?.call(HomePreparationStep.finalReadiness, state: observed);
  if (observed['tab'] != home || observed['walletUnlocked'] != true) {
    throw Fail('screens could not establish unlocked Home');
  }
}

Future<bool> screenRailExpanded(Instance inst, {
  HomePreparationObserver? observe,
}) async {
  observe?.call(HomePreparationStep.railState);
  final Map<String, dynamic> state = await stateOf(inst);
  observe?.call(HomePreparationStep.railReadiness, state: state);
  if (state['walletUnlocked'] != true ||
      state['tab'] == 'lock' ||
      state['walletInitCompleted'] != true) {
    throw Fail('screens rail is not ready in an unlocked profile');
  }
  observe?.call(HomePreparationStep.railTogglePresence);
  if (!await present(inst, <String, Object?>{'key': 'rail_toggle'})) {
    throw Fail('screens rail is not ready in an unlocked profile');
  }
  observe?.call(HomePreparationStep.railLabelPresence);
  return present(inst, <String, Object?>{'key': 'rail_label_dashboard'});
}

Future<void> setScreenRail(Instance inst, {
  required bool expanded, HomePreparationObserver? observe,
}) async {
  if (await screenRailExpanded(inst, observe: observe) == expanded) return;
  observe?.call(HomePreparationStep.railToggle);
  await call(inst, <String, Object?>{'cmd': 'tap', 'key': 'rail_toggle'});
  observe?.call(HomePreparationStep.railWait);
  await call(inst, <String, Object?>{
    'cmd': 'wait',
    'key': 'rail_label_dashboard',
    if (!expanded) 'gone': true,
  });
}

Future<void> restoreScreenRail(Instance inst, {required bool expanded}) async {
  await prepareScreenHome(inst);
  await setScreenRail(inst, expanded: expanded);
}

Future<bool> present(Instance inst, Map<String, Object?> sel, {
  void Function(ScreenCaptureReplyCode reply)? onRejected,
}) async {
  final Map<String, dynamic> r = await inst.send(<String, Object?>{
    'cmd': 'wait',
    ...sel,
    'timeoutMs': 0,
  });
  if (r['ok'] != true) {
    onRejected?.call(classifyScreenCaptureReply(r['error'], r['detail']));
  }
  return r['ok'] == true;
}

/// Scrolls until the selector is on screen. A list builds only what is
/// visible, so what is below the fold is not in the tree until then.
Future<void> reveal(
  Instance inst,
  Map<String, Object?> sel, {
  int step = 250,
  int max = 20,
}) async {
  ScreenCaptureReplyCode? lastReply;
  for (int i = 0; i <= max; i++) {
    if (await present(inst, sel,
      onRejected: (ScreenCaptureReplyCode reply) => lastReply = reply,
    )) {
      return;
    }
    await call(inst, <String, Object?>{'cmd': 'scroll', 'dy': step});
  }
  throw Fail('reveal: not found after ${max * step} px ${jsonEncode(sel)}',
    captureReply: lastReply,
  );
}

Future<void> until(
  Instance inst,
  bool Function(Map<String, dynamic> state) test,
  String what, {
  int seconds = 30,
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (true) {
    if (test(await stateOf(inst))) return;
    if (sw.elapsed.inSeconds >= seconds) throw Fail('$what: timed out');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

Future<void> goto(Instance inst, String tab, {
  HomePreparationObserver? observe,
}) async {
  observe?.call(HomePreparationStep.gotoState);
  final Map<String, dynamic> s = await stateOf(inst);
  observe?.call(HomePreparationStep.gotoTarget, state: s);
  final List<dynamic> tabs = s['tabs'] as List<dynamic>;
  if (!tabs.contains(tab)) {
    throw Fail('no tab "$tab"; tabs are ${tabs.join(', ')}');
  }
  observe?.call(HomePreparationStep.gotoTap);
  await call(inst, <String, Object?>{'cmd': 'tap', 'tab': tab});
  if (tab == 'notifications') {
    // The real rail opens a panel over the original page, not another tab.
    await call(inst, <String, Object?>{
      'cmd': 'wait', 'key': 'bell_panel', 'timeoutMs': 5000,
    });
    final Map<String, dynamic> current = await stateOf(inst);
    if (current['tab'] != s['tab']) {
      throw Fail('goto notifications: original page changed');
    }
    return;
  }
  observe?.call(HomePreparationStep.gotoWait);
  await until(
    inst,
    (Map<String, dynamic> s) {
      observe?.call(HomePreparationStep.gotoWait, state: s);
      return s['tab'] == tab;
    },
    'goto $tab',
    seconds: 5,
  );
}

/// Original unlock operations; observation never changes their inputs or waits.
enum UnlockStep {
  state, lock, fieldReady, typePassword, submit, wait, failureTree,
}

Future<void> unlock(
  Instance inst,
  String password, {
  void Function(UnlockStep step)? observe,
}) async {
  observe?.call(UnlockStep.state);
  final Map<String, dynamic> s = await stateOf(inst);
  observe?.call(UnlockStep.lock);
  if (s['tab'] != 'lock') {
    if (s['walletUnlocked'] != true) {
      throw Fail(
        'unlock requires the wallet lock screen or a confirmed unlocked state',
      );
    }
    stdout.writeln('already unlocked');
    return;
  }
  // The route can report lock before its cold-start input barrier is gone.
  // This read-only wait never types, submits or retries a refused input.
  observe?.call(UnlockStep.fieldReady);
  await call(inst, <String, Object?>{
    'cmd': 'wait',
    'key': 'wallet_password_field',
    'kind': 'field',
    'ready': true,
    'timeoutMs': 5000,
  });
  observe?.call(UnlockStep.typePassword);
  await call(inst, <String, Object?>{
    'cmd': 'type',
    'key': 'wallet_password_field',
    'value': password,
  });
  observe?.call(UnlockStep.submit);
  await call(inst, <String, Object?>{
    'cmd': 'tap',
    'key': 'wallet_unlock_button',
  });
  try {
    observe?.call(UnlockStep.wait);
    await until(
      inst,
      (Map<String, dynamic> s) =>
          s['tab'] != 'lock' && s['walletUnlocked'] == true,
      'unlock',
      seconds: 20,
    );
  } on Fail {
    // A wrong password costs an attempt; the wallet erases itself at zero.
    observe?.call(UnlockStep.failureTree);
    final Map<String, dynamic> t = await call(inst, <String, Object?>{
      'cmd': 'tree',
      'kind': 'text',
    });
    final Iterable<String> left = (t['nodes'] as List<dynamic>)
        .map(
          (dynamic n) => (n as Map<String, dynamic>)['label'] as String? ?? '',
        )
        .where((String l) => l.contains('attempt'));
    observe?.call(UnlockStep.wait);
    throw Fail('unlock failed${left.isEmpty ? '' : ': ${left.first}'}');
  }
}

/// From the Welcome screen of an empty profile to the dashboard.
Future<void> importWallet(Instance inst, Args a) async {
  await walletRecipe(inst).importWallet(
    chain: a['chain'],
    mnemonic: a['mnemonic'],
    password: a['password'],
    node: a['node'],
  );
  stdout.writeln('imported with the verified signing policy');
}

/// The recipe never prints private responses or retries an uncertain command.
WalletRecipe walletRecipe(Instance inst) => WalletRecipe(
  send: (Map<String, Object?> command, Duration timeout) =>
      inst.send(command, timeout: timeout),
);

/// On a screen that shows the node list (onboarding, or Settings): adds the
/// node if it is not listed, and selects it.
Future<void> selectNode(Instance inst, String url) async {
  await walletRecipe(inst).selectNode(url);
}

/// Sets the chain identifier the wallet signs with, in Settings. A devnet
/// refuses blocks signed for chain 1, and the wallet does not follow the node.
Future<void> clientChain(Instance inst, int id) async {
  await walletRecipe(inst).changeClientChain(id);
}

const List<String> walletTourPages = <String>[
  'dashboard', 'transfer', 'pillars', 'sentinels', 'staking', 'plasma',
  'tokens', 'p2pSwap', 'accelerator', 'notifications', 'settings',
];

/// Require every current page. Status icons cannot substitute for a page.
List<String> walletTourPlan(
  Map<String, dynamic> state, {
  int? readonlyNativePid,
}) {
  final Object? offered = state['tabs'];
  final bool modeCurrent = readonlyNativePid == null
      ? state['harnessMode'] == 'wallet'
      : harnessReadonlyNativeWalletMatches(state, readonlyNativePid);
  if (!modeCurrent ||
      state['booted'] != true || state['walletUnlocked'] != true ||
      state['walletInitCompleted'] != true || state['tab'] == 'lock' ||
      offered is! List || offered.length > 16 ||
      offered.any((dynamic value) => value is! String)) {
    throw Fail('tour: an initialized unlocked wallet is required');
  }
  final Set<String> tabs = offered.cast<String>().toSet();
  const Set<String> known = <String>{
    ...walletTourPages, 'walletConnect', 'generation', 'sync', 'lock',
  };
  if (tabs.length != offered.length || !known.containsAll(tabs) ||
      !tabs.containsAll(walletTourPages) || !tabs.contains(state['tab'])) {
    throw Fail('tour: the complete page catalog was not observed');
  }
  // Apps is available through Settings even without a WalletConnect project ID.
  return <String>[...walletTourPages, 'walletConnect'];
}

/// Finite original tour operations. Observation never repeats an operation.
enum WalletTourStep {
  beforePage, railNavigation, sectionControlWait, sectionControlTap,
  sectionPageWait, pointerNeutral, nodeRestingTap, settle, tree, logs, capture,
  afterPage,
  bellClose, bellGone, afterBell, returnHome,
}

/// Fixed error categories, without response text, values or host locations.
enum WalletTourFailureKind { refused, timeout, replyShape, filesystem, other }

/// The first failed original operation, still a normal harness refusal.
class WalletTourFailure extends Fail {
  /// Stores only the selected catalog page and finite diagnostic labels.
  WalletTourFailure({
    required this.page, required this.step, required this.kind,
  }) : super('tour: original operation refused');

  /// A catalog page; unknown input is never copied into a public receipt.
  final String page;

  /// The operation attempted immediately before the original failure.
  final WalletTourStep step;

  /// The original exception's category, without its message or stack.
  final WalletTourFailureKind kind;

  /// This receipt provides no permission to retry or accept a failed tour.
  Map<String, Object> get diagnostic => <String, Object>{
    'schema': 1, 'scope': 'original_wallet_page_tour_failure',
    'page': <String>[...walletTourPages, 'walletConnect'].contains(page)
        ? page : 'unknown',
    'step': step.name, 'kind': kind.name,
  };
}

Future<void> _tourPage(Instance inst, String page, {
  void Function(WalletTourStep step)? observe,
}) async {
  final String rail = switch (page) {
    'sentinels' => 'pillars',
    'walletConnect' => 'settings',
    _ => page,
  };
  observe?.call(WalletTourStep.railNavigation);
  // The intended bell view belongs to Home. The ordinary goto operation
  // still opens the panel over whichever page its caller actually owns.
  if (page == 'notifications') {
    await goto(inst, 'dashboard');
  }
  await goto(inst, rail);
  final (String, String)? section = switch (page) {
    'pillars' => ('nodes_tab_pillars', 'nodes_pillars_strip'),
    'sentinels' => ('nodes_tab_sentinels', 'nodes_sentinels_strip'),
    'settings' => ('settings_node', 'node_settings_page'),
    'walletConnect' => ('settings_apps', 'apps_settings_page'),
    _ => null,
  };
  if (section != null) {
    observe?.call(WalletTourStep.sectionControlWait);
    await call(inst, <String, Object?>{
      'cmd': 'wait', 'key': section.$1, 'timeoutMs': 5000,
    });
    observe?.call(WalletTourStep.sectionControlTap);
    await call(inst, <String, Object?>{'cmd': 'tap', 'key': section.$1});
    observe?.call(WalletTourStep.sectionPageWait);
    await call(inst, <String, Object?>{
      'cmd': 'wait', 'key': section.$2, 'timeoutMs': 5000,
    });
  }
}

Future<void> _tourContext(
  Instance inst,
  Map<String, dynamic> original, {
  int? readonlyNativePid,
}) async {
  final Map<String, dynamic> current = await stateOf(inst);
  walletTourPlan(current, readonlyNativePid: readonlyNativePid);
  for (final String key in <String>[
    'address', 'walletPath', 'node', 'chainId', 'signingChainId',
    'savedSigningChainId',
  ]) {
    if (current[key] != original[key]) {
      throw Fail('tour: wallet context changed');
    }
  }
}

/// Visits every page, including merged subpages, and retains finite coverage.
/// An unreachable page or uncertain command fails the tour immediately.
Future<void> tour(
  Instance inst,
  Args a, {
  Future<void> Function(String, Map<String, dynamic>)? capture,
  Future<void> Function(Duration)? settle,
  void Function(Map<String, Object?>)? publish,
  int? readonlyNativePid,
}) async {
  final Map<String, dynamic> s = await stateOf(inst);
  final List<String> pages = walletTourPlan(
    s, readonlyNativePid: readonlyNativePid,
  );
  final String dir = a['dir'] ?? '${inst.home}${Platform.pathSeparator}tour';
  final List<Map<String, Object?>> visited = <Map<String, Object?>>[];
  bool complete = false;
  String activePage = 'unknown';
  WalletTourStep activeStep = WalletTourStep.beforePage;
  int seq =
      (await call(inst, <String, Object?>{'cmd': 'logs', 'limit': 0}))['seq']
          as int;
  try {
    for (final String page in pages) {
      activePage = page;
      activeStep = WalletTourStep.beforePage;
      await _tourContext(inst, s, readonlyNativePid: readonlyNativePid);
      await _tourPage(inst, page,
          observe: (WalletTourStep step) => activeStep = step);
      if (readonlyNativePid != null) {
        // Keep resting captures clear of the preceding control's hover.
        activeStep = WalletTourStep.pointerNeutral;
        await call(inst, <String, Object?>{
          'cmd': 'hover', 'at': <int>[0, 0], 'settleMs': 0,
        });
        if (page == 'settings') {
          // A separate mouse can retain a tooltip after this pointer leaves.
          // Keep the resting tap outside the caption and rail controls.
          activeStep = WalletTourStep.nodeRestingTap;
          await call(inst, <String, Object?>{
            'cmd': 'tap', 'at': <int>[0, 779], 'settleMs': 0,
          });
        }
      }
      activeStep = WalletTourStep.settle;
      await (settle ?? Future<void>.delayed)(
        const Duration(milliseconds: 2500),
      );
      activeStep = WalletTourStep.tree;
      final List<dynamic> nodes =
          (await call(inst, <String, Object?>{'cmd': 'tree'}))['nodes']
              as List<dynamic>;
      final int errors = nodes.where(
        (dynamic node) => (node as Map<String, dynamic>)['kind'] == 'error',
      ).length;
      activeStep = WalletTourStep.logs;
      final Map<String, dynamic> logs = await call(inst, <String, Object?>{
        'cmd': 'logs', 'since': seq,
        'levels': <String>['SEVERE', 'SHOUT', 'FLUTTER'],
      });
      final int nextSeq = logs['seq'] as int;
      if (nextSeq < seq) throw Fail('tour: log sequence changed');
      seq = nextSeq;
      final int severe = (logs['logs'] as List<dynamic>).length;
      visited.add(<String, Object?>{
        'page': page, 'nodes': nodes.length, 'error_widgets': errors,
        'severe_logs': severe, 'captured': false,
        if (readonlyNativePid != null) 'layout': null,
      });
      if (errors != 0 || severe != 0) throw Fail('tour: page errors observed');
      activeStep = WalletTourStep.capture;
      final Map<String, dynamic> shot = await call(inst, <String, Object?>{
        'cmd': 'shot',
      });
      final Object? layout = readonlyNativePid == null
          ? null : shot['layoutObservation'];
      if (readonlyNativePid != null && layout is! Map<String, dynamic>) {
        throw Fail('tour: readonly layout observation is unavailable');
      }
      if (capture != null) {
        await capture(page, shot);
      } else {
        final Object? png = shot['png'];
        if (png is! String || png.length > 12 * 1024 * 1024) {
          throw Fail('tour: missing or oversized capture');
        }
        final List<int> bytes = base64Decode(png);
        const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
        if (bytes.length < 33 || bytes.length > 8 * 1024 * 1024 ||
            !signature.asMap().entries.every(
              (MapEntry<int, int> entry) => bytes[entry.key] == entry.value,
            )) {
          throw Fail('tour: invalid capture');
        }
        final File file = File('$dir${Platform.pathSeparator}$page.png');
        Directory parent = file.parent.absolute;
        while (true) {
          final FileSystemEntityType type = FileSystemEntity.typeSync(
            parent.path, followLinks: false,
          );
          if (type != FileSystemEntityType.directory &&
              type != FileSystemEntityType.notFound) {
            throw Fail('tour: capture parent is not a plain directory');
          }
          if (parent.parent.path == parent.path) break;
          parent = parent.parent;
        }
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw Fail('tour: capture already exists');
        }
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes, flush: true);
      }
      if (readonlyNativePid != null) visited.last['layout'] = layout;
      visited.last['captured'] = true;
      activeStep = WalletTourStep.afterPage;
      await _tourContext(inst, s, readonlyNativePid: readonlyNativePid);
      if (page == 'notifications') {
        // Close through the same ordinary panel control before another page.
        activeStep = WalletTourStep.bellClose;
        await call(inst, <String, Object?>{'cmd': 'tap', 'key': 'bell_close'});
        activeStep = WalletTourStep.bellGone;
        await call(inst, <String, Object?>{
          'cmd': 'wait', 'key': 'bell_panel', 'gone': true, 'timeoutMs': 5000,
        });
        activeStep = WalletTourStep.afterBell;
        await _tourContext(inst, s, readonlyNativePid: readonlyNativePid);
      }
    }
    activePage = 'dashboard';
    activeStep = WalletTourStep.returnHome;
    await goto(inst, 'dashboard');
    complete = true;
  } on Object catch (error, stack) {
    final WalletTourFailureKind kind = switch (error) {
      Fail() => WalletTourFailureKind.refused,
      TimeoutException() => WalletTourFailureKind.timeout,
      TypeError() || FormatException() || RangeError() =>
          WalletTourFailureKind.replyShape,
      FileSystemException() => WalletTourFailureKind.filesystem,
      _ => WalletTourFailureKind.other,
    };
    Error.throwWithStackTrace(WalletTourFailure(
      page: activePage, step: activeStep, kind: kind,
    ), stack);
  } finally {
    final Map<String, Object?> result = <String, Object?>{
      'schema': 1,
      'scope': readonlyNativePid == null
          ? 'wallet_page_tour' : 'readonly_native_page_tour',
      'complete': complete,
      'requested': pages, 'visited': visited,
    };
    if (publish != null) {
      publish(result);
    } else {
      stdout.writeln('SYRIUS_WALLET_TOUR:${jsonEncode(result)}');
    }
  }
}

Future<bool> recipe(Instance inst, String command, Args a) async {
  switch (command) {
    case 'goto':
      await goto(
        inst,
        a.rest.isEmpty ? (throw Fail('goto <tab>')) : a.rest.first,
      );
      stdout.writeln('ok');
    case 'unlock':
      await unlock(
        inst,
        a.rest.isNotEmpty
            ? a.rest.first
            : (a['password'] ?? (throw Fail('unlock <password>'))),
      );
      stdout.writeln('unlocked');
    case 'lock':
      await goto(inst, 'lock');
      stdout.writeln('locked');
    case 'import':
      await importWallet(inst, a);
    case 'node':
      await selectNode(
        inst,
        a.rest.isEmpty ? (throw Fail('node <ws url>')) : a.rest.first,
      );
      stdout.writeln('ok');
    case 'chain':
      await clientChain(
        inst,
        walletRecipeChain(a.rest.isEmpty ? null : a.rest.single),
      );
      stdout.writeln('ok');
    case 'lab-address':
      if (a.rest.isNotEmpty ||
          a.flags.keys.any((String key) => key != 'instance')) {
        throw Fail('lab-address takes no options');
      }
      final Map<String, Object> selected = await walletRecipe(inst)
          .selectLabAddress();
      stdout.writeln('SYRIUS_LAB_ADDRESS:${jsonEncode(selected)}');
    case 'reveal':
      await reveal(
        inst,
        selector(a.rest.isEmpty ? null : a.rest.first, a)..remove('force'),
        max: a.integer('max') ?? 20,
      );
      stdout.writeln('ok');
    case 'tour':
      await tour(inst, a);
    default:
      return false;
  }
  return true;
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || argv.first == 'help' || argv.first == '--help') {
    stdout.writeln(
      'usage: harness <command> [arguments] [--instance <name>] [--json]\n'
      'see harness/README.md',
    );
    return;
  }
  try {
    final Args a = Args(argv.sublist(1));
    final Instance inst = Instance(a['instance'] ?? 'default');
    await run(inst, argv.first, a);
  } on Object catch (e) {
    stderr.writeln('error: $e');
    exitCode = 1;
  }
}
