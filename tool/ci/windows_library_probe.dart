// Mapping can run DLL initialization. This child qualifies only mapping and
// symbol lookup. It never converts or invokes an export or loads wallet code.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

const Map<String, String> _libraries = <String, String>{
  'source': 'lib/embedded_node/blobs/libznn.dll',
  'debug': 'build/windows/x64/runner/Debug/libznn.dll',
  'release': 'build/windows/x64/runner/Release/libznn.dll',
};

void main(List<String> arguments) {
  bool mapped = false;
  bool runNodeLookup = false;
  bool stopNodeLookup = false;
  try {
    final Map<String, String> environment = Platform.environment;
    final String root = Directory.current.absolute.path;
    final String separator = Platform.pathSeparator;
    final String? profile = environment['SYRIUS_WINDOWS_BASELINE_PROFILE'];
    final String profilePrefix =
        '$root$separator.harness${separator}ci-windows-baseline-';
    if (!Platform.isWindows ||
        environment['GITHUB_ACTIONS'] != 'true' ||
        environment['RUNNER_OS'] != 'Windows' ||
        environment['RUNNER_ENVIRONMENT'] != 'github-hosted' ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(
          environment['GITHUB_SHA'] ?? '',
        ) ||
        environment['GITHUB_WORKSPACE'] != root ||
        arguments.length != 2 ||
        arguments.first != '--variant' ||
        !_libraries.containsKey(arguments.last) ||
        profile == null ||
        !profile.startsWith(profilePrefix) ||
        !RegExp(r'^[0-9a-f]{24}$').hasMatch(
          profile.substring(profilePrefix.length),
        ) ||
        environment['HOME'] != profile ||
        environment['USERPROFILE'] != profile ||
        environment['APPDATA'] !=
            '$profile${separator}AppData${separator}Roaming' ||
        environment['LOCALAPPDATA'] !=
            '$profile${separator}AppData${separator}Local' ||
        environment['TEMP'] != '$profile${separator}Temp' ||
        environment['TMP'] != '$profile${separator}Temp') {
      throw const FormatException('Probe admission refused');
    }
    final String relative = _libraries[arguments.last]!.replaceAll(
      '/',
      separator,
    );
    final File selected = File('$root$separator$relative');
    if (FileSystemEntity.typeSync(selected.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Library refused');
    }
    final DynamicLibrary library = DynamicLibrary.open(selected.path);
    mapped = true;
    final Pointer<Void> runNode = library.lookup<Void>('RunNode');
    runNodeLookup = runNode != nullptr;
    final Pointer<Void> stopNode = library.lookup<Void>('StopNode');
    stopNodeLookup = stopNode != nullptr;
    // A Go runtime must remain mapped until this original child exits.
  } on Object {
    exitCode = 1;
  }
  if (!mapped || !runNodeLookup || !stopNodeLookup) {
    exitCode = 1;
  }
  stdout.writeln(
    jsonEncode(<String, Object>{
      'schema': 1,
      'mapped': mapped,
      'run_node_lookup': runNodeLookup,
      'stop_node_lookup': stopNodeLookup,
      'exports_invoked': false,
    }),
  );
}
