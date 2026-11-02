import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/cubits/timer_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/pair.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/status_strip.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const Key _sync = Key('strip_sync');
const Key _height = Key('strip_height');
const Key _node = Key('strip_node');
const Key _chain = Key('strip_chain');
const Key _peers = Key('strip_peers');
const Key _behind = Key('strip_behind');
const Key _flight = Key('strip_flight');
const Key _plasma = Key('strip_plasma');
const Key _elapsed = Key('strip_plasma_elapsed');
const Key _typical = Key('strip_plasma_typical');
const Key _notice = Key('notice');

/// The strip's width in the smallest window (1200) with the rail open (200):
/// less the shell's padding (10 and 18) and the gap beside the rail (8).
const double _narrowest = 964;

/// The sync cubit without its node and without its storage: the strip only
/// listens to it.
class _Sync extends Cubit<NodeSyncStatusState> implements NodeSyncStatusCubit {
  _Sync() : super(const NodeSyncStatusState());

  /// The node answers with these heights.
  void answer({required int current, required int target, bool done = true}) =>
      emit(
        NodeSyncStatusState(
          status: TimerStatus.success,
          data: Pair<SyncState, SyncInfo>(
            done ? SyncState.syncDone : SyncState.syncing,
            SyncInfo.fromJson(<String, dynamic>{
              'state': (done ? SyncState.syncDone : SyncState.syncing).index,
              'currentHeight': current,
              'targetHeight': target,
            }),
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What one test holds of the strip's sources.
class _Rig {
  _Rig(this.tester) : _start = tester.binding.clock.now();

  final WidgetTester tester;
  final DateTime _start;
  final _Sync sync = _Sync();
  final PowGeneratingStatusBloc pow = PowGeneratingStatusBloc();
  PowWorkToken? _work;
  final PlasmaTimes times = PlasmaTimes();
  final Set<Hash> confirmed = <Hash>{};
  late final InFlightBlocks flight = InFlightBlocks(
    lookup: (Hash hash) async => confirmed.contains(hash),
  );
  final ValueNotifier<int?> peers = ValueNotifier<int?>(23);

  /// The test's clock, which `pump` moves.
  Duration uptime() => tester.binding.clock.now().difference(_start);

  /// Starts a new observed SDK generation without replaying an old owner.
  void startWork() {
    final PowWorkToken work = pow.claimWork();
    _work = work;
    pow.update(work, PowStatus.generating);
  }

  /// Completes only the SDK generation started by this fixture.
  void finishWork() {
    final PowWorkToken? work = _work;
    if (work != null) pow.update(work, PowStatus.done);
  }

  Future<void> show({
    double width = 1400,
    Widget? trailing,
    Widget? plasma,
    ThemeData? theme,
    TextDirection direction = TextDirection.ltr,
    bool showFlight = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: SizedBox(
                width: width,
                child: StatusStrip(
                  syncCubit: sync,
                  page: ValueNotifier<int>(0),
                  flight: flight,
                  showFlight: showFlight,
                  peers: peers,
                  plasma:
                      plasma ??
                      GenerationStatus(
                        status: pow.stream,
                        uptime: uptime,
                        times: times,
                      ),
                  trailing: trailing,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose() async {
    pow.dispose();
    await sync.close();
    peers.dispose();
    flight.dispose();
  }
}

final Hash _hash = Hash.parse('ab' * 32);
final Hash _otherHash = Hash.parse('cd' * 32);

Color _dot(WidgetTester tester) =>
    (tester.widget<AnimatedContainer>(find.byKey(_sync)).decoration!
            as BoxDecoration)
        .color!;

/// Whether each enclosing priority row includes the part's allocated box.
/// An animation can have no pointer target while its asset is loading, and a
/// part left out by the layout stays in the widget tree at its natural size.
bool _drawn(Key key) {
  final Iterable<Element> matches = find.byKey(key).evaluate();
  if (matches.isEmpty) {
    return false;
  }
  RenderObject? current = matches.single.findRenderObject();
  if (current is! RenderBox || !current.hasSize || current.size.isEmpty) {
    return false;
  }
  while (current != null) {
    final Object? data = current.parentData;
    if (data is PriorityRowParentData && !data.shown) {
      return false;
    }
    current = current.parent;
  }
  return true;
}

void main() {
  setUp(() => kCurrentNode = 'ws://127.0.0.1:35998');
  tearDown(() => kCurrentNode = null);

  /// A window wide enough for every part at the test font's width, which
  /// is about twice the wallet's.
  void wideWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('at rest: height, node, chain, peers and a green dot', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 3281904, target: 3281904);
    await rig.show(width: 2000);

    expect(find.text('#3,281,904'), findsOneWidget);
    expect(_drawn(_height), isTrue);
    expect(tester.widget<Text>(find.byKey(_node)).data, 'ws://127.0.0.1:35998');
    expect(_drawn(_chain), isTrue);
    expect(tester.widget<Text>(find.byKey(_peers)).data, '23');
    expect(_dot(tester), AppTokens.dark.znn);
    expect(find.byKey(_plasma), findsNothing);
    expect(find.byKey(_behind), findsNothing);
    expect(find.byKey(_flight), findsNothing);
    expect(find.byKey(_elapsed), findsNothing);
    expect(tester.getSize(find.byType(StatusStrip)).height, 44);
    final Rect strip = tester.getRect(find.byType(StatusStrip));
    expect(tester.getCenter(find.byKey(_sync)).dx - strip.left, 24);
    expect(tester.getCenter(find.byKey(_sync)).dy - strip.top, 22);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generating plasma: the bolt, seconds counting, then typical', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 100, target: 100);
    await rig.show(width: 2000);

    rig.startWork();
    await tester.pump();
    expect(tester.widget(find.byKey(_plasma)), isA<AppLottie>());
    expect(
      tester.widget<AppLottie>(find.byKey(_plasma)).asset,
      AppLottieAsset.plasmaGeneration,
    );
    expect(tester.widget<AppLottie>(find.byKey(_plasma)).repeat, isTrue);
    expect(find.text('Generating plasma'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_elapsed)).data, '0 s');
    // Nothing has been measured yet.
    expect(find.byKey(_typical), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(find.byKey(_elapsed)).data, '1 s');
    await tester.pump(const Duration(seconds: 13));
    expect(tester.widget<Text>(find.byKey(_elapsed)).data, '14 s');

    rig.finishWork();
    await tester.pump();
    expect(find.byKey(_plasma), findsNothing);
    expect(find.byKey(_elapsed), findsNothing);
    expect(rig.times.typical, const Duration(seconds: 14));

    // The second generation starts from zero and knows the first.
    rig.startWork();
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(_elapsed)).data, '0 s');
    expect(
      tester.widget<Text>(find.byKey(_typical)).data,
      contains('usually about 14 s'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<Text>(find.byKey(_elapsed)).data, '3 s');
    expect(tester.takeException(), isNull);
  });

  test('the typical time is the median of the last eight', () {
    final PlasmaTimes times = PlasmaTimes();
    expect(times.typical, isNull);
    for (final int seconds in <int>[20, 30, 400]) {
      times.add(Duration(seconds: seconds));
    }
    expect(times.typical, const Duration(seconds: 30));
    times.add(const Duration(seconds: 40));
    expect(times.typical, const Duration(seconds: 35));
    for (int i = 0; i < PlasmaTimes.kept; i++) {
      times.add(const Duration(seconds: 5));
    }
    expect(times.typical, const Duration(seconds: 5));
  });

  testWidgets('a block in flight is named until a momentum has it', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 100, target: 100);
    await rig.show(width: 2000);
    expect(find.byKey(_flight), findsNothing);

    rig.flight.sent(
      hash: _hash,
      amount: BigInt.from(1250000000),
      decimals: 8,
      symbol: 'ZNN',
    );
    await tester.pump();
    expect(_drawn(_flight), isTrue);
    // No trailing zeros, and the amount is its own left-to-right run.
    expect(find.text('12.5 ZNN'), findsOneWidget);
    expect(
      find.textContaining('waiting for a momentum', findRichText: true),
      findsOneWidget,
    );

    // A momentum without the block: still waiting.
    rig.sync.answer(current: 101, target: 101);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_flight), findsOneWidget);

    rig.flight.sent(
      hash: _otherHash,
      amount: BigInt.one,
      decimals: 0,
      symbol: 'PP',
    );
    await tester.pump();
    expect(
      find.textContaining('Sending 2 blocks', findRichText: true),
      findsOneWidget,
    );

    rig.confirmed.addAll(<Hash>[_hash, _otherHash]);
    rig.sync.answer(current: 102, target: 102);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_flight), findsNothing);
    expect(rig.flight.value, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a node behind: amber dot and how many momentums', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 3281862, target: 3281904, done: false);
    await rig.show(width: 2000);

    expect(_dot(tester), AppTokens.dark.warn);
    expect(
      tester.widget<Text>(find.byKey(_behind)).data,
      '42 momentums behind',
    );
    expect(_drawn(_behind), isTrue);

    // Caught up to within the node's usual slack.
    rig.sync.answer(current: 3281903, target: 3281904, done: false);
    // Stream delivery schedules a rebuild; render that frame before checking.
    await tester.pump();
    await tester.pump();
    expect(_dot(tester), AppTokens.dark.znn);
    expect(find.byKey(_behind), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the trailing notice is shown when given, at the far end', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 100, target: 100);
    await rig.show(width: 2000);
    expect(find.byKey(_notice), findsNothing);

    await rig.show(
      width: 2000,
      trailing: const Text('Syrius 0.3.0 is out', key: _notice),
    );
    expect(_drawn(_notice), isTrue);
    expect(
      tester.getRect(find.byKey(_notice)).right,
      tester.getRect(find.byType(StatusStrip)).right -
          AppTokens.dark.statusStripPadding.right,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing overflows; peers go first, then chain, then node', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 3281904, target: 3281904);
    rig.flight.sent(
      hash: _hash,
      amount: BigInt.from(1250000000),
      decimals: 8,
      symbol: 'ZNN',
    );

    final Set<String> seen = <String>{};
    for (double width = 2200; width >= 100; width -= 20) {
      await rig.show(
        width: width,
        trailing: const Text('Syrius 0.3.0 is out', key: _notice),
      );
      expect(tester.takeException(), isNull, reason: 'at $width');
      final bool node = _drawn(_node);
      final bool chain = _drawn(_chain);
      final bool peers = _drawn(_peers);
      expect(!peers || chain, isTrue, reason: 'peers without chain at $width');
      expect(!chain || node, isTrue, reason: 'chain without node at $width');
      expect(!node || _drawn(_flight), isTrue, reason: 'node first at $width');
      seen.add('${node ? 'n' : ''}${chain ? 'c' : ''}${peers ? 'p' : ''}');
      // The dot is never given up.
      expect(_drawn(_sync), isTrue, reason: 'at $width');
      expect(
        tester
            .getRect(find.byType(StatusStrip))
            .contains(
              tester.getCenter(find.byKey(_sync)),
            ),
        isTrue,
        reason: 'connection dot outside the strip at $width',
      );
    }
    // Each step of giving way was passed through on the way down.
    expect(seen, <String>{'ncp', 'nc', 'n', ''});
  });

  testWidgets('layout visibility includes a noninteractive plasma marker', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 3281904, target: 3281904);
    const Widget mark = SizedBox(key: _plasma, width: 36, height: 36);
    await rig.show(width: 2000, plasma: mark);
    expect(find.byKey(_plasma).hitTestable(), findsNothing);
    expect(_drawn(_plasma), isTrue);

    await rig.show(width: 100, plasma: mark);
    expect(_drawn(_sync), isTrue);
    expect(_drawn(_plasma), isFalse);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(_height),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      contains('3281904'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every state at once in the smallest window, both themes', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.times.add(const Duration(seconds: 25));
    rig.sync.answer(current: 3281862, target: 3281904, done: false);
    rig.flight.sent(
      hash: _hash,
      amount: BigInt.from(1250000000),
      decimals: 8,
      symbol: 'ZNN',
    );
    for (final ThemeData theme in <ThemeData>[
      AppTheme.darkTheme,
      AppTheme.lightTheme,
    ]) {
      await rig.show(
        width: _narrowest,
        theme: theme,
        trailing: const Text('Syrius 0.3.0 is out', key: _notice),
      );
      rig.startWork();
      await tester.pump();
      await tester.pump(const Duration(seconds: 14));
      expect(tester.takeException(), isNull);
      expect(_drawn(_sync), isTrue);
      expect(_drawn(_height), isTrue);
      expect(_drawn(_behind), isTrue);
      expect(_drawn(_plasma), isTrue);
      expect(_drawn(_elapsed), isTrue);
      expect(
        tester.getRect(find.byType(StatusStrip)).width,
        _narrowest,
      );
      rig.finishWork();
      await tester.pump();
    }
  });

