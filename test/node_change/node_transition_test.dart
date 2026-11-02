import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';

void main() {
  test('one transport owner holds quarantine until explicit completion', () {
    final int original = WalletContextRevision.value;
    final NodeTransitionLease lease = NodeChange.beginTransition()!;
    try {
      expect(lease.revision, original + 1);
      expect(WalletContextRevision.value, original + 1);
      expect(NodeChange.transitionPending, isTrue);
      expect(lease.isOwner, isTrue);
      expect(NodeChange.beginTransition(), isNull);
      expect(WalletContextRevision.value, original + 1);
      expect(lease.complete(), isTrue);
      expect(WalletContextRevision.value, original + 2);
      expect(NodeChange.transitionPending, isFalse);
      expect(lease.isOwner, isFalse);
      expect(lease.complete(), isFalse);
      expect(WalletContextRevision.value, original + 2);
    } finally {
      lease.complete();
    }
  });

  test('an old owner cannot release a replacement transport quarantine', () {
    final NodeTransitionLease original = NodeChange.beginTransition()!;
    expect(original.complete(), isTrue);
    final NodeTransitionLease replacement = NodeChange.beginTransition()!;
    try {
      final int revision = WalletContextRevision.value;
      expect(original.complete(), isFalse);
      expect(NodeChange.transitionPending, isTrue);
      expect(replacement.isOwner, isTrue);
      expect(WalletContextRevision.value, revision);
    } finally {
      replacement.complete();
    }
  });

  test('a reentrant observer cannot rewrite the expected acquisition', () {
    final int original = WalletContextRevision.value;
    bool observed = false;
    void invalidateAgain() {
      if (observed) {
        return;
      }
      observed = true;
      WalletContextRevision.invalidate();
    }

    WalletContextRevision.changes.addListener(invalidateAgain);
    NodeTransitionLease? lease;
    try {
      lease = NodeChange.beginTransition()!;
      expect(lease.revision, original + 1);
      expect(WalletContextRevision.value, original + 2);
      expect(NodeChange.transitionPending, isTrue);
      expect(lease.isOwner, isTrue);
    } finally {
      WalletContextRevision.changes.removeListener(invalidateAgain);
      lease?.complete();
    }
  });
}
