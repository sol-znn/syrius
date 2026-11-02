import 'dart:async';
import 'dart:ui' show FlutterView, SemanticsAction, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart' show SemanticsData, SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/window_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/window_frame.dart';

// Each registration selects one platform and keeps its existing description.
class _PlatformVariant extends TargetPlatformVariant {
  const _PlatformVariant(super.values);

  @override
  String describeValue(TargetPlatform value) => '';
}

const TargetPlatformVariant _windows = _PlatformVariant(
  <TargetPlatform>{TargetPlatform.windows},
);

class _OwnerScope extends InheritedWidget {
  const _OwnerScope({required this.owner, required super.child});

  final Object owner;

  @override
  bool updateShouldNotify(_OwnerScope oldWidget) =>
      !identical(owner, oldWidget.owner);
}

class _OwnedPage extends StatefulWidget {
  const _OwnedPage();

  @override
  State<_OwnedPage> createState() => _OwnedPageState();
}

class _OwnedPageState extends State<_OwnedPage> {
  final TextEditingController text = TextEditingController();
  Object? suppliedOwner;
  Size? bodySize;
  BoxConstraints? bodyConstraints;
  TextDirection? bodyDirection;
  int disposals = 0;

  @override
  Widget build(BuildContext context) {
    suppliedOwner = context
        .dependOnInheritedWidgetOfExactType<_OwnerScope>()!
        .owner;
    bodySize = MediaQuery.sizeOf(context);
    bodyDirection = Directionality.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          bodyConstraints = constraints;
          return Center(
            child: SizedBox(
              key: const ValueKey<String>('body-center'),
              width: 240,
              height: 80,
              child: TextField(controller: text),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    disposals++;
    text.dispose();
    super.dispose();
  }
}

class _Routes extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];
  final List<Route<dynamic>?> previous = <Route<dynamic>?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    previous.add(previousRoute);
  }
}