  testWidgets('smallest strip keeps its status and LTR data in RTL', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 3281862, target: 3281904, done: false);
    rig.times.add(const Duration(seconds: 25));
    rig.flight.sent(hash: _hash, amount: BigInt.zero);
    for (final ThemeData theme in <ThemeData>[
      AppTheme.darkTheme,
      AppTheme.lightTheme,
    ]) {
      await rig.show(
        width: _narrowest,
        theme: theme,
        direction: TextDirection.rtl,
        trailing: const Text('Wallet updates', key: _notice),
      );
      rig.startWork();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(_drawn(_sync), isTrue);
      expect(_drawn(_behind), isTrue);
      expect(_drawn(_elapsed), isTrue);
      expect(tester.takeException(), isNull);
      rig.finishWork();
      await tester.pump();
    }
  });

  testWidgets('a notice omitted by priority is omitted from actual semantics', (
    WidgetTester tester,
  ) async {
    wideWindow(tester);
    final SemanticsHandle handle = tester.ensureSemantics();
    final _Rig rig = _Rig(tester);
    addTearDown(rig.dispose);
    rig.sync.answer(current: 3281904, target: 3281904);
    try {
      await rig.show(
        width: 2000,
        trailing: const Text('NOTICE_MARKER', key: _notice),
      );
      expect(find.semantics.byLabel(RegExp('NOTICE_MARKER')), findsWidgets);
      await rig.show(
        width: 100,
        trailing: const Text('NOTICE_MARKER', key: _notice),
      );
      expect(find.byKey(_notice), findsOneWidget);
      expect(_drawn(_notice), isFalse);
      expect(find.semantics.byLabel(RegExp('NOTICE_MARKER')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    }
  });

  testWidgets(
    'hiding flight details preserves unresolved tracking and exact checks',
    (
      WidgetTester tester,
    ) async {
      wideWindow(tester);
      final _Rig rig = _Rig(tester);
      addTearDown(rig.dispose);
      rig.sync.answer(current: 100, target: 100);
      rig.flight.sent(hash: _hash, amount: BigInt.zero);
      await rig.show(width: 2000, showFlight: false);
      expect(find.byKey(_flight), findsNothing);
      expect(rig.flight.value.single.hash, _hash);
      await tester.pump(const Duration(seconds: 45));
      expect(rig.flight.value.single.hash, _hash);
      rig.sync.answer(current: 101, target: 101);
      await tester.pump();
      await tester.pump();
      expect(rig.flight.value.single.hash, _hash);
      await rig.show(width: 2000);
      expect(find.byKey(_flight), findsOneWidget);
      expect(
        find.text('Waiting for a momentum', findRichText: true),
        findsOneWidget,
      );
      await rig.show(width: 2000, showFlight: false);
      rig.confirmed.add(_hash);
      rig.sync.answer(current: 102, target: 102);
      await tester.pump();
      await tester.pump();
      expect(rig.flight.value, isEmpty);
      expect(find.byKey(_flight), findsNothing);
    },
  );
}
