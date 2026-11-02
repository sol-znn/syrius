import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hex/hex.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/background_crypto.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/functions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_actions.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

WalletActionContext? _captureWallet() {
  final String? selected = kSelectedAddress;
  return selected == null ? null : WalletActionContext.capture(selected);
}

bool Function() _captureWalletSource(
  WalletActionContext context,
  bool Function() external,
) {
  final WsClient socket = context.client.wsClient;
  final String? url = socket.url;
  final LedgerApi ledger = context.client.ledger;
  final StatsApi stats = context.client.stats;
  final Client ledgerClient = ledger.client;
  final Client statsClient = stats.client;
  bool revoked = false;
  return () =>
      !revoked &&
      !(revoked =
          !context.isCurrent ||
          !external() ||
          !identical(socket, context.client.wsClient) ||
          socket.url != url ||
          !identical(ledger, context.client.ledger) ||
          !identical(stats, context.client.stats) ||
          !identical(ledgerClient, ledger.client) ||
          !identical(statsClient, stats.client));
}

/// Reads only the exact open preference box; malformed values stay unknown.
SecuritySettingsState readSecuritySettingsState() {
  if (!Hive.isBoxOpen(kSharedPrefsBox) || app.sharedPrefsService == null) {
    return const SecuritySettingsState(lockMinutes: null, wrongPasswords: null);
  }
  final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
  int? positive(String key, int fallback) {
    return securityPositivePreference(
      box.get(key),
      exists: box.containsKey(key),
      fallback: fallback,
    );
  }

  return SecuritySettingsState(
    lockMinutes: positive(
      kAutoLockWalletMinutesKey,
      kAutoLockWalletDefaultIntervalMinutes,
    ),
    wrongPasswords: positive(
      kAutoEraseNumAttemptsKey,
      kAutoEraseNumAttemptsDefault.toInt(),
    ),
  );
}

/// Captures the actual open box. Mounting the Security view does not call it.
SecurityPolicySession? captureSecurityPolicy({
  required bool Function() isCurrent,
  required FutureOr<void> Function() onPolicyChanged,
  required String lockChanged,
  required String limitChanged,
}) {
  final WalletActionContext? context = _captureWallet();
  final SharedPrefsService? service = app.sharedPrefsService;
  if (context == null ||
      service == null ||
      !isCurrent() ||
      !Hive.isBoxOpen(kSharedPrefsBox)) {
    return null;
  }
  return _SecurityPolicy(
    context: context,
    visible: _captureWalletSource(context, isCurrent),
    preferences: Hive.box<dynamic>(kSharedPrefsBox),
    service: service,
    onPolicyChanged: onPolicyChanged,
    notifications: app.sl.get<NotificationsBloc>(),
    notificationStore: Hive.isBoxOpen(kNotificationsBox)
        ? Hive.box<dynamic>(kNotificationsBox)
        : null,
    lockChanged: lockChanged,
    limitChanged: limitChanged,
  );
}

class _SecurityPolicy implements SecurityPolicySession {
  _SecurityPolicy({
    required this._context,
    required this._visible,
    required this._preferences,
    required this._service,
    required this._onPolicyChanged,
    required this._notifications,
    required this._notificationStore,
    required this._lockChanged,
    required this._limitChanged,
  });

  final WalletActionContext _context;
  final bool Function() _visible;
  final Box<dynamic> _preferences;
  final SharedPrefsService _service;
  final FutureOr<void> Function() _onPolicyChanged;
  final NotificationsBloc _notifications;
  final Box<dynamic>? _notificationStore;
  final String _lockChanged;
  final String _limitChanged;
  num? _originalPolicy;
  bool _revoked = false;
  SecurityPreference? _written;
  int? _value;

  @override
  Object get store => _preferences;

  @override
  bool get ownsStore =>
      _preferences.isOpen &&
      Hive.isBoxOpen(kSharedPrefsBox) &&
      identical(_preferences, Hive.box<dynamic>(kSharedPrefsBox)) &&
      identical(_service, app.sharedPrefsService);

  @override
  bool get isCurrent =>
      !_revoked &&
      !(_revoked = !ownsStore || !_context.isCurrent || !_visible());

  String _key(SecurityPreference preference) =>
      preference == SecurityPreference.lockMinutes
      ? kAutoLockWalletMinutesKey
      : kAutoEraseNumAttemptsKey;

  @override
  Future<void> persist(SecurityPreference preference, int value) async {
    if (!ownsStore || !isCurrent || value <= 0 || _written != null) {
      throw const SecuritySettingsRefused();
    }
    // The shared key lane has admitted us. Freeze before the original put.
    _originalPolicy = preference == SecurityPreference.lockMinutes
        ? kAutoLockWalletMinutes
        : kAutoEraseWalletLimit;
    _written = preference;
    _value = value;
    if (preference == SecurityPreference.lockMinutes) {
      await _preferences.put(_key(preference), value);
    } else {
      await _preferences.put(_key(preference), value.toDouble());
    }
  }

