import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_binding.dart'
    as production;

/// Existing application preferences. Missing entries retain their old defaults.
enum WalletPreference {
  /// Ordinary automatic receiving remains enabled by default.
  autoReceive('enable_auto_receive', defaultValue: true),

  /// Desktop notifications remain opt-in.
  desktopNotifications('enable_desktop_notifications', defaultValue: false),

  /// Starting with the operating system remains opt-in.
  launchAtStartup('launch_at_startup', defaultValue: false),

  /// Watching copied WalletConnect links remains opt-in.
  clipboard('enable_clipboard_watcher', defaultValue: false);

  const WalletPreference(this.key, {required this.defaultValue});

  /// The existing persisted key, without migration or normalization.
  final String key;

  /// Used only when the original box has no such entry.
  final bool defaultValue;
}

/// A raw original entry; malformed values are retained rather than rewritten.
class WalletStoredPreference {
  /// Distinguishes a missing entry from an explicitly stored null.
  const WalletStoredPreference({required this.exists, this.value});

  /// Whether the original box contains the key.
  final bool exists;

  /// Its exact stored value, including unsupported custom content.
  final Object? value;

  /// A valid choice or the existing default for a genuinely absent entry.
  bool? effective(WalletPreference preference) => !exists
      ? preference.defaultValue
      : switch (value) {
          final bool choice => choice,
          _ => null,
        };
}

/// An original preference backend, injectable without opening a real box.
abstract interface class WalletPreferenceStore {
  /// The actual original Box identity shared by remounted presenters.
  Object get identity;

  /// Reads only the captured backend.
  WalletStoredPreference read(WalletPreference preference);

  /// Returns the original write Future without looking up another backend.
  Future<void> write(WalletPreference preference, {required bool value});
}

/// The original write and effect have separate, retained terminal states.
enum WalletPreferenceStatus {
  /// The captured source left before this write was admitted.
  refused,

  /// The original box write failed.
  saveFailed,

  /// The value was saved but its original effect could not be applied.
  applyFailed,

  /// Both persistence and the original effect completed.
  applied,
}

/// A completed preference action, independent of a widget's lifetime.
class WalletPreferenceOutcome {
  /// Keeps original Futures, values and errors rather than a display exception.
  const WalletPreferenceOutcome({
    required this.preference,
    required this.value,
    required this.status,
    this.write,
    this.effect,
    this.effectResult,
    this.error,
    this.stackTrace,
    this.observerError,
    this.notification,
    this.notificationResult,
  });

  /// The original preference key.
  final WalletPreference preference;

  /// The explicit requested value.
  final bool value;

  /// Persistence and application are never conflated.
  final WalletPreferenceStatus status;

  /// The identical original backend Future, when a write was admitted.
  final Future<void>? write;

  /// The identical original effect Future, when resources still allowed it.
  final Future<Object?>? effect;

  /// The original platform answer, including an explicit false answer.
  final Object? effectResult;

  /// The exact original write or effect error.
  final Object? error;

  /// The original error trace, when available.
  final StackTrace? stackTrace;

  /// Notification failure cannot turn a successful write into a failed one.
  final Object? observerError;

  /// The exact original notification Box Future, when history was admitted.
  final Future<dynamic>? notification;

  /// Its original backend answer, independent of transient display.
  final Object? notificationResult;

  /// A settled successful write remains committed after effect refusal.
  bool get committed =>
      status == WalletPreferenceStatus.applied ||
      status == WalletPreferenceStatus.applyFailed;
}

/// A source captured before admission, with no widget or global lookup inside.
class WalletSettingsBinding {
  /// Pure injected construction never creates a wallet or platform service.
  WalletSettingsBinding({
    required this.store,
    required this._ownsResources,
    required this._apply,
    this._notify,
    this._display,
  }) : _journal = _journals[store.identity] ??= _PreferenceJournal();

  /// Captures the real original preferences and effects without opening boxes.
  static WalletSettingsBinding? capture({
    required Future<void> Function() scanForReceives,
    bool Function()? senderIsCurrent,
  }) => production.captureWalletSettingsBinding(
    scanForReceives: scanForReceives,
    senderIsCurrent: senderIsCurrent,
  );

  /// The captured original backend.
  final WalletPreferenceStore store;
  final bool Function() _ownsResources;
  final Future<Object?> Function(
    WalletPreference, {
    required bool value,
    required bool Function() ownsResources,
  })
  _apply;
  final Future<dynamic> Function(
    WalletPreference, {
    required bool value,
    required bool Function() canDisplay,
  })?
  _notify;
  final void Function(
    WalletPreference, {
    required bool value,
    required bool Function() canDisplay,
  })?
  _display;
  final _PreferenceJournal _journal;
  bool _revoked = false;

