import 'package:mocktail/mocktail.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Sentinel extends Mock implements SentinelInfo {}

class _Owner extends Fake implements Address {
  _Owner(this.value);

  final String value;

  @override
  String toString() => value;
}

/// Synthetic identifiers for mocked presentation records, with no chain use.
String sentinelOwnerFixture(int index) =>
    'z1${index.toString().padLeft(38, '0')}';

/// One mocked RPC record; these fixtures cannot create or revoke a sentinel.
SentinelInfo sentinelFixture(
  int index, {
  bool active = true,
  bool open = false,
  int? cooldown,
  int? registered,
}) {
  final _Sentinel sentinel = _Sentinel();
  final int now =
      DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
  when(() => sentinel.owner).thenReturn(_Owner(sentinelOwnerFixture(index)));
  when(() => sentinel.active).thenReturn(active);
  when(() => sentinel.isRevocable).thenReturn(open);
  when(() => sentinel.revokeCooldown).thenReturn(
    cooldown ?? const Duration(days: 3, hours: 2, seconds: 30).inSeconds,
  );
  when(() => sentinel.registrationTimestamp).thenReturn(
    registered ?? now - const Duration(days: 27).inSeconds,
  );
  return sentinel;
}
