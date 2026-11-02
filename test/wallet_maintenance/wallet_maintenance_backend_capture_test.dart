import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart';

class _Sender extends Mock implements SendTransactionBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Box<dynamic>> owned;
  late Box<String> nodes;
  late SharedPrefsService? previousPreferences;
  late WalletFile? previousWallet;
  late String? previousPath;
  late bool previousInitialized;
  late bool previousEmbedded;

  setUp(() async {
    previousPreferences = app.sharedPrefsService;
    previousWallet = kWalletFile;
    previousPath = kWalletPath;
    previousInitialized = kWalletInitCompleted;
    previousEmbedded = kEmbeddedNodeRunning;
    expect(app.zenon, isNull);
    Hive.init('maintenance-backend-memory');
    owned = <Box<dynamic>>[];
    for (final String name in <String>[
      ...kCacheBoxesToBeDeleted, kKeyStoreBox,
    ]) {
      expect(Hive.isBoxOpen(name), isFalse);
      final Box<dynamic> box;
      if (name == kNodesBox) {
        nodes = await Hive.openBox<String>(name, bytes: Uint8List(0));
        box = nodes;
      } else {
        box = await Hive.openBox<dynamic>(name, bytes: Uint8List(0));
      }
      expect(box.path, isNull);
      owned.add(box);
    }
    app.sharedPrefsService = await SharedPrefsService.getInstance();
    kWalletFile = null;
    kWalletPath = 'synthetic-maintenance-wallet.enc';
    kWalletInitCompleted = false;
    kEmbeddedNodeRunning = false;
    await nodes.put('fixture', 'fixture-node');
    await Hive.box<dynamic>(kSharedPrefsBox).put('fixture-marker', true);
  });
  tearDown(() async {
    try {
      for (final Box<dynamic> box in owned.reversed) {
        if (box.isOpen) await box.close();
      }
    } finally {
      app.sharedPrefsService = previousPreferences;
      kWalletFile = previousWallet;
      kWalletPath = previousPath;
      kWalletInitCompleted = previousInitialized;
      kEmbeddedNodeRunning = previousEmbedded;
    }
  });

  WalletMaintenanceSession capture(WalletMaintenanceKind kind) {
    final WalletMaintenanceSession? original = captureWalletMaintenanceSession(
      kind: kind, sender: _Sender(),
    );
    expect(original, isNotNull);
    return original!;
  }

  test('reset captures the genuine String node registry without an erasure',
      () {
    // The original dynamic lookup reproduces Hive's exact-type refusal.
    expect(() => Hive.box<dynamic>(kNodesBox), throwsA(isA<HiveError>()));
    final WalletMaintenanceSession original = capture(
      WalletMaintenanceKind.reset,
    );
    expect(original.ownsResources, isTrue);
    expect(original.cleanupAvailable, isTrue);
    expect(Hive.box<String>(kNodesBox), same(nodes));
    expect(nodes.isOpen, isTrue);
    expect(nodes.get('fixture'), 'fixture-node');
    expect(Hive.box<dynamic>(kSharedPrefsBox).get('fixture-marker'), isTrue);
    expect(kWalletPath, 'synthetic-maintenance-wallet.enc');
    expect(kWalletFile, isNull);
    expect(kWalletInitCompleted, isFalse);
  });

  test('an equal replacement node registry cannot acquire the old reset',
      () async {
    final WalletMaintenanceSession original = capture(
      WalletMaintenanceKind.reset,
    );
    expect(original.ownsResources, isTrue);
    final Box<String> first = nodes;
    await first.close();
    nodes = await Hive.openBox<String>(kNodesBox, bytes: Uint8List(0));
    owned.add(nodes);
    await nodes.put('fixture', 'fixture-node');
    expect(nodes, isNot(same(first)));
    expect(original.ownsResources, isFalse);
    expect(nodes.get('fixture'), 'fixture-node');
    expect(original.ownsResources, isFalse);
    expect(kWalletPath, 'synthetic-maintenance-wallet.enc');
  });

  test('ordinary cache maintenance does not acquire the node registry',
      () async {
    final WalletMaintenanceSession original = capture(
      WalletMaintenanceKind.cache,
    );
    expect(original.ownsResources, isTrue);
    expect(original.cleanupAvailable, isTrue);
    await nodes.close();
    expect(original.ownsResources, isTrue);
    expect(Hive.box<dynamic>(kSharedPrefsBox).get('fixture-marker'), isTrue);
    expect(kWalletPath, 'synthetic-maintenance-wallet.enc');
  });
}
