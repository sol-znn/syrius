import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/harness.dart' as cli;
import '../../harness/bin/readonly_inspection_session.dart';
import '../../harness/bin/readonly_viewport_probe.dart';

Map<String, dynamic> _reply() => <String, dynamic>{
  'ok': true, 'pid': 44, 'booted': true,
  'harnessMode': 'readonly-native', 'readOnly': true,
  'readonlyAdmission': <String, dynamic>{
    'schema': 1, 'scope': 'readonly_native_sdk_admission', 'status': 'CURRENT',
    'publicationAdmissionPaused': true, 'automaticReceiveDisabled': true,
  },
  'readonlyWallet': <String, dynamic>{
    'schema': 1, 'scope': 'readonly_native_wallet_admission',
    'status': 'CURRENT', 'chain': 321, 'selectedIndex': 1,
    'nativeFrameObserved': true,
  },
};

void main() {
  test('viewport shots stay bound, restore and stop on an original refusal',
      () async {
    for (final String fault in <String>[
      'unbound', 'none', 'fresh-path', 'negative-shot', 'negative-locale',
      'wrong-client', 'wrong-pixels',
    ]) {
      final Directory root = Directory.systemTemp.createTempSync(
        'syrius-viewport-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory output = Directory(
        '${root.path}/.harness/ci-viewport-observations',
      );
      if (fault == 'fresh-path') output.createSync(recursive: true);
      String tab = 'dashboard';
      String locale = 'en';
      String direction = 'ltr';
      String theme = 'light';
      bool expanded = true;
      int width = 1280;
      int height = 780;
      final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
      final List<List<Object>> shots = <List<Object>>[];
      final Map<String, dynamic> negative = <String, dynamic>{
        'ok': false, 'error': 'Synthetic viewport refusal',
      };
      final ReadonlyInspectionSession session = ReadonlyInspectionSession(
        processId: 44,
        original: (Map<String, Object?> command, Duration timeout) async {
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 30)));
          commands.add(command);
          final Object? name = command['cmd'];
          if ((name == 'shot' && fault == 'negative-shot') ||
              (name == 'tap' && command['text'] != null &&
                  fault == 'negative-locale')) return negative;
          if (name == 'tap') {
            if (command['tab'] case final String value) tab = value;
            if (command['key'] == 'rail_toggle') expanded = !expanded;
            if (command['text'] case final String value) {
              locale = value == 'English' ? 'en' : 'ar';
              direction = locale == 'en' ? 'ltr' : 'rtl';
            }
          }
          if (name == 'theme') {
            if (command['mode'] case final String value) theme = value;
            if (command['restore'] case final Map<String, dynamic> value) {
              theme = value['mode'] as String;
            }
          }
          if (name == 'window') {
            if (command['width'] case final int value) width = value;
            if (command['height'] case final int value) height = value;
            if (command['restoreState'] != null) {
              width = 1280;
              height = 780;
            }
          }
          Uint8List? pixels;
          if (name == 'shot') {
            shots.add(<Object>[width, height, locale, direction, theme]);
            // Header-only transport data is not an actual rendered image.
            pixels = Uint8List(33)
              ..setAll(0, <int>[137, 80, 78, 71, 13, 10, 26, 10])
              ..setAll(12, ascii.encode('IHDR'));
            ByteData.sublistView(pixels)
              ..setUint32(8, 13)
              ..setUint32(16, fault == 'wrong-pixels' ? width + 1 : width)
              ..setUint32(20, height);
          }
          return <String, dynamic>{
            ..._reply(),
            if (name == 'state') ...<String, dynamic>{
              'walletUnlocked': true, 'walletInitCompleted': true,
              'tab': tab, 'tabs': <String>['dashboard', 'settings'],
              'locale': locale, 'direction': direction,
            },
            if (name == 'tree') 'nodes': <Object?>[
              <String, dynamic>{'key': 'rail_toggle', 'kind': 'button',
                'rect': <int>[8, 36, if (expanded) 184 else 40, 32]},
            ],
            if (name == 'theme') ...<String, dynamic>{
              'mode': theme, 'savedMode': 'ThemeMode.$theme',
              'brightness': theme,
            },
            if (name == 'window') ...<String, dynamic>{
              'window': <int>[80, 90, width, height],
              'client': <int>[width, height], 'clientMatched': true,
              'minimized': false, 'maximized': false,
              if (command['restoreState'] != null) 'restored': true,
            },
            if (name == 'shot') ...<String, dynamic>{
              'width': width, 'height': height, 'theme': theme,
              'client': <int>[
                if (fault == 'wrong-client') width + 1 else width, height,
              ],
              'scale': 1, 'asserted': true, 'png': base64Encode(pixels!),
            },
          };
        },
      );
      if (fault != 'unbound') await session.bindWallet();
      Future<Map<String, Object>> capture() => captureReadonlyViewportProbe(
        repository: root, session: session,
      );
      if (fault == 'none') {
        final Map<String, Object> receipt = await capture();
        expect(receipt['scope'], 'readonly_native_viewport_observation');
        expect(receipt['rendered_locale_restored'], isTrue);
        expect(receipt['theme_window_and_rail_restored'], isTrue);
        expect(receipt['locale_preference_restoration_qualified'], isFalse);
        expect(receipt['atomic_frame_qualified'], isFalse);
        expect(receipt['visual_matches'], 0);
        expect(shots, <List<Object>>[
          <Object>[1200, 600, 'en', 'ltr', 'dark'],
          <Object>[1200, 600, 'en', 'ltr', 'light'],
          <Object>[1280, 780, 'ar', 'rtl', 'dark'],
          <Object>[1280, 780, 'ar', 'rtl', 'light'],
        ]);
        expect(<Object>[tab, locale, direction, theme, expanded, width, height],
            <Object>['dashboard', 'en', 'ltr', 'light', true, 1280, 780]);
        expect(output.listSync().length, 4);
        final List<Map<String, Object>> captures =
            receipt['captures']! as List<Map<String, Object>>;
        expect(captures.length, 4);
        for (final Map<String, Object> value in captures) {
          final File file = File('${output.path}/${value['file']}');
          expect(file.lengthSync(), 33);
          final ByteData header = ByteData.sublistView(file.readAsBytesSync());
          expect(header.getUint32(16), value['width']);
          expect(header.getUint32(20), value['height']);
        }
      } else {
        await expectLater(capture(), throwsA(fault.startsWith('negative-')
            ? isA<cli.Fail>() : isA<ReadonlyInspectionRefused>()));
        if (fault == 'unbound') expect(commands, isEmpty);
        if (fault == 'fresh-path') expect(commands.length, 1);
        if (fault.startsWith('negative-')) {
          final int count = commands.length;
          await expectLater(session.send(<String, Object?>{'cmd': 'state'},
              const Duration(seconds: 30)),
              throwsA(isA<ReadonlyInspectionRefused>()));
          expect(commands.length, count);
          expect(negative, <String, dynamic>{
            'ok': false, 'error': 'Synthetic viewport refusal',
          });
        }
      }
      expect(commands.every((Map<String, Object?> value) => <String>{
        'readonly-wallet-bind', 'state', 'tree', 'tap', 'theme', 'window',
        'wait', 'shot',
      }.contains(value['cmd'])), isTrue);
    }
  });
}
