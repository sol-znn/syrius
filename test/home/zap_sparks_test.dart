import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/view/zap_sparks.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const MethodChannel _window = MethodChannel('window_manager');
const Key _target = Key('underlying_action');
const Key _paint = Key('home_zap_sparks_paint');
const ZapReceiveOwner _owner = ZapReceiveOwner(
  walletId: 'synthetic-wallet-owner',
  chainId: 321,
  recipient: 'synthetic-recipient',
);
const ZapReceiveScope _scope = ZapReceiveScope(
  owner: _owner,
  nodeId: 'synthetic-node',
);

// Isolated synthetic identities only. No history, balances, network or wallet
// fixtures are constructed by these tests. This double is not durable proof.
Hash _hash(int digit) => Hash.parse(
  List<String>.filled(64, digit.toRadixString(16)).join(),
);

class _Claims implements ZapReceiveClaims {
  final Set<ZapReceiveIdentity> seen = <ZapReceiveIdentity>{};
  final List<ZapReceiveIdentity> requests = <ZapReceiveIdentity>[];
  final List<Set<Hash>> baselines = <Set<Hash>>[];
  Completer<void>? primeGate;
  Completer<void>? claimGate;
  Error? primeFailure;
  Error? claimFailure;

  @override
  Future<void> prime(ZapReceiveOwner owner, Set<Hash> receiveHashes) async {
    baselines.add(receiveHashes);
    await primeGate?.future;
    final Error? failure = primeFailure;
    if (failure != null) throw failure;
    for (final Hash hash in receiveHashes) {
      seen.add(ZapReceiveIdentity(owner: owner, receiveHash: hash));
    }
  }

  @override
  Future<bool> claim(ZapReceiveIdentity identity) async {
    requests.add(identity);
    await claimGate?.future;
    final bool admitted = seen.add(identity);
    final Error? failure = claimFailure;
    if (failure != null) throw failure;
    return admitted;
  }
}

class _Rig {
  final _Claims claims = _Claims();
  final List<ZapSparksController> controllers = <ZapSparksController>[];
  late final ZapSparksController controller = qualified();
  bool current = true;
  bool brokenGuard = false;
  int taps = 0;

  ZapSparksController qualified({ZapReceiveScope scope = _scope}) {
    final ZapSparksController owner = ZapSparksController.qualified(
      scope: scope,
      claims: claims,
      isCurrent: () {
        if (brokenGuard) throw StateError('Synthetic context guard failure');
        return current;
      },
    );
    controllers.add(owner);
    return owner;
  }

