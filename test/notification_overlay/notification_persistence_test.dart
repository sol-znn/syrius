import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/hive/hive_adapters.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

class _Preferences extends SharedPrefsService {
  @override
  dynamic get(String key, {dynamic defaultValue}) => false;
}

void main() {
  late NotificationsBloc bloc;
  late Box<dynamic> history;
  late SharedPrefsService? previous;
  late StreamSubscription<WalletNotification?> subscription;
  late List<WalletNotification?> displayed;

  setUp(() async {
    previous = app.sharedPrefsService;
    app.sharedPrefsService = _Preferences();
    Hive
      ..init('notification-display-guards')
      ..registerAdapter(WalletNotificationAdapter(), override: true)
      ..registerAdapter(NotificationTypeAdapter(), override: true);
    history = await Hive.openBox<dynamic>(
      kNotificationsBox,
      bytes: Uint8List(0),
    );
    bloc = NotificationsBloc();
    displayed = <WalletNotification?>[];
    subscription = bloc.stream.listen(displayed.add);
  });

  tearDown(() async {
    await subscription.cancel();
    bloc.dispose();
    await Hive.close();
    app.sharedPrefsService = previous;
  });

  WalletNotification published() => WalletNotification(
    title: 'Block published',
    details: 'Accepted fixture publication',
    type: NotificationType.paymentSent,
    timestamp: 1,
    eventKind: 'blockPublished',
    walletScope: '321:test-wallet',
    chainId: 321,
    transactionHash: List<String>.filled(64, 'a').join(),
  );

  test(
    'a closed session preserves its exact history without transient UI',
    () async {
      final WalletNotification event = published();
      await bloc.addNotification(event, shouldDisplay: () => false);
      await Future<void>.delayed(Duration.zero);
      expect(history.values, <WalletNotification>[event]);
      expect(displayed, isEmpty);
    },
  );

  test(
    'display is checked again after persistence and before the stream',
    () async {
      int checks = 0;
      final WalletNotification event = published();
      await bloc.addNotification(event, shouldDisplay: () => ++checks == 1);
      await Future<void>.delayed(Duration.zero);
      expect(checks, 2);
      expect(history.values, <WalletNotification>[event]);
      expect(displayed, isEmpty);
    },
  );

  test(
    'the current session still receives the same persisted event once',
    () async {
      final WalletNotification event = published();
      await bloc.addNotification(event, shouldDisplay: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(history.values, <WalletNotification>[event]);
      expect(displayed, <WalletNotification>[event]);
    },
  );
}
