import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/change_wallet_password_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/dump_mnemonic_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/export/export_wallet_info_screen.dart';
import 'package:zenon_syrius_wallet_flutter/screens/export/export_wallet_password_screen.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

import 'support.dart';

class _PasswordSession implements SettingsPasswordSession {
  bool current = true;
  final List<String> calls = <String>[];
  Completer<void>? gate;

  @override
  bool get isCurrent => current;

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    calls.add('$currentPassword:$newPassword');
    await gate?.future;
  }
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final Finder field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _frame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _until(
  WidgetTester tester,
  bool Function() complete, {
  String Function()? diagnostic,
}) async {
  for (int frame = 0; frame < 100 && !complete(); frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    complete(),
    isTrue,
    reason: diagnostic == null
        ? 'the exact owned receipt settles within one second'
        : 'the exact owned receipt settles within one second: ${diagnostic()}',
  );
}

Future<void> _receipt<T>(WidgetTester tester, Future<T> receipt) async {
  bool completed = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    receipt.then<void>(
      (T _) {
        completed = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        completed = true;
      },
    ),
  );
  await _until(tester, () => completed);
  if (failure != null) {
    Error.throwWithStackTrace(failure!, trace!);
  }
}

void main() {
  late GlobalKey<NavigatorState> navigator;
  late SettingsSensitiveRoutes routes;
  late SensitiveSessionFixture source;
  late bool current;

  setUp(() {
    navigator = GlobalKey<NavigatorState>();
    routes = SettingsSensitiveRoutes();
    source = SensitiveSessionFixture();
    current = true;
  });

  Future<void> host(
    WidgetTester tester, {
    Widget? child,
    bool light = false,
    bool rtl = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: child ?? const Scaffold(body: Text('original parent')),
      ),
    );
    await _frame(tester);
  }

  Future<void> close(WidgetTester tester) async {
    final Iterable<Element> visibleInfo = find
        .byType(ExportWalletInfoScreen)
        .evaluate();
    final ModalRoute<void>? visibleRoute = visibleInfo.isEmpty
        ? null
        : ModalRoute.of<void>(visibleInfo.single);
    final TransitionRoute<void>? originalInfo =
        visibleRoute is TransitionRoute<void> ? visibleRoute : null;
    bool popped = false;
    bool completed = false;
    if (originalInfo != null) {
      unawaited(originalInfo.popped.then<void>((_) => popped = true));
      unawaited(originalInfo.completed.then<void>((_) => completed = true));
    }
    routes.close();
    await _until(
      tester,
      () => !routes.busy && (originalInfo == null || (popped && completed)),
      diagnostic: () =>
          'Info=${originalInfo != null}, popped=$popped, completed=$completed, '
          'active=${originalInfo?.isActive}, '
          'current=${originalInfo?.isCurrent}',
    );
    await _frame(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _frame(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> fillVault(WidgetTester tester) async {
    await _enter(tester, 'security_vault_key', 'Example!123');
    await _enter(tester, 'security_vault_repeat', 'Example!123');
  }

  Future<void> fillPassword(WidgetTester tester) async {
    await _enter(tester, 'security_password_current', 'Old!1234');
    await _enter(tester, 'security_password_new', 'New!1234');
    await _enter(tester, 'security_password_repeat', 'New!1234');
  }

  Future<void> openInfo(WidgetTester tester, {VoidCallback? complete}) async {
    unawaited(
      routes.open(
        navigator: navigator.currentState!,
        isCurrent: () => current,
        builder: (SettingsRouteLease lease) => ExportWalletInfoScreen(
          'synthetic seed',
          backupWalletFlow: true,
          session: source,
          routeLease: lease,
          onExported: complete,
        ),
      ),
    );
    await _frame(tester);
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets('password child scales in RTL with no backend, light $light', (
      WidgetTester tester,
    ) async {
      await host(
        tester,
        light: light,
        rtl: true,
        scale: 1.75,
        child: ChangeWalletPasswordScreen(
          onStepperNotificationSeeMorePressed: () {},
        ),
      );
      await fillPassword(tester);
      expect(find.byType(SeamGate), findsOneWidget);
      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.byKey(const Key('security_password_change')),
      );
      button.onPressed!();
      await _frame(tester);
      expect(
        find.text('Password changes are not available yet.'),
        findsOneWidget,
      );
      expect(navigator.currentState!.canPop(), isFalse);
      await close(tester);
    });
  }

  testWidgets(
    'injected password session snapshots both inputs and reserves once',
    (WidgetTester tester) async {
      final _PasswordSession password = _PasswordSession()
        ..gate = Completer<void>();
      await host(
        tester,
        child: ChangeWalletPasswordScreen(
          session: password,
          onStepperNotificationSeeMorePressed: () {},
        ),
      );
      await fillPassword(tester);
      final VoidCallback callback = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('security_password_change')),
          )
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(password.calls, <String>['Old!1234:New!1234']);
      await tester.pumpWidget(const SizedBox.shrink());
      password.gate!.complete();
      await _frame(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved seed Show callback refuses a replaced external source', (
    WidgetTester tester,
  ) async {
    bool original = true;
    await host(
      tester,
      child: DumpMnemonicScreen(session: source, isCurrent: () => original),
    );
    await _enter(tester, 'security_seed_password', 'Original!123');
    final VoidCallback callback = tester
        .widget<OutlinedButton>(find.byKey(const Key('security_seed_show')))
        .onPressed!;
    original = false;
    callback();
    await tester.pump();
    expect(source.reveals, 0);
    await close(tester);
  });

  testWidgets('seed double activation admits one immutable original password', (
    WidgetTester tester,
  ) async {
    source.revealGate = Completer<List<String>>();
    await host(tester, child: DumpMnemonicScreen(session: source));
    await _enter(tester, 'security_seed_password', 'Original!123');
    final VoidCallback callback = tester
        .widget<OutlinedButton>(find.byKey(const Key('security_seed_show')))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(source.reveals, 1);
    expect(source.password, 'Original!123');
    await tester.pumpWidget(const SizedBox.shrink());
    source.revealGate!.complete(List<String>.filled(24, 'synthetic'));
    await _frame(tester);
    expect(find.byKey(const Key('seed_phrase_words')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unobserved unrelated coverage round trip refuses late seed paint',
    (WidgetTester tester) async {
      source.revealGate = Completer<List<String>>();
      await host(tester, child: DumpMnemonicScreen(session: source));
      await _enter(tester, 'security_seed_password', 'Original!123');
      tester
          .widget<OutlinedButton>(find.byKey(const Key('security_seed_show')))
          .onPressed!();
      await tester.pump();
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext _) =>
              const Scaffold(body: Text('unrelated route')),
        ),
      );
      await _frame(tester);
      navigator.currentState!.pop();
      await _frame(tester);
      source.revealGate!.complete(List<String>.filled(24, 'synthetic'));
      await _frame(tester);
      expect(find.byKey(const Key('seed_phrase_words')), findsNothing);
      expect(source.reveals, 1);
      await close(tester);
    },
  );

  testWidgets('hardware seed direct callback refuses without an acquisition', (
    WidgetTester tester,
  ) async {
    source.hardware = true;
    await host(tester, child: DumpMnemonicScreen(session: source));
    await _enter(tester, 'security_seed_password', 'Original!123');
    tester
        .widget<OutlinedButton>(find.byKey(const Key('security_seed_show')))
        .onPressed!();
    await tester.pump();
    expect(source.reveals, 0);
    await close(tester);
  });

  testWidgets('seed Enter uses the actual single-line text input action', (
    WidgetTester tester,
  ) async {
    await host(tester, child: DumpMnemonicScreen(session: source));
    await _enter(tester, 'security_seed_password', 'Original!123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _frame(tester);
    expect(source.reveals, 1);
    expect(source.password, 'Original!123');
    expect(find.byKey(const Key('seed_phrase_words')), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'Vault promise is required and duplicate Continue owns one child',
    (WidgetTester tester) async {
      await host(tester);
      await openInfo(tester);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('export_seed_vault_continue')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('export_seed_vault_promise')));
      await tester.pump();
      final VoidCallback next = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('export_seed_vault_continue')),
          )
          .onPressed!;
      next();
      next();
      await _frame(tester);
      expect(find.byType(ExportWalletPasswordScreen), findsOneWidget);
      expect(routes.busy, isTrue);
      expect(source.exports, 0);
      await close(tester);
    },
  );

  testWidgets('owned two-step export returns only its exact chain to parent', (
    WidgetTester tester,
  ) async {
    int notices = 0;
    await host(tester);
    await openInfo(tester, complete: () => notices++);
    await tester.tap(find.byKey(const Key('export_seed_vault_promise')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('export_seed_vault_continue')));
    await _frame(tester);
    await fillVault(tester);
    await tester.tap(find.byKey(const Key('export_seed_vault_export')));
    await _until(tester, () => !routes.busy);
    expect(source.exports, 1);
    expect(source.password, 'Example!123');
    expect(notices, 1);
    expect(find.text('original parent'), findsOneWidget);
    expect(routes.busy, isFalse);
    await close(tester);
  });

  testWidgets('settled owned Info closes without another input or animation', (
    WidgetTester tester,
  ) async {
    await host(tester);
    await openInfo(tester);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(ExportWalletInfoScreen), findsOneWidget);
    expect(routes.busy, isTrue);
    await close(tester);
    expect(routes.busy, isFalse);
  });

  testWidgets(
    'retained Info Continue cannot revive after owned Back round trip',
    (WidgetTester tester) async {
      await host(tester);
      await openInfo(tester);
      await tester.tap(find.byKey(const Key('export_seed_vault_promise')));
      await tester.pump();
      final VoidCallback old = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('export_seed_vault_continue')),
          )
          .onPressed!;
      old();
      await _frame(tester);
      final TransitionRoute<void> original =
          ModalRoute.of<void>(
                tester.element(find.byType(ExportWalletPasswordScreen)),
              )!
              as TransitionRoute<void>;
      await tester.tap(find.text('Back'));
      await _receipt(tester, original.completed);
      await tester.pump();
      old();
      await _frame(tester);
      expect(find.byType(ExportWalletPasswordScreen), findsNothing);
      expect(find.byType(ExportWalletInfoScreen), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('late export result cannot pop an unrelated covering route', (
    WidgetTester tester,
  ) async {
    source.exportGate = Completer<bool>();
    int notices = 0;
    await host(tester);
    await openInfo(tester, complete: () => notices++);
    await tester.tap(find.byKey(const Key('export_seed_vault_promise')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('export_seed_vault_continue')));
    await _frame(tester);
    await fillVault(tester);
    final VoidCallback export = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('export_seed_vault_export')),
        )
        .onPressed!;
    export();
    export();
    await tester.pump();
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            const Scaffold(body: Text('unrelated route')),
      ),
    );
    await _frame(tester);
    source.exportGate!.complete(true);
    await _frame(tester);
    expect(source.exports, 1);
    expect(notices, 0);
    expect(find.text('unrelated route'), findsOneWidget);
    routes.close();
    await _frame(tester);
    expect(find.text('unrelated route'), findsOneWidget);
    navigator.currentState!.pop();
    await _frame(tester);
    expect(find.text('original parent'), findsOneWidget);
    expect(find.byType(ExportWalletInfoScreen), findsNothing);
    await close(tester);
  });

  testWidgets(
    'stale original Vault callback cannot release replacement owner',
    (WidgetTester tester) async {
      await host(tester);
      await openInfo(tester);
      await tester.tap(find.byKey(const Key('export_seed_vault_promise')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('export_seed_vault_continue')));
      await _frame(tester);
      await fillVault(tester);
      final VoidCallback old = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('export_seed_vault_export')),
          )
          .onPressed!;
      routes.close();
      await _until(tester, () => !routes.busy);
      routes = SettingsSensitiveRoutes();
      await openInfo(tester);
      old();
      await _frame(tester);
      expect(source.exports, 0);
      expect(find.byType(ExportWalletInfoScreen), findsOneWidget);
      expect(routes.busy, isTrue);
      await close(tester);
    },
  );
}
