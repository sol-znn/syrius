import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/client_window.dart';

const MethodChannel _channel = MethodChannel('window_manager');
const Size _initialOuter = Size(1200, 788);
const Size _requestedClient = Size(1280, 780);

// Only the native window channel is simulated. The agent reads the actual
// widget-test RenderView, including its layout and FlutterView metrics. These
// fixtures establish adapter behavior, not Windows desktop or native receipts.
class _NativeWindow {
  _NativeWindow(this.tester);

  final WidgetTester tester;
  final List<String> methods = <String>[];
  final List<Size> requests = <Size>[];
  Size outer = _initialOuter;
  Size maximum = _initialOuter;
  Offset position = const Offset(80, 90);
  bool publishMetrics = true;
  bool failMaximum = false;
  double? clientWidthLimit;
  Completer<void>? maximumReply;

  Size get client {
    final double width = outer.width - 16;
    final double? limit = clientWidthLimit;
    return Size(
      limit != null && width > limit ? limit : width,
      outer.height - 39,
    );
  }

  void publish() {
    tester.view.physicalSize = client * tester.view.devicePixelRatio;
  }

  Future<Object?> call(MethodCall method) async {
    methods.add(method.method);
    final Map<Object?, Object?> args = method.arguments == null
        ? <Object?, Object?>{}
        : Map<Object?, Object?>.from(method.arguments as Map<Object?, Object?>);
    switch (method.method) {
      case 'ensureInitialized':
        return null;
      case 'setMaximumSize':
        if (failMaximum) throw PlatformException(code: 'tracking-refused');
        if (maximumReply != null) await maximumReply!.future;
        maximum = Size(
          (args['width']! as num).toDouble(),
          (args['height']! as num).toDouble(),
        );
        return null;
      case 'getBounds':
        return <String, double>{
          'x': position.dx,
          'y': position.dy,
          'width': outer.width,
          'height': outer.height,
        };
      case 'setBounds':
        if (args['width'] != null && args['height'] != null) {
          final Size requested = Size(
            (args['width']! as num).toDouble(),
            (args['height']! as num).toDouble(),
          );
          requests.add(requested);
          outer = Size(
            requested.width.clamp(1, maximum.width).toDouble(),
            requested.height.clamp(1, maximum.height).toDouble(),
          );
          if (publishMetrics) publish();
        }
        if (args['x'] != null && args['y'] != null) {
          position = Offset(
            (args['x']! as num).toDouble(),
            (args['y']! as num).toDouble(),
          );
        }
        return null;
      case 'isMinimized':
      case 'isMaximized':
        return false;
      case 'show':
      case 'focus':
      case 'restore':
        return null;
      default:
        throw StateError('unexpected fixture window command');
    }
  }
}

Future<_NativeWindow> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final _NativeWindow native = _NativeWindow(tester)..publish();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _channel,
    native.call,
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    );
  });
  await tester.pumpWidget(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.expand(),
    ),
  );
  expect(tester.binding.renderViews.single.attached, isTrue);
  return native;
}

