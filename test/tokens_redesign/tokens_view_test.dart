import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/all_tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

class _Web3Service extends Mock implements IWeb3WalletService {
  int disposals = 0;

  @override
  void onDispose() => disposals++;
}

class _ObservedCatalog extends AllTokensBloc {
  _ObservedCatalog({required super.zenon});

  final List<Object> failures = <Object>[];

  @override
  void onError(Object error, StackTrace stackTrace) {
    failures.add(error);
    super.onError(error, stackTrace);
  }
}

/// Drains logical fixture callbacks on the widget clock that owns them.
Future<void> _pumpLogicalFuture<T>(
  WidgetTester tester,
  Future<T> pending, {
  required String description,
  VoidCallback? start,
}) async {
  bool completed = false;
  (Object, StackTrace)? failure;
  unawaited(
    pending.then<void>(
      (T _) {
        completed = true;
      },
      onError: (Object error, StackTrace stackTrace) {
        failure = (error, stackTrace);
        completed = true;
      },
    ),
  );
  start?.call();
  for (int turn = 0; turn < 100 && !completed; turn++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  final (Object, StackTrace)? originalFailure = failure;
  if (originalFailure != null) {
    Error.throwWithStackTrace(originalFailure.$1, originalFailure.$2);
  }
  expect(
    completed,
    isTrue,
    reason: '$description did not complete within 100 widget-clock turns.',
  );
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    ),
  ),
);

