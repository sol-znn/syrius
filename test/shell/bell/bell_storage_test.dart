import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/hive/hive_adapters.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_history.dart';

/// Writes the exact pre-bell field layout so a new reader sees real old bytes.
class _LegacyNotificationAdapter extends TypeAdapter<WalletNotification> {
  @override
  int get typeId => 100;

  @override
  WalletNotification read(BinaryReader reader) =>
      throw UnsupportedError('Fixture writer only');

  @override
  void write(BinaryWriter writer, WalletNotification value) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(value.title)
      ..writeByte(1)
      ..write(value.timestamp)
      ..writeByte(2)
      ..write(value.details)
      ..writeByte(3)
      ..write(value.type)
      ..writeByte(4)
      ..write(value.id);
  }
}

void main() {
  test(
    'reads legacy bytes, null rows and colliding timestamps by Hive key',
    () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'syrius_bell_legacy_',
      );
      Hive
        ..init(directory.path)
        ..registerAdapter(_LegacyNotificationAdapter())
        ..registerAdapter(NotificationTypeAdapter());
      try {
        Box<dynamic> box = await Hive.openBox<dynamic>('bell_legacy');
        await box.put(
          7,
          WalletNotification(
            title: 'Legacy title',
            timestamp: 10,
            details: 'Legacy detail',
            type: NotificationType.paymentSent,
            id: 3,
          ),
        );
        await box.put(
          '7',
          WalletNotification(
            title: 'Other legacy title',
            timestamp: 10,
            details: 'Other detail',
            type: NotificationType.error,
          ),
        );
        await box.add(null);
        await box.close();
        Hive.registerAdapter(WalletNotificationAdapter(), override: true);
        box = await Hive.openBox<dynamic>('bell_legacy');
        final HiveBellHistory history = HiveBellHistory(box);
        final List<BellRecord> records = history.read();
        expect(records.map((BellRecord r) => r.key), <Object>[7, '7']);
        final WalletNotification legacy = records.first.notification;
        expect(legacy.title, 'Legacy title');
        expect(legacy.details, 'Legacy detail');
        expect(legacy.id, 3);
        expect(legacy.eventKind, isNull);
        expect(legacy.walletScope, isNull);
        expect(legacy.chainId, isNull);
        expect(legacy.transactionHash, isNull);
        expect(foldBellRecords(records, '1:wallet-a'), hasLength(2));
        await history.deleteRecords(<BellRecord>[records.first]);
        expect(box.containsKey('7'), isTrue);
        expect(box.containsKey(7), isFalse);
      } finally {
        await Hive.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
