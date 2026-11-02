import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/window_frame.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/entry_caption_observer.dart';

// Each widget registration selects one platform and keeps its description.
class _PlatformVariant extends TargetPlatformVariant {
  const _PlatformVariant(super.values);

  @override
  String describeValue(TargetPlatform value) => '';
}

const TargetPlatformVariant _windows = _PlatformVariant(
  <TargetPlatform>{TargetPlatform.windows},
);

const MethodChannel _channel = MethodChannel('window_manager');

class _Native {
  final List<String> calls = <String>[];
  bool maximized = false;
  bool minimized = false;
  bool changeMode = true;
  bool failMaximize = false;
  bool failQuery = false;
  Completer<void>? holdMaximize;
  Completer<void>? holdUnmaximize;
  Completer<void>? holdMinimize;

  Future<Object?> call(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'isMaximized':
        if (failQuery) {
          throw PlatformException(code: 'private-query-failure');
        }
        return maximized;
      case 'maximize':
        if (holdMaximize != null) {
          await holdMaximize!.future;
        }
        if (failMaximize) {
          throw PlatformException(code: 'private-action-failure');
        }
        if (changeMode) {
          maximized = true;
        }
        return null;
      case 'unmaximize':
        if (holdUnmaximize != null) {
          await holdUnmaximize!.future;
        }
        if (changeMode) {
          maximized = false;
        }
        return null;
      case 'minimize':
        if (holdMinimize != null) {
          await holdMinimize!.future;
        }
        if (changeMode) {
          minimized = true;
        }
        return null;
      case 'isFullScreen':
        return false;
      default:
        throw StateError('Unexpected synthetic native call');
    }
  }

  Future<Map<String, Object?>> snapshot({required bool geometry}) async =>
      <String, Object?>{
        'minimized': minimized,
        'maximized': maximized,
        if (geometry && !minimized && !maximized) ...<String, Object?>{
          'window': <double>[40, 50, 1296, 819],
          'client': <double>[1280, 780],
          'physical': <double>[1280, 780],
          'devicePixelRatio': 1.0,
        },
      };
}

Map<String, Object?> _entry() => <String, Object?>{
  'captures': 4,
  'held': false,
  'nativeWindowReady': true,
  'startupReady': true,
  'welcomeReady': true,
};

Widget _host({Key? frameKey, bool duplicate = false, Widget? body}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext context, Widget? child) =>
          AppWindowFrame(key: frameKey, child: child!),
      home: Scaffold(
        body: duplicate
            ? Center(
                child: IconButton(
                  key: const ValueKey<String>('window-maximize'),
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                ),
              )
            : body ?? const SizedBox.expand(),
      ),
    );

Future<void> _microtasks() async {
  for (int i = 0; i < 16; i++) {
    await Future<void>.value();
  }
}

