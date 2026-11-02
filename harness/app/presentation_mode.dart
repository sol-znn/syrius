import 'readonly_native_mode.dart';

/// Selects a separate read-only host before any production wallet startup.
const String harnessPresentationEnvironment = 'SYRIUS_HARNESS_PRESENTATION';

/// These are component previews, separate from the numbered wallet captures.
const Set<String> harnessPresentationSurfaces = <String>{
  'welcome',
  'import',
  'seed-quiz',
  'lock-screen',
  'lock-wrong',
  'wallet-picker',
};

/// Refuses unknown input before a process or production owner is started.
String? harnessPresentationSurface(String? value) {
  if (value != null && !harnessPresentationSurfaces.contains(value)) {
    throw ArgumentError('Unsupported presentation surface');
  }
  return value;
}

/// Presentation cannot drive input, use wallet services or create shot proof.
bool harnessPresentationAllows(String command) => const <String>{
  'ping',
  'state',
  'presentation',
  'theme',
  'window',
  'tree',
  'assert',
  'wait',
  'logs',
  'stalls',
  'quit',
}.contains(command);

/// A live process is reused only for the exact requested kind of host.
bool harnessLaunchMatches(
  Map<String, dynamic> observed, {
  String? presentation,
  int? expectedPid,
  bool readonlyNative = false,
}) {
  if (readonlyNative) {
    return presentation == null &&
        harnessReadonlyNativeLaunchMatches(observed, expectedPid);
  }
  return (expectedPid == null || observed['pid'] == expectedPid) &&
      (presentation == null
          ? observed['harnessMode'] == 'wallet'
          : observed['harnessMode'] == 'presentation' &&
                observed['presentationScreen'] == presentation);
}

/// Replaces inherited profile and host controls without changing the parent.
Map<String, String> harnessLaunchEnvironment(
  Map<String, String> parent, {
  required String profileHome,
  required String appData,
  required String localAppData,
  required String temporary,
  required int port,
  required String token,
  String? presentation,
  bool readonlyNative = false,
  bool windows = false,
}) {
  final String? surface = harnessPresentationSurface(presentation);
  if (readonlyNative) {
    harnessReadonlyNativeRequested(
      <String, String>{...parent, harnessReadonlyNativeEnvironment: 'true'},
      windows: windows,
      presentation: surface,
    );
  }
  const Set<String> replaced = <String>{
    'APPDATA',
    'LOCALAPPDATA',
    'TEMP',
    'TMP',
    'HOME',
    'USERPROFILE',
    'SYRIUS_HARNESS_HOME',
    'SYRIUS_HARNESS_PORT',
    'SYRIUS_HARNESS_TOKEN',
    harnessPresentationEnvironment,
    harnessReadonlyNativeEnvironment,
  };
  return <String, String>{
    for (final MapEntry<String, String> entry in parent.entries)
      if (!replaced.contains(entry.key.toUpperCase())) entry.key: entry.value,
    'APPDATA': appData,
    'LOCALAPPDATA': localAppData,
    'TEMP': temporary,
    'TMP': temporary,
    'HOME': profileHome,
    'USERPROFILE': profileHome,
    'SYRIUS_HARNESS_HOME': profileHome,
    'SYRIUS_HARNESS_PORT': '$port',
    'SYRIUS_HARNESS_TOKEN': token,
    harnessPresentationEnvironment: ?surface,
    if (readonlyNative) harnessReadonlyNativeEnvironment: 'true',
  };
}
