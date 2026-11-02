import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/build_output.dart';

class _Bytes implements StreamConsumer<List<int>> {
  final List<int> bytes = <int>[];
  void Function()? onClose;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async => onClose?.call();
}

class _BuildProcess implements Process {
  _BuildProcess() {
    input.onClose = () => exited.complete(0);
  }

  final _Bytes input = _Bytes();
  final Completer<int> exited = Completer<int>();
  final StreamController<List<int>> out = StreamController<List<int>>();
  final StreamController<List<int>> err = StreamController<List<int>>();

  @override
  late final IOSink stdin = IOSink(input);
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exited.future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      throw StateError('no native process');
}

void main() {
  test('closed build input and both output EOFs are required', () async {
    final _BuildProcess process = _BuildProcess();
    final _Bytes out = _Bytes();
    final _Bytes err = _Bytes();
    final IOSink output = IOSink(out);
    final IOSink errors = IOSink(err);
    bool complete = false;
    final Future<int> result = finishIsolatedBuild(
      process, output: output, errors: errors,
    ).then((int code) {
      complete = true;
      return code;
    });
    expect(await process.exitCode, 0);
    expect(complete, isFalse);
    process.out.add(<int>[1, 2]);
    process.err.add(<int>[3]);
    await process.out.close();
    expect(complete, isFalse);
    await process.err.close();
    expect(await result, 0);
    await Future.wait<void>(<Future<void>>[output.flush(), errors.flush()]);
    expect(out.bytes, <int>[1, 2]);
    expect(err.bytes, <int>[3]);
    expect(process.input.bytes, isEmpty);
    await Future.wait<void>(<Future<void>>[output.close(), errors.close()]);
  });

  test('an output failure cannot be healed by a zero exit', () async {
    final _BuildProcess process = _BuildProcess();
    final IOSink output = IOSink(_Bytes());
    final IOSink errors = IOSink(_Bytes());
    final Future<void> checked = expectLater(
      finishIsolatedBuild(process, output: output, errors: errors),
      throwsA(isA<StateError>()),
    );
    process.out.addError(StateError('synthetic output failure'));
    await Future.wait<void>(<Future<void>>[
      process.out.close(), process.err.close(),
    ]);
    await checked;
    expect(await process.exitCode, 0);
    await Future.wait<void>(<Future<void>>[output.close(), errors.close()]);
  });
}
