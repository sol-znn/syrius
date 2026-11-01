import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as foundation show TargetPlatform;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/view/home_hero.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/plasma_meter.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/readonly_sdk_admission.dart';

const String _prices = '{"zenon-2":{"usd":0.62},"quasar":{"usd":0.031}}';
const MethodChannel _window = MethodChannel('window_manager');

HomeSnapshot _snapshot({
  BigInt? znn,
  BigInt? qsr,
  int currentPlasma = 84000,
  int maxPlasma = 100000,
}) => HomeSnapshot(
  znn: znn ?? BigInt.parse('120450000000'),
  qsr: qsr ?? BigInt.parse('1288000000000'),
  tokens: const <BalanceInfoListItem>[],
  currentPlasma: currentPlasma,
  maxPlasma: maxPlasma,
  fusedQsr: BigInt.zero,
  rewards: const <String, UncollectedReward>{},
);

class _Prices {
  int requests = 0;
  bool fail = false;
  String answer = _prices;
  DateTime now = DateTime.utc(2030);

  Future<String> call(Uri uri) async {
    expect(uri, PriceFeed.url);
    requests++;
    if (fail) throw const FormatException('Unavailable fixture');
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Prices source;
  late PriceFeed feed;
  late BalanceVisibility visibility;
  late Map<String, String> previousLabels;
  late List<String?> previousAddresses;
  late SharedPrefsService? previousPreferences;
  late List<TransferMode> opened;

  setUp(() {
    previousLabels = kAddressLabelMap;
    previousAddresses = kDefaultAddressList;
    previousPreferences = app.sharedPrefsService;
    app.sharedPrefsService = null;
    kAddressLabelMap = <String, String>{emptyAddress.toString(): 'Address 1'};
    kDefaultAddressList = <String?>[emptyAddress.toString()];
    visibility = BalanceVisibility();
    source = _Prices();
    feed = PriceFeed(request: source.call, now: () => source.now);
    opened = <TransferMode>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (MethodCall call) async => true);
  });

  tearDown(() {
    feed.dispose();
    visibility.dispose();
    kAddressLabelMap = previousLabels;
    kDefaultAddressList = previousAddresses;
    app.sharedPrefsService = previousPreferences;
    AppLottie.debugClear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
  });

