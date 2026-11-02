import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Replaces SDK calls so lifecycle cases never publish to a node.
class MockPublicationZenon extends Mock implements Zenon {}

/// Holds sync replies until a case has changed the originating session.
class MockPublicationStats extends Mock implements StatsApi {}

/// The captured reader owns its actual in-memory transport independently.
class MockPublicationClient extends Mock implements Client {}

/// Counts only the file acquisition owned by the publication under test.
class MockPublicationFile extends Mock implements WalletFile {}

/// Supplies an in-memory account without opening a wallet file.
class MockPublicationWallet extends Mock implements Wallet {}

/// Detects signing attempts without containing private key material.
class MockPublicationAccount extends Mock implements WalletAccount {}

/// Separates retained history from session-guarded transient displays.
class MockPublicationNotifications extends Mock implements NotificationsBloc {}

/// Exercises real ownership while allowing its display observer to fail.
class PublicationPow extends PowGeneratingStatusBloc {
  /// Calls [onUpdate] only after a current owner's SDK update is accepted.
  PublicationPow(void Function(PowStatus) onUpdate) : _onUpdate = onUpdate;

  final void Function(PowStatus) _onUpdate;

  @override
  bool update(PowWorkToken work, PowStatus status) {
    final bool accepted = super.update(work, status);
    if (accepted) _onUpdate(status);
    return accepted;
  }
}

/// Reports the original asynchronous release failure without replacing it.
class AsyncClosingPublicationFile extends MockPublicationFile {
  AsyncClosingPublicationFile(this.failure);

  final Error failure;
  int closes = 0;

  @override
  Future<void> close() async {
    closes++;
    await Future<void>.value();
    throw failure;
  }
}

/// Records settlement without advancing the fixture's controlled clock.
class PublicationOutcome {
  PublicationOutcome(Future<AccountBlockTemplate> future) {
    unawaited(
      future.then<void>(
        (AccountBlockTemplate value) {
          result = value;
          settled = true;
        },
        onError: (Object failure, StackTrace _) {
          error = failure;
          settled = true;
        },
      ),
    );
  }

  bool settled = false;
  AccountBlockTemplate? result;
  Object? error;
}

