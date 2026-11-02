import 'dart:async';

import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_controller.dart';
import 'package:zenon_syrius_wallet_flutter/services/pending_session_approval.dart';

const String testScope = '1:wallet-a';

WalletNotification event({
  String title = 'Stored event',
  int? timestamp = 100,
  String? scope,
  String? kind,
  int? chain,
  String? hash,
  NotificationType type = NotificationType.paymentSent,
}) => WalletNotification(
  title: title,
  timestamp: timestamp,
  details: 'Exact retained detail',
  type: type,
  walletScope: scope,
  eventKind: kind,
  chainId: chain,
  transactionHash: hash,
);

class MemoryBellHistory implements BellHistory {
  final Map<Object, WalletNotification> items = <Object, WalletNotification>{};
  final StreamController<BellHistoryChange> _changes =
      StreamController<BellHistoryChange>.broadcast(sync: true);
  bool failRead = false;
  void Function()? beforeDelete;

  @override
  List<BellRecord> read() {
    if (failRead) throw StateError('Read unavailable');
    return <BellRecord>[
      for (final MapEntry<Object, WalletNotification> entry in items.entries)
        BellRecord(key: entry.key, notification: entry.value),
    ];
  }

  @override
  Stream<BellHistoryChange> get changes => _changes.stream;

  void put(Object key, WalletNotification notification) {
    items[key] = notification;
    _changes.add(
      BellHistoryChange(
        key: key,
        record: BellRecord(key: key, notification: notification),
      ),
    );
  }

  @override
  Future<void> deleteRecords(Iterable<BellRecord> records) async {
    beforeDelete?.call();
    for (final BellRecord record in records) {
      final WalletNotification? current = items[record.key];
      if (current != null &&
          BellRecord(key: record.key, notification: current).identity ==
              record.identity) {
        items.remove(record.key);
        _changes.add(BellHistoryChange(key: record.key));
      }
    }
  }

  Future<void> close() => _changes.close();
}

BellController bell(
  MemoryBellHistory history, {
  String scope = testScope,
  Map<String, List<String>>? seen,
  PendingApprovalController? approvals,
}) => BellController(
  history: history,
  scope: scope,
  approvals: approvals,
  readSeen: (String key) => seen?[key] ?? <String>[],
  writeSeen: (String key, List<String> values) async {
    if (seen != null) seen[key] = values;
  },
);

/// Fake transport state makes client, scope, expiry and late results explicit.
class FakeApprovalClient {
  Object identity = Object();
  String scope = testScope;
  bool unlocked = true;
  bool fail = false;
  int approveCalls = 0;
  int declineCalls = 0;
  DateTime now = DateTime(2030, 1, 1, 12);
  Completer<void>? gate;
  final Map<int, PendingSessionApproval> proposals =
      <int, PendingSessionApproval>{};

  late final PendingApprovalController controller = PendingApprovalController(
    now: () => now,
    isCurrentContext: (PendingSessionApproval p) =>
        unlocked &&
        identical(p.clientIdentity, identity) &&
        p.walletScope == scope,
    proposalExists: (PendingSessionApproval p) => identical(proposals[p.id], p),
    approve: (PendingSessionApproval p) async {
      approveCalls++;
      await gate?.future;
      if (fail) throw StateError('Transport outcome unavailable');
      proposals.remove(p.id);
    },
    decline: (PendingSessionApproval p) async {
      declineCalls++;
      await gate?.future;
      if (fail) throw StateError('Transport outcome unavailable');
      proposals.remove(p.id);
    },
  );

  PendingSessionApproval add(int id) {
    final PendingSessionApproval proposal = PendingSessionApproval(
      id: id,
      expiresAt: now.add(const Duration(minutes: 5)),
      name: 'Example app',
      url: 'https://app.example',
      walletScope: scope,
      clientIdentity: identity,
      requiredNamespaces: <String, ApprovalNamespace>{
        'zenon': ApprovalNamespace(
          chains: const <String>['zenon:1'],
          methods: const <String>['znn_info'],
          events: const <String>['addressChange'],
        ),
      },
      optionalNamespaces: const <String, ApprovalNamespace>{},
      approvedNamespaces: <String, ApprovalNamespace>{
        'zenon': ApprovalNamespace(
          chains: const <String>['zenon:1'],
          accounts: const <String>['zenon:1:address-a', 'zenon:1:address-b'],
          methods: const <String>['znn_info'],
          events: const <String>['addressChange'],
        ),
      },
    );
    proposals[id] = proposal;
    controller.enqueue(proposal);
    return proposal;
  }
}
