import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

class _Store extends Fake implements Box<dynamic> {
  final Map<dynamic, dynamic> entries = <dynamic, dynamic>{};
  final List<String> calls = <String>[];
  final List<Future<int>> additions = <Future<int>>[];
  final List<Future<void>> deletions = <Future<void>>[];
  Future<int> Function(dynamic value)? addOperation;
  Future<void> Function(dynamic key)? deleteOperation;
  void Function()? onLength;
  int nextKey = 0;
  bool open = true;

  @override
  bool get isOpen => open;

  @override
  int get length {
    onLength?.call();
    return entries.length;
  }

  @override
  Iterable<dynamic> get keys => entries.keys;

  @override
  Future<int> add(dynamic value) {
    calls.add('add:${(value as WalletNotification?)?.title}');
    final Future<int> original = addOperation?.call(value) ?? store(value);
    additions.add(original);
    return original;
  }

  Future<int> store(dynamic value) {
    final int key = nextKey++;
    entries[key] = value;
    return Future<int>.value(key);
  }

  @override
  Future<void> delete(dynamic key) {
    calls.add('delete:$key');
    final Future<void> original;
    if (deleteOperation != null) {
      original = deleteOperation!(key);
    } else {
      entries.remove(key);
      original = Future<void>.value();
    }
    deletions.add(original);
    return original;
  }

  void fill() {
    for (int key = 0; key < kNotificationsEntriesLimit; key++) {
      entries[key] = key;
    }
    nextKey = kNotificationsEntriesLimit;
  }
}

class _Preferences extends SharedPrefsService {
  _Preferences({required this.enabled});

  bool enabled;
  int reads = 0;

  @override
  dynamic get(String key, {dynamic defaultValue}) {
    reads++;
    return enabled;
  }
}

WalletNotification _event(String title) => WalletNotification(
  title: title,
  details: 'Original publication',
  type: NotificationType.paymentSent,
  timestamp: 1,
);

