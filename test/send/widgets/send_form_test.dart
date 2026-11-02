import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_sync_status/node_sync_status.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/pair.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';

String _address(int n) => Address(
  'z',
  <int>[0, n ~/ 256, n % 256, ...List<int>.filled(17, 7)],
).toString();

final String _from = _address(100);
final String _otherFrom = _address(101);
final String _alice = _address(1);
final String _bob = _address(2);
final String _typed = _address(3);
final BigInt _available = BigInt.parse('120450000001');

class _Sender extends MockBloc<SendTransactionEvent, SendTransactionState>
    implements SendTransactionBloc {}

class _Sync extends MockCubit<NodeSyncStatusState>
    implements NodeSyncStatusCubit {}

class _SyncInfo extends Mock implements SyncInfo {}

class _Routes extends NavigatorObserver {
  final List<Route<dynamic>> popped = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
    super.didPop(route, previousRoute);
  }
}

class _Prices extends PriceFeed {
  _Prices()
    : super(
        request: (_) async => '{"zenon-2":{"usd":0.62},"quasar":{"usd":0.031}}',
      );

  bool get subscribed => hasListeners;
}

class _FailedContacts extends ContactsStore {
  @override
  bool get readFailed => true;
}

/// Supplies an existing store's finding without grinding checksum collisions.
/// The comparison algorithm itself is covered by contacts_store_test.dart.
class _ReviewContacts extends ContactsStore {
  bool review = false;
  String trusted = _alice;

  void changeTrusted(String address) {
    trusted = address;
    notifyListeners();
  }

  @override
  LookAlike? lookAlike(
    String to, {
    Iterable<String> ownAddresses = const <String>[],
  }) => review && to == _typed
      ? LookAlike(
          known: KnownAddress(
            trusted,
            KnownAddressKind.contact,
            contact: byAddress(trusted),
          ),
          differing: differingPositions(to, trusted),
        )
      : super.lookAlike(to, ownAddresses: ownAddresses);
}

NodeSyncStatusState _syncState({
  int behind = 0,
  SyncState remembered = SyncState.syncDone,
}) {
  final _SyncInfo info = _SyncInfo();
  when(() => info.state).thenReturn(
    behind == 0 ? SyncState.syncDone : SyncState.unknown,
  );
  when(() => info.currentHeight).thenReturn(100);
  when(() => info.targetHeight).thenReturn(100 + behind);
  return NodeSyncStatusState(
    status: TimerStatus.success,
    data: Pair<SyncState, SyncInfo>(remembered, info),
  );
}

AccountInfo _balance(String address) => AccountInfo(
  address: address,
  blockCount: 1,
  balanceInfoList: <BalanceInfoListItem>[
    BalanceInfoListItem(token: kZnnCoin, balance: _available),
    BalanceInfoListItem(token: kQsrCoin, balance: BigInt.from(99900000000)),
  ],
);

