import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/shaders/shader_clock.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

const MethodChannel _window = MethodChannel('window_manager');

class _Probe extends StatefulWidget {
  const _Probe({required this.onReady, required this.active});

  final ValueChanged<ShaderClock> onReady;
  final bool active;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  late final ShaderClock clock;

  @override
  void initState() {
    super.initState();
    clock = ShaderClock(vsync: this)..active = widget.active;
    widget.onReady(clock);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    clock.updateVisibility(context);
  }

  @override
  void didUpdateWidget(_Probe oldWidget) {
    super.didUpdateWidget(oldWidget);
    clock.active = widget.active;
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _host(
  ValueChanged<ShaderClock> onReady, {
  bool enabled = true,
  bool active = true,
  bool disableAnimations = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: TickerMode(
      enabled: enabled,
      child: _Probe(onReady: onReady, active: active),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool focused = true;

  setUp(() {
    focused = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (MethodCall call) async {
          if (call.method == 'isFocused') return focused;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
    expect(FrostHold.count.value, 0);
  });

  testWidgets('one clock advances by visible time and stops when inactive', (
    WidgetTester tester,
  ) async {
    late ShaderClock clock;
    void ready(ShaderClock value) => clock = value;
    await tester.pumpWidget(_host(ready));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(clock.value, closeTo(0.12, 0.000001));
    expect(clock.isRunning, isTrue);
    expect(tester.binding.transientCallbackCount, 1);

    await tester.pumpWidget(_host(ready, active: false));
    expect(clock.isRunning, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    final double held = clock.value;
    await tester.pump(const Duration(seconds: 30));
    expect(clock.value, held);
  });

  testWidgets('TickerMode stops scheduling and resuming excludes hidden time', (
    WidgetTester tester,
  ) async {
    late ShaderClock clock;
    void ready(ShaderClock value) => clock = value;
    await tester.pumpWidget(_host(ready));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_host(ready, enabled: false));
    final double held = clock.value;
    expect(clock.isRunning, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 90));
    expect(clock.value, held);

    await tester.pumpWidget(_host(ready));
    await tester.pump();
    expect(clock.value, held);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clock.value, closeTo(held + 0.1, 0.000001));
  });

  testWidgets('a window blur holds the clock until focus returns', (
    WidgetTester tester,
  ) async {
    late ShaderClock clock;
    await tester.pumpWidget(_host((ShaderClock value) => clock = value));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    clock.onWindowBlur();
    final double held = clock.value;
    expect(clock.isRunning, isFalse);
    await tester.pump(const Duration(minutes: 2));
    expect(clock.value, held);

    clock.onWindowFocus();
    await tester.pump();
    expect(clock.value, held);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clock.value, closeTo(held + 0.1, 0.000001));
  });

  testWidgets('an initially unfocused window does not keep scheduling', (
    WidgetTester tester,
  ) async {
    focused = false;
    late ShaderClock clock;
    await tester.pumpWidget(_host((ShaderClock value) => clock = value));
    await tester.pump();
    expect(clock.isRunning, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(clock.value, 0);
  });

  testWidgets('a stale startup focus answer cannot undo a newer blur', (
    WidgetTester tester,
  ) async {
    final Completer<bool> answer = Completer<bool>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _window,
      (MethodCall call) => answer.future,
    );
    late ShaderClock clock;
    await tester.pumpWidget(_host((ShaderClock value) => clock = value));
    clock.onWindowBlur();
    answer.complete(true);
    await tester.pump();
    expect(clock.isRunning, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('nested frosts release the clock only after the last closes', (
    WidgetTester tester,
  ) async {
    late ShaderClock clock;
    await tester.pumpWidget(_host((ShaderClock value) => clock = value));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    FrostHold.acquire();
    FrostHold.acquire();
    addTearDown(() {
      while (FrostHold.count.value > 0) {
        FrostHold.release();
      }
    });
    final double held = clock.value;
    expect(clock.isRunning, isFalse);
    FrostHold.release();
    expect(clock.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 20));
    expect(clock.value, held);
    FrostHold.release();
    await tester.pump();
    expect(clock.value, held);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clock.value, closeTo(held + 0.1, 0.000001));
  });

  testWidgets('background lifecycle holds the clock independently of focus', (
    WidgetTester tester,
  ) async {
    late ShaderClock clock;
    await tester.pumpWidget(_host((ShaderClock value) => clock = value));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    clock
      ..didChangeAppLifecycleState(AppLifecycleState.paused)
      ..onWindowFocus();
    final double held = clock.value;
    expect(clock.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 60));
    expect(clock.value, held);
    clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(clock.value, held);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clock.value, closeTo(held + 0.1, 0.000001));
  });

  testWidgets('both animation-effects flags leave the visible clock running', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    late ShaderClock clock;
    await tester.pumpWidget(
      _host(
        (ShaderClock value) => clock = value,
        disableAnimations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(clock.isRunning, isTrue);
    expect(clock.value, closeTo(0.4, 0.000001));
  });

  testWidgets('dispose releases scheduled frames and late focus answers', (
    WidgetTester tester,
  ) async {
    final Completer<bool> answer = Completer<bool>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _window,
      (MethodCall call) => answer.future,
    );
    await tester.pumpWidget(_host((ShaderClock value) {}));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    answer.complete(true);
    await tester.pump();
    FrostHold.acquire();
    FrostHold.release();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
