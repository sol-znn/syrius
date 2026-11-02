import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_fuse_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../plasma_fuse_redesign/support.dart';
import '../../plasma_redesign/support.dart' show PlasmaTransportCall;
import '../../token_actions_redesign/support.dart' show ActionTerminalObserver;

class MockZenon extends Mock implements Zenon {}

class MockEmbedded extends Mock implements EmbeddedApi {}

class MockPlasmaApi extends Mock implements PlasmaApi {}

class MockAccountBlockUtils extends Mock implements AccountBlockUtils {}

class MockZenonAddressUtils extends Mock implements ZenonAddressUtils {}

class MockAccountBlockTemplate extends Mock implements AccountBlockTemplate {}

void main() {
  initHydratedStorage();

  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(emptyAddress);
    registerFallbackValue(BigInt.zero);
  });

  group('FusePlasmaBloc', () {
    late MockZenon zenon;
    late MockEmbedded embedded;
    late MockPlasmaApi plasmaApi;
    late MockAccountBlockUtils accountBlockUtils;
    late MockZenonAddressUtils zenonAddressUtils;
    late FusePlasmaBloc bloc;
    late AccountBlockTemplate template;

    ActionTerminalObserver<FusePlasmaState> terminalObserver() =>
        ActionTerminalObserver<FusePlasmaState>(
          target: (BlocBase<dynamic> candidate) => candidate is FusePlasmaBloc,
          terminal: (FusePlasmaState state) =>
              state is FusePlasmaDone || state is FusePlasmaFailure,
        );

    setUp(() {
      zenon = MockZenon();
      embedded = MockEmbedded();
      plasmaApi = MockPlasmaApi();
      accountBlockUtils = MockAccountBlockUtils();
      zenonAddressUtils = MockZenonAddressUtils();
      template = MockAccountBlockTemplate();

      when(() => zenon.embedded).thenReturn(embedded);
      when(() => embedded.plasma).thenReturn(plasmaApi);
      when(() => plasmaApi.fuse(any(), any())).thenReturn(template);
      when(
        () => accountBlockUtils.createAccountBlock(
          any(),
          any(),
          waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        ),
      ).thenAnswer((_) async => template);
      when(() => zenonAddressUtils.refreshBalance()).thenAnswer((_) {});

      bloc = FusePlasmaBloc(
        accountBlockUtils: accountBlockUtils,
        zenon: zenon,
        zenonAddressUtils: zenonAddressUtils,
      );
    });

    test('initial state is correct', () {
      expect(bloc.state, const FusePlasmaInitial());
    });

    for (final bool accepted in <bool>[true, false]) {
      test(
        'terminal observer errors retain shared Fuse original: $accepted',
        () async {
          await bloc.close();
          final FuseFixture fixture = FuseFixture();
          final PlasmaSession session = fixture.confirmedSession();
          fixture.transport.deferred = true;
          final PlasmaFuseDraft draft = PlasmaFusePublisher.beginDraft(
            sender: fixture.sender,
            session: session,
            isCurrent: () => fixture.visible,
          )!;
          final FusePlasmaRequested event = FusePlasmaRequested(
            beneficiaryAddress: emptyAddress.toString(),
            amount: BigInt.from(1000000001),
            session: session,
            draft: draft,
            isCurrent: () => fixture.visible,
          );
          final ActionTerminalObserver<FusePlasmaState> observer =
              terminalObserver();
          final BlocObserver previous = Bloc.observer;
          Bloc.observer = observer;
          final FusePlasmaBloc observed = FusePlasmaBloc(
            accountBlockUtils: fixture.transport,
            zenon: zenon,
            zenonAddressUtils: zenonAddressUtils,
            sender: fixture.sender,
          );
          Future<FusePlasmaState> nextTerminal() => observed.stream
              .firstWhere(observer.terminal)
              .timeout(const Duration(seconds: 1));
          try {
            final Future<FusePlasmaState> delivery = nextTerminal();
            final Future<PlasmaTransportCall> started = fixture.transport.next;
            observed.add(event);
            final PlasmaTransportCall call = await started.timeout(
              const Duration(seconds: 1),
            );
            final AccountBlockTemplate response = fixture.transport.accepted(
              call,
            );
            final StateError originalError = StateError(
              'Synthetic Fuse outcome',
            );
            fixture.transport.completeNext(
              response: accepted ? response : null,
              error: accepted ? null : originalError,
            );
            final FusePlasmaState terminal = await delivery;
            final PlasmaFuseOutcome original = PlasmaFusePublisher.outcomesFor(
              fixture.sender,
            ).single;
            expect(observer.attempted, <FusePlasmaState>[terminal]);
            expect(observed.state, same(terminal));
            expect(observed.lastOutcome, same(original));
            expect(observer.reported, contains(same(observer.displayError)));
            if (accepted) {
              final FusePlasmaDone done = terminal as FusePlasmaDone;
              expect(done.accountBlock, same(response));
              expect(done.outcome, same(original));
              expect(original.result.block, same(response));
              expect(original.accepted, isTrue);
            } else {
              final FusePlasmaFailure failure = terminal as FusePlasmaFailure;
              expect(failure.error, same(originalError));
              expect(failure.outcome, same(original));
              expect(original.result.error, same(originalError));
              expect(original.accepted, isFalse);
            }
            expect(fixture.sender.busy.value, isFalse);
            expect(
              PlasmaFusePublisher.canRearm(fixture.sender, session),
              isFalse,
            );
            // Busy cleanup permits observation of this same original only.
            final Future<FusePlasmaState> replayDelivery = nextTerminal();
            observed.add(event);
            final FusePlasmaState replay = await replayDelivery;
            expect(observed.state, same(replay));
            expect(observed.lastOutcome, same(original));
            expect(observer.attempted, <FusePlasmaState>[terminal, replay]);
            if (accepted) {
              expect((replay as FusePlasmaDone).accountBlock, same(response));
            } else {
              expect((replay as FusePlasmaFailure).error, same(originalError));
            }
            expect(
              PlasmaFusePublisher.outcomesFor(fixture.sender),
              <PlasmaFuseOutcome>[original],
            );
            expect(fixture.transport.calls, hasLength(1));
            expect(fixture.sender.busy.value, isFalse);
            verifyNever(() => plasmaApi.fuse(any(), any()));
          } finally {
            Bloc.observer = previous;
            fixture.transport.release();
            await observed.close();
            await fixture.close();
          }
        },
      );
    }

    test(
      'shared Fuse proof failure clears busy despite observer errors',
      () async {
        await bloc.close();
        final FuseFixture fixture = FuseFixture();
        final PlasmaSession session = fixture.confirmedSession();
        final StateError originalError = StateError('Synthetic Fuse proof');
        fixture.accountRead = () async => throw originalError;
        final ActionTerminalObserver<FusePlasmaState> observer =
            terminalObserver();
        final BlocObserver previous = Bloc.observer;
        Bloc.observer = observer;
        final FusePlasmaBloc observed = FusePlasmaBloc(
          accountBlockUtils: fixture.transport,
          zenon: zenon,
          zenonAddressUtils: zenonAddressUtils,
          sender: fixture.sender,
        );
        Future<FusePlasmaState> nextTerminal() => observed.stream
            .firstWhere(observer.terminal)
            .timeout(const Duration(seconds: 1));
        FusePlasmaRequested request() => FusePlasmaRequested(
          beneficiaryAddress: emptyAddress.toString(),
          amount: BigInt.from(1000000001),
          session: session,
          draft: PlasmaFusePublisher.beginDraft(
            sender: fixture.sender,
            session: session,
            isCurrent: () => fixture.visible,
          ),
          isCurrent: () => fixture.visible,
        );
        try {
          final Future<FusePlasmaState> refusedDelivery = nextTerminal();
          observed.add(request());
          final FusePlasmaFailure refused =
              await refusedDelivery as FusePlasmaFailure;
          expect(observer.attempted, <FusePlasmaState>[refused]);
          expect(observed.state, same(refused));
          expect(refused.error, same(originalError));
          expect(refused.outcome, isNull);
          expect(observed.lastOutcome, isNull);
          expect(observer.reported, contains(same(originalError)));
          expect(fixture.transport.calls, isEmpty);
          expect(PlasmaFusePublisher.outcomesFor(fixture.sender), isEmpty);
          expect(fixture.sender.busy.value, isFalse);
          fixture.accountRead = null;
          final Future<FusePlasmaState> freshDelivery = nextTerminal();
          observed.add(request());
          final FusePlasmaDone done = await freshDelivery as FusePlasmaDone;
          expect(observer.attempted, <FusePlasmaState>[refused, done]);
          expect(observed.state, same(done));
          expect(done.accountBlock, same(done.outcome!.result.block));
          expect(observed.lastOutcome, same(done.outcome));
          expect(refused.error, same(originalError));
          expect(fixture.transport.calls, hasLength(1));
          expect(fixture.sender.busy.value, isFalse);
          verifyNever(() => plasmaApi.fuse(any(), any()));
        } finally {
          Bloc.observer = previous;
          fixture.transport.release();
          await observed.close();
          await fixture.close();
        }
      },
    );

    blocTest<FusePlasmaBloc, FusePlasmaState>(
      'emits [loading, done] on success',
      build: () => bloc,
      act: (FusePlasmaBloc bloc) => bloc.add(
        FusePlasmaRequested(
          beneficiaryAddress: emptyAddress.toString(),
          amount: BigInt.one,
        ),
      ),
      verify: (_) {
        verify(() => zenonAddressUtils.refreshBalance()).called(1);
      },
      expect: () => <FusePlasmaState>[
        const FusePlasmaLoading(),
        FusePlasmaDone(accountBlock: template),
      ],
    );

    blocTest<FusePlasmaBloc, FusePlasmaState>(
      'emits [loading, failure] on SyriusException',
      setUp: () {
        when(() => plasmaApi.fuse(any(), any())).thenThrow(FailureException());
      },
      build: () => bloc,
      act: (FusePlasmaBloc bloc) => bloc.add(
        FusePlasmaRequested(
          beneficiaryAddress: emptyAddress.toString(),
          amount: BigInt.one,
        ),
      ),
      expect: () => <Matcher>[
        isA<FusePlasmaLoading>(),
        isA<FusePlasmaFailure>().having(
          (FusePlasmaFailure s) => s.exception,
          'exception',
          isA<FailureException>(),
        ),
      ],
    );
  });
}
