import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/notification_type.dart';
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';

/// One stored event. Hive keys, unlike timestamps, are unique within the box.
class BellRecord {
  /// Retains the original storage key with its unmodified event payload.
  const BellRecord({required this.key, required this.notification});

  /// The exact Hive key used to address this stored event.
  final Object key;

  /// The retained producer payload.
  final WalletNotification notification;

  /// A local payload identity that prevents reused keys inheriting seen marks.
  String get identity {
    final List<Object?> payload = <Object?>[
      key,
      notification.timestamp,
      notification.title,
      notification.details,
      notification.type?.index,
      notification.id,
      notification.eventKind,
      notification.walletScope,
      notification.chainId,
      notification.transactionHash,
    ];
    return 'history:${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
  }
}

/// One retained-event insertion, replacement or removal.
class BellHistoryChange {
  /// Identifies a changed key and its new record, or null after removal.
  const BellHistoryChange({required this.key, this.record});

  /// The exact key that changed in the event store.
  final Object key;

  /// The new retained record, or null when this key no longer holds an event.
  final BellRecord? record;
}

/// A history boundary that also makes failed reads distinct from empty history.
abstract interface class BellHistory {
  /// Reads retained records and throws when history is unavailable.
  List<BellRecord> read();

  /// Publishes store changes without replaying the existing snapshot.
  Stream<BellHistoryChange> get changes;

  /// Deletes matching keys only while their original payload identities match.
  Future<void> deleteRecords(Iterable<BellRecord> records);
}

/// Reads legacy and current wallet notifications by their original Hive keys.
class HiveBellHistory implements BellHistory {
  /// Uses the application's existing heterogeneous notification box.
  HiveBellHistory(this.box);

  /// The existing notification box; this adapter does not own its lifecycle.
  final Box<dynamic> box;

  @override
  List<BellRecord> read() => <BellRecord>[
    for (final dynamic key in box.keys)
      if (box.get(key) case final WalletNotification notification)
        BellRecord(key: key as Object, notification: notification),
  ];

  @override
  Stream<BellHistoryChange> get changes => box.watch().map(
    (BoxEvent event) => BellHistoryChange(
      key: event.key as Object,
      record: event.deleted || event.value is! WalletNotification
          ? null
          : BellRecord(
              key: event.key as Object,
              notification: event.value as WalletNotification,
            ),
    ),
  );

  @override
  Future<void> deleteRecords(Iterable<BellRecord> records) async {
    // An explicit snapshot prevents a new event from being cleared with an old
    // panel. This boundary never touches pending connection decisions.
    for (final BellRecord record in records.toList(growable: false)) {
      final dynamic value = box.get(record.key);
      if (value is WalletNotification &&
          BellRecord(key: record.key, notification: value).identity ==
              record.identity) {
        await box.delete(record.key);
      }
    }
  }
}

/// A displayed record or an adjacent group of explicit block publications.
class BellRun {
  /// Freezes the supplied records in their existing display order.
  BellRun(Iterable<BellRecord> records)
    : records = List<BellRecord>.unmodifiable(records);

  /// The original individual records represented by this group.
  final List<BellRecord> records;

  /// The newest event used for this group's heading and timestamp.
  BellRecord get latest => records.first;

  /// Whether the group contains several publications to disclose together.
  bool get folded => records.length > 1;
}

/// Only explicitly marked, adjacent publications fold. No text or type guesses.
List<BellRun> foldBellRecords(List<BellRecord> records, String scope) {
  final List<BellRun> result = <BellRun>[];
  for (final BellRecord record in records) {
    final WalletNotification event = record.notification;
    final BellRun? previous = result.isEmpty ? null : result.last;
    if (previous != null &&
        _isPublication(event, scope) &&
        _isPublication(previous.latest.notification, scope) &&
        event.chainId == previous.latest.notification.chainId &&
        _sameDay(event.timestamp, previous.latest.notification.timestamp)) {
      result[result.length - 1] = BellRun(<BellRecord>[
        ...previous.records,
        record,
      ]);
    } else {
      result.add(BellRun(<BellRecord>[record]));
    }
  }
  return List<BellRun>.unmodifiable(result);
}

bool _isPublication(WalletNotification event, String scope) =>
    event.eventKind == 'blockPublished' &&
    event.type == NotificationType.paymentSent &&
    event.walletScope == scope &&
    event.chainId != null &&
    RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(event.transactionHash ?? '') &&
    event.timestamp != null;

bool _sameDay(int? first, int? second) {
  if (first == null || second == null) return false;
  try {
    final DateTime a = DateTime.fromMillisecondsSinceEpoch(first);
    final DateTime b = DateTime.fromMillisecondsSinceEpoch(second);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  } on Object {
    return false;
  }
}
