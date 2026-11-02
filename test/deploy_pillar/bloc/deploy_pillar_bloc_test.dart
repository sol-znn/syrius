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

class MockPillarApi extends Mock implements PillarApi {}

class MockAccountBlockUtils extends Mock implements AccountBlockUtils {}

class MockZenonAddressUtils extends Mock implements ZenonAddressUtils {}

class MockAccountBlockTemplate extends Mock implements AccountBlockTemplate {}

class FakeAddress extends Fake implements Address {}

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(FakeAddress());
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
  });

  group('DeployPillarBloc', () {
    late MockZenon zenon;
    late MockEmbedded embedded;
    late MockPillarApi pillarApi;
    late MockAccountBlockUtils accountBlockUtils;
    late MockZenonAddressUtils zenonAddressUtils;
    late AccountBlockTemplate template;

    DeployPillarBloc makeBloc() => DeployPillarBloc(
      accountBlockUtils: accountBlockUtils,
      zenon: zenon,
      zenonAddressUtils: zenonAddressUtils,
    );

    DeployPillarRequested request() => DeployPillarRequested(
      blockProducingAddress: emptyAddress,
      giveBlockRewardPercentage: 1,
      giveDelegateRewardPercentage: 1,
      pillarName: 'pillar',
      rewardAddress: emptyAddress,
    );

    ActionTerminalObserver<DeployPillarState> terminalObserver() =>
        ActionTerminalObserver<DeployPillarState>(
          target: (BlocBase<dynamic> candidate) =>
              candidate is DeployPillarBloc,
          terminal: (DeployPillarState state) =>
              state is DeployPillarDone || state is DeployPillarFailure,
        );

    setUp(() {
      zenon = MockZenon();
      embedded = MockEmbedded();
      pillarApi = MockPillarApi();
      accountBlockUtils = MockAccountBlockUtils();
      zenonAddressUtils = MockZenonAddressUtils();
      template = MockAccountBlockTemplate();

      when(() => zenon.embedded).thenReturn(embedded);
      when(() => embedded.pillar).thenReturn(pillarApi);
      when(
        () => pillarApi.checkNameAvailability(any()),
      ).thenAnswer((_) async => true);
      when(
        () => pillarApi.register(any(), any(), any(), any(), any()),
      ).thenReturn(template);
      when(
        () => accountBlockUtils.createAccountBlock(
          any(),
          any(),
          waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        ),
      ).thenAnswer((_) async => template);
      when(() => zenonAddressUtils.refreshBalance()).thenAnswer((_) {});
    });

    test('initial state is correct', () {
      final DeployPillarBloc bloc = makeBloc();
      addTearDown(bloc.close);
      expect(bloc.state, const DeployPillarInitial());
    });

    for (final bool accepted in <bool>[true, false]) {
      test(
        'terminal observer errors retain original Pillar result: $accepted',
        () async {
          final StateError originalError = StateError(
            'Synthetic Pillar result',
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
          final ActionTerminalObserver<DeployPillarState> observer =
              terminalObserver();
          final BlocObserver previous = Bloc.observer;
          Bloc.observer = observer;
          final DeployPillarBloc bloc = makeBloc();
          final Future<DeployPillarState> delivery = bloc.stream
              .firstWhere(observer.terminal)
              .timeout(const Duration(seconds: 1));
          try {
            bloc.add(request());
            final DeployPillarState terminal = await delivery;
            expect(observer.attempted, <DeployPillarState>[terminal]);
            expect(bloc.state, same(terminal));
            expect(observer.reported, contains(same(observer.displayError)));
            if (accepted) {
              expect(
                (terminal as DeployPillarDone).accountBlock,
                same(template),
              );
              verify(zenonAddressUtils.refreshBalance).called(1);
            } else {
              final DeployPillarFailure failure =
                  terminal as DeployPillarFailure;
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

    test('name-read error survives terminal and diagnostic errors', () async {
      final StateError originalError = StateError('Synthetic Pillar name read');
      when(
        () => pillarApi.checkNameAvailability(any()),
      ).thenThrow(originalError);
      final ActionTerminalObserver<DeployPillarState> observer =
          terminalObserver();
      final BlocObserver previous = Bloc.observer;
      Bloc.observer = observer;
      final DeployPillarBloc bloc = makeBloc();
      final Future<DeployPillarState> delivery = bloc.stream
          .firstWhere(observer.terminal)
          .timeout(const Duration(seconds: 1));
      try {
        bloc.add(request());
        final DeployPillarFailure terminal =
            await delivery as DeployPillarFailure;
        expect(observer.attempted, <DeployPillarState>[terminal]);
        expect(bloc.state, same(terminal));
        expect(terminal.error, same(originalError));
        expect(terminal.exception, isA<FailureException>());
        expect(observer.reported, contains(same(originalError)));
        verifyNever(
          () => pillarApi.register(any(), any(), any(), any(), any()),
        );
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

    blocTest<DeployPillarBloc, DeployPillarState>(
      'emits [loading, done] on success',
      build: makeBloc,
      act: (DeployPillarBloc bloc) => bloc.add(
        DeployPillarRequested(
          blockProducingAddress: emptyAddress,
          giveBlockRewardPercentage: 1,
          giveDelegateRewardPercentage: 1,
          pillarName: 'pillar',
          rewardAddress: emptyAddress,
        ),
      ),
      verify: (_) {
        verify(() => zenonAddressUtils.refreshBalance()).called(1);
      },
      expect: () => <DeployPillarState>[
        const DeployPillarLoading(),
        DeployPillarDone(accountBlock: template),
      ],
    );

    late StateError observerError;
    blocTest<DeployPillarBloc, DeployPillarState>(
      'retains acceptance when the optional balance observer fails',
      setUp: () {
        observerError = StateError('optional balance observer');
        when(zenonAddressUtils.refreshBalance).thenThrow(observerError);
      },
      build: makeBloc,
      act: (DeployPillarBloc bloc) => bloc.add(
        DeployPillarRequested(
          blockProducingAddress: emptyAddress,
          giveBlockRewardPercentage: 1,
          giveDelegateRewardPercentage: 1,
          pillarName: 'pillar',
          rewardAddress: emptyAddress,
        ),
      ),
      expect: () => <Matcher>[
        isA<DeployPillarLoading>(),
        isA<DeployPillarDone>().having(
          (DeployPillarDone state) => state.accountBlock,
          'original response',
          same(template),
        ),
      ],
      errors: () => <Matcher>[same(observerError)],
    );

    late StateError originalError;
    blocTest<DeployPillarBloc, DeployPillarState>(
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
      act: (DeployPillarBloc bloc) => bloc.add(
        DeployPillarRequested(
          blockProducingAddress: emptyAddress,
          giveBlockRewardPercentage: 1,
          giveDelegateRewardPercentage: 1,
          pillarName: 'pillar',
          rewardAddress: emptyAddress,
        ),
      ),
      expect: () => <Matcher>[
        isA<DeployPillarLoading>(),
        isA<DeployPillarFailure>(),
      ],
      errors: () => <Matcher>[same(originalError)],
      verify: (_) => verifyNever(zenonAddressUtils.refreshBalance),
    );

    for (final bool accepted in <bool>[true, false]) {
      late Completer<AccountBlockTemplate> original;
      late Completer<void> started;
      late StateError failure;
      blocTest<DeployPillarBloc, DeployPillarState>(
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
        act: (DeployPillarBloc bloc) async {
          bloc.add(
            DeployPillarRequested(
              blockProducingAddress: emptyAddress,
              giveBlockRewardPercentage: 1,
              giveDelegateRewardPercentage: 1,
              pillarName: 'pillar',
              rewardAddress: emptyAddress,
            ),
          );
          await started.future.timeout(const Duration(seconds: 2));
          await bloc.close().timeout(const Duration(seconds: 2));
          if (accepted) {
            original.complete(template);
          } else {
            original.completeError(failure);
          }
          await Future<void>.delayed(Duration.zero);
        },
        expect: () => <DeployPillarState>[const DeployPillarLoading()],
        errors: () => <Matcher>[same(failure)],
        verify: (DeployPillarBloc bloc) {
          expect(bloc.isClosed, isTrue);
          if (accepted) {
            verify(zenonAddressUtils.refreshBalance).called(1);
          } else {
            verifyNever(zenonAddressUtils.refreshBalance);
          }
        },
      );
    }

    late Completer<bool> nameReply;
    late Completer<void> nameStarted;
    blocTest<DeployPillarBloc, DeployPillarState>(
      'closing during the name read cannot start a publication afterwards',
      setUp: () {
        nameReply = Completer<bool>();
        nameStarted = Completer<void>();
        when(() => pillarApi.checkNameAvailability(any())).thenAnswer((_) {
          nameStarted.complete();
          return nameReply.future;
        });
      },
      build: makeBloc,
      act: (DeployPillarBloc bloc) async {
        bloc.add(
          DeployPillarRequested(
            blockProducingAddress: emptyAddress,
            giveBlockRewardPercentage: 1,
            giveDelegateRewardPercentage: 1,
            pillarName: 'pillar',
            rewardAddress: emptyAddress,
          ),
        );
        await nameStarted.future.timeout(const Duration(seconds: 2));
        await bloc.close().timeout(const Duration(seconds: 2));
        nameReply.complete(true);
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => <DeployPillarState>[const DeployPillarLoading()],
      verify: (_) {
        verifyNever(
          () => pillarApi.register(any(), any(), any(), any(), any()),
        );
        verifyNever(
          () => accountBlockUtils.createAccountBlock(
            any(),
            any(),
            waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
          ),
        );
      },
    );

    blocTest<DeployPillarBloc, DeployPillarState>(
      'emits failure when pillar name already exists',
      setUp: () {
        when(
          () => pillarApi.checkNameAvailability(any()),
        ).thenAnswer((_) async => false);
      },
      build: makeBloc,
      act: (DeployPillarBloc bloc) => bloc.add(
        DeployPillarRequested(
          blockProducingAddress: emptyAddress,
          giveBlockRewardPercentage: 1,
          giveDelegateRewardPercentage: 1,
          pillarName: 'pillar',
          rewardAddress: emptyAddress,
        ),
      ),
      expect: () => <Matcher>[
        isA<DeployPillarLoading>(),
        isA<DeployPillarFailure>().having(
          (DeployPillarFailure s) => s.exception,
          'exception',
          isA<PillarNameAlreadyExistsException>(),
        ),
      ],
    );
  });
}
