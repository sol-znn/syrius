import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../publication_session/support.dart';

void main() {
  late PublicationGlobals globals;
  late MockPublicationFile file;
  final String address = emptyAddress.toString();

  setUp(() {
    globals = PublicationGlobals();
    app.zenon = MockPublicationZenon();
    file = MockPublicationFile();
    kWalletFile = file;
    kWalletInitCompleted = true;
    kWalletPath = 'isolated-fixture';
    kSelectedAddress = address;
    kDefaultAddressList = <String?>[address];
    kCurrentPage = Tabs.dashboard;
    kCurrentNode = 'isolated-node';
    kNodeChainId = 321;
    setChainIdentifier(chainIdentifier: 321);
  });
  tearDown(() {
    globals.restore();
    WalletContextRevision.invalidate();
  });

  test(
    'capture keeps one selected initialized account without opening a file',
    () {
      final WalletActionContext captured = WalletActionContext.capture(
        address,
      )!;
      expect(captured.ownerAddress, address);
      expect(captured.client, same(app.zenon));
      expect(captured.isCurrent, isTrue);
      captured.requireCurrent();
      verifyNever(file.open);
      verifyNever(() => file.isOpen);
    },
  );

  test('an unselected or unknown account cannot be captured', () {
    expect(WalletActionContext.capture('another-account'), isNull);
    kDefaultAddressList = <String?>[];
    expect(WalletActionContext.capture(address), isNull);
  });

  test('transport quarantine refuses new and original action authority', () {
    final WalletActionContext captured = WalletActionContext.capture(address)!;
    final NodeTransitionLease lease = NodeTransitions.begin()!;
    try {
      expect(WalletActionContext.capture(address), isNull);
      expect(captured.isCurrent, isFalse);
      expect(captured.requireCurrent, throwsA(isA<Exception>()));
      expect(lease.complete(), isTrue);
      expect(captured.isCurrent, isFalse);
      expect(WalletActionContext.capture(address)!.isCurrent, isTrue);
      verifyNever(file.open);
    } finally {
      lease.complete();
    }
  });

  test('an unobserved transport round trip still revokes old authority', () {
    final WalletActionContext captured = WalletActionContext.capture(address)!;
    final NodeTransitionLease lease = NodeTransitions.begin()!;
    try {
      expect(lease.complete(), isTrue);
      expect(captured.isCurrent, isFalse);
      expect(WalletActionContext.capture(address)!.isCurrent, isTrue);
      verifyNever(file.open);
    } finally {
      lease.complete();
    }
  });

  final Map<String, void Function()> changes = <String, void Function()>{
    'lock': () => kCurrentPage = Tabs.lock,
    'uninitialized wallet': () => kWalletInitCompleted = false,
    'wallet release': () => kWalletFile = null,
    'wallet replacement': () => kWalletFile = MockPublicationFile(),
    'client replacement': () => app.zenon = MockPublicationZenon(),
    'selection': () => kSelectedAddress = 'another-account',
    'address membership': () => kDefaultAddressList[0] = 'another-account',
    'wallet identity': () => kWalletPath = 'another-isolated-fixture',
    'node': () => kCurrentNode = 'another-isolated-node',
    'node chain': () => kNodeChainId = 1,
    'chain': setChainIdentifier,
    'context round trip': WalletContextRevision.invalidate,
  };
  for (final MapEntry<String, void Function()> change in changes.entries) {
    test('${change.key} revokes the original authority', () {
      final WalletActionContext captured = WalletActionContext.capture(
        address,
      )!;
      change.value();
      expect(captured.isCurrent, isFalse);
      expect(captured.requireCurrent, throwsA(isA<Exception>()));
      verifyNever(file.open);
    });
  }

  test('a lock round trip cannot revive a previously refused context', () {
    final WalletActionContext captured = WalletActionContext.capture(address)!;
    kCurrentPage = Tabs.lock;
    expect(captured.isCurrent, isFalse);
    kCurrentPage = Tabs.dashboard;
    expect(captured.isCurrent, isFalse);
  });
}
