import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_ready_binding.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

// This display-only file cannot acquire, decrypt or release a wallet.
class _ClosedFile extends WalletFile {
  _ClosedFile() : super('fixture.enc');

  @override
  String get walletType => 'fixture';

  @override
  bool get isHardwareWallet => false;

  @override
  bool get isOpen => false;

  @override
  Future<Wallet> open() =>
      throw StateError('Display must not acquire a wallet');

  @override
  Future<void> close() => throw StateError('Display must not release a wallet');
}

void main() {
  late WalletFile? previousFile;
  late String? previousPath;
  late List<String?> previousMembers;
  late bool previousInitialized;
  late String? previousNode;
  late int? previousChain;
  late _ClosedFile file;
  NodeTransitionLease? owned;

  setUp(() {
    expect(NodeTransitions.pending, isFalse);
    previousFile = kWalletFile;
    previousPath = kWalletPath;
    previousMembers = kDefaultAddressList;
    previousInitialized = kWalletInitCompleted;
    previousNode = kCurrentNode;
    previousChain = kNodeChainId;
    file = _ClosedFile();
    kWalletFile = file;
    kWalletPath = file.walletPath;
    kDefaultAddressList = <String?>[emptyAddress.toString()];
    kWalletInitCompleted = true;
    kCurrentNode = 'ws://node.example:35998';
    kNodeChainId = null;
    owned = NodeTransitions.begin();
    expect(owned, isNotNull);
  });

  tearDown(() {
    if (owned?.isOwner ?? false) owned!.complete();
    kWalletFile = previousFile;
    kWalletPath = previousPath;
    kDefaultAddressList = previousMembers;
    kWalletInitCompleted = previousInitialized;
    kCurrentNode = previousNode;
    kNodeChainId = previousChain;
    owned = null;
  });

  test(
    'local Ready opens once while retaining the exact publication quarantine',
    () {
      final WalletReadyBinding? binding = WalletReadyBinding.capture(
        expectedFile: file,
      );
      expect(binding, isNotNull);
      expect(binding!.transportQuarantined, isTrue);
      expect(binding.firstAddress, emptyAddress.toString());
      expect(binding.isCurrent, isTrue);
      expect(binding.takeOpening(), isTrue);
      expect(binding.takeOpening(), isFalse);
      expect(NodeTransitions.pending, isTrue);
      expect(owned!.isOwner, isTrue);
    },
  );

  test(
    'a replacement quarantine cannot revive the earlier local Ready binding',
    () {
      final WalletReadyBinding binding = WalletReadyBinding.capture(
        expectedFile: file,
      )!;
      expect(owned!.complete(), isTrue);
      owned = NodeTransitions.begin();
      expect(NodeTransitions.pending, isTrue);
      expect(binding.isCurrent, isFalse);
      expect(binding.takeOpening(), isFalse);
      expect(owned!.isOwner, isTrue);
    },
  );

  test('quarantine never substitutes for successful local initialization', () {
    kWalletInitCompleted = false;
    expect(WalletReadyBinding.capture(expectedFile: file), isNull);
    expect(NodeTransitions.pending, isTrue);
    expect(owned!.isOwner, isTrue);
  });
}
