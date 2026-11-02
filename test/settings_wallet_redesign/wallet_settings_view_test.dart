import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_switch.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_options.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';

import 'support.dart';

const Key _auto = Key('wallet_settings_autoReceive');
const Key _notifications = Key('wallet_settings_desktopNotifications');
const Key _clipboard = Key('wallet_settings_clipboard');
const Key _maintenance = Key('wallet_settings_maintenance_toggle');

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (int frame = 0; frame < 100 && !done(); frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'the original settles within one second');
}

Widget _host(
  WalletSettingsFixture source,
  WalletSettingsBinding binding, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  bool disableAnimations = false,
  void Function(bool Function())? delete,
  void Function(bool Function())? reset,
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
        disableAnimations: disableAnimations,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1000,
              height: 650,
              child: WalletOptions(
                binding: binding,
                isCurrent: current,
                scanForReceives: () async => fail('injected owner only'),
                onDeleteCache: delete ?? (_) {},
                onResetWallet: reset ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _prepare(
  WidgetTester tester,
  WalletSettingsFixture source,
  WalletSettingsBinding binding, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  bool disableAnimations = false,
  void Function(bool Function())? delete,
  void Function(bool Function())? reset,
}) async {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.reset();
  });
  await tester.pumpWidget(
    _host(
      source,
      binding,
      light: light,
      rtl: rtl,
      scale: scale,
      disableAnimations: disableAnimations,
      delete: delete,
      reset: reset,
    ),
  );
}

SettingsSwitch _switch(WidgetTester tester, Key key) =>
    tester.widget<SettingsSwitch>(find.byKey(key, skipOffstage: false));

Disclosure _maintenanceDisclosure(WidgetTester tester) =>
    tester.widget<Disclosure>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Disclosure && widget.title == 'Maintenance',
      ),
    );

bool _focusWithin(WidgetTester tester, Key key) {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  final Element target = tester.element(find.byKey(key));
  bool found = false;
  context.visitAncestorElements((Element element) {
    found = identical(target, element);
    return !found;
  });
  return found;
}

