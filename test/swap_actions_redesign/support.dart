import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String fixtureAddress(int value) =>
    Address('z', <int>[0, ...List<int>.filled(19, value)]).toString();
String fixtureHash(int value) => value.toRadixString(16).padLeft(64, '0');

class _NoStore implements SwapPersistenceReservation {
  @override
  Future<void> store(HtlcSwap swap) async {}
  @override
  void refuse() {}
  @override
  void retainUnknown(Object error, StackTrace trace) {}
}

class _NoPublication implements SwapPublicationReservation {
  @override
  Future<void> prepare({Map<String, dynamic>? recovery}) async {}
  @override
  Future<void> accepted(String exactHash) async {}
  @override
  Future<void> refuseBeforePublication() async {}
  @override
  void retainUnknown(Object error, StackTrace trace) {}
}

/// No file, signer, SDK client, store, native capability or feed exists.
class SwapUiFixture {
  SwapUiFixture() {
    origin = SwapActionOrigin(
      identity: Object(),
      chainId: 321,
      ownerAddress: owner,
      members: <String>[owner, member],
      isCurrent: () => current,
      readHtlc: (String id) {
        depositReads++;
        return htlcReply?.call(id) ??
            Future<HtlcInfo>.error(const SwapActionRefused('fixture-absent'));
      },
      readBlock: (_) async {
        blockReads++;
        return null;
      },
      readChainTime: () async {
        clockReads++;
        return now;
      },
      readAccount: (String address) {
        accountReads.add(address);
        return accountReply ?? Future<AccountInfo>.value(account(address));
      },
      readToken: (String standard) {
        tokenReads++;
        return tokenReply ??
            Future<Token?>.value(
              <String, Token>{
                kZnnCoin.tokenStandard.toString(): kZnnCoin,
                kQsrCoin.tokenStandard.toString(): kQsrCoin,
              }[standard],
            );
      },
      readHistory: () {
        historyReads++;
        return records;
      },
      readContractBlocks: (_) async {
        blockReads++;
        return <AccountBlock>[];
      },
      reserveStore: () {
        mutations++;
        return _NoStore();
      },
      reservePublication: (_, _, _) {
        mutations++;
        return _NoPublication();
      },
      rearmStart: (_, _) async {
        mutations++;
        return false;
      },
      capturePublisher: (_) {
        mutations++;
        return (_, _) {
          mutations++;
          throw StateError('No fixture publisher');
        };
      },
      create: (_, _, _, _, _, _, _) {
        mutations++;
        throw StateError('No fixture builder');
      },
      unlock: (_, _) {
        mutations++;
        throw StateError('No fixture builder');
      },
      reclaim: (_) {
        mutations++;
        throw StateError('No fixture builder');
      },
    );
  }
  late final SwapActionOrigin origin;
  final String owner = fixtureAddress(1);
  final String member = fixtureAddress(2);
  final String counterparty = fixtureAddress(3);
  bool current = true;
  int now = 1000;
  BigInt available = BigInt.from(120450000000);
  final List<String> accountReads = <String>[];
  int depositReads = 0;
  int tokenReads = 0;
  int blockReads = 0;
  int clockReads = 0;
  int historyReads = 0;
  int mutations = 0;
  List<HtlcSwap> records = <HtlcSwap>[];
  Future<AccountInfo>? accountReply;
  Future<Token?>? tokenReply;
  Future<HtlcInfo> Function(String)? htlcReply;
  AccountInfo account(String address) => AccountInfo(
    address: address,
    blockCount: 1,
    balanceInfoList: <BalanceInfoListItem>[
      BalanceInfoListItem(token: kZnnCoin, balance: available),
      BalanceInfoListItem(token: kQsrCoin, balance: BigInt.zero),
    ],
  );
}

Widget swapHost(
  Widget child, {
  GlobalKey<NavigatorState>? navigator,
  bool light = false,
  bool rtl = false,
  double scale = 1,
  bool enabled = true,
  Size size = const Size(1280, 780),
}) => MaterialApp(
  navigatorKey: navigator,
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: TickerMode(
    enabled: enabled,
    child: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  ),
);

void prepareSwapViewport(
  WidgetTester tester, {
  Size size = const Size(1280, 780),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.reset();
  });
}

Future<void> swapFrames(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Widget fixtureDollars(BuildContext context, BigInt amount, Token token) =>
    const Text('Dollar fixture', key: Key('fixture_dollars'));

HtlcSwap fixtureRecord(
  SwapUiFixture fixture, {
  P2pSwapState state = P2pSwapState.active,
}) => HtlcSwap(
  id: fixtureHash(1),
  chainId: 321,
  type: P2pSwapType.native,
  direction: P2pSwapDirection.outgoing,
  selfAddress: fixture.owner,
  counterpartyAddress: fixture.counterparty,
  fromAmount: BigInt.from(10000000000),
  fromTokenStandard: kZnnCoin.tokenStandard.toString(),
  fromSymbol: kZnnCoin.symbol,
  fromDecimals: kZnnCoin.decimals,
  fromChain: P2pSwapChain.nom,
  toChain: P2pSwapChain.nom,
  startTime: 100,
  state: state,
  hashLock: fixtureHash(9),
  hashType: htlcHashTypeSha3,
  initialHtlcId: fixtureHash(1),
  initialHtlcExpirationTime: 10000,
);

HtlcInfo fixtureDeposit(
  SwapUiFixture fixture, {
  bool own = true,
  int? expires,
  int? id,
  BigInt? amount,
}) => HtlcInfo(
  id: Hash.parse(fixtureHash(id ?? (own ? 1 : 2))),
  timeLocked: Address.parse(own ? fixture.owner : fixture.counterparty),
  hashLocked: Address.parse(own ? fixture.counterparty : fixture.owner),
  tokenStandard: own ? kZnnCoin.tokenStandard : kQsrCoin.tokenStandard,
  amount: amount ?? BigInt.from(own ? 10000000000 : 100000000000),
  expirationTime: expires ?? (own ? 10000 : 5000),
  hashType: htlcHashTypeSha3,
  keyMaxSize: 32,
  hashLock: <int>[...List<int>.filled(31, 0), 9],
);
