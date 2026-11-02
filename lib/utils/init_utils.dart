import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/widget_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Restores the existing application preferences and wallet services.
class InitUtils {
  static Future<void>? _counterInitialization;
  static final List<WalletInitializationOperation> _counterOperations =
      <WalletInitializationOperation>[];

  /// Private startup receipts remain available to the owning coordinator.
  static List<WalletInitializationOperation> get counterOperations =>
      List<WalletInitializationOperation>.unmodifiable(_counterOperations);

  /// Loads shared state before entry can expose the wallet.
  static Future<void> initApp(BuildContext context) async {
    WidgetUtils.setThemeMode(context);
    WidgetUtils.setTextScale(context);
    WidgetUtils.setLanguage(context);
    _setAutoEraseWalletNumAttempts();
    _setAutoLockWalletTimeInterval();
    await _setNumUnlockFailedAttempts();
    await WalletInitializationSource.prepareBoxes();
    WalletInitializationSource.restorePath();
    await NodeUtils.setNode();
    _setChainId();
    await NodeUtils.loadDbNodes();
    await _openFavoriteTokensBox();
    await _openNotificationsBox();
    await _openRecipientBox();
    try {
      await ContactsStore.instance.open();
    } on Object {
      // The store retains its unavailable state. Its convenience data must
      // not turn wallet startup into a failed authentication attempt.
      try {
        Logger('InitUtils').warning('The address book could not be opened.');
      } on Object {
        // Logging is another optional observer, not authentication.
        return;
      }
    }
  }

  static void _setChainId() {
    setChainIdentifier(
      chainIdentifier: sharedPrefsService!.get(
        kChainIdKey,
        defaultValue: kChainIdDefaultValue,
      ),
    );
  }

  static Future<void> _setNumUnlockFailedAttempts() {
    if (_counterInitialization != null) return _counterInitialization!;
    final Completer<void> completion = Completer<void>();
    _counterInitialization = completion.future;
    final WalletInitializationOperation operation =
        WalletInitializationOperation('original-unlock-counter');
    _counterOperations.add(operation);
    unawaited(
      operation
          .run<void>(_initializeCounter)
          .then<void>(
            (_) => completion.complete(),
            onError: completion.completeError,
          ),
    );
    return completion.future;
  }

  static Future<void> _initializeCounter() async {
    final SharedPrefsService? preferences = sharedPrefsService;
    if (preferences == null || !Hive.isBoxOpen(kSharedPrefsBox)) {
      throw const WalletInitializationRefused('preferences');
    }
    final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
    bool owns() =>
        identical(preferences, sharedPrefsService) &&
        box.isOpen &&
        Hive.isBoxOpen(kSharedPrefsBox) &&
        identical(Hive.box<dynamic>(kSharedPrefsBox), box);
    final dynamic stored = box.get(kNumUnlockFailedAttemptsKey);
    if (stored != null && (stored is! int || stored < 0)) {
      throw const WalletInitializationRefused('counter');
    }
    if (stored == null) {
      final WalletInitializationOperation write = WalletInitializationOperation(
        'initialize-unlock-counter',
      );
      _counterOperations.add(write);
      await write.run<void>(() => box.put(kNumUnlockFailedAttemptsKey, 0));
      if (!owns() || box.get(kNumUnlockFailedAttemptsKey) != 0) {
        throw const WalletInitializationRefused('counter-write');
      }
      final WalletInitializationOperation flush = WalletInitializationOperation(
        'flush-unlock-counter',
      );
      _counterOperations.add(flush);
      await flush.run<void>(box.flush);
    }
    if (!owns() || box.get(kNumUnlockFailedAttemptsKey) != (stored ?? 0)) {
      throw const WalletInitializationRefused('counter-replaced');
    }
    kNumFailedUnlockAttempts = stored as int? ?? 0;
  }

  static void _setAutoEraseWalletNumAttempts() =>
      kAutoEraseWalletLimit = sharedPrefsService!.get(
        kAutoEraseNumAttemptsKey,
        defaultValue: kAutoEraseNumAttemptsDefault,
      );

  static void _setAutoLockWalletTimeInterval() =>
      kAutoLockWalletMinutes = sharedPrefsService!.get(
        kAutoLockWalletMinutesKey,
        defaultValue: kAutoLockWalletDefaultIntervalMinutes,
      );

  /// Captures every original backend before a creation factory is invoked.
  static WalletInitializationBinding? captureWalletCreation({
    required bool Function() sourceIsCurrent,
  }) => WalletInitializationSource.capture(
    creating: true,
    sourceIsCurrent: sourceIsCurrent,
  );

  /// Initializes only the file captured by the decrypting owner. An uncertain
  /// original is retained by its journal; this method never retries or resumes
  /// terminal service owners, migrates a cipher, or publishes a replacement.
  static Future<void> initWalletAfterDecryption(
    List<int> cipherKey, {
    required WalletFile originalFile,
    required WalletInitializationBinding binding,
  }) async {
    final WalletFile file = originalFile;
    binding.requireCurrent();
    final WalletInitializationRun original = binding.start(
      create: () => Future<Object>.value(file),
      cipherKey: cipherKey,
    );
    final WalletInitializationOutcome outcome = await original.completion;
    if (!outcome.published ||
        !outcome.initialized ||
        outcome.error != null ||
        !identical(outcome.file, file)) {
      // The original diagnostic remains private in the retained run.
      throw const WalletInitializationRefused('initialization');
    }
  }

  static Future<void> _openFavoriteTokensBox() async =>
      Hive.openBox(kFavoriteTokensBox);

  static Future<void> _openNotificationsBox() async =>
      Hive.openBox(kNotificationsBox);

  static Future<void> _openRecipientBox() async =>
      Hive.openBox(kRecipientAddressBox);
}
