import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as widgets
    show OverlayPortal, OverlayPortalController;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../harness/app/agent.dart';

class _PaletteIntent extends Intent {
  const _PaletteIntent();
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
  expect(done, isTrue, reason: 'the harness command did not finish');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result as T;
}

void main() {
  testWidgets('painted portal options escape only the caller scroll clip', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
    for (final Brightness brightness in <Brightness>[
      Brightness.dark, Brightness.light,
    ]) {
      final widgets.OverlayPortalController portal =
          widgets.OverlayPortalController();
      int selected = 0;
      int clipped = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: brightness, platform: TargetPlatform.windows,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320, height: 80,
              child: SingleChildScrollView(
                child: Column(children: <Widget>[
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Synthetic field',
                      suffixIcon: widgets.OverlayPortal(
                        controller: portal,
                        overlayChildBuilder: (BuildContext context) =>
                            Positioned(
                          left: 16, top: 140, width: 240, height: 48,
                          child: TextButton(
                            key: const Key('portal_option'),
                            onPressed: () {
                              selected++;
                              portal.hide();
                            },
                            child: const Text('Synthetic popup option'),
                          ),
                        ),
                        child: IconButton(
                          key: const Key('portal_open'),
                          onPressed: portal.show,
                          icon: const Icon(Icons.arrow_drop_down),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 200),
                  TextButton(
                    onPressed: () => clipped++,
                    child: const Text('Clipped original control'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await _drive(tester, agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'key': 'portal_open', 'settleMs': 0,
      }));
      expect(portal.isShowing, isTrue);
      expect(find.text('Synthetic popup option').hitTestable(), findsOneWidget);
      expect(find.text('Clipped original control').hitTestable(), findsNothing);
      await _drive(tester, agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'text': 'Synthetic popup option',
        'exact': true, 'settleMs': 0,
      }));
      expect(selected, 1);
      expect(portal.isShowing, isFalse);
      await expectLater(agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'text': 'Clipped original control', 'exact': true,
      }), throwsA(isA<HarnessError>()));
      expect(clipped, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('a client edge tap clears another mouse tooltip without drag', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final HarnessAgent agent = HarnessAgent.forTest();
    int drags = 0;
    const String message = 'Synthetic checksum tooltip';
    for (final Brightness brightness in <Brightness>[
      Brightness.dark, Brightness.light,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Positioned(
                  top: 0, left: 0, right: 0, height: 32,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => drags++,
                    child: const SizedBox.expand(),
                  ),
                ),
                const Center(
                  child: Tooltip(
                    message: message,
                    child: Text('Synthetic hash target'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 7,
      );
      await mouse.addPointer(
        location: tester.getCenter(find.text('Synthetic hash target')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(message), findsOneWidget);
      await _drive(tester, agent.commandForTest(<String, dynamic>{
        'cmd': 'hover', 'at': <int>[0, 0], 'settleMs': 0,
      }));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(message), findsOneWidget);
      await _drive(tester, agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'at': <int>[0, 779], 'settleMs': 0,
      }));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(message), findsNothing);
      expect(drags, 0);
      // The original caption location is a non-inert negative control.
      await _drive(tester, agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'at': <int>[0, 0], 'settleMs': 0,
      }));
      expect(drags, greaterThan(0));
      drags = 0;
      await mouse.removePointer();
      await tester.pump();
    }
  });

  testWidgets('chords reach focused Shortcuts exactly once and release keys', (
    WidgetTester tester,
  ) async {
    final HarnessAgent agent = HarnessAgent.forTest();
    int opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _PaletteIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PaletteIntent: CallbackAction<_PaletteIntent>(
                onInvoke: (_) {
                  opened++;
                  return null;
                },
              ),
            },
            child: const Focus(autofocus: true, child: Text('Shortcut target')),
          ),
        ),
      ),
    );
    await tester.pump();
    final Map<String, Object?> response = await _drive(
      tester,
      agent.commandForTest(<String, dynamic>{'cmd': 'key', 'key': 'ctrl+k'}),
    );
    expect(response['handled'], isTrue);
    expect(opened, 1);
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'key',
        'key': 'ctrl+unknown',
      }),
      throwsA(isA<HarnessError>()),
    );
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
  });

  testWidgets('text selection, traversal and Enter retain the desktop paths', (
    WidgetTester tester,
  ) async {
    final HarnessAgent agent = HarnessAgent.forTest();
    final TextEditingController controller = TextEditingController(
      text: 'sample',
    );
    final FocusNode first = FocusNode();
    final FocusNode second = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    int submitted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              TextField(
                controller: controller,
                focusNode: first,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  submitted++;
                },
              ),
              TextField(focusNode: second),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await _drive(
      tester,
      agent.commandForTest(<String, dynamic>{
        'cmd': 'key',
        'key': 'ctrl+a',
      }),
    );
    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.text.length);
    await _drive(
      tester,
      agent.commandForTest(<String, dynamic>{'cmd': 'key', 'key': 'tab'}),
    );
    expect(second.hasFocus, isTrue);
    await _drive(
      tester,
      agent.commandForTest(<String, dynamic>{'cmd': 'key', 'key': 'shift+tab'}),
    );
    expect(first.hasFocus, isTrue);
    await _drive(
      tester,
      agent.commandForTest(<String, dynamic>{'cmd': 'key', 'key': 'enter'}),
    );
    expect(submitted, 1);
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'drop messages retain order, physical coordinates and file payload',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(2560, 1560);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final HarnessAgent agent = HarnessAgent.forTest();
      final Directory scratch = Directory.systemTemp.createTempSync(
        'syrius-harness-drop-',
      );
      addTearDown(() {
        scratch.deleteSync(recursive: true);
      });
      final File file = File('${scratch.path}/fixture.txt')
        ..writeAsStringSync('fixture');
      final List<MethodCall> calls = <MethodCall>[];
      const StandardMethodCodec codec = StandardMethodCodec();
      ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
        'desktop_drop',
        (ByteData? data) async {
          calls.add(codec.decodeMethodCall(data));
          return codec.encodeSuccessEnvelope(null);
        },
      );
      addTearDown(() {
        ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
          'desktop_drop',
          null,
        );
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 100,
                top: 120,
                width: 200,
                height: 100,
                child: GestureDetector(
                  key: const ValueKey<String>('drop_target'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
            ],
          ),
        ),
      );
      await _drive(
        tester,
        agent.commandForTest(<String, dynamic>{
          'cmd': 'drop',
          'key': 'drop_target',
          'path': file.path,
        }),
      );
      expect(calls.map((MethodCall c) => c.method).toList(), <String>[
        'entered',
        'updated',
        'performOperation',
      ]);
      expect(calls[0].arguments, <double>[400, 340]);
      expect(calls[1].arguments, <double>[400, 340]);
      expect(calls[2].arguments, <String>[file.path]);
    },
  );

  testWidgets(
    'rich tooltip semantics and explicit tooltips remain plain selectors',
    (WidgetTester tester) async {
      final HarnessAgent agent = HarnessAgent.forTest();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                Tooltip(
                  richMessage: const TextSpan(
                    text: '',
                    semanticsLabel: 'Home Ctrl+1',
                    children: <InlineSpan>[
                      TextSpan(text: 'Home '),
                      WidgetSpan(child: Text('Ctrl+1')),
                    ],
                  ),
                  excludeFromSemantics: true,
                  child: IconButton(
                    key: const ValueKey<String>('nav_home_test'),
                    onPressed: () {},
                    icon: const Icon(Icons.home),
                  ),
                ),
                Tooltip(
                  message: 'Visual tooltip',
                  child: Semantics(
                    tooltip: 'Explicit tooltip Ctrl+2',
                    child: IconButton(
                      key: const ValueKey<String>('nav_explicit_test'),
                      onPressed: () {},
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final Map<String, Object?> tree = await agent.commandForTest(
        <String, dynamic>{'cmd': 'tree'},
      );
      final List<Map<String, Object?>> nodes =
          tree['nodes']! as List<Map<String, Object?>>;
      expect(
        nodes.firstWhere(
          (Map<String, Object?> n) => n['key'] == 'nav_home_test',
        )['tip'],
        'Home Ctrl+1',
      );
      expect(
        nodes.firstWhere(
          (Map<String, Object?> n) => n['key'] == 'nav_explicit_test',
        )['tip'],
        'Explicit tooltip Ctrl+2',
      );
      expect(nodes.toString(), isNot(contains('\uFFFC')));
    },
  );

  testWidgets('assert refuses missing, covered and error states', (
    WidgetTester tester,
  ) async {
    final HarnessAgent agent = HarnessAgent.forTest();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Target marker')),
        ),
      ),
    );
    expect(
      (await agent.commandForTest(<String, dynamic>{
        'cmd': 'assert',
        'text': 'Target marker',
      }))['asserted'],
      isTrue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              const Center(child: Text('Target marker')),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'assert',
        'text': 'Target marker',
      }),
      throwsA(isA<HarnessError>()),
    );
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'assert',
        'text': 'Missing marker',
      }),
      throwsA(isA<HarnessError>()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const Text('Target marker'),
              SizedBox(
                width: 100,
                height: 100,
                child: ErrorWidget('Expected fixture error'),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      agent.commandForTest(<String, dynamic>{
        'cmd': 'assert',
        'text': 'Target marker',
      }),
      throwsA(isA<HarnessError>()),
    );
  });
}
