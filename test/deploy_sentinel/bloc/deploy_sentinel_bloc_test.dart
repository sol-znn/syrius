import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../token_actions_redesign/support.dart' show ActionTerminalObserver;

class MockZenon extends Mock implements Zenon {}

class MockEmbedded extends Mock implements EmbeddedApi {}

class MockSentinelApi extends Mock implements SentinelApi {}

class MockAccountBlockUtils extends Mock implements AccountBlockUtils {}

class MockZenonAddressUtils extends Mock implements ZenonAddressUtils {}

class MockAccountBlockTemplate extends Mock implements AccountBlockTemplate {}

void main() {
  initHydratedStorage();

  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
  });

  group('DeploySentinelBloc', () {
    late MockZenon zenon;
    late MockEmbedded embedded;
    late MockSentinelApi sentinelApi;
    late MockAccountBlockUtils accountBlockUtils;
    late MockZenonAddressUtils zenonAddressUtils;
    late AccountBlockTemplate template;
    late AccountBlockTemplate response;

    DeploySentinelBloc makeBloc() => DeploySentinelBloc(
      accountBlockUtils: accountBlockUtils,
      zenon: zenon,
      zenonAddressUtils: zenonAddressUtils,
    );

    ActionTerminalObserver<DeploySentinelState> terminalObserver() =>
        ActionTerminalObserver<DeploySentinelState>(
          target: (BlocBase<dynamic> candidate) =>
              candidate is DeploySentinelBloc,
          terminal: (DeploySentinelState state) =>
              state is DeploySentinelDone || state is DeploySentinelFailure,
        );

    setUp(() {
      zenon = MockZenon();
      embedded = MockEmbedded();
      sentinelApi = MockSentinelApi();
      accountBlockUtils = MockAccountBlockUtils();
      zenonAddressUtils = MockZenonAddressUtils();
      template = MockAccountBlockTemplate();
      response = MockAccountBlockTemplate();

      when(() => zenon.embedded).thenReturn(embedded);
      when(() => embedded.sentinel).thenReturn(sentinelApi);
      when(() => sentinelApi.register()).thenReturn(template);
      when(
        () => accountBlockUtils.createAccountBlock(
          any(),
          any(),
          waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        ),
      ).thenAnswer((_) async => response);
      when(() => zenonAddressUtils.refreshBalance()).thenAnswer((_) {});
    });

    test('initial state is correct', () {
      final DeploySentinelBloc bloc = makeBloc();
      addTearDown(bloc.close);
      expect(bloc.state, const DeploySentinelInitial());
    });

    for (final bool accepted in <bool>[true, false]) {
      test(
        'terminal observer errors retain Sentinel original: $accepted',
        () async {
          final StateError originalError = StateError(
            'Synthetic Sentinel result',
          );
          if (!accepted) {
            when(
              () => accountBlockUtils.createAccountBlock(
                any(),
                any(),
                waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
              ),
            ).thenThrow(originalError);
          }
          final ActionTerminalObserver<DeploySentinelState> observer =
              terminalObserver();
          final BlocObserver previous = Bloc.observer;
          Bloc.observer = observer;
          final DeploySentinelBloc bloc = makeBloc();
          final Future<DeploySentinelState> delivery = bloc.stream
              .firstWhere(observer.terminal)
              .timeout(const Duration(seconds: 1));
          try {
            bloc.add(const DeploySentinelRequested());
            final DeploySentinelState terminal = await delivery;
            expect(observer.attempted, <DeploySentinelState>[terminal]);
            expect(bloc.state, same(terminal));
            expect(observer.reported, contains(same(observer.displayError)));
            if (accepted) {
              expect(
                (terminal as DeploySentinelDone).accountBlock,
                same(response),
              );
              verify(zenonAddressUtils.refreshBalance).called(1);
            } else {
              final DeploySentinelFailure failure =
                  terminal as DeploySentinelFailure;
              expect(failure.error, same(originalError));
              expect(failure.exception, isA<FailureException>());
              expect(observer.reported, contains(same(originalError)));
              verifyNever(zenonAddressUtils.refreshBalance);
            }
            verify(
              () => accountBlockUtils.createAccountBlock(
                template,
                any(),
                waitForRequiredPlasma: true,
              ),
            ).called(1);
          } finally {
            Bloc.observer = previous;
            await bloc.close();
          }
        },
      );
    }

    test('builder error survives terminal and diagnostic observers', () async {
      final StateError originalError = StateError('Synthetic Sentinel builder');
      when(sentinelApi.register).thenThrow(originalError);
      final ActionTerminalObserver<DeploySentinelState> observer =
          terminalObserver();
      final BlocObserver previous = Bloc.observer;
      Bloc.observer = observer;
      final DeploySentinelBloc bloc = makeBloc();
      final Future<DeploySentinelState> delivery = bloc.stream
          .firstWhere(observer.terminal)
          .timeout(const Duration(seconds: 1));
      try {
        bloc.add(const DeploySentinelRequested());
        final DeploySentinelFailure terminal =
            await delivery as DeploySentinelFailure;
        expect(observer.attempted, <DeploySentinelState>[terminal]);
        expect(bloc.state, same(terminal));
        expect(terminal.error, same(originalError));
        expect(terminal.exception, isA<FailureException>());
        expect(observer.reported, contains(same(originalError)));
        verifyNever(
          () => accountBlockUtils.createAccountBlock(
            any(),
            any(),
            waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
          ),
        );
      } finally {
        Bloc.observer = previous;
        await bloc.close();
      }
    });

    blocTest<DeploySentinelBloc, DeploySentinelState>(
      'emits [loading, done] on success',
      build: makeBloc,
      act: (DeploySentinelBloc bloc) =>
          bloc.add(const DeploySentinelRequested()),
      verify: (_) {
        verify(() => zenonAddressUtils.refreshBalance()).called(1);
      },
      expect: () => <DeploySentinelState>[
        const DeploySentinelLoading(),
        DeploySentinelDone(accountBlock: response),
      ],
    );

    late StateError observerError;
    blocTest<DeploySentinelBloc, DeploySentinelState>(
      'retains the exact accepted response when balance observation throws',
      setUp: () {
        observerError = StateError('optional balance observer');
        when(zenonAddressUtils.refreshBalance).thenThrow(observerError);
      },
      build: makeBloc,
      act: (DeploySentinelBloc bloc) =>
          bloc.add(const DeploySentinelRequested()),
      expect: () => <Matcher>[
        isA<DeploySentinelLoading>(),
        isA<DeploySentinelDone>().having(
          (DeploySentinelDone state) => state.accountBlock,
          'original response',
          same(response),
        ),
      ],
      errors: () => <Matcher>[same(observerError)],
      verify: (DeploySentinelBloc bloc) {
        expect((bloc.state as DeploySentinelDone).accountBlock, same(response));
        verify(
          () => accountBlockUtils.createAccountBlock(
            template,
            any(),
            waitForRequiredPlasma: true,
          ),
        ).called(1);
      },
    );

    late StateError originalError;
    blocTest<DeploySentinelBloc, DeploySentinelState>(
      'reports an arbitrary original error and completes the failed form',
      setUp: () {
        originalError = StateError('original publication error');
        when(
          () => accountBlockUtils.createAccountBlock(
            any(),
            any(),
            waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
          ),
        ).thenThrow(originalError);
      },
      build: makeBloc,
      act: (DeploySentinelBloc bloc) =>
          bloc.add(const DeploySentinelRequested()),
      expect: () => <Matcher>[
        isA<DeploySentinelLoading>(),
        isA<DeploySentinelFailure>(),
      ],
      errors: () => <Matcher>[same(originalError)],
      verify: (_) => verifyNever(zenonAddressUtils.refreshBalance),
    );

    for (final bool accepted in <bool>[true, false]) {
      late Completer<AccountBlockTemplate> original;
      late Completer<void> started;
      late StateError failure;
      blocTest<DeploySentinelBloc, DeploySentinelState>(
        'closed form retains the original outcome without emission: $accepted',
        setUp: () {
          original = Completer<AccountBlockTemplate>();
          started = Completer<void>();
          failure = StateError('original or optional observer error');
          when(
            () => accountBlockUtils.createAccountBlock(
              any(),
              any(),
              waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
            ),
          ).thenAnswer((_) {
            started.complete();
            return original.future;
          });
          when(zenonAddressUtils.refreshBalance).thenThrow(failure);
        },
        build: makeBloc,
        act: (DeploySentinelBloc bloc) async {
          bloc.add(const DeploySentinelRequested());
          await started.future.timeout(const Duration(seconds: 2));
          await bloc.close().timeout(const Duration(seconds: 2));
          if (accepted) {
            original.complete(response);
          } else {
            original.completeError(failure);
          }
          await Future<void>.delayed(Duration.zero);
        },
        expect: () => <DeploySentinelState>[const DeploySentinelLoading()],
        errors: () => <Matcher>[same(failure)],
        verify: (DeploySentinelBloc bloc) {
          expect(bloc.isClosed, isTrue);
          if (accepted) {
            verify(zenonAddressUtils.refreshBalance).called(1);
          } else {
            verifyNever(zenonAddressUtils.refreshBalance);
          }
        },
      );
    }

    blocTest<DeploySentinelBloc, DeploySentinelState>(
      'emits [loading, failure] on SyriusException',
      setUp: () {
        when(() => sentinelApi.register()).thenThrow(FailureException());
      },
      build: makeBloc,
      act: (DeploySentinelBloc bloc) =>
          bloc.add(const DeploySentinelRequested()),
      expect: () => <Matcher>[
        isA<DeploySentinelLoading>(),
        isA<DeploySentinelFailure>().having(
          (DeploySentinelFailure s) => s.exception,
          'exception',
          isA<FailureException>(),
        ),
      ],
    );
  });
}
