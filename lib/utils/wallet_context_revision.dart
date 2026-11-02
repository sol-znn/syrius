import 'package:flutter/foundation.dart';

/// Revokes pending confirmations before a wallet context can leave and return.
/// It contains no wallet, account, node or secret data.
abstract final class WalletContextRevision {
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// The current context generation.
  static int get value => _revision.value;

  /// Pages can discard stale paint in the same frame as authority changes.
  static ValueListenable<int> get changes => _revision;

  /// Called synchronously at an address, node, lock or session boundary.
  static void invalidate() => _revision.value++;
}
