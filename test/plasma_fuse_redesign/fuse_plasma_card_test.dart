import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/fuse_plasma.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/view/fuse_plasma_disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/view/fuse_plasma_form.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/multiple_balance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_fuse_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/plasma_beneficiary_address_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

const Key _amount = Key('fuse_plasma_amount_field');
const Key _beneficiary = Key('fuse_plasma_beneficiary_address_field');
const Key _submit = Key('fuse_plasma_submit_button');
const Key _another = Key('plasma_fuse_another');

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _Zenon extends Mock implements Zenon {}

class _QuietBalances extends ZenonAddressUtils {
  @override
  void refreshBalance() {}
}

class _CardFixture {
  _CardFixture() {
    session = source.confirmedSession();
    final AccountBlockTemplate block = session.fuseBlock(
      session.address,
      BigInt.from(1000000001),
    );
    expect(
      block.chainIdentifier,
      session.chainId,
      reason: 'The offline owning card must use its captured session chain',
    );
    choices.changeAddress(session.address);
    bloc = FusePlasmaBloc(
      accountBlockUtils: source.transport,
      zenon: _Zenon(),
      zenonAddressUtils: _QuietBalances(),
      sender: source.sender,
    );
    whenListen(balances, states.stream, initialState: success());
    _notificationLogs = Logger('NotificationUtils').onRecord
        .where((LogRecord record) => record.loggerName == 'NotificationUtils')
        .listen(notifications.add);
  }

  final FuseFixture source = FuseFixture();
  final _Balances balances = _Balances();
  final StreamController<MultipleBalanceState> states =
      StreamController<MultipleBalanceState>.broadcast();
  final PlasmaBeneficiaryAddressCubit choices = PlasmaBeneficiaryAddressCubit();
  final DisclosureController disclosure = DisclosureController();
  late final FusePlasmaBloc bloc;
  late final PlasmaSession session;
  late final StreamSubscription<LogRecord> _notificationLogs;
  final List<LogRecord> notifications = <LogRecord>[];
  int refreshed = 0;
  int outcomes = 0;

