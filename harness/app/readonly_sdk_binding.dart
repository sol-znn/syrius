import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' show Zenon;

import 'readonly_sdk_admission.dart';

/// Captures initialized original owners before a fresh profile receives input.
/// The native entrypoint must call this before reporting readiness.
Future<ReadonlySdkAdmission> sealReadonlyNativeSdk() {
  final Zenon? sdk = app.zenon;
  final SharedPrefsService? preferences = app.sharedPrefsService;
  if (sdk == null ||
      preferences == null ||
      !Hive.isBoxOpen(kSharedPrefsBox) ||
      kWalletFile != null ||
      kWalletInitCompleted) {
    throw const ReadonlySdkAdmissionRefused();
  }
  final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
  bool ownersCurrent() =>
      identical(app.zenon, sdk) &&
      app.sl.isRegistered<Zenon>() &&
      identical(app.sl.get<Zenon>(), sdk) &&
      identical(app.sharedPrefsService, preferences) &&
      box.isOpen &&
      Hive.isBoxOpen(kSharedPrefsBox) &&
      identical(Hive.box<dynamic>(kSharedPrefsBox), box);

  return ReadonlySdkAdmission.seal(
    sdkOwner: sdk,
    ownersCurrent: ownersCurrent,
    automaticDisabled: () =>
        box.get(
              kAutoReceiveKey,
              defaultValue: kAutoReceiveDefaultValue,
            ) ==
            false &&
        preferences.get(
              kAutoReceiveKey,
              defaultValue: kAutoReceiveDefaultValue,
            ) ==
            false,
    disableAutomatic: () => preferences.put(kAutoReceiveKey, false),
  );
}
