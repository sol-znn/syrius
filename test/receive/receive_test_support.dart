import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Hosts Receive without a wallet, storage, node or native export service.
Widget receiveTestHost(
  Widget child, {
  bool light = false,
  double width = 640,
  double scale = 1,
  bool reduced = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  locale: const Locale('en'),
  supportedLocales: const <Locale>[Locale('en')],
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  ),
);

/// A deterministic encoder boundary; no image or file operation runs.
Future<Uint8List?> receiveTestEncode(
  QrImage image,
  PrettyQrDecoration decoration,
  int size,
) async => Uint8List.fromList(<int>[1, 2, 3]);

/// Settles one disclosure while keeping the animation clock explicit.
Future<void> receiveTestReveal(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Disposes owned widgets before the test body ends.
Future<void> receiveTestDispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}
