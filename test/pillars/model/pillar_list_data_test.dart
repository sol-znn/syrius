import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars/model/pillar_list_data.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Pillar extends Mock implements PillarInfo {}

PillarInfo _pillar(
  String name, {
  String weight = '0',
  int produced = 0,
  int expected = 0,
}) {
  final _Pillar item = _Pillar();
  when(() => item.name).thenReturn(name);
  when(() => item.weight).thenReturn(BigInt.parse(weight));
  when(() => item.producedMomentums).thenReturn(produced);
  when(() => item.expectedMomentums).thenReturn(expected);
  return item;
}

void main() {
  test(
    'weight sorting distinguishes adjacent integers beyond double range',
    () {
      final PillarInfo smaller = _pillar('alpha', weight: '9007199254740992');
      final PillarInfo larger = _pillar('beta', weight: '9007199254740993');
      final List<PillarInfo> source = <PillarInfo>[smaller, larger];
      expect(
        selectLoadedPillars(source, query: '', sort: PillarListSort.weight),
        <PillarInfo>[larger, smaller],
      );
      expect(source, <PillarInfo>[smaller, larger]);
    },
  );

  test('production compares exact fractions and puts unknown ratios last', () {
    final PillarInfo lower = _pillar(
      'alpha',
      produced: int.parse('9007199254740992'),
      expected: int.parse('9007199254740993'),
    );
    final PillarInfo higher = _pillar(
      'beta',
      produced: int.parse('9007199254740993'),
      expected: int.parse('9007199254740994'),
    );
    final PillarInfo unknown = _pillar('unknown');
    expect(
      selectLoadedPillars(
        <PillarInfo>[unknown, lower, higher],
        query: '',
        sort: PillarListSort.production,
      ),
      <PillarInfo>[higher, lower, unknown],
    );
  });

  test(
    'search is trimmed, case insensitive and leaves source pages intact',
    () {
      final PillarInfo beta = _pillar('Beta');
      final PillarInfo alpha = _pillar('alpha');
      final List<PillarInfo> source = <PillarInfo>[beta, alpha];
      expect(
        selectLoadedPillars(
          source,
          query: ' ALP ',
          sort: PillarListSort.weight,
        ),
        <PillarInfo>[alpha],
      );
      expect(
        selectLoadedPillars(
          source,
          query: 'absent',
          sort: PillarListSort.weight,
        ),
        isEmpty,
      );
      expect(source, <PillarInfo>[beta, alpha]);
      expect(
        selectLoadedPillars(source, query: '', sort: PillarListSort.weight),
        <PillarInfo>[alpha, beta],
      );
    },
  );

  test(
    'compact weights preserve small units and truncate with integer math',
    () {
      const Map<String, String> cases = <String, String>{
        '0': '0',
        '1': '0.00000001',
        '120450000000': '1.2K',
        '992000000000': '9.92K',
        '99999999999999': '999.99K',
        '100000000000000': '1M',
        '9007199254740993': '90.07M',
        '-100000000000': '-1K',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        expect(
          compactPillarWeight(BigInt.parse(entry.key), decimals: 8),
          entry.value,
          reason: entry.key,
        );
      }
      expect(compactPillarWeight(BigInt.from(7), decimals: 0), '7');
    },
  );

  test('uptime preserves measured zero and refuses an absent denominator', () {
    expect(pillarUptimeText(produced: 0, expected: 12), '0%');
    expect(pillarUptimeText(produced: 12, expected: 12), '100%');
    expect(pillarUptimeText(produced: 1760, expected: 1762), '99.9%');
    expect(pillarUptimeText(produced: 1, expected: 3), '33.3%');
    expect(pillarUptimeText(produced: 2, expected: 3), '66.7%');
    expect(pillarUptimeText(produced: 0, expected: 0), isNull);
    expect(pillarUptimeText(produced: -1, expected: 2), isNull);
    expect(pillarUptimeText(produced: 1, expected: -1), isNull);
  });
}