/// Every SDK, history and wallet boundary is in memory. No key or file exists.
class PublicationFixture {
  PublicationFixture() {
    when(() => node.stats).thenReturn(stats);
    when(() => stats.client).thenReturn(statsClient);
    when(() => statsClient.sendRequest('stats.syncInfo', any())).thenAnswer((
      _,
    ) {
      syncCalls++;
      return (syncReply ?? Future<SyncInfo>.value(syncInfo)).then(
        (SyncInfo value) => value.toJson(),
      );
    });
    configureFile(file);
    when(file.close).thenAnswer((_) {
      closeCalls++;
      if (closeFailure case final Error failure) throw failure;
      return Future<void>.value();
    });
    when(() => wallet.getAccount(any())).thenAnswer((Invocation call) {
      accountIndices.add(call.positionalArguments.single as int);
      return accountReply ?? Future<WalletAccount>.value(account);
    });
    when(
      () => node.requiresPoW(
        any(),
        blockSigningKey: any(named: 'blockSigningKey'),
      ),
    ).thenAnswer((Invocation call) {
      powCalls++;
      signingAccount = call.namedArguments[#blockSigningKey] as WalletAccount;
      (call.positionalArguments.single as AccountBlockTemplate).address =
          actualSigner ?? Address.parse(addresses[accountIndices.last]);
      return powReply ?? Future<bool>.value(needsPlasma);
    });
    when(
      () => node.send(
        any(),
        currentKeyPair: any(named: 'currentKeyPair'),
        generatingPowCallback: any(named: 'generatingPowCallback'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
      ),
    ).thenAnswer((Invocation call) {
      sendCalls++;
      sentTemplate = call.positionalArguments.single as AccountBlockTemplate;
      sentAccount = call.namedArguments[#currentKeyPair] as WalletAccount;
      waitedForPlasma = call.namedArguments[#waitForRequiredPlasma] as bool;
      powCallback =
          call.namedArguments[#generatingPowCallback]
              as void Function(PowStatus);
      if (sendFailure case final Object failure) {
        return Future<AccountBlockTemplate>.error(failure);
      }
      return sendReply ?? Future<AccountBlockTemplate>.value(response);
    });
    when(
      () => notifications.sendPlasmaNotification(
        any(),
        shouldDisplay: any(named: 'shouldDisplay'),
        originalStore: any(named: 'originalStore'),
        requireOriginalStore: true,
      ),
    ).thenAnswer((Invocation call) {
      plasmaCalls++;
      displayGuards.add(call.namedArguments[#shouldDisplay] as bool Function());
      return plasmaReply ?? Future<void>.value();
    });
    when(
      () => notifications.addNotification(
        any(),
        shouldDisplay: any(named: 'shouldDisplay'),
        originalStore: any(named: 'originalStore'),
        requireOriginalStore: true,
      ),
    ).thenAnswer((Invocation call) {
      final WalletNotification event =
          call.positionalArguments.single as WalletNotification;
      records.add(event);
      displayGuards.add(call.namedArguments[#shouldDisplay] as bool Function());
      if (historyFailure case final Object failure) {
        return Future<void>.error(failure);
      }
      if (event.type == NotificationType.confirm) {
        return reviewReply ?? Future<void>.value();
      }
      return historyReply ?? Future<void>.value();
    });
    app.sl.pushNewScope();
    app.sl.registerSingleton<NotificationsBloc>(notifications);
    app.sl.registerSingleton<PowGeneratingStatusBloc>(pow);
    app.zenon = node;
    kWalletFile = file;
    kWalletPath = 'fixture-wallet';
    kCurrentNode = 'fixture-node';
    kNodeChainId = chain;
    setChainIdentifier(chainIdentifier: chain);
    kDefaultAddressList = List<String?>.of(addresses);
    kSelectedAddress = addresses.last;
    kWalletInitCompleted = true;
    kCurrentPage = Tabs.dashboard;
  }

  static const int chain = 321;
  final MockPublicationZenon node = MockPublicationZenon();
  final MockPublicationStats stats = MockPublicationStats();
  final MockPublicationClient statsClient = MockPublicationClient();
  final MockPublicationFile file = MockPublicationFile();
  final MockPublicationWallet wallet = MockPublicationWallet();
  final MockPublicationAccount account = MockPublicationAccount();
  final MockPublicationNotifications notifications =
      MockPublicationNotifications();
  late final PublicationPow pow = PublicationPow((PowStatus status) {
    powEvents.add(status);
    if (powDisplayFailure case final Error failure) throw failure;
  });
  final List<String> addresses = <String>[
    kZnnCoin.owner.toString(),
    emptyAddress.toString(),
  ];
  final AccountBlockTemplate template = AccountBlockTemplate(
    blockType: BlockTypeEnum.userSend.index,
  );
  late final AccountBlockTemplate response =
      AccountBlockTemplate(
          blockType: BlockTypeEnum.userSend.index,
          amount: BigInt.parse('900719925474099300000001'),
          tokenStandard: kZnnCoin.tokenStandard,
        )
        ..hash = Hash.parse(List<String>.filled(64, '7').join())
        ..address = Address.parse(addresses.last)
        ..chainIdentifier = chain;
  SyncInfo syncInfo = SyncInfo.fromJson(<String, dynamic>{
    'state': SyncState.syncDone.index,
    'currentHeight': 100,
    'targetHeight': 100,
  });
  final WalletFlightRegistry registry = WalletFlightRegistry(
    currentChainId: getChainIdentifier,
    lookup: (_, _) async => false,
  );
  final List<WalletNotification> records = <WalletNotification>[];
  final List<bool Function()> displayGuards = <bool Function()>[];
  final List<PowStatus> powEvents = <PowStatus>[];
  final List<int> accountIndices = <int>[];
  final List<List<String>> observedAddresses = <List<String>>[];
  Future<SyncInfo>? syncReply;
  Future<Wallet>? openReply;
  Future<WalletAccount>? accountReply;
  Future<bool>? powReply;
  Future<AccountBlockTemplate>? sendReply;
  Future<void>? plasmaReply;
  Future<void>? reviewReply;
  Future<void>? historyReply;
  Object? sendFailure;
  Object? historyFailure;
  Error? closeFailure;
  Error? observerFailure;
  Error? powDisplayFailure;
  bool needsPlasma = false;
  bool hardware = false;
  Address? actualSigner;
  int syncCalls = 0;
  int openCalls = 0;
  int closeCalls = 0;
  int powCalls = 0;
  int sendCalls = 0;
  int plasmaCalls = 0;
  int observerCalls = 0;
  WalletAccount? signingAccount;
  WalletAccount? sentAccount;
  AccountBlockTemplate? sentTemplate;
  bool? waitedForPlasma;
  void Function(PowStatus)? powCallback;

  void configureFile(MockPublicationFile target) {
    when(() => target.walletPath).thenReturn('fixture-wallet');
    when(() => target.isHardwareWallet).thenAnswer((_) => hardware);
    when(() => target.open()).thenAnswer((_) {
      openCalls++;
      return openReply ?? Future<Wallet>.value(wallet);
    });
  }

  PublicationOutcome publish({Address? address, bool waitForPlasma = false}) {
    return PublicationOutcome(
      AccountBlockUtils(
        publicationObserver:
            (AccountBlockTemplate block, Iterable<String> sourceAddresses) {
              observerCalls++;
              observedAddresses.add(List<String>.of(sourceAddresses));
              if (observerFailure case final Error failure) throw failure;
              registry.published(block, sourceAddresses);
            },
      ).createAccountBlock(
        template,
        'Fixture plasma purpose',
        address: address,
        waitForRequiredPlasma: waitForPlasma,
      ),
    );
  }

  Future<void> dispose() async {
    pow.dispose();
    registry.dispose();
    await app.sl.popScope();
  }
}

/// Restores values, list identity and the SDK's process chain setting.
class PublicationGlobals {
  final Zenon? node = app.zenon;
  final WalletFile? file = kWalletFile;
  final String? path = kWalletPath;
  final String? selected = kSelectedAddress;
  final String? currentNode = kCurrentNode;
  final int? nodeChain = kNodeChainId;
  final int chain = getChainIdentifier();
  final bool initialized = kWalletInitCompleted;
  final Tabs? page = kCurrentPage;
  final List<String?> addresses = kDefaultAddressList;

  void restore() {
    app.zenon = node;
    kWalletFile = file;
    kWalletPath = path;
    kSelectedAddress = selected;
    kCurrentNode = currentNode;
    kNodeChainId = nodeChain;
    kWalletInitCompleted = initialized;
    kCurrentPage = page;
    kDefaultAddressList = addresses;
    setChainIdentifier(chainIdentifier: chain);
  }
}
