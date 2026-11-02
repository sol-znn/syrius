import 'dart:async';
import 'dart:io';

/// Build tools get EOF, while the caller keeps its private control input open.
Future<int> finishIsolatedBuild(
  Process process, {
  IOSink? output,
  IOSink? errors,
}) async {
  final Future<int> code = process.exitCode;
  await Future.wait<void>(<Future<void>>[
    process.stdin.close(),
    (output ?? stdout).addStream(process.stdout),
    (errors ?? stderr).addStream(process.stderr),
    code.then<void>((int _) {}),
  ]);
  return code;
}
