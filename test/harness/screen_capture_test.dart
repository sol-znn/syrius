import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/harness.dart' as cli;
import '../../harness/bin/screen_capture.dart';

/// A transport double's header, not a rendered screenshot. Actual pixels and
/// DPI transforms are exercised separately in logical_capture_test.dart.
String _pngHeader({int width = 1280, int height = 780}) {
  final Uint8List bytes = Uint8List(33)
    ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
    ..setAll(12, ascii.encode('IHDR'));
  ByteData.sublistView(bytes)
    ..setUint32(8, 13)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return base64Encode(bytes);
}

class _Agent {
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
  final List<List<String>> lines = <List<String>>[];
  String mode = 'system';
  String? savedMode = 'ThemeMode.system';
  int homePreparations = 0;
  int shots = 0;
  String? failCommand;
  bool failHome = false;
  bool failRestore = false;
  bool wrongClient = false;
  bool wrongTheme = false;
  bool wrongImage = false;
  bool unassertedImage = false;
  bool corruptPng = false;
  bool wrongPngHeader = false;
  bool failSecondShot = false;

  Future<void> prepareHome() async {
    homePreparations++;
    if (failHome) throw StateError('unlocked Home is not available');
  }

  Future<Map<String, dynamic>> call(Map<String, Object?> command) async {
    commands.add(command);
    final String name = command['cmd']! as String;
    if (failCommand == name &&
        command['restore'] == null &&
        command['restoreState'] == null) {
      throw StateError('$name refused');
    }
    if (name == 'theme') {
      if (command['restore'] case final Map<String, dynamic> original) {
        if (failRestore) throw StateError('theme restore refused');
        mode = original['mode'] as String;
        savedMode = original['savedMode'] as String?;
      } else if (command['mode'] case final String requested) {
        mode = requested;
        savedMode = 'ThemeMode.$mode';
      }
      return <String, dynamic>{
        'mode': mode,
        'savedMode': savedMode,
        'brightness': wrongTheme ? 'wrong' : (mode == 'system' ? 'dark' : mode),
      };
    }
    if (name == 'window') {
      if (command['restoreState'] != null) {
        return <String, dynamic>{'restored': true};
      }
      return <String, dynamic>{
        'window': <int>[80, 90, 1216, 739],
        'client': <int>[
          if (command['width'] == null) ...<int>[1200, 700] else ...<int>[
            if (wrongClient) 1279 else 1280,
            780,
          ],
        ],
        'minimized': false,
        'maximized': true,
        'clientMatched': !wrongClient,
      };
    }
    if (name == 'shot') {
      shots++;
      if (failSecondShot && shots == 2) {
        throw StateError('second capture refused');
      }
      return <String, dynamic>{
        'client': <int>[1280, 780],
        'width': wrongImage ? 2560 : 1280,
        'height': 780,
        'scale': 1,
        'theme': mode,
        'asserted': !unassertedImage,
        'png': corruptPng
            ? 'not base64'
            : _pngHeader(width: wrongPngHeader ? 1279 : 1280),
      };
    }
    return <String, dynamic>{'asserted': true};
  }

  Future<void> runLine(List<String> words) async {
    lines.add(words);
    if (words.first == 'assert') {
      await call(<String, Object?>{
        'cmd': 'assert',
        ...cli.assertionArgs(cli.Args(words.sublist(1))),
      });
    }
  }
}

