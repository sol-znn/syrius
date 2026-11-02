import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The original account and unlocked session for an explicit wallet action.
/// A file's acquisition mutex does not establish that a session is unlocked.
class WalletActionContext {
  WalletActionContext._(this.ownerAddress, this.client, this._file)
    : _revision = WalletContextRevision.value,
      _node = kCurrentNode,
      _nodeChain = kNodeChainId,
      _chain = getChainIdentifier(),
      _walletPath = kWalletPath,
      _addresses = List<String?>.of(kDefaultAddressList);

  /// Captures only the currently selected account of an initialized wallet.
  static WalletActionContext? capture(String ownerAddress) {
    final Zenon? client = app.zenon;
    final WalletFile? file = kWalletFile;
    if (NodeTransitions.pending ||
        client == null ||
        file == null ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        kSelectedAddress != ownerAddress ||
        !kDefaultAddressList.contains(ownerAddress)) {
      return null;
    }
    return WalletActionContext._(ownerAddress, client, file);
  }

  /// The exact account that the original action names.
  final String ownerAddress;

  /// All later reads keep the original transport.
  final Zenon client;
  final WalletFile _file;
  final int _revision;
  final String? _node;
  final int? _nodeChain;
  final int _chain;
  final String? _walletPath;
  final List<String?> _addresses;
  bool _revoked = false;

  /// Once a captured context leaves, returning cannot revive its authority.
  bool get isCurrent {
    if (_revoked) return false;
    return !(_revoked =
        NodeTransitions.pending ||
        _revision != WalletContextRevision.value ||
        !identical(client, app.zenon) ||
        !identical(_file, kWalletFile) ||
        !kWalletInitCompleted ||
        kCurrentPage == Tabs.lock ||
        kSelectedAddress != ownerAddress ||
        !listEquals(_addresses, kDefaultAddressList) ||
        _walletPath != kWalletPath ||
        _node != kCurrentNode ||
        _nodeChain != kNodeChainId ||
        _chain != getChainIdentifier());
  }

  /// Refuses before signing or transport, without replacing an original result.
  void requireCurrent() {
    if (!isCurrent) {
      throw FailureException(message: currentL10n.publicationSessionChanged);
    }
  }
}