  static final Expando<_PreferenceJournal> _journals =
      Expando<_PreferenceJournal>();

  /// Observes all admitted original lanes after a maintenance quarantine.
  /// New writes require their own current resource guard; this never retries.
  static Future<void> pendingForStore(Object original) async {
    final _PreferenceJournal? journal = _journals[original];
    if (journal == null) {
      return;
    }
    final List<Future<WalletPreferenceOutcome>> admitted =
        <Future<WalletPreferenceOutcome>>[
          for (final _PreferenceLane lane in journal.lanes.values)
            for (final _PreferenceOperation operation in lane.queue)
              operation.completion.future,
        ];
    await Future.wait<WalletPreferenceOutcome>(admitted);
  }

  /// Resource ownership ignores route disposal but never revives a replacement.
  bool get ownsResources {
    if (_revoked) return false;
    final bool valid = _ownsResources();
    _revoked = _revoked || !valid;
    return !_revoked;
  }

  /// An immutable archive survives later views and later explicit changes.
  List<WalletPreferenceOutcome> get outcomes =>
      List<WalletPreferenceOutcome>.unmodifiable(_journal.outcomes);

  /// The exact pending operation is shared across remounts of this box and key.
  Future<WalletPreferenceOutcome>? pending(WalletPreference preference) {
    final _PreferenceLane? lane = _journal.lanes[preference];
    return lane == null || lane.queue.isEmpty
        ? null
        : lane.queue.first.completion.future;
  }

  /// Records a choice synchronously before observers can reenter or dispose.
  Future<WalletPreferenceOutcome> change(
    WalletPreference preference, {
    required bool value,
    required bool Function() isCurrent,
  }) {
    final _PreferenceLane lane = _journal.lanes.putIfAbsent(
      preference,
      _PreferenceLane.new,
    );
    final _PreferenceOperation? previous = lane.queue.isEmpty
        ? null
        : lane.queue.last;
    if (previous != null && previous.value == value) {
      return previous.completion.future;
    }
    final _PreferenceOperation operation = _PreferenceOperation(
      this,
      preference,
      isCurrent,
      value: value,
    );
    lane.queue.add(operation);
    _journal.changed();
    if (!lane.running) {
      lane.running = true;
      unawaited(_drain(lane));
    }
    return operation.completion.future;
  }

  Future<void> _drain(_PreferenceLane lane) async {
    while (lane.queue.isNotEmpty) {
      final _PreferenceOperation operation = lane.queue.first;
      final WalletPreferenceOutcome outcome = await operation.binding._run(
        operation,
      );
      _journal.outcomes.add(outcome);
      _journal.latest[operation.preference] = outcome;
      lane.queue.removeAt(0);
      operation.completion.complete(outcome);
      _journal.changed();
    }
    lane.running = false;
  }

  Future<WalletPreferenceOutcome> _run(_PreferenceOperation operation) async {
    Future<void>? write;
    Future<Object?>? effect;
    Object? effectResult;
    Object? error;
    StackTrace? trace;
    Object? observerError;
    Future<dynamic>? notification;
    Object? notificationResult;
    WalletPreferenceStatus status = WalletPreferenceStatus.refused;
    try {
      if (!operation.isCurrent || !ownsResources) {
        return WalletPreferenceOutcome(
          preference: operation.preference,
          value: operation.value,
          status: status,
        );
      }
      status = WalletPreferenceStatus.saveFailed;
      write = store.write(operation.preference, value: operation.value);
      // Once admitted, always observe this original write after view disposal.
      await write;
      status = WalletPreferenceStatus.applyFailed;
      final WalletStoredPreference stored = store.read(operation.preference);
      bool effectOwned() =>
          ownsResources &&
          store.read(operation.preference).exists &&
          store.read(operation.preference).value == operation.value;
      if (ownsResources && stored.exists && stored.value == operation.value) {
        effect = _apply(
          operation.preference,
          value: operation.value,
          ownsResources: effectOwned,
        );
        effectResult = await effect;
        if (effectResult != false && effectOwned()) {
          status = WalletPreferenceStatus.applied;
        }
      }
      bool canDisplay() => operation.isCurrent && ownsResources;
      if (status == WalletPreferenceStatus.applied &&
          canDisplay() &&
          _notify != null) {
        try {
          notification = _notify(
            operation.preference,
            value: operation.value,
            canDisplay: canDisplay,
          );
          notificationResult = await notification;
          if (canDisplay()) {
            _display?.call(
              operation.preference,
              value: operation.value,
              canDisplay: canDisplay,
            );
          }
        } on Object catch (failure) {
          observerError = failure;
        }
      }
    } on Object catch (failure, stack) {
      error = failure;
      trace = stack;
    }
    return WalletPreferenceOutcome(
      preference: operation.preference,
      value: operation.value,
      status: status,
      write: write,
      effect: effect,
      effectResult: effectResult,
      error: error,
      stackTrace: trace,
      observerError: observerError,
      notification: notification,
      notificationResult: notificationResult,
    );
  }
}

