import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Directory? _hiveDirectory;
DevnetWalletBinding? _walletBinding;
Zenon? _devnetClient;
WsClient? _devnetSocket;
String? _devnetSocketUrl;

class DevnetTestContext {
  static const int chainId = 69;
  static const int defaultSenderIndex = 3;
  static const int defaultRecipientIndex = 8;
  static const String defaultNodeUrl = 'ws://localhost:35998';
  static const String defaultPassword = 'devnet';
  static const String defaultMnemonic =
      'abstract affair idle position alien fluid board ordinary exist afraid '
      'chapter wood wood guide sun walnut crew perfect place firm poverty '
      'model side million';
  static const String testPillarOwnerAddress =
      'z1qp3yph55qgresyytz83anynr2f4z39x2z3ej3e';
  static const String testPillarName = 'testPillar';
  static const String testPillarRewardAddress =
      'z1qp3yph55qgresyytz83anynr2f4z39x2z3ej3e';
  static const String testPillarProducerAddress =
      'z1qzh6xyndzcuagylguxxlyp6s6kxz7lgh9zx093';
  static const int testPillarMomentumReward = 30;
  static const int testPillarDelegationReward = 55;
  static const String testPillarSetupQsrFuseAmount = '120';

  static const Map<int, String> fundedDevAddresses = <int, String>{
    1: 'z1qq6eg8n43g032hanpsfp02qcdmv7zfj3y2lt5d',
    3: 'z1qp3yph55qgresyytz83anynr2f4z39x2z3ej3e',
    8: 'z1qpeet8dcjg0m6x6m3tg437wnc42aa2nez2fzth',
    9: 'z1qqcam4ycu0ta8333hx38r5j2z3ry9jjfxkc7t5',
  };

  static String get defaultSenderAddress =>
      fundedDevAddresses[defaultSenderIndex]!;

  AccountBlockTemplate? sentBlock;
  AccountBlockTemplate? plasmaFuseBlock;
  AccountBlockTemplate? pillarQsrDepositBlock;
  AccountBlockTemplate? deployPillarBlock;
  AccountBlockTemplate? issueTokenBlock;
  AccountBlockTemplate? stakeBlock;
  BigInt? plasmaFuseAmount;
  BigInt? pillarQsrDepositAmount;
}

Future<void> initializeDevnetIntegrationTests() async {
  if (_walletBinding != null || _devnetClient != null) {
    throw StateError('The previous devnet wallet binding is still active');
  }
  if (app.zenon != null || app.sl.isRegistered<Zenon>()) {
    throw StateError('Devnet integration tests require an isolated SDK');
  }
  final Zenon client = Zenon();
  final WsClient socket = client.wsClient;
  if (!socket.isClosed() ||
      socket.status() == WebsocketStatus.connecting ||
      socket.status() == WebsocketStatus.running) {
    throw StateError('The SDK socket already has another owner');
  }
  _devnetClient = client;
  _devnetSocket = socket;
  _devnetSocketUrl = socket.url;
  app.zenon = client;
  await _initializeSharedPrefs();
  if (app.sl.isRegistered<DevnetTestContext>()) {
    await app.sl.unregister<DevnetTestContext>();
  }
  app.sl.registerSingleton<DevnetTestContext>(DevnetTestContext());

  final String nodeUrl = devnetEnv(
    'ZNN_TEST_NODE_URL',
    DevnetTestContext.defaultNodeUrl,
  );
  _devnetSocketUrl = nodeUrl;
  final bool connected = await socket
      .initialize(nodeUrl, retry: false)
      .timeout(const Duration(seconds: 15));

  expect(
    connected,
    isTrue,
    reason: 'Could not connect to devnet at $nodeUrl',
  );

  final String? connectedNodeUrl = socket.url;
  final LedgerApi ledger = client.ledger;
  final Client ledgerTransport = ledger.client;
  bool originalConnection() =>
      identical(app.zenon, client) &&
      identical(client.wsClient, socket) &&
      socket.status() == WebsocketStatus.running &&
      connectedNodeUrl == nodeUrl &&
      socket.url == connectedNodeUrl &&
      identical(client.ledger, ledger) &&
      identical(ledger.client, ledgerTransport) &&
      identical(ledgerTransport, socket) &&
      identical(client.stats.client, socket) &&
      !NodeTransitions.pending;
  expect(originalConnection(), isTrue);
  final Momentum momentum = await ledger.getFrontierMomentum();
  expect(originalConnection(), isTrue);
  expect(
    momentum.chainIdentifier,
    DevnetTestContext.chainId,
    reason:
        'Integration tests must run against docker devnet chain ID '
        '${DevnetTestContext.chainId}',
  );
  HydratedBloc.storage = InMemoryHydratedStorage();

  final KeyStore wallet = KeyStore.fromMnemonic(
    devnetEnv('ZNN_TEST_MNEMONIC', DevnetTestContext.defaultMnemonic),
  );
  await _configureWalletGlobals(
    wallet,
    nodeUrl: connectedNodeUrl!,
    verifiedChainId: momentum.chainIdentifier,
    originalConnection: originalConnection,
  );
  _registerTestServices();
}

