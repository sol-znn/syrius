import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';

import 'support.dart';

Future<void> _flush() async {
  for (int turn = 0; turn < 12; turn++) {
    await Future<void>.value();
  }
}

void main() {
  test(
    'queued generation retains its owner before another write settles',
    () async {
      final AddressesFixture source = AddressesFixture()..delayLabels = true;
      addTearDown(() {
        for (final (String, String, Completer<void>) write
            in source.labelWrites) {
          if (!write.$3.isCompleted) write.$3.complete();
        }
      });
      Object owner = Object();
      int captures = 0;
      int acquisitions = 0;
      source.generationCapture = (bool Function() current) {
        captures++;
        final Object original = owner;
        return AddressGenerationBinding(
          identity: Object(),
          members: source.members,
          owns: () => current() && identical(owner, original),
          acquire: () async {
            acquisitions++;
            return original;
          },
          release: () async {},
          derive: (Object wallet, int index) async => fixtureAddress(3),
          defaultLabel: (int number) => 'Address $number',
          writeLabel: (String address, String label) async {},
          writeMember: (String address) async => 2,
          publish: (String address, String label) => true,
        );
      };
      final AddressesSettingsBinding binding = source.bind();
      final Future<AddressesWriteOutcome> label = binding.rename(
        source.members.first,
        'Savings',
        isCurrent: () => true,
      );
      await _flush();
      final Future<AddressesWriteOutcome> generation = binding.generate(
        isCurrent: () => true,
      );
      expect(captures, 1);
      expect(binding.generate(isCurrent: () => true), same(generation));
      expect(captures, 1);
      owner = Object();
      source.labelWrites.single.$3.complete();
      expect((await label).committed, isTrue);
      final AddressesWriteOutcome result = await generation;
      expect(result.committed, isFalse);
      expect(result.error, isA<AddressGenerationRefused>());
      expect(acquisitions, 0);
      expect(source.members, hasLength(2));
    },
  );

  test(
    'a capture failure retains the original error and shared attempt',
    () async {
      final AddressesFixture source = AddressesFixture();
      final StateError failure = StateError('Synthetic capture failure');
      final StackTrace trace = StackTrace.current;
      int captures = 0;
      source.generationCapture = (bool Function() current) {
        captures++;
        Error.throwWithStackTrace(failure, trace);
      };
      final AddressesSettingsBinding binding = source.bind();
      final Future<AddressesWriteOutcome> first = binding.generate(
        isCurrent: () => true,
      );
      expect(binding.generate(isCurrent: () => true), same(first));
      final AddressesWriteOutcome result = await first;
      expect(captures, 1);
      expect(result.committed, isFalse);
      expect(result.write, isNull);
      expect(result.error, same(failure));
      expect(result.stackTrace.toString(), trace.toString());
    },
  );
}
