import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';

void main() {
  const SwapTermsService swapTerms = UnbuiltSwapTermsService();
  const ZapService zap = UnbuiltZapService();
  const WalletPickerService wallets = UnbuiltWalletPickerService();
  const PasswordRecoveryService recovery = UnbuiltPasswordRecoveryService();
  const PasswordChangeMigrationService passwords =
      UnbuiltPasswordChangeMigrationService();
  const OperatorModesService modes = UnbuiltOperatorModesService();
  const WalletUpdateNoticeService updates = UnbuiltWalletUpdateNoticeService();
  const BiometricUnlockService biometrics = UnbuiltBiometricUnlockService();
  const SecurityPolicyService security = UnbuiltSecurityPolicyService();
  const SporksService sporks = UnbuiltSporksService();
  const PillarAprService pillarApr = UnbuiltPillarAprService();
  final Map<Seam, Future<void> Function()> operations =
      <Seam, Future<void> Function()>{
        Seam.swapTerms: swapTerms.start,
        Seam.zapSend: zap.send,
        Seam.zapReceive: zap.receive,
        Seam.walletPicker: wallets.open,
        Seam.passwordRecovery: recovery.recover,
        Seam.passwordChangeMigration: passwords.change,
        Seam.operatorModes: modes.apply,
        Seam.walletUpdateNotice: updates.check,
        Seam.biometricUnlock: biometrics.unlock,
        Seam.autoLockOnClose: security.lockOnClose,
        Seam.wrongPasswordLimitOff: security.disableWrongPasswordLimit,
        Seam.sporks: sporks.load,
        Seam.pillarAprEstimate: pillarApr.load,
      };

  test('each missing implementation has a refusing service boundary', () {
    expect(operations.keys, unorderedEquals(Seam.values));
  });

  for (final MapEntry<Seam, Future<void> Function()> entry
      in operations.entries) {
    test('${entry.key.name} returns no invented result', () async {
      await expectLater(
        entry.value(),
        throwsA(
          isA<SeamNotBuilt>().having(
            (SeamNotBuilt error) => error.seam,
            'seam',
            entry.key,
          ),
        ),
      );
    });
  }
}
