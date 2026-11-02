import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';

/// Quarantines publication while the shared transport has no committed owner.
abstract final class NodeTransitions {
  static NodeTransitionLease? _active;

  /// An unfinished or uncertain transition keeps publication closed.
  static bool get pending => _active != null;

  /// Only one original transition can move the shared transport at a time.
  static NodeTransitionLease? begin() {
    if (_active != null) {
      return null;
    }
    final NodeTransitionLease lease = NodeTransitionLease._(
      WalletContextRevision.value + 1,
    );
    _active = lease;
    // A context that missed the temporary hold must still observe its exit.
    WalletContextRevision.invalidate();
    return lease;
  }
}

/// The original transport owner must verify commit or restoration explicitly.
/// There is no timeout, automatic release or disposal-based success.
class NodeTransitionLease {
  NodeTransitionLease._(this.revision);

  /// The single expected acquisition increment, before synchronous observers.
  final int revision;

  /// A saved owner cannot release another transition's quarantine.
  bool get isOwner => identical(NodeTransitions._active, this);

  /// Call only after verifying the committed or restored original transport.
  /// The caller binds the expected next revision before synchronous observers.
  bool complete() {
    if (!isOwner) {
      return false;
    }
    NodeTransitions._active = null;
    WalletContextRevision.invalidate();
    return true;
  }
}
