import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/wallet_connect_widgets/wallet_connect_qr_card.dart';

import 'support.dart';

Widget _host(
  AppsFixture source,
  AppsSettingsBinding binding, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  double width = 1000,
}) {
  final bool Function() current = source.captureView();
  return MaterialApp(
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: const Locale('en'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(1280, 780),
        textScaler: TextScaler.linear(scale),
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 650,
              child: AppsSettingsSection(binding: binding, isCurrent: current),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _prepare(
  WidgetTester tester,
  AppsFixture source,
  AppsSettingsBinding binding, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  double width = 1000,
}) async {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(source, binding, light: light, rtl: rtl, scale: scale, width: width),
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (int frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void _appsTestWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (WidgetTester tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

OutlinedButton _action(WidgetTester tester, String key) =>
    tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(OutlinedButton),
      ),
    );

void main() {
  late AppsFixture source;
  setUp(() => source = AppsFixture());
  tearDown(() => source.close());

  for (final bool light in <bool>[false, true]) {
    _appsTestWidgets(
      'one switch, combined facts and closed details in '
      '${light ? 'light' : 'dark'}',
      (WidgetTester tester) async {
        await _prepare(tester, source, source.bind(), light: light);
        expect(find.byType(SettingsSwitch), findsOneWidget);
        expect(find.text('sample.example'), findsOneWidget);
        expect(find.text('Example app'), findsOneWidget);
        expect(find.text('Unknown'), findsNWidgets(2));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('apps_settings_count')))
              .data,
          '2',
        );
        expect(find.text('1 session · 1 pairing'), findsOneWidget);
        final Disclosure disclosure = tester.widget<Disclosure>(
          find.byType(Disclosure),
        );
        expect(disclosure.controller!.isOpen, isFalse);
        expect(
          find.byKey(const Key('apps_pairing_disconnect_0')),
          findsNothing,
        );
        expect(source.writes, isEmpty);
        expect(source.actions, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _appsTestWidgets(
    'switch saves before applying and never shows an optimistic value',
    (WidgetTester tester) async {
      source.deferredPersistence = true;
      final AppsSettingsBinding binding = source.bind();
      await _prepare(tester, source, binding);
      await tester.tap(find.byKey(const Key('apps_settings_web_switch')));
      await tester.pump();
      expect(source.writes, hasLength(1));
      expect(source.actions, isEmpty);
      expect(
        tester
            .widget<SettingsSwitch>(
              find.byKey(const Key('apps_settings_web_switch')),
            )
            .value,
        isTrue,
      );
      source.writes.single.complete();
      await _frames(tester);
      expect(source.actions.single, (AppsActionKind.webApps, false));
      expect(
        tester
            .widget<SettingsSwitch>(
              find.byKey(const Key('apps_settings_web_switch')),
            )
            .value,
        isFalse,
      );
      expect(find.text('Off'), findsOneWidget);
      expect(binding.outcomes.single.status, AppsActionStatus.completed);
    },
  );

  _appsTestWidgets(
    'a saved old callback cannot affect a replacement connection',
    (
      WidgetTester tester,
    ) async {
      await _prepare(tester, source, source.bind());
      final VoidCallback original = _action(
        tester,
        'apps_disconnect_1',
      ).onPressed!;
      source.revision++;
      source.changes.add(null);
      await tester.pump();
      original();
      await _frames(tester);
      expect(source.writes, isEmpty);
      expect(source.actions, isEmpty);
      expect(find.text('Example app'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('apps_settings_count'))).data,
        'Unknown',
      );
    },
  );

  _appsTestWidgets(
    'an old rendered callback cannot target a new presenter with '
    'identical rows',
    (WidgetTester tester) async {
      await _prepare(tester, source, source.bind());
      final VoidCallback original = _action(
        tester,
        'apps_disconnect_0',
      ).onPressed!;
      source
        ..box = Object()
        ..entries = <String, Object?>{};
      final AppsSettingsBinding replacement = source.bind();
      await tester.pumpWidget(_host(source, replacement));
      original();
      await _frames(tester);
      expect(source.writes, isEmpty);
      expect(source.actions, isEmpty);
      expect(source.rows, hasLength(2));
    },
  );

  _appsTestWidgets(
    'closing the view during persistence cannot start its old disconnect',
    (WidgetTester tester) async {
      source.deferredPersistence = true;
      final AppsSettingsBinding binding = source.bind();
      await _prepare(tester, source, binding);
      await tester.tap(find.byKey(const Key('apps_disconnect_1')));
      await tester.pump();
      expect(source.writes, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      source.writes.single.complete();
      await _frames(tester);
      expect(source.actions, isEmpty);
      expect(binding.outcomes.single.status, AppsActionStatus.refused);
      expect(tester.takeException(), isNull);
    },
  );

  _appsTestWidgets('original accepted results survive unmounting', (
    WidgetTester tester,
  ) async {
    final Completer<Object?> response = Completer<Object?>();
    source.effect = (_, _) => response.future;
    final AppsSettingsBinding binding = source.bind();
    await _prepare(tester, source, binding);
    await tester.tap(find.byKey(const Key('apps_disconnect_1')));
    await _frames(tester);
    expect(source.actions, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    final Object accepted = Object();
    response.complete(accepted);
    await _frames(tester);
    expect(binding.outcomes.single.status, AppsActionStatus.completed);
    expect(binding.outcomes.single.effectResult, same(accepted));
    expect(identical(binding.outcomes.single.effect, response.future), isTrue);
    expect(tester.takeException(), isNull);
  });

  _appsTestWidgets('advanced pairing disconnection preserves the session row', (
    WidgetTester tester,
  ) async {
    await _prepare(tester, source, source.bind());
    await tester.tap(find.byKey(const Key('apps_settings_details_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final Finder action = find.byKey(const Key('apps_pairing_disconnect_0'));
    await tester.ensureVisible(action);
    await tester.pump();
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await _frames(tester);
    expect(source.actions.single.$1, AppsActionKind.disconnectPairing);
    expect(source.pairings, isEmpty);
    expect(
      source.rows.where(
        (AppsConnection row) => row.kind == AppsConnectionKind.walletConnect,
      ),
      hasLength(1),
    );
  });

  _appsTestWidgets(
    'link entry admits only a validated original URI and closes its own route',
    (WidgetTester tester) async {
      final AppsSettingsBinding binding = source.bind();
      await _prepare(tester, source, binding);
      await tester.tap(find.byKey(const Key('apps_settings_connect')));
      await tester.pump(const Duration(milliseconds: 240));
      await tester.enterText(find.byKey(const Key('wc_link')), 'wc:invalid');
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('wc_connect')))
            .onPressed,
        isNull,
      );
      expect(source.writes, isEmpty);
      await tester.enterText(
        find.byKey(const Key('wc_link')),
        validPairingLink,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('wc_connect')));
      await _frames(tester);
      expect(source.actions.single.$1, AppsActionKind.pair);
      expect('${source.actions.single.$2}', validPairingLink);
      expect(
        source.writes.single.intent.stored.keys,
        unorderedEquals(<String>['version', 'sequence', 'action']),
      );
      expect(find.byKey(const Key('apps_pair_dialog')), findsNothing);
      expect(
        source.rows,
        hasLength(2),
        reason: 'pairing does not invent an approved session',
      );
    },
  );

  _appsTestWidgets('invalid in-memory screen QR data never reaches pairing', (
    WidgetTester tester,
  ) async {
    int captures = 0;
    int pairs = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WalletConnectQrCard(
            isCurrent: () => true,
            capture: () {
              captures++;
              return Future<Uint8List?>.value(
                Uint8List.fromList(<int>[0, 1, 2]),
              );
            },
            onPair: (Uri uri, bool Function() owns) async {
              pairs++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('wc_scan_screen')));
    await _frames(tester);
    expect(captures, 1);
    expect(pairs, 0);
    expect(find.text('Invalid QR code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _appsTestWidgets(
    'large text and RTL retain every table action without overflow',
    (
      WidgetTester tester,
    ) async {
      await _prepare(
        tester,
        source,
        source.bind(),
        rtl: true,
        scale: 2,
        width: 700,
      );
      expect(find.byKey(const Key('apps_settings_web_switch')), findsOneWidget);
      expect(find.byKey(const Key('apps_settings_connect')), findsOneWidget);
      expect(find.byKey(const Key('apps_disconnect_0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
