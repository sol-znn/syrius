import 'dart:io';

import 'harness.dart' as cli;
import 'readonly_inspection_session.dart';
import 'screen_capture.dart';

/// Literal details defaults, separate from Home, Settings and generic
/// captures.
const String readonlyDetailsCatalogDirectory = '.harness/ci-details-catalog';

class _DetailsInstance extends cli.Instance {
  _DetailsInstance(this._session) : super('readonly-details-catalog');

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

/// Exports only a fixed catalog step. It does not reconstruct a missing cause.
Map<String, Object>? readonlyDetailsFailureDiagnostic(
  ScreenCaptureObservation? observation,
) {
  if (observation == null) return null;
  final String? screen = observation.screen;
  final String? theme = observation.theme;
  final int? line = observation.line;
  const Set<String> screens = <String>{
    'receive-qr',
    'zap-form',
    'plasma-fuse',
    'set-licences',
    'set-originals',
  };
  final bool script = observation.step == ScreenCaptureStep.scriptLine ||
      observation.step == ScreenCaptureStep.afterCaptureLine;
  if ((screen == null) != (theme == null) ||
      screen != null && !screens.contains(screen) ||
      theme != null && theme != 'dark' && theme != 'light' ||
      script && (screen == null || line == null) ||
      line != null && (!script || line < 1 || line > 65535)) {
    return null;
  }
  return <String, Object>{
    'schema': 1, 'kind': 'readonly_details_capture_failure',
    'last_entered_step': observation.step.name,
    'screen': ?screen, 'theme': ?theme, 'line': ?line,
  };
}

/// Runs five original details scripts through the same bound UI owner.
/// Each positive shot returns to Home before the next preparation can run.
Future<Map<String, Object>> captureReadonlyDetailsDefaults({
  required Directory repository,
  required ReadonlyInspectionSession session,
  void Function(ScreenCaptureObservation step)? onStep,
}) async {
  if (!session.walletBound) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.binding);
  }
  final _DetailsInstance instance = _DetailsInstance(session);
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
    onStep: onStep,
  );
  const List<String> screens = <String>[
    'receive-qr',
    'zap-form',
    'plasma-fuse',
    'set-licences',
    'set-originals',
  ];
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
  final List<String> captured = await capture.captureSelection(
    screens, directory: readonlyDetailsCatalogDirectory,
  );
  if (captured.length != files.length) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
  }
  for (int index = 0; index < files.length; index++) {
    final String expected =
        '$readonlyDetailsCatalogDirectory/${files[index]}';
    if (captured[index] != expected) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
    }
  }
  return <String, Object>{
    'schema': 1, 'scope': 'readonly_native_details_catalog_capture',
    'screens': screens, 'themes': const <String>['dark', 'light'],
    'files': files, 'width': 1280, 'height': 780, 'scale': 1,
    'capture_returned': true,
  };
}