void resetDevnetScenarioState() {
  app.sl<DevnetTestContext>()
    ..sentBlock = null
    ..plasmaFuseBlock = null
    ..pillarQsrDepositBlock = null
    ..deployPillarBlock = null
    ..issueTokenBlock = null
    ..stakeBlock = null
    ..plasmaFuseAmount = null
    ..pillarQsrDepositAmount = null;
  selectDevnetSender(DevnetTestContext.defaultSenderAddress);
}

void selectDevnetSender(String senderAddress) {
  if (!kDefaultAddressList.contains(senderAddress)) {
    throw StateError(
      'Sender address $senderAddress is not in the devnet wallet',
    );
  }
  kSelectedAddress = senderAddress;
}

/// Selects Transfer only for the original verified in-memory devnet owner.
void selectDevnetTransfer() {
  final DevnetWalletBinding? binding = _walletBinding;
  if (binding == null ||
      _devnetClient == null ||
      _devnetSocket == null ||
      _devnetSocketUrl == null ||
      !identical(app.zenon, _devnetClient) ||
      !identical(_devnetClient?.wsClient, _devnetSocket) ||
      _devnetSocket?.url != _devnetSocketUrl) {
    throw StateError('The original devnet Transfer owner is unavailable');
  }
  binding.selectTransfer();
}

Future<void> disposeDevnetIntegrationTests() async {
  if (_devnetClient == null &&
      _walletBinding == null &&
      _hiveDirectory == null) {
    return;
  }
  try {
    if (_walletBinding != null &&
        (!identical(app.zenon, _devnetClient) ||
            !identical(_devnetClient?.wsClient, _devnetSocket) ||
            _devnetSocket?.url != _devnetSocketUrl)) {
      throw StateError('The devnet wallet cannot restore a changed node owner');
    }
    _walletBinding?.restore();
    _walletBinding = null;
  } finally {
    await _stopOwnedDevnetNode();
  }
  await app.sharedPrefsService?.close();
  app.sharedPrefsService = null;
  if (app.sl.isRegistered<SharedPrefsService>()) {
    await app.sl.unregister<SharedPrefsService>();
  }
  await Hive.close();
  _hiveDirectory?.deleteSync(recursive: true);
  _hiveDirectory = null;
}

Future<void> _stopOwnedDevnetNode() async {
  final Zenon? client = _devnetClient;
  final WsClient? socket = _devnetSocket;
  if (client == null || socket == null) return;
  if (!identical(client.wsClient, socket) ||
      socket.url != _devnetSocketUrl ||
      socket.status() == WebsocketStatus.connecting) {
    throw StateError('The original devnet connection has not settled');
  }
  socket.stop();
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!socket.isClosed() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  if (!socket.isClosed() ||
      !identical(client.wsClient, socket) ||
      socket.url != _devnetSocketUrl ||
      socket.status() == WebsocketStatus.connecting ||
      socket.status() == WebsocketStatus.running) {
    throw StateError('The original devnet connection did not close');
  }
  if (app.sl.isRegistered<Zenon>() && identical(app.sl<Zenon>(), client)) {
    await app.sl.unregister<Zenon>();
  }
  if (identical(app.zenon, client)) app.zenon = null;
  _devnetClient = null;
  _devnetSocket = null;
  _devnetSocketUrl = null;
}

