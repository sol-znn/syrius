import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ScreenCaptureError implements Exception {
  const ScreenCaptureError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The original operation entered before a capture result is known.
enum ScreenCaptureStep {
  preflight, outputPreflight, themeSnapshot, windowSnapshot, windowShow,
  railSnapshot, clientResize, homePreparation, themeSelection, scriptLine,
  shotRequest, shotValidation, outputRetention, afterCaptureLine,
  railRestoration, themeRestoration, windowRestoration, complete,
}

/// A fixed step and catalog context, without commands, paths or response text.
class ScreenCaptureObservation {
  const ScreenCaptureObservation(this.step, {
    this.screen, this.theme, this.line,
  });

  final ScreenCaptureStep step;
  final String? screen;
  final String? theme;
  final int? line;
}

class ScreenSpec {
  const ScreenSpec(this.number, this.id);

  final int number;
  final String id;

  String stem(String theme) {
    if (theme != 'dark' && theme != 'light') {
      throw const ScreenCaptureError('theme must be dark or light');
    }
    return '${number.toString().padLeft(2, '0')}-$id-$theme';
  }
}

/// The mockup section order and its 01–47 shot prefixes are the capture order.
/// Catalog tests bind this list to both source sections and shot filenames.
const List<ScreenSpec> screenCatalog = <ScreenSpec>[
  ScreenSpec(1, 'home-rest'),
  ScreenSpec(2, 'home-open'),
  ScreenSpec(3, 'home-hidden'),
  ScreenSpec(4, 'home-bell'),
  ScreenSpec(5, 'home-goto'),
  ScreenSpec(6, 'home-zap'),
  ScreenSpec(7, 'send-rest'),
  ScreenSpec(8, 'send-warn'),
  ScreenSpec(9, 'receive'),
  ScreenSpec(10, 'receive-qr'),
  ScreenSpec(11, 'zap-form'),
  ScreenSpec(12, 'send-confirm'),
  ScreenSpec(13, 'staking'),
  ScreenSpec(14, 'staking-new'),
  ScreenSpec(15, 'staking-empty'),
  ScreenSpec(16, 'pillars'),
  ScreenSpec(17, 'pillar-mine'),
  ScreenSpec(18, 'sentinels'),
  ScreenSpec(19, 'spawn'),
  ScreenSpec(20, 'pillar-done'),
  ScreenSpec(21, 'plasma'),
  ScreenSpec(22, 'plasma-fuse'),
  ScreenSpec(23, 'tokens'),
  ScreenSpec(24, 'token-mine'),
  ScreenSpec(25, 'token-new'),
  ScreenSpec(26, 'swap-list'),
  ScreenSpec(27, 'swap-start'),
  ScreenSpec(28, 'az'),
  ScreenSpec(29, 'az-project'),
  ScreenSpec(30, 'set-node'),
  ScreenSpec(31, 'set-security'),
  ScreenSpec(32, 'set-display'),
  ScreenSpec(33, 'set-wallet'),
  ScreenSpec(34, 'set-apps'),
  ScreenSpec(35, 'set-addresses'),
  ScreenSpec(36, 'set-about'),
  ScreenSpec(37, 'set-licences'),
  ScreenSpec(38, 'set-originals'),
  ScreenSpec(39, 'launch'),
  ScreenSpec(40, 'launch-settle'),
  ScreenSpec(41, 'lock-screen'),
  ScreenSpec(42, 'lock-wrong'),
  ScreenSpec(43, 'lock-pick'),
  ScreenSpec(44, 'welcome'),
  ScreenSpec(45, 'import'),
  ScreenSpec(46, 'seed-quiz'),
  ScreenSpec(47, 'wallet-ready'),
];

List<ScreenSpec> selectScreens(String id) {
  if (id == 'all') return screenCatalog;
  for (final ScreenSpec screen in screenCatalog) {
    if (screen.id == id) return <ScreenSpec>[screen];
  }
  throw ScreenCaptureError('unknown screen "$id"; use a catalog id or all');
}

class ScreenLine {
  const ScreenLine(this.number, this.words);

  final int number;
  final List<String> words;
}

/// Parses words without shell expansion. A malformed quote is a script error,
/// rather than a different command accidentally reaching the wallet.
List<String> scriptWords(String line) {
  final List<String> words = <String>[];
  StringBuffer word = StringBuffer();
  String? quote;
  bool started = false;
  for (int i = 0; i < line.length; i++) {
    final String char = line[i];
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else if (quote == '"' &&
          char == r'\' &&
          i + 1 < line.length &&
          (line[i + 1] == '"' || line[i + 1] == r'\')) {
        word.write(line[++i]);
      } else {
        word.write(char);
      }
    } else if (char == '"' || char == "'") {
      quote = char;
      started = true;
    } else if (char.trim().isEmpty) {
      if (started) {
        words.add(word.toString());
        word = StringBuffer();
        started = false;
      }
    } else {
      word.write(char);
      started = true;
    }
  }
  if (quote != null) {
    throw const ScreenCaptureError('unclosed quote');
  }
  if (started) words.add(word.toString());
  return words;
}

class ScreenScript {
  const ScreenScript(this.screen, this.lines, this.assertion, {
    this.afterCapture = const <ScreenLine>[],
  });

  final ScreenSpec screen;
  final List<ScreenLine> lines;
  final List<ScreenLine> afterCapture;
  final Map<String, Object?> assertion;
}

typedef AgentCall =
    Future<Map<String, dynamic>> Function(
      Map<String, Object?> command,
    );
typedef AssertionParser = Map<String, Object?> Function(List<String> words);

/// Runs only UI commands, against an instance already owned by the launcher.
/// Lifecycle commands and output paths belong to the capture runner, never a
/// page script. Entry states need explicit reversible preparation in F06/N.
class ScreenCapture {
  ScreenCapture({
    required this.repository,
    required this.call,
    required this.prepareHome,
    required this.runLine,
    required this.assertionFor,
    this.readRailState,
    this.restoreRailState,
    this.onStep,
  });

  final Directory repository;
  final AgentCall call;
  final Future<void> Function() prepareHome;
  final Future<void> Function(List<String>) runLine;
  final AssertionParser assertionFor;
  final Future<bool> Function()? readRailState;
  final Future<void> Function({required bool expanded})? restoreRailState;
  final void Function(ScreenCaptureObservation step)? onStep;

  static const String _afterCapturePrefix = '# after-capture:';

  static const Set<String> _uiCommands = <String>{
    'tap',
    'hover',
    'type',
    'key',
    'scroll',
    'drag',
    'wait',
    'reveal',
    'goto',
    'lock',
    'assert',
  };

  String _join(List<String> parts) =>
      <String>[repository.path, ...parts].join(Platform.pathSeparator);

  FileSystemEntityType _type(List<String> parts) =>
      FileSystemEntity.typeSync(_join(parts), followLinks: false);

  void _checkParents(List<String> parts) {
    for (int i = 1; i <= parts.length; i++) {
      final FileSystemEntityType type = _type(parts.sublist(0, i));
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw ScreenCaptureError(
          'refusing non-directory or link: ${parts.sublist(0, i).join('/')}',
        );
      }
    }
  }

  List<String> _outputParts(String? relative) {
    final List<String> parts = (relative ?? '.harness/shots').split(
      RegExp(r'[/\\]'),
    );
    final RegExp name = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$');
    final RegExp reserved = RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    );
    if (parts.length < 2 ||
        parts.first != '.harness' ||
        parts
            .skip(1)
            .any(
              (String p) =>
                  !name.hasMatch(p) || p.endsWith('.') || reserved.hasMatch(p),
            )) {
      throw const ScreenCaptureError(
        'screens --dir must be a fresh relative directory beneath .harness',
      );
    }
    _checkParents(parts);
    if (relative != null && _type(parts) != FileSystemEntityType.notFound) {
      throw const ScreenCaptureError('screens --dir already exists');
    }
    return parts;
  }

  ScreenScript _script(ScreenSpec screen) {
    final List<String> parts = <String>['harness', 'screens'];
    _checkParents(parts);
    final List<String> fileParts = <String>[...parts, '${screen.id}.txt'];
    if (_type(fileParts) != FileSystemEntityType.file) {
      throw ScreenCaptureError(
        'missing script or refused link: harness/screens/${screen.id}.txt',
      );
    }
    final List<String> source = File(_join(fileParts)).readAsLinesSync();
    final List<ScreenLine> lines = <ScreenLine>[];
    final List<ScreenLine> afterCapture = <ScreenLine>[];
    for (int i = 0; i < source.length; i++) {
      final String text = source[i].trim();
      if (text.isEmpty) continue;
      final bool after = text.startsWith(_afterCapturePrefix);
      if (text.startsWith('#') && !after) {
        if (text.startsWith('# prerequisite:') &&
            text != '# prerequisite: unlocked-home') {
          throw ScreenCaptureError('${screen.id}: ${text.substring(2)}');
        }
        continue;
      }
      try {
        final List<String> words = scriptWords(
          after ? text.substring(_afterCapturePrefix.length).trim() : text,
        );
        if (words.isEmpty || !_uiCommands.contains(words.first) ||
            words.any(
              (String w) => w == '--instance' || w.startsWith('--instance='),
            )) {
          throw const ScreenCaptureError('not a screen UI command');
        }
        if (after) {
          if (lines.isEmpty || lines.last.words.first != 'assert') {
            throw const ScreenCaptureError(
              'after-capture needs a completed assertion',
            );
          }
          afterCapture.add(ScreenLine(i + 1, words));
        } else {
          if (afterCapture.isNotEmpty) {
            throw const ScreenCaptureError(
              'capture commands cannot follow after-capture',
            );
          }
          lines.add(ScreenLine(i + 1, words));
        }
      } on ScreenCaptureError catch (e) {
        throw ScreenCaptureError('${screen.id}:${i + 1}: $e');
      }
    }
    if (lines.isEmpty || lines.last.words.first != 'assert') {
      throw ScreenCaptureError('${screen.id}: finish the script with assert');
    }
    return ScreenScript(screen, lines, assertionFor(lines.last.words),
      afterCapture: afterCapture,
    );
  }

  /// Applies the actual script parser before any theme or window effect.
  /// Pending native prerequisites remain refusals, including for one screen.
  List<ScreenScript> preflight(String id) =>
      selectScreens(id).map(_script).toList();

  void _requireClient(Map<String, dynamic> response) {
    final Object? value = response['client'];
    if (value is! List ||
        value.length != 2 ||
        value[0] is! num ||
        value[1] is! num ||
        !(value[0] as num).isFinite ||
        !(value[1] as num).isFinite ||
        ((value[0] as num) - 1280).abs() >= 0.01 ||
        ((value[1] as num) - 780).abs() >= 0.01) {
      throw const ScreenCaptureError('observed client area is not 1280 by 780');
    }
  }

  Uint8List _png(Map<String, dynamic> shot, String theme) {
    _requireClient(shot);
    if (shot['width'] != 1280 ||
        shot['height'] != 780 ||
        shot['scale'] != 1 ||
        shot['theme'] != theme ||
        shot['asserted'] != true) {
      throw const ScreenCaptureError(
        'capture geometry, theme or state differs',
      );
    }
    final Object? encoded = shot['png'];
    if (encoded is! String || encoded.length > 24 * 1024 * 1024) {
      throw const ScreenCaptureError('missing or oversized PNG');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const ScreenCaptureError('invalid PNG encoding');
    }
    const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    final bool hasSignature =
        bytes.length >= 8 &&
        signature.asMap().entries.every(
          (MapEntry<int, int> e) => bytes[e.key] == e.value,
        );
    if (bytes.length < 33 ||
        bytes.length > 16 * 1024 * 1024 ||
        !hasSignature ||
        ByteData.sublistView(bytes).getUint32(8) != 13 ||
        ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR' ||
        ByteData.sublistView(bytes).getUint32(16) != 1280 ||
        ByteData.sublistView(bytes).getUint32(20) != 780) {
      throw const ScreenCaptureError('PNG header dimensions differ');
    }
    return bytes;
  }

  Future<List<String>> capture(String id, {String? directory}) async =>
      _capture(selectScreens(id), directory: directory);

  /// Preflights one finite selection before the first UI or output effect.
  /// The caller cannot mutate that selection while original inputs await.
  Future<List<String>> captureSelection(
    List<String> ids, {
    String? directory,
  }) async {
    final List<String> retained = List<String>.of(ids);
    if (retained.isEmpty || retained.length > screenCatalog.length ||
        retained.toSet().length != retained.length ||
        retained.contains('all')) {
      throw const ScreenCaptureError('selection needs unique catalog ids');
    }
    final List<ScreenSpec> screens = <ScreenSpec>[
      for (final String id in retained) selectScreens(id).single,
    ];
    return _capture(screens, directory: directory);
  }

  Future<List<String>> _capture(
    List<ScreenSpec> screens, {
    String? directory,
  }) async {
    void enter(ScreenCaptureStep step, {
      ScreenSpec? screen, String? theme, int? line,
    }) {
      onStep?.call(ScreenCaptureObservation(
        step, screen: screen?.id, theme: theme, line: line,
      ));
    }
    enter(ScreenCaptureStep.preflight);
    if ((readRailState == null) != (restoreRailState == null)) {
      throw const ScreenCaptureError('rail snapshot needs a restore callback');
    }
    // Complete preflight before changing the theme, moving the window or
    // creating outputs. A missing page script must not produce partial proof.
    final List<ScreenScript> scripts = screens.map(_script).toList();
    enter(ScreenCaptureStep.outputPreflight);
    final List<String> output = _outputParts(directory);
    for (final ScreenSpec screen in screens) {
      for (final String theme in <String>['dark', 'light']) {
        if (_type(<String>[...output, '${screen.stem(theme)}.png']) !=
            FileSystemEntityType.notFound) {
          throw ScreenCaptureError(
            'capture already exists: ${screen.stem(theme)}.png',
          );
        }
      }
    }
    enter(ScreenCaptureStep.themeSnapshot);
    final Map<String, dynamic> originalTheme = await call(
      <String, Object?>{'cmd': 'theme'},
    );
    enter(ScreenCaptureStep.windowSnapshot);
    final Map<String, dynamic> originalWindow = await call(
      <String, Object?>{'cmd': 'window'},
    );
    final List<String> captured = <String>[];
    bool? originalRail;
    Object? failure;
    final List<String> restorationFailures = <String>[];
    try {
      enter(ScreenCaptureStep.windowShow);
      await call(<String, Object?>{'cmd': 'window', 'do': 'show'});
      enter(ScreenCaptureStep.railSnapshot);
      originalRail = await readRailState?.call();
      for (final ScreenScript script in scripts) {
        for (final String theme in <String>['dark', 'light']) {
          enter(ScreenCaptureStep.clientResize,
            screen: script.screen, theme: theme,
          );
          final Map<String, dynamic> window = await call(<String, Object?>{
            'cmd': 'window',
            'do': 'show',
            'width': 1280,
            'height': 780,
          });
          _requireClient(window);
          if (window['clientMatched'] != true) {
            throw const ScreenCaptureError('client resize was not established');
          }
          enter(ScreenCaptureStep.homePreparation,
            screen: script.screen, theme: theme,
          );
          await prepareHome();
          enter(ScreenCaptureStep.themeSelection,
            screen: script.screen, theme: theme,
          );
          final Map<String, dynamic> themed = await call(
            <String, Object?>{'cmd': 'theme', 'mode': theme},
          );
          if (themed['mode'] != theme || themed['brightness'] != theme) {
            throw const ScreenCaptureError('requested theme was not observed');
          }
          for (final ScreenLine line in script.lines) {
            enter(ScreenCaptureStep.scriptLine,
              screen: script.screen, theme: theme, line: line.number,
            );
            try {
              await runLine(line.words);
            } on Object catch (e) {
              throw ScreenCaptureError(
                '${script.screen.id}:${line.number}: $e',
              );
            }
          }
          enter(ScreenCaptureStep.shotRequest,
            screen: script.screen, theme: theme,
          );
          final Map<String, dynamic> shot = await call(<String, Object?>{
            'cmd': 'shot',
            'width': 1280,
            'height': 780,
            'theme': theme,
            'expect': script.assertion,
          });
          enter(ScreenCaptureStep.shotValidation,
            screen: script.screen, theme: theme,
          );
          final Uint8List bytes = _png(shot, theme);
          enter(ScreenCaptureStep.outputRetention,
            screen: script.screen, theme: theme,
          );
          _checkParents(output);
          Directory(_join(output)).createSync(recursive: true);
          final List<String> path = <String>[
            ...output,
            '${script.screen.stem(theme)}.png',
          ];
          if (_type(path) != FileSystemEntityType.notFound) {
            throw const ScreenCaptureError('capture target changed during run');
          }
          // Refuse a target that appeared after preflight too. This run owns
          // the directory; a later path reopen is not an adversarial-FS guard.
          File(_join(path))
            ..createSync(exclusive: true)
            ..writeAsBytesSync(bytes, flush: true);
          captured.add(path.join('/'));
          // These real UI inputs run once after a fully retained positive shot.
          // A refusal propagates; neither capture nor restoration is replayed.
          for (final ScreenLine line in script.afterCapture) {
            enter(ScreenCaptureStep.afterCaptureLine,
              screen: script.screen, theme: theme, line: line.number,
            );
            try {
              await runLine(line.words);
            } on Object catch (e) {
              throw ScreenCaptureError(
                '${script.screen.id}:${line.number}: $e',
              );
            }
          }
        }
      }
    } on Object catch (e) {
      failure = e;
    } finally {
      if (originalRail != null) {
        try {
          if (failure == null && restorationFailures.isEmpty) {
            enter(ScreenCaptureStep.railRestoration);
          }
          await restoreRailState!(expanded: originalRail);
        } on Object catch (e) {
          restorationFailures.add('rail restore: $e');
        }
      }
      try {
        if (failure == null && restorationFailures.isEmpty) {
          enter(ScreenCaptureStep.themeRestoration);
        }
        await call(<String, Object?>{'cmd': 'theme', 'restore': originalTheme});
      } on Object catch (e) {
        restorationFailures.add('theme restore: $e');
      }
      try {
        if (failure == null && restorationFailures.isEmpty) {
          enter(ScreenCaptureStep.windowRestoration);
        }
        await call(<String, Object?>{
          'cmd': 'window',
          'restoreState': originalWindow,
        });
      } on Object catch (e) {
        restorationFailures.add('window restore: $e');
      }
    }
    if (failure != null || restorationFailures.isNotEmpty) {
      throw ScreenCaptureError(
        <String>[
          if (failure != null) failure.toString(),
          ...restorationFailures,
          if (captured.isNotEmpty)
            '${captured.length} earlier captures retained',
        ].join('; '),
      );
    }
    enter(ScreenCaptureStep.complete);
    return captured;
  }
}
