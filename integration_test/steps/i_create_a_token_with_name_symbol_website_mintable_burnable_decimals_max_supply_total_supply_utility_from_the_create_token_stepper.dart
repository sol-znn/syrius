// BDD Usage comments intentionally mirror Gherkin placeholders.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../support/devnet_registration_host.dart';
import '../support/devnet_test_context.dart';
import '../support/devnet_token_stepper_form.dart';

/// Usage: I create a token with name `<token_name>`, symbol `<token_symbol>`,
/// website `<website>`, mintable `<mintable>`, burnable `<burnable>`,
/// decimals `<decimals>`, max supply `<max_supply>`,
/// total supply `<total_supply>`, utility `<utility>`
/// from the Create Token stepper.
Future<void>
// The BDD generator names this function after its complete step text.
// ignore: lines_longer_than_80_chars
iCreateATokenWithNameSymbolWebsiteMintableBurnableDecimalsMaxSupplyTotalSupplyUtilityFromTheCreateTokenStepper(
  WidgetTester tester,
  dynamic token_name,
  dynamic token_symbol,
  dynamic website,
  dynamic mintable,
  dynamic burnable,
  dynamic decimals,
  dynamic max_supply,
  dynamic total_supply,
  dynamic utility,
) async {
  final DevnetTestContext context = app.sl<DevnetTestContext>();
  final String tokenName = token_name as String;
  final String tokenSymbol = token_symbol as String;
  final String tokenWebsite = website as String;
  final bool isMintable = bool.parse(mintable as String);
  final bool isBurnable = bool.parse(burnable as String);
  final int tokenDecimals = int.parse(decimals as String);
  final String maxSupply = max_supply as String;
  final String totalSupply = total_supply as String;
  final bool isUtility = bool.parse(utility as String);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DevnetRegistrationHost(
          balances: app.sl<MultipleBalanceBloc>(),
          child: BlocProvider<AllTokensBloc>(
            create: (_) => AllTokensBloc(zenon: app.zenon!),
            child: const CreateTokenStepperPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final Finder createButton = await prepareDevnetTokenIssue(
    tester,
    name: tokenName,
    symbol: tokenSymbol,
    website: tokenWebsite,
    mintable: isMintable,
    burnable: isBurnable,
    decimals: tokenDecimals,
    maxSupply: maxSupply,
    totalSupply: totalSupply,
    utility: isUtility,
  );
  expect(createButton, findsOneWidget);

  final IssueTokenBloc issueTokenBloc = tester
      .element(createButton)
      .read<IssueTokenBloc>();
  final Completer<AccountBlockTemplate> completer =
      Completer<AccountBlockTemplate>();
  final StreamSubscription<IssueTokenState> subscription = issueTokenBloc.stream
      .listen((IssueTokenState state) {
        if (state is IssueTokenDone && !completer.isCompleted) {
          completer.complete(state.accountBlock);
        } else if (state is IssueTokenFailure && !completer.isCompleted) {
          completer.completeError(state.exception);
        }
      });

  try {
    await tester.tap(createButton);
    context.issueTokenBlock = await _pumpUntilComplete(
      tester,
      completer.future,
      'token issuance success',
    );
  } finally {
    await subscription.cancel();
  }

  await tester.pump();
  expect(find.byType(TokenCreatedSuccess), findsOneWidget);
}

Future<T> _pumpUntilComplete<T>(
  WidgetTester tester,
  Future<T> future,
  String description,
) async {
  T? result;
  Object? error;
  StackTrace? stackTrace;
  bool completed = false;

  unawaited(
    future.then(
      (T value) {
        result = value;
        completed = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stackTrace = s;
        completed = true;
      },
    ),
  );

  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!completed && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  if (!completed) {
    throw TimeoutException('Timed out waiting for $description');
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stackTrace!);
  }
  return result as T;
}
