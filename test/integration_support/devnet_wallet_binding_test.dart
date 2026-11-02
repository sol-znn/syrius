import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../integration_test/support/devnet_test_context.dart';
import '../helpers/hydrated_bloc.dart';

class _OfflineNode extends Mock implements Zenon {}

class _NoRpcClient extends Mock implements Client {}

class _NoKeyWallet extends Mock implements Wallet {}

class _AdmissionOnlyFile extends DevnetWalletFile {
  _AdmissionOnlyFile(super._wallet);

  int acquisitions = 0;
  int releases = 0;
  bool held = false;

  @override
  bool get isOpen => held;

  @override
  Future<Wallet> open() {
    acquisitions++;
    throw StateError('Offline admission must not acquire a signer');
  }

  @override
  Future<void> close() async {
    releases++;
  }
}

Map<String, Object?> _globals() => <String, Object?>{
  'file': kWalletFile,
  'path': kWalletPath,
  'addresses': kDefaultAddressList,
  'labels': kAddressLabelMap,
  'selected': kSelectedAddress,
  'node': kCurrentNode,
  'nodeChain': kNodeChainId,
  'sdkChain': getChainIdentifier(),
  'page': kCurrentPage,
  'initialized': kWalletInitCompleted,
};

void _expectGlobals(Map<String, Object?> expected) {
  final Map<String, Object?> actual = _globals();
  for (final String name in expected.keys) {
    expect(actual[name], same(expected[name]), reason: name);
  }
}

