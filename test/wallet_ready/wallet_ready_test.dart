import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/wallet_ready_surface.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_ready_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';

const String _first = 'fixture-first-address';

WalletReadySurface _surface({
  required WalletReadyBinding? binding,
  VoidCallback? onOpen,
  ValueChanged<String>? onCopy,
  bool hardware = false,
  bool imported = false,
}) => WalletReadySurface(
  binding: binding,
  onOpen: onOpen ?? () {},
  onCopy: onCopy ?? (_) {},
  map: const SizedBox.expand(key: Key('fixture_map')),
  hardware: hardware,
  imported: imported,
);

Widget _host(
  Widget child, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  bool enabled = true,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TickerMode(
    enabled: enabled,
    child: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child,
      ),
    ),
  ),
);

void _prepare(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.reset();
  });
}

VoidCallback _open(WidgetTester tester) => tester
    .widget<PrimaryPill>(find.byKey(const Key('wallet_ready_open')))
    .onPressed!;

void main() {
  test('one opening is reserved before its observer can re-enter', () {
    int checks = 0;
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () {
        checks++;
        return true;
      },
    );
    expect(binding.takeOpening(), isTrue);
    expect(binding.takeOpening(), isFalse);
    expect(binding.isCurrent, isFalse);
    expect(checks, 1);
  });

  test('an observed owner replacement cannot revive after returning', () {
    bool current = true;
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => current,
    );
    expect(binding.isCurrent, isTrue);
    current = false;
    expect(binding.isCurrent, isFalse);
    current = true;
    expect(binding.takeOpening(), isFalse);
    expect(binding.firstAddress, _first);
  });

  test('failed owner observation refuses without inventing readiness', () {
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => throw StateError('Synthetic owner unavailable'),
    );
    expect(binding.isCurrent, isFalse);
    expect(binding.takeOpening(), isFalse);
  });

  for (final bool light in <bool>[false, true]) {
    for (final bool rtl in <bool>[false, true]) {
      testWidgets(
        'map and glass stay bounded in ${light ? 'light' : 'dark'} '
        '${rtl ? 'RTL' : 'LTR'}',
        (WidgetTester tester) async {
          _prepare(tester);
          final WalletReadyBinding binding = WalletReadyBinding(
            firstAddress: _first,
            isCurrent: () => true,
          );
          await tester.pumpWidget(
            _host(
              _surface(binding: binding),
              light: light,
              rtl: rtl,
              scale: rtl ? 2 : 1,
            ),
          );
          await tester.pump(const Duration(milliseconds: 321));
          expect(
            tester.getSize(find.byKey(const Key('wallet_ready_map'))),
            const Size(1200, 600),
          );
          expect(
            tester.getSize(find.byKey(const Key('wallet_ready_card'))).width,
            540,
          );
          expect(
            tester.widget<FrostedSurface>(find.byType(FrostedSurface)).sigma,
            10,
          );
          expect(
            tester
                .widget<Text>(find.byKey(const Key('wallet_ready_address')))
                .textDirection,
            TextDirection.ltr,
          );
          expect(find.byType(AppLottie), findsNothing);
          expect(find.text('Your wallet is ready'), findsOneWidget);
          expect(find.byType(PrimaryPill), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a reserved opening stays once-only under reentrant callbacks', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    int opens = 0;
    late VoidCallback saved;
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => true,
    );
    await tester.pumpWidget(
      _host(
        _surface(
          binding: binding,
          onOpen: () {
            opens++;
            saved();
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 321));
    saved = _open(tester);
    saved();
    saved();
    await tester.pump();
    expect(opens, 1);
    expect(
      tester
          .widget<PrimaryPill>(find.byKey(const Key('wallet_ready_open')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'copy receives the displayed first address and performs no opening',
    (WidgetTester tester) async {
      _prepare(tester);
      final List<String> copied = <String>[];
      int opens = 0;
      final WalletReadyBinding binding = WalletReadyBinding(
        firstAddress: _first,
        isCurrent: () => true,
      );
      await tester.pumpWidget(
        _host(
          _surface(binding: binding, onCopy: copied.add, onOpen: () => opens++),
        ),
      );
      await tester.pump(const Duration(milliseconds: 321));
      await tester.tap(find.byKey(const Key('wallet_ready_copy')));
      expect(copied, <String>[_first]);
      expect(opens, 0);
      expect(binding.isCurrent, isTrue);
    },
  );

  testWidgets('missing initialization has no fallback address or opening', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    await tester.pumpWidget(_host(_surface(binding: null)));
    await tester.pump(const Duration(milliseconds: 321));
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.byKey(const Key('wallet_ready_copy')), findsNothing);
    expect(
      tester
          .widget<PrimaryPill>(find.byKey(const Key('wallet_ready_open')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('saved callbacks refuse source replacement and disposal', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    int opens = 0;
    final WalletReadyBinding first = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => true,
    );
    final WalletReadyBinding second = WalletReadyBinding(
      firstAddress: 'fixture-second',
      isCurrent: () => true,
    );
    void opened() {
      opens++;
    }

    await tester.pumpWidget(_host(_surface(binding: first, onOpen: opened)));
    await tester.pump(const Duration(milliseconds: 321));
    final VoidCallback stale = _open(tester);
    await tester.pumpWidget(_host(_surface(binding: second, onOpen: opened)));
    stale();
    expect(opens, 0);
    final VoidCallback disposed = _open(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    disposed();
    expect(opens, 0);
  });

  testWidgets(
    'a foreground departure retires the saved callback after resume',
    (WidgetTester tester) async {
      _prepare(tester);
      int opens = 0;
      final WalletReadyBinding binding = WalletReadyBinding(
        firstAddress: _first,
        isCurrent: () => true,
      );
      await tester.pumpWidget(
        _host(_surface(binding: binding, onOpen: () => opens++)),
      );
      await tester.pump(const Duration(milliseconds: 321));
      final VoidCallback saved = _open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      saved();
      expect(opens, 0);
      _open(tester)();
      expect(opens, 1);
    },
  );

  testWidgets('cover and return retire the old route callback', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    int opens = 0;
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => true,
    );
    await tester.pumpWidget(
      _host(
        _surface(binding: binding, onOpen: () => opens++),
        navigator: navigator,
      ),
    );
    await tester.pump(const Duration(milliseconds: 321));
    final VoidCallback saved = _open(tester);
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Fixture cover')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    saved();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    saved();
    expect(opens, 0);
    _open(tester)();
    expect(opens, 1);
  });

  testWidgets('hardware completion claims no seed confirmation', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => true,
    );
    await tester.pumpWidget(_host(_surface(binding: binding, hardware: true)));
    await tester.pump(const Duration(milliseconds: 321));
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Seed'), findsNothing);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('import completion claims no new-wallet seed quiz', (
    WidgetTester tester,
  ) async {
    _prepare(tester);
    final WalletReadyBinding binding = WalletReadyBinding(
      firstAddress: _first,
      isCurrent: () => true,
    );
    await tester.pumpWidget(_host(_surface(binding: binding, imported: true)));
    await tester.pump(const Duration(milliseconds: 321));
    expect(find.text('Seed or file'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });
}