  @override
  void apply(SecurityPreference preference, int value) {
    if (!ownsStore ||
        _written != preference ||
        _value != value ||
        _preferences.get(_key(preference)) != value ||
        (preference == SecurityPreference.lockMinutes
            ? kAutoLockWalletMinutes != _originalPolicy
            : kAutoEraseWalletLimit != _originalPolicy)) {
      throw const SecuritySettingsRefused();
    }
    if (preference == SecurityPreference.lockMinutes) {
      kAutoLockWalletMinutes = value;
    } else {
      kAutoEraseWalletLimit = value.toDouble();
    }
  }

  @override
  Future<void> effect(SecurityPreference preference) async {
    if (preference == SecurityPreference.lockMinutes && ownsStore) {
      await _onPolicyChanged();
    }
  }

  @override
  Future<void> notify(SecurityPreference preference) async {
    final Box<dynamic>? store = _notificationStore;
    if (store != null &&
        isCurrent &&
        _notifications.ownsOriginalStore(store) &&
        app.sl.isRegistered<NotificationsBloc>() &&
        identical(_notifications, app.sl<NotificationsBloc>())) {
      final NotificationWriteReceipt receipt = await _notifications
          .writeNotification(
            WalletNotification(
              title: preference == SecurityPreference.lockMinutes
                  ? _lockChanged
                  : _limitChanged,
              details: '',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              type: preference == SecurityPreference.lockMinutes
                  ? NotificationType.autoLockIntervalChanged
                  : NotificationType.autoEraseNumAttemptsChanged,
            ),
            originalStore: store,
            shouldDisplay: () =>
                isCurrent &&
                app.sl.isRegistered<NotificationsBloc>() &&
                identical(_notifications, app.sl<NotificationsBloc>()),
          );
      if (!receipt.completed) {
        final Object error = receipt.error ?? const SecuritySettingsRefused();
        Error.throwWithStackTrace(
          error,
          receipt.stackTrace ?? StackTrace.current,
        );
      }
    }
  }
}

/// The signing account and resource are captured before any awaited input.
SecurityCryptoSession? captureSecurityCrypto({
  required bool Function() isCurrent,
}) {
  final WalletActionContext? context = _captureWallet();
  final WalletFile? file = kWalletFile;
  final int index = kDefaultAddressList.indexOf(kSelectedAddress);
  if (context == null ||
      file == null ||
      file.walletPath != kWalletPath ||
      index < 0 ||
      !isCurrent()) {
    return null;
  }
  return _SecurityCrypto(
    context,
    file,
    index,
    _captureWalletSource(context, isCurrent),
  );
}

class _SecurityCrypto implements SecurityCryptoSession {
  _SecurityCrypto(this._context, this._file, this._index, this._visible);

  final WalletActionContext _context;
  final WalletFile _file;
  final int _index;
  final bool Function() _visible;
  bool _revoked = false;

  @override
  bool get isCurrent =>
      !_revoked && !(_revoked = !_context.isCurrent || !_visible());

  void _require() {
    if (!isCurrent) {
      throw const SecuritySettingsRefused();
    }
  }

  Future<SecuritySignature> _sign(List<int> message) async {
    _require();
    final SecuritySignature result = await _file.access<SecuritySignature>(
      (Wallet wallet) async {
        _require();
        final WalletAccount account = await wallet.getAccount(_index);
        _require();
        final List<int> publicKey = await account.getPublicKey();
        _require();
        final List<int> signature = await account.sign(message);
        _require();
        return SecuritySignature(
          signature: HEX.encode(signature),
          publicKey: HEX.encode(publicKey),
        );
      },
    );
    _require();
    return result;
  }

  @override
  Future<SecuritySignature> signText(String message) =>
      _sign(messageBytesToSign(message));

  @override
  Future<SecuritySignature> signFile(String path) async {
    _require();
    final List<int> digest = await BackgroundCrypto.digestFile(path);
    _require();
    return _sign(digest);
  }

  Future<bool> _verify(
    List<int> message,
    String signature,
    String publicKey,
  ) async {
    _require();
    final bool result = await BackgroundCrypto.verify(
      HEX.decode(signature),
      message,
      HEX.decode(publicKey),
    );
    _require();
    return result;
  }

  @override
  Future<bool> verifyText(
    String message,
    String signature,
    String publicKey,
  ) => _verify(messageBytesToSign(message), signature, publicKey);

  @override
  Future<bool> verifyFile(
    String path,
    String signature,
    String publicKey,
  ) async {
    _require();
    final List<int> digest = await BackgroundCrypto.digestFile(path);
    _require();
    return _verify(digest, signature, publicKey);
  }

  @override
  Future<String?> pickFile() async {
    _require();
    final XFile? file = await openFile();
    _require();
    return file?.path;
  }

