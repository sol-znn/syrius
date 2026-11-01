import 'dart:io';

import 'harness.dart' as cli;
import 'readonly_inspection_session.dart';
import 'screen_capture.dart';

/// Literal Settings defaults, separate from the Home and generic captures.
const String readonlySettingsCatalogDirectory = '.harness/ci-settings-catalog';

class _SettingsInstance extends cli.Instance {
  _SettingsInstance(this._session) : super('readonly-settings-catalog');

  final ReadonlyInspectionSession _session;

  @override
  Map<String, dynamic> read() =>
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.process);

  @override
  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 30),
  }) => _session.send(command, timeout > const Duration(seconds: 30)
      ? const Duration(seconds: 30) : timeout);
}

/// Runs seven original navigation scripts through the same bound UI owner.
/// Each positive shot returns to Home before the next preparation can run.
Future<Map<String, Object>> captureReadonlySettingsDefaults({
  required Directory repository,
  required ReadonlyInspectionSession session,
}) async {
  if (!session.walletBound) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.binding);
  }
  final _SettingsInstance instance = _SettingsInstance(session);
  final ScreenCapture capture = ScreenCapture(
    repository: repository,
    call: (Map<String, Object?> command) => cli.call(instance, command),
    prepareHome: session.prepareScreenHome,
    runLine: (List<String> words) => cli.run(
      instance, words.first, cli.Args(words.sublist(1)),
    ),
    assertionFor: (List<String> words) =>
        cli.assertionArgs(cli.Args(words.sublist(1))),
    readRailState: session.railExpanded,
    restoreRailState: session.restoreScreenRail,
  );
  const List<String> screens = <String>[
    'set-node', 'set-security', 'set-display', 'set-wallet',
    'set-apps', 'set-addresses', 'set-about',
  ];
  const List<String> files = <String>[
    '30-set-node-dark.png', '30-set-node-light.png',
    '31-set-security-dark.png', '31-set-security-light.png',
    '32-set-display-dark.png', '32-set-display-light.png',
    '33-set-wallet-dark.png', '33-set-wallet-light.png',
    '34-set-apps-dark.png', '34-set-apps-light.png',
    '35-set-addresses-dark.png', '35-set-addresses-light.png',
    '36-set-about-dark.png', '36-set-about-light.png',
  ];
  final List<String> captured = await capture.captureSelection(
    screens, directory: readonlySettingsCatalogDirectory,
  );
  if (captured.length != files.length) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
  }
  for (int index = 0; index < files.length; index++) {
    final String expected =
        '$readonlySettingsCatalogDirectory/${files[index]}';
    if (captured[index] != expected) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
    }
  }
  return <String, Object>{
    'schema': 1, 'scope': 'readonly_native_settings_catalog_capture',
    'screens': screens, 'themes': const <String>['dark', 'light'],
    'files': files, 'width': 1280, 'height': 780, 'scale': 1,
    'capture_returned': true,
  };
}
