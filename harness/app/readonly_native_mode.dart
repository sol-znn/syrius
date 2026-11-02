import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';

import 'readonly_native_commands.dart';
import 'readonly_sdk_admission.dart';
import 'readonly_wallet_admission.dart';

/// Selects isolated native inspection explicitly, before any app owner starts.
const String harnessReadonlyNativeEnvironment = 'SYRIUS_CI_READONLY_INSPECTION';

/// A requested native inspection cannot retain the required startup scope.
class ReadonlyNativeModeRefused implements Exception {
  /// Refuses before native startup, private input or SDK initialization.
  const ReadonlyNativeModeRefused();
}

/// Absence preserves ordinary startup; every supplied value needs CI admission.
bool harnessReadonlyNativeRequested(
  Map<String, String> environment, {
  required bool windows,
  required String? presentation,
}) {
  final String? value = environment[harnessReadonlyNativeEnvironment];
  if (value == null) return false;
  if (value != 'true' ||
      !windows ||
      environment['GITHUB_ACTIONS'] != 'true' ||
      presentation != null) {
    throw const ReadonlyNativeModeRefused();
  }
  return true;
}

/// Projects only known admission refusals, without formatting original errors.
String? readonlyNativeRefusalCode(Object error) => switch (error) {
  ReadonlyNativeCommandRefused() => 'READONLY_NATIVE_COMMAND_REFUSED',
  ReadonlySdkAdmissionRefused() => 'READONLY_NATIVE_SDK_REFUSED',
  ReadonlyWalletAdmissionRefused() => 'READONLY_NATIVE_WALLET_REFUSED',
  OriginalPublicationRefused() => 'READONLY_NATIVE_PUBLICATION_REFUSED',
  _ => null,
};

/// Programmatic inspection cannot reuse or delete an ordinary profile.
void requireReadonlyNativeLaunch(
  Map<String, String> environment, {
  required bool windows,
  required String instance,
  required bool fresh,
  required String? presentation,
}) {
  if (!windows ||
      environment['GITHUB_ACTIONS'] != 'true' ||
      presentation != null ||
      fresh ||
      !RegExp(r'^ci-inspect-[a-f0-9]{24}$').hasMatch(instance)) {
    throw const ReadonlyNativeModeRefused();
  }
}

/// Readiness binds the actual process and the finite SDK admission receipt.
/// It supplies no wallet, client, socket, image or chain acceptance.
bool harnessReadonlyNativeLaunchMatches(
  Map<String, dynamic> observed,
  int? expectedPid,
) {
  final Object? admission = observed['readonlyAdmission'];
  return expectedPid != null &&
      expectedPid > 0 &&
      observed['pid'] is int &&
      observed['pid'] == expectedPid &&
      observed['harnessMode'] == 'readonly-native' &&
      observed['booted'] == true &&
      observed['readOnly'] == true &&
      admission is Map<String, dynamic> &&
      admission.length == 5 &&
      admission['schema'] is int &&
      admission['schema'] == 1 &&
      admission['scope'] == 'readonly_native_sdk_admission' &&
      admission['status'] == 'CURRENT' &&
      admission['publicationAdmissionPaused'] == true &&
      admission['automaticReceiveDisabled'] == true;
}

/// An opened-wallet reply must retain its actual process and separate scope.
/// Native qualification also needs the original actors behind this receipt.
bool harnessReadonlyNativeWalletMatches(
  Map<String, dynamic> observed,
  int? expectedPid,
) {
  final Object? wallet = observed['readonlyWallet'];
  return harnessReadonlyNativeLaunchMatches(observed, expectedPid) &&
      wallet is Map<String, dynamic> && wallet.length == 6 &&
      wallet['schema'] is int && wallet['schema'] == 1 &&
      wallet['scope'] == 'readonly_native_wallet_admission' &&
      wallet['status'] == 'CURRENT' &&
      wallet['chain'] is int && wallet['chain'] == 321 &&
      wallet['selectedIndex'] is int && wallet['selectedIndex'] == 1 &&
      wallet['nativeFrameObserved'] == true;
}
