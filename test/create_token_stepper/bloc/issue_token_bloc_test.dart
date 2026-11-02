import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../token_actions_redesign/support.dart' show ActionTerminalObserver;

class MockZenon extends Mock implements Zenon {}

class MockEmbedded extends Mock implements EmbeddedApi {}

class MockTokenApi extends Mock implements TokenApi {}

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

  group('IssueTokenBloc', () {
    late MockZenon zenon;
    late MockEmbedded embedded;
    late MockTokenApi tokenApi;
    late MockAccountBlockUtils accountBlockUtils;
    late MockZenonAddressUtils zenonAddressUtils;
    late MockAccountBlockTemplate template;
    late MockAccountBlockTemplate response;
    late Hash sendBlockHash;
    late TokenStandard newTokenStandard;
    late NewTokenData tokenData;

    IssueTokenBloc makeBloc() => IssueTokenBloc(
      accountBlockUtils: accountBlockUtils,
      zenon: zenon,
      zenonAddressUtils: zenonAddressUtils,
    );

    ActionTerminalObserver<IssueTokenState> terminalObserver() =>
        ActionTerminalObserver<IssueTokenState>(
          target: (BlocBase<dynamic> candidate) => candidate is IssueTokenBloc,
          terminal: (IssueTokenState state) =>
              state is IssueTokenDone || state is IssueTokenFailure,
        );

    setUp(() {
      zenon = MockZenon();
      embedded = MockEmbedded();
      tokenApi = MockTokenApi();
      accountBlockUtils = MockAccountBlockUtils();
      zenonAddressUtils = MockZenonAddressUtils();
      template = MockAccountBlockTemplate();
      response = MockAccountBlockTemplate();
      sendBlockHash = Hash.parse(
        '33f409250960e0c1c9f57b8a278f0937'
        '49bf8844ea0ca4f4b7b5526d05cdd3ce',
      );
      newTokenStandard = TokenStandard.parse(
        'zts1zdl4pmr425t0j97v4eu0du',
      );
      tokenData = NewTokenData(
        address: emptyAddress.toString(),
        tokenName: 'Token',
        tokenSymbol: 'TKN',
        tokenDomain: 'testing.com',
        totalSupply: BigInt.one,
        maxSupply: BigInt.one,
        decimals: 0,
        isMintable: false,
        isBurnable: false,
        isUtility: true,
      );

      when(() => zenon.embedded).thenReturn(embedded);
      when(() => embedded.token).thenReturn(tokenApi);
      when(
        () => tokenApi.issueToken(
          any(),
          any(),
          any(),
          any(),
          any(),
          any(),
          any(),
          any(),
          any(),
        ),
      ).thenReturn(template);
      when(() => response.hash).thenReturn(sendBlockHash);
      when(() => response.tokenStandard).thenReturn(znnZts);
      when(
        () => accountBlockUtils.createAccountBlock(
          any(),
          any(),
          address: any(named: 'address'),
          waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        ),
      ).thenAnswer((_) async => response);
      when(() => zenonAddressUtils.refreshBalance()).thenAnswer((_) {});
    });

    test('initial state is correct', () {
      final IssueTokenBloc bloc = makeBloc();
      addTearDown(bloc.close);
      expect(bloc.state, const IssueTokenInitial());
    });

    for (final bool accepted in <bool>[true, false]) {
      test(
        'terminal observer errors retain original issuance: $accepted',
        () async {
          final StateError originalError = StateError(
            'Synthetic issuance result',
          );
          if (!accepted) {
            when(
              () => accountBlockUtils.createAccountBlock(
                any(),
                any(),
                address: any(named: 'address'),
                waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
              ),
            ).thenThrow(originalError);
          }
          final ActionTerminalObserver<IssueTokenState> observer =
              terminalObserver();
          final BlocObserver previous = Bloc.observer;
          Bloc.observer = observer;
          final IssueTokenBloc bloc = makeBloc();
          final Future<IssueTokenState> delivery = bloc.stream
              .firstWhere(observer.terminal)
              .timeout(const Duration(seconds: 1));
          try {
            bloc.add(IssueTokenRequested(tokenData: tokenData));
            final IssueTokenState terminal = await delivery;
            expect(observer.attempted, <IssueTokenState>[terminal]);
            expect(bloc.state, same(terminal));
            expect(observer.reported, contains(same(observer.displayError)));
            if (accepted) {
              final IssueTokenDone done = terminal as IssueTokenDone;
              expect(done.accountBlock, same(response));
              expect(done.newTokenStandard, newTokenStandard);
              expect(bloc.lastAccepted, same(response));
              verify(zenonAddressUtils.refreshBalance).called(1);
            } else {
              final IssueTokenFailure failure = terminal as IssueTokenFailure;
              expect(failure.error, same(originalError));
              expect(failure.exception, isA<FailureException>());
              expect(observer.reported, contains(same(originalError)));
              expect(bloc.lastAccepted, isNull);
              verifyNever(zenonAddressUtils.refreshBalance);
            }
            verify(
              () => accountBlockUtils.createAccountBlock(
                template,
                any(),
                address: emptyAddress,
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

    test(
      'preparation error survives terminal and diagnostic observers',
      () async {
        final StateError originalError = StateError(
          'Synthetic issuance builder',
        );
        when(
          () => tokenApi.issueToken(
            any(),
            any(),
            any(),
            any(),
            any(),
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenThrow(originalError);
        final ActionTerminalObserver<IssueTokenState> observer =
            terminalObserver();
        final BlocObserver previous = Bloc.observer;
        Bloc.observer = observer;
        final IssueTokenBloc bloc = makeBloc();
        final Future<IssueTokenState> delivery = bloc.stream
            .firstWhere(observer.terminal)
            .timeout(const Duration(seconds: 1));
        try {
          bloc.add(IssueTokenRequested(tokenData: tokenData));
          final IssueTokenFailure terminal =
              await delivery as IssueTokenFailure;
          expect(observer.attempted, <IssueTokenState>[terminal]);
          expect(bloc.state, same(terminal));
          expect(terminal.error, same(originalError));
          expect(terminal.exception, isA<FailureException>());
          expect(observer.reported, contains(same(originalError)));
          expect(bloc.lastAccepted, isNull);
          verifyNever(
            () => accountBlockUtils.createAccountBlock(
              any(),
              any(),
              address: any(named: 'address'),
              waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
            ),
          );
        } finally {
          Bloc.observer = previous;
          await bloc.close();
        }
      },
    );

    blocTest<IssueTokenBloc, IssueTokenState>(
      'emits [loading, done] on success',
      build: makeBloc,
      act: (IssueTokenBloc bloc) => bloc.add(
        IssueTokenRequested(tokenData: tokenData),
      ),
      verify: (_) {
        verify(
          () => tokenApi.issueToken(
            tokenData.tokenName,
            tokenData.tokenSymbol,
            tokenData.tokenDomain,
            tokenData.totalSupply,
            tokenData.maxSupply,
            tokenData.decimals,
            tokenData.isMintable,
            tokenData.isBurnable,
            tokenData.isUtility,
          ),
        ).called(1);
        verify(() => zenonAddressUtils.refreshBalance()).called(1);
      },
      expect: () => <IssueTokenState>[
        const IssueTokenLoading(),
        IssueTokenDone(
          accountBlock: response,
          newTokenStandard: newTokenStandard,
        ),
      ],
    );

    late StateError observerError;
    blocTest<IssueTokenBloc, IssueTokenState>(
      'retains the exact issuance response when balance observation fails',
      setUp: () {
        observerError = StateError('optional balance observer');
        when(zenonAddressUtils.refreshBalance).thenThrow(observerError);
      },
      build: makeBloc,
      act: (IssueTokenBloc bloc) => bloc.add(
        IssueTokenRequested(tokenData: tokenData),
      ),
      expect: () => <Matcher>[
        isA<IssueTokenLoading>(),
        isA<IssueTokenDone>()
            .having(
              (IssueTokenDone state) => state.accountBlock,
              'original response',
              same(response),
            )
            .having(
              (IssueTokenDone state) => state.newTokenStandard,
              'original token standard',
              newTokenStandard,
            ),
      ],
      errors: () => <Matcher>[same(observerError)],
    );

    late StateError originalError;
    blocTest<IssueTokenBloc, IssueTokenState>(
      'reports an arbitrary original error and completes the failed form',
      setUp: () {
        originalError = StateError('original publication error');
        when(
          () => accountBlockUtils.createAccountBlock(
            any(),
            any(),
            address: any(named: 'address'),
            waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
          ),
        ).thenThrow(originalError);
      },
      build: makeBloc,
      act: (IssueTokenBloc bloc) => bloc.add(
        IssueTokenRequested(tokenData: tokenData),
      ),
      expect: () => <Matcher>[
        isA<IssueTokenLoading>(),
        isA<IssueTokenFailure>(),
      ],
      errors: () => <Matcher>[same(originalError)],
      verify: (_) => verifyNever(zenonAddressUtils.refreshBalance),
    );

    for (final bool accepted in <bool>[true, false]) {
      late Completer<AccountBlockTemplate> original;
      late Completer<void> started;
      late StateError failure;
      blocTest<IssueTokenBloc, IssueTokenState>(
        'closed form retains the original outcome without emission: $accepted',
        setUp: () {
          original = Completer<AccountBlockTemplate>();
          started = Completer<void>();
          failure = StateError('original or optional observer error');
          when(
            () => accountBlockUtils.createAccountBlock(
              any(),
              any(),
              address: any(named: 'address'),
              waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
            ),
          ).thenAnswer((_) {
            started.complete();
            return original.future;
          });
          when(zenonAddressUtils.refreshBalance).thenThrow(failure);
        },
        build: makeBloc,
        act: (IssueTokenBloc bloc) async {
          bloc.add(IssueTokenRequested(tokenData: tokenData));
          await started.future.timeout(const Duration(seconds: 2));
          await bloc.close().timeout(const Duration(seconds: 2));
          if (accepted) {
            original.complete(response);
          } else {
            original.completeError(failure);
          }
          await Future<void>.delayed(Duration.zero);
        },
        expect: () => <IssueTokenState>[const IssueTokenLoading()],
        errors: () => <Matcher>[same(failure)],
        verify: (IssueTokenBloc bloc) {
          expect(bloc.isClosed, isTrue);
          if (accepted) {
            verify(zenonAddressUtils.refreshBalance).called(1);
          } else {
            verifyNever(zenonAddressUtils.refreshBalance);
          }
        },
      );
    }

    blocTest<IssueTokenBloc, IssueTokenState>(
      'emits [loading, failure] on SyriusException',
      setUp: () {
        when(
          () => accountBlockUtils.createAccountBlock(
            any(),
            any(),
            address: any(named: 'address'),
            waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
          ),
        ).thenThrow(FailureException());
      },
      build: makeBloc,
      act: (IssueTokenBloc bloc) => bloc.add(
        IssueTokenRequested(tokenData: tokenData),
      ),
      expect: () => <Matcher>[
        isA<IssueTokenLoading>(),
        isA<IssueTokenFailure>().having(
          (IssueTokenFailure state) => state.exception,
          'exception',
          isA<FailureException>(),
        ),
      ],
    );

    blocTest<IssueTokenBloc, IssueTokenState>(
      'emits [loading, failure] on generic exception',
      setUp: () {
        when(
          () => accountBlockUtils.createAccountBlock(
            any(),
            any(),
            address: any(named: 'address'),
            waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
          ),
        ).thenThrow(Exception('boom'));
      },
      build: makeBloc,
      act: (IssueTokenBloc bloc) => bloc.add(
        IssueTokenRequested(tokenData: tokenData),
      ),
      expect: () => <Matcher>[
        isA<IssueTokenLoading>(),
        isA<IssueTokenFailure>().having(
          (IssueTokenFailure state) => state.exception,
          'exception',
          isA<FailureException>(),
        ),
      ],
    );
  });
}