void main() {
  initHydratedStorage();
  const String sender = DevnetTestContext.testPillarOwnerAddress;
  const String recipient = 'z1qpeet8dcjg0m6x6m3tg437wnc42aa2nez2fzth';
  const List<String> addresses = <String>[sender, recipient];
  const String nodeUrl = 'ws://127.0.0.1:35998';
  late Zenon? previousClient;
  late Map<String, Object?> previousGlobals;
  late _OfflineNode node;
  late _NoRpcClient transport;
  late _NoKeyWallet wallet;
  late _AdmissionOnlyFile file;
  late DevnetWalletBinding binding;

  setUp(() {
    expect(NodeTransitions.pending, isFalse);
    previousClient = app.zenon;
    previousGlobals = _globals();
    node = _OfflineNode();
    transport = _NoRpcClient();
    wallet = _NoKeyWallet();
    file = _AdmissionOnlyFile(wallet);
    final StatsApi stats = StatsApi()..setClient(transport);
    when(() => node.stats).thenReturn(stats);
    app.zenon = node;
    binding = DevnetWalletBinding.install(
      walletFile: file,
      addresses: addresses,
      selectedAddress: sender,
      nodeUrl: nodeUrl,
      verifiedChainId: DevnetTestContext.chainId,
    );
  });

  tearDown(() {
    try {
      binding.restore();
      _expectGlobals(previousGlobals);
      expect(file.acquisitions, 0);
      expect(file.releases, 0);
      verifyZeroInteractions(wallet);
      verifyZeroInteractions(transport);
    } finally {
      app.zenon = previousClient;
    }
  });

  AccountBlockUtils capture() => AccountBlockUtils.capture(
    address: Address.parse(sender),
  );

  test('verified devnet binding passes actual production capture', () {
    expect(capture, returnsNormally);
    expect(kWalletPath, file.walletPath);
    expect(kCurrentNode, nodeUrl);
    expect(kNodeChainId, DevnetTestContext.chainId);
    expect(getChainIdentifier(), DevnetTestContext.chainId);
    expect(kCurrentPage, Tabs.dashboard);
    expect(file.isOpen, isFalse);
  });

  test('Transfer selection retains its owner and restores the page', () {
    final int revision = WalletContextRevision.value;
    binding.selectTransfer();
    expect(kCurrentPage, Tabs.transfer);
    expect(WalletContextRevision.value, revision + 1);
    expect(kWalletFile, same(file));
    expect(app.zenon, same(node));
    expect(capture, returnsNormally);
    binding.selectTransfer();
    expect(WalletContextRevision.value, revision + 1);
    binding.restore();
    _expectGlobals(previousGlobals);
  });

  test('Transfer selection refuses a changed node', () {
    kCurrentNode = 'ws://127.0.0.1:45998';
    final Tabs? page = kCurrentPage;
    final int revision = WalletContextRevision.value;
    expect(binding.selectTransfer, throwsStateError);
    expect(kCurrentPage, same(page));
    expect(WalletContextRevision.value, revision);
  });

  testWidgets('real Send admission needs the original Transfer page', (
    WidgetTester tester,
  ) async {
    final SendTransactionBloc senderBloc = SendTransactionBloc();
    final ContactsStore contacts = ContactsStore();
    final PriceFeed prices = PriceFeed(request: (_) async => '{}');
    BalanceVisibility.debugReset();
    tester.view
      ..physicalSize = const Size(1280, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<SendTransactionBloc>.value(
            value: senderBloc,
            child: Scaffold(
              body: SingleChildScrollView(
                child: SendPopulated(
                  balances: <String, AccountInfo>{
                    sender: AccountInfo(
                      address: sender,
                      blockCount: 1,
                      balanceInfoList: <BalanceInfoListItem>[
                        BalanceInfoListItem(
                          token: kZnnCoin,
                          balance: BigInt.from(100000000000),
                        ),
                      ],
                    ),
                  },
                  contacts: contacts,
                  priceFeed: prices,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('send_recipient_field')),
        recipient,
      );
      await tester.enterText(
        find.byKey(const Key('send_amount_field')),
        '0.001',
      );
      await tester.pumpAndSettle();
      final Finder submit = find.byKey(const Key('send_submit_button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send_confirmation_marker')), findsNothing);
      expect(senderBloc.busy.value, isFalse);
      expect(file.acquisitions, 0);

      binding.selectTransfer();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send_confirmation_marker')), findsOneWidget);
      expect(senderBloc.busy.value, isFalse);
      expect(file.acquisitions, 0);
      await tester.tap(find.byKey(const Key('send_confirmation_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send_confirmation_marker')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      bool closed = false;
      final Future<void> original = senderBloc.close().whenComplete(() {
        closed = true;
      });
      for (int turn = 0; turn < 20 && !closed; turn++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(closed, isTrue);
      await original;
      contacts.dispose();
      prices.dispose();
      BalanceVisibility.debugReset();
    }
  });

  test('integration initialization refuses an existing process SDK', () async {
    final Map<String, Object?> before = _globals();
    await expectLater(initializeDevnetIntegrationTests(), throwsStateError);
    await disposeDevnetIntegrationTests();
    expect(app.zenon, same(node));
    _expectGlobals(before);
    verifyZeroInteractions(node);
  });

  test('integration initialization refuses a registered foreign SDK', () async {
    final Map<String, Object?> before = _globals();
    app.zenon = null;
    app.sl.pushNewScope();
    app.sl.registerSingleton<Zenon>(node);
    try {
      await expectLater(initializeDevnetIntegrationTests(), throwsStateError);
      await disposeDevnetIntegrationTests();
      expect(app.zenon, isNull);
      expect(app.sl<Zenon>(), same(node));
      _expectGlobals(before);
      verifyZeroInteractions(node);
    } finally {
      await app.sl.popScope();
      app.zenon = node;
    }
  });

  for (final MapEntry<String, void Function()> missing
      in <String, void Function()>{
        'wallet path': () => kWalletPath = null,
        'verified node chain': () => kNodeChainId = null,
        'unlocked page': () => kCurrentPage = Tabs.lock,
      }.entries) {
    test('production capture refuses missing ${missing.key}', () {
      missing.value();
      expect(capture, throwsA(isA<FailureException>()));
    });
  }

  for (final MapEntry<String, void Function()> change
      in <String, void Function()>{
        'node URL': () => kCurrentNode = 'ws://127.0.0.1:45998',
        'node chain': () => kNodeChainId = 70,
        'SDK chain': () => setChainIdentifier(chainIdentifier: 70),
        'wallet path': () => kWalletPath = 'other-memory-wallet',
        'selected address': () => kSelectedAddress = recipient,
        'member order': () =>
            kDefaultAddressList = <String?>[recipient, sender],
        'lock': () => kCurrentPage = Tabs.lock,
        'context round trip': () {
          kSelectedAddress = recipient;
          WalletContextRevision.invalidate();
          kSelectedAddress = sender;
          WalletContextRevision.invalidate();
        },
      }.entries) {
    test('captured devnet source refuses ${change.key} before RPC', () async {
      final AccountBlockUtils original = capture();
      change.value();
      await expectLater(
        original.createAccountBlock(
          AccountBlockTemplate(blockType: BlockTypeEnum.userSend.index),
          'Offline devnet admission',
          address: Address.parse(sender),
        ),
        throwsA(isA<FailureException>()),
      );
    });
  }

  test('chain 321 lab cannot install a Docker devnet binding', () {
    final Map<String, Object?> before = _globals();
    expect(
      () => DevnetWalletBinding.install(
        walletFile: file,
        addresses: addresses,
        selectedAddress: sender,
        nodeUrl: nodeUrl,
        verifiedChainId: 321,
      ),
      throwsStateError,
    );
    _expectGlobals(before);
  });

  test(
    'restoration preserves original collection and SDK chain identities',
    () {
      final int revision = WalletContextRevision.value;
      binding.restore();
      _expectGlobals(previousGlobals);
      expect(WalletContextRevision.value, revision + 1);
      binding.restore();
      expect(WalletContextRevision.value, revision + 1);
    },
  );

  test('restoration refuses a foreign wallet without closing either file', () {
    final _AdmissionOnlyFile foreign = _AdmissionOnlyFile(_NoKeyWallet());
    kWalletFile = foreign;
    try {
      expect(binding.restore, throwsStateError);
      expect(kWalletFile, same(foreign));
      expect(foreign.acquisitions, 0);
      expect(foreign.releases, 0);
    } finally {
      kWalletFile = file;
    }
  });

  test('restoration holds an acquired fixture instead of closing it', () {
    file.held = true;
    try {
      expect(binding.restore, throwsStateError);
      expect(kWalletFile, same(file));
      expect(file.releases, 0);
    } finally {
      file.held = false;
    }
  });
}
