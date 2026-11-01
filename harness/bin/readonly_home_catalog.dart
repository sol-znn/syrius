import 'dart:io';

import 'harness.dart' as cli;
import 'readonly_inspection_session.dart';
import 'screen_capture.dart';

/// A distinct output family, separate from the generic page tour.
const String readonlyHomeCatalogDirectory = '.harness/ci-home-catalog';

const List<String> _files = <String>[
  '01-home-rest-dark.png', '01-home-rest-light.png',
];

class _CatalogInstance extends cli.Instance {
  _CatalogInstance(this._session) : super('readonly-home-catalog');

  final ReadonlyInspectionSession _session;

  // Every request retains the original session; no alternate receipt opens.
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

/// Executes the real catalog script through the original bound UI session.
/// Completion retains the runner's original rail/theme/window restoration.
Future<Map<String, Object>> captureReadonlyHomeRest({
  required Directory repository,
  required ReadonlyInspectionSession session,
}) async {
  if (!session.walletBound) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.binding);
  }
  final ScreenCapture capture = _homeCapture(
    repository: repository, session: session,
  );
  final List<String> captured = await capture.capture(
    'home-rest', directory: readonlyHomeCatalogDirectory,
  );
  if (captured.length != 2 ||
      captured[0] != '$readonlyHomeCatalogDirectory/${_files[0]}' ||
      captured[1] != '$readonlyHomeCatalogDirectory/${_files[1]}') {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
  }
  return <String, Object>{
    'schema': 1, 'scope': 'readonly_native_home_catalog_capture',
    'screen': 'home-rest', 'number': 1,
    'themes': const <String>['dark', 'light'], 'files': _files,
    'width': 1280, 'height': 780, 'scale': 1, 'capture_returned': true,
  };
}

// Both entry points keep the same bound transport and original UI helpers.
ScreenCapture _homeCapture({
  required Directory repository,
  required ReadonlyInspectionSession session,
}) {
  final _CatalogInstance instance = _CatalogInstance(session);
  return ScreenCapture(
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
}

/// Captures the two authored Home states in one fresh output directory.
/// Hidden balances are restored only after each durably retained positive shot.
Future<Map<String, Object>> captureReadonlyHomeStates({
  required Directory repository,
  required ReadonlyInspectionSession session,
}) async {
  if (!session.walletBound) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.binding);
  }
  final ScreenCapture capture = _homeCapture(
    repository: repository, session: session,
  );
  const List<String> files = <String>[
    '01-home-rest-dark.png', '01-home-rest-light.png',
    '03-home-hidden-dark.png', '03-home-hidden-light.png',
  ];
  final List<String> captured = await capture.captureSelection(
    const <String>['home-rest', 'home-hidden'],
    directory: readonlyHomeCatalogDirectory,
  );
  if (captured.length != files.length) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
  }
  for (int index = 0; index < files.length; index++) {
    if (captured[index] != '$readonlyHomeCatalogDirectory/${files[index]}') {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
    }
  }
  return <String, Object>{
    'schema': 2, 'scope': 'readonly_native_home_catalog_capture',
    'screens': const <String>['home-rest', 'home-hidden'],
    'themes': const <String>['dark', 'light'], 'files': files,
    'width': 1280, 'height': 780, 'scale': 1, 'capture_returned': true,
  };
}