void main() {
  const MethodChannel channel = MethodChannel('window_manager');
  final List<MethodCall> nativeCalls = <MethodCall>[];
  bool maximized = false;
  bool queryFailure = false;
  bool effectChangesMode = false;
  final Map<String, Completer<Object?>> pending =
      <String, Completer<Object?>>{};

  setUp(() {
    nativeCalls.clear();
    pending.clear();
    maximized = false;
    queryFailure = false;
    effectChangesMode = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          nativeCalls.add(call);
          if (pending.containsKey(call.method)) {
            return pending[call.method]!.future;
          }
          if (call.method == 'isFullScreen') {
            return false;
          }
          if (call.method == 'isMaximized') {
            if (queryFailure) {
              throw PlatformException(
                code: 'synthetic',
                message: 'Private test text',
              );
            }
            return maximized;
          }
          if (effectChangesMode && call.method == 'maximize') {
            maximized = true;
          }
          if (effectChangesMode && call.method == 'unmaximize') {
            maximized = false;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    final AppWindowStatus? status = tester
        .state<AppWindowFrameState>(find.byType(AppWindowFrame))
        .windowStatus;
    expect(status?.queryPending ?? false, isFalse);
    expect(status?.actionPending ?? false, isFalse);
  }

  Future<_OwnedPageState> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 780),
    Brightness brightness = Brightness.dark,
    Locale locale = const Locale('en'),
    GlobalKey<NavigatorState>? navigator,
    NavigatorObserver? observer,
    Object? owner,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _OwnerScope(
        owner: owner ?? Object(),
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: <NavigatorObserver>[?observer],
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          builder: (BuildContext context, Widget? child) =>
              // Keep the production MUI bridge around the supplied Navigator.
              // ignore: deprecated_member_use
              MaterialUiCompatibilityBridge(
                child: AppWindowFrame(child: child!),
              ),
          home: const _OwnedPage(),
        ),
      ),
    );
    await settle(tester);
    return tester.state<_OwnedPageState>(find.byType(_OwnedPage));
  }

  Finder control(String key) => find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(IconButton),
  );

  testWidgets(
    'Windows initialization awaits hidden style on the original channel',
    (WidgetTester tester) async {
      final Completer<Object?> style = Completer<Object?>();
      pending['setTitleBarStyle'] = style;
      bool settled = false;
      final Future<void> original = configureAppWindowChrome().then((_) {
        settled = true;
      });
      await tester.pump();
      expect(settled, isFalse);
      expect(nativeCalls.single.method, 'setTitleBarStyle');
      expect(nativeCalls.single.arguments, <String, Object>{
        'titleBarStyle': 'hidden',
        'windowButtonVisibility': false,
      });
      style.complete();
      await original;
      expect(settled, isTrue);
      expect(nativeCalls.map((MethodCall call) => call.method), <String>[
        'setTitleBarStyle',
      ]);
    },
    variant: _windows,
  );

  testWidgets(
    'a hidden-style refusal is not converted to startup success',
    (WidgetTester tester) async {
      final Completer<Object?> style = Completer<Object?>();
      pending['setTitleBarStyle'] = style;
      final Future<void> original = configureAppWindowChrome();
      final Future<void> refusal = expectLater(
        original,
        throwsA(isA<PlatformException>()),
      );
      await tester.pump();
      style.completeError(PlatformException(code: 'synthetic'));
      await refusal;
      expect(nativeCalls.length, 1);
    },
    variant: _windows,
  );

  testWidgets(
    '1280 by 780 retains full client and gives body its real 748 pixels',
    (WidgetTester tester) async {
      final _OwnedPageState page = await mount(tester);
      final FlutterView originalView = View.of(page.context);
      expect(originalView, same(tester.view));
      expect(
        View.of(tester.element(find.byType(EditableText))),
        same(originalView),
      );
      final NavigatorState bodyNavigator = Navigator.of(page.context);
      final OverlayState captionOverlay = Overlay.of(
        tester.element(control('window-minimize')),
      );
      expect(
        View.of(tester.element(control('window-minimize'))),
        same(originalView),
      );
      expect(captionOverlay, isNot(same(bodyNavigator.overlay)));
      expect(Overlay.of(page.context), same(bodyNavigator.overlay));
      expect(
        Overlay.of(page.context, rootOverlay: true),
        same(bodyNavigator.overlay),
      );
      expect(
        Overlay.of(
          tester.element(control('window-minimize')),
          rootOverlay: true,
        ),
        same(captionOverlay),
      );
      expect(
        tester.getSize(find.byWidget(captionOverlay.widget)),
        const Size(1280, 780),
      );
      expect(tester.view.physicalSize, const Size(1280, 780));
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('window-caption'))),
        const Rect.fromLTWH(0, 0, 1280, 32),
      );
      expect(page.bodySize, const Size(1280, 748));
      expect(page.bodyConstraints!.biggest, const Size(1280, 748));
      expect(
        tester.getCenter(find.byKey(const ValueKey<String>('body-center'))),
        const Offset(640, 406),
      );
      for (final String key in <String>[
        'window-minimize',
        'window-maximize',
        'window-close',
      ]) {
        expect(tester.getSize(control(key)), const Size(44, 32));
      }
    },
    variant: _windows,
  );

  testWidgets(
    'a 1200 by 600 Flutter client gives a 568 pixel body',
    (WidgetTester tester) async {
      final _OwnedPageState page = await mount(
        tester,
        size: const Size(1200, 600),
      );
      expect(page.bodySize, const Size(1200, 568));
      expect(page.bodyConstraints!.biggest, const Size(1200, 568));
      expect(
        tester.getCenter(find.byKey(const ValueKey<String>('body-center'))),
        const Offset(600, 316),
      );
    },
    variant: _windows,
  );

  testWidgets(
    'theme changes retain original Navigator, page, controller and provider',
    (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      final Object owner = Object();
      final _OwnedPageState page = await mount(
        tester,
        navigator: navigator,
        owner: owner,
      );
      final FlutterView originalView = View.of(page.context);
      expect(originalView, same(tester.view));
      expect(
        View.of(tester.element(find.byType(EditableText))),
        same(originalView),
      );
      final NavigatorState originalNavigator = navigator.currentState!;
      final OverlayState originalBodyOverlay = originalNavigator.overlay!;
      final FocusScopeNode originalFocus = FocusScope.of(page.context);
      expect(Theme.of(page.context).brightness, Brightness.dark);
      expect(
        Material.maybeOf(tester.element(find.byType(TextField))),
        isNotNull,
      );
      expect(Overlay.of(page.context), same(originalBodyOverlay));
      expect(
        Overlay.of(page.context, rootOverlay: true),
        same(originalBodyOverlay),
      );
      final OverlayState originalCaptionOverlay = Overlay.of(
        tester.element(control('window-minimize')),
      );
      final AppWindowFrameState originalFrame = tester
          .state<AppWindowFrameState>(find.byType(AppWindowFrame));
      final Object originalCaptionOwner = originalFrame.windowStatus!.owner;
      final TextEditingController originalText = page.text;
      await tester.enterText(find.byType(TextField), 'Synthetic local draft');
      final _OwnedPageState after = await mount(
        tester,
        navigator: navigator,
        owner: owner,
        brightness: Brightness.light,
      );
      expect(after, same(page));
      expect(View.of(after.context), same(originalView));
      expect(
        View.of(tester.element(find.byType(EditableText))),
        same(originalView),
      );
      expect(
        View.of(tester.element(control('window-minimize'))),
        same(originalView),
      );
      expect(navigator.currentState, same(originalNavigator));
      expect(
        Navigator.of(after.context, rootNavigator: true),
        same(originalNavigator),
      );
      expect(FocusScope.of(after.context), same(originalFocus));
      expect(Theme.of(after.context).brightness, Brightness.light);
      expect(
        Material.maybeOf(tester.element(find.byType(TextField))),
        isNotNull,
      );
      expect(originalNavigator.overlay, same(originalBodyOverlay));
      expect(Overlay.of(after.context), same(originalBodyOverlay));
      expect(
        Overlay.of(after.context, rootOverlay: true),
        same(originalBodyOverlay),
      );
      expect(
        Overlay.of(tester.element(control('window-minimize'))),
        same(originalCaptionOverlay),
      );
      expect(tester.state(find.byType(AppWindowFrame)), same(originalFrame));
      expect(originalFrame.windowStatus!.owner, same(originalCaptionOwner));
      expect(after.text, same(originalText));
      expect(after.text.text, 'Synthetic local draft');
      expect(after.suppliedOwner, same(owner));
      expect(page.disposals, 0);
      expect(
        nativeCalls
            .where((MethodCall call) => call.method == 'isMaximized')
            .length,
        1,
      );
    },
    variant: _windows,
  );

  testWidgets(
    'routes and modal barriers stay in the original body Navigator',
    (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      final _Routes observer = _Routes();
      final _OwnedPageState page = await mount(
        tester,
        navigator: navigator,
        observer: observer,
      );
      final Route<dynamic> original = observer.pushed.single;
      final NavigatorState originalNavigator = navigator.currentState!;
      final OverlayState bodyOverlay = originalNavigator.overlay!;
      expect(Overlay.of(page.context), same(bodyOverlay));
      expect(
        Overlay.of(page.context, rootOverlay: true),
        same(bodyOverlay),
      );
      final Future<void> push = originalNavigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Second route')),
        ),
      );
      await settle(tester);
      expect(observer.previous.last, same(original));
      expect(page.disposals, 0);
      originalNavigator.pop();
      await settle(tester);
      await push;
      expect(tester.state(find.byType(_OwnedPage)), same(page));
      final Future<void> modal = showDialog<void>(
        context: page.context,
        builder: (_) => const AlertDialog(title: Text('Synthetic modal')),
      );
      await settle(tester);
      expect(observer.previous.last, same(original));
      expect(tester.getRect(find.byType(ModalBarrier).last).top, 32);
      final BuildContext barrierContext = tester.element(
        find.byType(ModalBarrier).last,
      );
      expect(Overlay.of(barrierContext), same(bodyOverlay));
      expect(
        Overlay.of(barrierContext, rootOverlay: true),
        same(bodyOverlay),
      );
      expect(navigator.currentState, same(originalNavigator));
      expect(
        find.byKey(const ValueKey<String>('window-caption')),
        findsOneWidget,
      );
      originalNavigator.pop();
      await settle(tester);
      await modal;
      expect(page.disposals, 0);
      int intercepted = 0;
      const Key probeKey = ValueKey<String>('body-root-overlay-probe');
      final OverlayEntry probe = OverlayEntry(
        builder: (_) => Positioned.fill(
          child: Listener(
            key: probeKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => intercepted++,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      Overlay.of(page.context, rootOverlay: true).insert(probe);
      try {
        await settle(tester);
        expect(
          tester.getRect(find.byKey(probeKey)),
          const Rect.fromLTWH(0, 32, 1280, 748),
        );
        await tester.tap(control('window-minimize'));
        await settle(tester);
        expect(intercepted, 0);
        expect(
          nativeCalls.where((MethodCall call) => call.method == 'minimize'),
          hasLength(1),
        );
        await tester.tap(find.byKey(probeKey));
        await tester.pump();
        expect(intercepted, 1);
      } finally {
        probe
          ..remove()
          ..dispose();
        await tester.pump();
      }
      expect(page.disposals, 0);
    },
    variant: _windows,
  );

  testWidgets(
    'dark and light caption colours and title type come from tokens',
    (WidgetTester tester) async {
      for (final Brightness brightness in <Brightness>[
        Brightness.dark,
        Brightness.light,
      ]) {
        await mount(tester, brightness: brightness);
        final AppTokens tokens = brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light;
        expect(
          tester
              .widget<Material>(
                find.byKey(const ValueKey<String>('window-caption')),
              )
              .color,
          tokens.windowCaptionBackground,
        );
        final Text title = tester.widget<Text>(find.text('SYRIUS'));
        expect(title.style, tokens.windowTitleText);
        expect(tokens.windowTitleText.fontSize, 12);
        expect(tokens.windowTitleText.letterSpacing, 4.08);
        expect(tokens.windowCloseHover, tokens.error.withValues(alpha: 0.12));
      }
    },
    variant: _windows,
  );

  testWidgets(
    'RTL routes retain direction while Windows controls stay on the right',
    (WidgetTester tester) async {
      final _OwnedPageState page = await mount(
        tester,
        locale: const Locale('ar'),
      );
      expect(page.bodyDirection, TextDirection.rtl);
      final double minX = tester.getCenter(control('window-minimize')).dx;
      final double maxX = tester.getCenter(control('window-maximize')).dx;
      final double closeX = tester.getCenter(control('window-close')).dx;
      expect(minX, lessThan(maxX));
      expect(maxX, lessThan(closeX));
      expect(tester.getRect(control('window-close')).right, 1276);
    },
    variant: _windows,
  );

  testWidgets(
    'localized tooltip buttons are keyboard focusable with button semantics',
    (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await mount(tester);
        expect(find.byTooltip('Minimize'), findsOneWidget);
        expect(find.byTooltip('Maximize'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
        final Finder minimize = control('window-minimize');
        final Finder rawTooltip = find.descendant(
          of: minimize,
          matching: find.byType(RawTooltip),
        );
        expect(rawTooltip, findsOneWidget);
        final Finder tooltipAnnotation = find.descendant(
          of: rawTooltip,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics && widget.properties.tooltip == 'Minimize',
          ),
        );
        expect(tooltipAnnotation, findsOneWidget);
        // Keep button flags and read the actual RawTooltip annotation node.
        final SemanticsData data = tester
            .getSemantics(minimize)
            .getSemanticsData();
        final SemanticsData tooltipData = tester
            .getSemantics(tooltipAnnotation)
            .getSemanticsData();
        expect(tooltipData.tooltip, 'Minimize');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isTrue);
        expect(tooltipData.flagsCollection.isFocused, isNot(Tristate.none));
        expect(tooltipData.hasAction(SemanticsAction.tap), isTrue);
        final FocusNode originalMinimizeFocus = Focus.of(
          tester.element(
            find.descendant(
              of: minimize,
              matching: find.byKey(
                const ValueKey<String>('window-caption-mark'),
              ),
            ),
          ),
        );
        expect(originalMinimizeFocus.canRequestFocus, isTrue);
        final SemanticsNode minimizeNode = tester.getSemantics(
          tooltipAnnotation,
        );
        expect(tooltipData.hasAction(SemanticsAction.focus), isTrue);
        // Establish caption focus through its original accessible focus action.
        tester.semantics.performAction(
          find.semantics.byPredicate(
            (SemanticsNode node) => node.id == minimizeNode.id,
          ),
          SemanticsAction.focus,
        );
        await settle(tester);
        expect(
          originalMinimizeFocus.hasPrimaryFocus,
          isTrue,
          reason:
              'Original Minimize focus: $originalMinimizeFocus; '
              'primary focus: ${FocusManager.instance.primaryFocus}',
        );
        expect(
          tester
              .getSemantics(tooltipAnnotation)
              .getSemanticsData()
              .flagsCollection
              .isFocused,
          Tristate.isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await settle(tester);
        final Finder maximizeAnnotation = find.descendant(
          of: control('window-maximize'),
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics && widget.properties.tooltip == 'Maximize',
          ),
        );
        expect(maximizeAnnotation, findsOneWidget);
        expect(
          tester
              .getSemantics(maximizeAnnotation)
              .getSemanticsData()
              .flagsCollection
              .isFocused,
          Tristate.isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await settle(tester);
        expect(
          originalMinimizeFocus.hasPrimaryFocus,
          isTrue,
          reason:
              'Original Minimize focus: $originalMinimizeFocus; '
              'primary focus: ${FocusManager.instance.primaryFocus}',
        );
        expect(
          tester
              .getSemantics(tooltipAnnotation)
              .getSemanticsData()
              .flagsCollection
              .isFocused,
          Tristate.isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          nativeCalls
              .where((MethodCall call) => call.method == 'minimize')
              .length,
          1,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(
          nativeCalls
              .where((MethodCall call) => call.method == 'minimize')
              .length,
          2,
        );
        expect(
          nativeCalls.any(
            (MethodCall call) => call.method == 'startDragging',
          ),
          isFalse,
        );
      } finally {
        semantics.dispose();
      }
    },
    variant: _windows,
  );

  testWidgets(
    'caption drag and secondary click use original native operations',
    (WidgetTester tester) async {
      await mount(tester);
      final Finder drag = find.byKey(
        const ValueKey<String>('window-drag-region'),
      );
      await tester.drag(drag, const Offset(24, 0));
      await tester.pump();
      expect(
        nativeCalls
            .where((MethodCall call) => call.method == 'startDragging')
            .length,
        1,
      );
      await tester.tap(drag, buttons: kSecondaryButton);
      await tester.pump(kDoubleTapMinTime);
      expect(
        nativeCalls
            .where((MethodCall call) => call.method == 'popUpWindowMenu')
            .length,
        1,
      );
      expect(
        nativeCalls.any(
          (MethodCall call) => call.method == 'destroy',
        ),
        isFalse,
      );
    },
    variant: _windows,
  );

  testWidgets(
    'positive fresh mode observation supplies the restore tooltip',
    (WidgetTester tester) async {
      effectChangesMode = true;
      await mount(tester);
      await tester.tap(control('window-maximize'));
      await settle(tester);
      expect(find.byTooltip('Restore'), findsOneWidget);
      expect(
        nativeCalls
            .where((MethodCall call) => call.method == 'maximize')
            .length,
        1,
      );
      await tester.tap(control('window-maximize'));
      await settle(tester);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(
        nativeCalls
            .where((MethodCall call) => call.method == 'unmaximize')
            .length,
        1,
      );
    },
    variant: _windows,
  );

  testWidgets(
    'a pending caption effect is not replayed and close stays independent',
    (WidgetTester tester) async {
      final Completer<Object?> effect = Completer<Object?>();
      pending['maximize'] = effect;
      await mount(tester);
      final AppWindowFrameState originalFrame = tester
          .state<AppWindowFrameState>(find.byType(AppWindowFrame));
      final Object originalOwner = originalFrame.windowStatus!.owner;
      await tester.tap(control('window-maximize'));
      await tester.pump();
      expect(
        tester.widget<IconButton>(control('window-maximize')).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(control('window-minimize')).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(control('window-close')).onPressed,
        isNotNull,
      );
      await tester.tap(control('window-close'));
      await tester.pump();
      expect(
        nativeCalls.where((MethodCall call) => call.method == 'close').length,
        1,
      );
      expect(
        nativeCalls.any(
          (MethodCall call) => call.method == 'destroy',
        ),
        isFalse,
      );
      expect(
        nativeCalls.any(
          (MethodCall call) => call.method == 'setPreventClose',
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(originalFrame.windowStatus!.owner, same(originalOwner));
      expect(originalFrame.windowStatus!.attached, isFalse);
      effect.completeError(
        PlatformException(code: 'synthetic', message: 'Private late text'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        nativeCalls
            .where((MethodCall call) => call.method == 'isMaximized')
            .length,
        2,
      );
    },
    variant: _windows,
  );

  testWidgets(
    'failed query leaves genuine close and minimize without private text',
    (WidgetTester tester) async {
      queryFailure = true;
      await mount(tester);
      expect(
        tester.widget<IconButton>(control('window-maximize')).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(control('window-minimize')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<IconButton>(control('window-close')).onPressed,
        isNotNull,
      );
      expect(find.textContaining('Private test text'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: _windows,
  );

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'preserves the native caption and full body on ${platform.name}',
      (WidgetTester tester) async {
        await configureAppWindowChrome();
        final _OwnedPageState page = await mount(tester);
        expect(
          find.byKey(const ValueKey<String>('window-caption')),
          findsNothing,
        );
        expect(page.bodySize, const Size(1280, 780));
        expect(page.bodyConstraints!.biggest, const Size(1280, 780));
        expect(nativeCalls, isEmpty);
      },
      variant: _PlatformVariant(<TargetPlatform>{platform}),
    );
  }
}
