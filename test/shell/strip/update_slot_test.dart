import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/update_slot.dart';

Widget _app(Widget child, {bool dark = true}) => MaterialApp(
  theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final bool dark in <bool>[true, false]) {
    testWidgets(
      'default update slot claims no release in ${dark ? 'dark' : 'light'}',
      (WidgetTester tester) async {
        await tester.pumpWidget(_app(const WalletUpdateSlot(), dark: dark));
        expect(find.text('Wallet updates'), findsOneWidget);
        expect(find.text('Update'), findsOneWidget);
        expect(find.textContaining('is out'), findsNothing);
        expect(find.byType(SeamGate), findsOneWidget);
        expect(
          tester.widget<SeamGate>(find.byType(SeamGate)).seam,
          Seam.walletUpdateNotice,
        );
        expect(
          tester.getSize(find.byKey(const Key('strip_update_button'))).height,
          26,
        );
        await tester.tap(
          find.byKey(const Key('strip_update_button')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an explicit display version is drawn but remains seamed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(const WalletUpdateSlot(version: '0.3.0')));
    expect(find.text('Syrius 0.3.0 is out'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('strip_update_button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard and semantics cannot activate the update control', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      int outside = 0;
      await tester.pumpWidget(
        _app(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const WalletUpdateSlot(),
              TextButton(
                onPressed: () {
                  outside++;
                },
                child: const Text('Outside'),
              ),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(outside, 1);
      expect(find.semantics.byLabel('Update'), findsNothing);
      final SemanticsNode node = tester.getSemantics(find.byType(SeamGate));
      expect(
        node,
        isSemantics(label: 'Not yet', hasEnabledState: true, isEnabled: false),
      );
      for (final ui.SemanticsAction action in <ui.SemanticsAction>[
        ui.SemanticsAction.tap,
        ui.SemanticsAction.longPress,
        ui.SemanticsAction.focus,
      ]) {
        expect(node.getSemanticsData().hasAction(action), isFalse);
        node.owner!.performAction(node.id, action);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
