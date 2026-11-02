import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/step_switcher.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class MockIssueTokenBloc extends MockBloc<IssueTokenEvent, IssueTokenState>
    implements IssueTokenBloc {}

class MockFavoriteTokensRepository extends Mock
    implements FavoriteTokensRepository {}

class MockAccountBlockTemplate extends Mock implements AccountBlockTemplate {}

void main() {
  group('IssueTokenStep', () {
    late MockIssueTokenBloc issueTokenBloc;
    late MockFavoriteTokensRepository favoriteTokensRepository;
    late ValueNotifier<NewTokenData> tokenData;

    setUp(() {
      issueTokenBloc = MockIssueTokenBloc();
      favoriteTokensRepository = MockFavoriteTokensRepository();
      when(() => issueTokenBloc.state).thenReturn(const IssueTokenInitial());
      tokenData = ValueNotifier<NewTokenData>(
        NewTokenData(
          address: 'z1qq6eg8n43g032hanpsfp02qcdmv7zfj3y2lt5d',
          tokenName: 'Token',
          tokenSymbol: 'TKN',
          tokenDomain: 'example.com',
          totalSupply: BigInt.one,
          decimals: 0,
          maxSupply: BigInt.one,
          isMintable: false,
          isBurnable: false,
          isUtility: true,
        ),
      );
    });

    tearDown(() async {
      tokenData.dispose();
      await issueTokenBloc.close();
    });

    testWidgets(
      'submits utility value changed by the checkbox',
      (WidgetTester tester) async {
        NewTokenData? submittedTokenData;

        await _pumpIssueTokenStep(
          tester,
          issueTokenBloc: issueTokenBloc,
          favoriteTokensRepository: favoriteTokensRepository,
          tokenData: tokenData,
          onIssuePressed: () {
            submittedTokenData = tokenData.value;
          },
        );

        await tester.tap(find.byKey(const Key('token_utility_checkbox')));
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('token_create_button')),
            matching: find.byType(OutlinedButton),
          ),
        );

        expect(submittedTokenData, isNotNull);
        expect(submittedTokenData!.isUtility, isFalse);
      },
    );

    testWidgets('retains issuance acceptance before saving the favorite', (
      WidgetTester tester,
    ) async {
      final MockAccountBlockTemplate accountBlock = MockAccountBlockTemplate();
      final TokenStandard newTokenStandard = TokenStandard.parse(
        'zts1zdl4pmr425t0j97v4eu0du',
      );
      final List<String> calls = <String>[];
      when(() => accountBlock.tokenStandard).thenReturn(znnZts);
      when(
        () => favoriteTokensRepository.add(newTokenStandard),
      ).thenAnswer((_) async => calls.add('favorite'));
      whenListen(
        issueTokenBloc,
        Stream<IssueTokenState>.value(
          IssueTokenDone(
            accountBlock: accountBlock,
            newTokenStandard: newTokenStandard,
          ),
        ),
        initialState: const IssueTokenInitial(),
      );
      await _pumpIssueTokenStep(
        tester,
        issueTokenBloc: issueTokenBloc,
        favoriteTokensRepository: favoriteTokensRepository,
        tokenData: tokenData,
        onIssuePressed: () {},
        onIssueDone: () => calls.add('done'),
      );
      await tester.pumpAndSettle();

      verify(
        () => favoriteTokensRepository.add(newTokenStandard),
      ).called(1);
      expect(calls, <String>['done', 'favorite']);
    });

    testWidgets(
      'favorite and UI observer errors preserve the original acceptance',
      (WidgetTester tester) async {
        final AccountBlockTemplate accepted =
            AccountBlockTemplate(
                blockType: BlockTypeEnum.userSend.index,
              )
              ..hash = Hash.parse(List<String>.filled(64, '8').join())
              ..address = emptyAddress
              ..chainIdentifier = 321;
        final TokenStandard issued = TokenStandard.parse(
          'zts1zdl4pmr425t0j97v4eu0du',
        );
        RegistrationPublication? publication;
        int completions = 0;
        when(() => favoriteTokensRepository.add(issued)).thenAnswer(
          (_) async => throw StateError('optional favorite write'),
        );
        whenListen(
          issueTokenBloc,
          Stream<IssueTokenState>.value(
            IssueTokenDone(accountBlock: accepted, newTokenStandard: issued),
          ),
          initialState: const IssueTokenInitial(),
        );
        await _pumpIssueTokenStep(
          tester,
          issueTokenBloc: issueTokenBloc,
          favoriteTokensRepository: favoriteTokensRepository,
          tokenData: tokenData,
          onIssuePressed: () {},
          onPublished: (RegistrationPublication original) {
            publication = original;
            throw StateError('optional receipt observer');
          },
          onIssueDone: () {
            completions++;
            throw StateError('optional completion observer');
          },
        );
        await tester.pump();
        expect(publication!.accountBlock, same(accepted));
        expect(publication!.hash, accepted.hash);
        expect(publication!.ownerAddress, emptyAddress.toString());
        expect(publication!.chainId, 321);
        expect(completions, 1);
        verify(() => favoriteTokensRepository.add(issued)).called(1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'retains the original issue listener without hidden publication',
      (
        WidgetTester tester,
      ) async {
        int listens = 0;
        int cancellations = 0;
        int submissions = 0;
        int completions = 0;
        final StreamController<IssueTokenState> states =
            StreamController<IssueTokenState>.broadcast(
              onListen: () => listens++,
              onCancel: () => cancellations++,
            );
        final Completer<void> saved = Completer<void>();
        addTearDown(() async {
          if (!saved.isCompleted) {
            saved.complete();
          }
          await states.close();
        });
        when(() => issueTokenBloc.stream).thenAnswer((_) => states.stream);
        final TokenStandard issued = TokenStandard.parse(
          'zts1zdl4pmr425t0j97v4eu0du',
        );
        when(() => favoriteTokensRepository.add(issued)).thenAnswer(
          (_) => saved.future,
        );
        Widget host(int step, {bool showContent = true}) =>
            RepositoryProvider<FavoriteTokensRepository>.value(
              value: favoriteTokensRepository,
              child: BlocProvider<IssueTokenBloc>.value(
                value: issueTokenBloc,
                child: MaterialApp(
                  localizationsDelegates: appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                    body: SizedBox(
                      width: 700,
                      height: 500,
                      child: StepSwitcher.retained(
                        step: step,
                        showContent: showContent,
                        children: <Widget>[
                          const SizedBox(height: 60),
                          IssueTokenStep(
                            active: step == 1 && showContent,
                            onBackPressed: () {},
                            onIssueDone: () => completions++,
                            onIssuePressed: () => submissions++,
                            tokenData: tokenData,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
        Finder create() => find.descendant(
          of: find.byKey(const Key('token_create_button')),
          matching: find.byType(OutlinedButton),
        );

        await tester.pumpWidget(host(0));
        await tester.pumpAndSettle();
        final State<IssueTokenStep> original = tester.state(
          find.byType(IssueTokenStep, skipOffstage: false),
        );
        expect(listens, 1);
        expect(submissions, 0);
        expect(completions, 0);
        await tester.pumpWidget(host(1));
        await tester.pumpAndSettle();
        expect(submissions, 0);
        await tester.tap(create());
        await tester.pump();
        expect(submissions, 1);
        final Offset oldAction = tester.getCenter(create());

        await tester.pumpWidget(host(0));
        await tester.tapAt(oldAction);
        expect(submissions, 1);
        states.add(
          IssueTokenDone(
            accountBlock: MockAccountBlockTemplate(),
            newTokenStandard: issued,
          ),
        );
        await tester.pump();
        verify(() => favoriteTokensRepository.add(issued)).called(1);
        expect(completions, 1);
        await tester.pumpWidget(host(1));
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(IssueTokenStep, skipOffstage: false)),
          same(original),
        );
        await tester.tap(create());
        expect(submissions, 1);
        expect(listens, 1);
        expect(cancellations, 0);

        saved.complete();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(completions, 1);
        await tester.pumpWidget(host(1, showContent: false));
        await tester.pumpAndSettle();
        expect(cancellations, 0);
        expect(submissions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(cancellations, 1);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Future<void> _pumpIssueTokenStep(
  WidgetTester tester, {
  required IssueTokenBloc issueTokenBloc,
  required FavoriteTokensRepository favoriteTokensRepository,
  required ValueNotifier<NewTokenData> tokenData,
  required VoidCallback onIssuePressed,
  VoidCallback? onIssueDone,
  ValueChanged<RegistrationPublication>? onPublished,
}) async {
  await tester.pumpWidget(
    RepositoryProvider<FavoriteTokensRepository>.value(
      value: favoriteTokensRepository,
      child: BlocProvider<IssueTokenBloc>.value(
        value: issueTokenBloc,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 500,
              child: IssueTokenStep(
                onPublished: onPublished,
                onBackPressed: () {},
                onIssueDone: onIssueDone ?? () {},
                onIssuePressed: onIssuePressed,
                tokenData: tokenData,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
