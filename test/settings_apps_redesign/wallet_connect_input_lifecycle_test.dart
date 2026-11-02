import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/wallet_connect_widgets/wallet_connect_qr_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/wallet_connect_widgets/wallet_connect_uri_card.dart';

import 'support.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _frames(WidgetTester tester) async {
  for (int frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets(
    'a replaced screen capture releases input only when the original settles',
    (WidgetTester tester) async {
      final Completer<Uint8List?> original = Completer<Uint8List?>();
      addTearDown(() {
        if (!original.isCompleted) original.complete();
      });
      int captures = 0;
      int pairs = 0;
      bool current() => true;
      Future<Uint8List?> capture() {
        captures++;
        return original.future;
      }

      final Widget first = WalletConnectQrCard(
        key: const Key('qr-input'),
        isCurrent: current,
        capture: capture,
        onPair: (Uri uri, bool Function() owns) async {
          pairs++;
        },
      );
      await tester.pumpWidget(_host(first));
      await tester.tap(find.byKey(const Key('wc_scan_screen')));
      await tester.pump();
      await tester.pumpWidget(
        _host(
          WalletConnectQrCard(
            key: const Key('qr-input'),
            isCurrent: current,
            capture: () async {
              captures++;
              return Uint8List.fromList(<int>[0, 1]);
            },
            onPair: (Uri uri, bool Function() owns) async {
              pairs++;
            },
          ),
        ),
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('wc_scan_screen')))
            .onPressed,
        isNull,
      );
      expect(captures, 1);
      original.complete(Uint8List.fromList(<int>[0, 1]));
      await _frames(tester);
      expect(find.text('Invalid QR code'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('wc_scan_screen')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('wc_scan_screen')));
      await _frames(tester);
      expect(captures, 2);
      expect(pairs, 0);
      expect(find.text('Invalid QR code'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a replaced pairing callback cannot leave link input permanently busy',
    (WidgetTester tester) async {
      final Completer<dynamic> original = Completer<dynamic>();
      addTearDown(() {
        if (!original.isCompleted) original.complete();
      });
      final ValueNotifier<String?> incoming = ValueNotifier<String?>(null);
      addTearDown(incoming.dispose);
      int originalCalls = 0;
      int replacementCalls = 0;
      bool Function()? originalOwns;
      bool current() => true;
      await tester.pumpWidget(
        _host(
          WalletConnectUriCard(
            key: const Key('link-input'),
            isCurrent: current,
            incomingLink: incoming,
            onPair: (Uri uri, bool Function() owns) {
              originalCalls++;
              originalOwns = owns;
              return original.future;
            },
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('wc_link')),
        validPairingLink,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('wc_connect')));
      await tester.pump();
      await tester.pumpWidget(
        _host(
          WalletConnectUriCard(
            key: const Key('link-input'),
            isCurrent: current,
            incomingLink: incoming,
            onPair: (Uri uri, bool Function() owns) async {
              replacementCalls++;
            },
          ),
        ),
      );
      expect(originalCalls, 1);
      expect(originalOwns!(), isFalse);
      expect(
        tester.widget<TextField>(find.byKey(const Key('wc_link'))).enabled,
        isFalse,
      );
      original.complete();
      await _frames(tester);
      expect(
        tester.widget<TextField>(find.byKey(const Key('wc_link'))).enabled,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('wc_link')),
        validPairingLink,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('wc_connect')));
      await _frames(tester);
      expect(originalCalls, 1);
      expect(replacementCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