  @override
  Future<String?> paste() async {
    _require();
    final ClipboardData? data = await Clipboard.getData('text/plain');
    _require();
    return data?.text;
  }

  @override
  Future<void> copy(String value) async {
    _require();
    await Clipboard.setData(ClipboardData(text: value));
  }
}

/// Captures an initialized software wallet for explicit Backup actions.
SettingsSensitiveSession? captureSettingsSensitiveSession({
  required bool Function() isCurrent,
  required String fileType,
}) {
  final WalletActionContext? context = _captureWallet();
  final WalletFile? file = kWalletFile;
  if (context == null ||
      file == null ||
      file.walletPath != kWalletPath ||
      !isCurrent()) {
    return null;
  }
  final String originalPath = file.walletPath;
  final bool Function() current = _captureWalletSource(context, isCurrent);
  return SettingsSensitiveActions(
    isCurrent: current,
    isHardwareWallet: file.isHardwareWallet,
    unlocked: _WalletSeedResource(file),
    decrypt: (String password) async {
      if (!current() || file.isHardwareWallet) {
        throw const SecuritySettingsRefused();
      }
      final WalletFile decrypted = await WalletFile.decrypt(
        originalPath,
        password,
      );
      return _WalletSeedResource(decrypted);
    },
    vault: _VaultBackend(current, fileType),
  );
}

/// Retains the onboarding export path without requiring an unlocked wallet.
SettingsSensitiveSession? captureOnboardingVaultSession({
  required bool Function() isCurrent,
  required String fileType,
}) {
  if (!isCurrent() || NodeChange.transitionPending) {
    return null;
  }
  if (kWalletInitCompleted && (kWalletFile?.isHardwareWallet ?? false)) {
    return null;
  }
  final Object? file = kWalletFile;
  final String? path = kWalletPath;
  final Object? client = app.zenon;
  final int revision = WalletContextRevision.value;
  final List<String?> addresses = List<String?>.of(kDefaultAddressList);
  final String? selected = kSelectedAddress;
  final bool initialized = kWalletInitCompleted;
  bool revoked = false;
  bool current() =>
      !revoked &&
      !(revoked =
          !isCurrent() ||
          NodeChange.transitionPending ||
          !identical(file, kWalletFile) ||
          !identical(client, app.zenon) ||
          path != kWalletPath ||
          revision != WalletContextRevision.value ||
          selected != kSelectedAddress ||
          initialized != kWalletInitCompleted ||
          !listEquals(addresses, kDefaultAddressList));
  return SettingsSensitiveActions(
    isCurrent: current,
    isHardwareWallet: false,
    unlocked: null,
    decrypt: (String _) async => throw const SecuritySettingsRefused(),
    vault: _VaultBackend(current, fileType),
  );
}

class _WalletSeedResource implements SettingsSeedResource {
  _WalletSeedResource(this._file);

  final WalletFile _file;

  @override
  Future<T> access<T>(Future<T> Function(String mnemonic) read) =>
      _file.isHardwareWallet
      ? Future<T>.error(const SecuritySettingsRefused())
      : _file.access<T>((Wallet wallet) async {
          if (wallet is! KeyStore) {
            throw const SecuritySettingsRefused();
          }
          return read(wallet.mnemonic!);
        });
}

class _VaultBackend implements SettingsVaultBackend {
  _VaultBackend(this._current, this._fileType);

  final bool Function() _current;
  final String _fileType;

  void _require() {
    if (!_current()) {
      throw const SecuritySettingsRefused();
    }
  }

  @override
  Future<Object?> chooseDestination() async {
    _require();
    final Directory initial = await getApplicationDocumentsDirectory();
    _require();
    final String stamp = FormatUtils.fileStamp(DateTime.now());
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: _fileType, extensions: const <String>['json']),
      ],
      initialDirectory: initial.path,
      suggestedName: 'zenon-syrius-wallet-backup-$stamp.json',
    );
    _require();
    return location?.path;
  }

  @override
  Future<Object> encrypt(String seed, String password) async {
    _require();
    final BackgroundKeyStore wallet = await BackgroundKeyStore.fromMnemonic(
      seed,
    );
    _require();
    final WalletAccount account = await wallet.getAccount();
    _require();
    final Address address = await account.getAddress();
    _require();
    // Same envelope and metadata as the pinned SDK's saveKeyStoreFunction.
    final EncryptedFile envelope = await BackgroundCrypto.encrypt(
      HEX.decode(wallet.entropy),
      password,
      metadata: <String, String>{
        baseAddressKey: address.toString(),
        walletTypeKey: keyStoreWalletType,
      },
    );
    _require();
    return json.encode(envelope);
  }

  @override
  Future<void> write(Object destination, Object envelope) async {
    _require();
    await File(destination as String).writeAsString(envelope as String);
  }
}
