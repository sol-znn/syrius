import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/security_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_sensitive_session.dart';

/// One original acquisition. Implementations release it in their own finally.
// A generic acquisition callback keeps the real resource outside presentation.
// ignore: one_member_abstracts
abstract interface class SettingsSeedResource {
  /// The callback runs only after this exact resource has been acquired.
  Future<T> access<T>(Future<T> Function(String mnemonic) read);
}

/// The existing Vault format, split at the last pre-write authority check.
abstract interface class SettingsVaultBackend {
  /// A cancelled picker returns null and admits no encryption or write.
  Future<Object?> chooseDestination();

  /// Produces the existing encrypted envelope without writing it.
  Future<Object> encrypt(String seed, String password);

  /// Awaits the original write. It must not retry an uncertain write.
  Future<void> write(Object destination, Object envelope);
}

/// Truthful progress of the original export, independent of its screen.
enum SettingsVaultOutcome {
  /// No file has been admitted yet.
  preparing,

  /// The native picker was cancelled.
  cancelled,

  /// The original write was admitted and its result is pending.
  writing,

  /// The original write future completed. This is not an atomicity claim.
  completed,

  /// Refused or failed before any write.
  refused,

  /// An admitted write threw. Its durable state is not established.
  uncertain,
}

/// Coordinates captured resources without a native or global default.
class SettingsSensitiveActions implements SettingsSensitiveSession {
  /// All dependencies are captured before the first asynchronous boundary.
  SettingsSensitiveActions({
    required this._isCurrent,
    required this.isHardwareWallet,
    required this._unlocked,
    required this._decrypt,
    required this._vault,
  });

  final bool Function() _isCurrent;
  final SettingsSeedResource? _unlocked;
  final Future<SettingsSeedResource> Function(String password) _decrypt;
  final SettingsVaultBackend _vault;
  bool _revoked = false;
  bool _exporting = false;
  SettingsVaultOutcome? _outcome;

  /// Retains the exact admitted result even after UI authority is revoked.
  SettingsVaultOutcome? get outcome => _outcome;

  @override
  final bool isHardwareWallet;

  @override
  bool get isCurrent => !_revoked && !(_revoked = !_isCurrent());

  void _require(bool Function() child) {
    if (!isCurrent || !child()) {
      throw const SecuritySettingsRefused();
    }
  }

  void _requireSeed(bool Function() child) {
    _require(child);
    if (isHardwareWallet) {
      throw const SecuritySettingsRefused();
    }
  }

  @override
  Future<List<String>> revealSeed(
    String password, {
    required bool Function() isCurrent,
  }) async {
    _requireSeed(isCurrent);
    final SettingsSeedResource original = await _decrypt(password);
    _requireSeed(isCurrent);
    final List<String> words = await original.access<List<String>>(
      (String mnemonic) async {
        _requireSeed(isCurrent);
        return List<String>.unmodifiable(mnemonic.split(' '));
      },
    );
    _requireSeed(isCurrent);
    return words;
  }

  @override
  Future<String> readExportSeed({required bool Function() isCurrent}) async {
    _requireSeed(isCurrent);
    final SettingsSeedResource? original = _unlocked;
    if (original == null) {
      throw const SecuritySettingsRefused();
    }
    final String seed = await original.access<String>((String mnemonic) async {
      _requireSeed(isCurrent);
      return mnemonic;
    });
    _requireSeed(isCurrent);
    return seed;
  }

  @override
  Future<bool> exportVault({
    required String seed,
    required String password,
    required bool Function() isCurrent,
  }) async {
    _requireSeed(isCurrent);
    if (_exporting || _outcome == SettingsVaultOutcome.uncertain) {
      throw const SecuritySettingsRefused();
    }
    _exporting = true;
    _outcome = SettingsVaultOutcome.preparing;
    bool admitted = false;
    try {
      final Object? destination = await _vault.chooseDestination();
      _requireSeed(isCurrent);
      if (destination == null) {
        _outcome = SettingsVaultOutcome.cancelled;
        return false;
      }
      final Object envelope = await _vault.encrypt(seed, password);
      _requireSeed(isCurrent);
      admitted = true;
      _outcome = SettingsVaultOutcome.writing;
      await _vault.write(destination, envelope);
      // The original write settles even if its route left while awaiting it.
      _outcome = SettingsVaultOutcome.completed;
      return true;
    } on Object {
      _outcome = admitted
          ? SettingsVaultOutcome.uncertain
          : SettingsVaultOutcome.refused;
      rethrow;
    } finally {
      _exporting = false;
    }
  }
}