void main() {
  for (final (bool, bool, double) variant in <(bool, bool, double)>[
    (false, false, 1),
    (true, true, 1.5),
  ]) {
    testWidgets('full-width Wallet has natural rows in variant $variant', (
      WidgetTester tester,
    ) async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      final WalletSettingsBinding binding = source.bind();
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await _prepare(
          tester,
          source,
          binding,
          light: variant.$1,
          rtl: variant.$2,
          scale: variant.$3,
        );
        final Size panel = tester.getSize(
          find.byKey(const Key('wallet_settings_preferences')),
        );
        expect(panel.width, 1000);
        expect(find.text('Preferences'), findsNothing);
        expect(_switch(tester, _auto).value, isTrue);
        expect(_switch(tester, _notifications).value, isFalse);
        expect(_switch(tester, _clipboard).value, isFalse);
        expect(find.byKey(_clipboard).hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Clipboard watcher'), findsNothing);
        expect(
          find.byKey(const Key('wallet_settings_reset_wallet')).hitTestable(),
          findsNothing,
        );
        expect(find.byType(SeamGate), findsNWidgets(2));
        expect(find.text('Wallets on this computer'), findsOneWidget);
        expect(find.text('3'), findsNothing);
        expect(source.store.writes, isEmpty);
        expect(source.effects, isEmpty);
        await tester.ensureVisible(find.byKey(_maintenance));
        await tester.tap(find.byKey(_maintenance));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        await tester.ensureVisible(find.byKey(_clipboard));
        expect(find.byKey(_clipboard).hitTestable(), findsOneWidget);
        expect(find.semantics.byLabel('Clipboard watcher'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('owning widget retains an admitted write across disposal', (
    WidgetTester tester,
  ) async {
    final WalletSettingsFixture source = WalletSettingsFixture();
    source.store.deferred = true;
    final WalletSettingsBinding binding = source.bind();
    await _prepare(tester, source, binding);
    final ValueChanged<bool> old = _switch(tester, _auto).onChanged!;
    await tester.tap(find.byKey(_auto));
    await tester.pump();
    expect(source.store.writes, hasLength(1));
    expect(_switch(tester, _auto).value, isTrue);
    expect(_switch(tester, _auto).onChanged, isNull);
    final Future<WalletPreferenceOutcome> original = binding.pending(
      WalletPreference.autoReceive,
    )!;
    await tester.pumpWidget(const SizedBox.shrink());
    source.leaveAndReturn();
    final WalletSettingsBinding remounted = source.bind();
    await tester.pumpWidget(_host(source, remounted));
    expect(_switch(tester, _auto).onChanged, isNull);
    expect(remounted.pending(WalletPreference.autoReceive), same(original));
    old(false);
    expect(source.store.writes, hasLength(1));
    source.store.writes.single.complete();
    await _until(tester, () => binding.outcomes.length == 1);
    final WalletPreferenceOutcome outcome = await original;
    await tester.pump();
    expect(outcome.status, WalletPreferenceStatus.applied);
    expect(outcome.write, same(source.store.writes.single.reply.future));
    expect(remounted.outcomes.single, same(outcome));
    expect(_switch(tester, _auto).value, isFalse);
    expect(_switch(tester, _auto).onChanged, isNotNull);
    expect(source.effects, hasLength(1));
    expect(source.notices, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard operates live switches and skips seamed choices', (
    WidgetTester tester,
  ) async {
    final WalletSettingsFixture source = WalletSettingsFixture();
    final WalletSettingsBinding binding = source.bind();
    await _prepare(tester, source, binding);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusWithin(tester, _auto), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusWithin(tester, _notifications), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_focusWithin(tester, _auto), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _until(tester, () => binding.outcomes.length == 1);
    await tester.pump(const Duration(milliseconds: 180));
    expect(_switch(tester, _auto).value, isFalse);
    final Iterable<ChoicePills<String>> modes = tester
        .widgetList<ChoicePills<String>>(
          find.byType(ChoicePills<String>),
        );
    for (final ChoicePills<String> choices in modes) {
      choices.onSelected('on');
    }
    expect(source.store.writes, hasLength(1));
    expect(binding.outcomes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final bool disabled in <bool>[false, true]) {
    testWidgets('Maintenance reversal revokes saved input, OS flag $disabled', (
      WidgetTester tester,
    ) async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      final WalletSettingsBinding binding = source.bind();
      int resets = 0;
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await _prepare(
          tester,
          source,
          binding,
          disableAnimations: disabled,
          reset: (_) => resets++,
        );
        await tester.tap(find.byKey(_maintenance));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        final ValueChanged<bool> old = _switch(tester, _clipboard).onChanged!;
        final VoidCallback oldReset = tester
            .widget<OutlinedButton>(
              find.byKey(const Key('wallet_settings_reset_wallet')),
            )
            .onPressed!;
        final DisclosureController controller =
            _maintenanceDisclosure(
                tester,
              ).controller!
              ..close()
              ..open();
        old(true);
        oldReset();
        expect(source.store.writes, isEmpty);
        expect(resets, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        controller.close();
        await tester.pump();
        expect(find.semantics.byLabel('Clipboard watcher'), findsNothing);
        expect(find.byKey(_clipboard).hitTestable(), findsNothing);
        await tester.pump(const Duration(milliseconds: 80));
        controller.open();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        controller.close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        controller.open();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        expect(find.semantics.byLabel('Clipboard watcher'), findsOneWidget);
        await tester.tap(find.byKey(_clipboard));
        await _until(tester, () => binding.outcomes.length == 1);
        expect(source.effects.single, (WalletPreference.clipboard, true));
        expect(resets, 0);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('replaced resources preserve the original owning-card write', (
    WidgetTester tester,
  ) async {
    final WalletSettingsFixture source = WalletSettingsFixture();
    source.store.deferred = true;
    final WalletSettingsBinding binding = source.bind();
    await _prepare(tester, source, binding);
    await tester.tap(find.byKey(_notifications));
    await tester.pump();
    source.revision++;
    source.store.writes.single.complete();
    await _until(tester, () => binding.outcomes.length == 1);
    expect(binding.outcomes.single.committed, isTrue);
    expect(source.effects, isEmpty);
    expect(source.notices, isEmpty);
    expect(find.text('Saved. Could not apply.'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maintenance source survives own coverage and binds its group', (
    WidgetTester tester,
  ) async {
    final WalletSettingsFixture source = WalletSettingsFixture();
    final WalletSettingsBinding binding = source.bind();
    bool Function()? cacheSource;
    bool Function()? resetSource;
    int captures = 0;
    await _prepare(
      tester,
      source,
      binding,
      delete: (bool Function() original) {
        captures++;
        cacheSource = original;
      },
      reset: (bool Function() original) => resetSource = original,
    );
    final VoidCallback oldCache = tester
        .widget<TextButton>(
          find.byKey(const Key('wallet_settings_delete_cache')),
        )
        .onPressed!;
    oldCache();
    expect(cacheSource!(), isTrue);
    final NavigatorState navigator = Navigator.of(
      tester.element(
        find.byKey(const Key('wallet_settings_delete_cache')),
      ),
    );
    final MaterialPageRoute<void> question = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Owned question')),
    );
    navigator.push<void>(question);
    await tester.pump();
    expect(cacheSource!(), isTrue);
    oldCache();
    expect(captures, 1);
    navigator.pop();
    bool complete = false;
    unawaited(question.completed.then<void>((_) => complete = true));
    await _until(tester, () => complete);
    await tester.pump();
    await tester.tap(find.byKey(_maintenance));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final VoidCallback oldReset = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('wallet_settings_reset_wallet')),
        )
        .onPressed!;
    oldReset();
    expect(resetSource!(), isTrue);
    _maintenanceDisclosure(
        tester,
      ).controller!
      ..close()
      ..open();
    expect(resetSource!(), isFalse);
    source.leaveAndReturn();
    expect(cacheSource!(), isFalse);
    expect(binding.outcomes, isEmpty);
    expect(source.store.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
