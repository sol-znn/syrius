import 'dart:io';

import 'harness.dart' as cli;
import 'readonly_inspection_session.dart';
import 'screen_capture.dart';

/// Literal navigation defaults, separate from Home, Settings and generic captures.
const String readonlyNavigationCatalogDirectory = '.harness/ci-navigation-catalog';

class _NavigationInstance extends cli.Instance {
  _NavigationInstance(this._session) : super('readonly-navigation-catalog');

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
Map<String, Object>? readonlyNavigationFailureDiagnostic(
  ScreenCaptureObservation? observation,
) {
  if (observation == null) return null;
  final String? screen = observation.screen;
  final String? theme = observation.theme;
  final int? line = observation.line;
  const Set<String> screens = <String>{
    'send-rest',
    'receive',
    'pillars',
    'plasma',
    'tokens',
    'swap-list',
    'az',
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
    'schema': 1, 'kind': 'readonly_navigation_capture_failure',
    'last_entered_step': observation.step.name,
    'screen': ?screen, 'theme': ?theme, 'line': ?line,
  };
}

/// Runs seven original navigation scripts through the same bound UI owner.
/// Each positive shot returns to Home before the next preparation can run.
Future<Map<String, Object>> captureReadonlyNavigationDefaults({
  required Directory repository,
  required ReadonlyInspectionSession session,
  void Function(ScreenCaptureObservation step)? onStep,
}) async {
  if (!session.walletBound) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.binding);
  }
  final _NavigationInstance instance = _NavigationInstance(session);
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
    'send-rest',
    'receive',
    'pillars',
    'plasma',
    'tokens',
    'swap-list',
    'az',
  ];
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
  final List<String> captured = await capture.captureSelection(
    screens, directory: readonlyNavigationCatalogDirectory,
  );
  if (captured.length != files.length) {
    throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
  }
  for (int index = 0; index < files.length; index++) {
    final String expected =
        '$readonlyNavigationCatalogDirectory/${files[index]}';
    if (captured[index] != expected) {
      throw const ReadonlyInspectionRefused(ReadonlyInspectionReason.reply);
    }
  }
  return <String, Object>{
    'schema': 1, 'scope': 'readonly_native_navigation_catalog_capture',
    'screens': screens, 'themes': const <String>['dark', 'light'],
    'files': files, 'width': 1280, 'height': 780, 'scale': 1,
    'capture_returned': true,
  };
}
