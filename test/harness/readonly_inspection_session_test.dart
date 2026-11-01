import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/readonly_home_catalog.dart';
import '../../harness/bin/readonly_inspection_session.dart';
import '../../harness/bin/screen_capture.dart';

Map<String, dynamic> _reply({bool wallet = false}) => <String, dynamic>{
  'ok': true, 'pid': 44, 'booted': true,
  'harnessMode': 'readonly-native', 'readOnly': true,
  'readonlyAdmission': <String, dynamic>{
    'schema': 1, 'scope': 'readonly_native_sdk_admission', 'status': 'CURRENT',
    'publicationAdmissionPaused': true, 'automaticReceiveDisabled': true,
  },
  if (wallet) 'readonlyWallet': <String, dynamic>{
    'schema': 1, 'scope': 'readonly_native_wallet_admission',
    'status': 'CURRENT',
    'chain': 321, 'selectedIndex': 1, 'nativeFrameObserved': true,
  },
};

class _JsonReentry {
  _JsonReentry(this.invoke);

  final void Function() invoke;

  String toJson() {
    invoke();
    return 'synthetic';
  }
}

class _CatalogStdout extends Fake implements Stdout {
  final List<Object?> lines = <Object?>[];

  @override
  void writeln([Object? object = '']) => lines.add(object);
}

