import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/client_window.dart';

void main() {
  test('measures logical client pixels from physical view metrics', () {
    for (final double ratio in <double>[1, 1.25, 1.5, 2, 3]) {
      final ClientMetrics metrics = ClientMetrics(
        Size(1280 * ratio, 780 * ratio),
        ratio,
      );
      expect(metrics.logicalSize, const Size(1280, 780));
      expect(metrics.matches(const Size(1280, 780)), isTrue);
      expect(metrics.toJson()['devicePixelRatio'], ratio);
    }
    expect(
      const ClientMetrics(Size(1279, 780), 1).matches(const Size(1280, 780)),
      isFalse,
    );
  });

  test('corrects native borders by the observed client delta', () async {
    for (final double ratio in <double>[1, 1.25, 2]) {
      Size outer = const Size(1200, 700);
      final List<Size> requests = <Size>[];
      int settled = 0;
      final ClientResizeResult result = await resizeClientArea(
        requested: const Size(1280, 780),
        readMetrics: () => ClientMetrics(
          Size((outer.width - 16) * ratio, (outer.height - 39) * ratio),
          ratio,
        ),
        readOuter: () async => outer,
        setOuter: (Size size) async {
          requests.add(size);
          outer = size;
        },
        settle: () async {
          settled++;
        },
      );
      expect(requests, <Size>[const Size(1296, 819)]);
      expect(result.observed.logicalSize, const Size(1280, 780));
      expect(result.outer, const Size(1296, 819));
      expect(result.attempts, 1);
      expect(result.toJson()['clientMatched'], isTrue);
      expect(settled, 1);
    }
  });

  test(
    'an already matching client does not resize its native window',
    () async {
      final ClientResizeResult result = await resizeClientArea(
        requested: const Size(1280, 780),
        readMetrics: () => const ClientMetrics(Size(2560, 1560), 2),
        readOuter: () async => const Size(1296, 819),
        setOuter: (_) async => fail('no resize expected'),
        settle: () async => fail('no settle expected'),
      );
      expect(result.attempts, 0);
    },
  );

  test('a constrained window refuses after its bounded retry budget', () async {
    int attempts = 0;
    await expectLater(
      resizeClientArea(
        requested: const Size(1280, 780),
        readMetrics: () => const ClientMetrics(Size(1200, 700), 1),
        readOuter: () async => const Size(1216, 739),
        setOuter: (_) async {
          attempts++;
        },
        settle: () async {},
        maxAttempts: 3,
      ),
      throwsA(
        isA<ClientResizeError>()
            .having((ClientResizeError e) => e.result.attempts, 'attempts', 3)
            .having(
              (ClientResizeError e) => e.result.toJson()['client'],
              'observed client',
              <double>[1200, 700],
            )
            .having(
              (ClientResizeError e) => e.result.toJson()['requestedClient'],
              'requested client',
              <double>[1280, 780],
            ),
      ),
    );
    expect(attempts, 3);
  });

  test('invalid metrics and unbounded requests cannot claim a match', () async {
    for (final ClientMetrics metrics in <ClientMetrics>[
      const ClientMetrics(Size.zero, 1),
      const ClientMetrics(Size(1280, 780), 0),
      const ClientMetrics(Size(1280, 780), double.nan),
    ]) {
      expect(() => metrics.logicalSize, throwsStateError);
    }
    for (final Size requested in <Size>[
      Size.zero,
      const Size(-1, 780),
      const Size(double.infinity, 780),
      const Size(16385, 780),
    ]) {
      await expectLater(
        resizeClientArea(
          requested: requested,
          readMetrics: () => const ClientMetrics(Size(1280, 780), 1),
          readOuter: () async => const Size(1280, 780),
          setOuter: (_) async => fail('invalid request reached native adapter'),
          settle: () async {},
        ),
        throwsArgumentError,
      );
    }
  });
}