  Future<void> show(
    WidgetTester tester, {
    ZapSparksController? owner,
    bool visible = true,
    bool ticking = true,
    bool light = false,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: TickerMode(
            enabled: ticking,
            child: Scaffold(
              body: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: GestureDetector(
                      key: _target,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                    ),
                  ),
                  Positioned.fill(
                    child: ZapSparks(
                      controller: owner ?? controller,
                      visible: visible,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<bool> prime([Iterable<Hash> hashes = const <Hash>[]]) =>
      controller.primeHistory(scope: _scope, receiveHashes: hashes);

  Future<bool> receive(int digit) =>
      controller.receive(scope: _scope, receiveHash: _hash(digit));

  void dispose() {
    for (final ZapSparksController controller in controllers) {
      controller.dispose();
    }
  }
}

ZapSparksPainter _frame(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(_paint)).painter! as ZapSparksPainter;

Future<void> _using(
  WidgetTester tester,
  Future<void> Function(_Rig rig) body,
) async {
  final _Rig rig = _Rig();
  try {
    await rig.show(tester);
    await body(rig);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    rig.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (MethodCall call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
  });

  testWidgets('default controller refuses direct calls and never autoplays', (
    WidgetTester tester,
  ) async {
    final ZapSparksController controller = ZapSparksController();
    final _Rig rig = _Rig();
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await rig.show(tester, owner: controller);
      expect(controller.seam, Seam.zapReceive);
      expect(find.byType(SeamGate), findsOneWidget);
      await expectLater(
        controller.primeHistory(scope: _scope, receiveHashes: <Hash>[_hash(1)]),
        throwsA(isA<SeamNotBuilt>()),
      );
      await expectLater(
        controller.receive(scope: _scope, receiveHash: _hash(1)),
        throwsA(isA<SeamNotBuilt>()),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(_paint), paintsExactlyCountTimes(#drawCircle, 0));
      expect(_frame(tester).progress, 1);
      await tester.tap(find.byKey(_target));
      expect(rig.taps, 1);
      final ExcludeSemantics excluded = tester.widget<ExcludeSemantics>(
        find
            .descendant(
              of: find.byType(ZapSparks),
              matching: find.byType(ExcludeSemantics),
            )
            .first,
      );
      expect(excluded.excluding, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      rig.dispose();
    }
  });

  testWidgets(
    'mount and initial history are silent before live admission',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.receive(1), isFalse);
      expect(rig.claims.requests, isEmpty);
      expect(await rig.prime(<Hash>[_hash(1), _hash(2)]), isTrue);
      expect(find.byKey(_paint), paintsExactlyCountTimes(#drawCircle, 0));
      expect(await rig.receive(1), isFalse);
      expect(await rig.receive(3), isTrue);
      await tester.pump();
      expect(find.byKey(_paint), paintsExactlyCountTimes(#drawCircle, 28));
    }),
  );

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'measured circles use the semantic palette, light=$light',
      (
        WidgetTester tester,
      ) => _using(tester, (_Rig rig) async {
        await rig.show(tester, light: light);
        final MaterialApp app = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        await tester.pump(app.themeAnimationDuration);
        await tester.pump(const Duration(microseconds: 1));
        expect(await rig.prime(), isTrue);
        expect(await rig.receive(1), isTrue);
        await tester.pump();
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Size size = tester.getSize(find.byKey(_paint));
        final Offset origin = size.center(const Offset(3, 3));
        expect(
          find.byKey(_paint),
          paints
            ..circle(
              x: origin.dx,
              y: origin.dy,
              radius: 3,
              color: tokens.qsrInk,
            )
            ..circle(x: origin.dx, y: origin.dy, radius: 3, color: tokens.pink)
            ..circle(x: origin.dx, y: origin.dy, radius: 3, color: tokens.znn),
        );
        expect(find.byKey(_paint), paintsExactlyCountTimes(#drawCircle, 28));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        final double eased = tokens.ease.transform(0.5);
        final Offset first =
            origin + ZapSparksPainter.destinations.first * eased;
        expect(
          find.byKey(_paint),
          paints..circle(
            x: first.dx,
            y: first.dy,
            radius: 3 * (1 - 0.8 * eased),
            color: tokens.qsrInk.withValues(
              alpha: tokens.qsrInk.a * (1 - eased),
            ),
          ),
        );
      }),
    );
  }

  test('geometry is fixed, immutable and spans the measured radial bounds', () {
    final List<Offset> points = ZapSparksPainter.destinations;
    expect(points, hasLength(28));
    expect(
      points.map((Offset p) => p.distance).reduce(math.min),
      closeTo(120, 1e-8),
    );
    expect(
      points.map((Offset p) => p.distance).reduce(math.max),
      closeTo(280, 1e-8),
    );
    expect(points.toSet(), hasLength(28));
    expect(() => points.add(Offset.zero), throwsUnsupportedError);
  });

  testWidgets(
    'all 28 finish at 900ms even when both OS motion flags are set',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      try {
        await rig.show(tester, disableAnimations: true);
        expect(await rig.prime(), isTrue);
        expect(await rig.receive(1), isTrue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 899));
        expect(_frame(tester).progress, closeTo(899 / 900, 1e-8));
        expect(find.byKey(_paint), paintsExactlyCountTimes(#drawCircle, 28));
        await tester.pump(const Duration(milliseconds: 1));
        expect(_frame(tester).progress, 1);
        expect(find.byKey(_paint), paintsExactlyCountTimes(#drawCircle, 0));
        expect(tester.binding.transientCallbackCount, 0);
        expect(await rig.receive(1), isFalse);
      } finally {
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      }
    }),
  );

  testWidgets(
    'queued deliveries wait for the first complete burst',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      expect(await rig.receive(1), isTrue);
      bool? second;
      final Future<void> waiting = rig.receive(2).then((bool value) {
        second = value;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 899));
      expect(second, isNull);
      expect(rig.claims.requests, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await waiting;
      await tester.pump();
      expect(second, isTrue);
      expect(_frame(tester).progress, 0);
      expect(rig.claims.requests, hasLength(2));
    }),
  );

  testWidgets(
    'queued duplicate cannot restart an already claimed hash',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      expect(await rig.receive(1), isTrue);
      final Future<bool> duplicate = rig.receive(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(await duplicate, isFalse);
      expect(_frame(tester).progress, 1);
      expect(rig.claims.seen, hasLength(1));
    }),
  );

  testWidgets(
    'recreated node context shares the exact durable delivery key',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      expect(await rig.receive(1), isTrue);
      const ZapReceiveScope next = ZapReceiveScope(
        owner: _owner,
        nodeId: 'another-synthetic-node',
      );
      final ZapSparksController reopened = rig.qualified(scope: next);
      await rig.show(tester, owner: reopened);
      expect(
        await reopened.primeHistory(scope: next, receiveHashes: const <Hash>[]),
        isTrue,
      );
      expect(
        await reopened.receive(scope: next, receiveHash: _hash(1)),
        isFalse,
      );
      expect(rig.claims.seen, hasLength(1));
      expect(_frame(tester).progress, 1);
    }),
  );

  test('wallet, chain and recipient are separate durable namespaces', () async {
    final _Claims claims = _Claims();
    for (final ZapReceiveOwner owner in <ZapReceiveOwner>[
      _owner,
      const ZapReceiveOwner(
        walletId: 'other-wallet',
        chainId: 321,
        recipient: 'synthetic-recipient',
      ),
      const ZapReceiveOwner(
        walletId: 'synthetic-wallet-owner',
        chainId: 999,
        recipient: 'synthetic-recipient',
      ),
      const ZapReceiveOwner(
        walletId: 'synthetic-wallet-owner',
        chainId: 321,
        recipient: 'other-recipient',
      ),
    ]) {
      final ZapReceiveIdentity identity = ZapReceiveIdentity(
        owner: owner,
        receiveHash: _hash(1),
      );
      expect(await claims.claim(identity), isTrue);
      expect(await claims.claim(identity), isFalse);
    }
    expect(claims.seen, hasLength(4));
  });

  testWidgets(
    'a different scope instance refuses before storage',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      final ZapReceiveScope stale = ZapReceiveScope(
        owner: _owner,
        nodeId: _scope.nodeId,
      );
      expect(
        await rig.controller.primeHistory(
          scope: stale,
          receiveHashes: <Hash>[_hash(1)],
        ),
        isFalse,
      );
      expect(await rig.prime(), isTrue);
      expect(
        await rig.controller.receive(scope: stale, receiveHash: _hash(1)),
        isFalse,
      );
      expect(rig.claims.requests, isEmpty);
      expect(rig.claims.baselines, hasLength(1));
    }),
  );

  testWidgets(
    'observed false context cannot revive a deferred claim',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      final Completer<void> gate = Completer<void>();
      rig.claims.claimGate = gate;
      final Future<bool> receiving = rig.receive(1);
      await tester.pump();
      expect(rig.claims.requests, hasLength(1));
      rig.current = false;
      expect(await rig.receive(2), isFalse);
      rig.current = true;
      gate.complete();
      expect(await receiving, isFalse);
      expect(await rig.receive(3), isFalse);
      expect(rig.claims.requests, hasLength(1));
      expect(rig.claims.seen, hasLength(1));
      expect(_frame(tester).progress, 1);
    }),
  );

  testWidgets(
    'a throwing context guard permanently revokes admission',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      rig.brokenGuard = true;
      expect(await rig.receive(1), isFalse);
      rig.brokenGuard = false;
      expect(await rig.receive(1), isFalse);
      expect(rig.claims.requests, isEmpty);
    }),
  );

  for (final bool ticking in <bool>[false, true]) {
    testWidgets(
      'hidden surface suppresses a deferred claim, ticking=$ticking',
      (
        WidgetTester tester,
      ) => _using(tester, (_Rig rig) async {
        expect(await rig.prime(), isTrue);
        final Completer<void> gate = Completer<void>();
        rig.claims.claimGate = gate;
        final Future<bool> receiving = rig.receive(1);
        await tester.pump();
        await rig.show(tester, ticking: ticking, visible: !ticking);
        await rig.show(tester);
        gate.complete();
        expect(await receiving, isFalse);
        expect(await rig.receive(1), isFalse);
        expect(_frame(tester).progress, 1);
        expect(tester.binding.transientCallbackCount, 0);
      }),
    );
  }

  testWidgets(
    'window blur and lifecycle hiding cancel without resume replay',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      expect(await rig.receive(1), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final WindowListener window =
          (tester.state(find.byType(ZapSparks)) as WindowListener)
            ..onWindowBlur();
      await tester.pump();
      expect(_frame(tester).progress, 1);
      window.onWindowFocus();
      await tester.pump(const Duration(seconds: 1));
      expect(_frame(tester).progress, 1);
      expect(await rig.receive(1), isFalse);
      expect(await rig.receive(2), isTrue);
      final WidgetsBindingObserver lifecycle =
          (tester.state(find.byType(ZapSparks)) as WidgetsBindingObserver)
            ..didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(_frame(tester).progress, 1);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(await rig.receive(2), isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    }),
  );

  testWidgets(
    'dispose rejects a late claim without rolling it back',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      final Completer<void> gate = Completer<void>();
      rig.claims.claimGate = gate;
      final Future<bool> receiving = rig.receive(1);
      await tester.pump();
      rig.controller.dispose();
      gate.complete();
      expect(await receiving, isFalse);
      expect(rig.claims.seen, hasLength(1));
      await tester.pump();
      expect(_frame(tester).progress, 1);
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'queued mutable hashes retain their original immutable identity',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      expect(await rig.prime(), isTrue);
      expect(await rig.receive(1), isTrue);
      final Hash mutable = _hash(2);
      final String original = mutable.toString();
      final Future<bool> queued = rig.controller.receive(
        scope: _scope,
        receiveHash: mutable,
      );
      mutable.hash[0] = 255;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(await queued, isTrue);
      expect(rig.claims.requests.last.receiveHash.toString(), original);
      expect(
        () => rig.claims.requests.last.receiveHash.hash[0] = 0,
        throwsUnsupportedError,
      );
    }),
  );

  testWidgets(
    'initial history freezes both the collection and each SDK hash',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      final Completer<void> gate = Completer<void>();
      rig.claims.primeGate = gate;
      final Hash mutable = _hash(1);
      final String original = mutable.toString();
      final List<Hash> history = <Hash>[mutable];
      final Future<bool> priming = rig.prime(history);
      mutable.hash[0] = 255;
      history.clear();
      gate.complete();
      expect(await priming, isTrue);
      final Set<Hash> baseline = rig.claims.baselines.single;
      expect(baseline.single.toString(), original);
      expect(baseline.clear, throwsUnsupportedError);
      expect(() => baseline.single.hash[0] = 0, throwsUnsupportedError);
      expect(await rig.receive(1), isFalse);
      expect(_frame(tester).progress, 1);
    }),
  );

  testWidgets(
    'empty hashes and uncertain durable claims never start paint',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      await expectLater(rig.prime(<Hash>[emptyHash]), throwsArgumentError);
      expect(rig.claims.baselines, isEmpty);
      expect(await rig.prime(), isTrue);
      await expectLater(
        rig.controller.receive(scope: _scope, receiveHash: emptyHash),
        throwsArgumentError,
      );
      final StateError original = StateError('Synthetic uncertain claim');
      rig.claims.claimFailure = original;
      await expectLater(rig.receive(1), throwsA(same(original)));
      rig.claims.claimFailure = null;
      expect(await rig.receive(1), isFalse);
      expect(_frame(tester).progress, 1);
      expect(rig.claims.seen, hasLength(1));
    }),
  );

  testWidgets(
    'failed or revoked initial prime cannot authorize a later signal',
    (
      WidgetTester tester,
    ) => _using(tester, (_Rig rig) async {
      final StateError original = StateError('Synthetic incomplete baseline');
      rig.claims.primeFailure = original;
      await expectLater(rig.prime(<Hash>[_hash(1)]), throwsA(same(original)));
      expect(await rig.receive(2), isFalse);
      expect(rig.claims.requests, isEmpty);
      rig.claims.primeFailure = null;
      final Completer<void> gate = Completer<void>();
      rig.claims.primeGate = gate;
      final Future<bool> priming = rig.prime(<Hash>[_hash(1)]);
      rig.current = false;
      expect(await rig.receive(2), isFalse);
      rig.current = true;
      gate.complete();
      expect(await priming, isFalse);
      expect(await rig.receive(2), isFalse);
      expect(_frame(tester).progress, 1);
    }),
  );
}