void main() {
  initHydratedStorage();
  late TokenTestClient transport;
  late TokenTestSdk sdk;
  late TokenTestGlobals globals;
  late TokenReadContext scope;
  late TokenTestFavorites favorites;
  final Token held = tokenFixture(1, name: 'Held token');
  final Token unheld = tokenFixture(
    2,
    name: 'Unheld favorite',
    owner: tokenAddress,
  );
  final BigInt exact = BigInt.parse('90071992547409931234567890');

  setUp(() {
    transport = TokenTestClient(
      (_, _) async => tokenPage(<Token>[held, unheld]),
    );
    sdk = TokenTestSdk(transport);
    globals = TokenTestGlobals()..install(sdk.zenon);
    scope = TokenReadContext(client: transport, ownsClient: () => true);
    favorites = TokenTestFavorites()
      ..standards.add(unheld.tokenStandard.toString());
  });

  tearDown(() async {
    await sdk.close();
    globals.restore();
    AppLottie.debugClear();
  });

  TokenBalanceState balances() => TokenBalanceState(
    context: scope,
    snapshot: TokenBalanceSnapshot.fromAccount(
      AccountInfo.fromJson(tokenAccount(<(Token, BigInt)>[(held, exact)])),
      emptyAddress.toString(),
    ),
  );

  for (final Brightness brightness in Brightness.values) {
    for (final TextDirection direction in TextDirection.values) {
      testWidgets(
        '${brightness.name} ${direction.name} shares filters '
        'and exact balances',
        (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = const Size(1280, 780);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final TokensPageController controller = TokensPageController();
          final ThemeData theme = brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme;
          await tester.pumpWidget(
            _host(
              TokensCard(
                controller: controller,
                catalog: AllTokensPopulated(
                  data: <Token>[held, unheld],
                  context: scope,
                ),
                balances: balances(),
                favoriteRepository: favorites,
              ),
              theme: theme,
              direction: direction,
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('Held token'), findsOneWidget);
          expect(find.text('Unheld favorite'), findsNothing);
          final Finder amount = find.byWidgetPredicate(
            (Widget widget) => widget is AmountText && widget.raw == exact,
          );
          expect(amount, findsOneWidget);
          final Text rendered = tester.widget<Text>(
            find.descendant(
              of: amount,
              matching: find.byType(Text),
            ),
          );
          expect(rendered.textDirection, TextDirection.ltr);
          expect(
            rendered.textSpan!.toPlainText(),
            splitAmount(exact, held.decimals).$1,
          );
          controller.selectFilter(TokensFilter.favorites);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('Unheld favorite'), findsOneWidget);
          expect(find.text('Held token'), findsNothing);
          expect(
            find.byWidgetPredicate(
              (Widget widget) =>
                  widget is AmountText && widget.raw == BigInt.zero,
            ),
            findsOneWidget,
          );
          controller.selectFilter(TokensFilter.all);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.enterText(
            find.byKey(const Key('tokens_search_field')),
            unheld.tokenStandard.toString(),
          );
          await tester.pump();
          expect(find.text('Held token'), findsNothing);
          expect(find.text('Unheld favorite'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        },
      );
    }
  }

  testWidgets(
    'unavailable balances display an unknown marker rather than zero',
    (
      WidgetTester tester,
    ) async {
      final TokensPageController controller = TokensPageController()
        ..selectFilter(TokensFilter.all);
      await tester.pumpWidget(
        _host(
          TokensCard(
            controller: controller,
            catalog: AllTokensPopulated(data: <Token>[unheld], context: scope),
            favoriteRepository: favorites,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byTooltip('Balance unavailable'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is AmountText && widget.raw == BigInt.zero,
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('unbound hydrated catalog cannot expose an authorized row', (
    WidgetTester tester,
  ) async {
    final TokensPageController controller = TokensPageController()
      ..selectFilter(TokensFilter.all);
    final AllTokensState cached = AllTokensState.fromJson(
      AllTokensPopulated(data: <Token>[held]).toJson(),
    );
    await tester.pumpWidget(
      _host(
        TokensCard(
          controller: controller,
          catalog: cached,
          favoriteRepository: favorites,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Held token'), findsNothing);
    expect(find.byKey(const Key('token_mint_button')), findsNothing);
    expect(find.byKey(const Key('token_burn_button')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a retained money callback rechecks its original context', (
    WidgetTester tester,
  ) async {
    bool current = true;
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 80,
          child: TokenCard(
            token: held,
            favoriteRepository: favorites,
            favoritesCallback: () {},
            isCurrent: () => current,
          ),
        ),
      ),
    );
    final IconButton mint = tester.widget<IconButton>(
      find.byKey(const Key('token_mint_button')),
    );
    expect(mint.onPressed, isNotNull);
    current = false;
    mint.onPressed!();
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ordinary unmount and remount retain filter query and scroll', (
    WidgetTester tester,
  ) async {
    final TokensPageController controller = TokensPageController()
      ..selectFilter(TokensFilter.all)
      ..setQuery('Fixture');
    final List<Token> catalog = <Token>[
      for (int index = 1; index <= 50; index++) tokenFixture(index),
    ];
    Widget card() => _host(
      TokensCard(
        controller: controller,
        catalog: AllTokensPopulated(data: catalog, context: scope),
        favoriteRepository: favorites,
      ),
    );
    await tester.pumpWidget(card());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.drag(
      find.byKey(const Key('tokens_rows')),
      const Offset(0, -600),
    );
    await tester.pump(const Duration(seconds: 1));
    final double saved = controller.scrollOffset;
    expect(saved, greaterThan(0));
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    await tester.pumpWidget(card());
    await tester.pump();
    final ListView list = tester.widget<ListView>(
      find.byKey(const Key('tokens_rows')),
    );
    expect(list.controller!.offset, closeTo(saved, 1));
    expect(controller.filter, TokensFilter.all);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tokens_search_field')))
          .controller!
          .text,
      'Fixture',
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'the page strip has actual counts SDK fee original coin and create entry',
    (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final AllTokensBloc catalog = AllTokensBloc(zenon: sdk.zenon);
      final TokenBalanceCubit account = TokenBalanceCubit(
        zenon: sdk.zenon,
        address: emptyAddress.toString(),
      );
      transport.respond = (String method, _) async =>
          method == 'embedded.token.getAll'
          ? tokenPage(<Token>[held, unheld])
          : tokenAccount(<(Token, BigInt)>[(held, exact)]);
      final Future<AllTokensState> ready = nextTokenState(
        catalog.stream,
        (AllTokensState state) => state is AllTokensPopulated,
      );
      final Future<TokenBalanceState> balanceReady = nextTokenState(
        account.stream,
        (TokenBalanceState state) => state.current != null,
      );
      await _pumpLogicalFuture<List<Object>>(
        tester,
        Future.wait<Object>(
          <Future<Object>>[ready, balanceReady],
          eagerError: true,
        ),
        description: 'Tokens strip catalog and account readiness',
        start: () {
          catalog.add(const AllTokensRequested());
          account.refresh();
        },
      );
      await tester.runAsync(() async {
        await AppLottie.debugLoad(AppLottieAsset.zts.path(kStripLeadSize, 1));
      });
      int creates = 0;
      await tester.pumpWidget(
        _host(
          BlocProvider<AllTokensBloc>.value(
            value: catalog,
            child: TokensPage(
              balanceReader: account,
              favoriteRepository: favorites,
              onStepperNotificationSeeMorePressed: () {},
              onCreateToken: () => creates++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester.widget<Text>(find.byKey(const Key('tokens_figure_held'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('tokens_figure_issued'))).data,
        '1',
      );
      expect(find.byType(TokenBalanceCard), findsNothing);
      final AppLottie original = tester.widget<AppLottie>(
        find.byType(AppLottie),
      );
      expect(original.size, kStripLeadSize);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is AmountText &&
              widget.raw == tokenZtsIssueFeeInZnn &&
              widget.symbol == 'ZNN',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tokens_create')));
      await tester.pump();
      expect(creates, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpLogicalFuture<void>(
        tester,
        account.close(),
        description: 'Tokens strip account close',
      );
      await _pumpLogicalFuture<void>(
        tester,
        catalog.close(),
        description: 'Tokens strip catalog close',
      );
    },
  );

  testWidgets(
    'actual selection node and revision changes remove old paint and callbacks',
    (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final _Web3Service web3 = _Web3Service();
      when(() => web3.emitAddressChangeEvent(any())).thenAnswer((_) async {});
      app.sl.pushNewScope(scopeName: 'isolated-token-selection');
      app.sl.registerSingleton<IWeb3WalletService>(web3);
      final SelectedAddressNotifier selection = SelectedAddressNotifier();
      final _ObservedCatalog catalog = _ObservedCatalog(zenon: sdk.zenon);
      final TokensPageController controller = TokensPageController()
        ..selectFilter(TokensFilter.all);
      Completer<Object?>? pendingCatalog;
      Completer<Object?>? pendingAccount;
      transport.respond = (String method, List<dynamic> arguments) async {
        // A nullable future must not become the synthetic RPC value itself.
        if (method == 'embedded.token.getAll') {
          return pendingCatalog == null
              ? tokenPage(<Token>[held, unheld])
              : await pendingCatalog.future;
        }
        return pendingAccount == null
            ? tokenAccount(<(Token, BigInt)>[
                (held, exact),
              ], address: arguments[0] as String)
            : await pendingAccount.future;
      };
      await tester.runAsync(
        () => AppLottie.debugLoad(
          AppLottieAsset.zts.path(kStripLeadSize, 1),
        ),
      );
      await tester.pumpWidget(
        _host(
          BlocProvider<AllTokensBloc>.value(
            value: catalog,
            child: TokensPage(
              controller: controller,
              favoriteRepository: favorites,
              onStepperNotificationSeeMorePressed: () {},
              onCreateToken: () {},
            ),
          ),
        ),
      );
      for (int turn = 0; turn < 8; turn++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 500));
      Finder amount(BigInt units) => find.byWidgetPredicate(
        (Widget widget) => widget is AmountText && widget.raw == units,
      );
      Future<void> waitForCurrentUnits(BigInt units) async {
        TokenBalanceState? balance;
        for (int turn = 0; turn < 100; turn++) {
          final Finder cards = find.byType(TokensCard);
          if (cards.evaluate().isNotEmpty) {
            balance = tester.widget<TokensCard>(cards).balances;
            final AllTokensState state = catalog.state;
            if (state is AllTokensPopulated &&
                state.isCurrent &&
                balance.current?.unitsFor(held.tokenStandard) == units) {
              return;
            }
          }
          await tester.pump(const Duration(milliseconds: 1));
        }
        final Iterable<String> requests = transport.requests.map<String>(
          ((String, List<dynamic>) request) => request.$1,
        );
        expect(
          catalog.state,
          isA<AllTokensPopulated>(),
          reason:
              'Catalog requests: ${requests.toList()}; '
              'failures: ${catalog.failures}',
        );
        expect((catalog.state as AllTokensPopulated).isCurrent, isTrue);
        expect(balance?.failed, isFalse);
        expect(balance?.context?.isCurrent, isTrue);
        expect(balance?.current?.unitsFor(held.tokenStandard), units);
      }

      expect(amount(exact), findsOneWidget);
      final VoidCallback oldMint = tester
          .widget<IconButton>(
            find.byKey(const Key('token_mint_button')).first,
          )
          .onPressed!;

      pendingCatalog = Completer<Object?>();
      pendingAccount = Completer<Object?>();
      selection.changeSelectedAddress(tokenAddress.toString());
      oldMint();
      await tester.pump();
      expect(amount(exact), findsNothing);
      expect(find.byKey(const Key('token_mint_button')), findsNothing);
      expect(controller.filter, TokensFilter.all);
      oldMint();
      expect(tester.takeException(), isNull);
      pendingCatalog.complete(tokenPage(<Token>[held, unheld]));
      pendingAccount.complete(
        tokenAccount(<(Token, BigInt)>[
          (held, BigInt.from(5)),
        ], address: tokenAddress.toString()),
      );
      await waitForCurrentUnits(BigInt.from(5));
      await tester.pump(const Duration(milliseconds: 500));
      expect(amount(BigInt.from(5)), findsOneWidget);
      expect(amount(exact), findsNothing);

      for (final bool nodeChange in <bool>[true, false]) {
        pendingCatalog = Completer<Object?>();
        pendingAccount = Completer<Object?>();
        if (nodeChange) {
          kCurrentNode = 'another-isolated-token-node';
          kNodeChainId = 1;
          setChainIdentifier();
          NodeChange.announce();
        } else {
          WalletContextRevision.invalidate();
        }
        await tester.pump();
        expect(amount(BigInt.from(5)), findsNothing);
        expect(find.byKey(const Key('token_mint_button')), findsNothing);
        pendingCatalog.complete(tokenPage(<Token>[held, unheld]));
        pendingAccount.complete(
          tokenAccount(<(Token, BigInt)>[
            (held, BigInt.from(5)),
          ], address: tokenAddress.toString()),
        );
        await waitForCurrentUnits(BigInt.from(5));
        await tester.pump(const Duration(milliseconds: 500));
        expect(amount(BigInt.from(5)), findsOneWidget);
      }
      expect(catalog.failures, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      selection.dispose();
      await _pumpLogicalFuture<void>(
        tester,
        catalog.close(),
        description: 'Tokens source-change catalog close',
      );
      await _pumpLogicalFuture<void>(
        tester,
        app.sl.popScope(),
        description: 'Tokens source-change scope disposal',
      );
      expect(web3.disposals, 1);
    },
  );
}