void main() {
  initHydratedStorage();
  late _Sender sender;
  late _Sync sync;
  late SendDraftCubit draft;
  late _ReviewContacts contacts;
  late _Prices prices;
  late _Routes routes;
  late ValueNotifier<bool> busy;
  late ValueNotifier<bool> visible;
  late StreamController<SendTransactionState> senderStates;
  late StreamController<NodeSyncStatusState> syncStates;
  late String? previousAddress;
  late List<String?> previousAddresses;
  late Map<String, String> previousLabels;
  late SharedPrefsService? previousPreferences;

  setUpAll(() {
    registerFallbackValue(
      SendTransactionInitiate(
        fromAddress: _from,
        toAddress: _alice,
        amount: BigInt.one,
        token: kZnnCoin,
      ),
    );
  });

  setUp(() async {
    previousAddress = kSelectedAddress;
    previousAddresses = kDefaultAddressList;
    previousLabels = kAddressLabelMap;
    previousPreferences = app.sharedPrefsService;
    app.sharedPrefsService = null;
    kSelectedAddress = _from;
    kDefaultAddressList = <String?>[_from, _otherFrom];
    kAddressLabelMap = <String, String>{
      _from: 'Address 1',
      _otherFrom: 'Address 2',
    };
    BalanceVisibility.debugReset();
    contacts = _ReviewContacts();
    await contacts.add(name: 'Alice', address: _alice);
    await contacts.add(name: 'Bob', address: _bob);
    prices = _Prices();
    routes = _Routes();
    busy = ValueNotifier<bool>(false);
    visible = ValueNotifier<bool>(true);
    draft = SendDraftCubit();
    sender = _Sender();
    sync = _Sync();
    senderStates = StreamController<SendTransactionState>.broadcast(sync: true);
    syncStates = StreamController<NodeSyncStatusState>.broadcast(sync: true);
    when(() => sender.busy).thenReturn(busy);
    whenListen(
      sender,
      senderStates.stream,
      initialState: const SendTransactionState(),
    );
    whenListen(sync, syncStates.stream, initialState: _syncState());
  });

  tearDown(() async {
    await senderStates.close();
    await syncStates.close();
    await draft.close();
    prices.dispose();
    contacts.dispose();
    busy.dispose();
    visible.dispose();
    app.sharedPrefsService = previousPreferences;
    kSelectedAddress = previousAddress;
    kDefaultAddressList = previousAddresses;
    kAddressLabelMap = previousLabels;
    BalanceVisibility.debugReset();
  });

  Widget host({
    ThemeData? theme,
    bool light = false,
    bool rtl = false,
    ContactsStore? book,
    double scale = 1,
  }) => MaterialApp(
    theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    navigatorObservers: <NavigatorObserver>[routes],
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<SendTransactionBloc>.value(value: sender),
        BlocProvider<SendDraftCubit>.value(value: draft),
      ],
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, bool active, _) => TickerMode(
                    enabled: active,
                    child: SendPopulated(
                      balances: <String, AccountInfo>{
                        _from: _balance(_from),
                        _otherFrom: _balance(_otherFrom),
                      },
                      showSender: false,
                      contacts: book ?? contacts,
                      priceFeed: prices,
                      syncCubit: sync,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> show(
    WidgetTester tester, {
    ThemeData? theme,
    bool light = false,
    bool rtl = false,
    ContactsStore? book,
  }) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(theme: theme, light: light, rtl: rtl, book: book),
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> fill(
    WidgetTester tester, {
    String? recipient,
    String amount = '12.5',
  }) async {
    await tester.enterText(
      find.byKey(const Key('send_recipient_field')),
      recipient ?? _alice,
    );
    await tester.enterText(find.byKey(const Key('send_amount_field')), amount);
    await tester.pump();
    // A mounted estimate receives its price asynchronously. Render the frame
    // scheduled by that answer before inspecting the displayed value.
    await tester.pump();
  }

  OutlinedButton action(WidgetTester tester) => tester.widget<OutlinedButton>(
    find.descendant(
      of: find.byKey(const Key('send_submit_button')),
      matching: find.byType(OutlinedButton),
    ),
  );

  String amount(WidgetTester tester) => tester
      .widget<TextField>(
        find.byKey(const Key('send_amount_field')),
      )
      .controller!
      .text;

  String recipient(WidgetTester tester) => tester
      .widget<TextField>(
        find.byKey(const Key('send_recipient_field')),
      )
      .controller!
      .text;

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'form uses full action and exact amounts, light $light',
      (WidgetTester tester) async {
        await show(tester, light: light);
        await fill(tester, amount: '12.50000001');
        expect(find.text('Send 12.50000001 ZNN'), findsOneWidget);
        expect(prices.priceOf(PricedCoin.znn), isNotNull);
        expect(find.text(r'≈ $7.75'), findsOneWidget);
        expect(action(tester).onPressed, isNotNull);
        expect(
          tester.getSize(find.byKey(const Key('send_submit_button'))).width,
          600,
        );
        expect(
          tester.getSize(find.byKey(const Key('send_submit_button'))).height,
          46,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('send_amount_field')))
              .textDirection,
          TextDirection.ltr,
        );
        expect(draft.state.amount, '12.50000001');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'one action names the first missing requirement',
    (WidgetTester tester) async {
      await show(tester);
      expect(find.text('Enter an address'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('send_recipient_field')),
        _alice,
      );
      await tester.pump();
      expect(find.text('Enter an amount'), findsOneWidget);
      await fill(tester, amount: '1205');
      expect(find.text('Not enough ZNN'), findsOneWidget);
      expect(action(tester).onPressed, isNull);
      await fill(tester, amount: '1.123456789');
      expect(action(tester).onPressed, isNull);
      tester
          .widget<TextField>(find.byKey(const Key('send_amount_field')))
          .onSubmitted!('1.123456789');
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      verifyNever(() => sender.add(any()));
    },
  );

  testWidgets(
    'Max replaces an invalid amount with the exact available units',
    (WidgetTester tester) async {
      await show(tester);
      await fill(tester, amount: '1.123456789');
      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(amount(tester), '1204.50000001');
      expect(draft.state.amount, '1204.50000001');
      expect(action(tester).onPressed, isNotNull);
    },
  );

  group('recent recipients', () {
    // Prepare the original store lane outside the widget's fake clock, like
    // the contacts above. Its previous completion belongs to the setup zone.
    setUp(() async {
      await contacts.noteSent(_from, _alice);
      await contacts.noteSent(_otherFrom, _bob);
      expect(contacts.hasPendingWrite, isFalse);
      expect(contacts.recent(_from).single.address, _alice);
      expect(contacts.recent(_otherFrom).single.address, _bob);
    });

    for (final bool light in <bool>[false, true]) {
      testWidgets(
        'Recent keeps 26 px and busy guards in compact density, $light',
        (WidgetTester tester) async {
          final ThemeData theme =
              (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
                visualDensity: VisualDensity.compact,
              );
          final Finder chip = find.byKey(
            ValueKey<String>('send_recent_$_alice'),
          );
          await show(tester, theme: theme);
          await fill(tester, recipient: _typed, amount: '7.00000001');
          expect(
            Theme.of(tester.element(chip)).visualDensity,
            VisualDensity.compact,
          );
          expect(tester.getSize(chip).height, 26);
          final VoidCallback retained = tester
              .widget<OutlinedButton>(chip)
              .onPressed!;

          busy.value = true;
          await tester.pump();
          expect(tester.getSize(chip).height, 26);
          expect(tester.widget<OutlinedButton>(chip).onPressed, isNull);
          retained();
          await tester.tap(chip, warnIfMissed: false);
          await tester.pump();
          expect(recipient(tester), _typed);
          expect(draft.state.recipient, _typed);
          expect(amount(tester), '7.00000001');

          busy.value = false;
          await tester.pump();
          await tester.tap(chip);
          await tester.pump();
          expect(recipient(tester), _alice);
          expect(draft.state.recipient, _alice);
          expect(amount(tester), '7.00000001');

          await tester.pumpWidget(host(theme: theme, scale: 1.75));
          await tester.pump();
          final Rect bounds = tester.getRect(chip);
          final Rect label = tester.getRect(
            find.descendant(of: chip, matching: find.text('Alice')),
          );
          expect(bounds.height, greaterThan(26));
          expect(label.top, greaterThanOrEqualTo(bounds.top));
          expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
          busy.value = true;
          await tester.pump();
          expect(tester.getSize(chip).height, greaterThan(26));
          expect(tester.widget<OutlinedButton>(chip).onPressed, isNull);
          expect(draft.state.recipient, _alice);
          expect(amount(tester), '7.00000001');
          verifyNever(() => sender.add(any()));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'recent chips are scoped to sender and preserve the amount',
      (WidgetTester tester) async {
        await show(tester);
        await fill(tester, recipient: _typed, amount: '7.00000001');
        expect(
          find.byKey(ValueKey<String>('send_recent_$_alice')),
          findsOneWidget,
        );
        expect(find.byKey(ValueKey<String>('send_recent_$_bob')), findsNothing);
        await tester.tap(find.byKey(ValueKey<String>('send_recent_$_alice')));
        await tester.pump();
        expect(recipient(tester), _alice);
        expect(amount(tester), '7.00000001');
        expect(find.byKey(const Key('send_last_sent')), findsOneWidget);
        expect(draft.state.recipient, _alice);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  testWidgets(
    'book search selects the complete address without submitting',
    (WidgetTester tester) async {
      await show(tester);
      await fill(tester, amount: '0.00000001');
      await tester.tap(find.byKey(const Key('send_address_book')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('send_contacts_search')),
        'Bob',
      );
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>('send_contact_$_alice')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey<String>('send_contact_$_bob')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(recipient(tester), _bob);
      expect(amount(tester), '0.00000001');
      verifyNever(() => sender.add(any()));
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool closeFirst in <bool>[false, true]) {
    testWidgets(
      'picker decides once before a frame, close first $closeFirst',
      (WidgetTester tester) async {
        await show(tester);
        await fill(tester, amount: '0.00000001');
        await tester.tap(find.byKey(const Key('send_address_book')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final VoidCallback select = tester
            .widget<ListTile>(
              find.byKey(ValueKey<String>('send_contact_$_bob')),
            )
            .onTap!;
        final VoidCallback close = tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Close'),
            )
            .onPressed!;
        if (closeFirst) {
          close();
          select();
          close();
        } else {
          select();
          select();
          close();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(routes.popped, hasLength(1));
        expect(find.byType(SendPopulated), findsOneWidget);
        expect(recipient(tester), closeFirst ? _alice : _bob);
        expect(amount(tester), '0.00000001');
        expect(tester.takeException(), isNull);
        verifyNever(() => sender.add(any()));
      },
    );
  }

  testWidgets('an arriving warning keeps the active amount editor', (
    WidgetTester tester,
  ) async {
    await show(tester);
    await fill(tester, recipient: _typed);
    final Finder field = find.byKey(const Key('send_amount_field'));
    final Element original = tester.element(field);
    final FocusNode focus = tester.widget<TextField>(field).focusNode!;
    expect(focus.hasFocus, isTrue);
    expect(find.byKey(const Key('send_recipient_warning')), findsNothing);
    contacts
      ..review = true
      ..changeTrusted(_alice);
    await tester.pump();
    expect(find.byKey(const Key('send_recipient_warning')), findsOneWidget);
    expect(tester.element(field), same(original));
    expect(focus.hasFocus, isTrue);
    expect(amount(tester), '12.5');
    expect(draft.state.amount, '12.5');
  });

  testWidgets(
    'look-alike acknowledgement is bound to the exact address pair',
    (WidgetTester tester) async {
      contacts.review = true;
      await show(tester);
      await fill(tester, recipient: _typed);
      expect(recipient(tester), _typed);
      expect(amount(tester), '12.5');
      expect(draft.state.recipient, _typed);
      expect(draft.state.amount, '12.5');
      expect(find.byKey(const Key('send_recipient_warning')), findsOneWidget);
      expect(find.text('Looks like Alice'), findsOneWidget);
      expect(action(tester).onPressed, isNull);
      expect(find.byKey(const Key('send_known_address')), findsOneWidget);
      expect(find.byKey(const Key('send_typed_address')), findsOneWidget);
      final SelectableText typedAddress = tester.widget<SelectableText>(
        find.byKey(const Key('send_typed_address')),
      );
      expect(typedAddress.textSpan!.toPlainText(), _typed);
      final List<int> differing = differingPositions(_typed, _alice);
      final List<InlineSpan> spans = typedAddress.textSpan!.children!;
      for (int index = 0; index < spans.length; index++) {
        expect(
          (spans[index] as TextSpan).style?.color != null,
          differing.contains(index),
        );
      }
      final VoidCallback stale = tester
          .widget<TextButton>(find.byKey(const Key('send_use_typed')))
          .onPressed!;
      await tester.ensureVisible(find.byKey(const Key('send_use_typed')));
      await tester.pump();
      expect(
        find.byKey(const Key('send_use_typed')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('send_use_typed')));
      await tester.pump();
      expect(recipient(tester), _typed);
      expect(amount(tester), '12.5');
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('send_use_typed')))
            .onPressed,
        isNull,
        reason: 'Acknowledgement disables the choice for this exact pair',
      );
      expect(action(tester).onPressed, isNotNull);
      await fill(tester, recipient: _bob);
      stale();
      await tester.pump();
      await fill(tester, recipient: _typed);
      expect(action(tester).onPressed, isNull);
      await tester.tap(find.byKey(const Key('send_use_typed')));
      await tester.pump();
      contacts.changeTrusted(_bob);
      await tester.pump();
      expect(action(tester).onPressed, isNull);
      await tester.tap(find.byKey(const Key('send_use_known')));
      await tester.pump();
      expect(recipient(tester), _bob);
      expect(amount(tester), '12.5');
      expect(find.byKey(const Key('send_recipient_warning')), findsNothing);
      verifyNever(() => sender.add(any()));
    },
  );

  testWidgets(
    'current sync data holds pointer, Enter and retained callbacks',
    (WidgetTester tester) async {
      await show(tester);
      await fill(tester);
      final VoidCallback retained = action(tester).onPressed!;
      syncStates.add(_syncState(behind: 42));
      await tester.pump();
      expect(find.byKey(const Key('send_node_behind')), findsOneWidget);
      expect(find.text('Waiting for the node'), findsOneWidget);
      expect(action(tester).onPressed, isNull);
      retained();
      tester
          .widget<TextField>(find.byKey(const Key('send_amount_field')))
          .onSubmitted!('12.5');
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      verifyNever(() => sender.add(any()));
      syncStates.add(_syncState(behind: 2));
      await tester.pump();
      expect(action(tester).onPressed, isNotNull);
      syncStates.add(_syncState(behind: 3));
      await tester.pump();
      expect(action(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'busy holds edits and defers external draft selection until idle',
    (WidgetTester tester) async {
      await show(tester);
      await fill(tester, amount: '8.00000001');
      final VoidCallback retained = action(tester).onPressed!;
      busy.value = true;
      draft.save(
        fromAddress: _otherFrom,
        tokenStandard: kQsrCoin.tokenStandard.toString(),
        recipient: _bob,
        amount: '2.00000001',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('send_recipient_field')))
            .enabled,
        isFalse,
      );
      expect(recipient(tester), _alice);
      expect(amount(tester), '8.00000001');
      retained();
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      busy.value = false;
      await tester.pump();
      expect(recipient(tester), _bob);
      expect(amount(tester), '2.00000001');
      expect(find.text('Send 2.00000001 QSR'), findsOneWidget);
      verifyNever(() => sender.add(any()));
    },
  );

  testWidgets(
    'contract and collection outcomes preserve the transfer draft',
    (WidgetTester tester) async {
      await show(tester);
      await fill(tester);
      for (final SendTransactionOrigin origin in <SendTransactionOrigin>[
        SendTransactionOrigin.contract,
        SendTransactionOrigin.collection,
      ]) {
        senderStates.add(
          SendTransactionState(
            status: SendTransactionStatus.success,
            origin: origin,
            data: AccountBlockTemplate(blockType: 1),
          ),
        );
        await tester.pump();
        expect(recipient(tester), _alice);
        expect(amount(tester), '12.5');
        expect(draft.state.amount, '12.5');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden mode releases its price feed and keeps the typed form',
    (WidgetTester tester) async {
      await show(tester);
      await fill(tester);
      expect(prices.subscribed, isTrue);
      visible.value = false;
      await tester.pump();
      expect(prices.subscribed, isFalse);
      visible.value = true;
      await tester.pump();
      expect(prices.subscribed, isTrue);
      expect(recipient(tester), _alice);
      expect(amount(tester), '12.5');
    },
  );

  testWidgets(
    'failed book reads show caution and keep ordinary Send available',
    (WidgetTester tester) async {
      final _FailedContacts failed = _FailedContacts();
      addTearDown(failed.dispose);
      await show(tester, book: failed);
      await fill(tester);
      expect(
        find.byKey(const Key('send_contacts_unavailable')),
        findsOneWidget,
      );
      expect(action(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('send_address_book')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('send_contacts_read_failed')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('send_contacts_empty')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RTL pins financial inputs and exposes icon tooltips',
    (WidgetTester tester) async {
      await show(tester, rtl: true);
      await fill(tester);
      for (final String key in <String>[
        'send_recipient_field',
        'send_amount_field',
      ]) {
        expect(
          tester.widget<TextField>(find.byKey(Key(key))).textDirection,
          TextDirection.ltr,
        );
      }
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send_address_book')))
            .tooltip,
        'Address book',
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send_clear_recipient')))
            .tooltip,
        'Clear recipient',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