String devnetEnv(String name, String fallback) {
  final String dartDefineValue = String.fromEnvironment(name);
  if (dartDefineValue.isNotEmpty) {
    return dartDefineValue;
  }

  final String? platformValue = Platform.environment[name];
  return platformValue == null || platformValue.isEmpty
      ? fallback
      : platformValue;
}

Future<void> _initializeSharedPrefs() async {
  _hiveDirectory ??= Directory.systemTemp.createTempSync(
    'syrius_devnet_integration_',
  );
  Hive.init(_hiveDirectory!.path);
  app.sharedPrefsService = await SharedPrefsService.getInstance();
  if (!Hive.isBoxOpen(kFavoriteTokensBox)) {
    await Hive.openBox<dynamic>(kFavoriteTokensBox);
  }
  if (app.sl.isRegistered<SharedPrefsService>()) {
    await app.sl.unregister<SharedPrefsService>();
  }
  app.sl.registerSingleton<SharedPrefsService>(app.sharedPrefsService!);
}

class DevnetWalletFile extends WalletFile {
  DevnetWalletFile(this._wallet) : super('devnet-memory-wallet');

  final Wallet _wallet;
  bool _isOpen = false;

  @override
  bool get isHardwareWallet => false;

  @override
  bool get isOpen => _isOpen;

  @override
  String get walletType => keyStoreWalletType;

  @override
  Future<Wallet> open() async {
    _isOpen = true;
    return _wallet;
  }

  @override
  Future<void> close() async {
    _isOpen = false;
  }
}

/// Installs only an in-memory wallet after the original node proves chain 69.
/// Offline tests can exercise production admission without opening the wallet.
class DevnetWalletBinding {
  /// Uses the verified node facts and the original fixture's in-memory path.
  factory DevnetWalletBinding.install({
    required DevnetWalletFile walletFile,
    required List<String> addresses,
    required String selectedAddress,
    required String nodeUrl,
    required int verifiedChainId,
  }) {
    if (verifiedChainId != DevnetTestContext.chainId ||
        nodeUrl.isEmpty ||
        addresses.isEmpty ||
        !addresses.contains(selectedAddress) ||
        walletFile.isOpen ||
        NodeTransitions.pending) {
      throw StateError('The verified devnet wallet source is unavailable');
    }
    final DevnetWalletBinding binding = DevnetWalletBinding._(
      walletFile,
      nodeUrl,
    );
    kWalletFile = walletFile;
    kWalletPath = walletFile.walletPath;
    kDefaultAddressList = List<String?>.of(addresses);
    kAddressLabelMap = <String, String>{
      for (int i = 0; i < addresses.length; i += 1) addresses[i]: 'Address $i',
    };
    kSelectedAddress = selectedAddress;
    kCurrentNode = nodeUrl;
    kNodeChainId = verifiedChainId;
    setChainIdentifier(chainIdentifier: verifiedChainId);
    kCurrentPage = Tabs.dashboard;
    kWalletInitCompleted = true;
    WalletContextRevision.invalidate();
    return binding;
  }

  DevnetWalletBinding._(this._walletFile, this._nodeUrl)
    : _client = app.zenon,
      _previousWalletFile = kWalletFile,
      _previousWalletPath = kWalletPath,
      _previousAddresses = kDefaultAddressList,
      _previousLabels = kAddressLabelMap,
      _previousSelectedAddress = kSelectedAddress,
      _previousNode = kCurrentNode,
      _previousNodeChainId = kNodeChainId,
      _previousChainId = getChainIdentifier(),
      _previousPage = kCurrentPage,
      _previousInitialized = kWalletInitCompleted;

  final DevnetWalletFile _walletFile;
  final Zenon? _client;
  final String _nodeUrl;
  final WalletFile? _previousWalletFile;
  final String? _previousWalletPath;
  final List<String?> _previousAddresses;
  final Map<String, String> _previousLabels;
  final String? _previousSelectedAddress;
  final String? _previousNode;
  final int? _previousNodeChainId;
  final int _previousChainId;
  final Tabs? _previousPage;
  final bool _previousInitialized;
  bool _restored = false;

