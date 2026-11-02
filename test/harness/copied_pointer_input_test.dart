import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/ci_copied_wallet_pointer.dart';
import '../../harness/bin/copied_wallet_pointer.dart';

void main() {
  test('pointer markers retain the fixed phase and binding step', () {
    for (final CopiedPointerPhase phase in CopiedPointerPhase.values) {
      expect(copiedPointerFailureMarker(
        'binding', CopiedWalletPointerRefused(phase)),
        'CI_POINTER_ERROR:binding:${phase.name}');
    }
  });

  test('pointer markers omit private errors and phase values', () {
    expect(copiedPointerFailureMarker(
      'private-phase', StateError('synthetic private path and password')),
      'CI_POINTER_ERROR:unknown:unknown');
  });

  test('private input preserves fragmented records and their exact order',
      () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    try {
      final Future<String> first = input.read();
      source
        ..add(utf8.encode('STA'))
        ..add(utf8.encode('RT\n'));
      expect(await first, 'START');
      source.add(utf8.encode('APPROVE\nFINISH\n'));
      expect(await input.read(), 'APPROVE');
      expect(await input.read(), 'FINISH');
      expect(input.alive, isTrue);
    } finally {
      await input.close();
      await source.close();
    }
  });

  test('parent EOF is observed while no record read is pending', () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    source.add(utf8.encode('START\n'));
    expect(await input.read(), 'START');
    await source.close();
    expect(input.alive, isFalse);
    await expectLater(input.read(), throwsFormatException);
    await input.close();
  });

  test('EOF cannot turn a queued approval into continued write authority',
      () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    source.add(utf8.encode('APPROVE\n'));
    await source.close();
    expect(input.alive, isFalse);
    await expectLater(input.read(), throwsFormatException);
    await input.close();
  });

  test('parent errors retire input even during an unrelated pending operation',
      () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    source.addError(StateError('synthetic parent failure'));
    await Future<void>.delayed(Duration.zero);
    expect(input.alive, isFalse);
    await expectLater(input.read(), throwsFormatException);
    await input.close();
    await source.close();
  });

  test('a partial record followed by EOF never becomes a command', () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    final Future<void> refused = expectLater(
      input.read(), throwsFormatException,
    );
    source.add(utf8.encode('APPRO'));
    await source.close();
    await refused;
    await input.close();
  });

  test('oversized unterminated private input retires the listener', () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    final Future<void> refused = expectLater(
      input.read(), throwsFormatException,
    );
    source.add(List<int>.filled(32769, 65));
    await refused;
    expect(input.alive, isFalse);
    await input.close();
    await source.close();
  });

  test('invalid UTF-8 cannot supply a private record', () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    final Future<void> refused = expectLater(
      input.read(), throwsFormatException,
    );
    source.add(<int>[0xff, 10]);
    await refused;
    await input.close();
    await source.close();
  });

  test('excess queued commands retire input instead of dropping a command',
      () async {
    final StreamController<List<int>> source = StreamController<List<int>>();
    final CopiedPointerInput input = CopiedPointerInput(source.stream);
    source.add(utf8.encode('START\nAPPROVE\nFINISH\n'));
    await Future<void>.delayed(Duration.zero);
    expect(input.alive, isFalse);
    await expectLater(input.read(), throwsFormatException);
    await input.close();
    await source.close();
  });
}
