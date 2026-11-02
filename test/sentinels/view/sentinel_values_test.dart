import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/view/sentinel_values.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/skeleton.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Sentinel extends Mock implements SentinelInfo {}

SentinelInfo _sentinel({
  required int cooldown,
  bool open = false,
  bool active = true,
}) {
  final _Sentinel sentinel = _Sentinel();
  when(() => sentinel.revokeCooldown).thenReturn(cooldown);
  when(() => sentinel.isRevocable).thenReturn(open);
  when(() => sentinel.active).thenReturn(active);
  return sentinel;
}

Widget _host(Widget child, {bool active = true, bool light = false}) =>
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: const <Locale>[Locale('en')],
      locale: const Locale('en'),
      home: Scaffold(
        body: TickerMode(
          enabled: active,
          child: Center(child: child),
        ),
      ),
    );

void main() {
  final DateTime readAt = DateTime.utc(2026, 10, 22, 12);

  testWidgets('registration ages keep an exact timestamp on hover', (
    WidgetTester tester,
  ) async {
    for (final (Duration, String) age in <(Duration, String)>[
      (const Duration(days: 27), '27 d ago'),
      (const Duration(days: 240), '8 mo ago'),
      (const Duration(days: 730), '2 y ago'),
    ]) {
      final int timestamp = readAt.subtract(age.$1).millisecondsSinceEpoch;
      await tester.pumpWidget(
        _host(
          SentinelRegistrationTime(
            timestamp: timestamp ~/ Duration.millisecondsPerSecond,
            now: readAt,
          ),
        ),
      );
      expect(find.text(age.$2), findsOneWidget);
      expect(
        find.byTooltip(
          FormatUtils.formatDateTimeSeconds(
            timestamp,
            locale: const Locale('en'),
          ),
        ),
        findsOneWidget,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('future registration timestamps show the date without a claim', (
    WidgetTester tester,
  ) async {
    final int timestamp = readAt
        .add(const Duration(days: 3))
        .millisecondsSinceEpoch;
    await tester.pumpWidget(
      _host(
        SentinelRegistrationTime(
          timestamp: timestamp ~/ Duration.millisecondsPerSecond,
          now: readAt,
        ),
      ),
    );
    expect(
      find.text(FormatUtils.formatDate(timestamp, locale: const Locale('en'))),
      findsOneWidget,
    );
    expect(find.textContaining('ago'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid timestamp stays unavailable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const SentinelRegistrationTime(timestamp: -1)),
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bool open in <bool>[false, true]) {
    testWidgets('window expiry needs another read, open=$open', (
      WidgetTester tester,
    ) async {
      DateTime now = readAt;
      int refreshed = 0;
      final SentinelInfo sentinel = _sentinel(cooldown: 3, open: open);
      await tester.pumpWidget(
        _host(
          SentinelRevocationTime(
            sentinel: sentinel,
            now: () => now,
            onRefresh: () => refreshed++,
          ),
        ),
      );
      expect(find.text(open ? 'now' : 'in 3 s'), findsOneWidget);
      now = readAt.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byType(Skeleton), findsOneWidget);
      expect(find.text('now'), findsNothing);
      expect(refreshed, 1);
      now = readAt.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(refreshed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('resuming a hidden value uses elapsed time and requests once', (
    WidgetTester tester,
  ) async {
    DateTime now = readAt;
    int refreshed = 0;
    final SentinelInfo sentinel = _sentinel(cooldown: 60);
    Widget value() => SentinelRevocationTime(
      sentinel: sentinel,
      now: () => now,
      onRefresh: () => refreshed++,
    );
    await tester.pumpWidget(_host(value(), active: false));
    now = readAt.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(refreshed, 0);
    await tester.pumpWidget(_host(value()));
    await tester.pump();
    expect(find.byType(Skeleton), findsOneWidget);
    expect(refreshed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a fresh record replaces an expired window', (
    WidgetTester tester,
  ) async {
    DateTime now = readAt;
    final SentinelInfo old = _sentinel(cooldown: 1);
    await tester.pumpWidget(
      _host(SentinelRevocationTime(sentinel: old, now: () => now)),
    );
    now = readAt.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Skeleton), findsOneWidget);
    await tester.pumpWidget(
      _host(
        SentinelRevocationTime(
          sentinel: _sentinel(cooldown: 3600, open: true),
          now: () => now,
        ),
      ),
    );
    expect(find.text('now'), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('revoked ownership never presents a revocation countdown', (
    WidgetTester tester,
  ) async {
    int refreshed = 0;
    await tester.pumpWidget(
      _host(
        SentinelRevocationTime(
          sentinel: _sentinel(cooldown: 0, active: false),
          onRefresh: () => refreshed++,
        ),
      ),
    );
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.text('now'), findsNothing);
    expect(refreshed, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid cooldowns stay unavailable without overflowing time', (
    WidgetTester tester,
  ) async {
    for (final int cooldown in <int>[-1, 8640000000000000]) {
      await tester.pumpWidget(
        _host(SentinelRevocationTime(sentinel: _sentinel(cooldown: cooldown))),
      );
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('now'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('status has an icon and a factual label, light=$light', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Row(
            children: <Widget>[
              SentinelStatusChip(active: true),
              SentinelStatusChip(active: false),
            ],
          ),
          light: light,
        ),
      );
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Revoked'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
      expect(find.text('Producing'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
