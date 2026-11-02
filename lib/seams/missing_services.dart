import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';

/// The missing two-sided offer, acceptance and quoted exchange terms.
// Existing one-sided HTLC deposit creation and joining stay available.
// ignore: one_member_abstracts
abstract interface class SwapTermsService {
  /// Refuses until a real agreement capability owns both displayed sides.
  Future<void> start();
}

/// Refuses before secrets, reads, signing, transport or persistence.
class UnbuiltSwapTermsService implements SwapTermsService {
  /// The boundary owns no wallet or network service.
  const UnbuiltSwapTermsService();

  @override
  Future<void> start() async => throw const SeamNotBuilt(Seam.swapTerms);
}

/// The missing annual-return model and its qualified chain inputs.
// Direct callers must meet the same boundary as the disabled sort control.
// ignore: one_member_abstracts
abstract interface class PillarAprService {
  /// Loads estimates only after their inputs and calculation exist.
  Future<void> load();
}

/// Refuses before a chain read or an invented return estimate.
class UnbuiltPillarAprService implements PillarAprService {
  /// Creates a service with no chain or price dependencies.
  const UnbuiltPillarAprService();

  @override
  Future<void> load() async => throw const SeamNotBuilt(Seam.pillarAprEstimate);
}

/// The missing Zap coordinator, separate from ordinary wallet transfers.
abstract interface class ZapService {
  /// Finds a recipient and sends a Zap.
  Future<void> send();

  /// Recognises incoming Zaps and exposes their message and receipt event.
  Future<void> receive();
}

/// Refuses Zap work without reading history, signing or publishing blocks.
class UnbuiltZapService implements ZapService {
  /// Creates a service with no wallet or network dependencies.
  const UnbuiltZapService();

  @override
  Future<void> send() async => throw const SeamNotBuilt(Seam.zapSend);

  @override
  Future<void> receive() async => throw const SeamNotBuilt(Seam.zapReceive);
}

/// The missing wallet catalog and switching lifecycle.
// The seam contract requires an interface and a refusing implementation.
// ignore: one_member_abstracts
abstract interface class WalletPickerService {
  /// Opens the catalog only when per-wallet state and switching are safe.
  Future<void> open();
}

/// Refuses before reading files or changing the selected wallet.
class UnbuiltWalletPickerService implements WalletPickerService {
  /// Creates a service with no storage dependencies.
  const UnbuiltWalletPickerService();

  @override
  Future<void> open() async => throw const SeamNotBuilt(Seam.walletPicker);
}

/// The missing password recovery route and its wallet ownership policy.
// A typed service boundary keeps direct activation subject to the same refusal.
// ignore: one_member_abstracts
abstract interface class PasswordRecoveryService {
  /// Opens recovery only after its ownership and secret-handling flow exists.
  Future<void> recover();
}

/// Refuses before reading secrets, changing files or starting a reset.
class UnbuiltPasswordRecoveryService implements PasswordRecoveryService {
  /// Creates a service with no wallet or storage dependencies.
  const UnbuiltPasswordRecoveryService();

  @override
  Future<void> recover() async =>
      throw const SeamNotBuilt(Seam.passwordRecovery);
}

/// The missing owned password and recovery-store migration operation.
// The route exists, but safe migration of its original stores does not.
// ignore: one_member_abstracts
abstract interface class PasswordChangeMigrationService {
  /// Changes the password only after owned recovery-store migration exists.
  Future<void> change();
}

/// Refuses before accessing a wallet, credentials, encryption or storage.
class UnbuiltPasswordChangeMigrationService
    implements PasswordChangeMigrationService {
  /// Creates a boundary without secret or persistence dependencies.
  const UnbuiltPasswordChangeMigrationService();

  @override
  Future<void> change() async =>
      throw const SeamNotBuilt(Seam.passwordChangeMigration);
}

/// The missing ownership detection and Auto / On / Off policy.
// The seam contract requires an interface and a refusing implementation.
// ignore: one_member_abstracts
abstract interface class OperatorModesService {
  /// Applies mode detection and overrides to the selected address.
  Future<void> apply();
}

/// Leaves existing Pillar and Sentinel features available.
class UnbuiltOperatorModesService implements OperatorModesService {
  /// Creates a service with no chain or preference dependencies.
  const UnbuiltOperatorModesService();

  @override
  Future<void> apply() async => throw const SeamNotBuilt(Seam.operatorModes);
}

/// The missing wallet release comparison, separate from the node updater.
// The seam contract requires an interface and a refusing implementation.
// ignore: one_member_abstracts
abstract interface class WalletUpdateNoticeService {
  /// Checks whether a newer wallet release can be announced.
  Future<void> check();
}

/// Refuses without requesting releases or claiming a version is current.
class UnbuiltWalletUpdateNoticeService implements WalletUpdateNoticeService {
  /// Creates a service with no network dependencies.
  const UnbuiltWalletUpdateNoticeService();

  @override
  Future<void> check() async =>
      throw const SeamNotBuilt(Seam.walletUpdateNotice);
}

/// The missing platform authentication and protected credential lifecycle.
// The seam contract requires an interface and a refusing implementation.
// ignore: one_member_abstracts
abstract interface class BiometricUnlockService {
  /// Unlocks the wallet using the platform's authentication facility.
  Future<void> unlock();
}

/// Refuses without accessing credentials or calling a platform API.
class UnbuiltBiometricUnlockService implements BiometricUnlockService {
  /// Creates a service with no credential or platform dependencies.
  const UnbuiltBiometricUnlockService();

  @override
  Future<void> unlock() async => throw const SeamNotBuilt(Seam.biometricUnlock);
}

/// Security choices that the existing positive-limit preferences cannot apply.
abstract interface class SecurityPolicyService {
  /// Replaces inactivity locking only after an owned close policy exists.
  Future<void> lockOnClose();

  /// Disables exhaustion only after its persistence and unlock policy exist.
  Future<void> disableWrongPasswordLimit();
}

/// Refuses without changing the current timer, attempt limit or wallet files.
class UnbuiltSecurityPolicyService implements SecurityPolicyService {
  /// Creates a boundary with no credential or preference dependencies.
  const UnbuiltSecurityPolicyService();

  @override
  Future<void> lockOnClose() async =>
      throw const SeamNotBuilt(Seam.autoLockOnClose);

  @override
  Future<void> disableWrongPasswordLimit() async =>
      throw const SeamNotBuilt(Seam.wrongPasswordLimitOff);
}

/// The missing wallet Sporks view and its chain boundary.
// The seam contract requires an interface and a refusing implementation.
// ignore: one_member_abstracts
abstract interface class SporksService {
  /// Loads Sporks for the connected chain.
  Future<void> load();
}

/// Refuses without reading or changing chain state.
class UnbuiltSporksService implements SporksService {
  /// Creates a service with no chain dependencies.
  const UnbuiltSporksService();

  @override
  Future<void> load() async => throw const SeamNotBuilt(Seam.sporks);
}