void main() {
  late Directory repository;
  late _Agent agent;
  late ScreenCapture capture;

  void writeScript(String id, [String? text]) {
    File('${repository.path}/harness/screens/$id.txt')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        text ??
            '# prerequisite: unlocked-home\n'
                'goto dashboard\nassert --key ${id}_marker\n',
      );
  }

  setUp(() {
    repository = Directory.systemTemp.createTempSync('syrius-harness-capture-');
    agent = _Agent();
    capture = ScreenCapture(
      repository: repository,
      call: agent.call,
      prepareHome: agent.prepareHome,
      runLine: agent.runLine,
      assertionFor: (List<String> words) =>
          cli.assertionArgs(cli.Args(words.sublist(1))),
    );
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  for (final bool failSecond in <bool>[false, true]) {
    test('hidden balance capture restores only completed shots $failSecond',
        () async {
      final String source = File('harness/screens/home-hidden.txt')
          .readAsStringSync();
      writeScript('home-hidden', source);
      bool hidden = false;
      int restores = 0;
      final List<bool> observedAtShot = <bool>[];
      agent.failSecondShot = failSecond;
      capture = ScreenCapture(
        repository: repository,
        call: (Map<String, Object?> command) async {
          if (command['cmd'] == 'shot') observedAtShot.add(hidden);
          return agent.call(command);
        },
        prepareHome: agent.prepareHome,
        runLine: (List<String> words) async {
          if (words.first == 'tap' && words[1] == 'Hide balances') {
            if (hidden) throw StateError('visible starting state missing');
            hidden = true;
          } else if (words.first == 'tap' && words[1] == 'Show balances') {
            if (!hidden) throw StateError('hidden capture state missing');
            hidden = false;
            restores++;
          }
          await agent.runLine(words);
        },
        assertionFor: (List<String> words) =>
            cli.assertionArgs(cli.Args(words.sublist(1))),
      );
      if (failSecond) {
        await expectLater(capture.capture('home-hidden'),
            throwsA(isA<ScreenCaptureError>()));
        expect(hidden, isTrue);
        expect(restores, 1);
      } else {
        expect(await capture.capture('home-hidden'), hasLength(2));
        expect(hidden, isFalse);
        expect(restores, 2);
      }
      expect(observedAtShot, <bool>[true, true]);
    });
  }

  test('after-capture metadata refuses invalid input before UI effects', () {
    for (final String source in <String>[
      '# after-capture: tap "Show balances"\nassert --key page',
      'assert --key page\n# after-capture:',
      'assert --key page\n# after-capture: quit',
      'assert --key page\n# after-capture: tap --instance other',
      'assert --key page\n# after-capture: tap eye\ntap other',
    ]) {
      writeScript('home-hidden', source);
      expect(() => capture.preflight('home-hidden'),
          throwsA(isA<ScreenCaptureError>()));
      expect(agent.commands, isEmpty);
      expect(agent.lines, isEmpty);
    }
  });

  test('authored page scripts finish with a valid stable assertion', () {
    final List<File> scripts = Directory('harness/screens')
        .listSync(followLinks: false)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.txt'))
        .toList();
    expect(scripts, isNotEmpty);
    for (final File script in scripts) {
      final String id = script.uri.pathSegments.last.replaceAll('.txt', '');
      expect(selectScreens(id).single.id, id);
      final List<List<String>> lines = script
          .readAsLinesSync()
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty && !line.startsWith('#'))
          .map(scriptWords)
          .toList();
      expect(lines.last.first, 'assert', reason: id);
      expect(cli.assertionArgs(cli.Args(lines.last.sublist(1))), isNotEmpty);
    }
  });

  for (final String id in <String>[
    'set-node',
    'set-security',
    'set-wallet',
    'set-addresses',
  ]) {
    test('actual $id passes preflight and injected capture', () async {
      final String text = File('harness/screens/$id.txt').readAsStringSync();
      expect(text.split('\n').first, '# prerequisite: unlocked-home');
      expect(text, contains('# Use an isolated harness profile.'));
      writeScript(id, text);
      final ScreenScript script = capture.preflight(id).single;
      expect(script.screen.id, id);
      expect(agent.commands, isEmpty);
      final List<List<String>> original = text
          .split('\n')
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty && !line.startsWith('#'))
          .map(scriptWords)
          .toList();
      final List<String> paths = await capture.capture(id);
      expect(paths, hasLength(2));
      expect(agent.lines, <List<String>>[...original, ...original]);
      expect(agent.homePreparations, 2);
      expect(agent.shots, 2);
      expect(agent.commands.last['restoreState'], isNotNull);
    });
  }

  test('actual pending entry recipes refuse before any effect', () async {
    for (final String id in <String>[
      'launch',
      'launch-settle',
      'lock-screen',
      'lock-wrong',
      'lock-pick',
      'welcome',
      'import',
      'seed-quiz',
      'wallet-ready',
    ]) {
      writeScript(id, File('harness/screens/$id.txt').readAsStringSync());
      expect(() => capture.preflight(id), throwsA(isA<ScreenCaptureError>()));
      await expectLater(
        capture.capture(id),
        throwsA(isA<ScreenCaptureError>()),
      );
    }
    expect(agent.commands, isEmpty);
    expect(agent.lines, isEmpty);
    expect(agent.homePreparations, 0);
    expect(Directory('${repository.path}/.harness').existsSync(), isFalse);
  });

  test('catalog matches all source sections and 94 numbered mockup shots', () {
    final List<File> source =
        Directory('mockups/redesign/src')
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.html'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    final List<String> ids = <String>[
      for (final File file in source)
        for (final RegExpMatch match in RegExp(
          '<section class="scr" id="([^"]+)"',
        ).allMatches(file.readAsStringSync()))
          match.group(1)!,
    ];
    expect(ids, screenCatalog.map((ScreenSpec s) => s.id).toList());
    expect(ids.toSet(), hasLength(47));
    final Set<String> expected = <String>{
      for (final ScreenSpec screen in screenCatalog)
        for (final String theme in <String>['dark', 'light'])
          '${screen.stem(theme)}.png',
    };
    final Set<String> actual = Directory('mockups/redesign/shots')
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.png'))
        .map((File f) => f.uri.pathSegments.last)
        .toSet();
    expect(actual, expected);
    expect(selectScreens('all'), same(screenCatalog));
    expect(selectScreens('receive').single.number, 9);
    expect(screenCatalog.last.stem('light'), '47-wallet-ready-light');
  });

  test('unknown IDs and instance traversal are refused', () async {
    for (final String id in <String>[
      '../home-rest',
      '01-home-rest',
      'home-rest/..',
      '',
      'ALL',
    ]) {
      await expectLater(
        capture.capture(id),
        throwsA(isA<ScreenCaptureError>()),
      );
    }
    for (final String name in <String>[
      '..',
      '../wallet',
      r'a\b',
      '/tmp',
      'a:b',
    ]) {
      expect(() => cli.Instance(name), throwsA(isA<cli.Fail>()));
    }
    expect(cli.Instance('fixture-1_test').name, 'fixture-1_test');
    expect(agent.commands, isEmpty);
  });

  test(
    'missing, empty, pending and unguarded scripts fail before app changes',
    () async {
      await expectLater(
        capture.capture('home-rest'),
        throwsA(isA<ScreenCaptureError>()),
      );
      const String pendingEntry =
          '# prerequisite: pending F06/N01 reversible entry preparation\n'
          'assert --key launch\n';
      for (final String text in <String>[
        '',
        '# no commands',
        'goto dashboard',
        pendingEntry,
        'assert @10,10',
        'assert #12',
        'assert --gone --key page',
      ]) {
        writeScript('home-rest', text);
        await expectLater(
          capture.capture('home-rest'),
          throwsA(
            anyOf(
              isA<ScreenCaptureError>(),
              isA<cli.Fail>(),
            ),
          ),
        );
      }
      expect(agent.commands, isEmpty);
      expect(Directory('${repository.path}/.harness').existsSync(), isFalse);
    },
  );

  test(
    'screen scripts cannot start, stop, nest or choose capture state and paths',
    () async {
      for (final String command in <String>[
        'start --fresh',
        'stop',
        'build',
        'run other.txt',
        'screens all',
        'shot --out ../old.png',
        'window --width 100 --height 100',
        'theme light',
        'drop --key importer ../wallet',
        'tap Go --instance other',
        'tap Go --instance=other',
      ]) {
        writeScript('home-rest', '$command\nassert --key page');
        await expectLater(
          capture.capture('home-rest'),
          throwsA(isA<ScreenCaptureError>()),
        );
      }
      expect(agent.commands, isEmpty);
    },
  );

  test('all scripts preflight before a capture starts', () async {
    writeScript('home-rest');
    await expectLater(
      capture.capture('all'),
      throwsA(isA<ScreenCaptureError>()),
    );
    expect(agent.commands, isEmpty);
  });

  test(
    'runs each script in dark then light and restores original settings',
    () async {
      writeScript('receive');
      final List<String> result = await capture.capture('receive');
      expect(result, <String>[
        '.harness/shots/09-receive-dark.png',
        '.harness/shots/09-receive-light.png',
      ]);
      expect(agent.homePreparations, 2);
      expect(agent.lines.map((List<String> l) => l.first).toList(), <String>[
        'goto',
        'assert',
        'goto',
        'assert',
      ]);
      final List<Map<String, Object?>> shots = agent.commands
          .where((Map<String, Object?> c) => c['cmd'] == 'shot')
          .toList();
      expect(
        shots.map((Map<String, Object?> c) => c['theme']).toList(),
        <String>['dark', 'light'],
      );
      expect(shots.first['expect'], <String, Object?>{
        'key': 'receive_marker',
        'exact': true,
      });
      expect(agent.mode, 'system');
      expect(agent.savedMode, 'ThemeMode.system');
      expect(agent.commands.last['restoreState'], isA<Map<String, dynamic>>());
      for (final String path in result) {
        expect(
          File('${repository.path}/$path').readAsBytesSync(),
          base64Decode(_pngHeader()),
        );
      }
    },
  );

  test(
    'all follows catalog order and makes 94 independently guarded captures',
    () async {
      for (final ScreenSpec screen in screenCatalog) {
        writeScript(screen.id);
      }
      final List<String> result = await capture.capture(
        'all',
        directory: '.harness/run-1',
      );
      expect(result, hasLength(94));
      expect(result.first, '.harness/run-1/01-home-rest-dark.png');
      expect(result.last, '.harness/run-1/47-wallet-ready-light.png');
      expect(agent.homePreparations, 94);
    },
  );

  test(
    'preserves existing targets and requires a fresh optional directory',
    () async {
      writeScript('home-rest');
      final File previous =
          File('${repository.path}/.harness/shots/01-home-rest-dark.png')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('retained evidence');
      await expectLater(
        capture.capture('home-rest'),
        throwsA(isA<ScreenCaptureError>()),
      );
      expect(previous.readAsStringSync(), 'retained evidence');
      await expectLater(
        capture.capture('home-rest', directory: '.harness/shots'),
        throwsA(isA<ScreenCaptureError>()),
      );
      expect(agent.commands, isEmpty);
      final List<String> fresh = await capture.capture(
        'home-rest',
        directory: '.harness/run-2',
      );
      expect(fresh.first, '.harness/run-2/01-home-rest-dark.png');
      expect(previous.readAsStringSync(), 'retained evidence');
    },
  );

  test(
    'directory traversal, absolute paths and Windows aliases are refused',
    () async {
      writeScript('home-rest');
      for (final String path in <String>[
        '../shots',
        '/tmp/shots',
        '.harness/../shots',
        '.harness/a/../../shots',
        '.harness//shots',
        '.harness/NUL',
        '.harness/CON.png',
        '.harness/end.',
        r'C:\shots',
        r'.harness\..\shots',
        '.harness',
      ]) {
        await expectLater(
          capture.capture('home-rest', directory: path),
          throwsA(isA<ScreenCaptureError>()),
        );
      }
      expect(agent.commands, isEmpty);
    },
  );

  test(
    'refuses output and script links without touching their targets',
    () async {
      writeScript('home-rest');
      final Directory retained = Directory('${repository.path}/retained')
        ..createSync();
      final File evidence = File('${retained.path}/sentinel')
        ..writeAsStringSync('keep');
      Link('${repository.path}/.harness').createSync(retained.path);
      await expectLater(
        capture.capture('home-rest'),
        throwsA(isA<ScreenCaptureError>()),
      );
      expect(evidence.readAsStringSync(), 'keep');
      Link('${repository.path}/.harness').deleteSync();
      final File script = File(
        '${repository.path}/harness/screens/home-rest.txt',
      );
      final File source = script.renameSync('${retained.path}/source.txt');
      Link(script.path).createSync(source.path);
      await expectLater(
        capture.capture('home-rest'),
        throwsA(isA<ScreenCaptureError>()),
      );
      expect(source.readAsStringSync(), contains('assert'));
      expect(agent.commands, isEmpty);
    },
    // Hosted CI must exercise real link refusal; missing privilege fails.
    // Other Windows sessions retain the explicit platform skip.
    skip: Platform.isWindows &&
        (Platform.environment['GITHUB_ACTIONS'] != 'true' ||
            Platform.environment['RUNNER_ENVIRONMENT'] != 'github-hosted')
        ? 'Windows symlink privilege is not assumed'
        : false,
  );

  test(
    'wrong geometry, theme, state and image payload never publish a shot',
    () async {
      writeScript('home-rest');
      for (final void Function() fault in <void Function()>[
        () {
          agent.wrongClient = true;
        },
        () {
          agent.wrongTheme = true;
        },
        () {
          agent.wrongImage = true;
        },
        () {
          agent.unassertedImage = true;
        },
        () {
          agent.corruptPng = true;
        },
        () {
          agent.wrongPngHeader = true;
        },
        () {
          agent.failCommand = 'assert';
        },
        () {
          agent.failHome = true;
        },
      ]) {
        agent = _Agent();
        capture = ScreenCapture(
          repository: repository,
          call: agent.call,
          prepareHome: agent.prepareHome,
          runLine: agent.runLine,
          assertionFor: (List<String> words) =>
              cli.assertionArgs(cli.Args(words.sublist(1))),
        );
        fault();
        await expectLater(
          capture.capture('home-rest'),
          throwsA(isA<ScreenCaptureError>()),
        );
        expect(
          File(
            '${repository.path}/.harness/shots/01-home-rest-dark.png',
          ).existsSync(),
          isFalse,
        );
        expect(agent.mode, 'system');
        expect(agent.commands.last['restoreState'], isNotNull);
      }
    },
  );

  test(
    'failure retains earlier captures and reports restore failures honestly',
    () async {
      writeScript('home-rest');
      agent
        ..failSecondShot = true
        ..failRestore = true;
      await expectLater(
        capture.capture('home-rest'),
        throwsA(
          isA<ScreenCaptureError>()
              .having(
                (ScreenCaptureError e) => e.message,
                'restoration',
                contains('theme restore'),
              )
              .having(
                (ScreenCaptureError e) => e.message,
                'earlier evidence',
                contains('1 earlier captures retained'),
              ),
        ),
      );
      expect(
        File(
          '${repository.path}/.harness/shots/01-home-rest-dark.png',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${repository.path}/.harness/shots/01-home-rest-light.png',
        ).existsSync(),
        isFalse,
      );
      expect(agent.commands.last['restoreState'], isNotNull);
    },
  );

  test('restores the original rail expansion after a script failure', () async {
    writeScript('home-rest');
    bool railExpanded = true;
    bool? restored;
    capture = ScreenCapture(
      repository: repository,
      call: agent.call,
      readRailState: () async => railExpanded,
      prepareHome: () async {
        railExpanded = false;
      },
      runLine: agent.runLine,
      assertionFor: (List<String> words) =>
          cli.assertionArgs(cli.Args(words.sublist(1))),
      restoreRailState: ({required bool expanded}) async {
        railExpanded = expanded;
        restored = expanded;
      },
    );
    agent.failCommand = 'assert';
    await expectLater(
      capture.capture('home-rest'),
      throwsA(isA<ScreenCaptureError>()),
    );
    expect(restored, isTrue);
    expect(railExpanded, isTrue);
    expect(agent.mode, 'system');
    expect(agent.commands.last['restoreState'], isNotNull);
  });

  test('script tokenizer preserves empty fields and rejects broken quotes', () {
    expect(scriptWords('type --key recipient ""'), <String>[
      'type',
      '--key',
      'recipient',
      '',
    ]);
    expect(scriptWords(r'''tap "Say \"hello\""'''), <String>[
      'tap',
      'Say "hello"',
    ]);
    expect(scriptWords("wait 'Screen ready'"), <String>[
      'wait',
      'Screen ready',
    ]);
    expect(
      () => scriptWords('tap "broken'),
      throwsA(isA<ScreenCaptureError>()),
    );
    expect(
      cli.assertionArgs(cli.Args(<String>['Screen ready'])),
      <String, Object?>{'text': 'Screen ready', 'exact': true},
    );
  });
}
