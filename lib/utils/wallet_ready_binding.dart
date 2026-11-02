import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The already initialized wallet that completed this onboarding route.
/// No address is derived, decrypted or loaded by this display capability.
class WalletReadyBinding {
  /// Supplies an immutable first address and an exact owner check.
  WalletReadyBinding({
    required this.firstAddress,
    required this._isCurrent,
    this.transportQuarantined = false,
  });

  /// Captures index zero only after initialization of the original file.
  static WalletReadyBinding? capture({WalletFile? expectedFile}) {
    final WalletFile? file = kWalletFile;
    final String? path = kWalletPath;
    final List<String?> members = List<String?>.of(kDefaultAddressList);
    final int revision = WalletContextRevision.value;
    final String? node = kCurrentNode;
    final int? chain = kNodeChainId;
    final bool quarantined = NodeTransitions.pending;
    if (file == null ||
        (expectedFile != null && !identical(file, expectedFile)) ||
        path == null ||
        path != file.walletPath ||
        !kWalletInitCompleted ||
        members.isEmpty ||
        members.first == null) {
      return null;
    }
    final String first = members.first!;
    try {
      if (Address.parse(first).toString() != first) return null;
    } on Object {
      return null;
    }
    return WalletReadyBinding(
      firstAddress: first,
      transportQuarantined: quarantined,
      isCurrent: () =>
          identical(file, kWalletFile) &&
          path == kWalletPath &&
          kWalletInitCompleted &&
          quarantined == NodeTransitions.pending &&
          revision == WalletContextRevision.value &&
          node == kCurrentNode &&
          chain == kNodeChainId &&
          listEquals(members, kDefaultAddressList),
    );
  }

  /// Index zero from successful initialization, never the selected account.
  final String firstAddress;

  /// Local display readiness grants no authority to release this quarantine.
  final bool transportQuarantined;
  final bool Function() _isCurrent;
  bool _revoked = false;
  bool _opened = false;

  /// Observing a departed source permanently retires this capability.
  bool get isCurrent {
    if (_revoked || _opened) return false;
    try {
      if (!_isCurrent()) _revoked = true;
    } on Object {
      _revoked = true;
    }
    return !_revoked;
  }

  /// Reserves the only navigation before any route observer can re-enter it.
  bool takeOpening() {
    if (!isCurrent) return false;
    _opened = true;
    return true;
  }
}
