import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/model/new_token_data.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/create_token_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../integration_test/support/devnet_token_stepper_form.dart';
import '../create_token_redesign/support.dart';

Future<void> _clock(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  TokenCreateFixture fixture,
  List<NewTokenData> issued,
) async {
  tester.view.physicalSize = const Size(1100, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CreateTokenStepperView(
          preflight: fixture.preflight,
          onIssue: issued.add,
        ),
      ),
    ),
  );
  await _clock(tester);
}

Future<Finder> _prepare(
  WidgetTester tester, {
  bool mintable = true,
  bool burnable = true,
  bool utility = false,
  String maximum = '100',
  Duration timeout = const Duration(seconds: 90),
}) => prepareDevnetTokenIssue(
  tester,
  name: 'newToken',
  symbol: 'TKK',
  website: 'testing.com',
  mintable: mintable,
  burnable: burnable,
  decimals: 3,
  maxSupply: maximum,
  totalSupply: '90',
  utility: utility,
  timeout: timeout,
);

Future<void> _close(
  WidgetTester tester,
  TokenCreateFixture fixture,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  fixture.dispose();
}

void main() {
  testWidgets(
    'mintable route returns Issue untapped and preserves the exact draft',
    (WidgetTester tester) async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      final List<NewTokenData> issued = <NewTokenData>[];
      try {
        await _mount(tester, fixture, issued);
        expect(find.byKey(const Key('token_plasma_next_button')), findsNothing);
        final Finder issue = await _prepare(tester);
        expect(issued, isEmpty);
        expect(fixture.accountReads, 2);
        expect(fixture.plasmaReads, 2);
        final VoidCallback originalIssue = tester
            .widget<PrimaryPill>(issue)
            .onPressed!;
        await tester.tap(issue);
        await _clock(tester);
        expect(issued, hasLength(1));
        final NewTokenData data = issued.single;
        expect(data.address, fixture.session.owner);
        expect(data.tokenName, 'newToken');
        expect(data.tokenSymbol, 'TKK');
        expect(data.tokenDomain, 'testing.com');
        expect(data.decimals, 3);
        expect(data.totalSupply, BigInt.from(90000));
        expect(data.maxSupply, BigInt.from(100000));
        expect(data.isMintable, isTrue);
        expect(data.isBurnable, isTrue);
        expect(data.isUtility, isFalse);
        originalIssue();
        await _clock(tester);
        expect(issued, hasLength(1));
        expect(fixture.accountReads, 3);
        expect(fixture.plasmaReads, 3);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, fixture);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'nonmintable route preserves equal supplies without a maximum field',
    (WidgetTester tester) async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      final List<NewTokenData> issued = <NewTokenData>[];
      try {
        await _mount(tester, fixture, issued);
        final Finder issue = await _prepare(
          tester,
          mintable: false,
          burnable: false,
          utility: true,
          maximum: '90',
        );
        expect(issued, isEmpty);
        expect(
          find.byKey(
            const Key('token_max_supply_field'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        await tester.tap(issue);
        await _clock(tester);
        expect(issued, hasLength(1));
        final NewTokenData data = issued.single;
        expect(data.address, fixture.session.owner);
        expect(data.totalSupply, BigInt.from(90000));
        expect(data.maxSupply, BigInt.from(90000));
        expect(data.decimals, 3);
        expect(data.isMintable, isFalse);
        expect(data.isBurnable, isFalse);
        expect(data.isUtility, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, fixture);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a pending original read times out once and late facts do not issue',
    (WidgetTester tester) async {
      final Completer<AccountInfo> original = Completer<AccountInfo>();
      final TokenCreateFixture fixture = TokenCreateFixture()
        ..accountRead = () => original.future;
      final List<NewTokenData> issued = <NewTokenData>[];
      try {
        await _mount(tester, fixture, issued);
        await expectLater(
          _prepare(tester, timeout: const Duration(milliseconds: 300)),
          throwsA(isA<TestFailure>()),
        );
        expect(issued, isEmpty);
        expect(fixture.accountReads, 1);
        expect(fixture.plasmaReads, 1);
        original.complete(tokenCreateAccount());
        await _clock(tester);
        expect(issued, isEmpty);
        expect(fixture.accountReads, 1);
        expect(fixture.plasmaReads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!original.isCompleted) {
          original.complete(tokenCreateAccount());
        }
        await _close(tester, fixture);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'different nonmintable supplies refuse before editing or issuance',
    (WidgetTester tester) async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      final List<NewTokenData> issued = <NewTokenData>[];
      try {
        await _mount(tester, fixture, issued);
        await expectLater(
          _prepare(tester, mintable: false),
          throwsA(isA<TestFailure>()),
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('token_name_field')))
              .controller!
              .text,
          isEmpty,
        );
        expect(issued, isEmpty);
        expect(fixture.accountReads, 1);
        expect(fixture.plasmaReads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, fixture);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a revoked original session refuses before editing or issuance',
    (WidgetTester tester) async {
      final TokenCreateFixture fixture = TokenCreateFixture();
      final List<NewTokenData> issued = <NewTokenData>[];
      try {
        await _mount(tester, fixture, issued);
        fixture.revoke();
        await tester.pump();
        await expectLater(
          _prepare(tester, timeout: const Duration(milliseconds: 300)),
          throwsA(isA<TestFailure>()),
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('token_name_field')))
              .controller!
              .text,
          isEmpty,
        );
        expect(issued, isEmpty);
        expect(fixture.accountReads, 1);
        expect(fixture.plasmaReads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, fixture);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