  /// Enters the actual Send page without replacing its production admission.
  void selectTransfer() {
    if (_restored ||
        _client == null ||
        !identical(app.zenon, _client) ||
        !identical(kWalletFile, _walletFile) ||
        _walletFile.isOpen ||
        kWalletPath != _walletFile.walletPath ||
        kCurrentNode != _nodeUrl ||
        kNodeChainId != DevnetTestContext.chainId ||
        getChainIdentifier() != DevnetTestContext.chainId ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        !kDefaultAddressList.contains(kSelectedAddress) ||
        NodeTransitions.pending) {
      throw StateError('The original devnet Transfer binding changed');
    }
    if (kCurrentPage != Tabs.transfer) {
      kCurrentPage = Tabs.transfer;
      WalletContextRevision.invalidate();
    }
  }

  /// Restores original values and collection identities, never a foreign file.
  void restore() {
    if (_restored) return;
    if (!identical(kWalletFile, _walletFile) || _walletFile.isOpen) {
      throw StateError('The devnet wallet cannot release its original binding');
    }
    kWalletFile = _previousWalletFile;
    kWalletPath = _previousWalletPath;
    kDefaultAddressList = _previousAddresses;
    kAddressLabelMap = _previousLabels;
    kSelectedAddress = _previousSelectedAddress;
    kCurrentNode = _previousNode;
    kNodeChainId = _previousNodeChainId;
    setChainIdentifier(chainIdentifier: _previousChainId);
    kCurrentPage = _previousPage;
    kWalletInitCompleted = _previousInitialized;
    _restored = true;
    WalletContextRevision.invalidate();
  }
}

class InMemoryHydratedStorage implements Storage {
  final Map<String, dynamic> _storage = <String, dynamic>{};

  @override
  Future<void> clear() async => _storage.clear();

  @override
  Future<void> close() async {}

  @override
  Future<void> delete(String key) async => _storage.remove(key);

  @override
  dynamic read(String key) => _storage[key];

  @override
  Future<void> write(String key, dynamic value) async => _storage[key] = value;
}

class TestNotificationsBloc extends NotificationsBloc {
  @override
  Future<void> addNotification(
    WalletNotification? notification, {
    bool Function()? shouldDisplay,
    Box<dynamic>? originalStore,
    bool requireOriginalStore = false,
  }) async {
    if (shouldDisplay?.call() != false) addEvent(notification);
  }

  @override
  Future<void> sendPlasmaNotification(
    String purposeOfGeneratingPlasma, {
    bool Function()? shouldDisplay,
    Box<dynamic>? originalStore,
    bool requireOriginalStore = false,
  }) async {}
}

void _registerTestServices() {
  if (!app.sl.isRegistered<Zenon>()) {
    app.sl.registerSingleton<Zenon>(app.zenon!);
  }
  if (!app.sl.isRegistered<NotificationsBloc>()) {
    app.sl.registerSingleton<NotificationsBloc>(TestNotificationsBloc());
  }
  if (!app.sl.isRegistered<BalanceBloc>()) {
    app.sl.registerSingleton<BalanceBloc>(BalanceBloc());
  }
  if (!app.sl.isRegistered<MultipleBalanceBloc>()) {
    app.sl.registerSingleton<MultipleBalanceBloc>(
      MultipleBalanceBloc(zenon: app.zenon!),
    );
  }
  if (!app.sl.isRegistered<PlasmaStatsBloc>()) {
    app.sl.registerSingleton<PlasmaStatsBloc>(
      PlasmaStatsBloc(zenon: app.zenon!),
    );
  }
  if (!app.sl.isRegistered<PowGeneratingStatusBloc>()) {
    app.sl.registerSingleton<PowGeneratingStatusBloc>(
      PowGeneratingStatusBloc(),
    );
  }
}

Future<void> _configureWalletGlobals(
  KeyStore wallet, {
  required String nodeUrl,
  required int verifiedChainId,
  required bool Function() originalConnection,
}) async {
  const int maxIndex = 9;
  final List<String> addresses = <String>[];

  for (int i = 0; i <= maxIndex; i += 1) {
    final WalletAccount account = await wallet.getAccount(i);
    addresses.add((await account.getAddress()).toString());
  }

  if (!originalConnection()) {
    throw StateError('The verified devnet connection changed');
  }
  _walletBinding = DevnetWalletBinding.install(
    walletFile: DevnetWalletFile(wallet),
    addresses: addresses,
    selectedAddress: DevnetTestContext.defaultSenderAddress,
    nodeUrl: nodeUrl,
    verifiedChainId: verifiedChainId,
  );
}
