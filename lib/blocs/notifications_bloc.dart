import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

part 'notification_writer.dart';

/// Persists events and emits transient notifications for the current session.
class NotificationsBloc extends BaseBloc<WalletNotification?> {
  /// Tests may bind inert operations without opening Hive or a native plugin.
  NotificationsBloc({
    Future<Box<dynamic>> Function()? openStore,
    bool Function(Box<dynamic> store)? ownsStore,
    this._desktopNotificationsEnabled,
    this._showDesktop,
  }) : _openStore = openStore ?? _openNotificationsStore,
       _ownsStore = ownsStore ?? _hiveOwnsStore,
       _usesHive = openStore == null && ownsStore == null;

  final Future<Box<dynamic>> Function() _openStore;
  final bool Function(Box<dynamic>) _ownsStore;
  final bool _usesHive;
  final bool? _desktopNotificationsEnabled;
  final Future<void> Function(String, String)? _showDesktop;
  final List<_NotificationWrite> _writes = <_NotificationWrite>[];
  Box<dynamic>? _store;
  bool _paused = false;
  Object? _revoked;
  StackTrace? _revokedStack;
  Future<NotificationDrainReceipt>? _drain;

  static final Expando<_NotificationStoreLane> _lanes =
      Expando<_NotificationStoreLane>();

  static Future<Box<dynamic>> _openNotificationsStore() =>
      Hive.openBox<dynamic>(kNotificationsBox);

  static bool _hiveOwnsStore(Box<dynamic> store) =>
      store.isOpen &&
      Hive.isBoxOpen(kNotificationsBox) &&
      identical(Hive.box<dynamic>(kNotificationsBox), store);

  /// Pins this owner's already-open backend without opening a Box by name.
  /// An original cannot regain authority after an observed replacement.
  bool ownsOriginalStore(Box<dynamic> store) {
    if (_paused || _revoked != null) return false;
    try {
      _bindStore(store);
      return !_paused && _revoked == null;
    } on Object {
      return false;
    }
  }

  /// Retires a replaced service owner; UI disposal alone does not retire it.
  void revokeOwnership() {
    _revoke(const NotificationWriterRefused('notification-owner-revoked'));
  }

  /// Stores the original event even if its wallet session has since closed.
  /// A late publication may suppress transient UI without losing its history.
  Future<void> addNotification(
    WalletNotification? notification, {
    bool Function()? shouldDisplay,
    Box<dynamic>? originalStore,
    bool requireOriginalStore = false,
  }) async {
    final NotificationWriteReceipt receipt = await writeNotification(
      notification,
      shouldDisplay: shouldDisplay,
      originalStore: originalStore,
      requireOriginalStore: requireOriginalStore,
    );
    if (receipt.error != null) {
      await addError(receipt.error!, receipt.stackTrace ?? StackTrace.empty);
    }
  }

  /// Reserves work before invoking any captured operation or observer.
  /// [originalStore] lets a caller bind its backend before an earlier write.
  Future<NotificationWriteReceipt> writeNotification(
    WalletNotification? notification, {
    bool Function()? shouldDisplay,
    Box<dynamic>? originalStore,
    bool requireOriginalStore = false,
  }) {
    if (_paused ||
        _revoked != null ||
        (requireOriginalStore && originalStore == null)) {
      return Future<NotificationWriteReceipt>.value(
        NotificationWriteReceipt(
          owner: this,
          store: originalStore ?? _store,
          completed: false,
          operations: const <NotificationOperationReceipt>[],
          error:
              _revoked ??
              NotificationWriterRefused(
                requireOriginalStore && originalStore == null
                    ? 'notification-original-store-absent'
                    : 'notification-writer-paused',
              ),
          stackTrace: _revokedStack,
        ),
      );
    }
    final _NotificationWrite write = _NotificationWrite();
    _writes.add(write);
    try {
      final Box<dynamic>? captured =
          originalStore ??
          _store ??
          (_usesHive && Hive.isBoxOpen(kNotificationsBox)
              ? Hive.box<dynamic>(kNotificationsBox)
              : null);
      if (captured != null) {
        write
          ..store = captured
          ..turn = _reserve(captured);
        _bindStore(captured);
      }
      if (originalStore == null) {
        final Future<Box<dynamic>> original = _openStore();
        write.open = write.observe('open', original);
      }
    } on Object catch (error, stackTrace) {
      write
        ..setupError = error
        ..setupStack = stackTrace;
    }
    // Settings and the native notification are captured before the first
    // await. SharedPrefsService itself has a replaceable static backend.
    try {
      write.show = _captureDesktopShow(notification);
    } on Object catch (error, stackTrace) {
      write
        ..displayError = error
        ..displayStack = stackTrace;
    }
    unawaited(_write(write, notification, shouldDisplay));
    return write.future;
  }

