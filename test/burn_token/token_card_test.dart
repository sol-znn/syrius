import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

void main() {
  const String owner = 'z1qq6eg8n43g032hanpsfp02qcdmv7zfj3y2lt5d';
  const String holder = 'z1qp3yph55qgresyytz83anynr2f4z39x2z3ej3e';

  setUp(() {
    kSelectedAddress = holder;
    kDefaultAddressList = <String?>[holder];
    kAddressLabelMap = <String, String>{holder: 'Holder'};
  });

  tearDown(() {
    kSelectedAddress = null;
    kDefaultAddressList = <String?>[];
    kAddressLabelMap = <String, String>{};
  });

  testWidgets('allows a non-owner to burn a publicly burnable token', (
    WidgetTester tester,
  ) async {
    await _pumpTokenCard(
      tester,
      _buildToken(owner: owner, isBurnable: true),
    );

    final Finder burnButton = find.byKey(const Key('token_burn_button'));
    expect(burnButton, findsOneWidget);
    expect(tester.widget<IconButton>(burnButton).onPressed, isNotNull);
  });

  testWidgets('allows the owner to burn an owner-only token', (
    WidgetTester tester,
  ) async {
    kSelectedAddress = owner;
    kDefaultAddressList = <String?>[owner];
    kAddressLabelMap = <String, String>{owner: 'Owner'};

    await _pumpTokenCard(
      tester,
      _buildToken(owner: owner, isBurnable: false),
    );

    final Finder burnButton = find.byKey(const Key('token_burn_button'));
    expect(burnButton, findsOneWidget);
    expect(tester.widget<IconButton>(burnButton).onPressed, isNotNull);
  });

  testWidgets('hides owner-only burn from the selected non-owner', (
    WidgetTester tester,
  ) async {
    kDefaultAddressList = <String?>[holder, owner];
    kAddressLabelMap = <String, String>{
      holder: 'Holder',
      owner: 'Owner',
    };

    await _pumpTokenCard(
      tester,
      _buildToken(owner: owner, isBurnable: false),
    );

    expect(find.byKey(const Key('token_burn_button')), findsNothing);
  });
}

Token _buildToken({required String owner, required bool isBurnable}) => Token(
  'Test Token',
  'TST',
  'zenon.org',
  BigInt.from(85),
  0,
  Address.parse(owner),
  znnZts,
  BigInt.from(100),
  isBurnable,
  false,
  true,
);

Future<void> _pumpTokenCard(
  WidgetTester tester,
  Token token,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 500,
          child: TokenCard(
            token: token,
            favoritesCallback: () {},
            favoriteRepository: _Favorites(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _Favorites implements FavoriteTokensRepository {
  @override
  bool contains(TokenStandard standard) => false;
  @override
  Future<void> add(TokenStandard standard) async {}
  @override
  Future<void> remove(TokenStandard standard) async {}
}