class _PreferenceOperation {
  _PreferenceOperation(
    this.binding,
    this.preference,
    this._isCurrent, {
    required this.value,
  });

  final WalletSettingsBinding binding;
  final WalletPreference preference;
  final bool value;
  final bool Function() _isCurrent;
  final Completer<WalletPreferenceOutcome> completion =
      Completer<WalletPreferenceOutcome>();
  bool _revoked = false;

  bool get isCurrent => !_revoked && !(_revoked = !_isCurrent());
}

class _PreferenceLane {
  final List<_PreferenceOperation> queue = <_PreferenceOperation>[];
  bool running = false;
}

class _PreferenceJournal extends ChangeNotifier {
  final Map<WalletPreference, _PreferenceLane> lanes =
      <WalletPreference, _PreferenceLane>{};
  final Map<WalletPreference, WalletPreferenceOutcome> latest =
      <WalletPreference, WalletPreferenceOutcome>{};
  final List<WalletPreferenceOutcome> outcomes = <WalletPreferenceOutcome>[];

  void changed() {
    try {
      notifyListeners();
    } on Object {
      // A display observer cannot replace an original action or its Future.
    }
  }
}

/// Only saved values are painted. Pending choices do not invent a commit.
class WalletSettingsState {
  /// Immutable data from the captured backend and its shared operation lanes.
  WalletSettingsState({
    required Map<WalletPreference, bool?> values,
    required Set<WalletPreference> busy,
    required Map<WalletPreference, WalletPreferenceStatus> failures,
    required this.available,
  }) : values = Map<WalletPreference, bool?>.unmodifiable(values),
       busy = Set<WalletPreference>.unmodifiable(busy),
       failures = Map<WalletPreference, WalletPreferenceStatus>.unmodifiable(
         failures,
       );

  /// Null denotes unsupported stored content, never a false fallback.
  final Map<WalletPreference, bool?> values;

  /// Each original box and key has one serial lane across views.
  final Set<WalletPreference> busy;

  /// Short localized errors are chosen from these stages.
  final Map<WalletPreference, WalletPreferenceStatus> failures;

  /// A missing or replaced backend disables input without opening a new box.
  final bool available;
}

/// A disposable view adapter; its original operations belong to the journal.
class WalletSettingsPresenter extends Cubit<WalletSettingsState> {
  /// Injection never falls back to a wallet, service locator or native plugin.
  WalletSettingsPresenter({required this.binding}) : super(_read(binding)) {
    binding?._journal.addListener(refresh);
  }

  /// Null represents unavailable original resources.
  final WalletSettingsBinding? binding;

  static WalletSettingsState _read(WalletSettingsBinding? binding) {
    final Map<WalletPreference, bool?> values = <WalletPreference, bool?>{};
    final Set<WalletPreference> busy = <WalletPreference>{};
    final Map<WalletPreference, WalletPreferenceStatus> failures =
        <WalletPreference, WalletPreferenceStatus>{};
    bool available = binding?.ownsResources ?? false;
    for (final WalletPreference preference in WalletPreference.values) {
      try {
        values[preference] = available
            ? binding!.store.read(preference).effective(preference)
            : null;
      } on Object {
        values[preference] = null;
        available = false;
      }
      if (binding?.pending(preference) != null) {
        busy.add(preference);
      }
      final WalletPreferenceStatus? status =
          binding?._journal.latest[preference]?.status;
      if (status == WalletPreferenceStatus.saveFailed ||
          status == WalletPreferenceStatus.applyFailed) {
        failures[preference] = status!;
      }
    }
    return WalletSettingsState(
      values: values,
      busy: busy,
      failures: failures,
      available: available,
    );
  }

  /// Repaints retained writes without changing or normalizing the backend.
  void refresh() {
    if (!isClosed) {
      emit(_read(binding));
    }
  }

  /// A captured view authority is checked before this exact choice is written.
  Future<WalletPreferenceOutcome>? change(
    WalletPreference preference, {
    required bool value,
    required bool Function() isCurrent,
  }) {
    if (isClosed || !isCurrent()) {
      return null;
    }
    return binding?.change(preference, value: value, isCurrent: isCurrent);
  }

  @override
  Future<void> close() {
    binding?._journal.removeListener(refresh);
    return super.close();
  }
}
