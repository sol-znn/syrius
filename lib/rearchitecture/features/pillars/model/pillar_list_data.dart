import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Orders only the rows already fetched by the list's existing reader.
enum PillarListSort {
  /// Greatest delegation weight first.
  weight,

  /// Greatest produced share of expected momentums first.
  production,
}

/// Filters and orders a copy without changing the reader's page order.
///
/// Pagination still uses the unfiltered source. A search that finds nothing
/// in this snapshot must not prevent the next page from being requested.
List<PillarInfo> selectLoadedPillars(
  Iterable<PillarInfo> source, {
  required String query,
  required PillarListSort sort,
}) {
  final String match = query.trim().toLowerCase();
  final List<PillarInfo> result =
      source
          .where((PillarInfo item) => item.name.toLowerCase().contains(match))
          .toList()
        ..sort((PillarInfo left, PillarInfo right) {
          final int order = switch (sort) {
            PillarListSort.weight => right.weight.compareTo(left.weight),
            PillarListSort.production => _compareProduction(left, right),
          };
          if (order != 0) return order;
          final int nameOrder = left.name.toLowerCase().compareTo(
            right.name.toLowerCase(),
          );
          return nameOrder == 0 ? left.name.compareTo(right.name) : nameOrder;
        });
  return result;
}

bool _hasProduction(PillarInfo item) =>
    item.expectedMomentums > 0 && item.producedMomentums >= 0;

int _compareProduction(PillarInfo left, PillarInfo right) {
  final bool leftKnown = _hasProduction(left);
  final bool rightKnown = _hasProduction(right);
  if (leftKnown != rightKnown) return leftKnown ? -1 : 1;
  if (!leftKnown) return 0;
  // Cross multiplication preserves the ordering beyond double precision.
  return (BigInt.from(right.producedMomentums) *
          BigInt.from(left.expectedMomentums))
      .compareTo(
        BigInt.from(left.producedMomentums) *
            BigInt.from(right.expectedMomentums),
      );
}

/// A compact weight, truncated to two fractional digits using integers.
///
/// Its caller also shows the exact smallest-unit amount on hover. Compact
/// text is never an input to delegation, sorting or another calculation.
String compactPillarWeight(BigInt raw, {required int decimals}) {
  RangeError.checkNotNegative(decimals, 'decimals');
  final BigInt magnitude = raw.abs();
  final BigInt unit = BigInt.from(10).pow(decimals);
  const List<String> suffixes = <String>['', 'K', 'M', 'B', 'T'];
  BigInt divisor = unit;
  int suffix = 0;
  while (suffix < suffixes.length - 1 &&
      magnitude >= divisor * BigInt.from(1000)) {
    divisor *= BigInt.from(1000);
    suffix++;
  }
  final String sign = raw.isNegative ? '-' : '';
  if (suffix == 0) {
    final String whole = (magnitude ~/ unit).toString();
    if (decimals == 0) return '$sign$whole';
    final String fraction = (magnitude % unit)
        .toString()
        .padLeft(decimals, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$sign$whole${fraction.isEmpty ? '' : '.$fraction'}';
  }
  final BigInt hundredths = magnitude * BigInt.from(100) ~/ divisor;
  final String whole = (hundredths ~/ BigInt.from(100)).toString();
  final String fraction = (hundredths % BigInt.from(100))
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '$sign$whole'
      '${fraction.isEmpty ? '' : '.$fraction'}${suffixes[suffix]}';
}

/// Production as a percentage rounded to one decimal using integer ratios.
///
/// No expected momentums means no measured ratio, rather than zero uptime.
String? pillarUptimeText({required int produced, required int expected}) {
  if (expected <= 0 || produced < 0) return null;
  final BigInt denominator = BigInt.from(expected);
  final BigInt tenths =
      (BigInt.from(produced) * BigInt.from(1000) + denominator ~/ BigInt.two) ~/
      denominator;
  final BigInt fraction = tenths % BigInt.from(10);
  return '${tenths ~/ BigInt.from(10)}'
      '${fraction == BigInt.zero ? '' : '.$fraction'}%';
}