Future<T> _drive<T>(WidgetTester tester, Future<T> command) async {
  bool done = false;
  T? result;
  Object? failure;
  StackTrace? trace;
  unawaited(
    command.then(
      (T value) {
        result = value;
        done = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    ),
  );
  for (int i = 0; i < 80 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'the original window command did not finish');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result as T;
}

Future<Object> _refusal<T>(WidgetTester tester, Future<T> command) async {
  try {
    await _drive(tester, command);
  } on Object catch (error) {
    return error;
  }
  fail('The original window command must refuse');
}

Future<Map<String, Object?>> _resize(HarnessAgent agent) =>
    agent.commandForTest(<String, dynamic>{
      'cmd': 'window',
      'do': 'show',
      'width': 1280,
      'height': 780,
    });

Matcher _unobserved(Size client) => isA<HarnessError>().having(
  (HarnessError error) => error.detail,
  'measured client refusal',
  allOf(
    containsPair('client', <double>[client.width, client.height]),
    containsPair('requestedClient', <double>[1280, 780]),
    containsPair('clientMatched', false),
    containsPair('resizeAttempts', 5),
  ),
);

void _expectView(WidgetTester tester, Size expected) {
  final RenderView view = tester.binding.renderViews.single;
  final ClientMetrics metrics = ClientMetrics(
    view.flutterView.physicalSize,
    view.flutterView.devicePixelRatio,
  );
  expect(metrics.logicalSize, expected);
  expect(view.size, expected);
}

void main() {
  testWidgets('default tracking clamp refuses the measured client', (
    WidgetTester tester,
  ) async {
    final _NativeWindow native = await _mount(tester);
    final HarnessAgent agent = HarnessAgent.forTest();
    expect(
      await _refusal(tester, _resize(agent)),
      _unobserved(const Size(1184, 749)),
    );
    expect(native.requests, hasLength(5));
    expect(native.outer, _initialOuter);
    expect(native.methods, isNot(contains('setMaximumSize')));
    _expectView(tester, const Size(1184, 749));
    expect(agent.captureFrameForTest, isNull);
  });

  testWidgets('startup tracking permits an exact client and original restore', (
    WidgetTester tester,
  ) async {
    final _NativeWindow native = await _mount(tester);
    final HarnessAgent agent = HarnessAgent.forTest();
    await configureHarnessWindowTracking();
    expect(native.methods, <String>['ensureInitialized', 'setMaximumSize']);
    expect(
      native.maximum,
      const Size(harnessMaximumOuterExtent, harnessMaximumOuterExtent),
    );
    expect(native.requests, isEmpty);
    final Map<String, Object?> original = await agent.commandForTest(
      <String, dynamic>{'cmd': 'window'},
    );
    final Map<String, Object?> response = await _drive(tester, _resize(agent));
    expect(response['clientMatched'], isTrue);
    expect(response['client'], <double>[1280, 780]);
    expect(response['physical'], <double>[1280, 780]);
    expect(response['devicePixelRatio'], 1);
    expect(native.requests, <Size>[const Size(1296, 819)]);
    _expectView(tester, _requestedClient);
    final Map<String, Object?> restored = await _drive(
      tester,
      agent.commandForTest(<String, dynamic>{
        'cmd': 'window',
        'restoreState': original,
      }),
    );
    expect(restored['restored'], isTrue);
    expect(restored['window'], original['window']);
    expect(restored['client'], original['client']);
    _expectView(tester, const Size(1184, 749));
    expect(agent.captureFrameForTest, isNull);
  });

  testWidgets(
    'tracking allowance cannot substitute for delayed Flutter metrics',
    (
      WidgetTester tester,
    ) async {
      final _NativeWindow native = await _mount(tester);
      native.publishMetrics = false;
      final HarnessAgent agent = HarnessAgent.forTest();
      await configureHarnessWindowTracking();
      expect(
        await _refusal(tester, _resize(agent)),
        _unobserved(const Size(1184, 749)),
      );
      expect(native.requests, hasLength(5));
      expect(native.outer.width, greaterThan(1280));
      _expectView(tester, const Size(1184, 749));
      expect(agent.captureFrameForTest, isNull);
    },
  );

  testWidgets('tracking allowance never rounds a one-pixel client mismatch', (
    WidgetTester tester,
  ) async {
    final _NativeWindow native = await _mount(tester);
    native.clientWidthLimit = 1279;
    final HarnessAgent agent = HarnessAgent.forTest();
    await configureHarnessWindowTracking();
    expect(
      await _refusal(tester, _resize(agent)),
      _unobserved(const Size(1279, 780)),
    );
    expect(native.requests, hasLength(5));
    _expectView(tester, const Size(1279, 780));
    expect(agent.captureFrameForTest, isNull);
  });

  testWidgets('startup awaits the original maximum-tracking reply', (
    WidgetTester tester,
  ) async {
    final _NativeWindow native = await _mount(tester);
    final Completer<void> reply = Completer<void>();
    native.maximumReply = reply;
    bool continued = false;
    final Future<bool> startup = configureHarnessWindowTracking().then((_) {
      continued = true;
      return true;
    });
    await tester.pump();
    expect(native.methods, <String>['ensureInitialized', 'setMaximumSize']);
    expect(continued, isFalse);
    expect(native.requests, isEmpty);
    reply.complete();
    expect(await _drive(tester, startup), isTrue);
    expect(continued, isTrue);
  });

  testWidgets('refused tracking configuration prevents startup continuation', (
    WidgetTester tester,
  ) async {
    final _NativeWindow native = await _mount(tester);
    native.failMaximum = true;
    bool continued = false;
    final Future<bool> startup = configureHarnessWindowTracking().then((_) {
      continued = true;
      return true;
    });
    expect(await _refusal(tester, startup), isA<PlatformException>());
    expect(continued, isFalse);
    expect(native.methods, <String>['ensureInitialized', 'setMaximumSize']);
    expect(native.requests, isEmpty);
  });
}
