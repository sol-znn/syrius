import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_binding.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Accelerator extends Mock implements AcceleratorApi {}

class _Pillar extends Mock implements PillarApi {}

class _Ledger extends Mock implements LedgerApi {}

void main() {
  late _Accelerator accelerator;
  late _Pillar pillar;
  late _Ledger ledger;
  late int publications;

  setUp(() {
    accelerator = _Accelerator();
    pillar = _Pillar();
    ledger = _Ledger();
    publications = 0;
  });
  tearDown(() {
    verifyZeroInteractions(accelerator);
    verifyZeroInteractions(pillar);
    verifyZeroInteractions(ledger);
    expect(publications, 0);
  });

  AcceleratorActionBinding binding(bool Function() current) =>
      AcceleratorActionBinding.forTesting(
        scopeKey: Object(),
        ownerAddress: emptyAddress.toString(),
        maximumZnn: BigInt.one,
        maximumQsr: BigInt.one,
        current: current,
        accelerator: accelerator,
        pillar: pillar,
        ledger: ledger,
        sender:
            (
              AccountBlockTemplate _,
              String _, {
              required bool Function() canPublish,
            }) {
              publications++;
              throw StateError('Unexpected publication');
            },
      );

  test('nested loss cannot be cleared by a restored outer action proof', () {
    late final AcceleratorActionBinding original;
    bool nested = false;
    bool current = true;
    bool? nestedCurrent;
    original = binding(() {
      if (!nested) {
        nested = true;
        current = false;
        nestedCurrent = original.isCurrent;
        current = true;
      }
      return current;
    });
    expect(original.isCurrent, isFalse);
    expect(nestedCurrent, isFalse);
    expect(current, isTrue);
    expect(original.isCurrent, isFalse);
    expect(original.isCurrent, isFalse);
  });

  test('an original action proof error still escapes unchanged', () {
    final StateError failure = StateError('Original proof failed');
    bool throwing = true;
    final AcceleratorActionBinding original = binding(
      () => throwing ? throw failure : true,
    );
    expect(() => original.isCurrent, throwsA(same(failure)));
    throwing = false;
    expect(original.isCurrent, isTrue);
  });
}
