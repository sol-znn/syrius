import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_view.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';

import 'support.dart';

TextButton _button(WidgetTester tester, String key) =>
    tester.widget<TextButton>(
      find
          .descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(TextButton),
          )
          .first,
    );

Future<void> _reveal(WidgetTester tester, String group) async {
  final Finder toggle = find.byKey(Key('security_settings_${group}_toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.enterText(find.byKey(Key(key)), value);
  await tester.pump();
}

void main() {
  late SecurityPolicyFixture source;
  late SecuritySettingsPresenter presenter;
  late CryptoSessionFixture crypto;
  late ValueNotifier<bool> shown;
  late ValueNotifier<int> scope;
  late GlobalKey<NavigatorState> navigator;
  late int secrets;
  late int exports;
  Completer<void>? routeGate;

  setUp(() {
    source = SecurityPolicyFixture();
    presenter = securityPresenter(source);
    crypto = CryptoSessionFixture();
    shown = ValueNotifier<bool>(true);
    scope = ValueNotifier<int>(0);
    navigator = GlobalKey<NavigatorState>();
    secrets = 0;
    exports = 0;
    routeGate = null;
  });
  tearDown(() async {
    if (!presenter.isClosed) {
      await presenter.close();
    }
    shown.dispose();
    scope.dispose();
  });

  Future<void> open(
    WidgetTester tester, {
    bool light = false,
    bool rtl = false,
    double scale = 1,
    double width = 992,
    bool hardware = false,
    void Function(bool Function())? reset,
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
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: 700,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: shown,
                    builder:
                        (BuildContext context, bool value, Widget? child) =>
                            TickerMode(enabled: value, child: child!),
                    child: ValueListenableBuilder<int>(
                      valueListenable: scope,
                      builder: (BuildContext context, int epoch, Widget? _) =>
                          SecuritySettingsView(
                            presenter: presenter,
                            hardware: hardware,
                            isCurrent: () => scope.value == epoch,
                            captureCrypto: (bool Function() _) => crypto,
                            onShowSeed: (bool Function() current) async {
                              if (current()) {
                                secrets++;
                              }
                              await routeGate?.future;
                            },
                            onExportVault: (bool Function() current) async {
                              if (current()) {
                                exports++;
                              }
                              await routeGate?.future;
                            },
                            onResetWallet: reset,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  for (final bool light in <bool>[false, true]) {
    for (final bool scaled in <bool>[false, true]) {
      testWidgets('measured Security stack light $light scaled RTL $scaled', (
        WidgetTester tester,
      ) async {
        await open(
          tester,
          light: light,
          rtl: scaled,
          scale: scaled ? 1.75 : 1,
          width: scaled ? 500 : 992,
        );
        expect(find.byType(SettingsSection), findsOneWidget);
        expect(find.byType(Panel), findsNWidgets(5));
        final Rect policies = tester.getRect(
          find.byKey(const Key('security_settings_policies')),
        );
        final Rect backup = tester.getRect(
          find.byKey(const Key('security_settings_backup')),
        );
        expect(policies.width, scaled ? 500 : 992);
        expect(backup.width, policies.width);
        expect(backup.top - policies.bottom, 12);
        expect(source.target.calls, isEmpty);
        expect(crypto.calls, isEmpty);
        expect(find.byType(Slider), findsNothing);
        expect(find.text('Confirm'), findsNothing);
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }
  }

  testWidgets('saved positive custom policy appears with mono exact value', (
    WidgetTester tester,
  ) async {
    await presenter.close();
    presenter = SecuritySettingsPresenter(
      initial: const SecuritySettingsState(lockMinutes: 7, wrongPasswords: 4),
      capture: () => source,
    );
    await open(tester);
    final Iterable<Segment<String>> segments = tester
        .widgetList<Segment<String>>(find.byType(Segment<String>));
    expect(segments.first.selected, '7');
    expect(segments.last.selected, '4');
    expect(
      segments.first.items
          .firstWhere((SegmentItem<String> item) => item.value == '7')
          .labelStyle
          ?.fontFamily,
      'JetBrainsMono',
    );
    expect(source.target.calls, isEmpty);
    await close(tester);
  });

  testWidgets('unknown persisted policies do not select invented defaults', (
    WidgetTester tester,
  ) async {
    await presenter.close();
    presenter = SecuritySettingsPresenter(
      initial: const SecuritySettingsState(
        lockMinutes: null,
        wrongPasswords: null,
      ),
      capture: () => source,
    );
    await open(tester);
    for (final Segment<String> segment in tester.widgetList<Segment<String>>(
      find.byType(Segment<String>),
    )) {
      expect(segment.selected, isNull);
    }
    expect(find.text('Setting unavailable'), findsNWidgets(2));
    expect(source.target.calls, isEmpty);
    await close(tester);
  });

  testWidgets('keyboard policy choice saves without a confirmation step', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump(const Duration(milliseconds: 400));
    expect(presenter.state.lockMinutes, 5);
    expect(source.target.saved[SecurityPreference.lockMinutes], 5);
    await close(tester);
  });

  testWidgets('seam controls expose attached disabled nodes without tap', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      final Iterable<SemanticsNode> nodes = find.semantics
          .byLabel('Not yet')
          .evaluate();
      expect(nodes, hasLength(4));
      for (final SemanticsNode node in nodes) {
        expect(node.attached, isTrue);
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      }
      expect(
        tester
            .widget<SeamGate>(
              find.byKey(const Key('security_settings_password_gate')),
            )
            .seam,
        Seam.passwordChangeMigration,
      );
      _button(tester, 'security_settings_password').onPressed!();
      await tester.pump();
      await tester.pump();
      expect(source.target.calls, isEmpty);
      expect(crypto.calls, isEmpty);
      expect(
        find.text('Password changes are not available yet.'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
    await close(tester);
  });

  testWidgets('hardware Backup rows have no direct activation callback', (
    WidgetTester tester,
  ) async {
    await open(tester, hardware: true);
    expect(_button(tester, 'security_settings_show_seed').onPressed, isNull);
    expect(_button(tester, 'security_settings_export_vault').onPressed, isNull);
    expect(secrets, 0);
    expect(exports, 0);
    await close(tester);
  });

  testWidgets('saved Backup callback reserves once before a deferred read', (
    WidgetTester tester,
  ) async {
    routeGate = Completer<void>();
    await open(tester);
    final VoidCallback callback = _button(
      tester,
      'security_settings_export_vault',
    ).onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(exports, 1);
    routeGate!.complete();
    await tester.pump();
    await close(tester);
  });

  testWidgets('old section callback cannot adopt a fresh true predicate', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final VoidCallback callback = _button(
      tester,
      'security_settings_show_seed',
    ).onPressed!;
    scope.value++;
    await tester.pump();
    callback();
    await tester.pump();
    expect(secrets, 0);
    await close(tester);
  });

  testWidgets('closed Sign form leaves actual attached input semantics', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      expect(find.semantics.byLabel('Message'), findsNothing);
      await _reveal(tester, 'sign');
      final Finder message = find.byKey(const Key('security_sign_message'));
      await tester.ensureVisible(message);
      await tester.pump();
      expect(message.hitTestable(), findsOneWidget);
      final SemanticsNode inputSemantics = tester.getSemantics(message);
      expect(find.semantics.byLabel('Message'), findsOneWidget);
      expect(inputSemantics.attached, isTrue);
      final SemanticsData inputData = inputSemantics.getSemanticsData();
      expect(inputData.label, 'Message');
      expect(inputData.flagsCollection.isTextField, isTrue);
      await _reveal(tester, 'sign');
      expect(find.semantics.byLabel('Message'), findsNothing);
      expect(inputSemantics.attached, isFalse);
    } finally {
      semantics.dispose();
    }
    await close(tester);
  });

  testWidgets('exact 32 UTF-8 byte text cannot invoke signing', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await _reveal(tester, 'sign');
    await _enter(
      tester,
      'security_sign_message',
      List<String>.filled(16, 'é').join(),
    );
    expect(_button(tester, 'security_sign_text').onPressed, isNull);
    expect(crypto.calls, isEmpty);
    await close(tester);
  });

  testWidgets('injected successful signing preserves exact input and result', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await _reveal(tester, 'sign');
    await _enter(tester, 'security_sign_message', 'original message');
    _button(tester, 'security_sign_text').onPressed!();
    await tester.pump();
    expect(crypto.calls, <String>['text:original message']);
    expect(find.text('signed text'), findsOneWidget);
    await close(tester);
  });

  testWidgets('saved Sign callback cannot survive disclosure reversal', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await _reveal(tester, 'sign');
    await _enter(tester, 'security_sign_message', 'original');
    final VoidCallback callback = _button(
      tester,
      'security_sign_text',
    ).onPressed!;
    await _reveal(tester, 'sign');
    await _reveal(tester, 'sign');
    callback();
    await tester.pump();
    expect(crypto.calls, isEmpty);
    await close(tester);
  });

  testWidgets('late signing result cannot paint after hidden round trip', (
    WidgetTester tester,
  ) async {
    crypto.signGate = Completer<SecuritySignature>();
    await open(tester);
    await _reveal(tester, 'sign');
    await _enter(tester, 'security_sign_message', 'original');
    _button(tester, 'security_sign_text').onPressed!();
    await tester.pump();
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    crypto.signGate!.complete(
      const SecuritySignature(signature: 'late result', publicKey: 'late key'),
    );
    await tester.pump();
    expect(find.text('late result'), findsNothing);
    expect(crypto.calls, <String>['text:original']);
    await close(tester);
  });

  testWidgets('deferred paste cannot fill a replacement section field', (
    WidgetTester tester,
  ) async {
    crypto.inputGate = Completer<String?>();
    await open(tester);
    await _reveal(tester, 'verify');
    final Finder paste = find.descendant(
      of: find.byKey(const Key('security_verify_message')),
      matching: find.byType(IconButton),
    );
    tester.widget<IconButton>(paste).onPressed!();
    await tester.pump();
    scope.value++;
    await tester.pump();
    crypto.inputGate!.complete('late paste');
    await tester.pump();
    expect(find.text('late paste'), findsNothing);
    expect(crypto.calls, <String>['paste']);
    await close(tester);
  });

  testWidgets('verification uses the exact original triple', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await _reveal(tester, 'verify');
    await _enter(tester, 'security_verify_message', 'message');
    await _enter(tester, 'security_verify_signature', 'signature');
    await _enter(tester, 'security_verify_public_key', 'public key');
    _button(tester, 'security_verify_text').onPressed!();
    await tester.pump();
    expect(crypto.calls, <String>['verify:message:signature:public key']);
    expect(find.text('Signature verified'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Remove callback needs expanded group and root handoff owner', (
    WidgetTester tester,
  ) async {
    bool Function()? continuation;
    int requests = 0;
    await open(
      tester,
      reset: (bool Function() current) {
        continuation = current;
        requests++;
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext _) =>
                const Scaffold(body: Text('owned question')),
          ),
        );
      },
    );
    await _reveal(tester, 'remove');
    _button(tester, 'security_settings_remove_wallet').onPressed!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, 1);
    expect(continuation!(), isTrue);
    scope.value++;
    await tester.pump();
    expect(continuation!(), isFalse);
    expect(find.text('owned question'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'Remove stays unavailable without the root maintenance callback',
    (WidgetTester tester) async {
      await open(tester);
      await _reveal(tester, 'remove');
      expect(
        _button(tester, 'security_settings_remove_wallet').onPressed,
        isNull,
      );
      await close(tester);
    },
  );
}