  /// Stops admission synchronously and retains one original drain Future.
  /// This pause is terminal; a fresh service owner must own future work.
  Future<NotificationDrainReceipt> pauseAndDrain() {
    final Future<NotificationDrainReceipt>? existing = _drain;
    if (existing != null) return existing;
    _paused = true;
    final Completer<NotificationDrainReceipt> completion =
        Completer<NotificationDrainReceipt>();
    _drain = completion.future;
    final List<_NotificationWrite> originals = List<_NotificationWrite>.of(
      _writes,
    );
    unawaited(_finishDrain(originals, completion));
    return completion.future;
  }

  Future<void> _finishDrain(
    List<_NotificationWrite> originals,
    Completer<NotificationDrainReceipt> completion,
  ) async {
    final List<NotificationWriteReceipt> receipts =
        <NotificationWriteReceipt>[];
    Object? error;
    StackTrace? stackTrace;
    for (final _NotificationWrite original in originals) {
      final NotificationWriteReceipt receipt = await original.future;
      receipts.add(receipt);
    }
    try {
      final Box<dynamic>? store = _store;
      if (_revoked != null) {
        Error.throwWithStackTrace(_revoked!, _revokedStack ?? StackTrace.empty);
      }
      if (store != null) _checkStore(store);
    } on Object catch (original, originalStack) {
      error ??= original;
      stackTrace ??= originalStack;
    }
    completion.complete(
      NotificationDrainReceipt(
        owner: this,
        store: _store,
        writes: receipts,
        completed: error == null,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<void> _write(
    _NotificationWrite write,
    WalletNotification? notification,
    bool Function()? shouldDisplay,
  ) async {
    Object? error;
    StackTrace? stackTrace;
    try {
      final _NotificationOperation? open = write.open;
      if (open != null) {
        final Object? opened = await open.result();
        if (opened is! Box<dynamic>) {
          throw const NotificationWriterRefused(
            'notification-store-unavailable',
          );
        }
        if (write.store != null && !identical(write.store, opened)) {
          _revoke(
            const NotificationWriterRefused('notification-store-replaced'),
          );
        }
        write.store ??= opened;
        write.turn ??= _reserve(opened);
        _bindStore(opened);
        write.store = opened;
      }
      if (write.setupError != null) {
        Error.throwWithStackTrace(write.setupError!, write.setupStack!);
      }
      final Box<dynamic> store = write.store!;
      await write.turn!.ready;
      _checkStore(store);
      while (store.length >= kNotificationsEntriesLimit) {
        _checkStore(store);
        final dynamic key = store.keys.first;
        _checkStore(store);
        final Future<void> original = store.delete(key);
        await write.observe('delete', original).result();
        _checkStore(store);
      }
      _checkStore(store);
      // Stored as finished text, so a notification keeps the language it was
      // written in: changing the language does not translate the old ones.
      final Future<int> original = store.add(notification);
      await write.observe('add', original).result();
      _checkStore(store);
      final bool display = shouldDisplay?.call() != false;
      _checkStore(store);
      if (!display) return;
      if (write.displayError != null) {
        Error.throwWithStackTrace(write.displayError!, write.displayStack!);
      }
      final Future<void> Function()? show = write.show;
      if (show != null) {
        final Future<void> original = show();
        await write.observe('display', original).result();
        _checkStore(store);
      }
      final bool emit = shouldDisplay?.call() != false;
      _checkStore(store);
      if (emit) addEvent(notification);
    } on Object catch (original, originalStack) {
      error = original;
      stackTrace = originalStack;
    } finally {
      final _NotificationTurn? turn = write.turn;
      if (turn != null) {
        // A failed open/setup still keeps its place until the predecessor
        // settles; releasing early would let a later caller overtake it.
        await turn.ready;
        turn.release();
      }
      write.complete(
        NotificationWriteReceipt(
          owner: this,
          store: write.store,
          completed: error == null && write.displayError == null,
          operations: write.operations
              .map(
                (_NotificationOperation operation) => operation.receipt!,
              )
              .toList(),
          error: error ?? write.displayError,
          stackTrace: stackTrace ?? write.displayStack,
        ),
      );
    }
  }

  _NotificationTurn _reserve(Box<dynamic> store) {
    final _NotificationStoreLane lane = _lanes[store] ??=
        _NotificationStoreLane();
    return lane.reserve();
  }

  void _bindStore(Box<dynamic> store) {
    if (_store != null && !identical(_store, store)) {
      _revoke(const NotificationWriterRefused('notification-store-replaced'));
    }
    _store ??= store;
    _checkStore(store);
  }

  void _checkStore(Box<dynamic> store) {
    if (_revoked == null) {
      try {
        if (!identical(_store, store) || !store.isOpen || !_ownsStore(store)) {
          _revoke(
            const NotificationWriterRefused('notification-store-replaced'),
          );
        }
      } on Object catch (error, stackTrace) {
        _revoke(error, stackTrace);
      }
    }
    if (_revoked != null) {
      Error.throwWithStackTrace(_revoked!, _revokedStack ?? StackTrace.empty);
    }
  }

  void _revoke(Object error, [StackTrace? stackTrace]) {
    _revoked ??= error;
    _revokedStack ??= stackTrace ?? StackTrace.current;
  }

  Future<void> Function()? _captureDesktopShow(
    WalletNotification? notification,
  ) {
    if (notification == null) return null;
    final bool enabled = _desktopNotificationsEnabled ?? _desktopEnabled();
    if (!enabled) return null;
    final AppLocalizations l10n = currentL10n;
    final String title = notification.title ?? l10n.notificationEmptyTitle;
    final String body = notification.details ?? l10n.notificationNoDetails;
    final Future<void> Function(String, String)? originalShow = _showDesktop;
    if (originalShow != null) return () => originalShow(title, body);
    final LocalNotification original = LocalNotification(
      title: title,
      body: body,
    );
    return original.show;
  }

  bool _desktopEnabled() {
    final Box<dynamic>? preferences = Hive.isBoxOpen(kSharedPrefsBox)
        ? Hive.box<dynamic>(kSharedPrefsBox)
        : null;
    final Object? value = preferences != null
        ? preferences.get(
            kEnableDesktopNotificationsKey,
            defaultValue: kEnableDesktopNotificationsDefaultValue,
          )
        : sharedPrefsService?.get(
            kEnableDesktopNotificationsKey,
            defaultValue: kEnableDesktopNotificationsDefaultValue,
          );
    return value is bool ? value : kEnableDesktopNotificationsDefaultValue;
  }

  /// Says that Plasma is about to be generated for a transaction.
  ///
  /// [purposeMessage] is the whole title, the message of a `PlasmaPurpose`
  /// (`utils/plasma_purpose.dart`): the sentence is not put together here,
  /// because one glued from an opening and a fragment cannot be translated.
  Future<void> sendPlasmaNotification(
    String purposeMessage, {
    bool Function()? shouldDisplay,
    Box<dynamic>? originalStore,
    bool requireOriginalStore = false,
  }) async {
    await addNotification(
      WalletNotification(
        title: purposeMessage,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: currentL10n.plasmaNotificationDetails,
        type: NotificationType.generatingPlasma,
      ),
      shouldDisplay: shouldDisplay,
      originalStore: originalStore,
      requireOriginalStore: requireOriginalStore,
    );
  }

  /// Stores and displays an existing flow's error with localized context.
  Future<void> addErrorNotification(Object error, String title) async {
    await addNotification(
      WalletNotification(
        title: title,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: currentL10n.notificationErrorWithDetails(title, error),
        type: NotificationType.error,
      ),
    );
  }
}
