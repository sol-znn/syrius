import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// A bounded, in-memory host. Callers inject every platform-facing source.
Widget aboutHost(
  Widget child, {
  bool light = false,
  bool rtl = false,
  double scale = 1,
  double width = 1000,
  double height = 650,
}) => MaterialApp(
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
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  ),
);

/// Runs owned view cleanup inside the active widget-test body.
void aboutTestWidgets(
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

/// Observes the actual Future across real-root and fake-frame microtasks.
/// Failure keeps its original object and trace; no completion is synthesized.
Future<void> observeAboutFuture(
  WidgetTester tester,
  Future<dynamic> original, {
  required String operation,
}) async {
  bool settled = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    original.then<void>(
      (dynamic _) {
        settled = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        settled = true;
      },
    ),
  );
  for (int frame = 0; frame < 20 && !settled; frame++) {
    await tester.runAsync(() async {
      await Future<void>.value();
    });
    await tester.pump();
  }
  expect(
    settled,
    isTrue,
    reason: 'The original $operation must settle within 20 pumps.',
  );
  if (failure != null) {
    Error.throwWithStackTrace(failure!, trace!);
  }
}

/// Selects a fixed viewport with only synchronous view reset in teardown.
void prepareAboutViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A genuine registry shape whose text is entirely owned by the test.
class FixtureLicence extends LicenseEntry {
  /// Uses supplied package names and complete paragraphs without parsing.
  FixtureLicence(this.names, this.lines);

  /// Synthetic package or font names.
  final List<String> names;

  /// Synthetic text with the registry's actual indentation model.
  final List<LicenseParagraph> lines;

  @override
  Iterable<String> get packages => names;

  @override
  Iterable<LicenseParagraph> get paragraphs => lines;
}
