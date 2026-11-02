import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/view/home_side_cards.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const String _prices = '{"zenon-2":{"usd":0.62},"quasar":{"usd":0.031}}';
const Key _toggle = ValueKey<String>('home_tokens_toggle');
const Key _body = Key('home_tokens_body');
const Key _collect = Key('home_collect_all');
final Hash _hash = Hash.parse('ab' * 32);
final Hash _otherHash = Hash.parse('cd' * 32);

class _Token extends Mock implements Token {}

class _Prices {
  int requests = 0;
  String answer = _prices;
  DateTime now = DateTime.utc(2040);

  Future<String> request(Uri uri) async {
    expect(uri, PriceFeed.url);
    requests++;
    return answer;
  }
}

class _ObservedFeed extends PriceFeed {
  _ObservedFeed(_Prices source)
    : super(request: source.request, now: () => source.now);

  bool get subscribed => hasListeners;
}

UncollectedReward _reward(String znn, String qsr) =>
    UncollectedReward.fromJson(<String, dynamic>{
      'address': emptyAddress.toString(),
      'znnAmount': znn,
      'qsrAmount': qsr,
    });

BalanceInfoListItem _token({
  String symbol = 'PP',
  int decimals = 0,
  BigInt? balance,
  bool missingBalance = false,
  TokenStandard? standard,
}) {
  final _Token token = _Token();
  when(() => token.symbol).thenReturn(symbol);
  when(() => token.decimals).thenReturn(decimals);
  when(() => token.tokenStandard).thenReturn(standard ?? znnZts);
  return BalanceInfoListItem(
    token: token,
    balance: missingBalance ? null : balance ?? BigInt.from(40),
  );
}

HomeSnapshot _snapshot({
  List<BalanceInfoListItem>? tokens,
  Map<String, UncollectedReward>? rewards,
}) => HomeSnapshot(
  znn: BigInt.zero,
  qsr: BigInt.zero,
  tokens: tokens ?? <BalanceInfoListItem>[_token()],
  currentPlasma: 0,
  maxPlasma: 0,
  fusedQsr: BigInt.zero,
  rewards:
      rewards ??
      <String, UncollectedReward>{
        'Delegation': _reward('300000000', '0'),
        'Sentinel': _reward('21400000', '840000000'),
        'Staking': _reward('0', '1000000000'),
      },
);