void main() {
  test('the real Home script stays bound across capture and refusal',
      () async {
    final String script = File('harness/screens/home-rest.txt')
        .readAsStringSync();
    // Header-only transport data is not an actual rendered image.
    final Uint8List header = Uint8List(33)
      ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
      ..setAll(12, ascii.encode('IHDR'));
    ByteData.sublistView(header)
      ..setUint32(8, 13)
      ..setUint32(16, 1280)
      ..setUint32(20, 780);
    for (final String fault in <String>['unbound', 'none', 'negative']) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-catalog-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      File('${repository.path}/harness/screens/home-rest.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(script);
      bool expanded = true;
      String mode = 'light';
      bool restoredWindow = false;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final Map<String, dynamic> negative = <String, dynamic>{
        'ok': false, 'error': 'Synthetic capture refusal',
      };
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
          commands.add(command);
          final Object? name = command['cmd'];
          if (name == 'shot' && fault == 'negative') return negative;
          if (name == 'tap' && command['key'] == 'rail_toggle') {
            expanded = !expanded;
          }
          if (name == 'theme') {
            if (command['mode'] case final String requested) mode = requested;
            if (command['restore'] case final Map<String, dynamic> original) {
              mode = original['mode'] as String;
            }
          }
          if (name == 'window' && command['restoreState'] != null) {
            restoredWindow = true;
          }
          return <String, dynamic>{
            ..._reply(wallet: true),
            if (name == 'state') ...<String, dynamic>{
              'walletUnlocked': true, 'walletInitCompleted': true,
              'tab': 'dashboard', 'tabs': <String>['dashboard', 'transfer'],
              'locale': 'en', 'direction': 'ltr',
            },
            if (name == 'tree') 'nodes': <Object?>[
              <String, dynamic>{'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32]},
            ],
            if (name == 'theme') ...<String, dynamic>{
              'mode': mode, 'savedMode': 'ThemeMode.$mode',
              'brightness': mode,
            },
            if (name == 'window') ...<String, dynamic>{
              'window': <int>[80, 90, 1200, 700],
              'client': <int>[
                if (command['width'] != null) 1280 else 1200,
                if (command['height'] != null) 780 else 700,
              ],
              'minimized': false, 'maximized': true, 'clientMatched': true,
              if (command['restoreState'] != null) 'restored': true,
            },
            if (name == 'wait' || name == 'assert') ...<String, dynamic>{
              'ms': 0, 'asserted': true,
              'target': <String, dynamic>{'ref': 0, 'kind': 'region',
                'key': command['key'], 'rect': <int>[0, 0, 200, 100]},
            },
            if (name == 'shot') ...<String, dynamic>{
              'client': <int>[1280, 780], 'width': 1280, 'height': 780,
              'scale': 1, 'theme': mode, 'asserted': true,
              'png': base64Encode(header),
            },
          };
        },
      );
      // The real CLI reports to stdout; keep its lines out of test events.
      Future<Map<String, Object>> capture() =>
          IOOverrides.runZoned<Future<Map<String, Object>>>(
        () => captureReadonlyHomeRest(
          repository: repository, session: session,
        ),
        stdout: () => output,
      );
      if (fault == 'unbound') {
        await expectLater(capture(),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands, isEmpty);
        expect(output.lines, isEmpty);
        continue;
      }
      await session.bindWallet();
      if (fault == 'negative') {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(commands.last['cmd'], 'shot');
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length, 1);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
        expect(restoredWindow, isFalse);
        expect(expanded, isFalse);
      } else {
        final Map<String, Object> receipt = await capture();
        expect(receipt['scope'], 'readonly_native_home_catalog_capture');
        expect(receipt['capture_returned'], isTrue);
        expect(receipt['files'], <String>[
          '01-home-rest-dark.png', '01-home-rest-light.png',
        ]);
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/01-home-rest-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length, 2);
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'tap' && value['tab'] == 'dashboard').length, 2);
        expect(expanded, isTrue);
        expect(mode, 'light');
        expect(restoredWindow, isTrue);
      }
      final List<Map<String, Object?>> pointer = commands
          .where((Map<String, Object?> value) => value['cmd'] == 'hover')
          .toList();
      final List<Map<String, Object?>> expectedPointer = <Map<String, Object?>>[
        <String, Object?>{'cmd': 'hover', 'at': <int>[0, 0], 'settleMs': 0},
        <String, Object?>{'cmd': 'hover', 'key': 'nav_notifications'},
      ];
      expect(pointer, <Map<String, Object?>>[
        ...expectedPointer,
        if (fault == 'none') ...expectedPointer,
      ]);
      final List<Map<String, Object?>> tooltip = commands
          .where((Map<String, Object?> value) => value['cmd'] == 'wait' &&
              value['text'] == 'Notifications')
          .toList();
      final Map<String, Object?> expectedTooltip = <String, Object?>{
        'cmd': 'wait', 'text': 'Notifications', 'kind': 'text',
        'exact': true, 'timeoutMs': 5000,
      };
      expect(tooltip, <Map<String, Object?>>[
        expectedTooltip,
        if (fault == 'none') expectedTooltip,
      ]);
      expect(output.lines.length, fault == 'negative' ? 9 : 18);
      expect(output.lines.every((Object? line) => line is String &&
          line.startsWith('ok')), isTrue);
      expect(commands.every((Map<String, Object?> value) => <String>{
        'readonly-wallet-bind', 'state', 'tree', 'tap', 'theme', 'window',
        'wait', 'assert', 'shot', 'hover',
      }.contains(value['cmd'])), isTrue);
    }
  });

  test('the real Home selection retains bound hidden shots and refusals',
      () async {
    final String script = File('harness/screens/home-rest.txt')
        .readAsStringSync();
    final String hiddenScript = File('harness/screens/home-hidden.txt')
        .readAsStringSync();
    // Header-only transport data is not an actual rendered image.
    final Uint8List header = Uint8List(33)
      ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
      ..setAll(12, ascii.encode('IHDR'));
    ByteData.sublistView(header)
      ..setUint32(8, 13)
      ..setUint32(16, 1280)
      ..setUint32(20, 780);
    for (final String fault in <String>['unbound', 'none', 'negative',
      'hidden-negative']) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-catalog-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      File('${repository.path}/harness/screens/home-rest.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(script);
      File(repository.path + '/harness/screens/home-hidden.txt')
        .writeAsStringSync(hiddenScript);
      bool expanded = true;
      String mode = 'light';
      bool hidden = false;
      int shots = 0;
      final List<bool> observedAtShot = <bool>[];
      bool restoredWindow = false;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final Map<String, dynamic> negative = <String, dynamic>{
        'ok': false, 'error': 'Synthetic capture refusal',
      };
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
          commands.add(command);
          final Object? name = command['cmd'];
          if (name == 'shot') {
            shots++;
            observedAtShot.add(hidden);
            if ((fault == 'negative' && shots == 1) ||
                (fault == 'hidden-negative' && shots == 3)) {
              return negative;
            }
          }
          if (name == 'tap' && command['text'] == 'Hide balances') {
            expect(hidden, isFalse);
            hidden = true;
          }
          if (name == 'tap' && command['text'] == 'Show balances') {
            expect(hidden, isTrue);
            hidden = false;
          }
          if (name == 'tap' && command['key'] == 'rail_toggle') {
            expanded = !expanded;
          }
          if (name == 'theme') {
            if (command['mode'] case final String requested) mode = requested;
            if (command['restore'] case final Map<String, dynamic> original) {
              mode = original['mode'] as String;
            }
          }
          if (name == 'window' && command['restoreState'] != null) {
            restoredWindow = true;
          }
          return <String, dynamic>{
            ..._reply(wallet: true),
            if (name == 'state') ...<String, dynamic>{
              'walletUnlocked': true, 'walletInitCompleted': true,
              'tab': 'dashboard', 'tabs': <String>['dashboard', 'transfer'],
              'locale': 'en', 'direction': 'ltr',
            },
            if (name == 'tree') 'nodes': <Object?>[
              <String, dynamic>{'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32]},
            ],
            if (name == 'theme') ...<String, dynamic>{
              'mode': mode, 'savedMode': 'ThemeMode.$mode',
              'brightness': mode,
            },
            if (name == 'window') ...<String, dynamic>{
              'window': <int>[80, 90, 1200, 700],
              'client': <int>[
                if (command['width'] != null) 1280 else 1200,
                if (command['height'] != null) 780 else 700,
              ],
              'minimized': false, 'maximized': true, 'clientMatched': true,
              if (command['restoreState'] != null) 'restored': true,
            },
            if (name == 'wait' || name == 'assert') ...<String, dynamic>{
              'ms': 0, 'asserted': true,
              'target': <String, dynamic>{'ref': 0, 'kind': 'region',
                'key': command['key'], 'rect': <int>[0, 0, 200, 100]},
            },
            if (name == 'shot') ...<String, dynamic>{
              'client': <int>[1280, 780], 'width': 1280, 'height': 780,
              'scale': 1, 'theme': mode, 'asserted': true,
              'png': base64Encode(header),
            },
          };
        },
      );
      // The real CLI reports to stdout; keep its lines out of test events.
      Future<Map<String, Object>> capture() =>
          IOOverrides.runZoned<Future<Map<String, Object>>>(
        () => captureReadonlyHomeStates(
          repository: repository, session: session,
        ),
        stdout: () => output,
      );
      if (fault == 'unbound') {
        await expectLater(capture(),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands, isEmpty);
        expect(output.lines, isEmpty);
        continue;
      }
      await session.bindWallet();
      if (fault == 'negative' || fault == 'hidden-negative') {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(commands.last['cmd'], 'shot');
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length,
            fault == 'negative' ? 1 : 3);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
        expect(restoredWindow, isFalse);
        expect(expanded, isFalse);
      } else {
        final Map<String, Object> receipt = await capture();
        expect(receipt['scope'], 'readonly_native_home_catalog_capture');
        expect(receipt['capture_returned'], isTrue);
        expect(receipt['schema'], 2);
        expect(receipt['screens'], <String>['home-rest', 'home-hidden']);
        expect(receipt['files'], <String>[
          '01-home-rest-dark.png', '01-home-rest-light.png',
          '03-home-hidden-dark.png', '03-home-hidden-light.png',
        ]);
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/01-home-rest-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        for (final String theme in <String>['dark', 'light']) {
          final File image = File(repository.path + '/' +
            readonlyHomeCatalogDirectory + '/03-home-hidden-' + theme + '.png');
          expect(image.readAsBytesSync(), header);
        }
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length, 4);
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'tap' && value['tab'] == 'dashboard').length, 4);
        expect(expanded, isTrue);
        expect(mode, 'light');
        expect(restoredWindow, isTrue);
      }
      final List<Map<String, Object?>> pointer = commands
          .where((Map<String, Object?> value) => value['cmd'] == 'hover')
          .toList();
      final List<Map<String, Object?>> expectedPointer = <Map<String, Object?>>[
        <String, Object?>{'cmd': 'hover', 'at': <int>[0, 0], 'settleMs': 0},
        <String, Object?>{'cmd': 'hover', 'key': 'nav_notifications'},
      ];
      expect(pointer, <Map<String, Object?>>[
        ...expectedPointer,
        if (fault == 'none' || fault == 'hidden-negative') ...expectedPointer,
      ]);
      final List<Map<String, Object?>> tooltip = commands
          .where((Map<String, Object?> value) => value['cmd'] == 'wait' &&
              value['text'] == 'Notifications')
          .toList();
      final Map<String, Object?> expectedTooltip = <String, Object?>{
        'cmd': 'wait', 'text': 'Notifications', 'kind': 'text',
        'exact': true, 'timeoutMs': 5000,
      };
      expect(tooltip, <Map<String, Object?>>[
        expectedTooltip,
        if (fault == 'none' || fault == 'hidden-negative') expectedTooltip,
      ]);
      expect(output.lines.length, fault == 'negative' ? 9 :
          fault == 'hidden-negative' ? 25 : 36);
      expect(observedAtShot, <bool>[
        false, if (fault != 'negative') false,
        if (fault != 'negative') true,
        if (fault == 'none') true,
      ]);
      expect(hidden, fault == 'hidden-negative');
      if (fault != 'none') {
        final int originalCalls = commands.length;
        await expectLater(session.send(<String, Object?>{'cmd': 'state'},
          const Duration(seconds: 1)),
          throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands.length, originalCalls);
      }
      expect(output.lines.every((Object? line) => line is String &&
          line.startsWith('ok')), isTrue);
      expect(commands.every((Map<String, Object?> value) => <String>{
        'readonly-wallet-bind', 'state', 'tree', 'tap', 'theme', 'window',
        'wait', 'assert', 'shot', 'hover',
      }.contains(value['cmd'])), isTrue);
    }
  });

  test('an admitted original reply keeps identity and its actual mode',
      () async {
    final Map<String, dynamic> original = _reply();
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        expect(command['cmd'], 'ping');
        return original;
      },
    );
    expect(await session.send(<String, Object?>{'cmd': 'ping'},
        const Duration(seconds: 1)), same(original));
    expect(original['harnessMode'], 'readonly-native');
    expect(calls, 1);
    expect(session.walletBound, isFalse);
  });

  test('a foreign process mode or SDK receipt permanently refuses replies',
      () async {
    for (final String fault in <String>['pid', 'mode', 'pending', 'expanded']) {
      final Map<String, dynamic> value = _reply();
      switch (fault) {
        case 'pid': value['pid'] = 45;
        case 'mode': value['harnessMode'] = 'wallet';
        case 'pending':
          (value['readonlyAdmission'] as Map<String, dynamic>)['status'] =
              'PENDING';
        case 'expanded':
          (value['readonlyAdmission'] as Map<String, dynamic>)['extra'] = true;
      }
      int calls = 0;
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          return value;
        },
      );
      await expectLater(session.send(<String, Object?>{'cmd': 'ping'},
          const Duration(seconds: 1)),
          throwsA(isA<ReadonlyInspectionRefused>()));
      value['pid'] = 44;
      await expectLater(session.send(<String, Object?>{'cmd': 'ping'},
          const Duration(seconds: 1)),
          throwsA(isA<ReadonlyInspectionRefused>()));
      expect(calls, 1);
    }
  });

  test('wallet binding reserves its only original request and scope',
      () async {
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        expect(command, <String, Object?>{'cmd': 'readonly-wallet-bind'});
        return _reply(wallet: true);
      },
    );
    await session.bindWallet();
    expect(session.walletBound, isTrue);
    await expectLater(session.bindWallet(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 1);
  });

  test('an SDK-only bind cannot establish an opened wallet', () async {
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        return _reply();
      },
    );
    await expectLater(session.bindWallet(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(session.walletBound, isFalse);
    await expectLater(session.bindWallet(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 1);
  });

  test('every later reply retains the original opened-wallet scope',
      () async {
    bool current = true;
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        return _reply(wallet: current);
      },
    );
    await session.bindWallet();
    current = false;
    await expectLater(session.send(<String, Object?>{'cmd': 'shot'},
        const Duration(seconds: 1)),
        throwsA(isA<ReadonlyInspectionRefused>()));
    current = true;
    await expectLater(session.send(<String, Object?>{'cmd': 'shot'},
        const Duration(seconds: 1)),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 2);
  });

  test('an original exception and stack remain exact without replay',
      () async {
    final StateError error = StateError('Synthetic private transport failure');
    final StackTrace trace = StackTrace.current;
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) {
        calls++;
        return Future<Map<String, dynamic>>.error(error, trace);
      },
    );
    Object? seen;
    StackTrace? seenTrace;
    await session.send(<String, Object?>{'cmd': 'ping'},
        const Duration(seconds: 1)).then<void>(
      (_) => fail('An original failure cannot supply readiness'),
      onError: (Object original, StackTrace originalTrace) {
        seen = original;
        seenTrace = originalTrace;
      },
    );
    expect(seen, same(error));
    expect(seenTrace, same(trace));
    await expectLater(session.bindWallet(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 1);
  });

  test('an original negative reply is returned unchanged and retires the lane',
      () async {
    final Map<String, dynamic> refused = <String, dynamic>{
      'ok': false, 'error': 'synthetic private diagnostic',
    };
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        return refused;
      },
    );
    expect(await session.send(<String, Object?>{'cmd': 'readonly-entry'},
        const Duration(seconds: 1)), same(refused));
    await expectLater(session.bindWallet(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 1);
  });

  test('caught transport reentry also refuses the outer positive reply',
      () async {
    late ReadonlyInspectionSession session;
    int calls = 0;
    session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        await expectLater(session.send(<String, Object?>{'cmd': 'ping'},
            timeout), throwsA(isA<ReadonlyInspectionRefused>()));
        return _reply();
      },
    );
    await expectLater(session.send(<String, Object?>{'cmd': 'ping'},
        const Duration(seconds: 1)),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 1);
  });

  test('nested command values are retained before an original await',
      () async {
    final Completer<void> pending = Completer<void>();
    final List<String> values = <String>['initial'];
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        expect(() => command['cmd'] = 'seed', throwsUnsupportedError);
        await pending.future;
        expect(command['values'], <String>['initial']);
        return _reply();
      },
    );
    final Future<Map<String, dynamic>> original = session.send(
      <String, Object?>{'cmd': 'type', 'values': values},
      const Duration(seconds: 1),
    );
    values[0] = 'changed';
    pending.complete();
    await original;
  });

  test('caught serialization reentry refuses before transport dispatch',
      () async {
    int calls = 0;
    late Future<void> inner;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        return _reply();
      },
    );
    final _JsonReentry value = _JsonReentry(() {
      inner = expectLater(session.send(<String, Object?>{'cmd': 'ping'},
          const Duration(seconds: 1)),
          throwsA(isA<ReadonlyInspectionRefused>()));
    });
    await expectLater(session.send(
        <String, Object?>{'cmd': 'type', 'value': value},
        const Duration(seconds: 1)),
        throwsA(isA<ReadonlyInspectionRefused>()));
    await inner;
    expect(calls, 0);
  });

  test('financial commands and an unreserved bind never reach the transport',
      () async {
    for (final String name in <String>[
      'seed', 'lab-send', 'lab-quiesce', 'lab-reopen-observe',
      'wallet-recipe', 'clipboard', 'readonly-wallet-bind', 'unknown',
    ]) {
      int calls = 0;
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          return _reply(wallet: true);
        },
      );
      await expectLater(session.send(<String, Object?>{'cmd': name},
          const Duration(seconds: 1)),
          throwsA(isA<ReadonlyInspectionRefused>()));
      expect(calls, 0);
    }
  });

  test('rail snapshots require the original opened-wallet binding', () async {
    int calls = 0;
    final ReadonlyInspectionSession session = ReadonlyInspectionSession(
      processId: 44,
      original: (Map<String, Object?> command, Duration timeout) async {
        calls++;
        return _reply(wallet: true);
      },
    );
    await expectLater(session.railExpanded(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    await expectLater(session.bindWallet(),
        throwsA(isA<ReadonlyInspectionRefused>()));
    expect(calls, 0);
  });

  test('positive rail snapshots preserve a collapsed or expanded session',
      () async {
    for (final bool expanded in <bool>[false, true]) {
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          commands.add(command);
          return <String, dynamic>{
            ..._reply(wallet: true),
            if (command['cmd'] == 'tree') 'nodes': <Object?>[
              <String, dynamic>{
                'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32],
              },
              <String, dynamic>{'kind': 'text', 'label': 'Synthetic content'},
            ],
          };
        },
      );
      await session.bindWallet();
      expect(await session.railExpanded(), expanded);
      expect((await session.send(<String, Object?>{'cmd': 'ping'},
          const Duration(seconds: 1)))['ok'], isTrue);
      expect(commands, <Map<String, Object?>>[
        <String, Object?>{'cmd': 'readonly-wallet-bind'},
        <String, Object?>{'cmd': 'tree'},
        <String, Object?>{'cmd': 'ping'},
      ]);
      expect(session.walletBound, isTrue);
    }
  });

  test('uncertain rail geometry retires without another original request',
      () async {
    final Map<String, dynamic> toggle = <String, dynamic>{
      'key': 'rail_toggle', 'kind': 'button', 'rect': <int>[8, 36, 40, 32],
    };
    final List<Map<String, dynamic>> faults = <Map<String, dynamic>>[
      <String, dynamic>{'ok': false},
      <String, dynamic>{'nodes': null},
      <String, dynamic>{'nodes': 1},
      <String, dynamic>{'nodes': <Object?>[]},
      <String, dynamic>{'nodes': <Object?>[toggle, null]},
      <String, dynamic>{'nodes': <Object?>[toggle, toggle]},
      <String, dynamic>{'nodes': <Object?>[
        <String, dynamic>{...toggle, 'enabled': false},
      ]},
      <String, dynamic>{'nodes': <Object?>[
        <String, dynamic>{...toggle, 'enabled': 'true'},
      ]},
      <String, dynamic>{'nodes': <Object?>[
        <String, dynamic>{...toggle, 'kind': 'text'},
      ]},
      <String, dynamic>{'nodes': <Object?>[
        toggle, <String, dynamic>{'kind': 'error'},
      ]},
      <String, dynamic>{'nodes': List<Object?>.filled(16385, toggle)},
      <String, dynamic>{'pid': 45, 'nodes': <Object?>[toggle]},
      <String, dynamic>{'readonlyWallet': null, 'nodes': <Object?>[toggle]},
      for (final Object? rect in <Object?>[
        null, 1, 'private synthetic value', <int>[], <int>[8, 36, 40],
        <int>[8, 36, 40, 32, 1], <Object?>[8, 36, true, 32],
        <num>[8, 36, 40.0, 32], <int>[-1, 36, 40, 32],
        <int>[8, 32769, 40, 32], <int>[8, 36, 0, 32],
        <int>[8, 36, 41, 32], <int>[8, 36, 183, 32],
        <int>[8, 36, 185, 32], <int>[8, 36, 40, 31],
        <int>[8, 36, 40, 33],
      ]) <String, dynamic>{'nodes': <Object?>[
        <String, dynamic>{...toggle, 'rect': rect},
      ]},
    ];
    for (final Map<String, dynamic> fault in faults) {
      int calls = 0;
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          return <String, dynamic>{
            ..._reply(wallet: true),
            if (command['cmd'] == 'tree') ...fault,
          };
        },
      );
      await session.bindWallet();
      await expectLater(session.railExpanded(),
          throwsA(isA<ReadonlyInspectionRefused>()));
      await expectLater(session.send(<String, Object?>{'cmd': 'ping'},
          const Duration(seconds: 1)),
          throwsA(isA<ReadonlyInspectionRefused>()));
      expect(calls, 2);
    }
  });

  test('Home preparation uses positive snapshots and restores its rail',
      () async {
    for (final bool original in <bool>[false, true]) {
      bool expanded = original;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          commands.add(command);
          expect(timeout, const Duration(seconds: 30));
          if (command['cmd'] == 'tap') {
            expect(command['key'], 'rail_toggle');
            expanded = !expanded;
          }
          return <String, dynamic>{
            ..._reply(wallet: true),
            if (command['cmd'] == 'state') ...<String, dynamic>{
              'walletUnlocked': true, 'walletInitCompleted': true,
              'tab': 'dashboard', 'tabs': <String>['dashboard', 'transfer'],
              'locale': 'en', 'direction': 'ltr',
            },
            if (command['cmd'] == 'tree') 'nodes': <Object?>[
              <String, dynamic>{
                'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32],
              },
            ],
          };
        },
      );
      await session.bindWallet();
      await session.prepareScreenHome();
      expect(expanded, isFalse);
      await session.restoreScreenRail(expanded: original);
      expect(expanded, original);
      expect(await session.railExpanded(), original);
      expect(commands.where((Map<String, Object?> c) =>
          c['cmd'] == 'tap').length, original ? 2 : 0);
      expect(commands.where((Map<String, Object?> c) =>
          c['cmd'] == 'wait').length, 0);
      expect(commands.every((Map<String, Object?> c) =>
          <String>{'readonly-wallet-bind', 'state', 'tree', 'tap'}
              .contains(c['cmd'])), isTrue);
      expect(session.walletBound, isTrue);
    }
  });

  test('uncertain Home preparation holds before any UI input or restore',
      () async {
    final List<Map<String, dynamic>> faults = <Map<String, dynamic>>[
      <String, dynamic>{'tab': 'lock'},
      <String, dynamic>{'tab': 'transfer'},
      <String, dynamic>{'tab': null},
      <String, dynamic>{'locale': 'ar'},
      <String, dynamic>{'direction': 'rtl'},
      <String, dynamic>{'walletUnlocked': false},
      <String, dynamic>{'walletInitCompleted': false},
      <String, dynamic>{'tabs': <String>[]},
      <String, dynamic>{'tabs': <String>['transfer']},
      <String, dynamic>{'tabs': <String>['dashboard', 'dashboard']},
      <String, dynamic>{'tabs': <Object?>['dashboard', null]},
      <String, dynamic>{'tabs': List<String>.filled(17, 'dashboard')},
      <String, dynamic>{'ok': false},
      <String, dynamic>{'pid': 45},
      <String, dynamic>{'readonlyWallet': null},
    ];
    for (final Map<String, dynamic> fault in faults) {
      int calls = 0;
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          expect(command['cmd'], calls == 1 ? 'readonly-wallet-bind' : 'state');
          return <String, dynamic>{
            ..._reply(wallet: true),
            if (command['cmd'] == 'state') ...<String, dynamic>{
              'walletUnlocked': true, 'walletInitCompleted': true,
              'tab': 'dashboard', 'tabs': <String>['dashboard'],
              'locale': 'en', 'direction': 'ltr', ...fault,
            },
          };
        },
      );
      await session.bindWallet();
      await expectLater(session.prepareScreenHome(),
          throwsA(isA<ReadonlyInspectionRefused>()));
      await expectLater(session.restoreScreenRail(expanded: true),
          throwsA(isA<ReadonlyInspectionRefused>()));
      expect(calls, 2);
    }
    for (final bool restore in <bool>[false, true]) {
      int calls = 0;
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          calls++;
          return _reply(wallet: true);
        },
      );
      await expectLater(restore ? session.restoreScreenRail(expanded: true)
          : session.prepareScreenHome(),
          throwsA(isA<ReadonlyInspectionRefused>()));
      expect(calls, 0);
    }
  });

  test('invalid process IDs refuse before a transport can be used', () {
    for (final int pid in <int>[-1, 0]) {
      expect(() => ReadonlyInspectionSession(processId: pid,
        original: (Map<String, Object?> command, Duration timeout) async =>
            throw StateError('No original call is admitted'),
      ), throwsA(isA<ReadonlyInspectionRefused>()));
    }
  });
}
