import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/utils/window_chrome.dart';

class _Window implements AppWindowBackend {
  final List<String> calls = <String>[];
  final List<WindowListener> listeners = <WindowListener>[];
  bool maximized = false;
  Future<bool> Function()? query;
  Future<void> Function()? maximizeEffect;
  Future<void> Function()? minimizeEffect;
  Future<void> Function()? closeEffect;

  @override
  void addListener(WindowListener listener) => listeners.add(listener);

  @override
  void removeListener(WindowListener listener) => listeners.remove(listener);

  @override
  Future<bool> isMaximized() {
    calls.add('query');
    return query?.call() ?? Future<bool>.value(maximized);
  }

  @override
  Future<void> maximize() {
    calls.add('maximize');
    return maximizeEffect?.call() ?? Future<void>.value();
  }

  @override
  Future<void> unmaximize() async => calls.add('unmaximize');

  @override
  Future<void> minimize() {
    calls.add('minimize');
    return minimizeEffect?.call() ?? Future<void>.value();
  }

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<void> popUpWindowMenu() async => calls.add('menu');

  @override
  Future<void> close() {
    calls.add('close');
    return closeEffect?.call() ?? Future<void>.value();
  }
}

Future<void> _flush() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.value();
  }
}

void main() {
  test(
    'immutable status retains one opaque owner through pending and disposal',
    () async {
      final Completer<void> effect = Completer<void>();
      final _Window original = _Window()..minimizeEffect = () => effect.future;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      final AppWindowStatus before = owner.status;
      final Future<void> pending = owner.minimize();
      final AppWindowStatus during = owner.status;
      expect(during.owner, same(before.owner));
      expect(before.actionPending, isFalse);
      expect(during.actionPending, isTrue);
      owner.dispose();
      effect.complete();
      await pending;
      expect(owner.status.owner, same(before.owner));
      expect(owner.status.attached, isFalse);
      expect(owner.status.actionPending, isFalse);
      expect(during.actionPending, isTrue);
    },
  );

  test(
    'retains one original listener and removes it on disposal',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      expect(original.listeners.single, same(owner));
      await _flush();
      expect(owner.maximized, isFalse);
      owner
        ..dispose()
        ..dispose();
      expect(original.listeners, isEmpty);
      expect(original.calls, <String>['query']);
    },
  );

  test(
    'initial query failure preserves independent close and minimize',
    () async {
      final _Window original = _Window()
        ..query = () => Future<bool>.error(
          StateError('Synthetic private query'),
        );
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      expect(owner.queryFailed, isTrue);
      expect(owner.canToggleMaximize, isFalse);
      expect(owner.canMinimize, isTrue);
      expect(owner.canClose, isTrue);
      await owner.minimize();
      await owner.close();
      expect(original.calls, <String>['query', 'minimize', 'close']);
      owner.dispose();
    },
  );

  test(
    'a fresh positive observation determines restore, not old state',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      expect(owner.maximized, isFalse);
      original.maximized = true;
      await owner.toggleMaximize();
      expect(original.calls, <String>['query', 'query', 'unmaximize', 'query']);
      // The fake void acknowledgement leaves actual mode unchanged.
      expect(owner.maximized, isTrue);
      owner.dispose();
    },
  );

  test(
    'maximize acknowledgement cannot invent a maximized observation',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      await owner.toggleMaximize();
      expect(original.calls, <String>['query', 'query', 'maximize', 'query']);
      expect(owner.maximized, isFalse);
      owner.dispose();
    },
  );

  test(
    'unknown fresh query never submits a toggle or retries itself',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      original.query = () => Future<bool>.error(StateError('Synthetic query'));
      await owner.toggleMaximize();
      await _flush();
      expect(original.calls, <String>['query', 'query']);
      expect(owner.maximized, isNull);
      expect(owner.canMinimize, isTrue);
      expect(owner.canClose, isTrue);
      owner.dispose();
    },
  );

  test(
    'pending original toggle excludes conflicting native mutations',
    () async {
      final Completer<void> effect = Completer<void>();
      final _Window original = _Window()..maximizeEffect = () => effect.future;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      final Future<void> pending = owner.toggleMaximize();
      await _flush();
      expect(owner.actionPending, isTrue);
      await owner.toggleMaximize();
      await owner.minimize();
      await owner.startDragging();
      expect(original.calls, <String>['query', 'query', 'maximize']);
      effect.complete();
      await pending;
      expect(owner.actionPending, isFalse);
      expect(owner.maximized, isFalse);
      owner.dispose();
    },
  );

  test(
    'an uncertain native action stays held while close remains original',
    () async {
      final _Window original = _Window()
        ..maximizeEffect = () => Future<void>.error(
          StateError('Synthetic effect'),
        );
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      await owner.toggleMaximize();
      expect(owner.actionHeld, isTrue);
      expect(owner.canMinimize, isFalse);
      expect(owner.canToggleMaximize, isFalse);
      await owner.minimize();
      await owner.close();
      expect(original.calls, <String>['query', 'query', 'maximize', 'close']);
      owner.dispose();
    },
  );

  test(
    'close is admitted once even while an original effect is pending',
    () async {
      final Completer<void> effect = Completer<void>();
      final Completer<void> close = Completer<void>();
      final _Window original = _Window()
        ..minimizeEffect = (() => effect.future)
        ..closeEffect = () => close.future;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      final Future<void> pending = owner.minimize();
      final Future<void> closing = owner.close();
      await owner.close();
      expect(owner.closing, isTrue);
      expect(owner.closePending, isTrue);
      expect(original.calls, <String>['query', 'minimize', 'close']);
      close.complete();
      await closing;
      expect(owner.closePending, isFalse);
      expect(owner.canClose, isFalse);
      effect.complete();
      await pending;
      owner.dispose();
    },
  );

  test(
    'external native close is observed without taking shutdown ownership',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      original.listeners.single.onWindowClose();
      expect(owner.closing, isTrue);
      expect(owner.closePending, isFalse);
      await owner.close();
      await owner.minimize();
      expect(original.calls, <String>['query']);
      owner.dispose();
    },
  );

  test(
    'failed close is private and is never replayed as a new close',
    () async {
      final _Window original = _Window()
        ..closeEffect = () => Future<void>.error(StateError('Synthetic close'));
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      await owner.close();
      expect(owner.closeFailed, isTrue);
      expect(owner.canClose, isFalse);
      await owner.close();
      expect(original.calls, <String>['query', 'close']);
      owner.dispose();
    },
  );

  test(
    'disposal during the fresh query prevents its later native effect',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      final Completer<bool> query = Completer<bool>();
      original.query = () => query.future;
      final Future<void> pending = owner.toggleMaximize();
      owner.dispose();
      query.complete(false);
      await pending;
      expect(original.calls, <String>['query', 'query']);
      expect(original.listeners, isEmpty);
    },
  );

  test(
    'disposal retains a late original effect without follow-up traffic',
    () async {
      final Completer<void> effect = Completer<void>();
      final _Window original = _Window()..maximizeEffect = () => effect.future;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      int notifications = 0;
      owner.addListener(() => notifications++);
      await _flush();
      final Future<void> pending = owner.toggleMaximize();
      await _flush();
      owner.dispose();
      final int atDispose = notifications;
      effect.completeError(StateError('Synthetic late effect'));
      await pending;
      expect(notifications, atDispose);
      expect(original.calls, <String>['query', 'query', 'maximize']);
    },
  );

  test(
    'a native mode event observes the original backend without adopting one',
    () async {
      final _Window original = _Window();
      final _Window replacement = _Window()..maximized = true;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      original
        ..maximized = true
        ..listeners.single.onWindowMaximize();
      await _flush();
      expect(owner.maximized, isTrue);
      expect(replacement.calls, isEmpty);
      expect(replacement.listeners, isEmpty);
      owner.dispose();
    },
  );

  test(
    'a mode change during a toggle query prevents a stale native effect',
    () async {
      final _Window original = _Window();
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await _flush();
      final Completer<bool> stale = Completer<bool>();
      original.query = () => stale.future;
      final Future<void> pending = owner.toggleMaximize();
      original
        ..maximized = true
        ..query = null
        ..listeners.single.onWindowMaximize();
      stale.complete(false);
      await pending;
      await _flush();
      expect(original.calls, <String>['query', 'query', 'query']);
      expect(owner.maximized, isTrue);
      owner.dispose();
    },
  );

  test(
    'a mutation during the initial query requires '
    'a later original observation',
    () async {
      final Completer<bool> old = Completer<bool>();
      final _Window original = _Window()..query = () => old.future;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      await owner.minimize();
      original
        ..query = null
        ..maximized = true;
      old.complete(false);
      await _flush();
      expect(original.calls, <String>['query', 'minimize', 'query']);
      expect(owner.maximized, isTrue);
      owner.dispose();
    },
  );

  test(
    'an event during an old query requires a new positive observation',
    () async {
      final Completer<bool> old = Completer<bool>();
      final _Window original = _Window()..query = () => old.future;
      final AppWindowController owner = AppWindowController.forTesting(
        original,
      );
      original
        ..maximized = true
        ..query = null
        ..listeners.single.onWindowMaximize();
      old.complete(false);
      await _flush();
      expect(original.calls, <String>['query', 'query']);
      expect(owner.maximized, isTrue);
      owner.dispose();
    },
  );
}