InFlightBlock _block({
  Hash? hash,
  BigInt? amount,
  int? decimals = 8,
  String? symbol = 'ZNN',
}) => InFlightBlock(
  hash: hash ?? _hash,
  amount: amount ?? BigInt.from(1250000000),
  decimals: decimals,
  symbol: symbol,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Prices source;
  late _ObservedFeed feed;
  late BalanceVisibility visibility;
  late ValueNotifier<List<InFlightBlock>> flight;
  late SharedPrefsService? previousPreferences;
  late int collections;

  setUp(() {
    previousPreferences = app.sharedPrefsService;
    app.sharedPrefsService = null;
    source = _Prices();
    feed = _ObservedFeed(source);
    visibility = BalanceVisibility();
    flight = ValueNotifier<List<InFlightBlock>>(const <InFlightBlock>[]);
    collections = 0;
  });

  tearDown(() {
    feed.dispose();
    visibility.dispose();
    flight.dispose();
    app.sharedPrefsService = previousPreferences;
  });

  Widget host({
    ThemeData? theme,
    HomeSnapshot? snapshot,
    bool noSnapshot = false,
    bool failed = false,
    bool enabled = true,
    bool busy = false,
    String? notice,
    VoidCallback? onCollect,
    bool noCallback = false,
    ValueListenable<List<InFlightBlock>>? blocks,
    bool light = false,
    bool rtl = false,
    bool reduced = false,
    double textScale = 1,
    double width = 500,
    Key? cardsKey,
  }) => MaterialApp(
    theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: appLocalizationsDelegates,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: width,
            height: 540,
            child: HomeSideCards(
              key: cardsKey,
              snapshot: noSnapshot ? null : snapshot ?? _snapshot(),
              failed: failed,
              collectEnabled: enabled,
              collectBusy: busy,
              collectionNotice: notice,
              onCollectAll: noCallback
                  ? null
                  : onCollect ?? () => collections++,
              flight: blocks ?? flight,
              visibility: visibility,
              priceFeed: feed,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    ThemeData? theme,
    HomeSnapshot? snapshot,
    bool noSnapshot = false,
    bool failed = false,
    bool enabled = true,
    bool busy = false,
    String? notice,
    bool noCallback = false,
    ValueListenable<List<InFlightBlock>>? blocks,
    bool light = false,
    bool rtl = false,
    bool reduced = false,
    double textScale = 1,
    double width = 500,
    Key? cardsKey,
  }) async {
    await tester.pumpWidget(
      host(
        theme: theme,
        snapshot: snapshot,
        noSnapshot: noSnapshot,
        failed: failed,
        enabled: enabled,
        busy: busy,
        notice: notice,
        noCallback: noCallback,
        blocks: blocks,
        light: light,
        rtl: rtl,
        reduced: reduced,
        textScale: textScale,
        width: width,
        cardsKey: cardsKey,
      ),
    );
    await tester.pump();
  }

  Future<void> openTokens(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_toggle));
    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'Collect all keeps 30 px and its busy guard in compact density, $light',
      (WidgetTester tester) async {
        final ThemeData theme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
              visualDensity: VisualDensity.compact,
            );
        final Finder button = find.byKey(_collect);
        await show(tester, theme: theme);
        expect(
          Theme.of(tester.element(button)).visualDensity,
          VisualDensity.compact,
        );
        expect(tester.getSize(button).height, 30);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        expect(collections, 1);

        await show(tester, theme: theme, busy: true);
        expect(tester.getSize(button).height, 30);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        expect(
          find.descendant(
            of: button,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        await tester.tap(button);
        expect(collections, 1);

        await show(tester, theme: theme, enabled: false);
        expect(tester.getSize(button).height, 30);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        await tester.tap(button);
        expect(collections, 1);

        await show(tester, theme: theme, textScale: 1.75);
        expect(tester.getSize(button).height, greaterThan(30));
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        expect(collections, 2);
        expect(flight.value, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('adds exact rewards and shared dollars on one compact line', (
    WidgetTester tester,
  ) async {
    await show(tester);
    expect(find.text('3.214', findRichText: true), findsOneWidget);
    expect(find.text('18.4', findRichText: true), findsOneWidget);
    expect(find.text(r'≈ $2.56'), findsOneWidget);
    expect(find.textContaining('3.2140', findRichText: true), findsNothing);
    expect(source.requests, 1);
    final Rect title = tester.getRect(find.text('To collect'));
    final Rect amount = tester.getRect(
      find.byKey(const Key('home_collect_znn')),
    );
    final Rect action = tester.getRect(find.byKey(_collect));
    expect((title.center.dy - amount.center.dy).abs(), lessThan(2));
    expect((action.center.dy - amount.center.dy).abs(), lessThan(2));
    expect(
      tester.getSize(find.byKey(const Key('home_collect_card'))).height,
      lessThan(60),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and failed first reads never show zero rewards', (
    WidgetTester tester,
  ) async {
    await show(tester, noSnapshot: true);
    expect(find.text('Loading'), findsOneWidget);
    expect(find.byType(AmountText), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
      isNull,
    );
    await show(tester, noSnapshot: true, failed: true);
    expect(find.text('Node not answering'), findsOneWidget);
    expect(find.text('None yet'), findsNothing);
    expect(source.requests, 0);
  });

  testWidgets('a failed refresh retains real figures and holds collection', (
    WidgetTester tester,
  ) async {
    await show(tester, failed: true);
    expect(find.text('3.214', findRichText: true), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_collect));
    expect(collections, 0);
  });

  testWidgets(
    'known empty rewards are one line and do not subscribe to prices',
    (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        snapshot: _snapshot(
          rewards: <String, UncollectedReward>{
            'Delegation': _reward('0', '0'),
          },
        ),
      );
      expect(find.text('None yet'), findsOneWidget);
      expect(find.byType(AmountText), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
        isNull,
      );
      expect(source.requests, 0);
      expect(feed.subscribed, isFalse);
      expect(find.byKey(const Key('home_tokens_body')), findsNothing);
    },
  );

  testWidgets('the callback is the only collection action', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(_collect));
    await tester.pump();
    expect(collections, 1);
    expect(flight.value, isEmpty);
    expect(find.text('3.214', findRichText: true), findsOneWidget);
    expect(find.text('Collected'), findsNothing);
    expect(find.byKey(const Key('home_pending_card')), findsNothing);
  });

  testWidgets(
    'shared admission, busy and absent callbacks disable Collect all',
    (
      WidgetTester tester,
    ) async {
      await show(tester, enabled: false);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
        isNull,
      );
      await show(tester, busy: true);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(_collect));
      await show(tester, noCallback: true);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
        isNull,
      );
      expect(collections, 0);
    },
  );

  testWidgets('an unresolved notice has no dismiss or retry action', (
    WidgetTester tester,
  ) async {
    await show(tester, notice: 'Collection outcome unknown');
    expect(find.text('Collection outcome unknown'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
      isNull,
    );
    expect(find.byType(OutlinedButton), findsOneWidget);
    final Rect notice = tester.getRect(
      find.byKey(const Key('home_collection_notice')),
    );
    expect(
      notice.top,
      greaterThan(tester.getRect(find.byKey(_collect)).bottom),
    );
    await show(
      tester,
      notice: 'Collection outcome unknown',
      snapshot: _snapshot(
        rewards: <String, UncollectedReward>{
          'Delegation': _reward('700000000', '0'),
        },
      ),
    );
    expect(find.text('Collection outcome unknown'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'hidden rewards, dollars, tokens and Pending leave no amounts in semantics',
    (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        flight.value = <InFlightBlock>[_block()];
        await show(tester);
        await openTokens(tester);
        final double shown = tester
            .getSize(
              find.byKey(const Key('home_collect_znn')),
            )
            .width;
        visibility.set(true);
        await tester.pump();
        expect(
          tester
              .getSize(
                find.byKey(const Key('home_collect_znn')),
              )
              .width,
          lessThan(shown),
        );
        expect(find.text(r'≈ $2.56'), findsNothing);
        expect(find.text('≈ ••••'), findsOneWidget);
        expect(find.text('ZNN'), findsNWidgets(2));
        expect(find.text('QSR'), findsOneWidget);
        expect(
          find.semantics.byLabel(
            RegExp(r'3\.214|18\.4|2\.56|12\.5|\b40\b'),
          ),
          findsNothing,
        );
        expect(find.byTooltip(_hash.toString()), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('dollar preference and incomplete prices remove estimates', (
    WidgetTester tester,
  ) async {
    source.answer = '{"zenon-2":{"usd":0.62}}';
    await show(tester);
    expect(find.byType(DollarText), findsNothing);
    expect(find.text('3.214', findRichText: true), findsOneWidget);
    feed.enabled = false;
    await tester.pump();
    expect(find.byType(DollarText), findsNothing);
    source.answer = _prices;
    source.now = source.now.add(PriceFeed.interval);
    feed.enabled = true;
    await tester.pump();
    await tester.pump();
    expect(find.text(r'≈ $2.56'), findsOneWidget);
    feed.enabled = false;
    await tester.pump();
    expect(find.byType(DollarText), findsNothing);
  });

  testWidgets('a single reward coin needs only its own real price', (
    WidgetTester tester,
  ) async {
    source.answer = '{"zenon-2":{"usd":0.62}}';
    await show(
      tester,
      snapshot: _snapshot(
        rewards: <String, UncollectedReward>{
          'Delegation': _reward('100000000', '0'),
        },
      ),
    );
    expect(
      tester
          .widget<AmountText>(
            find.descendant(
              of: find.byKey(const Key('home_collect_znn')),
              matching: find.byType(AmountText),
            ),
          )
          .raw,
      BigInt.from(100000000),
    );
    expect(find.text('QSR'), findsNothing);
    expect(find.text(r'≈ $0.6200'), findsOneWidget);
  });

  testWidgets('Tokens starts closed and retains its own state across reads', (
    WidgetTester tester,
  ) async {
    await show(tester);
    expect(find.byKey(_body, skipOffstage: false), findsNothing);
    await openTokens(tester);
    expect(find.text('PP'), findsOneWidget);
    expect(find.text('40', findRichText: true), findsOneWidget);
    await show(
      tester,
      snapshot: _snapshot(
        tokens: <BalanceInfoListItem>[
          _token(balance: BigInt.from(41)),
        ],
      ),
    );
    expect(find.byKey(_body), findsOneWidget);
    expect(find.text('41', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240, microseconds: 1));
    expect(find.byKey(_body, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard opens Tokens and closing removes row semantics immediately',
    (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await show(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        expect(find.byKey(_body), findsOneWidget);
        expect(find.semantics.byLabel(RegExp('PP')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(find.semantics.byLabel(RegExp('PP')), findsNothing);
        await tester.pump(const Duration(milliseconds: 240, microseconds: 1));
        expect(find.byKey(_body, skipOffstage: false), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('a new view starts Tokens closed after the prior owner leaves', (
    WidgetTester tester,
  ) async {
    await show(tester, cardsKey: const Key('first_scope'));
    await openTokens(tester);
    expect(find.byKey(_body), findsOneWidget);
    await show(tester, cardsKey: const Key('second_scope'));
    expect(find.byKey(_body, skipOffstage: false), findsNothing);
  });

  testWidgets('token rows use their original precision and have no prices', (
    WidgetTester tester,
  ) async {
    await show(
      tester,
      snapshot: _snapshot(
        tokens: <BalanceInfoListItem>[
          _token(balance: BigInt.from(40)),
          _token(
            symbol: 'WBTC',
            decimals: 8,
            balance: BigInt.from(210000),
            standard: qsrZts,
          ),
        ],
      ),
    );
    await openTokens(tester);
    expect(find.text('40', findRichText: true), findsOneWidget);
    expect(find.text('0.0021', findRichText: true), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_body), matching: find.byType(DollarText)),
      findsNothing,
    );
    expect(find.byTooltip(qsrZts.toString()), findsOneWidget);
    final AmountText amount = tester.widget<AmountText>(
      find
          .descendant(
            of: find.byKey(_body),
            matching: find.byType(AmountText),
          )
          .last,
    );
    expect(amount.raw, BigInt.from(210000));
    expect(amount.decimals, 8);
  });

  testWidgets(
    'missing metadata, balances and invalid precision remain unknown',
    (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        snapshot: _snapshot(
          tokens: <BalanceInfoListItem>[
            _token(missingBalance: true),
            _token(symbol: 'WBTC', decimals: 256, standard: qsrZts),
            BalanceInfoListItem(token: null, balance: BigInt.one),
          ],
        ),
      );
      await openTokens(tester);
      expect(find.text('Unknown'), findsNWidgets(3));
      expect(find.text('Unknown token standard'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_body),
          matching: find.byType(AmountText),
        ),
        findsNothing,
      );
      visibility.set(true);
      await tester.pump();
      expect(find.text('Unknown').hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'Pending appears and disappears only with injected exact hashes',
    (
      WidgetTester tester,
    ) async {
      await show(tester);
      expect(find.byKey(const Key('home_pending_card')), findsNothing);
      flight.value = <InFlightBlock>[_block()];
      await tester.pump();
      expect(find.byKey(const Key('home_pending_card')), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('home_pending_$_hash')),
        findsOneWidget,
      );
      expect(find.text('12.5', findRichText: true), findsOneWidget);
      expect(find.text('momentum'), findsOneWidget);
      flight.value = <InFlightBlock>[
        _block(hash: _otherHash, amount: BigInt.from(100000000)),
      ];
      await tester.pump();
      expect(find.byKey(ValueKey<String>('home_pending_$_hash')), findsNothing);
      expect(
        find.byKey(ValueKey<String>('home_pending_$_otherHash')),
        findsOneWidget,
      );
      flight.value = const <InFlightBlock>[];
      await tester.pump();
      expect(find.byKey(const Key('home_pending_card')), findsNothing);
    },
  );

  testWidgets(
    'unknown-unit publications retain hashes without invented amounts',
    (
      WidgetTester tester,
    ) async {
      flight.value = <InFlightBlock>[
        _block(amount: BigInt.zero),
        _block(hash: _otherHash, decimals: null, symbol: null),
        _block(hash: Hash.parse('ef' * 32), decimals: 256),
      ];
      await show(tester);
      expect(find.text('Waiting for a momentum'), findsNWidgets(3));
      expect(find.text('12.5', findRichText: true), findsNothing);
      expect(find.byTooltip(_hash.toString()), findsOneWidget);
      expect(find.byTooltip(_otherHash.toString()), findsOneWidget);
      expect(find.text('Collected'), findsNothing);
    },
  );

  testWidgets('Pending fills the remaining column and closes with its body', (
    WidgetTester tester,
  ) async {
    flight.value = <InFlightBlock>[_block()];
    await show(tester, reduced: true);
    final Finder card = find.byKey(const Key('home_pending_card'));
    final Rect open = tester.getRect(card);
    expect(open.bottom, closeTo(540, 1));
    expect(open.height, greaterThan(200));
    await tester.tap(find.byKey(const ValueKey<String>('home_pending_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final double moving = tester.getSize(card).height;
    expect(moving, lessThan(open.height));
    expect(moving, greaterThan(44));
    await tester.pump(const Duration(milliseconds: 120, microseconds: 1));
    expect(tester.getSize(card).height, 44);
    expect(
      find.byKey(ValueKey<String>('home_pending_$_hash'), skipOffstage: false),
      findsNothing,
    );
    expect(flight.value.single.hash, _hash);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the view neither polls confirmation nor settles publications by time',
    (
      WidgetTester tester,
    ) async {
      int lookups = 0;
      final InFlightBlocks blocks = InFlightBlocks(
        lookup: (_) async {
          lookups++;
          return true;
        },
      )..sent(hash: _hash, amount: BigInt.zero);
      try {
        await show(tester, blocks: blocks);
        await tester.pump(const Duration(minutes: 3));
        expect(lookups, 0);
        expect(blocks.value.single.hash, _hash);
        expect(
          find.byKey(ValueKey<String>('home_pending_$_hash')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      } finally {
        blocks.dispose();
      }
    },
  );

  testWidgets('replacing the registry detaches its earlier wallet view', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<InFlightBlock>> replacement =
        ValueNotifier<List<InFlightBlock>>(<InFlightBlock>[
          _block(hash: _otherHash),
        ]);
    try {
      flight.value = <InFlightBlock>[_block()];
      await show(tester);
      await show(
        tester,
        blocks: replacement,
        cardsKey: const Key('new_wallet'),
      );
      flight.value = const <InFlightBlock>[];
      await tester.pump();
      expect(find.byKey(ValueKey<String>('home_pending_$_hash')), findsNothing);
      expect(
        find.byKey(ValueKey<String>('home_pending_$_otherHash')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    } finally {
      replacement.dispose();
    }
  });

  testWidgets('leaving the view removes its shared price listener', (
    WidgetTester tester,
  ) async {
    await show(tester);
    expect(feed.subscribed, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(feed.subscribed, isFalse);
    final int requests = source.requests;
    source.now = source.now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(source.requests, requests);
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'large amounts remain reachable in ${light ? 'light' : 'dark'} RTL',
      (
        WidgetTester tester,
      ) async {
        final BigInt exact = BigInt.parse('123456789012345678901234567891');
        flight.value = <InFlightBlock>[_block(amount: exact)];
        await show(
          tester,
          light: light,
          rtl: true,
          textScale: 2,
          width: 380,
          snapshot: _snapshot(
            rewards: <String, UncollectedReward>{
              'Delegation': _reward(exact.toString(), '1'),
            },
            tokens: <BalanceInfoListItem>[_token(decimals: 8, balance: exact)],
          ),
        );
        await openTokens(tester);
        expect(tester.takeException(), isNull);
        final Iterable<AmountText> amounts = tester.widgetList<AmountText>(
          find.byType(AmountText),
        );
        expect(
          amounts.where((AmountText amount) => amount.raw == exact).length,
          3,
        );
        for (final Element element in find.byType(AmountText).evaluate()) {
          expect(Directionality.of(element), TextDirection.ltr);
        }
        expect(
          tester.widget<OutlinedButton>(find.byKey(_collect)).onPressed,
          isNotNull,
        );
        await tester.ensureVisible(find.byKey(_collect));
        await tester.tap(find.byKey(_collect));
        expect(collections, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Tokens disclosure keeps its reveal clock when OS motion is disabled',
    (
      WidgetTester tester,
    ) async {
      await show(tester, reduced: true);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final FadeTransition fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(_body),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, greaterThan(0));
      expect(fade.opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(_body), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