  Widget host({
    ThemeData? theme,
    HomeSnapshot? snapshot,
    bool noSnapshot = false,
    bool failed = false,
    bool light = false,
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
    bool reduced = false,
    Stream<PowGenerationState>? status,
  }) => MaterialApp(
    theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Directionality(
        textDirection: direction,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: HomeHero(
              key: const Key('home_hero'),
              address: emptyAddress.toString(),
              snapshot: noSnapshot ? null : snapshot ?? _snapshot(),
              failed: failed,
              onOpenTransfer: opened.add,
              visibility: visibility,
              priceFeed: feed,
              powStatus: status ?? const Stream<PowGenerationState>.empty(),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    ThemeData? theme,
    HomeSnapshot? snapshot,
    bool noSnapshot = false,
    bool failed = false,
    bool light = false,
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
    bool reduced = false,
    Stream<PowGenerationState>? status,
    Size size = const Size(1280, 780),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      host(
        theme: theme,
        snapshot: snapshot,
        noSnapshot: noSnapshot,
        failed: failed,
        light: light,
        direction: direction,
        textScale: textScale,
        reduced: reduced,
        status: status,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void expectSecondaryGeometry(WidgetTester tester) {
    for (final String name in const <String>['home_receive', 'home_zap']) {
      final Finder action = find.byKey(Key(name));
      final Finder button = find.descendant(
        of: action,
        matching: find.byType(OutlinedButton),
      );
      expect(button, findsOneWidget);
      expect(
        Theme.of(tester.element(action)).visualDensity,
        VisualDensity.compact,
      );
      expect(tester.getSize(action).height, 38);
      expect(tester.getSize(button).height, 38);
    }
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets('exact coin values and one shared priced total, light $light', (
      WidgetTester tester,
    ) async {
      await show(tester, light: light);
      final Object captureOwner = Object();
      bool automaticDisabled = false;
      final HarnessAgent capture = HarnessAgent.forTest()
        ..reserveReadonlyNative()
        ..attachReadonlyNative(await ReadonlySdkAdmission.seal(
          sdkOwner: captureOwner,
          ownersCurrent: () => true,
          automaticDisabled: () => automaticDisabled,
          disableAutomatic: () async { automaticDisabled = true; },
        ))
        ..booted = true;
      for (final String key in <String>['home_hero', 'home_znn']) {
        final Map<String, Object?> result = await capture.commandForTest(
          <String, dynamic>{'cmd': 'assert', 'key': key},
        );
        expect(result['asserted'], isTrue);
        final Map<String, Object?> target =
            result['target']! as Map<String, Object?>;
        final Rect observed = tester.getRect(find.byKey(Key(key)));
        expect(target['rect'], <int>[
          observed.left.round(), observed.top.round(),
          observed.width.round(), observed.height.round(),
        ]);
        expect(target['kind'], 'region');
      }
      expect(find.text('1,204.5'), findsOneWidget);
      expect(find.text('12,880'), findsOneWidget);
      expect(find.text('ZNN'), findsOneWidget);
      expect(find.text('QSR'), findsOneWidget);
      expect(find.text(r'$746.79'), findsOneWidget);
      expect(find.text(r'$399.28'), findsOneWidget);
      expect(find.text(r'≈ $1,146.07'), findsOneWidget);
      expect(source.requests, 1);
      expect(find.byType(PrimaryPill), findsOneWidget);
      expect(find.byKey(const Key('home_swap')), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      final Text dollars = tester.widget<Text>(find.text(r'$746.79'));
      expect(dollars.style!.fontFamily, kMonoFontFamily);
      expect(dollars.style!.fontSize, 13);
      final AmountText amount = tester.widget<AmountText>(
        find.byKey(const Key('home_znn')),
      );
      expect(
        amount.style.color,
        light ? AppTokens.light.foreground : AppTokens.dark.foreground,
      );
      final Rect balance = tester.getRect(
        find.byKey(const Key('home_znn_value')),
      );
      final Rect meter = tester.getRect(
        find.byKey(const Key('home_plasma_meter')),
      );
      final Rect send = tester.getRect(find.byKey(const Key('home_send')));
      expect(balance.right, lessThan(meter.left));
      expect(meter.right, lessThan(send.left));
      expect(tester.takeException(), isNull);

      kDefaultAddressList = <String?>[
        emptyAddress.toString(),
        Address('z', <int>[0, ...List<int>.filled(19, 7)]).toString(),
      ];
      for (final TextDirection direction in TextDirection.values) {
        for (final double width in <double>[1280, 1200]) {
          await show(tester, light: light, direction: direction,
              size: Size(width, 780));
          final bool ltr = direction == TextDirection.ltr;
          final Rect group = tester.getRect(
            find.byKey(const Key('home_hero_balances')),
          );
          final Rect plasma = tester.getRect(
            find.byKey(const Key('home_plasma_meter')),
          );
          final Rect hero = tester.getRect(find.byKey(const Key('home_hero')));
          final Rect last = tester.getRect(find.byKey(const Key('home_zap')));
          // The reference gives balances a 36 px gap before 220 px plasma,
          // and leaves flexible unused width before the end-aligned actions.
          expect(ltr ? plasma.left - group.right : group.left - plasma.right,
              closeTo(36, 1e-6));
          expect(plasma.width, 220);
          expect(ltr ? hero.right - last.right : last.left - hero.left,
              closeTo(24, 1e-6));
          expect(find.byKey(const Key('home_send')).hitTestable(),
              findsOneWidget);
          expect(find.byKey(const Key('home_receive')).hitTestable(),
              findsOneWidget);
          for (final String key in <String>[
            'home_copy_address', 'home_switch_address', 'home_eye',
          ]) {
            final Finder control = find.byKey(Key(key));
            expect(tester.getSize(control), const Size(14, 14));
            expect(control.hitTestable(), findsOneWidget);
          }
          expect(hero.height, lessThan(160));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.tap(find.byKey(const Key('home_switch_address')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      final NavigatorState menuNavigator = Navigator.of(
        tester.element(find.byType(PopupMenuItem<String>).first),
      );
      expect(menuNavigator.canPop(), isTrue);
      expect(
        FocusScope.of(
          tester.element(find.byType(PopupMenuItem<String>).first),
        ).hasFocus,
        isTrue,
      );
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.escape),
        isTrue,
      );
      // Start the reverse ticker before advancing its duration.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(menuNavigator.canPop(), isFalse);
      // Tick beyond the duration endpoint to complete route removal.
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'desktop secondary pills keep 38 px through hover and focus, $light',
      (WidgetTester tester) async {
        await show(
          tester,
          light: light,
          theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
            platform: foundation.TargetPlatform.windows,
            visualDensity: VisualDensity.compact,
          ),
        );
        expectSecondaryGeometry(tester);
        final Finder receive = find.byKey(const Key('home_receive'));
        final Rect original = tester.getRect(receive);
        final TestGesture mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(receive));
        await tester.pump(const Duration(milliseconds: 250));
        expectSecondaryGeometry(tester);
        expect(tester.getRect(receive), original);
        final FocusNode focus = Focus.of(
          tester.element(
            find.descendant(of: receive, matching: find.byType(Text)),
          ),
        )..requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        expectSecondaryGeometry(tester);
        expect(tester.getRect(receive), original);
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'desktop secondary sizing retains Receive routes and Zap refusal, '
      '$light',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await show(
            tester,
            light: light,
            theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
              platform: foundation.TargetPlatform.windows,
              visualDensity: VisualDensity.compact,
            ),
          );
          expectSecondaryGeometry(tester);
          final Finder receive = find.byKey(const Key('home_receive'));
          final Finder receiveButton = find.descendant(
            of: receive,
            matching: find.byType(OutlinedButton),
          );
          expect(
            tester
                .getSemantics(receiveButton)
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(receive);
          await tester.pump();
          final FocusNode focus = Focus.of(
            tester.element(
              find.descendant(of: receive, matching: find.byType(Text)),
            ),
          )..requestFocus();
          await tester.pump();
          expect(focus.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await tester.tap(find.byKey(const Key('home_send')));
          await tester.pump();
          expect(opened, <TransferMode>[
            TransferMode.receive,
            TransferMode.receive,
            TransferMode.send,
          ]);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          final Finder zap = find.byKey(const Key('home_zap'));
          final Finder zapButton = find.descendant(
            of: zap,
            matching: find.byType(OutlinedButton),
          );
          await tester.tapAt(tester.getCenter(zap));
          tester.widget<OutlinedButton>(zapButton).onPressed!();
          final FocusNode blocked = Focus.of(
            tester.element(
              find.descendant(of: zap, matching: find.byType(Text)),
            ),
          )..requestFocus();
          await tester.pump();
          expect(blocked.hasFocus, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          final SemanticsNode refusal = tester.getSemantics(
            find.byType(SeamGate),
          );
          expect(
            refusal.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          refusal.owner!.performAction(refusal.id, ui.SemanticsAction.tap);
          await tester.pump();
          expectSecondaryGeometry(tester);
          expect(opened, <TransferMode>[
            TransferMode.receive,
            TransferMode.receive,
            TransferMode.send,
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets('a value beyond double precision keeps its last base unit', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      snapshot: _snapshot(znn: BigInt.parse('9007199254740993')),
    );
    expect(find.text('90,071,992.54740993'), findsOneWidget);
    expect(find.text('90,071,992.54740992'), findsNothing);
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const Key('home_znn')),
        matching: find.byType(RichText),
      ),
    );
    final List<ui.TextBox> boxes = paragraph.getBoxesForSelection(
      const TextSelection(
        baseOffset: 0,
        extentOffset: '90,071,992.54740993'.length,
      ),
    );
    expect(boxes.last.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero balances have no trailing fractional zeros', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      snapshot: _snapshot(znn: BigInt.zero, qsr: BigInt.zero),
    );
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('0.00000000'), findsNothing);
    expect(find.text(r'$0.0000'), findsNWidgets(2));
    expect(find.text(r'≈ $0.0000'), findsOneWidget);
  });

  testWidgets('missing one price never presents a partial balance total', (
    WidgetTester tester,
  ) async {
    source.answer = '{"zenon-2":{"usd":0.62}}';
    await show(tester);
    expect(find.text(r'$746.79'), findsOneWidget);
    expect(find.byKey(const Key('home_qsr_dollars')), findsNothing);
    expect(find.byKey(const Key('home_total_dollars')), findsNothing);
  });

  testWidgets(
    'eye shares privacy and removes amounts from paint and semantics',
    (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await show(tester);
        final Size shown = tester.getSize(
          find.byKey(const Key('home_znn_value')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('home_eye')));
        await tester.pump();
        expect(visibility.hidden, isTrue);
        final Size hidden = tester.getSize(
          find.byKey(const Key('home_znn_value')),
        );
        expect(hidden.width, lessThan(shown.width));
        expect(hidden.height, shown.height);
        expect(find.byKey(const Key('home_znn')).hitTestable(), findsNothing);
        expect(find.byKey(const Key('home_qsr')).hitTestable(), findsNothing);
        expect(find.text('ZNN').hitTestable(), findsOneWidget);
        expect(find.text('QSR').hitTestable(), findsOneWidget);
        expect(find.text(r'$746.79'), findsNothing);
        expect(find.text(r'$399.28'), findsNothing);
        expect(find.text(r'≈ $1,146.07'), findsNothing);
        expect(find.text('≈ ••••'), findsOneWidget);
        expect(
          find.semantics.byLabel(
            RegExp(r'1,204\.5|12,880|746\.79|399\.28|1,146\.07'),
          ),
          findsNothing,
        );
        expect(find.byTooltip('Show balances'), findsOneWidget);
        visibility.set(false);
        await tester.pump();
        expect(tester.getSize(find.byKey(const Key('home_znn_value'))), shown);
        expect(find.byKey(const Key('home_znn')).hitTestable(), findsOneWidget);
        expect(find.byTooltip('Hide balances'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'hidden balances move one original eye and preserve focus and playback',
    (
      WidgetTester tester,
    ) async {
      for (final bool light in <bool>[false, true]) {
        visibility.set(false);
        await show(tester, light: light);
        final Finder eye = find.byType(EyeToggle);
        final Finder control = find.byKey(const Key('home_eye'));
        final Finder amount = find.byKey(const Key('home_znn_value'));
        final Finder symbol = find.byKey(const Key('home_znn_symbol'));
        final State<EyeToggle> state = tester.state<State<EyeToggle>>(eye);
        final Animation<double> controller = tester
            .widget<AppLottie>(find.byType(AppLottie))
            .controller!;
        final FocusNode focus = Focus.of(
          tester.element(
            find.descendant(of: eye, matching: find.byType(GestureDetector)),
          ),
        )..requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        expect(
          tester.getRect(control).bottom,
          lessThan(tester.getRect(amount).top),
        );
        expect(find.byKey(const Key('home_znn_dollars')), findsOneWidget);
        expect(find.byKey(const Key('home_qsr_dollars')), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(visibility.hidden, isTrue);
        expect(tester.state<State<EyeToggle>>(eye), same(state));
        expect(
          tester.widget<AppLottie>(find.byType(AppLottie)).controller,
          same(controller),
        );
        expect(focus.hasFocus, isTrue);
        final Rect hiddenEye = tester.getRect(control);
        final Rect hiddenAmount = tester.getRect(amount);
        final AppTokens tokens = AppTokens.of(tester.element(eye));
        expect(
          hiddenEye.left - tester.getRect(symbol).right,
          closeTo(
            tokens.heroHiddenEyeGap +
                (tokens.heroHiddenEyeSlotWidth - tokens.heroHiddenEyeSize) / 2,
            0.01,
          ),
        );
        expect(hiddenEye.top, greaterThanOrEqualTo(hiddenAmount.top));
        expect(hiddenEye.bottom, lessThanOrEqualTo(hiddenAmount.bottom));
        expect(find.byKey(const Key('home_znn_dollars')), findsNothing);
        expect(find.byKey(const Key('home_qsr_dollars')), findsNothing);
        expect(find.byKey(const Key('home_total_dollars')), findsOneWidget);
        expect(find.text('≈ ••••'), findsOneWidget);
        expect(controller.value * EyeToggle.frames, greaterThan(3.25));
        expect(
          controller.value * EyeToggle.frames,
          lessThan(EyeToggle.hiddenFrame),
        );

        await tester.pumpWidget(host(light: light, textScale: 2));
        await tester.pump();
        expect(tester.state<State<EyeToggle>>(eye), same(state));
        expect(focus.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          controller.value * EyeToggle.frames,
          closeTo(EyeToggle.hiddenFrame, 1e-6),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(visibility.hidden, isFalse);
        expect(tester.state<State<EyeToggle>>(eye), same(state));
        expect(focus.hasFocus, isTrue);
        expect(
          tester.getRect(control).bottom,
          lessThan(tester.getRect(amount).top),
        );
        expect(find.byKey(const Key('home_znn_dollars')), findsOneWidget);
        expect(find.byKey(const Key('home_qsr_dollars')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          controller.value * EyeToggle.frames,
          closeTo(EyeToggle.shownFrame, 1e-6),
        );

        visibility.set(true);
        await tester.pumpWidget(
          host(light: light, noSnapshot: true, failed: true),
        );
        await tester.pump();
        expect(tester.state<State<EyeToggle>>(eye), same(state));
        expect(control.hitTestable(), findsOneWidget);
        expect(find.byKey(const Key('home_hero_status')), findsOneWidget);
        expect(find.byType(AppLottie), findsOneWidget);
        expect(
          tester.widget<AppLottie>(find.byType(AppLottie)).controller,
          same(controller),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets('hidden spacing follows inline reference at both text scales', (
    WidgetTester tester,
  ) async {
    visibility.set(true);
    for (final bool light in <bool>[false, true]) {
      for (final TextDirection direction in TextDirection.values) {
        for (final double scale in <double>[1, 2]) {
          await show(tester, light: light, direction: direction,
            textScale: scale);
          final AppTokens tokens = AppTokens.of(
            tester.element(find.byType(HomeHero)),
          );
          for (final (String, TextStyle) row in <(String, TextStyle)>[
            ('home_znn', tokens.heroAmountText),
            ('home_qsr', tokens.heroSecondaryAmountText),
          ]) {
            final (String prefix, TextStyle style) = row;
            final Finder mask = find.descendant(
              of: find.byKey(ValueKey<String>('${prefix}_value')),
              matching: find.text(kHiddenAmountDots),
            );
            final Finder symbol = find.byKey(
              ValueKey<String>('${prefix}_symbol'),
            );
            // This is the reference's inline mask, space and plain symbol.
            final TextPainter reference = TextPainter(
              text: TextSpan(
                style: monoStyle(style).copyWith(
                  letterSpacing: style.fontSize! * 0.08,
                ),
                children: <InlineSpan>[
                  const TextSpan(text: '•••• '),
                  TextSpan(
                    text: prefix == 'home_znn' ? 'ZNN' : 'QSR',
                    style: tokens.heroSymbolText.copyWith(letterSpacing: 0),
                  ),
                ],
              ),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            expect(tester.getRect(symbol).right - tester.getRect(mask).left,
              closeTo(reference.width, 0.1));
            reference.dispose();
          }
          final Rect slot = tester.getRect(
            find.byKey(const Key('home_hidden_eye_slot')),
          );
          final Rect eye = tester.getRect(find.byKey(const Key('home_eye')));
          expect(slot.size, const Size(34, 20));
          expect(eye.size, const Size(20, 20));
          expect(eye.center, slot.center);
          final Finder primaryMask = find.descendant(
            of: find.byKey(const Key('home_znn_value')),
            matching: find.text(kHiddenAmountDots),
          );
          final double gap = direction == TextDirection.ltr
              ? slot.left - tester.getRect(
                  find.byKey(const Key('home_znn_symbol'))).right
              : tester.getRect(primaryMask).left - slot.right;
          expect(gap, closeTo(14, 0.1));
          expect(find.byKey(const Key('home_znn_dollars')), findsNothing);
          expect(find.byKey(const Key('home_qsr_dollars')), findsNothing);
          expect(find.text('≈ ••••'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('hidden width reveals neither balance length nor its changes', (
    WidgetTester tester,
  ) async {
    visibility.set(true);
    await show(tester);
    final Size first = tester.getSize(find.byKey(const Key('home_znn_value')));
    await tester.pumpWidget(host(snapshot: _snapshot(znn: BigInt.one)));
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('home_znn_value'))), first);
    expect(find.text('ZNN').hitTestable(), findsOneWidget);
  });

  testWidgets('Send and Receive select distinct existing transfer modes', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('home_send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('home_receive')));
    await tester.pump();
    expect(opened, <TransferMode>[TransferMode.send, TransferMode.receive]);
  });

  testWidgets(
    'Zap refuses pointer, keyboard, semantics and direct action calls',
    (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await show(tester);
        final Finder zap = find.byKey(const Key('home_zap'));
        await tester.tapAt(tester.getCenter(zap));
        await tester.pump();
        final Finder button = find.descendant(
          of: zap,
          matching: find.byType(OutlinedButton),
        );
        tester.widget<OutlinedButton>(button).onPressed!();
        final FocusNode focus = Focus.of(tester.element(button))
          ..requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        final SemanticsNode refusal = tester.getSemantics(
          find.byType(SeamGate),
        );
        expect(
          refusal.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        refusal.owner!.performAction(refusal.id, ui.SemanticsAction.tap);
        await tester.pump();
        final Finder tooltip = find.descendant(
          of: find.byType(SeamGate),
          matching: find.byType(Tooltip),
        );
        expect(tester.widget<Tooltip>(tooltip).message, 'Not yet');
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Display off hides dollars and suspends every request', (
    WidgetTester tester,
  ) async {
    feed.enabled = false;
    await show(tester);
    expect(source.requests, 0);
    expect(find.byType(DollarText), findsNothing);
    expect(find.text('1,204.5'), findsOneWidget);
    feed.enabled = true;
    await tester.pump();
    await tester.pump();
    expect(source.requests, 1);
    expect(find.text(r'≈ $1,146.07'), findsOneWidget);
    feed.enabled = false;
    await tester.pump();
    source.now = source.now.add(PriceFeed.interval * 2);
    await tester.pump(PriceFeed.interval * 2);
    expect(source.requests, 1);
    expect(find.byType(DollarText), findsNothing);
  });

  testWidgets(
    'leaving Home removes the last feed listener and returning resumes it',
    (
      WidgetTester tester,
    ) async {
      await show(tester);
      expect(source.requests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      source.now = source.now.add(PriceFeed.interval * 2);
      await tester.pump(PriceFeed.interval * 2);
      expect(source.requests, 1);
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(source.requests, 2);
      expect(find.text(r'≈ $1,146.07'), findsOneWidget);
    },
  );

  testWidgets('a failed price refresh retains the last exact values', (
    WidgetTester tester,
  ) async {
    await show(tester);
    source.fail = true;
    source.now = source.now.add(PriceFeed.interval);
    await tester.pump(PriceFeed.interval);
    await tester.pump();
    expect(source.requests, 2);
    expect(find.text(r'$746.79'), findsOneWidget);
    expect(find.text(r'$399.28'), findsOneWidget);
    expect(find.text(r'≈ $1,146.07'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'first-read loading and failure show no invented money or dollar request',
    (
      WidgetTester tester,
    ) async {
      await show(tester, noSnapshot: true);
      expect(find.text('Loading'), findsOneWidget);
      expect(find.byType(AmountText), findsNothing);
      expect(source.requests, 0);
      await tester.pumpWidget(host(noSnapshot: true, failed: true));
      await tester.pump();
      expect(find.text('Node not answering'), findsOneWidget);
      expect(find.byType(AmountText), findsNothing);
      expect(source.requests, 0);
    },
  );

  testWidgets('a failed node refresh keeps a previously read balance visible', (
    WidgetTester tester,
  ) async {
    await show(tester, failed: true);
    expect(find.text('1,204.5'), findsOneWidget);
    expect(find.text(r'≈ $1,146.07'), findsOneWidget);
    expect(find.text('Node not answering'), findsNothing);
  });

  testWidgets(
    'meter follows the real work stream including an already running job',
    (
      WidgetTester tester,
    ) async {
      final PowGeneratingStatusBloc work = PowGeneratingStatusBloc();
      addTearDown(work.dispose);
      final PowWorkToken first = work.claimWork();
      work.update(first, PowStatus.generating);
      await show(tester, status: work.stream);
      PlasmaMeter meter() => tester.widget<PlasmaMeter>(
        find.byKey(const Key('home_plasma_meter')),
      );
      expect(meter().active, isTrue);
      expect(meter().value, 0.84);
      work.update(first, PowStatus.done);
      await tester.pump();
      expect(meter().active, isFalse);
      final PowWorkToken second = work.claimWork();
      work.update(second, PowStatus.generating);
      await tester.pump();
      expect(meter().active, isTrue);
      work.invalidate();
      await tester.pump();
      expect(meter().active, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalidated work stays idle after Home remounts', (
    WidgetTester tester,
  ) async {
    final PowGeneratingStatusBloc work = PowGeneratingStatusBloc();
    addTearDown(work.dispose);
    final PowWorkToken old = work.claimWork();
    work.update(old, PowStatus.generating);
    await show(tester, status: work.stream);
    PlasmaMeter meter() => tester.widget<PlasmaMeter>(
      find.byKey(const Key('home_plasma_meter')),
    );
    expect(meter().active, isTrue);
    work.invalidate();
    await tester.pump();
    expect(meter().active, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(work.update(old, PowStatus.generating), isFalse);
    await tester.pumpWidget(host(status: work.stream));
    await tester.pump();
    expect(meter().active, isFalse);
    final PowWorkToken current = work.claimWork();
    work.update(current, PowStatus.generating);
    await tester.pump();
    expect(meter().active, isTrue);
    expect(work.update(old, PowStatus.done), isFalse);
    work.release(old);
    await tester.pump();
    expect(meter().active, isTrue);
    work.release(current);
    await tester.pump();
    expect(meter().active, isFalse);
  });

  testWidgets('failed or closed injected work sources stop the Home meter', (
    WidgetTester tester,
  ) async {
    final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
    final PowWorkToken work = owner.claimWork();
    final StreamController<PowGenerationState> status =
        StreamController<PowGenerationState>.broadcast(sync: true);
    try {
      await show(tester, status: status.stream);
      PlasmaMeter meter() => tester.widget<PlasmaMeter>(
        find.byKey(const Key('home_plasma_meter')),
      );
      status.add(PowGenerationState.generating(work));
      await tester.pump();
      expect(meter().active, isTrue);
      status.addError(StateError('Unavailable fixture'));
      await tester.pump();
      expect(meter().active, isFalse);
      await status.close();
      await tester.pump();
      expect(meter().active, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!status.isClosed) await status.close();
      owner.dispose();
    }
  });

  for (final ({
        int plasma,
        int maximum,
        String level,
        String note,
        double ratio,
      })
      sample
      in <({int plasma, int maximum, String level, String note, double ratio})>[
        (
          plasma: 0,
          maximum: 0,
          level: 'NONE',
          note: 'Sends need proof of work',
          ratio: 0,
        ),
        (
          plasma: 20999,
          maximum: 100000,
          level: 'LOW',
          note: 'Sends need proof of work',
          ratio: 0.20999,
        ),
        (
          plasma: 21000,
          maximum: 100000,
          level: 'LOW',
          note: 'Enough for 1 send',
          ratio: 0.21,
        ),
        (
          plasma: 33000,
          maximum: 100000,
          level: 'MEDIUM',
          note: 'Enough for 1 send',
          ratio: 0.33,
        ),
        (
          plasma: 66000,
          maximum: 100000,
          level: 'HIGH',
          note: 'Enough for about 3 sends',
          ratio: 0.66,
        ),
        (
          plasma: 120000,
          maximum: 100000,
          level: 'HIGH',
          note: 'Enough for about 5 sends',
          ratio: 1,
        ),
      ]) {
    testWidgets(
      'plasma ${sample.plasma}/${sample.maximum} has a factual level '
      'and send estimate',
      (
        WidgetTester tester,
      ) async {
        await show(
          tester,
          snapshot: _snapshot(
            currentPlasma: sample.plasma,
            maxPlasma: sample.maximum,
          ),
        );
        final PlasmaMeter meter = tester.widget<PlasmaMeter>(
          find.byKey(const Key('home_plasma_meter')),
        );
        expect(meter.value, closeTo(sample.ratio, 1e-12));
        expect(meter.active, isFalse);
        expect(find.text(sample.level), findsOneWidget);
        expect(find.text(sample.note), findsOneWidget);
      },
    );
  }

  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      testWidgets(
        'large text keeps controls and LTR money at the minimum window, '
        'light $light $direction',
        (
          WidgetTester tester,
        ) async {
          await show(
            tester,
            light: light,
            direction: direction,
            textScale: 2,
            size: const Size(1200, 600),
          );
          expect(
            find.byKey(const Key('home_send')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('home_receive')).hitTestable(),
            findsOneWidget,
          );
          final Rect amount = tester.getRect(
            find.byKey(const Key('home_znn_value')),
          );
          final Rect symbol = tester.getRect(
            find.byKey(const Key('home_znn_symbol')),
          );
          expect(amount.right, lessThanOrEqualTo(symbol.left));
          expect(
            tester.widget<Text>(find.text(r'$746.79')).style!.fontFamily,
            kMonoFontFamily,
          );
          expect(find.byTooltip(emptyAddress.toString()), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'the original eye keeps its half-second change with animation flags off',
    (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await show(tester, reduced: true);
      await tester.tap(find.byKey(const ValueKey<String>('home_eye')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final AppLottie eye = tester.widget<AppLottie>(find.byType(AppLottie));
      expect(eye.controller!.value * EyeToggle.frames, greaterThan(3.25));
      expect(
        eye.controller!.value * EyeToggle.frames,
        lessThan(EyeToggle.hiddenFrame),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        eye.controller!.value * EyeToggle.frames,
        closeTo(EyeToggle.hiddenFrame, 1e-6),
      );
    },
  );
}