NotificationsBloc _writer(
  _Store store, {
  Future<Box<dynamic>> Function()? openStore,
  bool Function(Box<dynamic>)? ownsStore,
  bool desktopNotificationsEnabled = false,
  Future<void> Function(String, String)? showDesktop,
}) {
  final NotificationsBloc bloc = NotificationsBloc(
    openStore: openStore ?? () => Future<Box<dynamic>>.value(store),
    ownsStore:
        ownsStore ?? (Box<dynamic> original) => identical(original, store),
    desktopNotificationsEnabled: desktopNotificationsEnabled,
    showDesktop: showDesktop,
  );
  addTearDown(bloc.dispose);
  return bloc;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'missing explicitly required original store never opens a later Box',
    () async {
      final _Store replacement = _Store();
      int opens = 0;
      final NotificationsBloc bloc = _writer(
        replacement,
        openStore: () {
          opens++;
          return Future<Box<dynamic>>.value(replacement);
        },
      );
      final NotificationWriteReceipt receipt = await bloc.writeNotification(
        _event('Original unavailable'),
        requireOriginalStore: true,
      );
      expect(receipt.completed, isFalse);
      expect(receipt.error, isA<NotificationWriterRefused>());
      expect(receipt.store, isNull);
      expect(receipt.operations, isEmpty);
      expect(opens, 0);
      expect(replacement.entries, isEmpty);
    },
  );

  test('pause retains the original open and add and waits for both', () async {
    final _Store store = _Store();
    final Completer<Box<dynamic>> opened = Completer<Box<dynamic>>();
    final Completer<int> added = Completer<int>();
    int opens = 0;
    store.addOperation = (dynamic value) {
      store.entries[7] = value;
      return added.future;
    };
    final NotificationsBloc bloc = _writer(
      store,
      openStore: () {
        opens++;
        return opened.future;
      },
    );
    final WalletNotification event = _event('Original');
    final Future<NotificationWriteReceipt> write = bloc.writeNotification(
      event,
    );
    final Future<NotificationDrainReceipt> drain = bloc.pauseAndDrain();
    expect(bloc.pauseAndDrain(), same(drain));
    bool finished = false;
    unawaited(
      drain.then<void>((NotificationDrainReceipt _) {
        finished = true;
      }),
    );
    final NotificationWriteReceipt refused = await bloc.writeNotification(
      _event('Late'),
    );
    expect(refused.completed, isFalse);
    expect(refused.error, isA<NotificationWriterRefused>());
    expect(opens, 1);
    expect(store.calls, isEmpty);
    await _settle();
    expect(finished, isFalse);
    opened.complete(store);
    await _settle();
    expect(store.calls, <String>['add:Original']);
    expect(finished, isFalse);
    added.complete(7);
    final NotificationWriteReceipt written = await write;
    final NotificationDrainReceipt paused = await drain;
    expect(written.completed, isTrue);
    expect(written.store, same(store));
    expect(
      written.operations.map((NotificationOperationReceipt r) => r.name),
      <String>['open', 'add'],
    );
    expect(written.operations[0].future, same(opened.future));
    expect(written.operations[0].result, same(store));
    expect(written.operations[1].future, same(added.future));
    expect(written.operations[1].result, 7);
    expect(paused.owner, same(bloc));
    expect(paused.store, same(store));
    expect(paused.completed, isTrue);
    expect(paused.writes, <NotificationWriteReceipt>[written]);
    expect(store.entries.values, <WalletNotification>[event]);
    expect(paused.writes.clear, throwsUnsupportedError);
    expect(written.operations.clear, throwsUnsupportedError);
  });

  test(
    'a reentrant open observer sees reserved work and closed admission',
    () async {
      final _Store store = _Store();
      final Completer<Box<dynamic>> opened = Completer<Box<dynamic>>();
      late NotificationsBloc bloc;
      Future<NotificationDrainReceipt>? observedDrain;
      Future<NotificationWriteReceipt>? refused;
      bloc = _writer(
        store,
        openStore: () {
          observedDrain = bloc.pauseAndDrain();
          refused = bloc.writeNotification(_event('Reentrant'));
          return opened.future;
        },
      );
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        _event('Reserved'),
      );
      expect(bloc.pauseAndDrain(), same(observedDrain));
      expect((await refused!).completed, isFalse);
      opened.complete(store);
      final NotificationWriteReceipt receipt = await write;
      final NotificationDrainReceipt drain = await observedDrain!;
      expect(receipt.completed, isTrue);
      expect(drain.completed, isTrue);
      expect(drain.writes, <NotificationWriteReceipt>[receipt]);
      expect(store.calls, <String>['add:Reserved']);
    },
  );

  test('an explicitly captured store bypasses opening by name', () async {
    final _Store store = _Store();
    int opens = 0;
    final NotificationsBloc bloc = _writer(
      store,
      openStore: () {
        opens++;
        throw StateError('Unexpected open');
      },
    );
    expect(bloc.ownsOriginalStore(store), isTrue);
    final NotificationWriteReceipt receipt = await bloc.writeNotification(
      _event('Captured'),
      originalStore: store,
      shouldDisplay: () => false,
    );
    expect(opens, 0);
    expect(receipt.completed, isTrue);
    expect(receipt.operations.single.name, 'add');
    expect(receipt.operations.single.future, same(store.additions.single));
    expect((await bloc.pauseAndDrain()).completed, isTrue);
    expect(bloc.ownsOriginalStore(store), isFalse);
  });

  test(
    'same-Box owners serialize retention before reentrant observers',
    () async {
      final _Store store = _Store()..fill();
      final Completer<void> deleted = Completer<void>();
      store.deleteOperation = (dynamic key) {
        if (key == 0) {
          return deleted.future.then<void>((dynamic _) {
            store.entries.remove(key);
          });
        }
        store.entries.remove(key);
        return Future<void>.value();
      };
      final NotificationsBloc first = _writer(store);
      final NotificationsBloc second = _writer(store);
      Future<NotificationWriteReceipt>? secondWrite;
      store.onLength = () {
        store.onLength = null;
        secondWrite = second.writeNotification(
          _event('Second'),
          originalStore: store,
          shouldDisplay: () => false,
        );
      };
      final Future<NotificationWriteReceipt> firstWrite = first
          .writeNotification(
            _event('First'),
            originalStore: store,
            shouldDisplay: () => false,
          );
      await _settle();
      expect(secondWrite, isNotNull);
      expect(store.calls, <String>['delete:0']);
      deleted.complete();
      final NotificationWriteReceipt firstReceipt = await firstWrite;
      final NotificationWriteReceipt secondReceipt = await secondWrite!;
      expect(firstReceipt.completed, isTrue);
      expect(secondReceipt.completed, isTrue);
      expect(store.calls, <String>[
        'delete:0',
        'add:First',
        'delete:1',
        'add:Second',
      ]);
      expect(store.entries.length, kNotificationsEntriesLimit);
      expect(store.entries.containsKey(0), isFalse);
      expect(store.entries.containsKey(1), isFalse);
      expect(firstReceipt.operations.first.future, same(store.deletions.first));
      expect(secondReceipt.operations.first.future, same(store.deletions.last));
    },
  );

  test(
    'the Box lane is reserved before its ownership observer reenters',
    () async {
      final _Store store = _Store();
      final NotificationsBloc second = _writer(store);
      Future<NotificationWriteReceipt>? reentrant;
      final NotificationsBloc first = _writer(
        store,
        ownsStore: (Box<dynamic> original) {
          reentrant ??= second.writeNotification(
            _event('Second'),
            originalStore: store,
          );
          return identical(original, store);
        },
      );
      final NotificationWriteReceipt receipt = await first.writeNotification(
        _event('First'),
        originalStore: store,
      );
      expect(receipt.completed, isTrue);
      expect((await reentrant!).completed, isTrue);
      expect(store.calls, <String>['add:First', 'add:Second']);
    },
  );

  test('a failed original delete is retained and prevents an add', () async {
    final _Store store = _Store()..fill();
    final Completer<void> deleted = Completer<void>();
    store.deleteOperation = (dynamic _) => deleted.future;
    final NotificationsBloc bloc = _writer(store);
    final Object failure = StateError('Original delete failure');
    final StackTrace trace = StackTrace.fromString('original-delete');
    final Future<NotificationWriteReceipt> write = bloc.writeNotification(
      _event('Failure'),
      originalStore: store,
    );
    final Future<NotificationDrainReceipt> drain = bloc.pauseAndDrain();
    await _settle();
    deleted.completeError(failure, trace);
    final NotificationWriteReceipt receipt = await write;
    expect(receipt.completed, isFalse);
    expect(receipt.error, same(failure));
    expect(receipt.operations.single.name, 'delete');
    expect(receipt.operations.single.future, same(deleted.future));
    expect(receipt.operations.single.error, same(failure));
    expect(receipt.operations.single.stackTrace.toString(), trace.toString());
    expect(store.calls, <String>['delete:0']);
    final NotificationDrainReceipt paused = await drain;
    expect(paused.completed, isTrue);
    expect(paused.error, isNull);
    expect(paused.writes.single.error, same(failure));
  });

  test(
    'a failed queued open cannot release a later write past its predecessor',
    () async {
      final _Store store = _Store();
      final Completer<int> added = Completer<int>();
      int attempts = 0;
      store.addOperation = (dynamic value) =>
          ++attempts == 1 ? added.future : store.store(value);
      final Completer<Box<dynamic>> opened = Completer<Box<dynamic>>();
      final NotificationsBloc first = _writer(store);
      final NotificationsBloc failed = _writer(
        store,
        openStore: () => opened.future,
      );
      final NotificationsBloc last = _writer(store);
      expect(failed.ownsOriginalStore(store), isTrue);
      final Future<NotificationWriteReceipt> firstWrite = first
          .writeNotification(
            _event('First'),
            originalStore: store,
          );
      final Future<NotificationWriteReceipt> failedWrite = failed
          .writeNotification(_event('Failed open'));
      final Future<NotificationWriteReceipt> lastWrite = last.writeNotification(
        _event('Last'),
        originalStore: store,
      );
      final Object failure = StateError('Queued open failure');
      opened.completeError(failure, StackTrace.fromString('queued-open'));
      await _settle();
      expect(store.calls, <String>['add:First']);
      added.complete(0);
      expect((await firstWrite).completed, isTrue);
      expect((await failedWrite).error, same(failure));
      expect((await lastWrite).completed, isTrue);
      expect(store.calls, <String>['add:First', 'add:Last']);
    },
  );

  test(
    'a failed add does not hide its error when queued work succeeds',
    () async {
      final _Store store = _Store();
      final Completer<int> added = Completer<int>();
      int attempts = 0;
      store.addOperation = (dynamic value) =>
          ++attempts == 1 ? added.future : store.store(value);
      final NotificationsBloc bloc = _writer(store);
      final Object failure = StateError('Original add failure');
      final Future<NotificationWriteReceipt> first = bloc.writeNotification(
        _event('Failed'),
        originalStore: store,
      );
      final Future<NotificationWriteReceipt> second = bloc.writeNotification(
        _event('Succeeded'),
        originalStore: store,
      );
      final Future<NotificationDrainReceipt> drain = bloc.pauseAndDrain();
      await _settle();
      added.completeError(failure, StackTrace.fromString('original-add'));
      final NotificationWriteReceipt failed = await first;
      final NotificationWriteReceipt succeeded = await second;
      final NotificationDrainReceipt paused = await drain;
      expect(failed.operations.single.future, same(added.future));
      expect(failed.operations.single.error, same(failure));
      expect(succeeded.completed, isTrue);
      expect(paused.completed, isTrue);
      expect(paused.error, isNull);
      expect(paused.writes, <NotificationWriteReceipt>[failed, succeeded]);
      expect(store.calls, <String>['add:Failed', 'add:Succeeded']);
    },
  );

  test(
    'an original open failure is retained without touching a store',
    () async {
      final _Store store = _Store();
      final Completer<Box<dynamic>> opened = Completer<Box<dynamic>>();
      final NotificationsBloc bloc = _writer(
        store,
        openStore: () => opened.future,
      );
      final Object failure = StateError('Original open failure');
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        _event('Failure'),
      );
      final Future<NotificationDrainReceipt> drain = bloc.pauseAndDrain();
      opened.completeError(failure, StackTrace.fromString('original-open'));
      final NotificationWriteReceipt receipt = await write;
      expect(receipt.completed, isFalse);
      expect(receipt.operations.single.name, 'open');
      expect(receipt.operations.single.future, same(opened.future));
      expect(receipt.operations.single.error, same(failure));
      expect(store.calls, isEmpty);
      final NotificationDrainReceipt paused = await drain;
      expect(paused.completed, isTrue);
      expect(paused.writes.single.error, same(failure));
    },
  );

  test(
    'display uses captured permission and retains its original Future',
    () async {
      final SharedPrefsService? previous = app.sharedPrefsService;
      addTearDown(() => app.sharedPrefsService = previous);
      final _Preferences preferences = _Preferences(enabled: true);
      app.sharedPrefsService = preferences;
      final _Store store = _Store();
      final Completer<int> added = Completer<int>();
      final Completer<void> displayed = Completer<void>();
      store.addOperation = (dynamic value) {
        store.entries[4] = value;
        return added.future;
      };
      final List<String> titles = <String>[];
      final NotificationsBloc bloc = NotificationsBloc(
        openStore: () => Future<Box<dynamic>>.value(store),
        ownsStore: (Box<dynamic> original) => identical(original, store),
        showDesktop: (String title, String body) {
          titles.add(title);
          expect(body, 'Original publication');
          return displayed.future;
        },
      );
      addTearDown(bloc.dispose);
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        _event('Captured display'),
        originalStore: store,
      );
      final Future<NotificationDrainReceipt> drain = bloc.pauseAndDrain();
      bool drained = false;
      unawaited(
        drain.then<void>((NotificationDrainReceipt _) {
          drained = true;
        }),
      );
      preferences.enabled = false;
      app.sharedPrefsService = _Preferences(enabled: false);
      added.complete(4);
      await _settle();
      expect(preferences.reads, 1);
      expect(titles, <String>['Captured display']);
      expect(drained, isFalse);
      displayed.complete();
      final NotificationWriteReceipt receipt = await write;
      expect(receipt.completed, isTrue);
      expect(receipt.operations.last.name, 'display');
      expect(receipt.operations.last.future, same(displayed.future));
      expect((await drain).completed, isTrue);
    },
  );

  test(
    'a failed original native display keeps history and its exact error',
    () async {
      final _Store store = _Store();
      final Completer<void> displayed = Completer<void>();
      final NotificationsBloc bloc = _writer(
        store,
        desktopNotificationsEnabled: true,
        showDesktop: (String _, String _) => displayed.future,
      );
      final WalletNotification event = _event('Display failure');
      final Object failure = StateError('Original display failure');
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        event,
        originalStore: store,
      );
      await _settle();
      displayed.completeError(
        failure,
        StackTrace.fromString('original-display'),
      );
      final NotificationWriteReceipt receipt = await write;
      expect(receipt.completed, isFalse);
      expect(receipt.error, same(failure));
      expect(receipt.operations.last.future, same(displayed.future));
      expect(receipt.operations.last.error, same(failure));
      expect(store.entries.values, <WalletNotification>[event]);
      final NotificationDrainReceipt paused = await bloc.pauseAndDrain();
      expect(paused.completed, isTrue);
      expect(paused.writes.single.error, same(failure));
    },
  );

  test(
    'view disposal keeps admitted history while its UI guard closes',
    () async {
      final _Store store = _Store();
      final Completer<int> added = Completer<int>();
      store.addOperation = (dynamic value) {
        store.entries[1] = value;
        return added.future;
      };
      final NotificationsBloc bloc = _writer(store);
      final List<WalletNotification?> events = <WalletNotification?>[];
      final StreamSubscription<WalletNotification?> subscription = bloc.stream
          .listen(events.add);
      addTearDown(subscription.cancel);
      bool current = true;
      final WalletNotification event = _event('Published before disposal');
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        event,
        originalStore: store,
        shouldDisplay: () => current,
      );
      await _settle();
      current = false;
      bloc.dispose();
      added.complete(1);
      final NotificationWriteReceipt receipt = await write;
      expect(receipt.completed, isTrue);
      expect(store.entries.values, <WalletNotification>[event]);
      expect(events, isEmpty);
      expect((await bloc.pauseAndDrain()).completed, isTrue);
    },
  );

  test(
    'an observed replacement remains revoked when the original returns',
    () async {
      final _Store original = _Store();
      final _Store replacement = _Store();
      Box<dynamic> current = original;
      final Completer<int> added = Completer<int>();
      original.addOperation = (dynamic _) => added.future;
      final NotificationsBloc bloc = _writer(
        original,
        ownsStore: (Box<dynamic> store) => identical(current, store),
      );
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        _event('Original'),
        originalStore: original,
      );
      await _settle();
      current = replacement;
      added.complete(1);
      final NotificationWriteReceipt receipt = await write;
      expect(receipt.completed, isFalse);
      expect(receipt.error, isA<NotificationWriterRefused>());
      current = original;
      expect(bloc.ownsOriginalStore(original), isFalse);
      final NotificationWriteReceipt refused = await bloc.writeNotification(
        _event('Returned original'),
        originalStore: original,
      );
      expect(refused.error, same(receipt.error));
      expect(original.calls, <String>['add:Original']);
      expect(replacement.calls, isEmpty);
      expect((await bloc.pauseAndDrain()).completed, isFalse);
    },
  );

  test(
    'a replacement during open cannot redirect the captured operation',
    () async {
      final _Store original = _Store();
      final _Store replacement = _Store();
      Box<dynamic> current = original;
      final Completer<Box<dynamic>> opened = Completer<Box<dynamic>>();
      final NotificationsBloc bloc = _writer(
        original,
        openStore: () => opened.future,
        ownsStore: (Box<dynamic> store) => identical(current, store),
      );
      final Future<NotificationWriteReceipt> write = bloc.writeNotification(
        _event('Original'),
      );
      current = replacement;
      opened.complete(original);
      final NotificationWriteReceipt receipt = await write;
      expect(receipt.completed, isFalse);
      expect(receipt.store, same(original));
      expect(receipt.operations.single.future, same(opened.future));
      expect(receipt.operations.single.result, same(original));
      expect(original.calls, isEmpty);
      expect(replacement.calls, isEmpty);
      current = original;
      expect(bloc.ownsOriginalStore(original), isFalse);
    },
  );

  test(
    'explicit service retirement is terminal without retiring UI history',
    () async {
      final _Store store = _Store();
      final NotificationsBloc bloc = _writer(store);
      expect(bloc.ownsOriginalStore(store), isTrue);
      bloc.revokeOwnership();
      expect(bloc.ownsOriginalStore(store), isFalse);
      final NotificationWriteReceipt refused = await bloc.writeNotification(
        _event('Retired'),
        originalStore: store,
      );
      expect(refused.completed, isFalse);
      expect(store.calls, isEmpty);
      final NotificationDrainReceipt drain = await bloc.pauseAndDrain();
      expect(drain.completed, isFalse);
      expect(drain.error, same(refused.error));
    },
  );

  test(
    'a closed explicitly captured backend is refused before opening',
    () async {
      final _Store store = _Store()..open = false;
      int opens = 0;
      final NotificationsBloc bloc = _writer(
        store,
        openStore: () {
          opens++;
          return Future<Box<dynamic>>.value(store);
        },
      );
      final NotificationWriteReceipt refused = await bloc.writeNotification(
        _event('Closed backend'),
        originalStore: store,
      );
      expect(refused.completed, isFalse);
      expect(refused.error, isA<NotificationWriterRefused>());
      expect(refused.operations, isEmpty);
      expect(opens, 0);
      expect(store.calls, isEmpty);
      store.open = true;
      expect(bloc.ownsOriginalStore(store), isFalse);
      expect((await bloc.pauseAndDrain()).completed, isFalse);
    },
  );
}