Future<void> _refusal<T extends Object>(Future<Object?> original) async {
  await expectLater(original, throwsA(isA<T>()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Native native;

  setUp(() {
    native = _Native();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.call);
  });

  tearDown(() {
    if (native.holdMaximize case final Completer<void> pending) {
      if (!pending.isCompleted) {
        pending.complete();
      }
    }
    if (native.holdUnmaximize case final Completer<void> pending) {
      if (!pending.isCompleted) {
        pending.complete();
      }
    }
    if (native.holdMinimize case final Completer<void> pending) {
      if (!pending.isCompleted) {
        pending.complete();
      }
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> mount(
    WidgetTester tester, {
    bool duplicate = false,
    Widget? body,
  }) async {
    tester.view
      ..physicalSize = const Size(1280, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(duplicate: duplicate, body: body));
    await tester.pump();
    await _microtasks();
  }

  // Synthetic observer input calls the actual production IconButton callback.
  // It does not claim pointer dispatch, native Windows, HTTP or startup proof.
  EntryCaptionObserver observer({
    bool dispatch = true,
    bool reportRelease = true,
    Duration Function()? elapsed,
  }) => EntryCaptionObserver(
    readEntry: _entry,
    readWindow: native.snapshot,
    elapsed: elapsed,
    tap: (Element button, VoidCallback admission, VoidCallback released) async {
      admission();
      if (dispatch) {
        (button.widget as IconButton).onPressed!();
      }
      if (reportRelease) {
        released();
      }
    },
  );

  Future<Map<String, Object?>> settled(EntryCaptionObserver original) async {
    for (int i = 0; i < 32; i++) {
      await _microtasks();
      final Map<String, Object?> result = await original.observe();
      if (result['settled'] == true) {
        return result;
      }
    }
    fail(
      'The original caption action did not settle within the finite fixture',
    );
  }

  Future<void> throughMinimize(EntryCaptionObserver original) async {
    await original.bind();
    for (final String action in <String>['maximize', 'restore', 'minimize']) {
      await original.tap(action);
      expect((await settled(original))['settled'], isTrue);
    }
  }

  test('caption RPC cannot invent an original native entry owner', () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    await _refusal<HarnessError>(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'entry-caption',
        'do': 'bind',
      }),
    );
  });

  test(
    'public refusal retains the first finite cause without native reads',
    () {
      final EntryCaptionObserver original = observer()
        ..hold(const CaptionRefused('caption-tree-refused'))
        ..hold(StateError('private-native-diagnostic'));
      expect(original.publicFailureCode, 'CAPTION_TREE_REFUSED');
      expect(native.calls, isEmpty);
    },
  );

  test(
    'public refusal never exposes private or unrecognized original errors',
    () {
      for (final Object failure in <Object>[
        StateError('private-native-diagnostic'),
        const CaptionRefused('private-native-diagnostic'),
      ]) {
        final EntryCaptionObserver original = observer()..hold(failure);
        expect(original.publicFailureCode, 'CAPTION_HELD');
      }
      expect(native.calls, isEmpty);
    },
  );

  testWidgets('deep body ancestry retains the original caption owner', (
    WidgetTester tester,
  ) async {
    Widget body = const SizedBox.shrink();
    for (int depth = 0; depth < 300; depth++) {
      body = KeyedSubtree(child: body);
    }
    await mount(tester, body: body);
    final AppWindowFrameState frame = tester.state<AppWindowFrameState>(
      find.byType(AppWindowFrame),
    );
    final Object owner = frame.windowStatus!.owner;
    final Map<String, Object?> result = await observer().bind();
    expect(result['original'], isTrue);
    expect(result['settled'], isTrue);
    expect(result['stage'], 0);
    expect(frame.windowStatus!.owner, same(owner));
  }, variant: _windows);

  testWidgets('total tree capacity refuses before native caption observation', (
    WidgetTester tester,
  ) async {
    await mount(
      tester,
      body: Stack(
        children: List<Widget>.filled(8192, const SizedBox.shrink()),
      ),
    );
    native.calls.clear();
    final EntryCaptionObserver original = observer();
    await _refusal<CaptionRefused>(original.bind());
    expect(original.publicFailureCode, 'CAPTION_TREE_CAPACITY_REFUSED');
    expect(native.calls, isEmpty);
  }, variant: _windows);

  testWidgets('synthetic four observations retain the original frame owner', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    final AppWindowFrameState frame = tester.state<AppWindowFrameState>(
      find.byType(AppWindowFrame),
    );
    final Object owner = frame.windowStatus!.owner;
    final EntryCaptionObserver original = observer();
    await throughMinimize(original);
    await original.ordinaryRestore(() {
      native.minimized = false;
      return Future<void>.value();
    });
    final Map<String, Object?> result = await original.observe();
    expect(result['stage'], 4);
    expect(result['observations'], 4);
    expect(result['settled'], isTrue);
    expect(frame.windowStatus!.owner, same(owner));
    original.requireGeometryRestore();
    expect(
      original.requireGeometryRestore,
      throwsA(isA<CaptionRefused>()),
    );
    expect(
      native.calls.where((String call) => call == 'maximize'),
      hasLength(1),
    );
    expect(
      native.calls.where((String call) => call == 'unmaximize'),
      hasLength(1),
    );
    expect(
      native.calls.where((String call) => call == 'minimize'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  for (final bool reportRelease in <bool>[false, true]) {
    testWidgets(
      'synthetic missing immediate pending holds, '
      'release=$reportRelease',
      (WidgetTester tester) async {
        await mount(tester);
        final EntryCaptionObserver original = observer(
          dispatch: false,
          reportRelease: reportRelease,
        );
        await original.bind();
        await _refusal<CaptionRefused>(original.tap('maximize'));
        await _refusal<CaptionRefused>(original.observe());
        expect(native.calls, isNot(contains('maximize')));
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: _windows,
    );
  }

  for (final int stage in <int>[1, 2]) {
    testWidgets(
      'synthetic stage $stage waits for the next enabled control',
      (WidgetTester tester) async {
        await mount(tester);
        final AppWindowFrameState frame = tester.state<AppWindowFrameState>(
          find.byType(AppWindowFrame),
        );
        final Object owner = frame.windowStatus!.owner;
        final EntryCaptionObserver original = observer();
        await original.bind();
        if (stage == 2) {
          await original.tap('maximize');
          await _microtasks();
          await tester.pump();
          expect((await settled(original))['observations'], 1);
        }

        final Completer<void> held = Completer<void>();
        final String action = stage == 1 ? 'maximize' : 'restore';
        final String nextAction = stage == 1 ? 'restore' : 'minimize';
        final String nextMethod = stage == 1 ? 'unmaximize' : 'minimize';
        final String nextKey = stage == 1
            ? 'window-maximize'
            : 'window-minimize';
        if (stage == 1) {
          native.holdMaximize = held;
        } else {
          native.holdUnmaximize = held;
        }
        final Finder nextControl = find.descendant(
          of: find.byKey(ValueKey<String>(nextKey)),
          matching: find.byType(IconButton),
        );
        final Element button = tester.element(nextControl);
        expect((button.widget as IconButton).onPressed, isNotNull);
        await original.tap(action);
        await tester.pump(); // Paint the original disabled callback.
        expect(frame.windowStatus!.actionPending, isTrue);
        expect((button.widget as IconButton).onPressed, isNull);
        expect((await original.observe())['pending'], isTrue);

        held.complete();
        for (int i = 0; i < 32; i++) {
          await _microtasks(); // Drain only; supply no painted frame.
          if (!frame.windowStatus!.actionPending &&
              !frame.windowStatus!.queryPending) {
            break;
          }
        }
        expect(frame.windowStatus!.owner, same(owner));
        expect(frame.windowStatus!.actionPending, isFalse);
        expect(frame.windowStatus!.queryPending, isFalse);
        expect(native.maximized, stage == 1);
        expect(tester.element(nextControl), same(button));
        expect((button.widget as IconButton).onPressed, isNull);
        for (int i = 0; i < 3; i++) {
          final Map<String, Object?> waiting = await original.observe();
          expect(waiting['stage'], stage);
          expect(waiting['observations'], stage - 1);
          expect(waiting['pending'], isFalse);
          expect(waiting['settled'], isFalse);
          expect(waiting['held'], isFalse);
          expect(waiting['original'], isTrue);
        }
        expect(native.calls, isNot(contains(nextMethod)));

        await tester.pump(); // Rebuild the same original enabled control.
        expect(tester.element(nextControl), same(button));
        expect((button.widget as IconButton).onPressed, isNotNull);
        final Map<String, Object?> ready = await original.observe();
        expect(ready['settled'], isTrue);
        expect(ready['observations'], stage);
        expect(ready['held'], isFalse);
        expect(frame.windowStatus!.owner, same(owner));
        await original.tap(nextAction);
        await _microtasks();
        expect(
          native.calls.where((String call) => call == nextMethod),
          hasLength(1),
        );
        await _refusal<CaptionRefused>(original.tap(nextAction));
        expect(
          native.calls.where((String call) => call == nextMethod),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: _windows,
    );
  }

  testWidgets('synthetic pending minimize completes without another paint', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    final EntryCaptionObserver original = observer();
    await original.bind();
    for (final String action in <String>['maximize', 'restore']) {
      await original.tap(action);
      await _microtasks();
      expect((await settled(original))['settled'], isTrue);
    }
    native.holdMinimize = Completer<void>();
    await original.tap('minimize');
    await tester.pump(); // Paint disabled controls while minimize is held.
    final Element minimize = tester.element(
      find.descendant(
        of: find.byKey(const ValueKey<String>('window-minimize')),
        matching: find.byType(IconButton),
      ),
    );
    expect((minimize.widget as IconButton).onPressed, isNull);
    expect((await original.observe())['pending'], isTrue);
    native.holdMinimize!.complete();
    await _microtasks(); // Deliberately no pump or painted-frame completion.
    final Map<String, Object?> minimized = await settled(original);
    expect((minimize.widget as IconButton).onPressed, isNull);
    expect(minimized['settled'], isTrue);
    expect(minimized['window'], <String, Object?>{
      'minimized': true,
      'maximized': false,
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic native action failure permanently holds restore', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    final EntryCaptionObserver original = observer();
    await original.bind();
    native.failMaximize = true;
    await original.tap('maximize');
    await _microtasks();
    await _refusal<CaptionRefused>(original.observe());
    await _refusal<CaptionRefused>(original.tap('restore'));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic frame replacement cannot adopt the new controller', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    final EntryCaptionObserver original = observer();
    await original.bind();
    await tester.pumpWidget(
      _host(frameKey: const ValueKey<String>('replacement')),
    );
    await tester.pump();
    await _refusal<CaptionRefused>(original.tap('maximize'));
    expect(native.calls, isNot(contains('maximize')));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic duplicate keyed controls refuse before dispatch', (
    WidgetTester tester,
  ) async {
    await mount(tester, duplicate: true);
    final EntryCaptionObserver original = observer();
    await _refusal<CaptionRefused>(original.bind());
    expect(native.calls, isNot(contains('maximize')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic failed mode query leaves the control disabled', (
    WidgetTester tester,
  ) async {
    native.failQuery = true;
    await mount(tester);
    final EntryCaptionObserver original = observer();
    await _refusal<CaptionRefused>(original.bind());
    expect(native.calls, isNot(contains('maximize')));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic native mismatch cannot advance or replay a tap', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    final EntryCaptionObserver original = observer();
    await original.bind();
    native.changeMode = false;
    await original.tap('maximize');
    await _microtasks();
    final Map<String, Object?> result = await original.observe();
    expect(result['settled'], isFalse);
    expect(result['observations'], 0);
    await _refusal<CaptionRefused>(original.tap('restore'));
    expect(
      native.calls.where((String call) => call == 'maximize'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic ordinary restore retains its exact original Future', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    final EntryCaptionObserver original = observer();
    await throughMinimize(original);
    final Completer<void> nativeRestore = Completer<void>();
    final Future<Map<String, Object?>> pending = original.ordinaryRestore(
      () => nativeRestore.future,
    );
    await _microtasks();
    expect(original.originalRestoreForTest, same(nativeRestore.future));
    expect((await original.observe())['pending'], isTrue);
    native.minimized = false;
    nativeRestore.complete();
    await pending;
    expect(original.originalRestoreForTest, same(nativeRestore.future));
    expect((await original.observe())['observations'], 4);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('synthetic absolute timeout never replaces a late restore', (
    WidgetTester tester,
  ) async {
    await mount(tester);
    Duration elapsed = Duration.zero;
    final EntryCaptionObserver original = observer(elapsed: () => elapsed);
    await throughMinimize(original);
    final Completer<void> nativeRestore = Completer<void>();
    final Future<void> refusal = _refusal<CaptionRefused>(
      original.ordinaryRestore(() => nativeRestore.future),
    );
    await _microtasks();
    expect(original.originalRestoreForTest, same(nativeRestore.future));
    elapsed = const Duration(seconds: 21);
    native.minimized = false;
    nativeRestore.complete();
    await refusal;
    expect(original.originalRestoreForTest, same(nativeRestore.future));
    await _refusal<CaptionRefused>(original.observe());
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  for (final bool resized in <bool>[false, true]) {
    testWidgets(
      resized
          ? 'real caption pointer waits for resized layout before targeting'
          : 'real PointerUp wiring observes pending before another paint',
      (
        WidgetTester tester,
      ) async {
        await mount(tester);
        native.holdMaximize = Completer<void>();
        final HarnessAgent agent = HarnessAgent.forTest();
        final Element button = tester.element(
          find.descendant(
            of: find.byKey(const ValueKey<String>('window-maximize')),
            matching: find.byType(IconButton),
          ),
        );
        final AppWindowFrameState frame = tester.state<AppWindowFrameState>(
          find.byType(AppWindowFrame),
        );
        if (resized) {
          // Queue metrics without a paint; the old caption is outside the view.
          tester.view.physicalSize = const Size(960, 780);
        }
        bool released = false;
        bool releaseEntered = false;
        bool complete = false;
        Object? failure;
        StackTrace? failureStack;
        final Future<void> original = agent.tapCaptionForTest(
          button,
          () {
            expectSync(frame.windowStatus!.actionPending, isFalse);
          },
          () {
            releaseEntered = true;
            expectSync(frame.windowStatus!.actionPending, isTrue);
            released = true;
          },
        );
        unawaited(
          original.then<void>(
            (_) {
              complete = true;
            },
            onError: (Object error, StackTrace stack) {
              failure = error;
              failureStack = stack;
              complete = true;
            },
          ),
        );
        for (int i = 0; i < 80 && !released && !complete; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        final Object? beforeReleaseFailure = failure;
        final Object? beforeReleaseCause =
            beforeReleaseFailure is CaptionRefused
            ? beforeReleaseFailure.code
            : beforeReleaseFailure;
        expect(
          beforeReleaseFailure,
          isNull,
          reason: '$beforeReleaseCause\n$failureStack',
        );
        expect(
          released,
          isTrue,
          reason:
              'Release entered: $releaseEntered; '
              'original completion: $complete; native calls: ${native.calls}',
        );
        // Supply no frame after observing the original release.
        await _microtasks();
        expect(complete, isTrue);
        expect(failure, isNull);
        native.holdMaximize!.complete();
        await _microtasks();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
      variant: _windows,
    );
  }
}
