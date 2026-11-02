import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/p2p_swap_warning_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/p2p_swap_options_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/transfer_toggle_card_size_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/dialogs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../swap_list_redesign/support.dart';

class _WarningPreferences extends SharedPrefsService {
  int reads = 0;

  @override
  dynamic get(String key, {dynamic defaultValue}) {
    expect(key, kHasReadP2pSwapWarningKey);
    reads++;
    return false;
  }
}

Widget _app(Widget child, {bool light = false}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final bool light in <bool>[false, true]) {
    testWidgets('transfer toggle forgets revoked work, light $light', (
      WidgetTester tester,
    ) async {
      final PowGeneratingStatusBloc status = PowGeneratingStatusBloc();
      app.sl.pushNewScope();
      app.sl.registerSingleton<PowGeneratingStatusBloc>(status);
      int taps = 0;
      Widget view() => _app(
        TransferToggleCardSizeButton(
          onPressed: () => taps++,
          iconData: Icons.expand_more,
        ),
        light: light,
      );
      IconButton button() => tester.widget<IconButton>(find.byType(IconButton));
      try {
        final PowWorkToken old = status.claimWork();
        status.update(old, PowStatus.generating);
        await tester.pumpWidget(view());
        await tester.pump();
        expect(button().onPressed, isNull);
        status.invalidate();
        await tester.pump();
        expect(button().onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(status.update(old, PowStatus.generating), isFalse);
        await tester.pumpWidget(view());
        await tester.pump();
        expect(button().onPressed, isNotNull);
        final PowWorkToken current = status.claimWork();
        status.update(current, PowStatus.generating);
        await tester.pump();
        expect(status.update(old, PowStatus.done), isFalse);
        status.release(old);
        await tester.pump();
        expect(button().onPressed, isNull);
        status.release(current);
        await tester.pump();
        await tester.tap(find.byType(IconButton));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        status.dispose();
        await app.sl.popScope();
      }
    });
  }

  for (final String action in <String>['p2p_join_swap', 'p2p_start_swap']) {
    testWidgets('$action forgets revoked work before opening its warning', (
      WidgetTester tester,
    ) async {
      final PowGeneratingStatusBloc status = PowGeneratingStatusBloc();
      final SharedPrefsService? previous = app.sharedPrefsService;
      final _WarningPreferences preferences = _WarningPreferences();
      app.sharedPrefsService = preferences;
      app.sl.pushNewScope();
      app.sl.registerSingleton<PowGeneratingStatusBloc>(status);
      final SwapListFixture source = SwapListFixture();
      final SwapListBinding owner = source.bind();
      Widget view() => _app(
        Builder(
          builder: (BuildContext context) {
            void openWarning() {
              if (!owner.ownsResources()) return;
              preferences.get(kHasReadP2pSwapWarningKey);
              unawaited(
                showCustomDialog(
                  context: context,
                  content: P2PSwapWarningModal(onAccepted: () {}),
                ),
              );
            }

            return P2pSwapOptionsCard(
              swaps: const Stream<List<P2pSwap>>.empty(),
              binding: owner,
              onStart: openWarning,
              onJoin: openWarning,
            );
          },
        ),
      );
      try {
        final PowWorkToken old = status.claimWork();
        status.update(old, PowStatus.generating);
        await tester.pumpWidget(view());
        await tester.pump();
        await tester.tap(find.byKey(Key(action)));
        await tester.pump();
        expect(preferences.reads, 0);
        expect(find.byType(P2PSwapWarningModal), findsNothing);
        status.invalidate();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(status.update(old, PowStatus.generating), isFalse);
        await tester.pumpWidget(view());
        await tester.pump();
        await tester.tap(find.byKey(Key(action)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(preferences.reads, 1);
        expect(find.byType(P2PSwapWarningModal), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        status.dispose();
        await app.sl.popScope();
        app.sharedPrefsService = previous;
      }
    });
  }

  testWidgets('an unowned swap control refuses before its injected warning', (
    WidgetTester tester,
  ) async {
    final SwapListFixture source = SwapListFixture()..ready = false;
    int opened = 0;
    await tester.pumpWidget(
      _app(
        P2pSwapOptionsCard(
          binding: source.bind(),
          onStart: () => opened++,
          onJoin: () => opened++,
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('p2p_start_swap')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const Key('p2p_join_swap')),
      warnIfMissed: false,
    );
    expect(opened, 0);
    expect(find.byType(P2PSwapWarningModal), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