  MultipleBalanceState success() => MultipleBalanceState(
    status: MultipleBalanceStatus.success,
    data: <String, AccountInfo>{
      session.address: AccountInfo(
        address: session.address,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(
            token: kQsrCoin,
            balance: BigInt.parse('1000000000000'),
          ),
        ],
      ),
    },
  );

  Widget host() => MultiBlocProvider(
    providers: <BlocProvider<dynamic>>[
      BlocProvider<MultipleBalanceBloc>.value(value: balances),
      BlocProvider<SendTransactionBloc>.value(value: source.sender),
      BlocProvider<PlasmaBeneficiaryAddressCubit>.value(value: choices),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 1000,
            height: 650,
            child: Column(
              children: <Widget>[
                FusePlasmaDisclosure(
                  controller: disclosure,
                  isCurrent: () => source.visible,
                  builder: (_, bool Function() isCurrent) => FusePlasmaCard(
                    bloc: bloc,
                    ownerAddress: session.address,
                    captureSession: (String owner) =>
                        owner == session.address ? session : null,
                    beneficiaries: <FusePlasmaBeneficiary>[
                      FusePlasmaBeneficiary(
                        address: session.address,
                        label: 'Address 1',
                      ),
                    ],
                    refreshBalances: () => refreshed++,
                    onPlasmaFused: () => outcomes++,
                    isCurrent: isCurrent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> close() async {
    source.transport.release();
    await bloc.close();
    await choices.close();
    await states.close();
    await balances.close();
    await _notificationLogs.cancel();
    disclosure.dispose();
    await source.close();
  }
}

Future<T> _real<T>(WidgetTester tester, Future<T> Function() operation) async {
  bool completed = false;
  late T result;
  (Object, StackTrace)? failure;
  await tester.runAsync<void>(() async {
    try {
      result = await operation().timeout(const Duration(seconds: 1));
      completed = true;
    } on Object catch (error, trace) {
      failure = (error, trace);
    }
  });
  if (failure case (final Object error, final StackTrace trace)) {
    Error.throwWithStackTrace(error, trace);
  }
  if (!completed) fail('Owned fixture operation did not complete');
  return result;
}

Future<_CardFixture> _prepare(WidgetTester tester) async {
  final _CardFixture fixture = await _real(tester, () async => _CardFixture());
  tester.view.physicalSize = const Size(1280, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _real(tester, fixture.close);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(fixture.host());
  fixture.disclosure.open();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
  return fixture;
}

Future<void> _until(
  WidgetTester tester,
  _CardFixture fixture,
  bool Function() done, {
  bool allowFailure = false,
}) async {
  void requireExpectedState() {
    final FusePlasmaState state = fixture.bloc.state;
    if (state is FusePlasmaFailure &&
        (!allowFailure || state.outcome == null)) {
      Error.throwWithStackTrace(
        state.error ?? state.exception,
        StackTrace.current,
      );
    }
  }

  for (int turn = 0; turn < 40; turn++) {
    requireExpectedState();
    if (done()) return;
    // The injected SDK owners were constructed outside the widget clock.
    await _real<void>(tester, () async {});
    requireExpectedState();
    await tester.pump(const Duration(milliseconds: 25));
  }
  requireExpectedState();
  fail(
    'Owned widget operation did not settle within forty frames: '
    '${fixture.bloc.state.runtimeType}, '
    '${fixture.source.transport.calls.length} transport calls, '
    '${PlasmaFusePublisher.outcomesFor(fixture.source.sender).length} '
    'originals',
  );
}

LoadingButton _button(WidgetTester tester) => tester.widget<LoadingButton>(
  find.descendant(
    of: find.byKey(_submit),
    matching: find.byType(LoadingButton),
  ),
);

Future<void> _external(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('fuse_plasma_beneficiary_selector')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('fuse_plasma_another_address_option')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byKey(_beneficiary), tokenAddress.toString());
  await tester.pump();
}

Future<void> _traverse(WidgetTester tester) async {
  final FocusNode amount = tester
      .widget<TextField>(find.byKey(_amount))
      .focusNode!;
  final FocusNode beneficiary = tester
      .widget<TextField>(find.byKey(_beneficiary))
      .focusNode!;
  expect(find.byType(TextField), findsNWidgets(2));
  amount.requestFocus();
  await tester.pump();
  expect(amount.hasFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  expect(beneficiary.hasFocus, isTrue);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  expect(amount.hasFocus, isTrue);
}

void main() {
  initHydratedStorage();

  for (final bool succeeds in <bool>[true, false]) {
    testWidgets('stale owning-card delivery retains its exact original, '
        'accepted $succeeds', (WidgetTester tester) async {
      final _CardFixture fixture = await _prepare(tester);
      await _external(tester);
      await tester.enterText(find.byKey(_amount), '100.00000001');
      await tester.pump();
      final State<StatefulWidget> form = tester.state(
        find.byType(FusePlasmaForm),
      );
      final TextEditingController amount = tester
          .widget<TextField>(find.byKey(_amount))
          .controller!;
      final TextEditingController beneficiary = tester
          .widget<TextField>(find.byKey(_beneficiary))
          .controller!;
      final VoidCallback oldSubmit = _button(tester).onPressed!;
      fixture.source.transport.deferred = true;
      oldSubmit();
      await _until(
        tester,
        fixture,
        () => fixture.source.transport.pending.isNotEmpty,
      );
      fixture.states.add(
        const MultipleBalanceState(status: MultipleBalanceStatus.loading),
      );
      await _real<void>(tester, () async {});
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(FusePlasmaForm)), same(form));
      fixture.states.add(
        MultipleBalanceState(
          status: MultipleBalanceStatus.failure,
          error: FailureException(),
        ),
      );
      await _real<void>(tester, () async {});
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(FusePlasmaForm)), same(form));
      expect(
        tester.widget<TextField>(find.byKey(_amount)).controller,
        same(amount),
      );
      expect(
        tester.widget<TextField>(find.byKey(_beneficiary)).controller,
        same(beneficiary),
      );
      expect(amount.text, '100.00000001');
      expect(beneficiary.text, tokenAddress.toString());
      oldSubmit();
      expect(fixture.source.transport.calls, hasLength(1));
      fixture.disclosure.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      fixture.disclosure.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      await _traverse(tester);
      expect(
        tester.state<LoadingButtonState>(find.byType(LoadingButton)).btnState,
        ButtonState.busy,
      );
      final AccountBlockTemplate response = fixture.source.transport.accepted(
        fixture.source.transport.calls.single,
      );
      final StateError error = StateError('Synthetic original SDK uncertainty');
      if (succeeds) {
        fixture.source.transport.completeNext(response: response);
      } else {
        fixture.source.transport.completeNext(error: error);
      }
      await _until(
        tester,
        fixture,
        () =>
            fixture.bloc.lastOutcome != null &&
            !fixture.source.sender.busy.value,
        allowFailure: !succeeds,
      );
      // Producer settlement can precede listener delivery. Observe the real
      // button's completed reversal after that delivery, within finite frames.
      await _until(
        tester,
        fixture,
        () =>
            tester
                .state<LoadingButtonState>(find.byType(LoadingButton))
                .btnState ==
            ButtonState.idle,
        allowFailure: !succeeds,
      );
      await _real<void>(tester, () async {});
      final PlasmaFuseOutcome original = fixture.bloc.lastOutcome!;
      expect(
        PlasmaFusePublisher.outcomesFor(fixture.source.sender).single,
        same(original),
      );
      expect(original.accepted, succeeds);
      if (succeeds) {
        final FusePlasmaDone state = fixture.bloc.state as FusePlasmaDone;
        expect(state.accountBlock, same(response));
        expect(state.outcome, same(original));
        expect(original.result.block, same(response));
      } else {
        final FusePlasmaFailure state = fixture.bloc.state as FusePlasmaFailure;
        expect(state.error, same(error));
        expect(state.outcome, same(original));
        expect(original.result.error, same(error));
      }
      expect(tester.state(find.byType(FusePlasmaForm)), same(form));
      expect(amount.text, '100.00000001');
      expect(beneficiary.text, tokenAddress.toString());
      expect(fixture.source.sender.busy.value, isFalse);
      expect(
        tester.state<LoadingButtonState>(find.byType(LoadingButton)).btnState,
        ButtonState.idle,
      );
      expect(fixture.refreshed, 0);
      expect(fixture.outcomes, 0);
      expect(fixture.notifications, isEmpty);
      oldSubmit();
      await tester.pump();
      expect(fixture.source.transport.calls, hasLength(1));
      fixture.states.add(fixture.success());
      await _real<void>(tester, () async {});
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.byKey(_amount)).controller,
        same(amount),
      );
      expect(fixture.outcomes, 0);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_another)).onPressed,
        isNull,
      );
      if (succeeds) {
        fixture.source.registry.published(response, <String>[
          fixture.session.address,
        ]);
        fixture.source.confirmedHashes.add(original.publicationHash!);
        await _real(tester, fixture.source.flight.check);
        await tester.pump();
        expect(
          tester.widget<OutlinedButton>(find.byKey(_another)).onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(_another));
        await tester.pump();
        await tester.enterText(find.byKey(_amount), '20.00000001');
        await tester.pump();
        oldSubmit();
        expect(fixture.source.transport.calls, hasLength(1));
        fixture.source.transport.deferred = false;
        _button(tester).onPressed!();
        await _until(tester, fixture, () => fixture.outcomes == 1);
        await tester.pump(const Duration(milliseconds: 500));
        await _real<void>(tester, () async {});
        final List<PlasmaFuseOutcome> archive = PlasmaFusePublisher.outcomesFor(
          fixture.source.sender,
        );
        expect(archive, hasLength(2));
        expect(archive.first, same(original));
        expect(archive.first.result.block, same(response));
        expect(archive.last.amount, BigInt.from(2000000001));
        expect(fixture.source.transport.calls, hasLength(2));
        expect(fixture.refreshed, 1);
        expect(fixture.outcomes, 1);
        expect(amount.text, isEmpty);
        expect(fixture.source.sender.busy.value, isFalse);
        expect(fixture.notifications, isEmpty);
      } else {
        expect(
          PlasmaFusePublisher.canRearm(fixture.source.sender, fixture.session),
          isFalse,
        );
        expect(_button(tester).onPressed, isNull);
        expect(
          PlasmaFusePublisher.outcomesFor(
            fixture.source.sender,
          ).single.result.error,
          same(error),
        );
        expect(amount.text, '100.00000001');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('owning card requires confirmed Another and fences '
      'its old controls', (WidgetTester tester) async {
    final _CardFixture fixture = await _prepare(tester);
    await tester.enterText(find.byKey(_amount), '100.00000001');
    await tester.pump();
    final VoidCallback oldSubmit = _button(tester).onPressed!;
    oldSubmit();
    await _until(tester, fixture, () => fixture.outcomes == 1);
    final PlasmaFuseOutcome original = fixture.bloc.lastOutcome!;
    final AccountBlockTemplate accepted = original.result.block!;
    expect(
      tester.widget<OutlinedButton>(find.byKey(_another)).onPressed,
      isNull,
    );
    fixture.source.registry.published(accepted, <String>[
      fixture.session.address,
    ]);
    fixture.source.flight.clear();
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byKey(_another)).onPressed,
      isNull,
    );
    fixture.source.registry.published(accepted, <String>[
      fixture.session.address,
    ]);
    fixture.source.confirmedHashes.add(original.publicationHash!);
    await _real(tester, fixture.source.flight.check);
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byKey(_another)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(_another));
    await tester.pump();
    await tester.enterText(find.byKey(_amount), '20.00000001');
    await tester.pump();
    oldSubmit();
    await tester.pump();
    expect(fixture.source.transport.calls, hasLength(1));
    _button(tester).onPressed!();
    await _until(tester, fixture, () => fixture.outcomes == 2);
    final List<PlasmaFuseOutcome> archive = PlasmaFusePublisher.outcomesFor(
      fixture.source.sender,
    );
    expect(archive, hasLength(2));
    expect(archive.first, same(original));
    expect(archive.first.result.block, same(accepted));
    expect(archive.last.amount, BigInt.from(2000000001));
    expect(fixture.source.transport.calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
