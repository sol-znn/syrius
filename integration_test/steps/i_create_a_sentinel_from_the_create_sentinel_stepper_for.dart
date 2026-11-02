import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/fetch_bloc/fetch_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../support/devnet_deposit_confirmation.dart';
import '../support/devnet_registration_host.dart';
import '../support/devnet_test_context.dart';

/// Usage: I create a sentinel from the Create Sentinel stepper
/// for `<sentinel_owner>`.
Future<void> iCreateASentinelFromTheCreateSentinelStepperFor(
  WidgetTester tester,
  String owner,
) async {
  selectDevnetSender(owner);
  final DevnetSentinelPreflight preflight = DevnetSentinelPreflight.capture(
    owner,
  );
  final AccountInfo accountInfo = await preflight.readAccountInfo(tester);
  preflight.requireCurrent();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DevnetRegistrationHost(
          balances: app.sl<MultipleBalanceBloc>(),
          child: const CreateSentinelStepperPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await _tapAndSettle(
    tester,
    const Key('sentinel_plasma_next_button'),
    beforeTap: preflight.requireCurrent,
  );
  final DevnetDepositConfirmation? depositConfirmation = await _completeQsrStep(
    tester,
    owner,
    accountInfo,
    preflight,
  );
  await _tapAndSettle(
    tester,
    const Key('sentinel_znn_next_button'),
    beforeTap: preflight.requireReady,
  );

  final Finder registerButton = find.byKey(
    const Key('sentinel_register_button'),
  );
  await _pumpUntilFound(tester, registerButton);
  await tester.ensureVisible(registerButton);
  await tester.pumpAndSettle();
  final DeploySentinelBloc deploySentinelBloc = tester
      .element(registerButton)
      .read<DeploySentinelBloc>();
  final Completer<void> completer = Completer<void>();
  final StreamSubscription<DeploySentinelState> subscription =
      deploySentinelBloc.stream.listen((DeploySentinelState state) {
        if (state is DeploySentinelDone && !completer.isCompleted) {
          completer.complete();
        } else if (state is DeploySentinelFailure && !completer.isCompleted) {
          completer.completeError(
            DevnetDepositFailure(
              DevnetDepositFailureCode.registrationFailed,
              originalError: state.error ?? state.exception,
            ),
          );
        }
      });

  try {
    preflight.requireReady();
    depositConfirmation?.requireCurrent();
    await tester.tap(registerButton);
    await _pumpUntilComplete(
      tester,
      completer.future,
      'sentinel registration success',
    );
  } finally {
    await subscription.cancel();
  }
}

Future<DevnetDepositConfirmation?> _completeQsrStep(
  WidgetTester tester,
  String owner,
  AccountInfo accountInfo,
  DevnetSentinelPreflight preflight,
) async {
  final Finder qsrNextButton = find.byKey(
    const Key('sentinel_qsr_next_button'),
  );
  final Finder qsrAmountField = find.byKey(
    const Key('sentinel_qsr_amount_field'),
  );
  await _pumpUntilAnyFound(tester, <Finder>[qsrNextButton, qsrAmountField]);
  DevnetDepositConfirmation? confirmation;

  final BigInt depositedQsr = await preflight.readDepositedQsr(tester);
  final BigInt remainingQsr = sentinelRegisterQsrAmount > depositedQsr
      ? sentinelRegisterQsrAmount - depositedQsr
      : BigInt.zero;

  if (qsrAmountField.evaluate().isNotEmpty) {
    final TextFormField amountField = tester.widget<TextFormField>(
      qsrAmountField,
    );
    final BigInt depositAmount = amountField.controller!.text.extractDecimals(
      coinDecimals,
    );
    expect(depositAmount, remainingQsr);
    expect(
      accountInfo.getBalance(qsrZts),
      greaterThanOrEqualTo(depositAmount),
      reason: 'Sentinel owner does not have enough QSR for the slot deposit',
    );

    final Finder depositButton = find.byKey(
      const Key('sentinel_qsr_deposit_button'),
    );
    await _pumpUntilFound(tester, depositButton);
    await tester.ensureVisible(depositButton);
    await tester.pumpAndSettle();
    final SentinelDepositQsrBloc depositBloc = tester
        .element(depositButton)
        .read<SentinelDepositQsrBloc>();
    final CreateSentinelQsrInfoBloc originalQsrInfo = tester
        .element(depositButton)
        .read<CreateSentinelQsrInfoBloc>();
    final DevnetDepositConfirmation originalConfirmation =
        DevnetDepositConfirmation.capture(
          sender: tester.element(depositButton).read<SendTransactionBloc>(),
          ownerAddress: owner,
          expectedDeposit: app.zenon!.embedded.sentinel.depositQsr(
            depositAmount,
          ),
        );
    confirmation = originalConfirmation;
    final Completer<void> completer = Completer<void>();
    final StreamSubscription<SentinelDepositQsrState> subscription = depositBloc
        .stream
        .listen((SentinelDepositQsrState state) {
          if (state is SentinelDepositQsrDone && !completer.isCompleted) {
            completer.complete();
          } else if (state is SentinelDepositQsrFailure &&
              !completer.isCompleted) {
            completer.completeError(
              DevnetDepositFailure(
                DevnetDepositFailureCode.depositFailed,
                originalError: state.exception,
              ),
            );
          }
        });

    try {
      preflight.requireReady();
      await tester.tap(depositButton);
      await _pumpUntilComplete(
        tester,
        completer.future,
        'sentinel QSR deposit success',
      );
      await originalConfirmation.confirm(tester);
      final BigInt completedDeposit = await originalConfirmation
          .waitForSentinelDeposit(tester);
      expect(completedDeposit, sentinelRegisterQsrAmount);
      originalConfirmation.requireCurrent();
      preflight.requireReady();
      // The publication-time read can precede the confirmed contract effect.
      // Refresh the retained view once; never repeat the deposit operation.
      originalQsrInfo.add(FetchRequestData(address: Address.parse(owner)));
    } finally {
      await subscription.cancel();
      await originalConfirmation.close(tester);
    }
  } else {
    expect(
      depositedQsr,
      greaterThanOrEqualTo(sentinelRegisterQsrAmount),
      reason: 'Sentinel owner does not have enough deposited QSR',
    );
  }

  confirmation?.requireCurrent();
  await _tapAndSettle(
    tester,
    const Key('sentinel_qsr_next_button'),
    beforeTap: preflight.requireReady,
  );
  return confirmation;
}

Future<void> _tapAndSettle(
  WidgetTester tester,
  Key key, {
  required VoidCallback beforeTap,
}) async {
  final Finder finder = find.byKey(key);
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  beforeTap();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilAnyFound(
  WidgetTester tester,
  List<Finder> finders,
) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (finders.every((Finder finder) => finder.evaluate().isEmpty) &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(
    finders.any((Finder finder) => finder.evaluate().isNotEmpty),
    isTrue,
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilComplete(
  WidgetTester tester,
  Future<void> future,
  String description,
) async {
  Object? error;
  StackTrace? stackTrace;
  bool completed = false;

  unawaited(
    future.then(
      (_) {
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
}
