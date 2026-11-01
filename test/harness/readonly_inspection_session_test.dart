import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/ci_wallet_inspection.dart'
    show readonlyInspectionCatalogFamily;
import '../../harness/bin/readonly_details_catalog.dart';
import '../../harness/bin/readonly_home_catalog.dart';
import '../../harness/bin/readonly_inspection_session.dart';
import '../../harness/bin/readonly_navigation_catalog.dart';
import '../../harness/bin/readonly_settings_catalog.dart';
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
  test('catalog choice preserves the original Details default', () {
    expect(readonlyInspectionCatalogFamily(<String, String>{}), 'details');
    for (final String family in <String>[
      'home', 'settings', 'navigation', 'details',
    ]) {
      expect(readonlyInspectionCatalogFamily(<String, String>{
        'SYRIUS_READONLY_CATALOG_FAMILY': family,
      }), family);
    }
    for (final String refused in <String>[
      '', 'Home', 'home,navigation', 'all', '../home', ' details',
    ]) {
      expect(() => readonlyInspectionCatalogFamily(<String, String>{
        'SYRIUS_READONLY_CATALOG_FAMILY': refused,
      }), throwsA(isA<ReadonlyInspectionRefused>()));
    }
  });

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
      File('${repository.path}/harness/screens/home-hidden.txt')
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
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/03-home-hidden-$theme.png');
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

  test('real Home open shots retain bound state and first refusals',
      () async {
    final String script = File('harness/screens/home-rest.txt')
        .readAsStringSync();
    final String hiddenScript = File('harness/screens/home-hidden.txt')
        .readAsStringSync();
    final String openScript = File('harness/screens/home-open.txt')
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
      'hidden-negative', 'open-negative', 'open-restore-negative']) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-catalog-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      File('${repository.path}/harness/screens/home-rest.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(script);
      File('${repository.path}/harness/screens/home-hidden.txt')
        .writeAsStringSync(hiddenScript);
      File('${repository.path}/harness/screens/home-open.txt')
        .writeAsStringSync(openScript);
      bool expanded = true;
      String mode = 'light';
      bool hidden = false;
      bool tokensOpen = false;
      String currentTab = 'dashboard';
      int retainedOpenRestorations = 0;
      final List<bool> tokensAtShot = <bool>[];
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
            tokensAtShot.add(tokensOpen);
            if ((fault == 'negative' && shots == 1) ||
                (fault == 'hidden-negative' && shots == 5) ||
                (fault == 'open-negative' && shots == 3)) {
              return negative;
            }
          }
          final Object? requestedTab = command['tab'];
          if (name == 'tap' && requestedTab is String) {
            currentTab = requestedTab;
            if (currentTab == 'transfer') {
              tokensOpen = false;
            }
          }
          if (name == 'tap' && command['key'] == 'home_tokens_toggle') {
            if (tokensOpen) {
              final File retained = File('${repository.path}/'
                '$readonlyHomeCatalogDirectory/02-home-open-$mode.png');
              expect(retained.readAsBytesSync(), header);
              if (fault == 'open-restore-negative') {
                return negative;
              }
              retainedOpenRestorations++;
            }
            tokensOpen = !tokensOpen;
          }
          if (name == 'wait' && command['key'] == 'home_tokens_body') {
            expect(tokensOpen, command['gone'] != true);
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
              'tab': currentTab, 'tabs': <String>['dashboard', 'transfer'],
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
        () => captureReadonlyHomeOpenStates(
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
      if (fault == 'negative' || fault == 'hidden-negative' ||
          fault == 'open-negative' || fault == 'open-restore-negative') {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(commands.last['cmd'],
            fault == 'open-restore-negative' ? 'tap' : 'shot');
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length,
            fault == 'negative' ? 1 : fault == 'hidden-negative' ? 5 : 3);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
        expect(restoredWindow, isFalse);
        expect(expanded, fault.startsWith('open-'));
      } else {
        final Map<String, Object> receipt = await capture();
        expect(receipt['scope'], 'readonly_native_home_catalog_capture');
        expect(receipt['capture_returned'], isTrue);
        expect(receipt['schema'], 3);
        expect(receipt['screens'],
            <String>['home-rest', 'home-open', 'home-hidden']);
        expect(receipt['files'], <String>[
          '01-home-rest-dark.png', '01-home-rest-light.png',
          '02-home-open-dark.png', '02-home-open-light.png',
          '03-home-hidden-dark.png', '03-home-hidden-light.png',
        ]);
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/01-home-rest-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/02-home-open-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/03-home-hidden-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length, 6);
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'tap' && value['tab'] == 'dashboard').length, 6);
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
        if (fault != 'negative') ...expectedPointer,
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
        if (fault != 'negative') expectedTooltip,
      ]);
      expect(observedAtShot,
          List<bool>.generate(shots, (int index) => index >= 4));
      expect(tokensAtShot, List<bool>.generate(shots,
          (int index) => index >= 2 && index < 4));
      expect(tokensOpen, fault.startsWith('open-'));
      expect(retainedOpenRestorations,
          fault == 'none' || fault == 'hidden-negative' ? 2 : 0);
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

  test('real Home palette shots dismiss only after retained positive output',
      () async {
    final String script = File('harness/screens/home-rest.txt')
        .readAsStringSync();
    final String hiddenScript = File('harness/screens/home-hidden.txt')
        .readAsStringSync();
    final String openScript = File('harness/screens/home-open.txt')
        .readAsStringSync();
    final String gotoScript = File('harness/screens/home-goto.txt')
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
      'hidden-negative', 'open-negative', 'open-restore-negative',
      'goto-negative', 'goto-restore-negative']) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-catalog-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      File('${repository.path}/harness/screens/home-rest.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(script);
      File('${repository.path}/harness/screens/home-hidden.txt')
        .writeAsStringSync(hiddenScript);
      File('${repository.path}/harness/screens/home-open.txt')
        .writeAsStringSync(openScript);
      File('${repository.path}/harness/screens/home-goto.txt')
        .writeAsStringSync(gotoScript);
      bool expanded = true;
      String mode = 'light';
      bool hidden = false;
      bool tokensOpen = false;
      bool paletteOpen = false;
      int paletteRestorations = 0;
      final List<bool> paletteAtShot = <bool>[];
      String currentTab = 'dashboard';
      int retainedOpenRestorations = 0;
      final List<bool> tokensAtShot = <bool>[];
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
            tokensAtShot.add(tokensOpen);
            paletteAtShot.add(paletteOpen);
            if ((fault == 'negative' && shots == 1) ||
                (fault == 'hidden-negative' && shots == 5) ||
                (fault == 'open-negative' && shots == 3) ||
                (fault == 'goto-negative' && shots == 7)) {
              return negative;
            }
          }
          final Object? requestedTab = command['tab'];
          if (name == 'tap' && requestedTab is String) {
            currentTab = requestedTab;
            if (currentTab == 'transfer') {
              tokensOpen = false;
            }
          }
          if (name == 'key' && command['key'] == 'ctrl+k') {
            expect(command, <String, Object?>{'cmd': 'key', 'key': 'ctrl+k'});
            expect(paletteOpen, isFalse);
            paletteOpen = true;
          }
          if (name == 'key' && command['key'] == 'escape') {
            expect(command, <String, Object?>{'cmd': 'key', 'key': 'escape'});
            expect(paletteOpen, isTrue);
            final File retained = File.fromUri(repository.uri.resolve(
              '$readonlyHomeCatalogDirectory/05-home-goto-$mode.png',
            ));
            expect(retained.readAsBytesSync(), header);
            if (fault == 'goto-restore-negative') return negative;
            paletteOpen = false;
            paletteRestorations++;
          }
          if (name == 'type') {
            expect(command, <String, Object?>{
              'cmd': 'type', 'key': 'go_to_field', 'value': 'del',
            });
            expect(paletteOpen, isTrue);
          }
          if ((name == 'wait' || name == 'assert') &&
              command['key'] == 'go_to_palette') {
            expect(paletteOpen, command['gone'] != true);
          }
          if (name == 'tap' && command['key'] == 'home_tokens_toggle') {
            if (tokensOpen) {
              final File retained = File('${repository.path}/'
                '$readonlyHomeCatalogDirectory/02-home-open-$mode.png');
              expect(retained.readAsBytesSync(), header);
              if (fault == 'open-restore-negative') {
                return negative;
              }
              retainedOpenRestorations++;
            }
            tokensOpen = !tokensOpen;
          }
          if (name == 'wait' && command['key'] == 'home_tokens_body') {
            expect(tokensOpen, command['gone'] != true);
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
            if (name == 'key') 'handled': true,
            if (name == 'type') 'value': command['value'],
            if (name == 'state') ...<String, dynamic>{
              'walletUnlocked': true, 'walletInitCompleted': true,
              'tab': currentTab, 'tabs': <String>['dashboard', 'transfer'],
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
        () => captureReadonlyHomeGotoStates(
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
      if (fault == 'negative' || fault == 'hidden-negative' ||
          fault == 'open-negative' || fault == 'open-restore-negative' ||
          fault == 'goto-negative' || fault == 'goto-restore-negative') {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(commands.last['cmd'],
            fault == 'open-restore-negative' ? 'tap' :
            fault == 'goto-restore-negative' ? 'key' : 'shot');
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length,
            fault == 'negative' ? 1 : fault == 'hidden-negative' ? 5 :
            fault.startsWith('goto-') ? 7 : 3);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
        expect(restoredWindow, isFalse);
        expect(expanded, fault.startsWith('open-'));
      } else {
        final Map<String, Object> receipt = await capture();
        expect(receipt['scope'], 'readonly_native_home_catalog_capture');
        expect(receipt['capture_returned'], isTrue);
        expect(receipt['schema'], 4);
        expect(receipt['screens'],
            <String>['home-rest', 'home-open', 'home-hidden', 'home-goto']);
        expect(receipt['files'], <String>[
          '01-home-rest-dark.png', '01-home-rest-light.png',
          '02-home-open-dark.png', '02-home-open-light.png',
          '03-home-hidden-dark.png', '03-home-hidden-light.png',
          '05-home-goto-dark.png', '05-home-goto-light.png',
        ]);
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/01-home-rest-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/02-home-open-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        for (final String theme in <String>['dark', 'light']) {
          final File image = File('${repository.path}/'
            '$readonlyHomeCatalogDirectory/03-home-hidden-$theme.png');
          expect(image.readAsBytesSync(), header);
        }
        for (final String theme in <String>['dark', 'light']) {
          final File image = File.fromUri(repository.uri.resolve(
            '$readonlyHomeCatalogDirectory/05-home-goto-$theme.png',
          ));
          expect(image.readAsBytesSync(), header);
        }
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'shot').length, 8);
        expect(commands.where((Map<String, Object?> value) =>
            value['cmd'] == 'tap' && value['tab'] == 'dashboard').length, 8);
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
        if (fault != 'negative') ...expectedPointer,
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
        if (fault != 'negative') expectedTooltip,
      ]);
      expect(observedAtShot,
          List<bool>.generate(shots,
              (int index) => index >= 4 && index < 6));
      expect(tokensAtShot, List<bool>.generate(shots,
          (int index) => index >= 2 && index < 4));
      expect(tokensOpen, fault.startsWith('open-'));
      expect(retainedOpenRestorations,
          fault == 'negative' || fault.startsWith('open-') ? 0 : 2);
      expect(paletteAtShot,
          List<bool>.generate(shots, (int index) => index >= 6));
      expect(paletteOpen, fault.startsWith('goto-'));
      expect(paletteRestorations, fault == 'none' ? 2 : 0);
      final List<Map<String, Object?>> paletteKeys = commands.where(
        (Map<String, Object?> value) => value['cmd'] == 'key',
      ).toList();
      expect(paletteKeys, <Map<String, Object?>>[
        if (shots >= 7)
          <String, Object?>{'cmd': 'key', 'key': 'ctrl+k'},
        if (shots >= 7 && fault != 'goto-negative')
          <String, Object?>{'cmd': 'key', 'key': 'escape'},
        if (fault == 'none') ...<Map<String, Object?>>[
          <String, Object?>{'cmd': 'key', 'key': 'ctrl+k'},
          <String, Object?>{'cmd': 'key', 'key': 'escape'},
        ],
      ]);
      final List<Map<String, Object?>> queries = commands.where(
        (Map<String, Object?> value) => value['cmd'] == 'type',
      ).toList();
      final Map<String, Object?> query = <String, Object?>{
        'cmd': 'type', 'key': 'go_to_field', 'value': 'del',
      };
      expect(queries, <Map<String, Object?>>[
        if (shots >= 7) query,
        if (fault == 'none') query,
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
        'wait', 'assert', 'shot', 'hover', 'key', 'type',
      }.contains(value['cmd'])), isTrue);
    }
  });

  test('bound Settings captures return home after retained positive output',
      () async {
    const List<String> screens = <String>[
      'set-node', 'set-security', 'set-display', 'set-wallet',
      'set-apps', 'set-addresses', 'set-about',
    ];
    const List<String> keys = <String>[
      'settings_node', 'settings_security', 'settings_display',
      'settings_wallet', 'settings_apps', 'settings_addresses',
      'settings_about',
    ];
    final Map<String, String> scripts = <String, String>{
      for (final String screen in screens)
        screen: File('harness/screens/$screen.txt').readAsStringSync(),
    };
    final List<String> files = <String>[
      for (int i = 0; i < screens.length; i++)
        for (final String theme in <String>['dark', 'light'])
          '${i + 30}-${screens[i]}-$theme.png',
    ];
    // Header-only transport data is not an actual rendered image.
    final Uint8List header = Uint8List(33)
      ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
      ..setAll(12, ascii.encode('IHDR'));
    ByteData.sublistView(header)
      ..setUint32(8, 13)
      ..setUint32(16, 1280)
      ..setUint32(20, 780);
    for (final String fault in <String>[
      'unbound', 'none', 'first', 'shot', 'return', 'late', 'png',
    ]) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-settings-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      for (final MapEntry<String, String> script in scripts.entries) {
        File('${repository.path}/harness/screens/${script.key}.txt')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(script.value);
      }
      String tab = 'dashboard';
      String mode = 'light';
      String selected = '';
      bool expanded = true;
      bool restoredWindow = false;
      int shots = 0;
      int returned = 0;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final List<ScreenCaptureObservation> progress =
          <ScreenCaptureObservation>[];
      final Map<String, dynamic> negative = <String, dynamic>{
        'ok': false, 'error': 'Synthetic capture refusal',
      };
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
          commands.add(command);
          final Object? name = command['cmd'];
          final Object? targetKey = command['key'];
          final Object? targetTab = command['tab'];
          if (name == 'tap' && command['key'] == 'rail_toggle') {
            expect(tab, 'dashboard');
            expanded = !expanded;
          }
          if (name == 'tap' && targetKey != null &&
              command['key'] != 'rail_toggle') {
            expect(tab, 'settings');
            expect(keys, contains(command['key']));
            if (fault == 'first') return negative;
            selected = screens[keys.indexOf(targetKey as String)];
          }
          if (name == 'tap' && targetTab != null) {
            expect(<String>['dashboard', 'settings'], contains(command['tab']));
            if (command['tab'] == 'dashboard') {
              expect(shots, returned + 1);
              final File retained = File('${repository.path}/'
                '$readonlySettingsCatalogDirectory/${files[shots - 1]}');
              expect(retained.readAsBytesSync(), header);
              if (fault == 'return') return negative;
              returned++;
            }
            tab = targetTab as String;
          }
          if (name == 'shot') {
            expect(tab, 'settings');
            expect(selected, screens[shots ~/ 2]);
            if (fault == 'shot' || fault == 'late' && shots == 5) {
              return negative;
            }
            shots++;
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
              'tab': tab, 'tabs': <String>['dashboard', 'settings'],
              'locale': 'en', 'direction': 'ltr',
            },
            if (name == 'tree') 'nodes': <Object?>[
              <String, dynamic>{'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32]},
            ],
            if (name == 'theme') ...<String, dynamic>{
              'mode': mode, 'savedMode': 'ThemeMode.$mode', 'brightness': mode,
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
              'png': base64Encode(fault == 'png' ? Uint8List(33) : header),
            },
          };
        },
      );
      Future<Map<String, Object>> capture() =>
          IOOverrides.runZoned<Future<Map<String, Object>>>(
        () => captureReadonlySettingsDefaults(
          repository: repository, session: session, onStep: progress.add,
        ),
        stdout: () => output,
      );
      if (fault == 'unbound') {
        await expectLater(capture(),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands, isEmpty);
        expect(progress, isEmpty);
        expect(output.lines, isEmpty);
        continue;
      }
      await session.bindWallet();
      if (fault == 'none') {
        final Map<String, Object> receipt = await capture();
        expect(receipt, <String, Object>{
          'schema': 1, 'scope': 'readonly_native_settings_catalog_capture',
          'screens': screens, 'themes': <String>['dark', 'light'],
          'files': files, 'width': 1280, 'height': 780, 'scale': 1,
          'capture_returned': true,
        });
        expect(shots, 14);
        expect(returned, 14);
        expect(tab, 'dashboard');
        expect(expanded, isTrue);
        expect(mode, 'light');
        expect(restoredWindow, isTrue);
        expect(progress.last.step, ScreenCaptureStep.complete);
      } else {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(shots, fault == 'return' || fault == 'png' ? 1 :
            fault == 'late' ? 5 : 0);
        expect(returned, fault == 'late' ? 5 : 0);
        expect(restoredWindow, isFalse);
        final ScreenCaptureObservation last = progress.last;
        expect(last.step, switch (fault) {
          'first' => ScreenCaptureStep.scriptLine,
          'return' => ScreenCaptureStep.afterCaptureLine,
          'png' => ScreenCaptureStep.shotValidation,
          _ => ScreenCaptureStep.shotRequest,
        });
        expect(last.screen, fault == 'late' ? 'set-display' : 'set-node');
        expect(last.theme, fault == 'late' ? 'light' : 'dark');
        expect(readonlySettingsFailureDiagnostic(last), isNotNull);
        // Original binding stays recorded; the held lane refuses later input.
        expect(session.walletBound, isTrue);
        final int originalCalls = commands.length;
        await expectLater(session.send(
            <String, Object?>{'cmd': 'state'}, const Duration(seconds: 5)),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands.length, originalCalls);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
      }
      final Directory images = Directory(
        '${repository.path}/$readonlySettingsCatalogDirectory',
      );
      final int retained = fault == 'png' ? 0 : shots;
      expect(images.existsSync() ? images.listSync().length : 0, retained);
      for (int i = 0; i < retained; i++) {
        expect(File('${images.path}/${files[i]}').readAsBytesSync(), header);
      }
      final List<Map<String, Object?>> scrolls = commands.where(
        (Map<String, Object?> value) => value['cmd'] == 'scroll',
      ).toList();
      expect(scrolls, hasLength(switch (fault) {
        'first' => 0,
        'none' || 'late' => 4,
        'shot' || 'return' || 'png' => 2,
        _ => throw StateError('Unexpected bound capture fault'),
      }));
      expect(scrolls, equals(<Map<String, Object?>>[
        for (int pair = 0; pair < scrolls.length ~/ 2; pair++)
          ...<Map<String, Object?>>[
            <String, Object?>{'cmd': 'scroll', 'dy': -1000000},
            <String, Object?>{
              'cmd': 'scroll', 'key': 'node_settings_peers_toggle', 'dy': 300,
            },
          ],
      ]));
      expect(commands.every((Map<String, Object?> value) => <String>{
        'readonly-wallet-bind', 'state', 'tree', 'tap', 'theme', 'window',
        'wait', 'assert', 'shot', 'scroll',
      }.contains(value['cmd'])), isTrue);
      expect(output.lines.every((Object? line) => line is String &&
          line.startsWith('ok')), isTrue);
    }
  });

  test('bound Navigation captures return home after retained positive output',
      () async {
    const List<String> screens = <String>[
      'send-rest',
      'receive',
      'pillars',
      'plasma',
      'tokens',
      'swap-list',
      'az',
    ];
    const List<String> routes = <String>[
      'transfer',
      'transfer',
      'pillars',
      'plasma',
      'tokens',
      'p2pSwap',
      'accelerator',
    ];
    final Map<String, String> scripts = <String, String>{
      for (final String screen in screens)
        screen: File('harness/screens/$screen.txt').readAsStringSync(),
    };
    const List<String> files = <String>[
      '07-send-rest-dark.png',
      '07-send-rest-light.png',
      '09-receive-dark.png',
      '09-receive-light.png',
      '16-pillars-dark.png',
      '16-pillars-light.png',
      '21-plasma-dark.png',
      '21-plasma-light.png',
      '23-tokens-dark.png',
      '23-tokens-light.png',
      '26-swap-list-dark.png',
      '26-swap-list-light.png',
      '28-az-dark.png',
      '28-az-light.png',
    ];
    // Header-only transport data is not an actual rendered image.
    final Uint8List header = Uint8List(33)
      ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
      ..setAll(12, ascii.encode('IHDR'));
    ByteData.sublistView(header)
      ..setUint32(8, 13)
      ..setUint32(16, 1280)
      ..setUint32(20, 780);
    expect(readonlyNavigationFailureDiagnostic(
      const ScreenCaptureObservation(ScreenCaptureStep.scriptLine,
        screen: 'set-node', theme: 'dark', line: 5),
    ), isNull);
    for (final String fault in <String>[
      'unbound', 'none', 'first', 'shot', 'return', 'late', 'png',
    ]) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-navigation-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      for (final MapEntry<String, String> script in scripts.entries) {
        File('${repository.path}/harness/screens/${script.key}.txt')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(script.value);
      }
      String tab = 'dashboard';
      String mode = 'light';
      String selected = '';
      bool expanded = true;
      bool restoredWindow = false;
      int shots = 0;
      int returned = 0;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final List<ScreenCaptureObservation> progress =
          <ScreenCaptureObservation>[];
      final Map<String, dynamic> negative = <String, dynamic>{
        'ok': false, 'error': 'Synthetic capture refusal',
      };
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
          commands.add(command);
          final Object? name = command['cmd'];
          final Object? targetKey = command['key'];
          final Object? targetTab = command['tab'];
          if (name == 'tap' && command['key'] == 'rail_toggle') {
            expect(tab, 'dashboard');
            expanded = !expanded;
          }
          if (name == 'tap' && targetKey != null &&
              command['key'] != 'rail_toggle') {
            expect(tab, routes[shots ~/ 2]);
            if (fault == 'first') return negative;
          }
          if (name == 'tap' && targetTab != null) {
            expect(<String>['dashboard', ...routes], contains(command['tab']));
            if (targetTab != 'dashboard') {
              expect(targetTab, routes[shots ~/ 2]);
              selected = screens[shots ~/ 2];
            }
            if (command['tab'] == 'dashboard') {
              expect(shots, returned + 1);
              final File retained = File('${repository.path}/'
                '$readonlyNavigationCatalogDirectory/${files[shots - 1]}');
              expect(retained.readAsBytesSync(), header);
              if (fault == 'return') return negative;
              returned++;
            }
            tab = targetTab as String;
          }
          if (name == 'shot') {
            expect(tab, routes[shots ~/ 2]);
            expect(selected, screens[shots ~/ 2]);
            if (fault == 'shot' || fault == 'late' && shots == 5) {
              return negative;
            }
            shots++;
          }
          if (name == 'type') {
            expect(tab, 'pillars');
            expect(command['key'], 'pillars_search');
            expect(command['value'], 'dev1');
            expect(command['submit'], isNull);
          }
          if (name == 'key') expect(command['key'], 'escape');
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
              'tab': tab, 'tabs': <String>[
                'dashboard', 'transfer', 'pillars', 'plasma', 'tokens',
                'p2pSwap', 'accelerator',
              ],
              'locale': 'en', 'direction': 'ltr',
            },
            if (name == 'tree') 'nodes': <Object?>[
              <String, dynamic>{'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32]},
            ],
            if (name == 'theme') ...<String, dynamic>{
              'mode': mode, 'savedMode': 'ThemeMode.$mode', 'brightness': mode,
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
            if (name == 'type') 'value': command['value'],
            if (name == 'key') 'handled': true,
            if (name == 'shot') ...<String, dynamic>{
              'client': <int>[1280, 780], 'width': 1280, 'height': 780,
              'scale': 1, 'theme': mode, 'asserted': true,
              'png': base64Encode(fault == 'png' ? Uint8List(33) : header),
            },
          };
        },
      );
      Future<Map<String, Object>> capture() =>
          IOOverrides.runZoned<Future<Map<String, Object>>>(
        () => captureReadonlyNavigationDefaults(
          repository: repository, session: session, onStep: progress.add,
        ),
        stdout: () => output,
      );
      if (fault == 'unbound') {
        await expectLater(capture(),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands, isEmpty);
        expect(progress, isEmpty);
        expect(output.lines, isEmpty);
        continue;
      }
      await session.bindWallet();
      if (fault == 'none') {
        final Map<String, Object> receipt = await capture();
        expect(receipt, <String, Object>{
          'schema': 1, 'scope': 'readonly_native_navigation_catalog_capture',
          'screens': screens, 'themes': <String>['dark', 'light'],
          'files': files, 'width': 1280, 'height': 780, 'scale': 1,
          'capture_returned': true,
        });
        expect(shots, 14);
        expect(returned, 14);
        expect(tab, 'dashboard');
        expect(expanded, isTrue);
        expect(mode, 'light');
        expect(restoredWindow, isTrue);
        expect(progress.last.step, ScreenCaptureStep.complete);
      } else {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(shots, fault == 'return' || fault == 'png' ? 1 :
            fault == 'late' ? 5 : 0);
        expect(returned, fault == 'late' ? 5 : 0);
        expect(restoredWindow, isFalse);
        final ScreenCaptureObservation last = progress.last;
        expect(last.step, switch (fault) {
          'first' => ScreenCaptureStep.scriptLine,
          'return' => ScreenCaptureStep.afterCaptureLine,
          'png' => ScreenCaptureStep.shotValidation,
          _ => ScreenCaptureStep.shotRequest,
        });
        expect(last.screen, fault == 'late' ? 'pillars' : 'send-rest');
        expect(last.theme, fault == 'late' ? 'light' : 'dark');
        expect(readonlyNavigationFailureDiagnostic(last), isNotNull);
        // Original binding stays recorded; the held lane refuses later input.
        expect(session.walletBound, isTrue);
        final int originalCalls = commands.length;
        await expectLater(session.send(
            <String, Object?>{'cmd': 'state'}, const Duration(seconds: 5)),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands.length, originalCalls);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
      }
      final Directory images = Directory(
        '${repository.path}/$readonlyNavigationCatalogDirectory',
      );
      final int retained = fault == 'png' ? 0 : shots;
      expect(images.existsSync() ? images.listSync().length : 0, retained);
      for (int i = 0; i < retained; i++) {
        expect(File('${images.path}/${files[i]}').readAsBytesSync(), header);
      }
      expect(commands.every((Map<String, Object?> value) => <String>{
        'readonly-wallet-bind', 'state', 'tree', 'tap', 'theme', 'window',
        'wait', 'assert', 'shot', 'type', 'key',
      }.contains(value['cmd'])), isTrue);
      expect(output.lines.every((Object? line) => line is String &&
          line.startsWith('ok')), isTrue);
    }
  });

  test('bound Details captures return home after retained positive output',
      () async {
    const List<String> screens = <String>[
      'receive-qr',
      'zap-form',
      'plasma-fuse',
      'set-licences',
      'set-originals',
    ];
    const List<String> routes = <String>[
      'transfer',
      'transfer',
      'plasma',
      'settings',
      'settings',
    ];
    final Map<String, String> scripts = <String, String>{
      for (final String screen in screens)
        screen: File('harness/screens/$screen.txt').readAsStringSync(),
    };
    const List<String> files = <String>[
      '10-receive-qr-dark.png',
      '10-receive-qr-light.png',
      '11-zap-form-dark.png',
      '11-zap-form-light.png',
      '22-plasma-fuse-dark.png',
      '22-plasma-fuse-light.png',
      '37-set-licences-dark.png',
      '37-set-licences-light.png',
      '38-set-originals-dark.png',
      '38-set-originals-light.png',
    ];
    // Header-only transport data is not an actual rendered image.
    final Uint8List header = Uint8List(33)
      ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
      ..setAll(12, ascii.encode('IHDR'));
    ByteData.sublistView(header)
      ..setUint32(8, 13)
      ..setUint32(16, 1280)
      ..setUint32(20, 780);
    expect(readonlyDetailsFailureDiagnostic(
      const ScreenCaptureObservation(ScreenCaptureStep.scriptLine,
        screen: 'set-node', theme: 'dark', line: 5),
    ), isNull);
    for (final String fault in <String>[
      'unbound', 'none', 'first', 'shot', 'return', 'late', 'png', 'close',
    ]) {
      final _CatalogStdout output = _CatalogStdout();
      final Directory repository = Directory.systemTemp.createTempSync(
        'syrius-readonly-details-',
      );
      addTearDown(() => repository.deleteSync(recursive: true));
      for (final MapEntry<String, String> script in scripts.entries) {
        File('${repository.path}/harness/screens/${script.key}.txt')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(script.value);
      }
      String tab = 'dashboard';
      String mode = 'light';
      String selected = '';
      bool expanded = true;
      bool restoredWindow = false;
      int shots = 0;
      int returned = 0;
      int closedFuse = 0;
      bool afterShot = false;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final List<ScreenCaptureObservation> progress =
          <ScreenCaptureObservation>[];
      final Map<String, dynamic> negative = <String, dynamic>{
        'ok': false, 'error': 'Synthetic capture refusal',
      };
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
          commands.add(command);
          final Object? name = command['cmd'];
          final Object? targetKey = command['key'];
          final Object? targetTab = command['tab'];
          if (name == 'tap' && command['key'] == 'rail_toggle') {
            expect(tab, 'dashboard');
            expanded = !expanded;
          }
          if (name == 'tap' && targetKey != null &&
              command['key'] != 'rail_toggle') {
            expect(tab, routes[(afterShot ? shots - 1 : shots) ~/ 2]);
            if (fault == 'first') return negative;
          }
          if (name == 'tap' && targetTab != null) {
            expect(<String>['dashboard', ...routes], contains(command['tab']));
            if (targetTab != 'dashboard') {
              expect(targetTab, routes[shots ~/ 2]);
              selected = screens[shots ~/ 2];
            }
            if (command['tab'] == 'dashboard') {
              expect(shots, returned + 1);
              final File retained = File('${repository.path}/'
                '$readonlyDetailsCatalogDirectory/${files[shots - 1]}');
              expect(retained.readAsBytesSync(), header);
              if (fault == 'return') return negative;
              returned++;
              afterShot = false;
            }
            tab = targetTab as String;
          }
          if (name == 'shot') {
            expect(tab, routes[shots ~/ 2]);
            expect(selected, screens[shots ~/ 2]);
            if (fault == 'shot' || fault == 'late' && shots == 5) {
              return negative;
            }
            shots++;
            afterShot = true;
          }
          if (name == 'tap' && command['key'] == 'plasma_close_fuse' &&
              afterShot) {
            expect(tab, 'plasma');
            expect(shots, returned + 1);
            final File retained = File('${repository.path}/'
              '$readonlyDetailsCatalogDirectory/${files[shots - 1]}');
            expect(retained.readAsBytesSync(), header);
            if (fault == 'close') return negative;
            closedFuse++;
          }
          if (name == 'type') {
            final String expected = switch (tab) {
              'settings' => 'originals_discovery_field',
              'plasma' => 'fuse_plasma_amount_field',
              _ => 'receive_amount_field',
            };
            expect(command['key'], expected);
            expect(command['value'], tab == 'settings' ? '321' : '100');
            expect(command['submit'], isNull);
          }
          if (name == 'key') expect(command['key'], 'escape');
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
              'tab': tab, 'tabs': <String>[
                'dashboard', 'transfer', 'plasma', 'settings',
              ],
              'locale': 'en', 'direction': 'ltr',
            },
            if (name == 'tree') 'nodes': <Object?>[
              <String, dynamic>{'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32]},
              for (final String key in <String>[
                'about_licences_end', 'originals_discovery_field',
              ])
                <String, dynamic>{'key': key, 'kind': 'region',
                  'rect': <int>[220, 180, 120, 32]},
            ],
            if (name == 'theme') ...<String, dynamic>{
              'mode': mode, 'savedMode': 'ThemeMode.$mode', 'brightness': mode,
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
            if (name == 'type') 'value': command['value'],
            if (name == 'key') 'handled': true,
            if (name == 'shot') ...<String, dynamic>{
              'client': <int>[1280, 780], 'width': 1280, 'height': 780,
              'scale': 1, 'theme': mode, 'asserted': true,
              'png': base64Encode(fault == 'png' ? Uint8List(33) : header),
            },
          };
        },
      );
      Future<Map<String, Object>> capture() =>
          IOOverrides.runZoned<Future<Map<String, Object>>>(
        () => captureReadonlyDetailsDefaults(
          repository: repository, session: session, onStep: progress.add,
        ),
        stdout: () => output,
      );
      if (fault == 'unbound') {
        await expectLater(capture(),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands, isEmpty);
        expect(progress, isEmpty);
        expect(output.lines, isEmpty);
        continue;
      }
      await session.bindWallet();
      if (fault == 'none') {
        final Map<String, Object> receipt = await capture();
        expect(receipt, <String, Object>{
          'schema': 1, 'scope': 'readonly_native_details_catalog_capture',
          'screens': screens, 'themes': <String>['dark', 'light'],
          'files': files, 'width': 1280, 'height': 780, 'scale': 1,
          'capture_returned': true,
        });
        expect(shots, 10);
        expect(returned, 10);
        expect(closedFuse, 2);
        expect(tab, 'dashboard');
        expect(expanded, isTrue);
        expect(mode, 'light');
        expect(restoredWindow, isTrue);
        expect(progress.last.step, ScreenCaptureStep.complete);
      } else {
        await expectLater(capture(), throwsA(isA<ScreenCaptureError>()));
        expect(shots, fault == 'return' || fault == 'png' ? 1 :
            fault == 'late' || fault == 'close' ? 5 : 0);
        expect(returned, fault == 'late' ? 5 :
            fault == 'close' ? 4 : 0);
        expect(closedFuse, fault == 'late' ? 1 : 0);
        expect(restoredWindow, isFalse);
        final ScreenCaptureObservation last = progress.last;
        expect(last.step, switch (fault) {
          'first' => ScreenCaptureStep.scriptLine,
          'return' || 'close' => ScreenCaptureStep.afterCaptureLine,
          'png' => ScreenCaptureStep.shotValidation,
          _ => ScreenCaptureStep.shotRequest,
        });
        expect(last.screen, fault == 'late' || fault == 'close' ?
            'plasma-fuse' : 'receive-qr');
        expect(last.theme, fault == 'late' ? 'light' : 'dark');
        expect(readonlyDetailsFailureDiagnostic(last), isNotNull);
        // Original binding stays recorded; the held lane refuses later input.
        expect(session.walletBound, isTrue);
        final int originalCalls = commands.length;
        await expectLater(session.send(
            <String, Object?>{'cmd': 'state'}, const Duration(seconds: 5)),
            throwsA(isA<ReadonlyInspectionRefused>()));
        expect(commands.length, originalCalls);
        expect(negative, <String, dynamic>{
          'ok': false, 'error': 'Synthetic capture refusal',
        });
      }
      final Directory images = Directory(
        '${repository.path}/$readonlyDetailsCatalogDirectory',
      );
      final int retained = fault == 'png' ? 0 : shots;
      expect(images.existsSync() ? images.listSync().length : 0, retained);
      for (int i = 0; i < retained; i++) {
        expect(File('${images.path}/${files[i]}').readAsBytesSync(), header);
      }
      final List<Map<String, Object?>> scrolls = commands.where(
        (Map<String, Object?> value) => value['cmd'] == 'scroll',
      ).toList();
      expect(scrolls, equals(<Map<String, Object?>>[
        if (fault == 'none')
          for (int pair = 0; pair < 4; pair++)
            ...<Map<String, Object?>>[
              <String, Object?>{
                'cmd': 'scroll', 'key': 'about_licences_toggle', 'dy': 300,
              },
              <String, Object?>{'cmd': 'scroll', 'dy': 1000000},
            ],
      ]));
      expect(commands.every((Map<String, Object?> value) => <String>{
        'readonly-wallet-bind', 'state', 'tree', 'tap', 'theme', 'window',
        'wait', 'assert', 'shot', 'type', 'key', 'scroll',
      }.contains(value['cmd'])), isTrue);
      expect(output.lines.every((Object? line) => line is String &&
          line.startsWith('ok')), isTrue);
    }
  });

  test('Settings capture diagnostics retain only a closed step and context',
      () {
    expect(readonlySettingsFailureDiagnostic(null), isNull);
    expect(readonlySettingsFailureDiagnostic(const ScreenCaptureObservation(
      ScreenCaptureStep.preflight,
    )), <String, Object>{
      'schema': 1, 'kind': 'readonly_settings_capture_failure',
      'last_entered_step': 'preflight',
    });
    expect(readonlySettingsFailureDiagnostic(const ScreenCaptureObservation(
      ScreenCaptureStep.scriptLine, screen: 'set-node', theme: 'dark', line: 5,
    )), <String, Object>{
      'schema': 1, 'kind': 'readonly_settings_capture_failure',
      'last_entered_step': 'scriptLine', 'screen': 'set-node',
      'theme': 'dark', 'line': 5,
    });
    for (final ScreenCaptureObservation invalid in <ScreenCaptureObservation>[
      const ScreenCaptureObservation(ScreenCaptureStep.homePreparation,
        screen: 'Synthetic private path', theme: 'dark'),
      const ScreenCaptureObservation(ScreenCaptureStep.homePreparation,
        screen: 'set-node', theme: 'Synthetic private locale'),
      const ScreenCaptureObservation(ScreenCaptureStep.scriptLine,
        screen: 'set-node', theme: 'dark'),
      const ScreenCaptureObservation(ScreenCaptureStep.scriptLine,
        screen: 'set-node', theme: 'dark', line: 0),
      const ScreenCaptureObservation(ScreenCaptureStep.scriptLine,
        screen: 'set-node', theme: 'dark', line: 65536),
      const ScreenCaptureObservation(ScreenCaptureStep.preflight, line: 5),
    ]) {
      expect(readonlySettingsFailureDiagnostic(invalid), isNull);
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
