import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/tokens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

void main() {
  final String owner = emptyAddress.toString();
  final Token held = tokenFixture(1, name: 'Held token', symbol: 'SAME');
  final Token unheld = tokenFixture(
    2,
    name: 'Unheld token',
    symbol: 'SAME',
    owner: tokenAddress,
  );
  final Token zero = tokenFixture(3);
  final BigInt exact = BigInt.parse('900719925474099312345678901234567890');

  TokenBalanceSnapshot snapshot() => TokenBalanceSnapshot.fromAccount(
    AccountInfo.fromJson(
      tokenAccount(<(Token, BigInt)>[
        (kZnnCoin, BigInt.one),
        (kQsrCoin, BigInt.one),
        (held, exact),
        (zero, BigInt.zero),
      ]),
    ),
    owner,
  );

  test('exact units exceed binary float precision without rounding', () {
    final TokenBalanceSnapshot balances = snapshot();
    expect(balances.unitsFor(held.tokenStandard), exact);
    expect(balances.heldCount, 1);
    expect(balances.heldTokens.single.tokenStandard, held.tokenStandard);
  });

  test(
    'successful complete absent membership is zero, unavailable is null',
    () {
      expect(snapshot().unitsFor(unheld.tokenStandard), BigInt.zero);
      expect(const TokenBalanceState().current, isNull);
      expect(const TokenBalanceState(failed: true).current, isNull);
      final TokenBalanceSnapshot empty = TokenBalanceSnapshot.fromAccount(
        AccountInfo.fromJson(<String, dynamic>{
          'address': owner,
          'accountHeight': 0,
        }),
        owner,
      );
      expect(empty.heldCount, 0);
      expect(empty.unitsFor(held.tokenStandard), BigInt.zero);
    },
  );

  test('null, duplicate, negative and other-account balances are refused', () {
    final List<AccountInfo> invalid = <AccountInfo>[
      AccountInfo(address: owner, blockCount: 1),
      AccountInfo(
        address: owner,
        balanceInfoList: const <BalanceInfoListItem>[],
      ),
      AccountInfo(
        address: tokenAddress.toString(),
        blockCount: 1,
        balanceInfoList: const <BalanceInfoListItem>[],
      ),
      AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(token: held, balance: null),
        ],
      ),
      AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(token: null, balance: BigInt.one),
        ],
      ),
      AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(token: held, balance: -BigInt.one),
        ],
      ),
      AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[
          BalanceInfoListItem(token: held, balance: BigInt.one),
          BalanceInfoListItem(token: held, balance: BigInt.two),
        ],
      ),
    ];
    for (final AccountInfo account in invalid) {
      expect(
        () => TokenBalanceSnapshot.fromAccount(account, owner),
        throwsFormatException,
      );
    }
  });

  test('captured units and token metadata do not alias mutable SDK fields', () {
    final Token mutable = tokenFixture(4);
    final BalanceInfoListItem entry = BalanceInfoListItem(
      token: mutable,
      balance: exact,
    );
    final TokenBalanceSnapshot captured = TokenBalanceSnapshot.fromAccount(
      AccountInfo(
        address: owner,
        blockCount: 1,
        balanceInfoList: <BalanceInfoListItem>[entry],
      ),
      owner,
    );
    entry.balance = BigInt.zero;
    mutable.name = 'Changed externally';
    expect(captured.unitsFor(mutable.tokenStandard), exact);
    expect(captured.heldTokens.single.name, 'Fixture token 4');
  });

  test('malformed account numeric metadata remains unavailable', () {
    for (final int decimals in <int>[-1, 256, 1000000000]) {
      final Token malformed = tokenFixture(9, decimals: decimals);
      expect(
        () => TokenBalanceSnapshot.fromAccount(
          AccountInfo(
            address: owner,
            blockCount: 1,
            balanceInfoList: <BalanceInfoListItem>[
              BalanceInfoListItem(token: malformed, balance: BigInt.one),
            ],
          ),
          owner,
        ),
        throwsFormatException,
      );
    }
    final Token negative = tokenFixture(10, supply: -BigInt.one);
    expect(
      () => TokenBalanceSnapshot.fromAccount(
        AccountInfo(
          address: owner,
          blockCount: 1,
          balanceInfoList: <BalanceInfoListItem>[
            BalanceInfoListItem(token: negative, balance: BigInt.one),
          ],
        ),
        owner,
      ),
      throwsFormatException,
    );
  });

  List<Token>? project(
    TokensFilter filter, {
    List<Token>? catalog,
    TokenBalanceSnapshot? balances,
    Set<String> favorites = const <String>{},
    String query = '',
  }) => TokenListProjection(
    catalog: catalog,
    balances: balances,
    favorites: favorites,
    filter: filter,
    query: query,
  ).rows;

  test(
    'Held works from complete account facts while catalog is unavailable',
    () {
      final List<Token>? rows = project(
        TokensFilter.held,
        balances: snapshot(),
      );
      expect(rows?.single.tokenStandard, held.tokenStandard);
      expect(project(TokensFilter.held, catalog: <Token>[held]), isNull);
      expect(project(TokensFilter.all, balances: snapshot()), isNull);
      expect(project(TokensFilter.favorites, balances: snapshot()), isNull);
    },
  );

  test(
    'Favorites includes an unheld later catalog token and matches exact ZTS',
    () {
      final List<Token> catalog = <Token>[held, unheld, kZnnCoin, kQsrCoin];
      final List<Token>? rows = project(
        TokensFilter.favorites,
        catalog: catalog,
        balances: snapshot(),
        favorites: <String>{unheld.tokenStandard.toString(), 'SAME'},
      );
      expect(rows, hasLength(1));
      expect(rows!.single.tokenStandard, unheld.tokenStandard);
      expect(snapshot().unitsFor(unheld.tokenStandard), BigInt.zero);
      expect(project(TokensFilter.all, catalog: catalog), hasLength(2));
    },
  );

  test(
    'all four query fields filter the same list without changing membership',
    () {
      final List<Token> catalog = <Token>[held, unheld];
      for (final String query in <String>[
        'UNHELD TOKEN',
        'same',
        tokenAddress.toString().toUpperCase(),
        unheld.tokenStandard.toString().toUpperCase(),
      ]) {
        final List<Token>? rows = project(
          TokensFilter.favorites,
          catalog: catalog,
          balances: snapshot(),
          query: query,
          favorites: <String>{unheld.tokenStandard.toString()},
        );
        expect(rows?.single.tokenStandard, unheld.tokenStandard);
      }
    },
  );

  test('favorite changes filter membership without shuffling All', () {
    final List<Token> catalog = <Token>[held, unheld, zero];
    expect(
      project(
        TokensFilter.all,
        catalog: catalog,
        favorites: <String>{zero.tokenStandard.toString()},
      )!.map((Token token) => token.tokenStandard),
      catalog.map((Token token) => token.tokenStandard),
    );
  });

  test(
    'issued count is selected-account scoped and unavailable stays unknown',
    () {
      expect(issuedTokenCount(null, owner), isNull);
      expect(issuedTokenCount(<Token>[], owner), 0);
      expect(
        issuedTokenCount(<Token>[held, unheld, kZnnCoin, kQsrCoin], owner),
        1,
      );
      expect(issuedTokenCount(<Token>[held], null), isNull);
    },
  );

  test('controller retains only filter, query and finite scroll state', () {
    final TokensPageController controller = TokensPageController();
    addTearDown(controller.dispose);
    controller
      ..selectFilter(TokensFilter.favorites)
      ..setQuery(' exact query ')
      ..rememberScroll(840);
    expect(controller.filter, TokensFilter.favorites);
    expect(controller.query, ' exact query ');
    expect(controller.scrollOffset, 840);
    controller
      ..rememberScroll(double.nan)
      ..rememberScroll(-1);
    expect(controller.scrollOffset, 840);
    controller.selectFilter(TokensFilter.all);
    expect(controller.scrollOffset, 0);
    expect(controller.query, ' exact query ');
  });
}
